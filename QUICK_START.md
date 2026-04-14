# 快速开始指南

## 新创建的文件列表

### 核心设计系统
1. `lib/config/design_tokens.dart` - 三层设计令牌系统
2. `lib/utils/design_extensions.dart` - 便捷扩展方法

### 组件库
3. `lib/widgets/animated_feedback.dart` - 动画反馈组件
4. `lib/widgets/immersive_experience.dart` - 沉浸式体验组件
5. `lib/widgets/diary_interactions.dart` - 日记专属组件
6. `lib/widgets/smart_notifications.dart` - 智能通知组件
7. `lib/widgets/widgets.dart` - 统一导出

### 示例页面
8. `lib/screens/design_showcase_screen.dart` - 组件展示
9. `lib/screens/extensions_demo_screen.dart` - 扩展方法演示

### 文档
10. `lib/config/design_system_guide.md` - 使用指南
11. `SKILL_IMPLEMENTATION_SUMMARY.md` - 实现总结

---

## 使用方法

### 1. 导入组件

```dart
import 'package:diary_app/widgets/widgets.dart';
import 'package:diary_app/utils/design_extensions.dart';
```

### 2. 使用扩展方法（推荐）

```dart
// 快速创建卡片
Text('内容')
    .paddingAll(Spacing.lg)
    .asCard()
    .withBounce(onTap: () {})
    .withSlideIn(index: 0)
```

### 3. 显示通知

```dart
// 显示 Toast
context.showSuccess('保存成功！');
context.showError('操作失败');

// 显示成就
showDialog(
  context: context,
  builder: (context) => AchievementDialog(
    title: '连续7天',
    description: '恭喜你！',
    icon: '🔥',
  ),
);
```

### 4. 使用日记组件

```dart
// 心情选择器
MoodSelector(
  moods: moodList,
  selectedMood: selectedIndex,
  onMoodSelected: (index) {},
)

// 标签云
TagCloud(
  tags: ['日记', '心情', '旅行'],
  selectedTags: selectedTags,
  onTagTap: (tag) {},
)
```

---

## 运行示例

在 `main.dart` 中添加路由：

```dart
// 设计展示页面
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const DesignShowcaseScreen()),
);

// 扩展方法演示
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const ExtensionsDemoScreen()),
);
```

---

## 设计系统核心

### 间距 (8pt 网格)
- `Spacing.xs` = 4px
- `Spacing.sm` = 8px
- `Spacing.md` = 12px
- `Spacing.lg` = 16px
- `Spacing.xl` = 20px
- `Spacing.xxl` = 24px

### 动画时长
- `Durations.micro` = 100ms (微交互)
- `Durations.fast` = 150ms (快速反馈)
- `Durations.normal` = 300ms (标准过渡)
- `Durations.slow` = 500ms (页面切换)

### 缓动曲线
- `Curves.spring` - 弹性效果
- `Curves.easeOutExpo` - 指数减速
- `Curves.gentle` - 柔和过渡

---

## 特性亮点

✅ 三层设计令牌架构  
✅ 30+ 精美组件  
✅ 20+ 扩展方法  
✅ 100+ 设计令牌  
✅ 完整的动画系统  
✅ 触觉反馈支持  

---

## 下一步

1. 查看 `lib/screens/design_showcase_screen.dart` 了解所有组件
2. 阅读 `lib/config/design_system_guide.md` 学习使用方式
3. 在新功能中尝试使用扩展方法
4. 逐步迁移旧代码
