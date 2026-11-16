package com.chhreader.chh_app

import java.io.File
import java.nio.file.Files

/** Standalone JVM boundary check; no Android runtime or filesystem permissions. */
fun main() {
    val root = Files.createTempDirectory("image-save-check-").toFile()
    try {
        val cache = File(root, "cache").apply { mkdirs() }
        val codeCache = File(root, "code_cache").apply { mkdirs() }
        fun allowed(file: File?) = ImageBridge.isSaveSource(file, cache, codeCache)
        fun image(parent: File, name: String = "source") =
            File(parent, name).apply { parent.mkdirs(); writeText("fixture") }
        check(allowed(image(cache)))
        check(allowed(image(File(codeCache, "chher-image-lease-1"))))
        check(!allowed(null))
        check(!allowed(codeCache))
        check(!allowed(File(cache, "missing")))
        val outside = image(File(root, "files"))
        check(!allowed(outside))
        check(!allowed(image(File(root, "cache-other"))))
        check(!allowed(File(cache, "../files/source")))
        val escape = File(codeCache, "escape")
        Files.createSymbolicLink(escape.toPath(), outside.toPath())
        check(!allowed(escape))
        println("Image save source: all 9 boundary checks passed")
    } finally {
        root.deleteRecursively()
    }
}
