package com.example.diary_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 小组件渲染：把 [CourseWidgetPlan] 里「今天」那一天画成 RemoteViews。
 *
 * 为什么自己画位图而不用 `setInt(viewId, "setColorFilter", color)`：
 * RemoteViews 只允许调用带 `@RemotableViewMethod` 的方法，`setColorFilter`
 * 在部分 ROM/版本上会抛 `ActionException`；而 `setImageViewBitmap` 是老牌
 * 稳定接口，圆角、颜色都由我们自己画，效果完全可控。
 */
object CourseWidgetRenderer {

    /** 圆角位图缓存：颜色就那几种（主题 + 8 色课表色板），不必每次重画 */
    private val bitmapCache = HashMap<String, Bitmap>()

    fun render(context: Context, appWidgetId: Int): RemoteViews {
        val plan = CourseWidgetStore.plan(context)
        val theme = plan?.theme ?: CourseWidgetTheme.FALLBACK
        val views = RemoteViews(context.packageName, R.layout.widget_course)

        // 底板：浅色/深色两套 drawable，走官方 setImageViewResource。
        // ⚠️ 别改成 setInt(..., "setBackgroundResource", ...)：所有 setInt 都是反射调用，
        // 而框架的 RemoteViews.getMethod() 会强校验方法带 @RemotableViewMethod，
        // 没带就在**启动器进程**抛 ActionException → 桌面显示「无法加载小部件」。
        // setImageViewResource 是官方 API，不碰反射，稳。
        views.setImageViewResource(
            R.id.widget_bg,
            if (theme.isLight) R.drawable.widget_course_bg_light
            else R.drawable.widget_course_bg_dark,
        )

        val now = Date()
        val cal = Calendar.getInstance()
        val nowMinutes = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        val todayKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now)

        // ==================== 日期块 ====================
        views.setImageViewBitmap(
            R.id.widget_chip_bg,
            roundedRect(context, 46, 50, 14f, theme.accent),
        )
        views.setTextViewText(
            R.id.widget_chip_day,
            SimpleDateFormat("d", Locale.CHINA).format(now),
        )
        views.setTextViewText(
            R.id.widget_chip_weekday,
            SimpleDateFormat("EE", Locale.CHINA).format(now),
        )
        views.setTextColor(R.id.widget_chip_day, 0xFFFFFFFF.toInt())
        views.setTextColor(R.id.widget_chip_weekday, 0xE6FFFFFF.toInt())

        // ==================== 标题 / 副标题 ====================
        views.setTextColor(R.id.widget_title, theme.foreground)
        views.setTextColor(R.id.widget_subtitle, theme.secondary)
        views.setInt(R.id.widget_divider, "setBackgroundColor", theme.divider)
        views.setTextColor(R.id.widget_empty_title, theme.foreground)
        views.setTextColor(R.id.widget_empty_sub, theme.secondary)
        views.setTextColor(R.id.widget_footer, theme.secondary)

        val day = plan?.days?.get(todayKey)
        val dateText = SimpleDateFormat("M月d日", Locale.CHINA).format(now)

        // ==================== 分情况：有数据 / 假期 / 待同步 / 还没课表 ====================
        if (plan == null || day == null) {
            // 绝不假装「今天没课」：没数据就说没数据，否则用户以为真的没课
            views.setViewVisibility(R.id.widget_rows, View.GONE)
            views.setViewVisibility(R.id.widget_empty_box, View.VISIBLE)
            views.setViewVisibility(R.id.widget_footer, View.GONE)

            when {
                // 压根没导入过课表 —— 引导去导入，而不是说「待同步」
                plan != null && !plan.hasSemester -> {
                    views.setTextViewText(R.id.widget_title, "还没有课表")
                    views.setTextViewText(R.id.widget_subtitle, "$dateText · 去导入一份")
                    views.setTextViewText(R.id.widget_empty_title, "支持三种导入方式")
                    views.setTextViewText(
                        R.id.widget_empty_sub,
                        "教务系统 · Excel 模板 · ICS 日历",
                    )
                }
                // 有课表，但今天落在预计算窗口之外（App 太久没开）
                else -> {
                    views.setTextViewText(R.id.widget_title, "课表待刷新")
                    views.setTextViewText(R.id.widget_subtitle, "$dateText · 打开 App 同步一次")
                    views.setTextViewText(R.id.widget_empty_title, "打开「小记日记」同步一次")
                    views.setTextViewText(R.id.widget_empty_sub, "同步后这里会自动更新")
                }
            }
            applyDeepLink(context, views)
            return views
        }

        val items = day.items
        val weekText = day.week?.let { "第 $it 周" }

        if (items.isEmpty()) {
            views.setViewVisibility(R.id.widget_rows, View.GONE)
            views.setViewVisibility(R.id.widget_empty_box, View.VISIBLE)
            views.setViewVisibility(R.id.widget_footer, View.GONE)
            views.setTextViewText(
                R.id.widget_title,
                if (day.week == null) "假期中" else "今日无课",
            )
            views.setTextViewText(
                R.id.widget_subtitle,
                if (weekText != null) "$weekText · $dateText" else dateText,
            )
            views.setTextViewText(
                R.id.widget_empty_title,
                if (day.week == null) "好好休息" else "今天没有安排",
            )
            views.setTextViewText(
                R.id.widget_empty_sub,
                if (day.week == null && plan.semesterName.isNotEmpty()) {
                    "上一学期：${plan.semesterName}"
                } else {
                    "· 偷得浮生半日闲 ·"
                },
            )
            applyDeepLink(context, views)
            return views
        }

        views.setViewVisibility(R.id.widget_empty_box, View.GONE)
        views.setViewVisibility(R.id.widget_rows, View.VISIBLE)

        val capacity = rowCapacity(context, appWidgetId)
        val shown = items.take(capacity)

        // 「下一节」只标给第一门还没开始的课
        val nextIndex = items.indexOfFirst { it.startMin != null && nowMinutes < it.startMin }

        views.removeAllViews(R.id.widget_rows)
        shown.forEachIndexed { index, item ->
            val state = when {
                item.endMin != null && nowMinutes > item.endMin -> RowState.FINISHED
                item.startMin != null && nowMinutes >= item.startMin &&
                    (item.endMin == null || nowMinutes <= item.endMin) -> RowState.ONGOING
                else -> RowState.UPCOMING
            }
            val badge = when {
                state == RowState.ONGOING -> "进行中"
                index == nextIndex -> "下一节"
                else -> null
            }
            views.addView(
                R.id.widget_rows,
                buildRow(context, item, state, badge, theme),
            )
        }

        views.setTextViewText(R.id.widget_title, "今日 ${items.size} 节课")
        views.setTextViewText(
            R.id.widget_subtitle,
            if (weekText != null) "$weekText · $dateText" else dateText,
        )

        // ==================== 底部提示 ====================
        val hidden = items.size - shown.size
        val allDone = items.all { it.endMin != null && nowMinutes > it.endMin }
        val footer = when {
            hidden > 0 -> "还有 $hidden 节"
            allDone -> "今天的课上完啦"
            else -> null
        }
        if (footer != null) {
            views.setViewVisibility(R.id.widget_footer, View.VISIBLE)
            views.setTextViewText(R.id.widget_footer, footer)
        } else {
            views.setViewVisibility(R.id.widget_footer, View.GONE)
        }

        applyDeepLink(context, views)
        return views
    }

    private enum class RowState { UPCOMING, ONGOING, FINISHED }

    private fun buildRow(
        context: Context,
        item: CourseWidgetItem,
        state: RowState,
        badge: String?,
        theme: CourseWidgetTheme,
    ): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.widget_course_row)

        // 色条：已上完的淡掉，正在上的加满
        val barColor = when (state) {
            RowState.FINISHED -> alpha(item.color, 0x59)
            RowState.ONGOING -> item.color
            RowState.UPCOMING -> alpha(item.color, 0xCC)
        }
        row.setImageViewBitmap(R.id.row_bar, roundedRect(context, 3, 30, 1.5f, barColor))

        row.setTextViewText(R.id.row_time, item.time)
        row.setTextViewText(R.id.row_name, item.name)

        when (state) {
            RowState.ONGOING -> {
                row.setTextColor(R.id.row_time, theme.accent)
                row.setTextColor(R.id.row_name, theme.foreground)
                // 用官方 RemoteViews API 而不是反射调 setTextSize：
                // 前者带单位、且确定被 @RemotableViewMethod 放行
                row.setTextViewTextSize(
                    R.id.row_name,
                    TypedValue.COMPLEX_UNIT_SP,
                    13.5f,
                )
            }
            RowState.FINISHED -> {
                row.setTextColor(R.id.row_time, alpha(theme.secondary, 0x99))
                row.setTextColor(R.id.row_name, alpha(theme.secondary, 0xCC))
            }
            RowState.UPCOMING -> {
                row.setTextColor(R.id.row_time, theme.secondary)
                row.setTextColor(R.id.row_name, theme.foreground)
            }
        }

        val location = item.location.trim()
        if (location.isEmpty()) {
            row.setViewVisibility(R.id.row_loc, View.GONE)
        } else {
            row.setViewVisibility(R.id.row_loc, View.VISIBLE)
            row.setTextViewText(R.id.row_loc, location)
            row.setTextColor(
                R.id.row_loc,
                if (state == RowState.FINISHED) alpha(theme.secondary, 0x99) else theme.secondary,
            )
        }

        if (badge == null) {
            row.setViewVisibility(R.id.row_badge, View.GONE)
        } else {
            row.setViewVisibility(R.id.row_badge, View.VISIBLE)
            row.setTextViewText(R.id.row_badge, badge)
            row.setTextColor(R.id.row_badge, theme.accent)
        }

        return row
    }

    // ==================== 尺寸 ====================

    /**
     * 按小组件当前高度估算能放几行。
     *
     * 头部 50dp + 分割线上下 15dp + 内边距 22dp ≈ 87dp 固定开销，
     * 每行约 40dp，底部「还有 N 节」再留 18dp。
     */
    private fun rowCapacity(context: Context, appWidgetId: Int): Int {
        val heightDp = try {
            val options = AppWidgetManager.getInstance(context)
                .getAppWidgetOptions(appWidgetId)
            val minH = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0
            if (minH > 0) minH else 130
        } catch (t: Throwable) {
            130
        }
        val available = heightDp - 105
        return (available / 40).coerceIn(1, 6)
    }

    // ==================== 工具 ====================

    /**
     * 画一张圆角矩形位图。
     *
     * 尺寸是固定 dp，所以位图不会被缩放变形（这是不用 `setColorFilter` 的副产品）；
     * 相同参数的位图会缓存复用。
     */
    private fun roundedRect(
        context: Context,
        widthDp: Int,
        heightDp: Int,
        radiusDp: Float,
        color: Int,
    ): Bitmap {
        val key = "$widthDp|$heightDp|$radiusDp|$color"
        bitmapCache[key]?.let { return it }

        val density = context.resources.displayMetrics.density
        val w = (widthDp * density).toInt().coerceAtLeast(1)
        val h = (heightDp * density).toInt().coerceAtLeast(1)
        val r = radiusDp * density

        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        canvas.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), r, r, paint)

        if (bitmapCache.size > 48) bitmapCache.clear()
        bitmapCache[key] = bitmap
        return bitmap
    }

    /** 把不透明度写进 ARGB 的高字节 */
    private fun alpha(color: Int, a: Int): Int = (color and 0x00FFFFFF) or ((a and 0xFF) shl 24)

    private fun applyDeepLink(context: Context, views: RemoteViews) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("diaryapp://courses"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val pending = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pending)
    }
}
