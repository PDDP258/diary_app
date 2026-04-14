/// ============================================================================
/// 工具库统一导出 - 技能整合版
/// ============================================================================
///
/// 使用方式:
/// ```dart
/// import 'package:diary_app/utils/utils.dart';
/// ```

// ===== 技能整合: 设计令牌和扩展 =====
export 'design_extensions.dart' show
    DesignContextExtension,
    DesignWidgetExtension,
    DesignTextExtension,
    DesignColorExtension,
    DesignDurationExtension,
    Animated,
    Spacing,
    Radius,
    Shadows,
    Durations,
    Curves;

// ===== 技能整合: 性能优化 =====
export 'performance_optimizations.dart' show
    PerformanceMonitor,
    DebouncedBuilder,
    VirtualizedList,
    ImageCacheManager,
    Throttler,
    Debouncer,
    LazyBuilder,
    FrameSplitter,
    ObjectPool,
    TaskQueue,
    MemoryHelper,
    MemoryInfo,
    OptimizedFadeImage,
    RepaintBoundaryWrapper,
    SelectiveValueListenableBuilder,
    PerformanceBuilder;

// ===== 技能整合: 安全工具 =====
export 'security_utils.dart' show
    EncryptionService,
    SecureStorageManager,
    CertificatePinningManager,
    ObfuscationUtil,
    InputValidator,
    PasswordStrength,
    SecurityChecklist,
    SecurityCheck,
    SecurityCheckResult,
    AuditLogger,
    AuditLog,
    AuditLogLevel,
    ThreatDetector,
    ThreatRule,
    Threat,
    ThreatSeverity;

// ===== 技能整合: 测试工具 =====
// 注意：测试工具不从此文件导出，以避免生产代码引入 dev_dependencies
// 需要时请在测试文件中直接导入：import 'package:diary_app/utils/testing_utils.dart';
