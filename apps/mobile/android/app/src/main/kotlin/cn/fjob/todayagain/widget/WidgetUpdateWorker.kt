package cn.fjob.todayagain.widget

import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Re-renders the widget from the stored timeline. Android does not support
 * `updatePeriodMillis` below 30 minutes and WorkManager scheduling is inexact,
 * so the widget always shows the real `computedAt` time instead of pretending
 * to be live.
 */
class WidgetUpdateWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {
    override fun doWork(): Result {
        FjobWidgetProvider.updateAll(applicationContext)
        return Result.success()
    }

    companion object {
        private const val UNIQUE_NAME = "fjob-widget-refresh"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<WidgetUpdateWorker>(
                30,
                TimeUnit.MINUTES,
            ).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_NAME)
        }
    }
}
