package com.chhreader.chh_app

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

internal class SupportBridge(
    private val activity: Activity,
    engine: FlutterEngine,
) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "chh/support")
    private val worker = Executors.newSingleThreadExecutor()
    private val pendingSaves = mutableListOf<Save>()

    private class Save(
        val bytes: ByteArray,
        val displayName: String,
        val result: MethodChannel.Result,
    )

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImage" -> {
                    val args = call.arguments as? Map<*, *>
                    val bytes = args?.get("bytes") as? ByteArray
                    val name = args?.get("displayName") as? String
                    if (bytes == null || bytes.isEmpty() || name == null ||
                        !SupportNativePolicy.isPngDisplayName(name)
                    ) {
                        result.error("invalid_args", null, null)
                    } else {
                        saveImage(Save(bytes, name, result))
                    }
                }
                "openWeChatScan" -> result.success(openWeChatScan())
                else -> result.notImplemented()
            }
        }
    }

    private fun saveImage(save: Save) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            writeImage(save)
            return
        }
        pendingSaves.add(save)
        if (pendingSaves.size != 1) return
        try {
            activity.requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                STORAGE_PERMISSION_REQUEST,
            )
        } catch (_: RuntimeException) {
            onRequestPermissionsResult(STORAGE_PERMISSION_REQUEST, intArrayOf())
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != STORAGE_PERMISSION_REQUEST) return false
        val saves = pendingSaves.toList()
        pendingSaves.clear()
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        for (save in saves) {
            if (granted) writeImage(save) else save.result.error("permission_denied", null, null)
        }
        return true
    }

    private fun writeImage(save: Save) {
        worker.execute {
            try {
                insertImage(save)
                activity.runOnUiThread { save.result.success(true) }
            } catch (_: Exception) {
                activity.runOnUiThread { save.result.error("save_failed", null, null) }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun insertImage(save: Save) {
        val resolver = activity.contentResolver
        val scopedStorage = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val legacyFile = if (scopedStorage) null else reserveLegacyFile(save.displayName)
        var uri: Uri? = null
        try {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, legacyFile?.name ?: save.displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
                if (scopedStorage) {
                    put(MediaStore.MediaColumns.RELATIVE_PATH, SupportNativePolicy.RELATIVE_PATH)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                } else {
                    put(MediaStore.MediaColumns.DATA, checkNotNull(legacyFile).absolutePath)
                }
            }
            val collection = if (scopedStorage) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
            val inserted = checkNotNull(resolver.insert(collection, values))
            uri = inserted
            checkNotNull(resolver.openOutputStream(inserted)).use { it.write(save.bytes) }
            if (scopedStorage) {
                val published = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
                check(resolver.update(inserted, published, null, null) > 0)
            }
        } catch (error: Exception) {
            uri?.let { runCatching { resolver.delete(it, null, null) } }
            legacyFile?.let { runCatching { it.delete() } }
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun reserveLegacyFile(displayName: String): File {
        val directory = File(Environment.getExternalStorageDirectory(), SupportNativePolicy.RELATIVE_PATH)
        check(directory.mkdirs() || directory.isDirectory)
        var file = File(directory, displayName)
        var number = 1
        while (!file.createNewFile()) {
            file = File(directory, SupportNativePolicy.numberedDisplayName(displayName, number++))
        }
        return file
    }

    private fun openWeChatScan(): String {
        val scan = Intent()
            .setClassName(SupportNativePolicy.WECHAT_PACKAGE, SupportNativePolicy.WECHAT_LAUNCHER)
            .putExtra(SupportNativePolicy.WECHAT_SCAN_EXTRA, SupportNativePolicy.WECHAT_SCAN_VALUE)
            .setFlags(SupportNativePolicy.WECHAT_SCAN_FLAGS)
        try {
            activity.startActivity(scan)
            return "scan"
        } catch (_: RuntimeException) {
            // LauncherUI may be unavailable while the app's entry point still works.
        }
        return try {
            val app = activity.packageManager.getLaunchIntentForPackage(SupportNativePolicy.WECHAT_PACKAGE)
                ?: return "missing"
            activity.startActivity(app)
            "app"
        } catch (_: RuntimeException) {
            "missing"
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        for (save in pendingSaves) save.result.error("save_failed", null, null)
        pendingSaves.clear()
        worker.shutdown()
    }

    private companion object {
        const val STORAGE_PERMISSION_REQUEST = 0x434A
    }
}
