package com.example.diary_app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** 一节课（已由 Dart 侧把节次换算成钟点与分钟数） */
data class CourseWidgetItem(
    val time: String,
    val startMin: Int?,
    val endMin: Int?,
    val section: Int,
    val name: String,
    val location: String,
    val color: Int,
)

/** 计划里的一天 */
data class CourseWidgetDay(
    val date: String,
    val week: Int?,
    val weekday: Int,
    val items: List<CourseWidgetItem>,
)

/** 小组件配色（跟随 App 主题） */
data class CourseWidgetTheme(
    val background: Int,
    val foreground: Int,
    val secondary: Int,
    val accent: Int,
    val divider: Int,
) {
    /** 底色是不是浅色 —— 决定用哪张底板 drawable */
    val isLight: Boolean get() = relativeLuminance(background) > 0.5f

    companion object {
        val FALLBACK = CourseWidgetTheme(
            background = 0xFFFDF8F0.toInt(),
            foreground = 0xFF2C241F.toInt(),
            secondary = 0xFF8A7D6F.toInt(),
            accent = 0xFFC4956A.toInt(),
            divider = 0xFFF5E6D3.toInt(),
        )

        /** WCAG 相对亮度，和 Flutter 的 computeLuminance 同口径 */
        private fun relativeLuminance(color: Int): Float {
            fun channel(v: Int): Float {
                val s = v / 255f
                return if (s <= 0.03928f) s / 12.92f
                else Math.pow(((s + 0.055) / 1.055).toDouble(), 2.4).toFloat()
            }
            val r = channel((color shr 16) and 0xFF)
            val g = channel((color shr 8) and 0xFF)
            val b = channel(color and 0xFF)
            return 0.2126f * r + 0.7152f * g + 0.0722f * b
        }

        fun parse(json: JSONObject?): CourseWidgetTheme {
            if (json == null) return FALLBACK
            return CourseWidgetTheme(
                background = json.optLong("background", FALLBACK.background.toLong()).toInt(),
                foreground = json.optLong("foreground", FALLBACK.foreground.toLong()).toInt(),
                secondary = json.optLong("secondary", FALLBACK.secondary.toLong()).toInt(),
                accent = json.optLong("accent", FALLBACK.accent.toLong()).toInt(),
                divider = json.optLong("divider", FALLBACK.divider.toLong()).toInt(),
            )
        }
    }
}

/**
 * Dart 侧预计算好的整份计划。
 *
 * 原生侧**只做查表渲染**，不碰任何课表业务逻辑 —— 因为小组件刷新时
 * App 进程常常不存在（系统广播唤醒），读不到 SQLite 也算不出教学周。
 */
data class CourseWidgetPlan(
    val hasSemester: Boolean,
    val semesterName: String,
    val generatedAt: String,
    val rangeStart: String,
    val rangeEnd: String,
    val days: Map<String, CourseWidgetDay>,
    val theme: CourseWidgetTheme,
) {
    companion object {
        /** 与 Dart 侧 CourseWidgetPlan.schemaVersion 对齐；不认的版本一律当没数据 */
        const val SCHEMA_VERSION = 1

        /** 解析失败 / 版本不认 / 空串 → null（渲染器会走「待同步」态） */
        fun parse(json: String?): CourseWidgetPlan? {
            if (json.isNullOrBlank()) return null
            return try {
                val root = JSONObject(json)
                if (root.optInt("schemaVersion", 0) != SCHEMA_VERSION) return null

                val days = LinkedHashMap<String, CourseWidgetDay>()
                val arr: JSONArray = root.optJSONArray("days") ?: JSONArray()
                for (i in 0 until arr.length()) {
                    val d = arr.optJSONObject(i) ?: continue
                    val date = d.optString("date", "")
                    if (date.isEmpty()) continue
                    val items = ArrayList<CourseWidgetItem>()
                    val itemsArr = d.optJSONArray("items") ?: JSONArray()
                    for (j in 0 until itemsArr.length()) {
                        val it = itemsArr.optJSONObject(j) ?: continue
                        items.add(
                            CourseWidgetItem(
                                time = it.optString("time", ""),
                                startMin = it.optIntOrNull("startMin"),
                                endMin = it.optIntOrNull("endMin"),
                                section = it.optInt("section", 0),
                                name = it.optString("name", ""),
                                location = it.optString("location", ""),
                                color = it.optLong("color", 0xFFC4956A).toInt(),
                            )
                        )
                    }
                    days[date] = CourseWidgetDay(
                        date = date,
                        week = d.optIntOrNull("week"),
                        weekday = d.optInt("weekday", 1),
                        items = items,
                    )
                }

                CourseWidgetPlan(
                    hasSemester = root.optBoolean("hasSemester", false),
                    semesterName = root.optString("semesterName", ""),
                    generatedAt = root.optString("generatedAt", ""),
                    rangeStart = root.optString("rangeStart", ""),
                    rangeEnd = root.optString("rangeEnd", ""),
                    days = days,
                    theme = CourseWidgetTheme.parse(root.optJSONObject("theme")),
                )
            } catch (t: Throwable) {
                null
            }
        }
    }

    /** 今天是否落在计划覆盖的日期范围内 */
    fun covers(dateKey: String): Boolean =
        rangeStart.isNotEmpty() && rangeEnd.isNotEmpty() &&
            dateKey >= rangeStart && dateKey <= rangeEnd
}

/** `optInt` 分不清「没有这个键」和「值是 0」，这里需要一个真能返回 null 的 */
internal fun JSONObject.optIntOrNull(key: String): Int? =
    if (has(key) && !isNull(key)) optInt(key, Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE } else null

/**
 * 小组件的数据落盘。
 *
 * 用**原生自己的** SharedPreferences 而不是 Flutter 的 `FlutterSharedPreferences.xml`：
 * 后者是 shared_preferences 插件的内部格式（键带 `flutter.` 前缀、值类型编码），
 * 从原生侧直接读写等于依赖插件的实现细节，插件一升级就可能坏。
 */
object CourseWidgetStore {
    private const val PREFS = "course_widget_prefs"
    private const val KEY_PLAN = "plan_json"
    private const val KEY_HANDLE = "background_handle"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun savePlan(context: Context, json: String) {
        prefs(context).edit().putString(KEY_PLAN, json).apply()
    }

    fun planJson(context: Context): String? = prefs(context).getString(KEY_PLAN, null)

    fun plan(context: Context): CourseWidgetPlan? = CourseWidgetPlan.parse(planJson(context))

    fun clearPlan(context: Context) {
        prefs(context).edit().remove(KEY_PLAN).apply()
    }

    /** 后台入口点的 Dart 回调句柄；-1 表示还没注册 */
    fun backgroundHandle(context: Context): Long = prefs(context).getLong(KEY_HANDLE, -1L)

    fun saveBackgroundHandle(context: Context, handle: Long) {
        prefs(context).edit().putLong(KEY_HANDLE, handle).apply()
    }
}
