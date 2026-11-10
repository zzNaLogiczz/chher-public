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
    private var permissionResult: MethodChannel.Result? = null
    private var launch = activity.intent?.getBooleanExtra(OPEN_MESSAGES, false) == true

    init {
        activity.intent?.removeExtra(OPEN_MESSAGES)
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "requestPermission" -> requestPermission(result)
                    "show" -> {
                        val uid = call.argument<String>("uid")
                        val notices = call.argument<Int>("notices")
                        val messages = call.argument<Int>("messages")
                        if (uid == null || !uid.matches(Regex("[1-9][0-9]*")) ||
                            notices == null || messages == null || notices < 0 || messages < 0) {
                            result.error("invalid_counts", "无效的未读计数", null)
                        } else {
                            show(activity, uid, notices, messages)
                            result.success(null)
                        }
                    }
                    "clear" -> { clear(activity); result.success(null) }
                    "takeLaunch" -> { result.success(launch); launch = false }
                    "setSession" -> {
                        setSession(activity, call.argument<Boolean>("active") == true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: RuntimeException) {
                result.error("notification_failed", error.javaClass.simpleName, null)
            }
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(enabled(activity)); return
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
        permissionResult?.success(enabled(activity))
        permissionResult = null
        return true
    }

    fun onNewIntent(intent: Intent) {
        if (!intent.getBooleanExtra(OPEN_MESSAGES, false)) return
        intent.removeExtra(OPEN_MESSAGES)
        channel.invokeMethod("openMessages", null)
    }

    fun dispose() {
        permissionResult?.success(false)
        permissionResult = null
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val OPEN_MESSAGES = "chh.openMessages"
        private const val PERMISSION_REQUEST = 4361
        private const val NOTIFICATION_ID = 4362
        private const val JOB_ID = 4363
        private const val CHANNEL_ID = "chh_messages"
        internal fun prefs(context: Context) = context.getSharedPreferences("chh_notifications", Context.MODE_PRIVATE)
        internal fun enabled(context: Context): Boolean {
            if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
            val manager = context.getSystemService(NotificationManager::class.java)
            if (!manager.areNotificationsEnabled()) return false
            if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL_ID)?.importance == NotificationManager.IMPORTANCE_NONE) return false
            return true
        }

        @Synchronized
        internal fun show(context: Context, uid: String, notices: Int, messages: Int) {
            val prefs = prefs(context)
            val manager = context.getSystemService(NotificationManager::class.java)
            val sameUser = prefs.getString("uid", null) == uid
            val oldNotices = if (sameUser) prefs.getInt("notices", 0) else 0
            val oldMessages = if (sameUser) prefs.getInt("messages", 0) else 0
            if (!sameUser) manager.cancel(NOTIFICATION_ID)
            if (notices == 0 && messages == 0) manager.cancel(NOTIFICATION_ID)
            // A denied permission must not consume the first unread alert.
            if (!enabled(context) && (notices > 0 || messages > 0)) return
            val increased = notices > oldNotices || messages > oldMessages
            val changed = notices != oldNotices || messages != oldMessages
            val visible = manager.activeNotifications.any { it.id == NOTIFICATION_ID }
            if (increased || (changed && visible && (notices > 0 || messages > 0))) {
                if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "提醒与私信", NotificationManager.IMPORTANCE_DEFAULT)
                )
                val intent = Intent(context, MainActivity::class.java)
                    .setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra(OPEN_MESSAGES, true)
                val pending = PendingIntent.getActivity(context, NOTIFICATION_ID, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val text = listOfNotNull(
                    if (notices > 0) "$notices 条未读提醒" else null,
                    if (messages > 0) "$messages 条未读私信" else null,
                ).joinToString("，")
                @Suppress("DEPRECATION")
                val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL_ID) else Notification.Builder(context)
                manager.notify(NOTIFICATION_ID, builder
                    .setSmallIcon(R.drawable.ic_notification)
                    .setContentTitle("新消息")
                    .setContentText(text)
                    .setContentIntent(pending)
                    .setAutoCancel(true)
                    .setOnlyAlertOnce(!increased)
                    .setDefaults(Notification.DEFAULT_ALL)
                    .setVisibility(Notification.VISIBILITY_PRIVATE)
                    .setCategory(Notification.CATEGORY_MESSAGE)
                    .build())
            }
            prefs.edit().putString("uid", uid).putInt("notices", notices).putInt("messages", messages)
                .putLong("header_revision", prefs.getLong("header_revision", 0) + 1).apply()
        }

        @Synchronized
        internal fun clear(context: Context) {
            context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
            prefs(context).edit().remove("uid").remove("notices").remove("messages").apply()
        }

        internal fun setSession(context: Context, active: Boolean) {
            val scheduler = context.getSystemService(JobScheduler::class.java)
            val prefs = prefs(context)
            val revision = prefs.getLong("session_revision", 0)
            prefs.edit().putBoolean("active", active)
                .putLong("session_revision", if (active) revision else revision + 1).apply()
            if (!active) {
                scheduler.cancel(JOB_ID)
                clear(context)
            } else if (scheduler.getPendingJob(JOB_ID) == null) {
                scheduler.schedule(JobInfo.Builder(JOB_ID, ComponentName(context, MessageCheckService::class.java))
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                    .setPeriodic(15 * 60 * 1000L)
                    .build())
            }
        }
    }
}
