package com.example.diary_app

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * 速记浮窗 MethodChannel 插件
 */
class FloatingWindowPlugin(private val context: Context) : MethodCallHandler {

    companion object {
        private const val TAG = "FloatingWindowPlugin"
        const val CHANNEL_NAME = "com.diary_app/floating_window"
        private const val PREFS_NAME = "floating_window_prefs"
        private const val KEY_SERVICE_RUNNING = "service_running"

        private const val ACTION_SHOW = "ACTION_SHOW"
        private const val ACTION_HIDE = "ACTION_HIDE"
        private const val ACTION_SHOW_PANEL = "ACTION_SHOW_PANEL"
        private const val ACTION_HIDE_PANEL = "ACTION_HIDE_PANEL"
        private const val ACTION_UPDATE_SETTINGS = "ACTION_UPDATE_SETTINGS"

        private const val EXTRA_COLOR = "color"
        private const val EXTRA_OPACITY = "opacity"
        private const val EXTRA_POS_X = "posX"
        private const val EXTRA_POS_Y = "posY"
        private const val EXTRA_TAGS = "tags"

        private var methodChannel: MethodChannel? = null

        private fun getPrefs(context: Context): SharedPreferences {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }

        fun setServiceRunning(context: Context, running: Boolean) {
            getPrefs(context).edit().putBoolean(KEY_SERVICE_RUNNING, running).apply()
        }

        fun isServiceRunning(context: Context): Boolean {
            return getPrefs(context).getBoolean(KEY_SERVICE_RUNNING, false)
        }

        fun notifySaveQuickNote(content: String, tag: String): Boolean {
            return try {
                methodChannel?.invokeMethod("onSaveQuickNote", mapOf(
                    "content" to content,
                    "tag" to tag
                ))
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to notify save quick note", e)
                false
            }
        }

        fun notifyPanelShown() {
            try { methodChannel?.invokeMethod("onPanelShown", null) } catch (_: Exception) {}
        }

        fun notifyPanelHidden() {
            try { methodChannel?.invokeMethod("onPanelHidden", null) } catch (_: Exception) {}
        }

        fun notifyPositionChanged(x: Int, y: Int) {
            try {
                methodChannel?.invokeMethod("onPositionChanged", mapOf("x" to x, "y" to y))
            } catch (_: Exception) {}
        }

        fun notifySettingsChanged(color: Int, opacity: Float, sizeDp: Int, iconEmoji: String = "") {
            try {
                val colorHex = String.format("#%06X", 0xFFFFFF and color)
                methodChannel?.invokeMethod("onSettingsChanged", mapOf(
                    "color" to colorHex,
                    "opacity" to opacity,
                    "sizeDp" to sizeDp,
                    "iconEmoji" to iconEmoji
                ))
            } catch (e: Exception) {
                Log.w(TAG, "Failed to notify settings changed", e)
            }
        }

        fun notifyFunctionSettingsChanged(
            syncToNotification: Boolean,
            syncToSelfTalk: Boolean,
            showWordCount: Boolean,
            autoHideToEdge: Boolean,
            doubleTapSensitivityMs: Int,
            fontSize: Int,
            useTags: Boolean
        ) {
            try {
                methodChannel?.invokeMethod("onFunctionSettingsChanged", mapOf(
                    "syncToNotification" to syncToNotification,
                    "syncToSelfTalk" to syncToSelfTalk,
                    "showWordCount" to showWordCount,
                    "autoHideToEdge" to autoHideToEdge,
                    "doubleTapSensitivityMs" to doubleTapSensitivityMs,
                    "fontSize" to fontSize,
                    "useTags" to useTags
                ))
            } catch (e: Exception) {
                Log.w(TAG, "Failed to notify function settings changed", e)
            }
        }

        fun notifyPanelSizeChanged(width: Int, height: Int) {
            try {
                methodChannel?.invokeMethod("onPanelSizeChanged", mapOf(
                    "width" to width,
                    "height" to height
                ))
            } catch (e: Exception) {
                Log.w(TAG, "Failed to notify panel size changed", e)
            }
        }
    }

    fun registerWith(engine: FlutterEngine) {
        methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel?.setMethodCallHandler(this)
        Log.d(TAG, "Plugin registered")
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        Log.d(TAG, "Method called: ${call.method}")
        when (call.method) {
            "showFloatingButton" -> {
                try {
                    val colorHex = call.argument<String>("color") ?: "#FF6B6B"
                    val opacity = call.argument<Double>("opacity")?.toFloat() ?: 1.0f
                    val posX = call.argument<Int>("posX") ?: -1
                    val posY = call.argument<Int>("posY") ?: -1
                    val tags = call.argument<List<String>>("tags")
                    val autoHideToEdge = call.argument<Boolean>("autoHideToEdge") ?: true
                    val doubleTapSensitivityMs = call.argument<Int>("doubleTapSensitivityMs") ?: 300
                    val iconEmoji = call.argument<String>("iconEmoji") ?: ""
                    val windowSize = call.argument<Int>("windowSize") ?: 60

                    val color = parseColor(colorHex)
                    val intent = Intent(context, FloatingWindowService::class.java).apply {
                        action = ACTION_SHOW
                        putExtra(EXTRA_COLOR, color)
                        putExtra(EXTRA_OPACITY, opacity)
                        putExtra(EXTRA_POS_X, posX)
                        putExtra(EXTRA_POS_Y, posY)
                        putExtra("autoHideToEdge", autoHideToEdge)
                        putExtra("doubleTapSensitivityMs", doubleTapSensitivityMs)
                        putExtra("iconEmoji", iconEmoji)
                        putExtra("windowSize", windowSize)
                        if (tags != null) {
                            putExtra(EXTRA_TAGS, tags.toTypedArray())
                        }
                    }
                    startService(intent)
                    setServiceRunning(context, true)
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "showFloatingButton failed", e)
                    result.error("SERVICE_ERROR", e.message, null)
                }
            }
            "hideFloatingWindow" -> {
                try {
                    val intent = Intent(context, FloatingWindowService::class.java).apply {
                        action = ACTION_HIDE
                    }
                    startService(intent)
                    setServiceRunning(context, false)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SERVICE_ERROR", e.message, null)
                }
            }
            "showQuickNotePanel" -> {
                try {
                    val barWidth = call.argument<Int>("barWidth") ?: -1
                    val barHeight = call.argument<Int>("barHeight") ?: -1
                    val fontSize = call.argument<Int>("fontSize") ?: -1
                    val intent = Intent(context, FloatingWindowService::class.java).apply {
                        action = ACTION_SHOW_PANEL
                        putExtra("barWidth", barWidth)
                        putExtra("barHeight", barHeight)
                        putExtra("fontSize", fontSize)
                    }
                    startService(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SERVICE_ERROR", e.message, null)
                }
            }
            "hideQuickNotePanel" -> {
                try {
                    val intent = Intent(context, FloatingWindowService::class.java).apply {
                        action = ACTION_HIDE_PANEL
                    }
                    startService(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SERVICE_ERROR", e.message, null)
                }
            }
            "updateSettings" -> {
                try {
                    val colorHex = call.argument<String>("color") ?: "#FF6B6B"
                    val opacity = call.argument<Double>("opacity")?.toFloat() ?: 1.0f
                    val intent = Intent(context, FloatingWindowService::class.java).apply {
                        action = ACTION_UPDATE_SETTINGS
                        putExtra(EXTRA_COLOR, parseColor(colorHex))
                        putExtra(EXTRA_OPACITY, opacity)
                    }
                    startService(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SERVICE_ERROR", e.message, null)
                }
            }
            "isServiceRunning" -> {
                result.success(isServiceRunning(context))
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun startService(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    private fun parseColor(colorHex: String): Int {
        return try {
            android.graphics.Color.parseColor(colorHex)
        } catch (e: Exception) {
            0xFFFF6B6B.toInt()
        }
    }
}
