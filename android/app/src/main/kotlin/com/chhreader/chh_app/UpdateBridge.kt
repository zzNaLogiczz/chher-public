package com.chhreader.chh_app

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * 应用内更新的原生部分：读取本机版本、验证服务器签名、核对安装包、交给系统安装器。
 * 下载在 Dart 侧完成；这里不联网，只处理本地文件和系统接口。
 */
internal class UpdateBridge(
    private val activity: Activity,
    engine: FlutterEngine,
) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "chh/update")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val statusAction = "${activity.packageName}.UPDATE_INSTALL_STATUS"
    private var receiverRegistered = false

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
            if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                // 首次自更新、或系统要求确认时，弹出系统安装确认页
                val confirm = confirmIntent(intent) ?: return report("failed", "confirm_missing")
                try {
                    activity.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    report("pending_user_action", null)
                } catch (error: RuntimeException) {
                    report("failed", error.javaClass.simpleName)
                }
                return
            }
            val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
            report(if (status == PackageInstaller.STATUS_SUCCESS) "success" else "failed", message ?: "status_$status")
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "appInfo" -> result.success(appInfo())
                    "verifySignature" -> result.success(
                        UpdateSignature.verify(
                            call.argument<ByteArray>("publicKey"),
                            call.argument<ByteArray>("payload"),
                            call.argument<ByteArray>("signature"),
                        ),
                    )
                    "inspectApk" -> inspectApk(call.argument<String>("path")!!, result)
                    "canInstall" -> result.success(canInstall())
                    "openInstallPermission" -> result.success(openInstallPermission())
                    "install" -> install(call.argument<String>("path")!!, result)
                    else -> result.notImplemented()
                }
            } catch (error: RuntimeException) {
                result.error("update_failed", error.javaClass.simpleName, null)
            }
        }
    }

    private fun appInfo(): Map<String, Any?> {
        val info = packageInfo(activity.packageName, 0)
        return mapOf(
            "packageName" to activity.packageName,
            "versionCode" to versionCodeOf(info),
            "versionName" to info.versionName,
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "sdkInt" to Build.VERSION.SDK_INT,
            "filesDir" to activity.filesDir.absolutePath,
        )
    }

    /** 在后台线程计算 sha256 并读取安装包信息；结果用于安装前的最后一道核对。 */
    private fun inspectApk(path: String, result: MethodChannel.Result) {
        worker.execute {
            val outcome = try {
                val file = File(path)
                val archive = archiveInfo(path)
                mapOf(
                    "sha256" to sha256(file),
                    "packageName" to archive?.packageName,
                    "versionCode" to archive?.let { versionCodeOf(it) },
                    "sameSigner" to (archive != null && sameSigner(archive)),
                )
            } catch (error: Exception) {
                mapOf("error" to error.javaClass.simpleName)
            }
            main.post { result.success(outcome) }
        }
    }

    private fun canInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || activity.packageManager.canRequestPackageInstalls()

    /** 打开“允许安装未知应用”设置页；用户返回后由 Dart 侧重新检查。 */
    private fun openInstallPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
        return try {
            activity.startActivity(intent)
            true
        } catch (error: RuntimeException) {
            false
        }
    }

    private fun install(path: String, result: MethodChannel.Result) {
        registerReceiver()
        worker.execute {
            val outcome = try {
                commitSession(File(path))
                "started"
            } catch (error: Exception) {
                "failed:${error.javaClass.simpleName}"
            }
            main.post { result.success(outcome) }
        }
    }

    private fun commitSession(file: File) {
        val installer = activity.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(activity.packageName)
            setSize(file.length())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // 应用已是自己的安装来源时，系统可免确认直接更新；否则仍会弹确认页
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
        }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            FileInputStream(file).use { input ->
                session.openWrite("base.apk", 0, file.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            val intent = Intent(statusAction).setPackage(activity.packageName)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            // 系统要往这个 Intent 里写入安装状态，必须可变
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
            val pending = PendingIntent.getBroadcast(activity, sessionId, intent, flags)
            session.commit(pending.intentSender)
        }
    }

    private fun registerReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter(statusAction)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(statusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            activity.registerReceiver(statusReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun report(status: String, message: String?) {
        main.post { channel.invokeMethod("installStatus", mapOf("status" to status, "message" to message)) }
    }

    @Suppress("DEPRECATION")
    private fun confirmIntent(intent: Intent): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }

    @Suppress("DEPRECATION")
    private fun packageInfo(name: String, flags: Int): PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.packageManager.getPackageInfo(name, PackageManager.PackageInfoFlags.of(flags.toLong()))
        } else {
            activity.packageManager.getPackageInfo(name, flags)
        }

    @Suppress("DEPRECATION")
    private fun archiveInfo(path: String): PackageInfo? {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.packageManager.getPackageArchiveInfo(path, PackageManager.PackageInfoFlags.of(flags.toLong()))
        } else {
            activity.packageManager.getPackageArchiveInfo(path, flags)
        }
    }

    @Suppress("DEPRECATION")
    private fun versionCodeOf(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()

    /** 安装包的签名证书必须与当前应用一致；系统也会拒绝，但这里提前给出明确结果。 */
    @Suppress("DEPRECATION")
    private fun sameSigner(archive: PackageInfo): Boolean {
        val installed = signerDigests(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo(activity.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            } else {
                packageInfo(activity.packageName, PackageManager.GET_SIGNATURES)
            },
        )
        val incoming = signerDigests(archive)
        return installed.isNotEmpty() && installed == incoming
    }

    @Suppress("DEPRECATION")
    private fun signerDigests(info: PackageInfo): Set<String> {
        val signing = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.signingInfo else null
        val signatures = if (signing != null) {
            signing.apkContentsSigners
        } else {
            info.signatures
        } ?: return emptySet()
        return signatures.map { UpdateSignature.sha256Hex(it.toByteArray()) }.toSet()
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        if (receiverRegistered) {
            try {
                activity.unregisterReceiver(statusReceiver)
            } catch (error: IllegalArgumentException) {
                // 已被系统注销
            }
            receiverRegistered = false
        }
        worker.shutdown()
    }
}
