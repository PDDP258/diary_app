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

    // 点击检测
    private var lastUpTime = 0L
    private var doubleTapSensitivityMs = 300
    private val LONG_PRESS_DELAY = 500L
    private var isLongPressTriggered = false
    private val longPressHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var longPressRunnable: Runnable? = null

    // 贴边缩小
    private var isCollapsed = false
    private var normalSize = 60
    private var collapsedSize = 24

    // 设置
    private var buttonColor = 0xFFFF6B6B.toInt()
    private var buttonOpacity = 1.0f
    private var buttonSizeDp = 60
    private var savedPosX = -1
    private var savedPosY = -1
    private var autoHideToEdge = true
    private var iconEmoji = ""
    private var savedBarWidth = -1
    private var savedBarHeight = -1

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

            updateButtonAppearance()

            val btn = view.findViewById<ImageButton>(R.id.floating_button)
                ?: run { Log.e(TAG, "floating_button not found"); return }

            // 设置图标（自定义 emoji 或默认系统图标）
            try {
                if (iconEmoji.isNotEmpty()) {
                    btn.setImageDrawable(createEmojiDrawable(iconEmoji, dpToPx(24), 0xFFFFFFFF.toInt()))
                } else {
                    btn.setImageResource(android.R.drawable.ic_menu_edit)
                }
            } catch (_: Exception) {
                btn.setImageResource(android.R.drawable.ic_input_add)
            }

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

        val drawable = GradientDrawable()
        drawable.shape = GradientDrawable.OVAL
        drawable.setColor(buttonColor)
        btn.background = drawable

        // 设置整体透明度（在 View 上设置，不在 LayoutParams 上设置，避免触摸失效）
        view.alpha = buttonOpacity.coerceIn(0.2f, 1.0f)
    }

    private fun createColorCircle(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
        }
    }

    private fun createColorCircleWithBorder(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
            setStroke(dpToPx(3), 0xFFFFFFFF.toInt())
        }
    }

    private fun createEmojiDrawable(emoji: String, sizePx: Int, textColor: Int): android.graphics.drawable.BitmapDrawable {
        val bitmap = android.graphics.Bitmap.createBitmap(sizePx, sizePx, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)
        val paint = android.graphics.Paint().apply {
            textSize = sizePx * 0.65f
            color = textColor
            textAlign = android.graphics.Paint.Align.CENTER
            isAntiAlias = true
        }
        val x = sizePx / 2f
        val y = sizePx / 2f + (paint.textSize * 0.35f)
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
                } else if (!isLongPressTriggered) {
                    // 没有拖动，也不是长按 → 处理点击/双击
                    val now = System.currentTimeMillis()
                    if (now - lastUpTime < doubleTapSensitivityMs && lastUpTime > 0) {
                        // 双击
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

            val etContent = view.findViewById<EditText>(R.id.et_quick_note)
                ?: run { Log.e(TAG, "et_quick_note not found"); return }
            val tvWordCount = view.findViewById<TextView>(R.id.tv_word_count)
                ?: run { Log.e(TAG, "tv_word_count not found"); return }
            etContent.addTextChangedListener(object : android.text.TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                override fun afterTextChanged(s: android.text.Editable?) {
                    val length = s?.length ?: 0
                    tvWordCount.text = "${length}字"
                }
            })

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

            windowManager.addView(view, panelParams)
            isPanelShowing = true
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
        val view = floatingPanelView ?: return
        try {
            windowManager.removeView(view)
        } catch (_: Exception) {}
        floatingPanelView = null
        isPanelShowing = false
        FloatingWindowPlugin.notifyPanelHidden()
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
                    FloatingWindowPlugin.notifySettingsChanged(buttonColor, buttonOpacity, buttonSizeDp)
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
                    FloatingWindowPlugin.notifySettingsChanged(buttonColor, buttonOpacity, buttonSizeDp)
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
                    FloatingWindowPlugin.notifySettingsChanged(buttonColor, buttonOpacity, buttonSizeDp)
                    Toast.makeText(this, "大小已更新", Toast.LENGTH_SHORT).show()
                }
            }

            // ===== Tab 切换 =====
            val pageAppearance = view.findViewById<LinearLayout>(R.id.page_appearance)
            val pageFunction = view.findViewById<LinearLayout>(R.id.page_function)
            val tabAppearance = view.findViewById<TextView>(R.id.tab_appearance)
            val tabFunction = view.findViewById<TextView>(R.id.tab_function)

            fun switchTab(isAppearance: Boolean) {
                if (isAppearance) {
                    pageAppearance?.visibility = View.VISIBLE
                    pageFunction?.visibility = View.GONE
                    tabAppearance?.setBackgroundColor(0xFFFFFFFF.toInt())
                    tabAppearance?.setTextColor(0xFF1A1A1A.toInt())
                    tabAppearance?.setTypeface(null, android.graphics.Typeface.BOLD)
                    tabFunction?.setBackgroundColor(0x00000000)
                    tabFunction?.setTextColor(0xFF666666.toInt())
                    tabFunction?.setTypeface(null, android.graphics.Typeface.NORMAL)
                } else {
                    pageAppearance?.visibility = View.GONE
                    pageFunction?.visibility = View.VISIBLE
                    tabAppearance?.setBackgroundColor(0x00000000)
                    tabAppearance?.setTextColor(0xFF666666.toInt())
                    tabAppearance?.setTypeface(null, android.graphics.Typeface.NORMAL)
                    tabFunction?.setBackgroundColor(0xFFFFFFFF.toInt())
                    tabFunction?.setTextColor(0xFF1A1A1A.toInt())
                    tabFunction?.setTypeface(null, android.graphics.Typeface.BOLD)
                }
            }

            tabAppearance?.setOnClickListener { switchTab(true) }
            tabFunction?.setOnClickListener { switchTab(false) }

            // ===== 功能设置 =====
            // 从 SharedPreferences 读取当前功能设置（Flutter 侧保存的）
            val prefs = getSharedPreferences("flutter_floating_window_settings", Context.MODE_PRIVATE)

            val switchSyncNotif = view.findViewById<Switch>(R.id.switch_sync_notification)
            val switchSyncSelfTalk = view.findViewById<Switch>(R.id.switch_sync_self_talk)
            val switchShowWordCount = view.findViewById<Switch>(R.id.switch_show_word_count)
            val switchAutoHideEdge = view.findViewById<Switch>(R.id.switch_auto_hide_edge)
            val seekBarDoubleTap = view.findViewById<SeekBar>(R.id.seekbar_double_tap)
            val tvDoubleTapValue = view.findViewById<TextView>(R.id.tv_double_tap_value)

            // 初始化值（默认 true, true, true, true, 300）
            switchSyncNotif?.isChecked = prefs.getBoolean("syncToNotification", true)
            switchSyncSelfTalk?.isChecked = prefs.getBoolean("syncToSelfTalk", true)
            switchShowWordCount?.isChecked = prefs.getBoolean("showWordCount", true)
            switchAutoHideEdge?.isChecked = prefs.getBoolean("autoHideToEdge", true)
            val savedDoubleTap = prefs.getInt("doubleTapSensitivityMs", 300)
            seekBarDoubleTap?.progress = savedDoubleTap - 100
            tvDoubleTapValue?.text = "${savedDoubleTap}ms"

            // 功能设置变更监听
            fun notifyFunctionSettings() {
                FloatingWindowPlugin.notifyFunctionSettingsChanged(
                    syncToNotification = switchSyncNotif?.isChecked ?: true,
                    syncToSelfTalk = switchSyncSelfTalk?.isChecked ?: true,
                    showWordCount = switchShowWordCount?.isChecked ?: true,
                    autoHideToEdge = switchAutoHideEdge?.isChecked ?: true,
                    doubleTapSensitivityMs = (seekBarDoubleTap?.progress ?: 200) + 100
                )
            }

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

            windowManager.addView(view, settingsParams)
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
