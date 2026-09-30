package com.example.diary_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.util.Log

/**
 * 今日课程小组件。
 *
 * 刷新时机（这也是修掉「重新开机后还显示昨天的课」的地方）：
 * 1. `updatePeriodMillis=1800000` —— 系统至少每 30 分钟唤醒一次 [onUpdate]，
 *    按已存计划重画。**跨天就靠它**，不需要 App 在前台；
 * 2. 开机 / 应用更新 —— [CourseWidgetBootReceiver] 立刻重画；
 * 3. 用户缩放小组件 —— [onAppWidgetOptionsChanged] 重排行数；
 * 4. App 内课表变更 —— Dart 推送新计划后立即重画。
 */
class CourseWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { update(context, appWidgetManager, it) }
        // 顺手确认每日后台任务还在（幂等：已排过就保持原计划，不会顺延）
        CourseWidgetScheduler.ensure(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?,
    ) {
        // 用户拖大/拖小 → 可用行数变了，重算
        update(context, appWidgetManager, appWidgetId)
    }

    override fun onEnabled(context: Context) {
        CourseWidgetScheduler.ensure(context)
    }

    override fun onDisabled(context: Context) {
        // 桌面上一个实例都不剩了：停掉后台任务，别白耗电
        CourseWidgetScheduler.cancel(context)
    }

    companion object {
        private const val TAG = "CourseWidgetProvider"

        /** 重画全部实例 */
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = try {
                manager.getAppWidgetIds(
                    ComponentName(context, CourseWidgetProvider::class.java)
                )
            } catch (t: Throwable) {
                Log.e(TAG, "取小组件实例列表失败", t)
                return
            }
            ids.forEach { update(context, manager, it) }
        }

        /** 重画单个实例。渲染失败不能把广播炸掉，否则系统会记一次 ANR-ish 崩溃 */
        fun update(context: Context, manager: AppWidgetManager, appWidgetId: Int) {
            try {
                manager.updateAppWidget(
                    appWidgetId,
                    CourseWidgetRenderer.render(context, appWidgetId),
                )
            } catch (t: Throwable) {
                Log.e(TAG, "小组件渲染失败 id=$appWidgetId", t)
            }
        }
    }
}
