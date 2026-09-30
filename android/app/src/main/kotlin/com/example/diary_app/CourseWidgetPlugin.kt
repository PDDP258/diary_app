package com.example.diary_app

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 课表小组件的 Dart ↔ 原生通道。
 *
 * | 方法 | 用途 |
 * |---|---|
 * | `updatePlan` | Dart 推来两周计划（JSON）→ 落盘 + 立即重画 |
 * | `refresh` | 只按已有计划重画 |
 * | `clear` | 清掉计划（没有学期配置时）→ 小组件回到引导文案 |
 * | `registerBackground` | 交来后台入口点的回调句柄 + 确保每日任务在排 |
 * | `backgroundDone` | 后台 Dart 干完活了，可以销毁引擎 |
 *
 * 同一个类会在两个引擎里注册：主界面引擎（MainActivity），
 * 以及后台任务临时起的无界面引擎（[CourseWidgetBackgroundRunner]）。
 */
class CourseWidgetPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updatePlan" -> {
                val plan = call.argument<String>("plan")
                if (plan.isNullOrBlank()) {
                    result.error("bad_plan", "计划为空", null)
                    return
                }
                CourseWidgetStore.savePlan(context, plan)
                CourseWidgetProvider.updateAll(context)
                CourseWidgetScheduler.ensure(context)
                result.success(null)
            }

            "refresh" -> {
                CourseWidgetProvider.updateAll(context)
                result.success(null)
            }

            "clear" -> {
                CourseWidgetStore.clearPlan(context)
                CourseWidgetProvider.updateAll(context)
                result.success(null)
            }

            "registerBackground" -> {
                val handle = call.argument<Number>("handle")?.toLong() ?: -1L
                CourseWidgetStore.saveBackgroundHandle(context, handle)
                CourseWidgetScheduler.ensure(context)
                result.success(null)
            }

            "backgroundDone" -> {
                CourseWidgetBackgroundRunner.signalDone()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "com.diary_app/course_widget"
        private const val TAG = "CourseWidgetPlugin"

        /** 挂到指定引擎上（主引擎与后台引擎共用） */
        fun install(engine: FlutterEngine, context: Context) {
            try {
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .setMethodCallHandler(CourseWidgetPlugin(context.applicationContext))
            } catch (t: Throwable) {
                Log.e(TAG, "注册课表小组件通道失败", t)
            }
        }
    }
}
