package com.chhreader.chh_app

import io.flutter.embedding.engine.systemchannels.ProcessTextChannel.ProcessTextMethodHandler

/** The engine caches activity resolution, but looks up labels for every query. */
internal class CachedProcessTextHandler(
    private val plugin: ProcessTextMethodHandler,
) : ProcessTextMethodHandler by plugin {
    private var actions: Map<String, String>? = null

    override fun queryTextActions(): Map<String, String> =
        actions ?: plugin.queryTextActions().also { actions = it }

    fun invalidate() {
        actions = null
    }
}
