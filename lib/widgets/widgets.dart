/// ============================================================================
/// 组件库统一导出 - 技能整合版
/// ============================================================================
///
/// 使用方式:
/// ```dart
/// import 'package:diary_app/widgets/widgets.dart';
/// ```

// ===== 技能整合: 无障碍组件 =====
export 'accessibility_components.dart' show
    SemanticWrapper,
    AccessibleButton,
    AccessibleIconButton,
    HighContrastText,
    ScreenReaderOnly,
    FocusableArea,
    LiveRegion,
    AccessibleFormField,
    AccessibleProgressIndicator,
    ContrastChecker,
    ColorExtension,
    AccessibilityHelper,
    HapticFeedbackType;

// ===== 技能整合: 动画反馈组件 =====
export 'animated_feedback.dart' show
    RippleButton,
    BouncyCard,
    ShakeAnimation,
    BreathingAnimation,
    PulseAnimation,
    SlideInAnimation,
    CountAnimation;

// ===== 技能整合: 沉浸式体验组件 =====
export 'immersive_experience.dart' show
    ParallaxContainer,
    ParallaxLayer,
    FlipCard,
    FlipDirection,
    MagicText,
    NeonText,
    FloatingParticles,
    GlassmorphicContainer,
    GradientBorderContainer,
    TypewriterText;

// ===== 技能整合: 日记专属交互组件 =====
export 'diary_interactions.dart' show
    MoodSelector,
    MoodData,
    TiltCard,
    TagCloud,
    ImagePreviewGrid,
    AnimatedProgressRing,
    WordCountIndicator;

// ===== 技能整合: 智能通知组件 =====
export 'smart_notifications.dart' show
    ToastManager,
    ToastType,
    BadgeUnlockAnimation,
    AchievementDialog,
    GuidedTooltip,
    TooltipPosition,
    ConfettiCelebration;

// ===== 现有组件导出 =====
export 'interactive_button.dart' show
    InteractiveButton,
    InteractiveIconButton;

export 'skeleton_loading.dart' show
    ShimmerEffect,
    SkeletonContainer,
    DiaryCardSkeleton,
    DiaryListSkeleton,
    StatsSkeleton,
    LoadingPlaceholder,
    ContentLoader;

export 'page_transitions.dart' show
    FadeSlideTransition,
    DiaryListItemTransition,
    CardExpandTransition,
    SharedElementTransition,
    BottomSheetTransition,
    ScaleFadeTransition,
    SkeletonLoadingTransition,
    ShakeTransition;
