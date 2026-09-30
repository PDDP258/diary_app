# Flutter release 构建默认启用 R8。这里放 **只被 AndroidManifest / 反射引用、
# 编译器看不见** 的那些类 —— 不显式 keep 的话 R8 可能改名甚至剥掉它们，
# 症状是「编译通过、真机上某个入口就是不触发」。

# ==================== 今日课程桌面小组件 ====================
# 说明：这几条其实是「保险 + 自文档」。原因：
#   1. Provider / BootReceiver 由 AndroidManifest 引用，AGP 会自动生成 keep 规则；
#   2. Worker 有 `PeriodicWorkRequestBuilder<CourseWidgetWorker>()` 这类**类字面量**
#      引用，R8 视作使用；且 androidx.work 自带
#      `-keepnames class * extends androidx.work.ListenableWorker`
#      （见 work-runtime-*.aar 内嵌的 proguard.txt）防止改名。
# 但 WorkManager 是按**类名字符串**反射实例化 Worker 的，一旦哪天把
# `PeriodicWorkRequestBuilder<X>()` 改成传动态类名、或 AGP 自动规则行为变化，
# 就会静默失效。所以显式写死更稳。
-keep class com.example.diary_app.CourseWidgetProvider { *; }
-keep class com.example.diary_app.CourseWidgetBootReceiver { *; }
-keep class com.example.diary_app.CourseWidgetWorker { *; }
-keepnames class com.example.diary_app.CourseWidgetPlan { *; }
-keepnames class com.example.diary_app.CourseWidgetRenderer { *; }

# 注：glance_widget 已于 2026-09-30 移除（小组件改为自绘 RemoteViews），
# 原来的 `-keep class androidx.glance.**` 等规则一并删掉。
