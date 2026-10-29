package com.chhreader.chh_app

import android.app.Activity
import android.content.Context
import android.view.View
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** 把 Flutter 编辑框的明确点击同步给 Android 输入法，不修改文本或系统输入法配置。 */
internal class EditorTouchBridge(
    private val activity: Activity,
    engine: FlutterEngine,
) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "chh/editor_touch")
    private val imm = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "editorTapped") {
                result.notImplemented()
            } else {
                try {
                    result.success(editorTapped())
                } catch (error: RuntimeException) {
                    result.error("editor_touch_failed", error.javaClass.simpleName, null)
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun editorTapped(): Boolean {
        if (activity.isFinishing || activity.isDestroyed) return false
        val view = activity.currentFocus as? FlutterView ?: return false
        val decor = activity.window.decorView
        if (decor.findFocus() !== view || !decor.hasWindowFocus() ||
            !view.isAttachedToWindow || !view.isShown ||
            view.visibility != View.VISIBLE || view.windowVisibility != View.VISIBLE ||
            !view.isFocused || !view.hasWindowFocus() || view.windowToken == null
        ) return false

        // Android TextView 的真实点击仍先发送 viewClicked，再请求普通软键盘显示。
        // 此 API 虽已 deprecated，但部分输入法靠它结束硬件按键模式；Flutter 的
        // TextInput.show 只有 showSoftInput，缺少这次点击通知。这里只补齐明确
        // 编辑点击的兼容语义，不在生命周期或任意触摸时运行，也不重建输入连接。
        imm.viewClicked(view)
        // 返回值只代表系统接受显示请求，不代表键盘已有可见内容。
        return imm.showSoftInput(view, 0)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
