package com.chhreader.chh_app

import android.app.job.JobParameters
import android.app.job.JobService
import android.os.Handler
import android.os.Looper

/** JobScheduler may defer checks during idle/battery saving; this is not push delivery. */
class MessageCheckService : JobService() {
    private val main = Handler(Looper.getMainLooper())
    private var running: AccountChecker.Run? = null

    override fun onStartJob(params: JobParameters): Boolean {
        running?.cancel()
        running = AccountChecker.get(this).check(allowLegacy = true) { run, _ ->
            main.post {
                if (running === run) {
                    running = null
                    jobFinished(params, false)
                }
            }
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        cancelRun()
        return true
    }

    override fun onDestroy() {
        cancelRun()
        super.onDestroy()
    }

    private fun cancelRun() {
        running?.cancel()
        running = null
    }
}
