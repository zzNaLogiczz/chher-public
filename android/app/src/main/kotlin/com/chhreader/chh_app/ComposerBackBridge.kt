package com.chhreader.chh_app

import android.app.Activity
import android.os.Build
import android.view.KeyEvent
import android.view.ViewGroup
import android.widget.FrameLayout
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Only the active writing sheet overrides the IME's first-back dismissal. */
internal class ComposerBackBridge(private val activity: Activity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "chh/composer_back")
    private var disposed = false
    private var enabled = false
    private var callback: OnBackInvokedCallback? = null
    private var legacyContainer: FrameLayout? = null

    init {
        if (Build.VERSION.SDK_INT < 33) activity.window.decorView.post {
            if (!disposed) installLegacyContainer()
        }
        channel.setMethodCallHandler { call, result ->
            if (call.method == "setEnabled") {
                setEnabled(call.arguments == true)
                result.success(null)
            } else result.notImplemented()
        }
    }

    private fun setEnabled(value: Boolean) {
        if (enabled == value) return
        enabled = value
        if (Build.VERSION.SDK_INT >= 33) {
            if (value) {
                val handler = OnBackInvokedCallback { channel.invokeMethod("back", null) }
                callback = handler
                activity.onBackInvokedDispatcher.registerOnBackInvokedCallback(
                    OnBackInvokedDispatcher.PRIORITY_OVERLAY, handler,
                )
            } else {
                callback?.let { activity.onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }
                callback = null
            }
        }
    }

    private fun installLegacyContainer() {
        if (legacyContainer == null) {
            // Install before editing starts so reparenting cannot disturb an input connection.
            val content = activity.findViewById<ViewGroup>(android.R.id.content)
            val child = content.getChildAt(0) ?: return
            val container = object : FrameLayout(activity) {
                override fun dispatchKeyEventPreIme(event: KeyEvent): Boolean {
                    if (enabled && event.keyCode == KeyEvent.KEYCODE_BACK) {
                        if (event.action == KeyEvent.ACTION_UP && !event.isCanceled) {
                            channel.invokeMethod("back", null)
                        }
                        return true
                    }
                    return super.dispatchKeyEventPreIme(event)
                }
            }
            val params = child.layoutParams
            content.removeView(child)
            container.addView(child, FrameLayout.LayoutParams(-1, -1))
            content.addView(container, 0, params)
            legacyContainer = container
        }
    }

    fun dispose() {
        disposed = true
        setEnabled(false)
        channel.setMethodCallHandler(null)
        legacyContainer?.let { container ->
            val parent = container.parent as? ViewGroup
            val child = container.getChildAt(0)
            if (parent != null && child != null) {
                val index = parent.indexOfChild(container)
                val params = container.layoutParams
                container.removeView(child)
                parent.removeView(container)
                parent.addView(child, index, params)
            }
        }
        legacyContainer = null
    }
}
