import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../screens/custom_sticker_screen.dart';
import '../utils/platform_helpers.dart';

/// 随机贴图覆盖层组件
/// 用于在日记页和日历页显示随机位置、随机角度、随机出现的贴图
class RandomStickerOverlay extends StatefulWidget {
  final String targetPage;
  final double appearProbability; // 出现概率 0.0-1.0

  const RandomStickerOverlay({
    super.key,
    required this.targetPage,
    this.appearProbability = 0.7, // 默认70%概率出现
  });

  @override
  State<RandomStickerOverlay> createState() => _RandomStickerOverlayState();
}

/// 全局单例随机数生成器，避免多个实例产生相同的随机序列
final Random _globalRandom = Random();

class _RandomStickerOverlayState extends State<RandomStickerOverlay> {
  List<RandomStickerDisplay> _stickers = [];
  bool _isLoading = true;
  List<CustomSticker> _allAvailableStickers = [];

  // 动画配置
  static const Duration _fadeInDuration = Duration(milliseconds: 400);
  static const Duration _fadeOutDuration = Duration(milliseconds: 300);
  
  // 动态数量管理参数
  static const int _softMaxStickers = 5; // 软上限，超过后旧贴纸更容易消失
  static const int _hardMaxStickers = 8; // 硬上限，绝对不超过这个数量

  @override
  void initState() {
    super.initState();
    _initializeStickers();
  }

  /// 初始化贴图系统 - 加载可用贴图并开始随机出现流程
  Future<void> _initializeStickers() async {
    await _loadAvailableStickers();

    if (_allAvailableStickers.isNotEmpty) {
      // 页面加载时，随机延迟后显示第一张贴图
      _scheduleNextSticker(initial: true);
    } else {
      setState(() => _isLoading = false);
    }
  }

  /// 加载所有可用的贴图
  Future<void> _loadAvailableStickers() async {
    final prefs = await SharedPreferences.getInstance();
    final stickersJson = prefs.getString('custom_stickers');

    if (stickersJson != null) {
      final List<dynamic> list = jsonDecode(stickersJson);
      _allAvailableStickers = list
          .map((e) => CustomSticker.fromMap(e))
          .where(
            (s) => s.targetPage == 'all' || s.targetPage == widget.targetPage,
          )
          .toList();
    }
  }

  /// 安排下一个贴图出现
  /// 增加出现模式的随机性：有时单个，有时连续2-3个
  void _scheduleNextSticker({bool initial = false}) {
    // 随机延迟：初始2-4秒，后续6-18秒（更大的随机范围）
    final delaySeconds = initial
        ? 2.0 + _globalRandom.nextDouble() * 2.0 // 2-4秒初始延迟
        : 6 + _globalRandom.nextInt(13); // 6-18秒后续间隔（更灵活）

    Future.delayed(Duration(milliseconds: (delaySeconds * 1000).round()), () {
      if (!mounted) return;

      // 根据概率决定是否显示
      if (_globalRandom.nextDouble() < widget.appearProbability) {
        _addRandomSticker();
        
        // 15%概率：连续出现第二张（营造"贴纸潮"效果）
        if (_globalRandom.nextDouble() < 0.15 && _stickers.length < _hardMaxStickers - 1) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) _addRandomSticker();
          });
          
          // 5%概率：连续出现第三张（罕见的三连发）
          if (_globalRandom.nextDouble() < 0.33) {
            Future.delayed(const Duration(milliseconds: 1600), () {
              if (mounted) _addRandomSticker();
            });
          }
        }
      }

      // 继续安排下一个
      _scheduleNextSticker();
    });
  }

  /// 添加一个随机贴图，带有丰富的随机属性
  void _addRandomSticker() {
    if (_allAvailableStickers.isEmpty) return;
    
    // 动态数量管理：超过软上限后，随机移除旧贴纸
    if (_stickers.length >= _softMaxStickers) {
      // 计算移除概率：贴纸越多，移除概率越高
      final removalChance = (_stickers.length - _softMaxStickers + 1) * 0.3;
      if (_globalRandom.nextDouble() < removalChance && _stickers.isNotEmpty) {
        // 随机选择一个旧贴纸移除（不是总是最旧的）
        final indexToRemove = _globalRandom.nextInt(_stickers.length ~/ 2);
        _removeStickerWithFade(_stickers[indexToRemove].id);
      }
    }
    
    // 硬上限检查
    if (_stickers.length >= _hardMaxStickers) {
      return; // 达到硬上限，不再添加
    }

    // 随机选择一个贴图
    final sticker = _allAvailableStickers[
        _globalRandom.nextInt(_allAvailableStickers.length)];

    // 生成随机位置
    final position = _generateRandomPosition();
    if (position == null) return;

    // 随机角度 (-45° 到 45°，更大的变化范围)
    final rotation = (_globalRandom.nextDouble() - 0.5) * 0.8;

    // 随机缩放 (0.5 到 1.4，更大的变化范围)
    final scale = 0.5 + _globalRandom.nextDouble() * 0.9;

    // 生成唯一ID
    final id =
        '${sticker.id}_${DateTime.now().millisecondsSinceEpoch}_${_globalRandom.nextInt(1000)}';

    // 为每个贴纸随机分配一个"性格"（生命周期）
    // 0: 闪现型(短暂), 1: 普通型, 2: 常驻型(长久)
    final personality = _globalRandom.nextInt(10);
    final int lifespanSeconds;
    if (personality < 2) {
      // 20% 概率：闪现型，5-8秒
      lifespanSeconds = 5 + _globalRandom.nextInt(4);
    } else if (personality < 7) {
      // 50% 概率：普通型，12-18秒
      lifespanSeconds = 12 + _globalRandom.nextInt(7);
    } else {
      // 30% 概率：常驻型，20-30秒
      lifespanSeconds = 20 + _globalRandom.nextInt(11);
    }

    final newSticker = RandomStickerDisplay(
      id: id,
      isEmoji: sticker.type == CustomStickerType.emoji,
      imagePath:
          sticker.type == CustomStickerType.emoji ? null : sticker.imagePath,
      emoji: sticker.type == CustomStickerType.emoji ? sticker.emoji : null,
      positionX: position.dx,
      positionY: position.dy,
      rotation: rotation,
      scale: scale,
      opacity: 0.0,
      isVisible: false,
    );

    setState(() {
      _stickers.add(newSticker);
      _isLoading = false;
    });

    // 延迟一帧后触发淡入动画
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      setState(() {
        final index = _stickers.indexWhere((s) => s.id == id);
        if (index != -1) {
          _stickers[index] = _stickers[index].copyWith(
            opacity: 1.0,
            isVisible: true,
          );
        }
      });
    });

    // 根据"性格"安排消失时间
    _scheduleStickerRemoval(id, lifespanSeconds);
  }

  /// 生成随机位置，只避开核心输入区
  /// 使用完全随机策略，让贴纸可以出现在屏幕的任何角落
  Offset? _generateRandomPosition() {
    double x, y;
    int attempts = 0;
    const maxAttempts = 30;

    do {
      // 完全随机生成位置，只避开屏幕边缘一小部分和核心输入区
      x = 0.05 + _globalRandom.nextDouble() * 0.90;  // 0.05-0.95
      y = 0.08 + _globalRandom.nextDouble() * 0.86;  // 0.08-0.94
      
      attempts++;
    } while (attempts < maxAttempts &&
        (_isInCoreContentArea(x, y) || _isTooCloseToExistingStickers(x, y)));

    if (attempts >= maxAttempts) return null;
    return Offset(x, y);
  }

  /// 安排贴图消失（带淡出动画）
  /// [lifespanSeconds] 自定义生命周期（秒）
  void _scheduleStickerRemoval(String id, int lifespanSeconds) {
    Future.delayed(Duration(seconds: lifespanSeconds), () {
      if (!mounted) return;

      _removeStickerWithFade(id);
    });
  }
  
  /// 立即移除贴图（带淡出动画）
  void _removeStickerWithFade(String id) {
    if (!mounted) return;

    // 先触发淡出动画
    setState(() {
      final index = _stickers.indexWhere((s) => s.id == id);
      if (index != -1) {
        _stickers[index] = _stickers[index].copyWith(
          opacity: 0.0,
          isVisible: false,
        );
      }
    });

    // 等待淡出动画完成后移除
    Future.delayed(_fadeOutDuration, () {
      if (!mounted) return;
      setState(() {
        _stickers.removeWhere((s) => s.id == id);
      });
    });
  }

  /// 检查位置是否在核心输入区（日期、心情、输入框）
  /// 这是用户主要交互区域，贴纸不能遮挡这里
  bool _isInCoreContentArea(double x, double y) {
    // 核心输入区：日期卡片(0.08-0.22)、心情选择器(0.24-0.38)、标题输入(0.40-0.52)
    // 简化为一个连续区域
    const coreLeft = 0.08;
    const coreRight = 0.92;
    const coreTop = 0.10;
    const coreBottom = 0.55;
    
    // 检查是否在这个矩形区域内
    if (x >= coreLeft && x <= coreRight && y >= coreTop && y <= coreBottom) {
      // 在核心区内，计算到中心的距离
      final centerX = (coreLeft + coreRight) / 2; // 0.50
      final centerY = (coreTop + coreBottom) / 2; // 0.325
      final distance = sqrt(pow(x - centerX, 2) + pow(y - centerY, 2));
      
      // 只避开最核心的30%区域（日期和心情卡片）
      // 边缘区域（如x接近0.08或0.92）允许出现
      return distance < 0.25;
    }
    
    // 不在核心区内，允许出现
    return false;
  }

  /// 检查位置是否太靠近现有贴图
  bool _isTooCloseToExistingStickers(double x, double y) {
    const minDistance = 0.25; // 最小间距25%，避免重叠
    for (final sticker in _stickers) {
      final distance =
          sqrt(pow(x - sticker.positionX, 2) + pow(y - sticker.positionY, 2));
      if (distance < minDistance) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _stickers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: _stickers.map((sticker) => _buildSticker(sticker)).toList(),
    );
  }

  Widget _buildSticker(RandomStickerDisplay sticker) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final left = sticker.positionX * screenWidth;
    final top = sticker.positionY * screenHeight;

    // 计算贴图最大显示尺寸（最长边）
    // 基础大小40px，根据scale变化范围 20px - 56px
    final maxSize = 40 * sticker.scale;

    return Positioned(
      left: left - maxSize / 2,
      top: top - maxSize / 2,
      child: AnimatedOpacity(
        opacity: sticker.opacity,
        duration: sticker.isVisible ? _fadeInDuration : _fadeOutDuration,
        curve: sticker.isVisible ? Curves.easeOut : Curves.easeIn,
        child: AnimatedScale(
          scale: sticker.isVisible ? 1.0 : 0.5,
          duration: sticker.isVisible ? _fadeInDuration : _fadeOutDuration,
          curve: sticker.isVisible ? Curves.elasticOut : Curves.easeIn,
          child: Transform.rotate(
            angle: sticker.rotation,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: maxSize,
                maxHeight: maxSize,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: sticker.isEmoji
                    ? Container(
                        width: maxSize * 0.8,
                        height: maxSize * 0.8,
                        alignment: Alignment.center,
                        child: Text(
                          sticker.emoji!,
                          style: TextStyle(fontSize: maxSize * 0.64),
                        ),
                      )
                    : _buildStickerImage(sticker.imagePath!, maxSize),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建贴纸图片，支持非正方形比例
  Widget _buildStickerImage(String imagePath, double maxSize) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return PlatformImage(
          path: imagePath,
          width: maxSize,
          height: maxSize,
          fit: BoxFit.contain,
          cacheWidth: 150,
          cacheHeight: 150,
        );
      },
    );
  }
}

/// 随机贴图显示数据
class RandomStickerDisplay {
  final String id;
  final bool isEmoji;
  final String? imagePath;
  final String? emoji;
  final double positionX;
  final double positionY;
  final double rotation;
  final double scale;
  final double opacity; // 透明度，用于淡入淡出动画
  final bool isVisible; // 是否可见状态，控制动画方向

  RandomStickerDisplay({
    required this.id,
    required this.isEmoji,
    this.imagePath,
    this.emoji,
    required this.positionX,
    required this.positionY,
    required this.rotation,
    required this.scale,
    this.opacity = 1.0,
    this.isVisible = true,
  }) : assert(
          isEmoji ? emoji != null : imagePath != null,
          'isEmoji为true时emoji不能为null，为false时imagePath不能为null',
        );

  /// 创建副本，用于动画状态更新
  RandomStickerDisplay copyWith({
    String? id,
    bool? isEmoji,
    String? imagePath,
    String? emoji,
    double? positionX,
    double? positionY,
    double? rotation,
    double? scale,
    double? opacity,
    bool? isVisible,
  }) {
    return RandomStickerDisplay(
      id: id ?? this.id,
      isEmoji: isEmoji ?? this.isEmoji,
      imagePath: imagePath ?? this.imagePath,
      emoji: emoji ?? this.emoji,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      opacity: opacity ?? this.opacity,
      isVisible: isVisible ?? this.isVisible,
    );
  }
}
