package com.chhreader.chh_app

import io.flutter.embedding.engine.systemchannels.ProcessTextChannel.ProcessTextMethodHandler
import io.flutter.plugin.common.MethodChannel

fun main() {
    var queryCount = 0
    val plugin = object : ProcessTextMethodHandler {
        override fun queryTextActions(): Map<String, String> =
            if (++queryCount == 1) mapOf("translate" to "Translate") else emptyMap()

        override fun processTextAction(id: String, input: String, readOnly: Boolean, result: MethodChannel.Result) {
            check(id == "translate" && input == "selected text" && readOnly)
            result.success("processed")
        }
    }

    val handler = CachedProcessTextHandler(plugin)
    check(queryCount == 0)
    check(handler.queryTextActions() == mapOf("translate" to "Translate"))
    check(handler.queryTextActions() == mapOf("translate" to "Translate"))
    check(queryCount == 1)

    var processed: Any? = null
    handler.processTextAction("translate", "selected text", true, object : MethodChannel.Result {
        override fun success(result: Any?) { processed = result }
        override fun error(code: String, message: String?, details: Any?) = error("$code: $message")
        override fun notImplemented() = error("Missing action delegate")
    })
    check(processed == "processed" && queryCount == 1)

    handler.invalidate()
    check(handler.queryTextActions().isEmpty())
    check(handler.queryTextActions().isEmpty())
    check(queryCount == 2)
    println("Process text: first query, cache hits, action delegation and invalidation passed")
}
