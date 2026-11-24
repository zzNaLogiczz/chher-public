package com.chhreader.chh_app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.WebStorage
import androidx.webkit.CookieManagerCompat
import androidx.webkit.WebViewFeature
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask

/** Call vault operations via [submit] or from a background thread only. */
internal class AccountVault private constructor(private val context: Context) {
    // No extra encryption: the app sandbox gives this the same protection as WebView's cookie store.
    private val file by lazy { File(context.noBackupFilesDir, "accounts/vault-v1.json") }
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var lastSnapshotAt = 0L
    val listeners = CopyOnWriteArraySet<() -> Unit>()

    internal class Failure(val code: String) : RuntimeException()

    fun submit(operation: () -> Unit) = worker.execute(operation)

    fun list(): Map<String, Any?> = backgroundOperation { summary(read()) }

    fun capture(uid: String, name: String, notices: Int?, messages: Int?, observed: Boolean): Map<String, Any?> = backgroundOperation {
        val vault = read()
        requireNoPendingLogin(vault)
        val prior = find(vault, uid)
        val priorAuth = prior?.snapshotAuth()
        val adopting = vault.uid("currentUid") == null
        captureInto(vault, liveCookies(), uid, name, notices, messages, observed)
        write(vault)
        publishAccounts(vault)
        if (observed) {
            val relogin = prior != null && (adopting || priorAuth != prior.snapshotAuth())
            runCatching { NotificationBridge.recovered(context, uid, resetUnread = relogin) }
        }
        changed(vault)
    }

    fun activate(uid: String): Map<String, Any?> = backgroundOperation {
        val vault = read()
        requireNoPendingLogin(vault)
        val account = find(vault, uid) ?: throw Failure("account_not_found")
        val now = System.currentTimeMillis()
        val target = usableCookies(account, now)
        if (AccountCookies.inferPrefix(target) != account.getString("prefix")) {
            val wasExpired = account.isExpired()
            markExpiredInto(account, now)
            write(vault)
            notifyExpired(account, wasExpired)
            changed(vault)
            throw Failure("account_expired")
        }
        swapCookies(vault, liveCookies(), target) {
            account.put("lastUsedAt", now)
            vault.put("currentUid", uid)
            write(vault)
        }
        changed(vault)
    }

    fun remove(uid: String): Map<String, Any?> = backgroundOperation {
        val vault = read()
        requireNoPendingLogin(vault)
        val accounts = vault.getJSONArray("accounts")
        val index = accounts.objects().indexOfFirst { it.getString("uid") == uid }
        if (index < 0) return@backgroundOperation summary(vault)
        accounts.remove(index)
        if (vault.uid("currentUid") == uid) vault.put("currentUid", JSONObject.NULL)
        write(vault)
        runCatching { NotificationBridge.removeAccount(context, uid) }
        publishAccounts(vault)
        changed(vault)
    }

    fun markExpired(uid: String): Map<String, Any?> = backgroundOperation {
        val vault = read()
        requireNoPendingLogin(vault)
        val account = find(vault, uid) ?: return@backgroundOperation summary(vault)
        if (vault.uid("currentUid") != uid) return@backgroundOperation summary(vault)
        val wasExpired = account.isExpired()
        markExpiredInto(account, System.currentTimeMillis())
        write(vault)
        notifyExpired(account, wasExpired)
        changed(vault)
    }

    fun beginLogin(targetUid: String?): Map<String, Any?> = backgroundOperation {
        val vault = read()
        requireNoPendingLogin(vault)
        val count = vault.getJSONArray("accounts").length()
        if (targetUid == null && count >= MAX) throw Failure("account_limit")
        if (targetUid != null && find(vault, targetUid) == null) throw Failure("account_not_found")

        val live = liveCookies()
        val previousUid = vault.uid("currentUid")
        val previous = previousUid?.let { find(vault, it) }
        val now = System.currentTimeMillis()
        if (AccountCookies.inferPrefix(freshCookies(live, now)) != null) {
            if (previous == null) throw Failure("identity_required")
            captureInto(vault, live, previous.getString("uid"), previous.getString("name"))
        } else if (previous == null && AccountCookies.hasAuth(accountCookies(vault, live))) {
            throw Failure("identity_required")
        }

        // Persist the recovery marker before modifying the separate WebView cookie store.
        vault.put("pendingLogin", JSONObject()
            .put("previousUid", previousUid ?: JSONObject.NULL)
            .put("startedAt", System.currentTimeMillis()))
        write(vault)
        swapCookies(vault, live, emptyList(), afterRollback = {
            vault.put("pendingLogin", JSONObject.NULL)
            write(vault)
        }) {}
        changed(vault)
    }

    fun peekAuth(): Boolean = backgroundOperation {
        AccountCookies.hasAuth(liveCookies().values)
    }

    fun endLogin(restore: Boolean): Map<String, Any?> = backgroundOperation {
        val vault = read()
        val pending = vault.optJSONObject("pendingLogin") ?: throw Failure("login_not_pending")
        val live = liveCookies()
        if (restore) {
            restorePrevious(vault, pending, live)
        } else {
            if (AccountCookies.inferPrefix(freshCookies(live, System.currentTimeMillis())) == null) {
                throw Failure("invalid_credentials")
            }
            CookieManager.getInstance().flush()
            finishLogin(vault, null)
        }
        changed(vault)
    }

    fun recover(): Map<String, Any?> = backgroundOperation {
        val vault = read()
        val pending = vault.optJSONObject("pendingLogin") ?: return@backgroundOperation summary(vault)
        val live = liveCookies()
        if (AccountCookies.hasAuth(live.values)) {
            val previous = pending.uid("previousUid")?.let { find(vault, it) }
            val sameAuth = previous?.let {
                val prefix = it.getString("prefix")
                val auth = AccountCookies.authValue(live.values, prefix)
                auth != null && auth == AccountCookies.authValue(it.cookies(), prefix)
            } == true
            CookieManager.getInstance().flush()
            finishLogin(vault, if (sameAuth) pending.uid("previousUid") else null)
        } else {
            restorePrevious(vault, pending, live)
        }
        changed(vault)
    }

    fun calibrateNotifications() = backgroundOperation {
        val vault = read()
        publishAccounts(vault)
        if (vault.getJSONArray("accounts").objects().any { it.has("notified") }) write(vault)
    }

    // This ticket holds credentials within the native checker only.
    class CheckInput(
        val uid: String?,
        val cookieHeader: String,
        val current: Boolean,
        val attemptAt: Long,
        val savedAt: Long,
        val snapshotAuth: String?,
        val liveAuth: Map<String, String>,
        val foregroundRevision: Long,
    )

    fun checkTargets(uids: Set<String>?, allowLegacy: Boolean): List<String?> = backgroundOperation {
        val vault = read()
        publishAccounts(vault, calibrateJob = false)
        val accounts = vault.getJSONArray("accounts").objects()
        if (accounts.isEmpty() && allowLegacy) return@backgroundOperation listOf(null)
        val current = vault.uid("currentUid")
        accounts.map { it.getString("uid") }
            .filter { uids == null || it in uids }
            .sortedBy { it != current }
    }

    fun prepareCheck(uid: String?, force: Boolean): CheckInput? = backgroundOperation {
        val vault = read()
        val pending = vault.optJSONObject("pendingLogin") != null
        if (uid == null) {
            if (pending || vault.getJSONArray("accounts").length() > 0) return@backgroundOperation null
            val live = readCookieHeader()
            if (!AccountCookies.hasAuth(AccountCookies.normalize(live))) return@backgroundOperation null
            return@backgroundOperation CheckInput(null, live, true, System.currentTimeMillis(), 0, null, emptyMap(),
                NotificationBridge.foregroundRevision(null))
        }
        val account = find(vault, uid) ?: return@backgroundOperation null
        val current = vault.uid("currentUid") == uid
        if (current && pending) return@backgroundOperation null
        val now = System.currentTimeMillis()
        val status = account.getJSONObject("status")
        if (!force && !AccountCheck.isDue(current, status.getLong("attemptAt"),
                status.getInt("failures"), now)) return@backgroundOperation null

        val live = readCookieHeader()
        val liveCookies = AccountCookies.normalize(live)
        val header = if (current) live else {
            val accountCookies = AccountCookies.accountCookies(liveCookies, accountPrefixes(vault)).toSet()
            (usableCookies(account, now) + liveCookies.filterNot { it in accountCookies })
                .joinToString("; ") { it.substringBefore(';').trim() }
        }
        CheckInput(uid, header, current, now, account.getLong("savedAt"), account.snapshotAuth(),
            if (current) liveAuth(vault, liveCookies) else emptyMap(),
            NotificationBridge.foregroundRevision(uid))
    }

    fun applyCheck(input: CheckInput, result: AccountCheck.Result, cancelled: () -> Boolean) = backgroundOperation {
        if (cancelled()) return@backgroundOperation
        val vault = read()
        val uid = input.uid
        if (uid == null) {
            if (result.state == AccountCheck.State.OK && vault.getJSONArray("accounts").length() == 0 &&
                vault.optJSONObject("pendingLogin") == null && readCookieHeader() == input.cookieHeader && !cancelled()) {
                runCatching { NotificationBridge.showChecked(context, result.uid, result.notices, result.messages,
                    result.pmHasCount, input.foregroundRevision, legacy = true) }
            }
            return@backgroundOperation
        }
        val account = find(vault, uid) ?: return@backgroundOperation
        if (account.getLong("savedAt") != input.savedAt || account.snapshotAuth() != input.snapshotAuth) return@backgroundOperation
        if ((vault.uid("currentUid") == uid) != input.current) return@backgroundOperation
        if (input.current && (vault.optJSONObject("pendingLogin") != null ||
                liveAuth(vault, AccountCookies.normalize(readCookieHeader())) != input.liveAuth)) {
            return@backgroundOperation
        }
        if (cancelled()) return@backgroundOperation

        val now = System.currentTimeMillis()
        val wasExpired = account.isExpired()
        val status = account.getJSONObject("status").put("attemptAt", input.attemptAt)
        when (result.state) {
            AccountCheck.State.OK -> status.put("state", "ok").put("checkedAt", now)
                .put("notices", result.notices).put("messages", result.messages).put("failures", 0)
            AccountCheck.State.EXPIRED -> {
                markExpiredInto(account, now)
                status.put("failures", 0)
            }
            AccountCheck.State.FAILED -> status.put("failures", (status.getInt("failures").toLong() + 1)
                .coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
        }
        write(vault)
        changed(vault)
        when (result.state) {
            AccountCheck.State.OK -> runCatching {
                if (wasExpired) NotificationBridge.recovered(context, uid, resetUnread = false)
                NotificationBridge.showChecked(context, uid, result.notices, result.messages,
                    result.pmHasCount, input.foregroundRevision, legacy = false)
            }
            AccountCheck.State.EXPIRED -> notifyExpired(account, wasExpired)
            AccountCheck.State.FAILED -> Unit
        }
        Unit
    }

    private fun publishAccounts(vault: JSONObject, calibrateJob: Boolean = true) {
        val names = vault.getJSONArray("accounts").objects()
            .associate { it.getString("uid") to it.getString("name") }
        runCatching { NotificationBridge.publishAccounts(context, names, calibrateJob) }
    }

    private fun notifyExpired(account: JSONObject, wasExpired: Boolean) {
        runCatching { NotificationBridge.expired(context, account.getString("uid"), account.getString("name"), wasExpired) }
    }

    private fun JSONObject.isExpired(): Boolean = getJSONObject("status").getString("state") == "expired"

    private fun JSONObject.snapshotAuth(): String? = AccountCookies.authValue(cookies(), getString("prefix"))

    private fun liveAuth(vault: JSONObject, cookies: List<String>): Map<String, String> =
        AccountCookies.accountCookies(cookies, accountPrefixes(vault)).mapNotNull {
            val name = AccountCookies.name(it)
            if (!AccountCookies.isCredential(name, "auth")) return@mapNotNull null
            AccountCookies.authValue(cookies, name.removeSuffix("auth"))?.let { value -> name to value }
        }.toMap()

    private inline fun <T> backgroundOperation(operation: () -> T): T {
        // Check before taking the lock: its owner may be waiting for the main Looper.
        if (Looper.myLooper() == Looper.getMainLooper()) throw Failure("main_thread")
        return synchronized(this, operation)
    }

    private fun restorePrevious(vault: JSONObject, pending: JSONObject, live: LiveCookies) {
        val previousUid = pending.uid("previousUid")
        val previous = previousUid?.let { find(vault, it) }
        val now = System.currentTimeMillis()
        val target = previous?.let { usableCookies(it, now) }.orEmpty()
        val canRestore = previous != null &&
            AccountCookies.inferPrefix(target) == previous.getString("prefix")
        val wasExpired = previous?.isExpired() == true
        swapCookies(vault, live, if (canRestore) target else emptyList()) {
            if (canRestore) {
                previous.put("lastUsedAt", now)
            } else if (previous != null) {
                markExpiredInto(previous, now)
            }
            finishLogin(vault, if (canRestore) previousUid else null)
        }
        if (!canRestore && previous != null) notifyExpired(previous, wasExpired)
    }

    private fun finishLogin(vault: JSONObject, uid: String?) {
        vault.put("currentUid", uid ?: JSONObject.NULL)
        vault.put("pendingLogin", JSONObject.NULL)
        write(vault)
    }

    private fun markExpiredInto(account: JSONObject, now: Long) {
        account.getJSONObject("status").put("state", "expired").put("checkedAt", now)
    }

    private fun captureInto(
        vault: JSONObject, live: LiveCookies, uid: String, name: String,
        notices: Int? = null, messages: Int? = null, observed: Boolean = false,
    ) {
        val saved = find(vault, uid)
        val accounts = vault.getJSONArray("accounts")
        if (saved == null && accounts.length() >= MAX) throw Failure("account_limit")
        val now = System.currentTimeMillis()
        val cookies = freshCookies(live, now)
        val prefix = AccountCookies.inferPrefix(cookies) ?: throw Failure("invalid_credentials")
        // A replacement in the same clock tick still invalidates a check ticket.
        lastSnapshotAt = maxOf(now, lastSnapshotAt + 1, (saved?.getLong("savedAt") ?: 0) + 1)
        val account = saved ?: JSONObject().put("uid", uid)
            .put("status", JSONObject().put("state", "unknown").put("checkedAt", 0)
                .put("attemptAt", 0).put("failures", 0).put("notices", 0).put("messages", 0))
        account.put("name", name)
            .put("prefix", prefix)
            .put("cookies", JSONArray(cookies.filter { AccountCookies.name(it).startsWith(prefix) }))
            .put("savedAt", lastSnapshotAt)
        if (saved == null || vault.uid("currentUid") != uid) account.put("lastUsedAt", now)
        val status = account.getJSONObject("status")
        if (observed) {
            status.put("state", "ok").put("checkedAt", now).put("failures", 0)
        }
        if (notices != null) status.put("notices", notices)
        if (messages != null) status.put("messages", messages)
        if (saved == null) accounts.put(account)
        vault.put("currentUid", uid)
    }

    private fun usableCookies(account: JSONObject, now: Long): List<String> =
        account.cookies().filterNot { AccountCookies.isExpired(it, account.getLong("savedAt"), now) }

    private data class LiveCookies(val hasInfo: Boolean, val values: List<String>)

    private fun freshCookies(live: LiveCookies, now: Long): List<String> =
        live.values.filterNot { AccountCookies.isExpired(it, now, now) }

    private fun liveCookies(): LiveCookies = onMain {
        val manager = CookieManager.getInstance()
        val hasInfo = WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO)
        val cookies = if (hasInfo) CookieManagerCompat.getCookieInfo(manager, URL)
            else AccountCookies.normalize(manager.getCookie(URL))
        LiveCookies(hasInfo, cookies)
    }

    private fun accountCookies(vault: JSONObject, live: LiveCookies): List<String> =
        AccountCookies.accountCookies(live.values, accountPrefixes(vault))

    private fun accountPrefixes(vault: JSONObject): List<String> =
        vault.getJSONArray("accounts").objects().map { it.getString("prefix") }

    private fun readCookieHeader(): String = onMain { CookieManager.getInstance().getCookie(URL).orEmpty() }

    private fun swapCookies(
        vault: JSONObject,
        before: LiveCookies,
        target: List<String>,
        afterRollback: () -> Unit = {},
        commit: () -> Unit,
    ) {
        val previous = accountCookies(vault, before)
        try {
            replaceCookies(before.hasInfo, previous, target)
            commit()
        } catch (error: Exception) {
            try {
                val partial = liveCookies()
                replaceCookies(partial.hasInfo, accountCookies(vault, partial), previous)
                afterRollback()
            } catch (_: Exception) {
                throw Failure("cookie_update_failed")
            }
            throw error
        }
    }

    private fun replaceCookies(hasInfo: Boolean, existing: List<String>, target: List<String>) {
        for (raw in existing.flatMap { AccountCookies.deletions(it, hasInfo) }.distinct()) {
            setCookie(raw)
        }
        onMain { WebStorage.getInstance().deleteAllData() }
        target.forEach(::setCookie)
        CookieManager.getInstance().flush()
    }

    private fun setCookie(raw: String) {
        // Ask from the main Looper so WebView delivers the callback there. Only the worker waits.
        val result = CompletableFuture<Boolean>()
        onMain { CookieManager.getInstance().setCookie(URL, raw) { result.complete(it) } }
        if (!result.get()) throw Failure("cookie_update_failed")
    }

    private fun <T> onMain(operation: () -> T): T {
        val task = FutureTask { operation() }
        if (!main.post(task)) throw Failure("cookie_update_failed")
        return task.get()
    }

    private fun requireNoPendingLogin(vault: JSONObject) {
        if (vault.optJSONObject("pendingLogin") != null) throw Failure("login_pending")
    }

    private fun read(): JSONObject {
        if (!file.exists()) return JSONObject().put("version", 1)
            .put("currentUid", JSONObject.NULL).put("pendingLogin", JSONObject.NULL)
            .put("accounts", JSONArray())
        return JSONObject(file.readText()).also {
            if (it.getInt("version") != 1) throw Failure("vault_unavailable")
        }
    }

    private fun write(vault: JSONObject) {
        vault.getJSONArray("accounts").objects().forEach { it.remove("notified") }
        val directory = file.parentFile ?: throw Failure("vault_unavailable")
        if (!directory.isDirectory && !directory.mkdirs()) throw Failure("vault_unavailable")
        val temporary = File(directory, "vault-v1.tmp")
        try {
            FileOutputStream(temporary).use {
                it.write(vault.toString().toByteArray(Charsets.UTF_8))
                it.fd.sync()
            }
            Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING)
        } finally {
            temporary.delete()
        }
    }

    private fun find(vault: JSONObject, uid: String): JSONObject? =
        vault.getJSONArray("accounts").objects().firstOrNull { it.getString("uid") == uid }

    private fun JSONObject.uid(key: String): String? = if (isNull(key)) null else getString(key)

    private fun JSONObject.cookies(): List<String> =
        getJSONArray("cookies").let { raw -> List(raw.length()) { raw.getString(it) } }

    private fun JSONArray.objects(): List<JSONObject> = List(length()) { getJSONObject(it) }

    private fun changed(vault: JSONObject): Map<String, Any?> {
        main.post { listeners.forEach { it() } }
        return summary(vault)
    }

    private fun summary(vault: JSONObject): Map<String, Any?> = mapOf(
        "currentUid" to vault.uid("currentUid"),
        "max" to MAX,
        "accounts" to vault.getJSONArray("accounts").objects().map { account ->
            val status = account.getJSONObject("status")
            mapOf(
                "uid" to account.getString("uid"),
                "name" to account.getString("name"),
                "state" to status.getString("state"),
                "checkedAt" to status.getLong("checkedAt"),
                "notices" to status.getInt("notices"),
                "messages" to status.getInt("messages"),
                "lastUsedAt" to account.getLong("lastUsedAt"),
                "failures" to status.getInt("failures"),
            )
        },
    )

    companion object {
        private const val URL = "https://www.chiphell.com"
        private const val MAX = 5
        private var singleton: AccountVault? = null

        @Synchronized
        fun get(context: Context): AccountVault =
            singleton ?: AccountVault(context.applicationContext).also { singleton = it }
    }
}
