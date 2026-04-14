# 设计系统使用指南

## 概述

本设计系统基于以下 Skills 构建：
- **design-system-patterns**: 三层令牌架构
- **visual-design-foundations**: 8pt 网格、排版系统
- **interaction-design**: 微交互、动画曲线

---

## 🎨 设计令牌架构

### 三层架构

```
┌─────────────────────────────────────┐
│  Layer 3: Component Tokens          │
│  组件级令牌 - 按钮、卡片、输入框      │
├─────────────────────────────────────┤
│  Layer 2: Semantic Tokens           │
│  语义化令牌 - 背景、文字、边框        │
├─────────────────────────────────────┤
│  Layer 1: Primitive Tokens          │
│  原始值 - 颜色、间距、圆角、阴影      │
└─────────────────────────────────────┘
```

---

## 📐 8pt 网格系统

### 间距使用

```dart
// ❌ 避免硬编码
padding: EdgeInsets.all(16)

// ✅ 使用设计令牌
padding: EdgeInsets.all(PrimitiveSpacing.lg)  // 16px
```

### 间距对照表

| Token | 值 | 使用场景 |
|-------|-----|---------|
| `xs` | 4px | 图标间距、紧凑内边距 |
| `sm` | 8px | 小间距、标签间隙 |
| `md` | 12px | 中等间距 |
| `lg` | 16px | 标准间距、卡片内边距 |
| `xl` | 20px | 大间距 |
| `xxl` | 24px | 组件间距 |
| `xxxl` | 32px | 区块间距 |

---

## 🎨 颜色系统

### 原始颜色

```dart
// 品牌色
PrimitiveColors.rose500    // 主色调
PrimitiveColors.mint500    // 成功色
PrimitiveColors.amber500   // 警告色
PrimitiveColors.sky500     // 信息色

// 中性色
PrimitiveColors.gray50     // 最浅背景
PrimitiveColors.gray900    // 最深文字
```

### 语义化颜色

```dart
final colors = SemanticColors(context, scheme);

colors.backgroundDefault   // 默认背景
colors.backgroundElevated  //  elevated 背景
colors.textPrimary         // 主要文字
colors.textSecondary       // 次要文字
colors.borderDefault       // 默认边框
colors.stateSuccess        // 成功状态
```

---

## ✍️ 排版系统

### 字体层级

```dart
// 展示文字
Text('标题', style: SemanticTypography.display)

// 标题层级
Text('标题1', style: SemanticTypography.heading1)
Text('标题2', style: SemanticTypography.heading2)
Text('标题3', style: SemanticTypography.heading3)

// 正文层级
Text('大正文', style: SemanticTypography.bodyLarge)
Text('正文', style: SemanticTypography.body)
Text('小正文', style: SemanticTypography.bodySmall)

// UI 文字
Text('标签', style: SemanticTypography.label)
Text('说明', style: SemanticTypography.caption)
Text('按钮', style: SemanticTypography.button)
```

---

## 🎯 动画系统

### 时长规范

| 时长 | 值 | 使用场景 |
|-----|-----|---------|
| `micro` | 100ms | 微交互、按钮反馈 |
| `fast` | 150ms | 快速反馈、状态切换 |
| `normal` | 300ms | 标准过渡、页面切换 |
| `slow` | 500ms | 慢速动画、复杂效果 |
| `elaborate` | 800ms | 复杂动画、强调效果 |

### 缓动曲线

```dart
// 标准曲线
PrimitiveAnimation.easeOut      // 减速
PrimitiveAnimation.easeIn       // 加速
PrimitiveAnimation.easeInOut    // 加减速

// 特殊曲线
PrimitiveAnimation.spring       // 弹性效果 (0.34, 1.56, 0.64, 1)
PrimitiveAnimation.easeOutExpo  // 指数减速 (0.16, 1, 0.3, 1)
PrimitiveAnimation.gentle       // 柔和过渡 (0.23, 1.0, 0.32, 1.0)
```

---

## 🧩 组件使用

### 动画反馈组件

```dart
// 涟漪按钮
RippleButton(
  onTap: () {},
  backgroundColor: scheme.primaryColor,
  child: Text('点击我'),
)

// 弹跳卡片
BouncyCard(
  onTap: () {},
  child: YourWidget(),
)

// 震动动画
ShakeAnimation(
  shouldShake: _shouldShake,
  child: YourWidget(),
)

// 呼吸动画
BreathingAnimation(
  child: YourWidget(),
)

// 滑动入场
SlideInAnimation(
  index: 0,  // 用于错峰动画
  child: YourWidget(),
)
```

### 沉浸式体验组件

```dart
// 魔法文字
MagicText(
  text: '流光效果',
  colors: [Colors.red, Colors.blue, Colors.green],
)

// 霓虹文字
NeonText(
  text: 'NEON',
  glowColor: Colors.cyan,
)

// 玻璃态容器
GlassmorphicContainer(
  child: YourWidget(),
)

// 渐变边框
GradientBorderContainer(
  child: YourWidget(),
)

// 粒子背景
FloatingParticles(
  particleCount: 20,
  colors: [Colors.white, Colors.pink],
)
```

### 日记专属组件

```dart
// 心情选择器
MoodSelector(
  moods: moodList,
  selectedMood: selectedIndex,
  onMoodSelected: (index) {},
)

// 3D 倾斜卡片
TiltCard(
  onTap: () {},
  child: YourWidget(),
)

// 标签云
TagCloud(
  tags: ['日记', '心情', '旅行'],
  selectedTags: selectedTags,
  onTagTap: (tag) {},
)

// 字数统计
WordCountIndicator(
  count: 256,
  goal: 300,
)

// 进度环
AnimatedProgressRing(
  progress: 0.75,
  center: Text('75%'),
)
```

### 智能通知组件

```dart
// 显示 Toast
ToastManager().show(
  context,
  message: '保存成功！',
  type: ToastType.success,
)

// 徽章解锁动画
BadgeUnlockAnimation(
  badgeName: '连续7天',
  badgeIcon: '🔥',
  badgeColor: Colors.orange,
)

// 成就弹窗
showDialog(
  context: context,
  builder: (context) => AchievementDialog(
    title: '获得成就',
    description: '恭喜你！',
    icon: '🏆',
  ),
)

// 五彩纸屑
ConfettiCelebration(
  particleCount: 100,
  onComplete: () {},
)
```

---

## 🎬 动画最佳实践

### 1. 使用正确的时长

```dart
// ✅ 微交互使用 100-150ms
AnimatedContainer(
  duration: PrimitiveAnimation.fast,  // 150ms
  child: button,
)

// ✅ 页面过渡使用 300-500ms
PageTransition(
  duration: PrimitiveAnimation.slow,  // 500ms
  child: page,
)
```

### 2. 使用 Spring 曲线

```dart
// ✅ 交互元素使用 Spring 曲线
AnimatedContainer(
  curve: PrimitiveAnimation.spring,
  child: widget,
)
```

### 3. 错峰动画

```dart
// ✅ 列表项错峰入场
ListView.builder(
  itemBuilder: (context, index) {
    return SlideInAnimation(
      index: index,  // 自动计算延迟
      child: ListItem(),
    );
  },
)
```

### 4. 触觉反馈

```dart
// ✅ 重要交互添加触觉反馈
GestureDetector(
  onTap: () {
    HapticFeedback.lightImpact();  // 轻触
    // 或
    HapticFeedback.mediumImpact(); // 中等
    // 或
    HapticFeedback.heavyImpact();  // 重触
  },
)
```

---

## 📱 响应式设计

### 使用语义化间距

```dart
Container(
  // ✅ 组件内部使用 component 间距
  padding: EdgeInsets.all(SemanticSpacing.componentMd),
  
  // ✅ 组件之间使用 element 间距
  margin: EdgeInsets.only(bottom: SemanticSpacing.elementMd),
)
```

### 容器边距

```dart
// ✅ 屏幕边距
Padding(
  padding: EdgeInsets.all(SemanticSpacing.screenPadding),
  child: content,
)
```

---

## 🧪 示例：完整页面

```dart
class ExamplePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      body: SingleChildScrollView(
        // ✅ 使用语义化间距
        padding: EdgeInsets.all(SemanticSpacing.screenPadding),
        child: Column(
          children: [
            // ✅ 使用 SlideInAnimation 错峰入场
            SlideInAnimation(
              index: 0,
              child: _buildCard(),
            ),
            SizedBox(height: SemanticSpacing.elementMd),
            
            SlideInAnimation(
              index: 1,
              child: _buildCard(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCard() {
    return BouncyCard(
      onTap: () {},
      child: Container(
        // ✅ 使用 Primitive 间距
        padding: EdgeInsets.all(PrimitiveSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(PrimitiveRadius.xl),
          boxShadow: PrimitiveShadows.md,
        ),
        child: Text(
          '卡片内容',
          // ✅ 使用语义化排版
          style: SemanticTypography.body,
        ),
      ),
    );
  }
}
```

---

## 🎯 迁移指南

### 从旧系统迁移

```dart
// ❌ 旧代码
padding: EdgeInsets.all(16),
borderRadius: BorderRadius.circular(20),
duration: Duration(milliseconds: 300),

// ✅ 新代码
padding: EdgeInsets.all(PrimitiveSpacing.lg),
borderRadius: BorderRadius.circular(PrimitiveRadius.xl),
duration: PrimitiveAnimation.normal,
```

---

## 📚 相关文件

- `lib/config/design_tokens.dart` - 设计令牌定义
- `lib/widgets/animated_feedback.dart` - 动画反馈组件
- `lib/widgets/immersive_experience.dart` - 沉浸式体验组件
- `lib/widgets/diary_interactions.dart` - 日记专属组件
- `lib/widgets/smart_notifications.dart` - 智能通知组件
- `lib/screens/design_showcase_screen.dart` - 组件展示页面
