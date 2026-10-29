package com.chhreader.chh_app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * 发帖图片的原生部分：系统选图、按 EXIF 转正解码、缩放与编码。
 * 压缩策略（尺寸、质量怎么取）在 Dart 侧，这里只提供可组合的原语；
 * 重新编码不写入原图元数据，拍摄地点等信息不会随图片上传。
 */
internal class ImageBridge(
    private val activity: Activity,
    engine: FlutterEngine,
) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "chh/image")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val dir = File(activity.cacheDir, "chh_upload")
    private val sources = HashMap<Int, Source>()
    private var nextHandle = 1
    private var pendingPick: MethodChannel.Result? = null

    private class Source(val bytes: ByteArray, val format: String, val bitmap: Bitmap?) {
        var scaledSide = 0
        var scaled: Bitmap? = null
    }

    init {
        // 上次进程留下的临时文件此时已无人引用
        worker.execute { dir.deleteRecursively(); dir.mkdirs() }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pick(call.argument<Int>("max") ?: 1, result)
                "open" -> work(result) { open(call.argument<String>("uri")!!) }
                "encode" -> work(result) {
                    encode(
                        call.argument<Int>("handle")!!,
                        call.argument<Int>("maxSide")!!,
                        call.argument<Int>("quality")!!,
                        call.argument<String>("format")!!,
                    )
                }
                "original" -> work(result) { original(call.argument<Int>("handle")!!) }
                "close" -> work(result) { close(call.argument<Int>("handle")!!); null }
                "discard" -> work(result) { discard(call.argument<String>("path")!!); null }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingPick?.success(emptyList<String>())
        pendingPick = null
        worker.execute {
            sources.values.forEach { recycle(it) }
            sources.clear()
        }
        worker.shutdown()
    }

    /** 选图结果；不是本桥的请求返回 false，交给其他组件处理 */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK) return false
        val result = pendingPick ?: return true
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<String>())
            return true
        }
        val uris = mutableListOf<String>()
        data.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri.toString()) }
        if (uris.isEmpty()) data.data?.let { uris.add(it.toString()) }
        result.success(uris)
        return true
    }

    // 系统照片选择器与文件选择器都只授予所选图片的临时读取权，不需要存储权限
    private fun pick(max: Int, result: MethodChannel.Result) {
        if (pendingPick != null) return result.error("busy", "picker already open", null)
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                if (max > 1) putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, min(max, MediaStore.getPickImagesMaxLimit()))
            }
        } else {
            Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "image/*"
                addCategory(Intent.CATEGORY_OPENABLE)
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, max > 1)
            }
        }
        pendingPick = result
        try {
            activity.startActivityForResult(intent, REQUEST_PICK)
        } catch (error: ActivityNotFoundException) {
            pendingPick = null
            result.error("no_picker", error.javaClass.simpleName, null)
        }
    }

    private fun open(uri: String): Map<String, Any> {
        val bytes = activity.contentResolver.openInputStream(Uri.parse(uri))?.use { it.readBytes() }
            ?: throw IllegalStateException("unreadable")
        val format = sniff(bytes)
        // 动图不解码：保留原字节才能保留动画
        val bitmap = if (format == "gif") null else decode(bytes) ?: throw IllegalStateException("undecodable")
        val width: Int
        val height: Int
        if (bitmap != null) {
            width = bitmap.width
            height = bitmap.height
        } else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            width = bounds.outWidth
            height = bounds.outHeight
        }
        val handle = nextHandle++
        sources[handle] = Source(bytes, format, bitmap)
        return mapOf("handle" to handle, "width" to width, "height" to height, "format" to format, "size" to bytes.size)
    }

    /** 解码并转正；超大图在解码时就缩到最长边不超过 [MAX_SIDE]，避免整张大图进内存 */
    private fun decode(bytes: ByteArray): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                // ImageDecoder 会按 EXIF 方向转正
                return ImageDecoder.decodeBitmap(ImageDecoder.createSource(ByteBuffer.wrap(bytes))) { decoder, info, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    val longest = max(info.size.width, info.size.height)
                    if (longest > MAX_SIDE) {
                        val f = MAX_SIDE.toFloat() / longest
                        decoder.setTargetSize(
                            max(1, (info.size.width * f).roundToInt()),
                            max(1, (info.size.height * f).roundToInt()),
                        )
                    }
                }
            } catch (_: OutOfMemoryError) {
                return null
            } catch (_: Exception) {
                // 交给 BitmapFactory 再试一次
            }
        }
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_SIDE) sample *= 2
            val options = BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: return null
            upright(decoded, bytes)
        } catch (_: OutOfMemoryError) {
            null
        }
    }

    /** BitmapFactory 不处理 EXIF 方向，这里按标签旋转或翻转 */
    private fun upright(bitmap: Bitmap, bytes: ByteArray): Bitmap {
        val orientation = try {
            ExifInterface(ByteArrayInputStream(bytes))
                .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        } catch (_: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.postRotate(90f); matrix.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.postRotate(270f); matrix.postScale(-1f, 1f) }
            else -> return bitmap
        }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }

    private fun encode(handle: Int, maxSide: Int, quality: Int, format: String): Map<String, Any> {
        val source = sources[handle] ?: throw IllegalStateException("closed")
        val base = source.bitmap ?: throw IllegalStateException("not decodable")
        val bitmap = scaled(source, base, maxSide)
        val out = ByteArrayOutputStream()
        if (format == "png") {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        } else {
            // JPEG 没有透明通道：透明处铺白底，免得变成黑色
            val opaque = if (bitmap.hasAlpha()) flatten(bitmap) else bitmap
            opaque.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), out)
            if (opaque !== bitmap) opaque.recycle()
        }
        val file = write(out.toByteArray(), if (format == "png") "png" else "jpg")
        return mapOf("path" to file.path, "size" to file.length().toInt(), "width" to bitmap.width, "height" to bitmap.height)
    }

    /** 同一尺寸的多次质量尝试复用一张缩放图 */
    private fun scaled(source: Source, base: Bitmap, maxSide: Int): Bitmap {
        val longest = max(base.width, base.height)
        if (maxSide >= longest) return base
        source.scaled?.let { if (source.scaledSide == maxSide) return it }
        source.scaled?.recycle()
        val f = maxSide.toFloat() / longest
        val next = Bitmap.createScaledBitmap(
            base,
            max(1, (base.width * f).roundToInt()),
            max(1, (base.height * f).roundToInt()),
            true,
        )
        source.scaled = next
        source.scaledSide = maxSide
        return next
    }

    private fun flatten(bitmap: Bitmap): Bitmap {
        val flat = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(flat)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(bitmap, 0f, 0f, null)
        return flat
    }

    private fun original(handle: Int): Map<String, Any> {
        val source = sources[handle] ?: throw IllegalStateException("closed")
        val file = write(source.bytes, if (source.format == "gif") "gif" else "bin")
        return mapOf("path" to file.path, "size" to file.length().toInt())
    }

    private fun close(handle: Int) {
        sources.remove(handle)?.let { recycle(it) }
    }

    private fun recycle(source: Source) {
        source.scaled?.recycle()
        source.bitmap?.recycle()
    }

    private fun discard(path: String) {
        val file = File(path)
        // 只删自己目录里的文件
        if (file.canonicalPath.startsWith(dir.canonicalPath + File.separator)) file.delete()
    }

    private fun write(bytes: ByteArray, ext: String): File {
        dir.mkdirs()
        val file = File(dir, "${UUID.randomUUID()}.$ext")
        file.writeBytes(bytes)
        return file
    }

    private fun work(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (error: OutOfMemoryError) {
                main.post { result.error("out_of_memory", null, null) }
            } catch (error: Exception) {
                main.post { result.error("image_failed", error.message ?: error.javaClass.simpleName, null) }
            }
        }
    }

    companion object {
        private const val REQUEST_PICK = 0x4348
        private const val MAX_SIDE = 4096

        /** 按文件头识别格式，不看扩展名 */
        fun sniff(bytes: ByteArray): String {
            fun at(i: Int) = if (i < bytes.size) bytes[i].toInt() and 0xff else -1
            fun ascii(from: Int, text: String) = text.indices.all { at(from + it) == text[it].code }
            return when {
                at(0) == 0xff && at(1) == 0xd8 && at(2) == 0xff -> "jpeg"
                at(0) == 0x89 && ascii(1, "PNG") -> "png"
                ascii(0, "GIF") -> "gif"
                bytes.size >= 12 && ascii(0, "RIFF") && ascii(8, "WEBP") -> "webp"
                bytes.size >= 12 && ascii(4, "ftyp") -> "heif"
                else -> "unknown"
            }
        }
    }
}
