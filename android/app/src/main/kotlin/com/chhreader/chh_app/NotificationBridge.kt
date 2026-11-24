package com.chhreader.chh_app

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

internal class NotificationBridge(private val activity: Activity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "chh/notifications")
    private val vault = AccountVault.get(activity)
    private var permissionResult: MethodChannel.Result? = null
    private var launch = takeAction(activity.intent)
    private var launchTaken = false

    init {
        refreshCatalog()
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "requestPermission" -> requestPermission(result)
                    "show" -> {
                        val uid = call.argument<String>("uid")
                        val notices = call.argument<Int>("notices")
                        val messages = call.argument<Int>("messages")
                        val pmHasCount = call.argument<Boolean>("pmHasCount") ?: true
                        if (uid == null || !uid.matches(UID) ||
                            notices == null || messages == null || notices < 0 || messages < 0) {
                            result.error("invalid_counts", "无效的未读计数", null)
                        } else {
                            show(activity, uid, notices, messages, pmHasCount)
                            result.success(null)
                        }
                    }
                    "takeLaunch" -> {
                        launchTaken = true
                        result.success(launch)
                        launch = null
                    }
                    "setSession" -> {
                        refreshCatalog()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: RuntimeException) {
                result.error("notification_failed", error.javaClass.simpleName, null)
            }
        }
    }

    private fun refreshCatalog() {
        vault.submit {
            runCatching { vault.calibrateNotifications() }
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(enabled(activity, MESSAGES_CHANNEL)); return
        }
        if (permissionResult != null || prefs(activity).getBoolean("asked", false)) {
            result.success(false); return
        }
        prefs(activity).edit().putBoolean("asked", true).apply()
        permissionResult = result
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        permissionResult?.success(enabled(activity, MESSAGES_CHANNEL))
        permissionResult = null
        return true
    }

    fun onNewIntent(intent: Intent) {
        val action = takeAction(intent) ?: return
        // The Dart handler may not be installed when another intent arrives during startup.
        if (launchTaken) channel.invokeMethod("openNotification", action) else launch = action
    }

    fun dispose() {
        permissionResult?.success(false)
        permissionResult = null
        channel.setMethodCallHandler(null)
    }

    companion object {
        private const val OPEN_MESSAGES = "chh.openMessages"
        private const val ACCOUNT_UID = "chh.accountUid"
        private const val RELOGIN_UID = "chh.reloginUid"
        private const val PERMISSION_REQUEST = 4361
        private const val MESSAGE_ID = 4362
        private const val JOB_ID = 4363
        private const val EXPIRY_ID = 4364
        private const val MESSAGES_CHANNEL = "chh_messages"
        private const val ACCOUNTS_CHANNEL = "chh_accounts"
        private val UID = Regex("[1-9][0-9]*")

        private var accountNames: Map<String, String> = emptyMap()
        private val removedUids = mutableSetOf<String>()
        private var foregroundSequence = 0L
        private val foregroundByUid = mutableMapOf<String, Long>()

        private fun prefs(context: Context) =
            context.getSharedPreferences("chh_notifications", Context.MODE_PRIVATE)

        private fun accountKey(uid: String, field: String) = "account.$uid.$field"

        private fun takeAction(intent: Intent?): Map<String, String?>? {
            if (intent == null) return null
            val reloginUid = intent.getStringExtra(RELOGIN_UID)
            val opensMessages = intent.getBooleanExtra(OPEN_MESSAGES, false)
            val accountUid = intent.getStringExtra(ACCOUNT_UID)
            intent.removeExtra(RELOGIN_UID)
            intent.removeExtra(OPEN_MESSAGES)
            intent.removeExtra(ACCOUNT_UID)
            return when {
                reloginUid?.matches(UID) == true -> mapOf("action" to "relogin", "uid" to reloginUid)
                opensMessages && (accountUid == null || accountUid.matches(UID)) ->
                    mapOf("action" to "messages", "uid" to accountUid)
                else -> null
            }
        }

        private fun enabled(context: Context, channel: String): Boolean {
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                return false
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            return manager.areNotificationsEnabled() &&
                manager.getNotificationChannel(channel)?.importance != NotificationManager.IMPORTANCE_NONE
        }

        @Synchronized
        internal fun publishAccounts(context: Context, names: Map<String, String>, calibrateJob: Boolean = true) {
            accountNames = names
            removedUids.removeAll(names.keys)
            migrate(context)
            if (!calibrateJob) return
            val scheduler = context.getSystemService(JobScheduler::class.java)
            val pending = scheduler.getPendingJob(JOB_ID)
            if (names.isEmpty()) {
                if (pending != null) scheduler.cancel(JOB_ID)
            } else if (pending == null) {
                scheduler.schedule(JobInfo.Builder(JOB_ID, ComponentName(context, MessageCheckService::class.java))
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                    .setPeriodic(15 * 60 * 1000L)
                    .build())
            }
        }

        private fun migrate(context: Context) {
            val prefs = prefs(context)
            if (prefs.getBoolean("account_notifications_migrated", false)) return
            val edit = prefs.edit()
            val uid = prefs.getString("uid", null)
            if (uid?.matches(UID) == true) {
                edit.putInt(accountKey(uid, "notices"), prefs.getInt("notices", 0))
                    .putInt(accountKey(uid, "messages"), prefs.getInt("messages", 0))
            }
            context.getSystemService(NotificationManager::class.java).cancel(MESSAGE_ID)
            edit.remove("uid").remove("notices").remove("messages")
                .remove("active").remove("session_revision").remove("header_revision")
                .putBoolean("account_notifications_migrated", true).apply()
        }

        @Synchronized
        internal fun foregroundRevision(uid: String?): Long =
            if (uid == null) foregroundSequence else foregroundByUid[uid] ?: 0

        @Synchronized
        internal fun show(context: Context, uid: String, notices: Int, messages: Int, pmHasCount: Boolean) {
            if (uid in removedUids) return
            foregroundByUid[uid] = ++foregroundSequence
            showMessages(context, uid, notices, messages, pmHasCount)
        }

        @Synchronized
        internal fun showChecked(
            context: Context, uid: String, notices: Int, messages: Int,
            pmHasCount: Boolean, expectedForegroundRevision: Long, legacy: Boolean,
        ) {
            if (uid in removedUids || foregroundRevision(if (legacy) null else uid) != expectedForegroundRevision) return
            showMessages(context, uid, notices, messages, pmHasCount)
        }

        private fun showMessages(context: Context, uid: String, notices: Int, messages: Int, pmHasCount: Boolean) {
            migrate(context)
            val prefs = prefs(context)
            val manager = context.getSystemService(NotificationManager::class.java)
            val noticesKey = accountKey(uid, "notices")
            val messagesKey = accountKey(uid, "messages")
            val pmHasCountKey = accountKey(uid, "pmHasCount")
            val oldNotices = prefs.getInt(noticesKey, 0)
            val oldMessages = prefs.getInt(messagesKey, 0)
            if (notices == 0 && messages == 0) {
                manager.cancel(uid, MESSAGE_ID)
            } else {
                // A denied permission must not consume the first unread alert.
                if (!enabled(context, MESSAGES_CHANNEL)) return
                val increases = AccountNotificationPolicy.unreadIncreased(oldNotices, oldMessages, notices, messages)
                val pmTextChanged = messages > 0 && prefs.getBoolean(pmHasCountKey, !pmHasCount) != pmHasCount
                val update = (notices != oldNotices || messages != oldMessages || pmTextChanged) &&
                    manager.activeNotifications.any { it.tag == uid && it.id == MESSAGE_ID }
                if (increases || update) {
                    manager.createNotificationChannel(
                        NotificationChannel(MESSAGES_CHANNEL, "提醒与私信", NotificationManager.IMPORTANCE_DEFAULT)
                    )
                    val name = accountNames[uid]
                    val title = if (accountNames.size >= 2 && name != null) "$name · 新消息" else "新消息"
                    val text = AccountNotificationPolicy.messageText(notices, messages, pmHasCount)
                    val notification = builder(context, uid, MESSAGE_ID, "messages", MESSAGES_CHANNEL)
                        .setContentTitle(title)
                        .setContentText(text)
                        .setOnlyAlertOnce(!increases)
                        .setCategory(Notification.CATEGORY_MESSAGE)
                        .build()
                    try {
                        manager.notify(uid, MESSAGE_ID, notification)
                    } catch (_: SecurityException) {
                        return
                    }
                }
            }
            prefs.edit().putInt(noticesKey, notices).putInt(messagesKey, messages)
                .putBoolean(pmHasCountKey, pmHasCount).apply()
        }

        @Synchronized
        internal fun expired(context: Context, uid: String, name: String, wasExpired: Boolean) {
            migrate(context)
            val prefs = prefs(context)
            val key = accountKey(uid, "expired")
            if (!AccountNotificationPolicy.enteredExpired(wasExpired, true, prefs.getBoolean(key, false)) ||
                !enabled(context, ACCOUNTS_CHANNEL)) return
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(ACCOUNTS_CHANNEL, "账号状态", NotificationManager.IMPORTANCE_DEFAULT)
            )
            val notification = builder(context, uid, EXPIRY_ID, "relogin", ACCOUNTS_CHANNEL)
                .setContentTitle("$name 登录已失效")
                .setContentText("点按重新登录")
                .setCategory(Notification.CATEGORY_STATUS)
                .build()
            try {
                manager.notify(uid, EXPIRY_ID, notification)
            } catch (_: SecurityException) {
                return
            }
            prefs.edit().putBoolean(key, true).apply()
        }

        @Synchronized
        internal fun recovered(context: Context, uid: String, resetUnread: Boolean) {
            migrate(context)
            context.getSystemService(NotificationManager::class.java).cancel(uid, EXPIRY_ID)
            val edit = prefs(context).edit().remove(accountKey(uid, "expired"))
            if (resetUnread) edit.remove(accountKey(uid, "notices")).remove(accountKey(uid, "messages"))
                .remove(accountKey(uid, "pmHasCount"))
            edit.apply()
        }

        @Synchronized
        internal fun removeAccount(context: Context, uid: String) {
            migrate(context)
            removedUids.add(uid)
            foregroundByUid.remove(uid)
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.cancel(uid, MESSAGE_ID)
            manager.cancel(uid, EXPIRY_ID)
            prefs(context).edit()
                .remove(accountKey(uid, "notices")).remove(accountKey(uid, "messages")).remove(accountKey(uid, "expired"))
                .remove(accountKey(uid, "pmHasCount"))
                .apply()
        }

        private fun builder(context: Context, uid: String, id: Int, action: String, channel: String): Notification.Builder {
            // A unique action separates PendingIntents without triggering Flutter deep links.
            val intent = Intent(context, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .setAction("${context.packageName}.notification.$action.$uid")
            if (action == "messages") intent.putExtra(OPEN_MESSAGES, true).putExtra(ACCOUNT_UID, uid)
            else intent.putExtra(RELOGIN_UID, uid)
            val pending = PendingIntent.getActivity(context, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            return Notification.Builder(context, channel)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentIntent(pending)
                .setAutoCancel(true)
                .setDefaults(Notification.DEFAULT_ALL)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
        }
    }
}
