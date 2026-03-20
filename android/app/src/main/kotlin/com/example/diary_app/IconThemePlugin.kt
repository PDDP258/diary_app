package com.example.diary_app

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * 「笔迹·成长」图标主题插件
 * 
 * 功能：支持动态切换应用桌面图标颜色主题
 * 原理：通过启用/禁用 Activity 别名来实现图标切换
 * 
 * 4种配色：
 * - coral: 珊瑚红（默认）
 * - mint: 青绿色
 * - pink: 樱花粉
 * - starry: 星空主题（商店购买）
 */
class IconThemePlugin(private val context: Context) : MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.diaryapp/icon_theme"
        
        // 支持的图标主题
        private val SUPPORTED_THEMES = listOf(
            "coral",   // 珊瑚红
            "mint",    // 青绿色
            "pink",    // 樱花粉
            "starry"   // 星空主题（商店购买）
        )
    }

    fun registerWith(engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getAvailableThemes" -> {
                result.success(SUPPORTED_THEMES)
            }
            "getCurrentTheme" -> {
                val currentTheme = getCurrentEnabledTheme()
                result.success(currentTheme)
            }
            "setIconTheme" -> {
                val themeName = call.argument<String>("theme")
                if (themeName == null) {
                    result.error("INVALID_ARGUMENT", "Theme name is required", null)
                    return
                }
                
                if (!SUPPORTED_THEMES.contains(themeName)) {
                    result.error("UNSUPPORTED_THEME", "Theme '$themeName' is not supported", null)
                    return
                }
                
                val success = setIconTheme(themeName)
                result.success(success)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * 设置图标主题
     */
    private fun setIconTheme(themeName: String): Boolean {
        return try {
            val packageManager = context.packageManager
            val packageName = context.packageName

            // 禁用所有主题别名
            SUPPORTED_THEMES.forEach { theme ->
                val aliasName = "${packageName}.MainActivity_$theme"
                val componentName = ComponentName(context, aliasName)
                
                try {
                    packageManager.setComponentEnabledSetting(
                        componentName,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP
                    )
                } catch (e: Exception) {
                    // 忽略错误
                }
            }

            // 启用选中的主题别名
            val selectedAlias = "${packageName}.MainActivity_$themeName"
            val selectedComponent = ComponentName(context, selectedAlias)
            
            packageManager.setComponentEnabledSetting(
                selectedComponent,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )

            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    /**
     * 获取当前启用的图标主题
     */
    private fun getCurrentEnabledTheme(): String {
        return try {
            val packageManager = context.packageManager
            val packageName = context.packageName

            SUPPORTED_THEMES.forEach { theme ->
                val aliasName = "${packageName}.MainActivity_$theme"
                val componentName = ComponentName(context, aliasName)
                
                try {
                    val state = packageManager.getComponentEnabledSetting(componentName)
                    if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                        return theme
                    }
                } catch (e: Exception) {
                    // 忽略错误
                }
            }
            
            "coral" // 默认
        } catch (e: Exception) {
            "coral"
        }
    }
}
