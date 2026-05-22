package com.example.diary_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.os.Build
import android.os.IBinder
import android.util.DisplayMetrics
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.Spinner
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import android.animation.ValueAnimator

/**
 * 速记浮窗前台服务
 *
 * 使用原生 Android View 实现系统级悬浮窗。
 * 功能：拖拽、贴边吸附缩小、双击展开面板、设置面板、自定义标签。
 */
class FloatingWindowService : Service() {

    companion object {
        private const val TAG = "FloatingWindowService"
        private const val NOTIFICATION_CHANNEL_ID = "diary_app_floating_window"
        private const val NOTIFICATION_ID = 1001
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

        // 默认标签（会被 Flutter 传来的自定义标签覆盖）
        private var customTags = arrayOf("灵感", "待办", "备忘", "读书", "想法")
    }

    private lateinit var windowManager: WindowManager
    private var floatingButtonView: View? = null
    private var floatingPanelView: View? = null
    private var floatingSettingsView: View? = null
    private var buttonParams: WindowManager.LayoutParams? = null
    private var panelParams: WindowManager.LayoutParams? = null
    private var settingsParams: WindowManager.LayoutParams? = null

    // 拖动状态
    private var initialX = 0
    private var initialY = 0
    private var touchDownX = 0f
    private var touchDownY = 0f
    private var isDragging = false
    private var isPanelShowing = false
    private var isSettingsShowing = false
    private var isPanelAnimatingOut = false

    // 点击检测
    private var lastUpTime = 0L
    private var doubleTapSensitivityMs = 300
    private val LONG_PRESS_DELAY = 500L
    private var isLongPressTriggered = false
    private val longPressHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var longPressRunnable: Runnable? = null

    // 面板自动隐藏
    private val autoHideHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var autoHideRunnable: Runnable? = null
    private var autoHideDelaySeconds = 5

    // 贴边缩小
    private var isCollapsed = false
    private var normalSize = 60
    private var collapsedSize = 24

    // 呼吸动画
    private var breathingAnimator: ValueAnimator? = null
    private var isBreathingPaused = false

    // 设置（默认暖棕色，参考木质风格）
    private var buttonColor = 0xFFC4956A.toInt()
    private var buttonOpacity = 1.0f
    private var buttonSizeDp = 60
    private var savedPosX = -1
    private var savedPosY = -1
    private var autoHideToEdge = true
    private var iconEmoji = ""
    private var savedBarWidth = -1
    private var savedBarHeight = -1
    private var savedFontSize = -1

    // 屏幕尺寸
    private var screenWidth = 0
    private var screenHeight = 0

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        updateScreenSize()

        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        Log.d(TAG, "Foreground service started with notification")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action}")
        when (intent?.action) {
            ACTION_SHOW -> {
                buttonColor = intent.getIntExtra(EXTRA_COLOR, buttonColor)
                buttonOpacity = intent.getFloatExtra(EXTRA_OPACITY, 1.0f)
                savedPosX = intent.getIntExtra(EXTRA_POS_X, -1)
                savedPosY = intent.getIntExtra(EXTRA_POS_Y, -1)
                autoHideToEdge = intent.getBooleanExtra("autoHideToEdge", true)
                doubleTapSensitivityMs = intent.getIntExtra("doubleTapSensitivityMs", 300)
                iconEmoji = intent.getStringExtra("iconEmoji") ?: ""
                buttonSizeDp = intent.getIntExtra("windowSize", buttonSizeDp)
                val tags = intent.getStringArrayExtra(EXTRA_TAGS)
                if (tags != null && tags.isNotEmpty()) {
                    customTags = tags
                }
                showFloatingButton()
            }
            ACTION_HIDE -> hideAll()
            ACTION_SHOW_PANEL -> {
                savedBarWidth = intent.getIntExtra("barWidth", -1)
                savedBarHeight = intent.getIntExtra("barHeight", -1)
                savedFontSize = intent.getIntExtra("fontSize", -1)
                showPanel()
            }
            ACTION_HIDE_PANEL -> hidePanel()
            ACTION_UPDATE_SETTINGS -> {
                buttonColor = intent.getIntExtra(EXTRA_COLOR, buttonColor)
                buttonOpacity = intent.getFloatExtra(EXTRA_OPACITY, 1.0f)
                updateButtonAppearance()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy")
        hideAll()
        FloatingWindowPlugin.setServiceRunning(this, false)
    }

    private fun updateScreenSize() {
        val metrics = DisplayMetrics()
        windowManager.defaultDisplay.getMetrics(metrics)
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
        Log.d(TAG, "Screen size: ${screenWidth}x${screenHeight}")
    }

    // ==================== 通知 ====================

    private fun createNotification(): Notification {
        val channelName = "速记浮窗"
        val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                channelName,
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "保持速记浮窗在后台运行"
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("小记速记浮窗运行中")
            .setContentText("点击返回应用")
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    // ==================== 浮窗按钮 ====================

    private fun showFloatingButton() {
        if (floatingButtonView != null) {
            Log.d(TAG, "Button already showing")
            return
        }

        Log.d(TAG, "Creating floating button, color=${Integer.toHexString(buttonColor)}, opacity=$buttonOpacity, size=${buttonSizeDp}dp")

        try {
            val inflater = getSystemService(LAYOUT_INFLATER_SERVICE) as LayoutInflater
            val view = inflater.inflate(R.layout.floating_button, null)
            floatingButtonView = view

            if (view == null) {
                Log.e(TAG, "Failed to inflate floating_button layout")
                return
            }

            val btn = view.findViewById<ImageButton>(R.id.floating_button)
                ?: run { Log.e(TAG, "floating_button not found"); return }

            updateButtonAppearance()

            // 触摸事件统一处理（双击展开面板、长按打开主应用、拖动）
            // 必须设置在 ImageButton 上，不能设置在父 FrameLayout 上，
            // 否则 ImageButton 的 click listener 会消费事件导致父布局收不到触摸
            btn.setOnTouchListener { _, event ->
                handleButtonTouch(event)
            }

            val size = dpToPx(buttonSizeDp)
            buttonParams = WindowManager.LayoutParams(
                size,
                size,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = if (savedPosX >= 0) savedPosX else screenWidth - size - dpToPx(16)
                y = if (savedPosY >= 0) savedPosY else screenHeight / 2
            }

            windowManager.addView(view, buttonParams)
            // 启动呼吸动画
            startBreathingAnimation()
            Log.d(TAG, "Floating button ADDED at (${buttonParams!!.x}, ${buttonParams!!.y})")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add floating button", e)
            floatingButtonView = null
            buttonParams = null
        }
    }

    private fun updateButtonAppearance() {
        val view = floatingButtonView ?: return
        val btn = view.findViewById<ImageButton>(R.id.floating_button) ?: return

        // ===== 图片图标模式：使用生成的图片作为完整按钮外观 =====
        if (iconEmoji == "💡") {
            btn.setImageResource(R.drawable.icon_bulb)
            btn.scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            btn.setBackgroundResource(0) // 彻底清除背景
            btn.imageTintList = null // 清除 tint，避免图片被染色
            btn.clearColorFilter()
            view.alpha = buttonOpacity.coerceIn(0.2f, 1.0f)
            return
        }

        // ===== 代码绘制模式：木质风格渐变背景 + emoji/图标 =====
        val sizePx = dpToPx(buttonSizeDp)
        val cornerRadius = sizePx * 0.25f

        // 层1：柔和阴影
        val shadowDrawable = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            this.cornerRadius = cornerRadius
            setColor(0x20000000)
        }

        // 层2：外框层（用户选择的颜色，温暖渐变模拟木质感）
        val frameDrawable = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            this.cornerRadius = cornerRadius
            colors = intArrayOf(
                lightenColor(buttonColor, 1.1f),
                buttonColor,
                darkenColor(buttonColor, 0.8f)
            )
            orientation = GradientDrawable.Orientation.TL_BR
        }

        // 层3：内部浅色层（形成内凹效果，类似图片的米色内部）
        val innerPadding = (sizePx * 0.14f).toInt().coerceAtLeast(dpToPx(4))
        val innerCornerRadius = cornerRadius * 0.65f
        val innerColor = blendWithWhite(buttonColor, 0.72f)
        val innerDrawable = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            this.cornerRadius = innerCornerRadius
            colors = intArrayOf(
                lightenColor(innerColor, 1.06f),
                innerColor
            )
            orientation = GradientDrawable.Orientation.TL_BR
        }

        // 组合三层：阴影 → 外框 → 内部
        val layerDrawable = LayerDrawable(arrayOf(shadowDrawable, frameDrawable, innerDrawable)).apply {
            setLayerInset(0, dpToPx(2), dpToPx(5), dpToPx(2), 0)
            setLayerInset(1, 0, 0, 0, dpToPx(3))
            setLayerInset(2, innerPadding, innerPadding, innerPadding, innerPadding + dpToPx(3))
        }

        btn.background = layerDrawable

        // 设置图标（emoji 或默认系统图标）
        if (iconEmoji.isNotEmpty()) {
            btn.setImageDrawable(createEmojiDrawable(iconEmoji, dpToPx(28), 0xFF8B5E3C.toInt()))
        } else {
            btn.setImageResource(android.R.drawable.ic_menu_edit)
        }
        btn.scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
        btn.imageTintList = null
        btn.clearColorFilter()

        // 设置整体透明度（在 View 上设置，不在 LayoutParams 上设置，避免触摸失效）
        view.alpha = buttonOpacity.coerceIn(0.2f, 1.0f)
    }

    /**
     * 将颜色与白色混合，生成协调的浅色
     */
    private fun blendWithWhite(color: Int, ratio: Float): Int {
        val a = android.graphics.Color.alpha(color)
        val r = (android.graphics.Color.red(color) * (1 - ratio) + 255 * ratio).toInt().coerceIn(0, 255)
        val g = (android.graphics.Color.green(color) * (1 - ratio) + 255 * ratio).toInt().coerceIn(0, 255)
        val b = (android.graphics.Color.blue(color) * (1 - ratio) + 255 * ratio).toInt().coerceIn(0, 255)
        return android.graphics.Color.argb(a, r, g, b)
    }

    /**
     * 加深颜色
     */
    private fun darkenColor(color: Int, factor: Float): Int {
        val a = android.graphics.Color.alpha(color)
        val r = (android.graphics.Color.red(color) * factor).toInt().coerceIn(0, 255)
        val g = (android.graphics.Color.green(color) * factor).toInt().coerceIn(0, 255)
        val b = (android.graphics.Color.blue(color) * factor).toInt().coerceIn(0, 255)
        return android.graphics.Color.argb(a, r, g, b)
    }

    /**
     * 减淡颜色
     */
    private fun lightenColor(color: Int, factor: Float): Int {
        val a = android.graphics.Color.alpha(color)
        val r = (android.graphics.Color.red(color) * factor).toInt().coerceIn(0, 255)
        val g = (android.graphics.Color.green(color) * factor).toInt().coerceIn(0, 255)
        val b = (android.graphics.Color.blue(color) * factor).toInt().coerceIn(0, 255)
        return android.graphics.Color.argb(a, r, g, b)
    }

    // ==================== 呼吸动画 ====================

    private fun startBreathingAnimation() {
        if (breathingAnimator?.isRunning == true) return
        val btn = floatingButtonView?.findViewById<ImageButton>(R.id.floating_button) ?: return

        breathingAnimator = ValueAnimator.ofFloat(1.0f, 1.06f, 1.0f).apply {
            duration = 2200
            repeatCount = ValueAnimator.INFINITE
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animator ->
                if (!isBreathingPaused) {
                    val scale = animator.animatedValue as Float
                    btn.scaleX = scale
                    btn.scaleY = scale
                }
            }
            start()
        }
    }

    private fun pauseBreathingAnimation() {
        isBreathingPaused = true
        val btn = floatingButtonView?.findViewById<ImageButton>(R.id.floating_button) ?: return
        btn.animate()
            .scaleX(1.0f)
            .scaleY(1.0f)
            .setDuration(150)
            .start()
    }

    private fun resumeBreathingAnimation() {
        isBreathingPaused = false
    }

    private fun stopBreathingAnimation() {
        breathingAnimator?.cancel()
        breathingAnimator = null
    }

    private fun createColorCircle(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
        }
    }

    /**
     * 创建带选中效果的颜色圆形（白色边框 + 外圈阴影）
     */
    private fun createColorCircleWithBorder(color: Int): android.graphics.drawable.LayerDrawable {
        // 外圈阴影
        val shadow = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(0x20000000)
        }
        // 颜色圆
        val circle = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
            setStroke(dpToPx(3), 0xFFFFFFFF.toInt())
        }
        return LayerDrawable(arrayOf(shadow, circle)).apply {
            setLayerInset(0, 0, dpToPx(2), 0, dpToPx(2))
            setLayerInset(1, dpToPx(2), 0, dpToPx(2), dpToPx(4))
        }
    }

    /**
     * 创建精美的 emoji 图标 Drawable
     * 直接在按钮内部浅色区域上绘制清晰的 emoji，无额外背景
     */
    private fun createEmojiDrawable(emoji: String, sizePx: Int, textColor: Int): android.graphics.drawable.BitmapDrawable {
        val bitmap = android.graphics.Bitmap.createBitmap(sizePx, sizePx, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)

        // 绘制 emoji（更大更清晰）
        val paint = android.graphics.Paint().apply {
            textSize = sizePx * 0.58f
            color = textColor
            textAlign = android.graphics.Paint.Align.CENTER
            isAntiAlias = true
        }
        val x = sizePx / 2f
        val y = sizePx / 2f + (paint.textSize * 0.38f)
        canvas.drawText(emoji, x, y, paint)

        return android.graphics.drawable.BitmapDrawable(resources, bitmap)
    }

    private fun resizeButton(targetSizeDp: Int, animated: Boolean = true) {
        val view = floatingButtonView ?: return
        val btn = view.findViewById<ImageButton>(R.id.floating_button) ?: return
        val params = buttonParams ?: return
        val targetSize = dpToPx(targetSizeDp)
        val currentSize = params.width

        // 根据目标大小调整 padding（小圆点时 padding 也要小）
        val targetPadding = when {
            targetSizeDp <= 30 -> dpToPx(3)
            targetSizeDp <= 48 -> dpToPx(8)
            else -> dpToPx(14)
        }

        if (animated) {
            val startPadding = btn.paddingTop
            val animator = ValueAnimator.ofInt(currentSize, targetSize)
            animator.duration = 200
            animator.interpolator = AccelerateDecelerateInterpolator()
            animator.addUpdateListener { animation ->
                val newSize = animation.animatedValue as Int
                val fraction = animation.animatedFraction
                params.width = newSize
                params.height = newSize
                // 同步调整 padding
                val newPadding = (startPadding + (targetPadding - startPadding) * fraction).toInt()
                btn.setPadding(newPadding, newPadding, newPadding, newPadding)
                try {
                    windowManager.updateViewLayout(view, params)
                } catch (_: Exception) {}
            }
            animator.addListener(object : android.animation.Animator.AnimatorListener {
                override fun onAnimationStart(animation: android.animation.Animator) {}
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    updateButtonAppearance()
                }
                override fun onAnimationCancel(animation: android.animation.Animator) {}
                override fun onAnimationRepeat(animation: android.animation.Animator) {}
            })
            animator.start()
        } else {
            params.width = targetSize
            params.height = targetSize
            btn.setPadding(targetPadding, targetPadding, targetPadding, targetPadding)
            try {
                windowManager.updateViewLayout(view, params)
            } catch (_: Exception) {}
        }
    }

    private fun collapseButton() {
        if (isCollapsed) return
        isCollapsed = true
        resizeButton(collapsedSize)
        Log.d(TAG, "Button collapsed")
    }

    private fun expandButton() {
        if (!isCollapsed) return
        isCollapsed = false
        resizeButton(buttonSizeDp)
        resumeBreathingAnimation()
        Log.d(TAG, "Button expanded")
    }

    private fun handleButtonTouch(event: MotionEvent): Boolean {
        val params = buttonParams ?: return false
        val view = floatingButtonView ?: return false

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                initialX = params.x
                initialY = params.y
                touchDownX = event.rawX
                touchDownY = event.rawY
                isDragging = false
                isLongPressTriggered = false

                // 暂停呼吸动画
                pauseBreathingAnimation()

                // 拖动时自动展开
                if (isCollapsed) {
                    expandButton()
                }

                // 启动长按检测
                longPressRunnable = Runnable {
                    if (!isDragging && !isLongPressTriggered) {
                        isLongPressTriggered = true
                        // 长按震动反馈
                        view.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
                        openMainApp()
                    }
                }
                longPressHandler.postDelayed(longPressRunnable!!, LONG_PRESS_DELAY)

                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val deltaX = (event.rawX - touchDownX).toInt()
                val deltaY = (event.rawY - touchDownY).toInt()

                if (kotlin.math.abs(deltaX) > 10 || kotlin.math.abs(deltaY) > 10) {
                    if (!isDragging) {
                        isDragging = true
                        // 开始拖动，取消长按检测
                        longPressRunnable?.let { longPressHandler.removeCallbacks(it) }
                    }
                }

                params.x = initialX + deltaX
                params.y = initialY + deltaY
                windowManager.updateViewLayout(floatingButtonView, params)
                return true
            }
            MotionEvent.ACTION_UP -> {
                // 取消长按检测
                longPressRunnable?.let { longPressHandler.removeCallbacks(it) }

                if (isDragging) {
                    // 拖动结束，贴边吸附
                    snapToEdge()
                    savePosition(params.x, params.y)
                    // 贴边后暂停呼吸动画
                    pauseBreathingAnimation()
                } else if (!isLongPressTriggered) {
                    // 没有拖动，也不是长按 → 处理点击/双击
                    val now = System.currentTimeMillis()
                    if (now - lastUpTime < doubleTapSensitivityMs && lastUpTime > 0) {
                        // 双击：展开/收起面板
                        view.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
                        togglePanel()
                    }
                    lastUpTime = now
                }
                return true
            }
        }
        return false
    }

    private fun snapToEdge() {
        if (!autoHideToEdge) return
        val params = buttonParams ?: return
        val view = floatingButtonView ?: return
        val btn = view.findViewById<ImageButton>(R.id.floating_button) ?: return

        // 判断贴左边还是右边
        val isLeftSide = params.x + params.width / 2 < screenWidth / 2

        // 目标尺寸和位置（缩小后）
        val targetSize = dpToPx(collapsedSize)
        val margin = dpToPx(2) // 小边距，让圆点几乎贴边
        val targetX = if (isLeftSide) margin else screenWidth - targetSize - margin
        val targetPadding = dpToPx(3)

        // 同时动画：移动 + 缩小
        val animator = ValueAnimator.ofFloat(0f, 1f)
        animator.duration = 250
        animator.interpolator = AccelerateDecelerateInterpolator()

        val startX = params.x
        val startSize = params.width
        val startPadding = btn.paddingTop

        animator.addUpdateListener { animation ->
            val fraction = animation.animatedValue as Float
            // 位置
            params.x = (startX + (targetX - startX) * fraction).toInt()
            // 大小
            val newSize = (startSize + (targetSize - startSize) * fraction).toInt()
            params.width = newSize
            params.height = newSize
            // padding
            val newPadding = (startPadding + (targetPadding - startPadding) * fraction).toInt()
            btn.setPadding(newPadding, newPadding, newPadding, newPadding)
            try {
                windowManager.updateViewLayout(view, params)
            } catch (_: Exception) {}
        }

        animator.addListener(object : android.animation.Animator.AnimatorListener {
            override fun onAnimationStart(animation: android.animation.Animator) {}
            override fun onAnimationEnd(animation: android.animation.Animator) {
                isCollapsed = true
                pauseBreathingAnimation()
                updateButtonAppearance() // 确保缩小后外观正确（清除背景/tint等）
                view.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY)
                Log.d(TAG, "Snap animation done, button collapsed to ${params.x},${params.y}")
            }
            override fun onAnimationCancel(animation: android.animation.Animator) {}
            override fun onAnimationRepeat(animation: android.animation.Animator) {}
        })

        animator.start()
    }

    // ==================== 速记面板 ====================

    private fun togglePanel() {
        if (isPanelShowing) hidePanel() else showPanel()
    }

    private fun showPanel() {
        if (floatingPanelView != null) return
        if (floatingButtonView == null) return
        // 如果设置面板已打开，先关闭
        if (isSettingsShowing) hideSettingsPanel()

        try {
            val inflater = getSystemService(LAYOUT_INFLATER_SERVICE) as LayoutInflater
            val view = inflater.inflate(R.layout.floating_panel, null)
            floatingPanelView = view

            if (view == null) {
                Log.e(TAG, "Failed to inflate floating_panel layout")
                return
            }

            val spinner = view.findViewById<Spinner>(R.id.spinner_tag)
                ?: run { Log.e(TAG, "spinner_tag not found"); return }
            val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_item, customTags)
            adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            spinner.adapter = adapter

            // 根据设置控制标签显示/隐藏
            val panelPrefs = getSharedPreferences("flutter_floating_window_settings", Context.MODE_PRIVATE)
            val useTags = panelPrefs.getBoolean("useTags", true)
            if (!useTags) {
                spinner.visibility = View.GONE
            }

            val etContent = view.findViewById<EditText>(R.id.et_quick_note)
                ?: run { Log.e(TAG, "et_quick_note not found"); return }
            val tvWordCount = view.findViewById<TextView>(R.id.tv_word_count)
                ?: run { Log.e(TAG, "tv_word_count not found"); return }

            // 应用字体大小设置
            if (savedFontSize > 0) {
                etContent.textSize = savedFontSize.toFloat()
            }

            // 粘贴按钮
            val btnPaste = view.findViewById<TextView>(R.id.btn_paste)
            btnPaste?.setOnClickListener {
                val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                if (clipboard.hasPrimaryClip()) {
                    val clip = clipboard.primaryClip
                    if (clip != null && clip.itemCount > 0) {
                        val text = clip.getItemAt(0).text?.toString() ?: ""
                        etContent.append(text)
                    }
                }
            }

            // 关闭按钮
            val btnClosePanel = view.findViewById<TextView>(R.id.btn_close_panel)
            btnClosePanel?.setOnClickListener { hidePanel() }

            // 设置按钮
            val btnSettings = view.findViewById<TextView>(R.id.btn_settings)
            btnSettings?.setOnClickListener { showSettingsPanel() }

            // 保存按钮
            val btnSave = view.findViewById<TextView>(R.id.btn_save)
            btnSave?.setOnClickListener {
                val content = etContent.text.toString().trim()
                if (content.isEmpty()) {
                    Toast.makeText(this, "内容不能为空", Toast.LENGTH_SHORT).show()
                    return@setOnClickListener
                }
                val tag = spinner.selectedItem?.toString() ?: ""
                saveQuickNote(content, tag)
                view.performHapticFeedback(android.view.HapticFeedbackConstants.CONFIRM)
                etContent.setText("")
                hidePanel()
            }

            val panelWidth = if (savedBarWidth > 0) savedBarWidth else dpToPx(320).coerceAtMost(screenWidth - dpToPx(32))
            val panelHeight = if (savedBarHeight > 0) savedBarHeight else WindowManager.LayoutParams.WRAP_CONTENT
            panelParams = WindowManager.LayoutParams(
                panelWidth,
                panelHeight,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                val btnParams = buttonParams
                if (btnParams != null) {
                    x = (btnParams.x - panelWidth / 2 + dpToPx(30)).coerceIn(dpToPx(8), screenWidth - panelWidth - dpToPx(8))
                    y = (btnParams.y - dpToPx(200)).coerceIn(dpToPx(8), screenHeight - dpToPx(300))
                } else {
                    x = dpToPx(16)
                    y = screenHeight / 3
                }
            }

            // 拖动横杠（调节面板大小）
            val dragHandle = view.findViewById<View>(R.id.drag_handle)
            var dragStartX = 0f
            var dragStartY = 0f
            var initialPanelWidth = 0
            var initialPanelHeight = 0
            dragHandle?.setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        dragStartX = event.rawX
                        dragStartY = event.rawY
                        initialPanelWidth = panelParams?.width ?: dpToPx(320)
                        initialPanelHeight = panelParams?.height ?: dpToPx(200)
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val params = panelParams ?: return@setOnTouchListener false
                        val deltaX = (event.rawX - dragStartX).toInt()
                        val deltaY = (event.rawY - dragStartY).toInt()

                        val minWidth = dpToPx(200)
                        val maxWidth = screenWidth - dpToPx(32)
                        val minHeight = dpToPx(120)
                        val maxHeight = screenHeight / 2

                        params.width = (initialPanelWidth + deltaX).coerceIn(minWidth, maxWidth)
                        params.height = (initialPanelHeight + deltaY).coerceIn(minHeight, maxHeight)
                        try {
                            windowManager.updateViewLayout(view, params)
                        } catch (_: Exception) {}
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        val params = panelParams
                        if (params != null) {
                            FloatingWindowPlugin.notifyPanelSizeChanged(
                                params.width,
                                params.height
                            )
                        }
                        true
                    }
                    else -> false
                }
            }

            // 自动隐藏定时器
            autoHideDelaySeconds = panelPrefs.getInt("autoHideDelaySeconds", 5)
            val autoHideEnabled = panelPrefs.getBoolean("autoHideBar", false)

            fun resetAutoHideTimer() {
                autoHideRunnable?.let { autoHideHandler.removeCallbacks(it) }
                if (autoHideEnabled && autoHideDelaySeconds > 0) {
                    autoHideRunnable = Runnable {
                        if (isPanelShowing) {
                            hidePanel()
                            Toast.makeText(this, "速记面板已自动收起", Toast.LENGTH_SHORT).show()
                        }
                    }
                    autoHideHandler.postDelayed(autoHideRunnable!!, autoHideDelaySeconds * 1000L)
                }
            }

            // 启动自动隐藏
            if (autoHideEnabled) resetAutoHideTimer()

            // 在面板交互中重置定时器
            etContent.addTextChangedListener(object : android.text.TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                override fun afterTextChanged(s: android.text.Editable?) {
                    val length = s?.length ?: 0
                    tvWordCount.text = "${length}字"
                    if (autoHideEnabled) resetAutoHideTimer()
                }
            })

            // 为面板根布局添加触摸监听以重置定时器
            view.setOnTouchListener { _, event ->
                if (event.action == MotionEvent.ACTION_DOWN && autoHideEnabled) {
                    resetAutoHideTimer()
                }
                false
            }

            // 展开动画：先设为不可见，addView 后再淡入缩放
            view.alpha = 0f
            view.scaleX = 0.92f
            view.scaleY = 0.92f

            windowManager.addView(view, panelParams)

            // 延迟一帧开始动画，避免 addView 瞬间的闪烁
            view.post {
                view.animate()
                    .alpha(1f)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(180)
                    .setInterpolator(AccelerateDecelerateInterpolator())
                    .start()
            }

            isPanelShowing = true
            isPanelAnimatingOut = false
            FloatingWindowPlugin.notifyPanelShown()
            Log.d(TAG, "Panel ADDED")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show panel", e)
            floatingPanelView = null
            panelParams = null
            Toast.makeText(this, "面板打开失败: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun hidePanel() {
        if (isPanelAnimatingOut) return
        autoHideRunnable?.let { autoHideHandler.removeCallbacks(it) }
        autoHideRunnable = null
        val view = floatingPanelView ?: return
        isPanelAnimatingOut = true
        // 收起动画（淡出+缩放）
        view.animate()
            .alpha(0f)
            .scaleX(0.9f)
            .scaleY(0.9f)
            .setDuration(150)
            .withEndAction {
                try {
                    windowManager.removeView(view)
                } catch (_: Exception) {}
                floatingPanelView = null
                isPanelShowing = false
                isPanelAnimatingOut = false
                FloatingWindowPlugin.notifyPanelHidden()
            }
            .start()
    }

    // ==================== 设置面板 ====================

    private fun showSettingsPanel() {
        if (floatingSettingsView != null) return
        if (floatingButtonView == null) return
        // 关闭速记面板（如果打开）
        if (isPanelShowing) hidePanel()

        try {
            val inflater = getSystemService(LAYOUT_INFLATER_SERVICE) as LayoutInflater
            val view = inflater.inflate(R.layout.floating_settings_panel, null)
            floatingSettingsView = view

            if (view == null) {
                Log.e(TAG, "Failed to inflate settings panel")
                return
            }

            // 关闭按钮
            val btnClose = view.findViewById<TextView>(R.id.btn_close_settings)
            btnClose?.setOnClickListener { hideSettingsPanel() }

            // 颜色选择（带选中边框）
            val colors = mapOf(
                R.id.color_red to 0xFFFF6B6B.toInt(),
                R.id.color_purple to 0xFF7C4DFF.toInt(),
                R.id.color_blue to 0xFF448AFF.toInt(),
                R.id.color_green to 0xFF66BB6A.toInt(),
                R.id.color_orange to 0xFFFFA726.toInt(),
                R.id.color_pink to 0xFFEC407A.toInt()
            )

            fun updateColorSelection(selectedView: View?) {
                colors.keys.forEach { viewId ->
                    val v = view.findViewById<View>(viewId)
                    if (v == selectedView) {
                        v?.background = createColorCircleWithBorder(colors[viewId] ?: buttonColor)
                    } else {
                        v?.background = createColorCircle(colors[viewId] ?: buttonColor)
                    }
                }
            }

            colors.forEach { (viewId, color) ->
                val colorView = view.findViewById<View>(viewId)
                // 初始化背景
                colorView?.background = if (color == buttonColor)
                    createColorCircleWithBorder(color) else createColorCircle(color)

                colorView?.setOnClickListener { clickedView ->
                    buttonColor = color
                    updateButtonAppearance()
                    updateColorSelection(clickedView)
                    FloatingWindowPlugin.notifySettingsChanged(buttonColor, buttonOpacity, buttonSizeDp, iconEmoji)
                    Toast.makeText(this, "颜色已更新", Toast.LENGTH_SHORT).show()
                }
            }

            // 透明度滑块
            val seekBar = view.findViewById<SeekBar>(R.id.seekbar_opacity)
            val tvOpacity = view.findViewById<TextView>(R.id.tv_opacity_value)
            seekBar?.progress = (buttonOpacity * 100).toInt()
            tvOpacity?.text = "${(buttonOpacity * 100).toInt()}%"
            seekBar?.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                    buttonOpacity = progress / 100f
                    tvOpacity?.text = "${progress}%"
                    updateButtonAppearance()
                }
                override fun onStartTrackingTouch(seekBar: SeekBar?) {}
                override fun onStopTrackingTouch(seekBar: SeekBar?) {
                    FloatingWindowPlugin.notifySettingsChanged(buttonColor, buttonOpacity, buttonSizeDp, iconEmoji)
                }
            })

            // 大小选择（带选中状态）
            val sizeMap = mapOf(
                R.id.btn_size_small to 48,
                R.id.btn_size_medium to 60,
                R.id.btn_size_large to 72
            )

            fun updateSizeSelection(selectedId: Int) {
                sizeMap.forEach { (viewId, _) ->
                    val sizeBtn = view.findViewById<TextView>(viewId)
                    if (viewId == selectedId) {
                        sizeBtn?.setBackgroundResource(R.drawable.bg_size_option_selected)
                        sizeBtn?.setTextColor(0xFFFFFFFF.toInt())
                    } else {
                        sizeBtn?.setBackgroundResource(R.drawable.bg_size_option)
                        sizeBtn?.setTextColor(0xFF666666.toInt())
                    }
                }
            }

            // 初始化选中状态
            val currentSizeId = when (buttonSizeDp) {
                48 -> R.id.btn_size_small
                72 -> R.id.btn_size_large
                else -> R.id.btn_size_medium
            }
            updateSizeSelection(currentSizeId)

            sizeMap.forEach { (viewId, sizeDp) ->
                val sizeBtn = view.findViewById<TextView>(viewId)
                sizeBtn?.setOnClickListener {
                    buttonSizeDp = sizeDp
                    resizeButton(buttonSizeDp)
                    updateSizeSelection(viewId)
                    FloatingWindowPlugin.notifySettingsChanged(buttonColor, buttonOpacity, buttonSizeDp, iconEmoji)
                    Toast.makeText(this, "大小已更新", Toast.LENGTH_SHORT).show()
                }
            }

            // ===== 图标选择器 =====
            val iconMap = mapOf(
                R.id.icon_default to "",
                R.id.icon_bulb to "💡",
                R.id.icon_note to "📝",
                R.id.icon_pin to "📌",
                R.id.icon_bell to "🔔",
                R.id.icon_star to "⭐",
                R.id.icon_moon to "🌙",
                R.id.icon_sun to "☀️",
                R.id.icon_flower to "🌸",
                R.id.icon_fire to "🔥",
                R.id.icon_diamond to "💎",
                R.id.icon_target to "🎯"
            )

            fun updateIconSelection(selectedId: Int) {
                iconMap.forEach { (viewId, _) ->
                    val iconBtn = view.findViewById<TextView>(viewId)
                    if (viewId == selectedId) {
                        iconBtn?.setBackgroundResource(R.drawable.bg_icon_option_selected)
                        iconBtn?.animate()?.scaleX(1.1f)?.scaleY(1.1f)?.setDuration(150)?.start()
                    } else {
                        iconBtn?.setBackgroundResource(R.drawable.bg_icon_option)
                        iconBtn?.animate()?.scaleX(1.0f)?.scaleY(1.0f)?.setDuration(150)?.start()
                    }
                }
            }

            // 初始化选中状态
            val currentIconId = iconMap.entries.find { it.value == iconEmoji }?.key ?: R.id.icon_default
            updateIconSelection(currentIconId)

            iconMap.forEach { (viewId, emoji) ->
                val iconBtn = view.findViewById<TextView>(viewId)
                iconBtn?.setOnClickListener {
                    iconEmoji = emoji
                    updateButtonAppearance()
                    updateIconSelection(viewId)
                    FloatingWindowPlugin.notifySettingsChanged(buttonColor, buttonOpacity, buttonSizeDp, iconEmoji)
                    Toast.makeText(this, "图标已更新", Toast.LENGTH_SHORT).show()
                }
            }

            // ===== Tab 切换（底部指示器样式） =====
            val pageAppearance = view.findViewById<LinearLayout>(R.id.page_appearance)
            val pageFunction = view.findViewById<LinearLayout>(R.id.page_function)
            val tabAppearance = view.findViewById<TextView>(R.id.tab_appearance)
            val tabFunction = view.findViewById<TextView>(R.id.tab_function)
            val indicatorAppearance = view.findViewById<View>(R.id.tab_indicator_appearance)
            val indicatorFunction = view.findViewById<View>(R.id.tab_indicator_function)

            fun switchTab(isAppearance: Boolean) {
                if (isAppearance) {
                    pageAppearance?.visibility = View.VISIBLE
                    pageFunction?.visibility = View.GONE
                    tabAppearance?.setTextColor(0xFF1A1A1A.toInt())
                    tabAppearance?.setTypeface(null, android.graphics.Typeface.BOLD)
                    indicatorAppearance?.visibility = View.VISIBLE
                    tabFunction?.setTextColor(0xFF999999.toInt())
                    tabFunction?.setTypeface(null, android.graphics.Typeface.NORMAL)
                    indicatorFunction?.visibility = View.INVISIBLE
                } else {
                    pageAppearance?.visibility = View.GONE
                    pageFunction?.visibility = View.VISIBLE
                    tabAppearance?.setTextColor(0xFF999999.toInt())
                    tabAppearance?.setTypeface(null, android.graphics.Typeface.NORMAL)
                    indicatorAppearance?.visibility = View.INVISIBLE
                    tabFunction?.setTextColor(0xFF1A1A1A.toInt())
                    tabFunction?.setTypeface(null, android.graphics.Typeface.BOLD)
                    indicatorFunction?.visibility = View.VISIBLE
                }
            }

            tabAppearance?.setOnClickListener { switchTab(true) }
            tabFunction?.setOnClickListener { switchTab(false) }

            // ===== 功能设置 =====
            // 从 SharedPreferences 读取当前功能设置（Flutter 侧保存的）
            val prefs = getSharedPreferences("flutter_floating_window_settings", Context.MODE_PRIVATE)

            val switchUseTags = view.findViewById<Switch>(R.id.switch_use_tags)
            val switchSyncNotif = view.findViewById<Switch>(R.id.switch_sync_notification)
            val switchSyncSelfTalk = view.findViewById<Switch>(R.id.switch_sync_self_talk)
            val switchShowWordCount = view.findViewById<Switch>(R.id.switch_show_word_count)
            val switchAutoHideEdge = view.findViewById<Switch>(R.id.switch_auto_hide_edge)
            val seekBarDoubleTap = view.findViewById<SeekBar>(R.id.seekbar_double_tap)
            val tvDoubleTapValue = view.findViewById<TextView>(R.id.tv_double_tap_value)

            // 初始化值（默认 true, true, true, true, true, 300）
            switchUseTags?.isChecked = prefs.getBoolean("useTags", true)
            switchSyncNotif?.isChecked = prefs.getBoolean("syncToNotification", true)
            switchSyncSelfTalk?.isChecked = prefs.getBoolean("syncToSelfTalk", true)
            switchShowWordCount?.isChecked = prefs.getBoolean("showWordCount", true)
            switchAutoHideEdge?.isChecked = prefs.getBoolean("autoHideToEdge", true)
            val savedDoubleTap = prefs.getInt("doubleTapSensitivityMs", 300)
            seekBarDoubleTap?.progress = savedDoubleTap - 100
            tvDoubleTapValue?.text = "${savedDoubleTap}ms"

            val seekBarFontSize = view.findViewById<SeekBar>(R.id.seekbar_font_size)
            val tvFontSizeValue = view.findViewById<TextView>(R.id.tv_font_size_value)
            val savedFontSize = prefs.getInt("fontSize", 15)
            seekBarFontSize?.progress = savedFontSize - 12
            tvFontSizeValue?.text = "${savedFontSize}sp"

            // 功能设置变更监听
            fun notifyFunctionSettings() {
                FloatingWindowPlugin.notifyFunctionSettingsChanged(
                    syncToNotification = switchSyncNotif?.isChecked ?: true,
                    syncToSelfTalk = switchSyncSelfTalk?.isChecked ?: true,
                    showWordCount = switchShowWordCount?.isChecked ?: true,
                    autoHideToEdge = switchAutoHideEdge?.isChecked ?: true,
                    doubleTapSensitivityMs = (seekBarDoubleTap?.progress ?: 200) + 100,
                    fontSize = (seekBarFontSize?.progress ?: 3) + 12,
                    useTags = switchUseTags?.isChecked ?: true
                )
            }

            switchUseTags?.setOnCheckedChangeListener { _, _ -> notifyFunctionSettings() }
            switchSyncNotif?.setOnCheckedChangeListener { _, _ -> notifyFunctionSettings() }
            switchSyncSelfTalk?.setOnCheckedChangeListener { _, _ -> notifyFunctionSettings() }
            switchShowWordCount?.setOnCheckedChangeListener { _, _ -> notifyFunctionSettings() }
            switchAutoHideEdge?.setOnCheckedChangeListener { _, _ ->
                autoHideToEdge = switchAutoHideEdge.isChecked
                notifyFunctionSettings()
            }
            seekBarDoubleTap?.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                    val ms = progress + 100
                    tvDoubleTapValue?.text = "${ms}ms"
                    doubleTapSensitivityMs = ms
                }
                override fun onStartTrackingTouch(seekBar: SeekBar?) {}
                override fun onStopTrackingTouch(seekBar: SeekBar?) {
                    notifyFunctionSettings()
                }
            })

            seekBarFontSize?.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                    val size = progress + 12
                    tvFontSizeValue?.text = "${size}sp"
                }
                override fun onStartTrackingTouch(seekBar: SeekBar?) {}
                override fun onStopTrackingTouch(seekBar: SeekBar?) {
                    notifyFunctionSettings()
                }
            })

            val panelWidth = dpToPx(280).coerceAtMost(screenWidth - dpToPx(32))
            settingsParams = WindowManager.LayoutParams(
                panelWidth,
                WindowManager.LayoutParams.WRAP_CONTENT,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                val btnParams = buttonParams
                if (btnParams != null) {
                    x = (btnParams.x - panelWidth / 2 + dpToPx(30)).coerceIn(dpToPx(8), screenWidth - panelWidth - dpToPx(8))
                    y = (btnParams.y - dpToPx(280)).coerceIn(dpToPx(8), screenHeight - dpToPx(350))
                } else {
                    x = dpToPx(16)
                    y = screenHeight / 3
                }
            }

            // 展开动画
            view.alpha = 0f
            view.scaleX = 0.95f
            view.scaleY = 0.95f

            windowManager.addView(view, settingsParams)

            view.post {
                view.animate()
                    .alpha(1f)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(150)
                    .setInterpolator(AccelerateDecelerateInterpolator())
                    .start()
            }

            isSettingsShowing = true
            Log.d(TAG, "Settings panel ADDED")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show settings panel", e)
            floatingSettingsView = null
            settingsParams = null
        }
    }

    private fun hideSettingsPanel() {
        val view = floatingSettingsView ?: return
        try {
            windowManager.removeView(view)
        } catch (_: Exception) {}
        floatingSettingsView = null
        isSettingsShowing = false
    }

    // ==================== 公共方法 ====================

    private fun hideAll() {
        stopBreathingAnimation()
        hideSettingsPanel()
        hidePanel()
        val view = floatingButtonView
        if (view != null) {
            try {
                windowManager.removeView(view)
            } catch (_: Exception) {}
            floatingButtonView = null
        }
    }

    private fun openMainApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("open_quick_notes", true)
        }
        startActivity(intent)
    }

    private fun saveQuickNote(content: String, tag: String) {
        val success = FloatingWindowPlugin.notifySaveQuickNote(content, tag)
        if (success) {
            Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(this, "保存失败，请打开应用重试", Toast.LENGTH_SHORT).show()
        }
    }

    private fun savePosition(x: Int, y: Int) {
        FloatingWindowPlugin.notifyPositionChanged(x, y)
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * resources.displayMetrics.density).toInt()
    }
}
