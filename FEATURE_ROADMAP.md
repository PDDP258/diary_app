# 小记日记功能路线图

## Phase 1: 农历功能（内置算法）

### 2026年节假日数据

#### 法定节假日（已确认）
| 节日 | 日期 | 农历 | 放假安排 |
|------|------|------|----------|
| 元旦 | 1月1日-3日 | - | 放假3天 |
| 春节 | 2月15日-23日 | 腊月廿八-正月初七 | 放假9天 |
| 清明节 | 4月4日-6日 | - | 放假3天 |
| 劳动节 | 5月1日-5日 | - | 放假5天 |
| 端午节 | 6月19日-21日 | 五月初五 | 放假3天 |
| 中秋节 | 9月25日-27日 | 八月十五 | 放假3天 |
| 国庆节 | 10月1日-7日 | - | 放假7天 |

#### 传统节日（农历）
```dart
final lunarFestivals2026 = {
  '腊月廿九': '除夕',
  '正月初一': '春节 🧧',
  '正月十五': '元宵节 🏮',
  '五月初五': '端午节 🐲',
  '七月初七': '七夕节 💕',
  '八月十五': '中秋节 🥮',
  '九月初九': '重阳节 🌼',
  '腊月初八': '腊八节 🥣',
};
```

#### 2026年二十四节气
```dart
final solarTerms2026 = {
  '2026-01-05': '小寒',
  '2026-01-20': '大寒',
  '2026-02-04': '立春',
  '2026-02-18': '雨水',
  '2026-03-05': '惊蛰',
  '2026-03-20': '春分',
  '2026-04-05': '清明',
  '2026-04-20': '谷雨',
  '2026-05-05': '立夏',
  '2026-05-21': '小满',
  '2026-06-05': '芒种',
  '2026-06-21': '夏至',
  '2026-07-07': '小暑',
  '2026-07-23': '大暑',
  '2026-08-07': '立秋',
  '2026-08-23': '处暑',
  '2026-09-07': '白露',
  '2026-09-23': '秋分',
  '2026-10-08': '寒露',
  '2026-10-23': '霜降',
  '2026-11-07': '立冬',
  '2026-11-22': '小雪',
  '2026-12-07': '大雪',
  '2026-12-22': '冬至',
};
```

### 农历算法实现

**核心类设计**：
```dart
class LunarCalendarService {
  // 缓存避免重复计算
  static final Map<String, LunarDate> _cache = {};
  
  /// 获取农历日期（带缓存）
  static LunarDate getLunarDate(DateTime date) {
    final key = '${date.year}-${date.month}-${date.day}';
    if (_cache.containsKey(key)) return _cache[key]!;
    
    final lunarDate = _calculateLunarDate(date);
    _cache[key] = lunarDate;
    return lunarDate;
  }
  
  /// 简化版农历计算（仅2026年）
  static LunarDate _calculateLunarDate(DateTime date) {
    // 使用预计算的2026年农历数据表
    // 数据量约 365 * 20字节 = 7KB
  }
  
  /// 获取节日信息
  static String? getFestival(DateTime date) {
    // 检查阳历节日
    // 检查农历节日
    // 检查节气
  }
  
  /// 获取干支纪年
  static String getGanZhiYear(int year) {
    // 2026年 = 丙午年
  }
  
  /// 获取生肖
  static String getZodiac(int year) {
    // 2026年 = 🐴 马年
  }
}
```

**数据表结构（2026年）**：
```dart
// 每月农历信息（简化存储）
class LunarMonthData {
  final int lunarMonth;      // 农历月份 1-12
  final int lunarDay;        // 农历日期 1-30
  final bool isLeapMonth;    // 是否闰月
  final int dayOfYear;       // 一年中的第几天
}

// 预计算2026年全年数据
final lunarData2026 = [
  LunarMonthData(11, 12, false, 1),   // 1月1日 = 冬月十二
  // ... 全年365天
];
```

### UI 实现

1. **日历单元格农历显示**
   - 在 `_buildDayCell` 中添加农历显示
   - 字体：11px，textMediumColor
   - 节日高亮：主题色

2. **顶部农历信息卡片**
   - 玻璃态设计
   - 显示：干支 + 生肖 + 农历日期
   - 节日/节气标记

---

## Phase 2: 目标功能

### 功能设计

**目标设置**：
- 每月目标篇数：8/12/20/30/自定义
- 目标类型：日记篇数、字数、连续天数

**进度追踪**：
- 本月已完成/目标
- 完成百分比
- 连续记录天数
- 预计达成日期

**激励机制**：
- 达成目标动画（彩纸飘落）
- 连续记录火焰 🔥
- 月度成就徽章

### 数据模型

```dart
class MonthlyGoal {
  final int year;
  final int month;
  final int targetCount;
  final GoalType type;
  int completedCount;
  int currentStreak;
  int longestStreak;
  bool isCompleted;
  DateTime? completedAt;
  
  MonthlyGoal({
    required this.year,
    required this.month,
    this.targetCount = 12,
    this.type = GoalType.diaryCount,
    this.completedCount = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.isCompleted = false,
    this.completedAt,
  });
}

enum GoalType {
  diaryCount,    // 日记篇数
  wordCount,     // 总字数
  streakDays,    // 连续天数
  photoCount,    // 照片数量
}
```

### UI 组件

1. **目标进度卡片**
   - 环形进度条（Animated）
   - 文字信息
   - 设置按钮

2. **目标设置弹窗**
   - 预设选项 Chip
   - 自定义输入
   - 目标类型选择

3. **达成庆祝动画**
   - 使用现有 Confetti 组件
   - 进度环完成动画
   - Toast 提示

---

## Phase 3: 三级标签系统重构

### 当前问题
- 标签只有一级，分类不够细致
- 用户希望更细致的分类管理

### 新设计：三级标签系统

```dart
class TagCategory {
  final String id;
  final String name;           // 一级分类名称
  final String? emoji;         // 图标
  final Color color;           // 主题色
  final List<TagSubCategory> subCategories;
  final int sortOrder;
}

class TagSubCategory {
  final String id;
  final String name;           // 二级分类名称
  final List<Tag> tags;        // 三级：具体标签
  final int sortOrder;
}

class Tag {
  final String id;
  final String name;
  final int usageCount;
  final DateTime createdAt;
}
```

### 预设分类体系

```dart
final defaultCategories = [
  TagCategory(
    name: '生活',
    emoji: '🏠',
    color: Colors.blue,
    subCategories: [
      TagSubCategory(name: '饮食', tags: ['早餐', '午餐', '晚餐', '美食']),
      TagSubCategory(name: '购物', tags: ['网购', '超市', '逛街']),
      TagSubCategory(name: '健康', tags: ['运动', '睡眠', '生病', '体检']),
    ],
  ),
  TagCategory(
    name: '工作',
    emoji: '💼',
    color: Colors.orange,
    subCategories: [
      TagSubCategory(name: '日常', tags: ['上班', '加班', '会议', '出差']),
      TagSubCategory(name: '成长', tags: ['学习', '培训', '考证', '晋升']),
    ],
  ),
  TagCategory(
    name: '情感',
    emoji: '❤️',
    color: Colors.pink,
    subCategories: [
      TagSubCategory(name: '家人', tags: ['父母', '孩子', '伴侣', '聚会']),
      TagSubCategory(name: '朋友', tags: ['聚会', '聊天', '旅行']),
      TagSubCategory(name: '心情', tags: ['开心', '难过', '焦虑', '感恩']),
    ],
  ),
  TagCategory(
    name: '娱乐',
    emoji: '🎮',
    color: Colors.purple,
    subCategories: [
      TagSubCategory(name: '影视', tags: ['电影', '电视剧', '综艺', '动漫']),
      TagSubCategory(name: '游戏', tags: ['手游', '网游', '单机']),
      TagSubCategory(name: '阅读', tags: ['小说', '漫画', '书籍']),
    ],
  ),
  TagCategory(
    name: '旅行',
    emoji: '✈️',
    color: Colors.green,
    subCategories: [
      TagSubCategory(name: '目的地', tags: ['国内', '国外', '周边']),
      TagSubCategory(name: '类型', tags: ['自驾游', '跟团', '徒步', '露营']),
    ],
  ),
];
```

### UI 设计

1. **标签管理页面**
   - 树形结构展示三级分类
   - 可折叠/展开
   - 拖拽排序
   - 添加/编辑/删除

2. **写日记时标签选择**
   - 底部弹出选择器
   - 三级联动选择
   - 搜索快速定位
   - 最近使用快捷入口

3. **标签统计页面**
   - 按分类统计
   - 可视化图表
   - 使用频率排行

---

## Phase 4: 搜索功能升级

### 当前问题
- 只能按关键词搜索
- 不支持标签筛选
- 不支持多条件组合

### 新设计：高级搜索

```dart
class SearchFilter {
  String? keyword;
  List<String>? tags;
  DateTime? startDate;
  DateTime? endDate;
  List<int>? moodIds;
  bool? hasPhotos;
  bool? isFavorite;
  String? categoryId;      // 一级分类
  String? subCategoryId;   // 二级分类
}
```

### 搜索界面

1. **搜索主页**
   ```
   ┌─────────────────────────────┐
   │ 🔍 输入关键词...      [筛选] │
   ├─────────────────────────────┤
   │ 最近搜索：工作 旅行 心情      │
   ├─────────────────────────────┤
   │ 热门标签：                   │
   │ [工作] [生活] [美食] [旅行]  │
   ├─────────────────────────────┤
   │ 高级筛选：                   │
   │ 时间 ▼  心情 ▼  标签 ▼      │
   └─────────────────────────────┘
   ```

2. **筛选面板**
   - 时间范围：最近7天/30天/自定义
   - 心情筛选：多选
   - 标签筛选：三级选择器
   - 其他：有图片、收藏等

3. **搜索结果页**
   - 结果数量统计
   - 排序选项（时间/相关度）
   - 高亮显示关键词
   - 快速预览

---

## Phase 5: 标签分类功能更新

### 日记列表标签展示

```dart
// 在日记卡片中展示标签
Widget _buildTags(List<Tag> tags) {
  return Wrap(
    spacing: 4,
    children: tags.map((tag) {
      // 根据标签所属分类显示不同颜色
      final category = getCategoryByTag(tag);
      return Chip(
        label: Text(tag.name),
        backgroundColor: category.color.withOpacity(0.2),
        side: BorderSide(color: category.color),
        labelStyle: TextStyle(color: category.color, fontSize: 11),
      );
    }).toList(),
  );
}
```

### 按标签分类浏览

1. **分类入口**
   - 统计页新增"标签分类"卡片
   - 日历页侧边栏快捷入口

2. **分类浏览页**
   ```
   ┌─────────────────────────────┐
   │ ← 标签分类                   │
   ├─────────────────────────────┤
   │ [全部] [生活] [工作] [情感]  │
   ├─────────────────────────────┤
   │ 生活                         │
   │ ├─ 饮食 (12)                 │
   │ │   ├─ 早餐 (5)              │
   │ │   └─ 美食 (7)              │
   │ ├─ 健康 (8)                  │
   │ └─ ...                       │
   └─────────────────────────────┘
   ```

3. **标签时间线**
   - 选择标签后显示该标签下的日记时间线
   - 支持多标签组合筛选
   - 统计该标签使用频率

---

## 数据迁移策略

### 标签系统迁移

1. **备份现有标签**
2. **创建默认三级分类**
3. **智能映射旧标签到新分类**
   - "早餐" → 生活/饮食/早餐
   - "工作" → 工作/日常/上班
   - "电影" → 娱乐/影视/电影
4. **用户可手动调整**

### 兼容性处理

```dart
// 读取时兼容旧格式
List<Tag> migrateOldTags(List<dynamic> oldTags) {
  return oldTags.map((oldTag) {
    // 查找映射关系
    final mapping = tagMapping[oldTag];
    if (mapping != null) {
      return Tag(
        id: mapping.id,
        name: mapping.name,
        categoryId: mapping.categoryId,
        subCategoryId: mapping.subCategoryId,
      );
    }
    // 未映射的归入"其他"分类
    return createOtherTag(oldTag);
  }).toList();
}
```

---

## 实施顺序

### 第1周：农历功能
- [ ] 创建 `LunarCalendarService`
- [ ] 实现2026年农历数据表
- [ ] 日历单元格显示农历
- [ ] 顶部农历信息卡片

### 第2周：目标功能
- [ ] 创建 `GoalProvider`
- [ ] 实现目标进度卡片
- [ ] 目标设置弹窗
- [ ] 达成庆祝动画

### 第3-4周：标签系统重构
- [ ] 更新 Tag 数据模型
- [ ] 创建三级分类管理页面
- [ ] 更新写日记标签选择器
- [ ] 数据迁移工具

### 第5周：搜索功能升级
- [ ] 更新 SearchFilter 模型
- [ ] 实现高级搜索界面
- [ ] 多条件组合搜索
- [ ] 搜索结果优化

### 第6周：整合测试
- [ ] 全流程测试
- [ ] 性能优化
- [ ] Bug修复
- [ ] 发布准备

---

## 技术要点

### 性能优化
1. **农历计算缓存**：Map缓存避免重复计算
2. **标签按需加载**：分页加载大量标签
3. **搜索索引**：本地数据库索引优化

### 用户体验
1. **渐进式引导**：首次使用三级标签时引导
2. **智能推荐**：根据内容推荐标签
3. **快捷操作**：最近使用、常用标签

### 兼容性
1. **数据迁移**：旧标签无缝迁移
2. **降级方案**：网络异常时本地计算
