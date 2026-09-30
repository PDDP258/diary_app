package com.example.diary_app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 注册图标主题插件
        // 「笔迹·成长」图标换色功能
        IconThemePlugin(this).registerWith(flutterEngine)
        
        // 注册速记浮窗插件
        // 原生 Android View 实现系统级悬浮窗
        FloatingWindowPlugin(this).registerWith(flutterEngine)

        // 注册课表小组件插件
        // Dart 侧推「未来两周课表计划」进来，原生侧落盘并重画小组件
        CourseWidgetPlugin.install(flutterEngine, this)
    }
}
