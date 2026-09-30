package com.example.diary_app

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * 每日后台刷新任务的排期。
 *
 * 为什么用 WorkManager 而不是 [android.content.BroadcastReceiver] 里的 goAsync()：
 * 广播接收器的执行窗口只有 ~10 秒，而这里要起一个 Flutter 引擎跑 Dart
 * （读 SQLite → 重排提醒 → 生成计划），超时会被系统直接杀掉进程。
 * Worker 有正经的执行窗口，也能跨重启自动恢复。
 */
object CourseWidgetScheduler {

    private const val TAG = "CourseWidgetScheduler"
    private const val PERIODIC_WORK = "course_widget_daily_refresh"
    private const val ONCE_WORK = "course_widget_refresh_once"

    /** 每天 11 点做一次（PD 的提议：那会儿一般还没关机） */
    private const val REFRESH_HOUR = 11

    /**
     * 保证「每日刷新」任务在排。反复调用是安全的 —— 用 [ExistingPeriodicWorkPolicy.KEEP]，
     * 已排过就原样保留。
     *
     * 这一点很关键：小组件每 30 分钟就会触发一次 [CourseWidgetProvider.onUpdate]，
     * 如果这里用 UPDATE，每次都会以「距下一个 11 点」重算延迟，
     * 任务会被无限往后推，永远等不到执行。
     */
    fun ensure(context: Context) {
        try {
            val request = PeriodicWorkRequestBuilder<CourseWidgetWorker>(24, TimeUnit.HOURS)
                .setInitialDelay(millisToNext(REFRESH_HOUR), TimeUnit.MILLISECONDS)
                .setConstraints(
                    Constraints.Builder()
                        // 纯本地计算，不需要网络
                        .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
                        .build()
                )
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                PERIODIC_WORK,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        } catch (t: Throwable) {
            Log.e(TAG, "排期每日刷新失败", t)
        }
    }

    /**
     * 立刻插一次刷新（开机后、用户新装/更新后）。
     * 用 REPLACE：连续触发只保留最后一次，不会堆积。
     */
    fun refreshSoon(context: Context) {
        try {
            val request = OneTimeWorkRequestBuilder<CourseWidgetWorker>().build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                ONCE_WORK,
                ExistingWorkPolicy.REPLACE,
                request,
            )
        } catch (t: Throwable) {
            Log.e(TAG, "立刻刷新入队失败", t)
        }
    }

    fun cancel(context: Context) {
        try {
            WorkManager.getInstance(context).cancelUniqueWork(PERIODIC_WORK)
            WorkManager.getInstance(context).cancelUniqueWork(ONCE_WORK)
        } catch (t: Throwable) {
            Log.e(TAG, "取消后台刷新失败", t)
        }
    }

    /** 距下一个 [hour] 点整还有多少毫秒 */
    internal fun millisToNext(hour: Int, now: Calendar = Calendar.getInstance()): Long {
        val next = Calendar.getInstance().apply {
            timeInMillis = now.timeInMillis
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now.timeInMillis) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }
        return next.timeInMillis - now.timeInMillis
    }
}
