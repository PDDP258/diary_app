package com.example.diary_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 注册图标主题插件
        // 「笔迹·成长」图标换色功能
        IconThemePlugin(context).registerWith(flutterEngine)
    }
}
