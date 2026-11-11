package com.chhreader.chh_app

import android.app.job.JobParameters
import android.app.job.JobService
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import java.net.HttpURLConnection
import java.net.URL

/** JobScheduler may defer checks during idle/battery saving; this is not push delivery. */
class MessageCheckService : JobService() {
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var connection: HttpURLConnection? = null
    private var generation = 0

    override fun onStartJob(params: JobParameters): Boolean {
        val prefs = NotificationBridge.prefs(this)
        if (!prefs.getBoolean("active", false) || !NotificationBridge.enabled(this)) return false
        val cookie = currentCookie() ?: return false
        if (!hasAuth(cookie)) return false
        val revision = prefs.getLong("session_revision", 0)
        val headerRevision = prefs.getLong("header_revision", 0)
        val epoch = ++generation
        Thread {
            val header = try { fetch(cookie) } catch (_: Exception) { null }
            main.post {
                if (epoch != generation) return@post
                try {
                    // Never apply an old response after auth or a newer foreground observation.
                    if (header != null && prefs.getBoolean("active", false) &&
                        prefs.getLong("session_revision", 0) == revision &&
                        prefs.getLong("header_revision", 0) == headerRevision &&
                        currentCookie() == cookie &&
                        prefs.getString("uid", null).let { it == null || it == header.uid }) {
                        NotificationBridge.show(this, header.uid, header.notices, header.messages)
                    }
                } catch (_: RuntimeException) {
                    // Permission can be revoked between the enabled check and notify.
                } finally {
                    jobFinished(params, false)
                }
            }
        }.start()
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        generation++
        connection?.disconnect()
        return true
    }

    override fun onDestroy() {
        generation++
        connection?.disconnect()
        super.onDestroy()
    }

    private fun currentCookie(): String? = try {
        CookieManager.getInstance().getCookie(SITE)
    } catch (_: RuntimeException) { null }

    private fun hasAuth(cookie: String) = cookie.split(';').any {
        val entry = it.trim().split('=', limit = 2)
        entry.size == 2 && entry[0].endsWith("_auth") && entry[1].isNotEmpty()
    }

    private fun fetch(cookie: String): MessageHeader? {
        val request = URL("$SITE/forum.php?mobile=no").openConnection() as HttpURLConnection
        connection = request
        try {
            request.connectTimeout = 10_000
            request.readTimeout = 10_000
            request.instanceFollowRedirects = false
            request.useCaches = false
            request.setRequestProperty("Cookie", cookie)
            request.setRequestProperty("Cache-Control", "no-cache")
            // Match DirectFetcher's desktop headers; mobile hints trigger the site's WAF.
            request.setRequestProperty("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36")
            request.setRequestProperty("Accept", "text/html,application/xhtml+xml,*/*;q=0.8")
            request.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9")
            request.setRequestProperty("sec-ch-ua", "\"Chromium\";v=\"155\", \"Not=A?Brand\";v=\"24\"")
            request.setRequestProperty("sec-ch-ua-mobile", "?0")
            request.setRequestProperty("sec-ch-ua-platform", "\"macOS\"")
            if (request.responseCode != 200) return null
            val bytes = request.inputStream.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (output.size() <= 2 * 1024 * 1024) {
                    val size = input.read(buffer)
                    if (size < 0) break
                    output.write(buffer, 0, size)
                }
                output.toByteArray()
            }
            if (bytes.size > 2 * 1024 * 1024) return null
            return MessageHeader.parse(bytes.toString(Charsets.UTF_8))
        } finally {
            request.disconnect()
            connection = null
        }
    }

    companion object { private const val SITE = "https://www.chiphell.com" }
}
