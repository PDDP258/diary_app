package com.example.diary_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 开机 / 应用更新后立刻把小组件刷成「今天」。
 *
 * 为什么必须有这个接收器：小组件是靠系统定时唤醒刷新的（最少 30 分钟一次），
 * 刚开机那一刻拿到的还是休眠前存下的画面 —— 于是出现「9 月 30 日开机，
 * 小组件仍显示 9 月 29 日的课」。这里在开机广播里立刻按已有计划重画一次，
 * 再异步拉 Dart 续排提醒窗口、生成新计划。
 */
class CourseWidgetBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            ACTION_QUICKBOOT_POWERON,
            ACTION_HTC_QUICKBOOT_POWERON -> {
                Log.i(TAG, "收到 ${intent.action}，立即刷新课表小组件")
                // 1. 立刻重画（纯原生，必然成功）
                CourseWidgetProvider.updateAll(context)
                // 2. 确认每日任务在排（WorkManager 自己也能跨重启恢复，这里幂等兜底）
                CourseWidgetScheduler.ensure(context)
                // 3. 异步拉 Dart：续排提醒 + 生成新计划
                CourseWidgetScheduler.refreshSoon(context)
            }
        }
    }

    companion object {
        private const val TAG = "CourseWidgetBoot"
        private const val ACTION_QUICKBOOT_POWERON = "android.intent.action.QUICKBOOT_POWERON"
        private const val ACTION_HTC_QUICKBOOT_POWERON = "com.htc.intent.action.QUICKBOOT_POWERON"
    }
}
