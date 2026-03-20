# 农历与目标功能设计方案

## 一、农历功能设计

### 1. 功能需求
- 显示农历日期（初一、初二...三十）
- 显示农历节日（春节、元宵、端午、中秋、重阳等）
- 显示二十四节气
- 显示干支纪年（甲辰年、乙巳年等）
- 显示生肖

### 2. 技术实现

**方案A：使用第三方库（推荐）**
```yaml
dependencies:
  lunar_calendar: ^1.0.0  # 或其他农历库
```

**方案B：内置农历算法**
- 使用简化版农历算法，覆盖1900-2100年
- 存储农历数据表（约3KB）

### 3. UI 设计（基于 skills 设计原则）

#### A. 日历单元格农历显示
```
┌─────────────────┐
│        15       │  ← 阳历 (16px, FontWeight.w600)
│      正月十五    │  ← 农历 (11px, textMediumColor)
│   [日记圆点]     │  ← 日记标记
└─────────────────┘
```

**实现位置**：`_buildDayCell` 方法中，在日期数字下方添加

**代码结构**：
```dart
Column(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    Text('${date.day}'),  // 阳历
    const SizedBox(height: 2),
    Text(
      lunarDate,  // 农历
      style: TextStyle(
        fontSize: 11,
        color: isFestival 
          ? scheme.primaryColor  // 节日用主题色
          : scheme.textMediumColor.withOpacity(0.8),
        fontWeight: isFestival ? FontWeight.w600 : FontWeight.normal,
      ),
    ),
  ],
)
```

#### B. 顶部农历信息卡片（玻璃态设计）
参考 visual-design-foundations 的卡片规范：
- 圆角：16px
- 内边距：16px
- 阴影：elevation 4
- 背景：玻璃态渐变

```dart
Container(
  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [
        scheme.cardColor.withOpacity(0.9),
        scheme.cardColor.withOpacity(0.7),
      ],
    ),
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.08),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  ),
  child: Row(
    children: [
      // 干支和生肖
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('甲辰年 🐉', style: TextStyle(fontSize: 14)),
          Text('农历正月初一', style: TextStyle(fontSize: 12)),
        ],
      ),
      const Spacer(),
      // 节日或节气标记
      if (isFestival)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.primaryColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('🏮 春节'),
        ),
    ],
  ),
)
```

### 4. 节日高亮配色
| 节日类型 | 颜色 | 示例 |
|---------|------|------|
| 传统节日 | 红色 | 春节 🧧、元宵 🏮 |
| 节气 | 金色 | 立春 🌱、清明 🌿 |
| 其他 | 主题色 | 中秋 🥮、重阳 🌼 |

---

## 二、目标功能设计

### 1. 功能需求
- 设置每月写日记目标（8篇/12篇/20篇/自定义）
- 显示本月完成进度（环形进度条）
- 显示连续写日记天数
- 达成目标时显示庆祝动画
- 在日历上标记已写日期

### 2. 数据模型

```dart
class MonthlyGoal {
  final int year;
  final int month;
  final int targetCount;      // 目标篇数
  final int completedCount;   // 已完成篇数
  final int currentStreak;    // 当前连续天数
  final bool isCompleted;     // 是否已完成

  MonthlyGoal({
    required this.year,
    required this.month,
    required this.targetCount,
    this.completedCount = 0,
    this.currentStreak = 0,
    this.isCompleted = false,
  });
}
```

### 3. UI 设计

#### A. 目标进度卡片（基于 design-system-patterns）

```
┌─────────────────────────────────────────┐
│ 本月目标  [设置图标]                      │
│                                         │
│    ╭──────────╮    已完成 8/12 篇       │
│    │          │    ━━━━━━━━░░░░  67%    │
│    │   75%   │    连续记录 5 天 🔥      │
│    │  ◠◡◠    │                         │
│    ╰──────────╯    还差 4 篇达成目标    │
│                                         │
└─────────────────────────────────────────┘
```

**实现细节**：
- 卡片圆角：16px
- 内边距：16px
- 阴影：elevation 4
- 进度环：使用 `CircularProgressIndicator` 或自定义 painter
- 动画时长：500ms，ease-out 缓动

**代码结构**：
```dart
class GoalProgressCard extends StatefulWidget {
  final MonthlyGoal goal;
  final VoidCallback onTapSettings;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          // 环形进度
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return CircularProgressIndicator(
                value: _animation.value,
                strokeWidth: 8,
                backgroundColor: scheme.lightColor.withOpacity(0.3),
                valueColor: AlwaysStoppedAnimation<Color>(
                  goal.isCompleted ? Colors.green : scheme.primaryColor,
                ),
              );
            },
          ),
          // 文字信息
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('已完成 ${goal.completedCount}/${goal.targetCount} 篇'),
              Text('连续记录 ${goal.currentStreak} 天 🔥'),
            ],
          ),
        ],
      ),
    );
  }
}
```

#### B. 目标设置弹窗

```dart
showModalBottomSheet(
  context: context,
  builder: (context) => Container(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('设置本月目标', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 16),
        // 预设选项
        Wrap(
          spacing: 12,
          children: [8, 12, 20, 30].map((count) {
            return ChoiceChip(
              label: Text('$count篇'),
              selected: selectedTarget == count,
              onSelected: (_) => setTarget(count),
            );
          }).toList(),
        ),
      ],
    ),
  ),
);
```

#### C. 达成目标庆祝动画（基于 interaction-design）

使用 skill 中的庆祝模式：
- 动画时长：500ms+
- 缓动：spring (cubic-bezier(0.34, 1.56, 0.64, 1))
- 效果：彩纸飘落 + 进度环完成动画

参考 `milestone_service.dart` 的现有实现。

### 4. 目标状态显示

在日历上标记目标完成状态：
- 已写日记日期：显示绿色小圆点
- 连续记录：日期之间用虚线连接
- 达成目标当天：显示 🎉 标记

---

## 三、整合到日历页

### 新的日历页结构

```dart
Column(
  children: [
    // 1. 顶部农历信息卡片（新增）
    _buildLunarInfoCard(),
    
    // 2. 目标进度卡片（新增）
    GoalProgressCard(
      goal: monthlyGoal,
      onTapSettings: _showGoalSettings,
    ),
    
    // 3. 原有的日期标题和导航
    _buildHeader(),
    
    // 4. 星期标题
    _buildWeekdayHeader(),
    
    // 5. 日历网格（单元格带农历）
    _buildCalendarGrid(),
    
    // 6. 底部操作栏
    _buildActionBar(),
  ],
)
```

### 农历算法服务

```dart
class LunarCalendarService {
  /// 获取农历日期
  static String getLunarDate(DateTime date) {
    // 返回：初一、初二...三十
  }
  
  /// 获取农历节日
  static String? getLunarFestival(DateTime date) {
    // 返回：春节、元宵等，无则返回 null
  }
  
  /// 获取节气
  static String? getSolarTerm(DateTime date) {
    // 返回：立春、雨水等，无则返回 null
  }
  
  /// 获取干支纪年
  static String getGanZhiYear(DateTime date) {
    // 返回：甲辰年
  }
  
  /// 获取生肖
  static String getZodiac(DateTime date) {
    // 返回：🐉 龙
  }
}
```

---

## 四、技术实现步骤

### Phase 1: 农历功能
1. 添加农历计算库或内置算法
2. 创建 `LunarCalendarService`
3. 修改 `_buildDayCell` 添加农历显示
4. 创建顶部农历信息卡片
5. 测试不同日期的显示效果

### Phase 2: 目标功能
1. 创建 `MonthlyGoal` 数据模型
2. 创建 `GoalProvider` 管理目标状态
3. 创建 `GoalProgressCard` UI
4. 创建目标设置弹窗
5. 整合庆祝动画
6. 持久化存储目标数据

### Phase 3: 优化与测试
1. 性能优化（避免频繁计算农历）
2. 适配不同屏幕尺寸
3. 测试各种主题下的显示效果
4. 添加减少动画支持（无障碍）

---

## 五、参考设计资源

### 来自 skills 的设计原则

**visual-design-foundations**:
- 8-point 网格系统
- 卡片内边距：16px
- 圆角：16px
- 阴影：elevation 4

**interaction-design**:
- 进度动画：500ms，ease-out
- 庆祝动画：spring 缓动
- 减少动画支持：`prefers-reduced-motion`

**design-system-patterns**:
- 使用语义化 token
- 组件变体系统
- 主题适配

**react-native-design**:
- SafeArea 适配
- 平台特定样式
- 性能优化

---

## 六、预估工作量

| 功能 | 预估时间 | 复杂度 |
|------|---------|--------|
| 农历算法/库集成 | 2-4h | 中等 |
| 日历单元格农历显示 | 1-2h | 简单 |
| 顶部农历卡片 | 2h | 简单 |
| 目标数据模型 | 1h | 简单 |
| 目标进度卡片 UI | 3-4h | 中等 |
| 目标设置弹窗 | 2h | 简单 |
| 庆祝动画 | 2h | 中等 |
| 整合测试 | 2h | 中等 |

**总计**：约 15-20 小时
