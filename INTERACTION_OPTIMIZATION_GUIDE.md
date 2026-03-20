# 交互优化使用指南

基于 [Interaction Design Skill](skills/interaction-design) 的优化实现

## 新增组件概览

### 1. InteractiveButton - 交互增强按钮

**特性：**
- 150ms 快速按压反馈
- Spring 弹性动画 (overshoot 效果)
- 触觉 + 视觉 + 音效三重反馈
- 阴影动态变化

**使用示例：**
```dart
InteractiveButton(
  onPressed: () => saveDiary(),
  backgroundColor: scheme.primaryColor,
  child: const Text('保存日记'),
)
```

**参数说明：**
- `scaleFactor`: 按压缩放比例 (默认 0.96)
- `enableHaptic`: 启用触觉反馈 (默认 true)
- `enableSound`: 启用音效 (默认 true)

---

### 2. PageTransitions - 页面过渡动画

**包含过渡类型：**
- `FadeSlideTransition`: 淡入上浮（通用）
- `DiaryListItemTransition`: 列表项错峰入场
- `CardExpandTransition`: 卡片展开（详情页）
- `SharedElementTransition`: Hero 共享元素
- `BottomSheetTransition`: 底部弹窗滑入
- `ScaleFadeTransition`: 缩放淡入（FAB）

**使用示例：**
```dart
// 列表项入场动画
DiaryListItemTransition(
  index: index,
  animation: animation,
  child: DiaryCard(diary: diary),
)

// 共享元素过渡（日记封面到详情）
SharedElementTransition(
  tag: 'diary-${diary.id}',
  child: DiaryCover(image: diary.coverImage),
)
```

**动画时长规范：**
| 过渡类型 | 时长 | 缓动曲线 |
|---------|------|---------|
| 微交互 | 100-150ms | Spring |
| 列表项 | 300ms | Ease-out |
| 页面切换 | 300-500ms | Ease-in-out |

---

### 3. SwipeableListItem - 滑动操作列表项

**特性：**
- 左滑删除手势
- 阈值判断 (100px)
- 背景渐显提示
- 确认对话框

**使用示例：**
```dart
SwipeableListItem(
  onDelete: () => deleteDiary(diary.id),
  onTap: () => openDiaryDetail(diary),
  confirmDeleteText: '确定要删除这篇日记吗？',
  child: DiaryCard(diary: diary),
)
```

---

### 4. SkeletonLoading - 骨架屏加载

**特性：**
- Shimmer 闪光效果
- 保留布局结构
- 多种预设样式

**使用示例：**
```dart
// 日记列表加载
ContentLoader(
  isLoading: isLoading,
  skeleton: DiaryListSkeleton(itemCount: 3),
  content: DiaryList(diaries: diaries),
)

// 统计页面加载
ContentLoader(
  isLoading: isLoading,
  skeleton: StatsSkeleton(),
  content: StatsView(stats: stats),
)
```

**预设骨架屏：**
- `DiaryCardSkeleton`: 日记卡片骨架
- `DiaryListSkeleton`: 日记列表骨架
- `StatsSkeleton`: 统计页面骨架

---

## 最佳实践

### 1. 动画性能
- ✅ 使用 `transform` 和 `opacity` 属性
- ✅ 使用 `AnimatedBuilder` 避免不必要的重建
- ❌ 避免动画 `width`, `height`, `top`, `left`

### 2. 无障碍支持
```dart
// 减少动画偏好支持
bool prefersReducedMotion = MediaQuery.of(context).disableAnimations;

// 在动画组件中使用
if (prefersReducedMotion) {
  return child; // 跳过动画
}
```

### 3. 反馈层级
```
Level 1: 微交互 (100-150ms)
  - 按钮按压
  - 图标切换
  
Level 2: 状态变化 (200-300ms)
  - 列表项添加/删除
  - 卡片展开/收起
  
Level 3: 页面过渡 (300-500ms)
  - 页面切换
  - 模态框出现
```

### 4. 缓动函数选择
```dart
// 进入元素 - 减速
const easeOut = Cubic(0.16, 1, 0.3, 1);

// 离开元素 - 加速
const easeIn = Cubic(0.55, 0, 1, 0.45);

// 移动中 - 减速后加速
const easeInOut = Cubic(0.65, 0, 0.35, 1);

// 弹性效果 - 趣味性
const spring = Cubic(0.34, 1.56, 0.64, 1);
```

---

## 优化建议

### 当前可优化的交互点：

1. **日记列表项**
   ```dart
   // 添加错峰入场动画
   AnimatedList(
     itemBuilder: (context, index, animation) {
       return DiaryListItemTransition(
         index: index,
         animation: animation,
         child: DiaryListTile(diary: diaries[index]),
       );
     },
   )
   ```

2. **保存按钮**
   ```dart
   // 替换为交互增强按钮
   InteractiveButton(
     onPressed: saveDiary,
     backgroundColor: scheme.primaryColor,
     child: const Text('保存'),
   )
   ```

3. **日记卡片**
   ```dart
   // 添加滑动删除
   SwipeableListItem(
     onDelete: () => deleteDiary(diary.id),
     onTap: () => navigateToDetail(diary),
     child: DiaryCard(diary: diary),
   )
   ```

4. **加载状态**
   ```dart
   // 添加骨架屏
   ContentLoader(
     isLoading: isLoading,
     skeleton: DiaryListSkeleton(),
     content: DiaryList(diaries: diaries),
   )
   ```

---

## 注意事项

1. **不要过度动画**
   - 动画应该有意义，不要为了动画而动画
   - 同一屏幕不要超过 3 个同时进行的动画

2. **保持一致性**
   - 相同时长的动画使用相同的缓动曲线
   - 同一类操作使用相同的反馈模式

3. **考虑低端设备**
   - 测试动画在低端设备上的性能
   - 提供降级方案（减少动画或简化效果）

4. **用户控制**
   - 允许用户取消长动画
   - 提供减少动画的选项

---

## 相关文件

- `lib/widgets/interactive_button.dart` - 交互按钮
- `lib/widgets/page_transitions.dart` - 页面过渡
- `lib/widgets/swipeable_list_item.dart` - 滑动列表项
- `lib/widgets/skeleton_loading.dart` - 骨架屏
