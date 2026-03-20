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
  /// 每个贴图有独立的随机延迟，避免同时刷新
  void _scheduleNextSticker({bool initial = false}) {
    // 随机延迟：初始3-6秒（增加延迟避免重叠），后续5-12秒（降低刷新频率）
    final delaySeconds = initial
        ? 3.0 + _globalRandom.nextDouble() * 3.0 // 3-6秒
        : 5 + _globalRandom.nextInt(8); // 5-12秒

    Future.delayed(Duration(milliseconds: (delaySeconds * 1000).round()), () {
      if (!mounted) return;

      // 根据概率决定是否显示
      if (_globalRandom.nextDouble() < widget.appearProbability) {
        _addRandomSticker();
      }

      // 继续安排下一个
      _scheduleNextSticker();
    });
  }

  /// 添加一个随机贴图
  void _addRandomSticker() {
    if (_allAvailableStickers.isEmpty) return;

    // 随机选择一个贴图
    final sticker =
        _allAvailableStickers[_globalRandom.nextInt(_allAvailableStickers.length)];

    // 生成随机位置（避开中央和已有贴图）
    final position = _generateRandomPosition();
    if (position == null) return; // 找不到合适位置

    // 随机角度 (-30° 到 30°)
    final rotation = (_globalRandom.nextDouble() - 0.5) * 0.5;

    // 随机缩放 (0.6 到 1.2)
    final scale = 0.6 + _globalRandom.nextDouble() * 0.6;

    // 生成唯一ID
    final id =
        '${sticker.id}_${DateTime.now().millisecondsSinceEpoch}_${_globalRandom.nextInt(1000)}';

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
      opacity: 0.0, // 初始透明度为0
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

    // 安排这个贴图消失（5-15秒后）
    _scheduleStickerRemoval(id);
  }

  /// 生成随机位置，避开中央和已有贴图
  Offset? _generateRandomPosition() {
    double x, y;
    int attempts = 0;
    const maxAttempts = 30;

    do {
      // 使用更分散的随机策略
      // 将屏幕分成8个区域，随机选择区域后再随机位置
      final zone = _globalRandom.nextInt(8);
      switch (zone) {
        case 0: // 左上
          x = 0.05 + _globalRandom.nextDouble() * 0.35;
          y = 0.08 + _globalRandom.nextDouble() * 0.3;
          break;
        case 1: // 中上
          x = 0.4 + _globalRandom.nextDouble() * 0.2;
          y = 0.05 + _globalRandom.nextDouble() * 0.25;
          break;
        case 2: // 右上
          x = 0.6 + _globalRandom.nextDouble() * 0.35;
          y = 0.08 + _globalRandom.nextDouble() * 0.3;
          break;
        case 3: // 左中
          x = 0.03 + _globalRandom.nextDouble() * 0.25;
          y = 0.35 + _globalRandom.nextDouble() * 0.3;
          break;
        case 4: // 右中
          x = 0.72 + _globalRandom.nextDouble() * 0.25;
          y = 0.35 + _globalRandom.nextDouble() * 0.3;
          break;
        case 5: // 左下
          x = 0.05 + _globalRandom.nextDouble() * 0.35;
          y = 0.65 + _globalRandom.nextDouble() * 0.3;
          break;
        case 6: // 中下
          x = 0.4 + _globalRandom.nextDouble() * 0.2;
          y = 0.7 + _globalRandom.nextDouble() * 0.25;
          break;
        default: // 右下
          x = 0.6 + _globalRandom.nextDouble() * 0.35;
          y = 0.65 + _globalRandom.nextDouble() * 0.3;
          break;
      }
      attempts++;
    } while (attempts < maxAttempts &&
        (_isTooCloseToCenter(x, y) || _isTooCloseToExistingStickers(x, y)));

    if (attempts >= maxAttempts) return null;
    return Offset(x, y);
  }

  /// 安排贴图消失（带淡出动画）
  void _scheduleStickerRemoval(String id) {
    // 随机显示时长：3-8秒（更短的显示时间，提高刷新频率）
    final displayDuration = 3 + _globalRandom.nextInt(6);

    Future.delayed(Duration(seconds: displayDuration), () {
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
    });
  }

  /// 检查位置是否太靠近屏幕中央
  bool _isTooCloseToCenter(double x, double y) {
    const centerX = 0.5;
    const centerY = 0.5;
    final distance = sqrt(pow(x - centerX, 2) + pow(y - centerY, 2));
    return distance < 0.3; // 增加中央避开区域到30%
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
    final maxSize = 80 * sticker.scale;

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
