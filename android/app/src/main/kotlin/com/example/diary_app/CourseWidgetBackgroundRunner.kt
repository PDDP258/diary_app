package com.example.diary_app

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.view.FlutterCallbackInformation
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * 在**没有界面**的情况下跑一段 Dart：起一个临时 FlutterEngine，
 * 执行 Dart 侧注册过的回调句柄（`courseWidgetBackgroundEntry`）。
 *
 * 为什么必须跑 Dart：小组件自己的刷新（重画）确实不需要 Dart，
 * 但**课前提醒的滚动窗口续排**和**生成新的两周计划**都要读 SQLite、算教学周，
 * 这些只有 Dart 会做。开机、每日定时正好是「App 不在前台」的时刻，
 * 所以只能这样把 Dart 拉起来。
 *
 * 这个引擎是**尽力而为**的：起不来就直接返回 false，
 * 调用方照样会把小组件按已有计划重画一遍，功能降级但不中断。
 */
object CourseWidgetBackgroundRunner {

    private const val TAG = "CourseWidgetBg"

    /** 等待 Dart 干完活的上限；超时就销毁引擎，别让后台进程挂着 */
    private const val DONE_TIMEOUT_SECONDS = 25L

    @Volatile
    private var doneLatch: CountDownLatch? = null

    /**
     * 起引擎跑一次后台 Dart 任务。
     *
     * 注意：`executeDartCallback` 是立即返回的，真正的 Dart 执行在引擎的
     * 独立 isolate 里异步进行 —— 所以这里必须等 Dart 主动回话
     * （[signalDone]），否则会提前销毁引擎把活干一半掐了。
     *
     * @return 是否成功把任务跑完
     */
    fun run(context: Context): Boolean {
        val handle = CourseWidgetStore.backgroundHandle(context)
        if (handle < 0L) {
            Log.w(TAG, "还没收到 Dart 回调句柄，跳过（App 至少启动过一次后才会注册）")
            return false
        }

        var engine: FlutterEngine? = null
        return try {
            val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(handle)
            if (callbackInfo == null) {
                Log.w(TAG, "回调句柄无效 handle=$handle")
                return false
            }

            // 用局部 val 而不是给外面的 var 赋值：避免可空智能转换的坑
            val created = FlutterEngine(context)
            engine = created

            // pub 插件：读 SQLite、写 SharedPreferences、排通知都靠它们
            GeneratedPluginRegistrant.registerWith(created)
            // 自家的 MethodChannel plugin（GeneratedPluginRegistrant 管不着）——
            // 没有它，Dart 侧推计划和「干完了」的回话都送不进来
            CourseWidgetPlugin.install(created, context)

            val latch = CountDownLatch(1)
            doneLatch = latch

            created.dartExecutor.executeDartCallback(
                DartExecutor.DartCallback(
                    context.assets,
                    // 与 FlutterLoader.findAppBundlePath() 的默认值一致
                    "flutter_assets",
                    callbackInfo,
                )
            )

            val finished = latch.await(DONE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            if (!finished) {
                Log.w(TAG, "后台 Dart 任务未在 ${DONE_TIMEOUT_SECONDS}s 内回话，按超时处理")
            }
            finished
        } catch (t: Throwable) {
            Log.e(TAG, "后台引擎执行失败（已降级为只重画小组件）", t)
            false
        } finally {
            doneLatch = null
            try {
                engine?.destroy()
            } catch (t: Throwable) {
                Log.e(TAG, "销毁后台引擎失败", t)
            }
        }
    }

    /** Dart 侧干完活后调用（走 `backgroundDone` 方法） */
    fun signalDone() {
        doneLatch?.countDown()
    }
}
