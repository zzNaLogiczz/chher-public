package com.chhreader.chh_app

import android.content.Context
import android.util.Log
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** One network worker for both periodic jobs and checks requested by Flutter. */
internal class AccountChecker private constructor(private val vault: AccountVault) {
    private val network = Executors.newSingleThreadExecutor()
    private val deadlines = Executors.newSingleThreadScheduledExecutor()

    class Run(private val cancellationExecutor: Executor) {
        @Volatile var cancelled = false
            private set
        private var connection: HttpURLConnection? = null

        fun cancel() {
            val request = synchronized(this) {
                cancelled = true
                connection
            }
            if (request != null) cancellationExecutor.execute { request.disconnect() }
        }

        @Synchronized
        fun attach(request: HttpURLConnection): Boolean {
            if (cancelled) return false
            connection = request
            return true
        }

        @Synchronized
        fun detach() {
            connection = null
        }
    }

    fun check(
        uids: Set<String>? = null,
        force: Boolean = false,
        allowLegacy: Boolean = false,
        finished: (Run, Exception?) -> Unit,
    ): Run {
        val run = Run(deadlines)
        network.execute {
            var failure: Exception? = null
            try {
                if (!run.cancelled) {
                    for (uid in vault.checkTargets(uids, allowLegacy)) {
                        if (run.cancelled) break
                        val input = vault.prepareCheck(uid, force) ?: continue
                        if (run.cancelled) break
                        val result = fetch(input, run)
                        if (run.cancelled) break
                        vault.applyCheck(input, result) { run.cancelled }
                    }
                }
            } catch (error: Exception) {
                failure = error
            } finally {
                finished(run, failure)
            }
        }
        return run
    }

    private fun fetch(input: AccountVault.CheckInput, run: Run): AccountCheck.Result {
        val home = AccountCheck.classify(200, fetchPage(SITE, input.cookieHeader, run), input.uid)
        if (home.state != AccountCheck.State.OK || run.cancelled) return home
        val unread = PmUnread.parse(fetchPage(PM_USERS, input.cookieHeader, run, ajax = true))
        Log.d("AccountChecker", "getpmuser success=${unread != null} count=${unread?.size ?: 0}")
        return home.withUnreadPm(unread)
    }

    private fun fetchPage(url: URL, cookieHeader: String, run: Run, ajax: Boolean = false): String? {
        val request = try { url.openConnection() as HttpURLConnection }
        catch (_: Exception) { return null }
        if (!run.attach(request)) {
            request.disconnect()
            return null
        }
        val expired = AtomicBoolean(false)
        val deadline = deadlines.schedule({
            expired.set(true)
            request.disconnect()
        }, TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
        try {
            request.connectTimeout = TIMEOUT_MS
            request.readTimeout = TIMEOUT_MS
            request.instanceFollowRedirects = false
            request.useCaches = false
            request.requestMethod = "GET"
            if (cookieHeader.isNotEmpty()) request.setRequestProperty("Cookie", cookieHeader)
            if (ajax) {
                request.setRequestProperty("Referer", "https://www.chiphell.com")
                request.setRequestProperty("X-Requested-With", "XMLHttpRequest")
            }
            request.setRequestProperty("Cache-Control", "no-cache")
            // Keep the desktop client hints aligned with the foreground direct fetcher.
            request.setRequestProperty("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36")
            request.setRequestProperty("Accept", "text/html,application/xhtml+xml,*/*;q=0.8")
            request.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9")
            request.setRequestProperty("sec-ch-ua", "\"Chromium\";v=\"155\", \"Not=A?Brand\";v=\"24\"")
            request.setRequestProperty("sec-ch-ua-mobile", "?0")
            request.setRequestProperty("sec-ch-ua-platform", "\"macOS\"")
            if (run.cancelled || request.responseCode != 200 || request.contentLengthLong > MAX_BYTES) {
                return null
            }

            val html = request.inputStream.use { stream ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                var remaining = MAX_BYTES
                while (remaining > 0) {
                    if (run.cancelled || expired.get()) return null
                    val count = stream.read(buffer, 0, minOf(buffer.size, remaining))
                    if (count < 0) break
                    output.write(buffer, 0, count)
                    remaining -= count
                }
                if (remaining == 0 && stream.read() != -1) return null
                output.toString("UTF-8")
            }
            return html.takeUnless { expired.get() || run.cancelled }
        } catch (_: Exception) {
            // Transport failures can carry request headers, so keep them inside this worker.
            return null
        } finally {
            deadline.cancel(false)
            run.detach()
            request.disconnect()
        }
    }

    companion object {
        private val SITE = URL("https://www.chiphell.com/forum.php?mobile=no")
        private val PM_USERS = URL("https://www.chiphell.com/home.php?mod=spacecp&ac=pm&op=getpmuser&inajax=1")
        private const val TIMEOUT_MS = 10_000
        private const val MAX_BYTES = 2 * 1024 * 1024
        private var singleton: AccountChecker? = null

        @Synchronized
        fun get(context: Context): AccountChecker =
            singleton ?: AccountChecker(AccountVault.get(context)).also { singleton = it }
    }
}
