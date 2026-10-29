package com.chhreader.chh_app

import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.Surface
import android.view.SurfaceHolder
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** A per-window preference. Battery saver, user settings and OEM policy still win. */
class MainActivity : FlutterActivity() {
    private val maxRefreshHz = 120f
    private var resumed = false
    private var requestedMode: Display.Mode? = null
    private var flutterSurface: FlutterSurfaceView? = null
    private var channel: MethodChannel? = null
    private var sessionChannel: MethodChannel? = null
    private var editorTouchBridge: EditorTouchBridge? = null
    private var updateBridge: UpdateBridge? = null
    private var imageBridge: ImageBridge? = null
    private var surfaceVoteHz = 0f
    private var lastError: String? = null
    private var originalModeId = 0
    private var originalRefreshRate = 0f

    private val surfaceCallback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            if (resumed) requestPreferredRefresh()
        }
        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            if (resumed) requestSurfaceRate(holder.surface, requestedMode?.refreshRate ?: 0f)
        }
        override fun surfaceDestroyed(holder: SurfaceHolder) {
            surfaceVoteHz = 0f
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        editorTouchBridge?.dispose()
        editorTouchBridge = EditorTouchBridge(this, flutterEngine)
        updateBridge?.dispose()
        updateBridge = UpdateBridge(this, flutterEngine)
        imageBridge?.dispose()
        imageBridge = ImageBridge(this, flutterEngine)
        sessionChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chh/session")
        sessionChannel?.setMethodCallHandler { call, result ->
            if (call.method != "flushCookies") {
                result.notImplemented()
            } else {
                // flush performs disk I/O; finish it before reporting login success.
                Thread {
                    try {
                        CookieManager.getInstance().flush()
                        runOnUiThread { result.success(null) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("cookie_flush_failed", error.javaClass.simpleName, null) }
                    }
                }.start()
            }
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chh/display_refresh")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPreferred" -> {
                    if (resumed) {
                        bindFlutterSurface(window.decorView)
                        requestPreferredRefresh()
                    }
                    result.success(displaySnapshot())
                }
                "read" -> result.success(displaySnapshot())
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // 只截下发帖选图的结果；其余请求码照常交给插件
        if (imageBridge?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        originalModeId = window.attributes.preferredDisplayModeId
        originalRefreshRate = window.attributes.preferredRefreshRate
        window.decorView.post { bindFlutterSurface(window.decorView) }
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        requestPreferredRefresh()
        window.decorView.post {
            if (resumed) {
                bindFlutterSurface(window.decorView)
                requestPreferredRefresh()
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        window.decorView.post {
            if (resumed) requestPreferredRefresh()
        }
    }

    override fun onPause() {
        resumed = false
        flutterSurface?.holder?.surface?.let { requestSurfaceRate(it, 0f) }
        val attributes = window.attributes
        attributes.preferredDisplayModeId = originalModeId
        attributes.preferredRefreshRate = originalRefreshRate
        window.attributes = attributes
        super.onPause()
    }

    override fun onDestroy() {
        editorTouchBridge?.dispose()
        editorTouchBridge = null
        updateBridge?.dispose()
        updateBridge = null
        imageBridge?.dispose()
        imageBridge = null
        flutterSurface?.holder?.removeCallback(surfaceCallback)
        flutterSurface = null
        channel?.setMethodCallHandler(null)
        channel = null
        sessionChannel?.setMethodCallHandler(null)
        sessionChannel = null
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun currentDisplay(): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display ?: windowManager.defaultDisplay
        else windowManager.defaultDisplay

    private fun bindFlutterSurface(view: View) {
        // Do not vote on plugin/video surfaces owned by other components.
        if (view is FlutterSurfaceView && flutterSurface !== view) {
            flutterSurface?.holder?.removeCallback(surfaceCallback)
            flutterSurface = view
            view.holder.addCallback(surfaceCallback)
            if (resumed && view.holder.surface.isValid) {
                requestSurfaceRate(view.holder.surface, requestedMode?.refreshRate ?: 0f)
            }
            return
        }
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) bindFlutterSurface(view.getChildAt(index))
        }
    }

    private fun requestPreferredRefresh() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val display = currentDisplay() ?: return
        val current = display.mode
        // Keep the current physical resolution; never trade clarity for Hz.
        val candidate = display.supportedModes.filter {
            it.physicalWidth == current.physicalWidth &&
                it.physicalHeight == current.physicalHeight &&
                RefreshRatePolicy.isWithinCap(it.refreshRate, maxRefreshHz)
        }.maxByOrNull { it.refreshRate }
        requestedMode = candidate
        try {
            val attributes = window.attributes
            val modeId = candidate?.modeId ?: 0
            val rate = candidate?.refreshRate ?: 0f
            if (attributes.preferredDisplayModeId != modeId || attributes.preferredRefreshRate != rate) {
                attributes.preferredDisplayModeId = modeId
                attributes.preferredRefreshRate = rate
                window.attributes = attributes
            }
            lastError = null
            flutterSurface?.holder?.surface?.let { requestSurfaceRate(it, rate) }
        } catch (error: RuntimeException) {
            lastError = error.javaClass.simpleName
        }
    }

    private fun requestSurfaceRate(surface: Surface, rate: Float) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || !surface.isValid) return
        try {
            // UI is variable-rate content, not fixed-source video. Never request
            // a disruptive non-seamless switch merely to satisfy this hint.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                surface.setFrameRate(rate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                    Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS)
            } else {
                surface.setFrameRate(rate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
            }
            surfaceVoteHz = rate
        } catch (error: RuntimeException) {
            lastError = error.javaClass.simpleName
        }
    }

    private fun modeSnapshot(mode: Display.Mode): Map<String, Any> = mapOf(
        "id" to mode.modeId,
        "width" to mode.physicalWidth,
        "height" to mode.physicalHeight,
        "refreshRate" to mode.refreshRate.toDouble()
    )

    private fun displaySnapshot(): Map<String, Any?> {
        val display = currentDisplay()
        val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && display != null
        return mapOf(
            "available" to supported,
            "apiLevel" to Build.VERSION.SDK_INT,
            "foreground" to resumed,
            "maxRequestedHz" to maxRefreshHz.toDouble(),
            "capToleranceHz" to RefreshRatePolicy.CAP_TOLERANCE_HZ.toDouble(),
            "requestedMode" to requestedMode?.let { modeSnapshot(it) },
            "actualMode" to if (supported) modeSnapshot(display.mode) else null,
            "actualRefreshRate" to display?.refreshRate?.toDouble(),
            "supportedModes" to if (supported) display.supportedModes.map { modeSnapshot(it) } else emptyList<Map<String, Any>>(),
            "preferredDisplayModeId" to window.attributes.preferredDisplayModeId,
            "surfaceVoteHz" to surfaceVoteHz.toDouble(),
            "surfaceAvailable" to (flutterSurface?.holder?.surface?.isValid == true),
            "lastError" to lastError
        )
    }
}
