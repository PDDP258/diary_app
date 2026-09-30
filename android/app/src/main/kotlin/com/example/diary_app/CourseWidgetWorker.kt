package com.example.diary_app

import android.content.Context
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * 每日 / 开机后的后台刷新。
 *
 * 顺序有意为之：
 * 1. 先按**已有计划**重画小组件 —— 这一步纯原生，必然成功，
 *    所以即使 Dart 起不来，桌面上看到的也是今天正确的课表；
 * 2. 再拉起 Dart 续排提醒窗口、生成新计划；
 * 3. 用 Dart 可能写下的新计划再画一次。
 */
class CourseWidgetWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {

    override fun doWork(): Result {
        val context = applicationContext

        // 1. 先保证「显示正确」（不依赖 Dart）
        CourseWidgetProvider.updateAll(context)

        // 2. 拉起 Dart：续排课前提醒 + 重新生成两周计划
        val ok = CourseWidgetBackgroundRunner.run(context)
        Log.i(TAG, "后台刷新完成，Dart 任务成功=$ok")

        // 3. 用新计划再画一次
        CourseWidgetProvider.updateAll(context)

        // 永远返回 success：失败重试也不会更好（下次定时自会再试），
        // 反而会在队列里堆重试
        return Result.success()
    }

    companion object {
        private const val TAG = "CourseWidgetWorker"
    }
}
