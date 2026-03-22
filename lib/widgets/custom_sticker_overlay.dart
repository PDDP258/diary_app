import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../screens/custom_sticker_screen.dart';
import '../utils/platform_helpers.dart';

/// 自定义贴图覆盖层组件
/// 用于在日历和日记页面显示用户自定义的贴图
/// 支持在页面上直接拖拽调整位置
class CustomStickerOverlay extends StatefulWidget {
  final String targetPage;

  const CustomStickerOverlay({
    super.key,
    required this.targetPage,
  });

  @override
  State<CustomStickerOverlay> createState() => _CustomStickerOverlayState();
}

class _CustomStickerOverlayState extends State<CustomStickerOverlay> {
  List<StickerPosition> _stickers = [];
  bool _isLoading = true;
  StickerPosition? _draggingSticker;

  @override
  void initState() {
    super.initState();
    _loadStickers();
  }

  Future<void> _loadStickers() async {
    final prefs = await SharedPreferences.getInstance();
    final stickersJson = prefs.getString('custom_stickers');
    if (stickersJson != null) {
      final List<dynamic> list = jsonDecode(stickersJson);
      _stickers = list
          .map((e) => StickerPosition.fromSticker(CustomSticker.fromMap(e)))
          .where(
              (s) => s.targetPage == 'all' || s.targetPage == widget.targetPage)
          .toList();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveStickerPosition(StickerPosition sticker) async {
    final prefs = await SharedPreferences.getInstance();
    final stickersJson = prefs.getString('custom_stickers');
    if (stickersJson != null) {
      final List<dynamic> list = jsonDecode(stickersJson);
      final stickers = list.map((e) => CustomSticker.fromMap(e)).toList();
      final index = stickers.indexWhere((s) => s.id == sticker.id);
      if (index != -1) {
        stickers[index] = sticker.toSticker(stickers[index]);
        await prefs.setString('custom_stickers',
            jsonEncode(stickers.map((e) => e.toMap()).toList()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _stickers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      children:
          _stickers.map((sticker) => _buildDraggableSticker(sticker)).toList(),
    );
  }

  Widget _buildDraggableSticker(StickerPosition sticker) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final left = sticker.positionX * screenWidth;
    final top = sticker.positionY * screenHeight;

    // 减小图片显示尺寸（从80改为60），避免遮挡内容
    final maxSize = 60 * sticker.scale;
    // 扩大点击区域，确保拖拽体验流畅，最小100x100
    final hitAreaSize = maxSize < 100 ? 100.0 : maxSize + 20;

    return Positioned(
      left: left - hitAreaSize / 2,
      top: top - hitAreaSize / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) {
          setState(() => _draggingSticker = sticker);
        },
        onPanUpdate: (details) {
          // 优化拖拽体验：使用更直接的坐标计算，减少阻力感
          setState(() {
            // 直接根据delta更新位置，无需重新计算left/top
            sticker.positionX = (sticker.positionX + details.delta.dx / screenWidth)
                .clamp(0.03, 0.97);
            sticker.positionY = (sticker.positionY + details.delta.dy / screenHeight)
                .clamp(0.05, 0.92);
          });
        },
        onPanEnd: (_) {
          _saveStickerPosition(sticker);
          setState(() => _draggingSticker = null);
        },
        onPanCancel: () {
          setState(() => _draggingSticker = null);
        },
        onLongPress: () => _showStickerOptions(sticker),
        child: Container(
          width: hitAreaSize,
          height: hitAreaSize,
          decoration: BoxDecoration(
            // 拖动时显示半透明背景提示可拖动区域
            color: _draggingSticker == sticker
                ? Colors.white.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: _draggingSticker == sticker
                ? Border.all(color: Colors.white.withOpacity(0.3), width: 1)
                : null,
          ),
          child: Center(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: maxSize,
                maxHeight: maxSize,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Transform.rotate(
                  angle: sticker.rotation,
                  child: sticker.type == CustomStickerType.emoji
                      ? Container(
                          width: maxSize * 0.8,
                          height: maxSize * 0.8,
                          alignment: Alignment.center,
                          child: Text(
                            sticker.emoji!,
                            style: TextStyle(fontSize: maxSize * 0.64),
                          ),
                        )
                      : PlatformImage(
                          path: sticker.imagePath!,
                          width: maxSize,
                          height: maxSize,
                          fit: BoxFit.contain,
                          cacheWidth: 200,
                          cacheHeight: 200,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showStickerOptions(StickerPosition sticker) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('编辑贴图（缩放/旋转）'),
                    onTap: () {
                      Navigator.pop(context);
                      _editSticker(sticker);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title:
                        const Text('删除贴图', style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.pop(context);
                      _deleteSticker(sticker);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '提示：按住并拖动贴图可调整位置',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _editSticker(StickerPosition stickerPos) async {
    final prefs = await SharedPreferences.getInstance();
    final stickersJson = prefs.getString('custom_stickers');
    if (stickersJson == null) return;

    final List<dynamic> list = jsonDecode(stickersJson);
    final stickers = list.map((e) => CustomSticker.fromMap(e)).toList();
    final index = stickers.indexWhere((s) => s.id == stickerPos.id);
    if (index == -1) return;

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StickerEditorScreen(sticker: stickers[index]),
      ),
    );

    if (!mounted) return;

    if (result != null && result is CustomSticker) {
      setState(() {
        stickers[index] = result;
        final posIndex = _stickers.indexWhere((s) => s.id == result.id);
        if (posIndex != -1) {
          _stickers[posIndex] = StickerPosition.fromSticker(result);
        }
      });
      await prefs.setString('custom_stickers',
          jsonEncode(stickers.map((e) => e.toMap()).toList()));
    }
  }

  Future<void> _deleteSticker(StickerPosition sticker) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个贴图吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      final stickersJson = prefs.getString('custom_stickers');
      if (stickersJson != null) {
        final List<dynamic> list = jsonDecode(stickersJson);
        final stickers = list.map((e) => CustomSticker.fromMap(e)).toList();
        stickers.removeWhere((s) => s.id == sticker.id);
        await prefs.setString('custom_stickers',
            jsonEncode(stickers.map((e) => e.toMap()).toList()));
        setState(() {
          _stickers.removeWhere((s) => s.id == sticker.id);
        });
      }
    }
  }
}

class StickerPosition {
  final String id;
  final CustomStickerType type;
  final String? imagePath;
  final String? emoji;
  final String targetPage;
  double positionX;
  double positionY;
  double scale;
  double rotation;

  StickerPosition({
    required this.id,
    required this.type,
    this.imagePath,
    this.emoji,
    required this.targetPage,
    required this.positionX,
    required this.positionY,
    required this.scale,
    required this.rotation,
  }) : assert(type == CustomStickerType.image
            ? imagePath != null
            : emoji != null);

  factory StickerPosition.fromSticker(CustomSticker sticker) {
    // 使用全局随机数生成器，避免多个实例产生相同的随机序列
    final random = Random();
    
    // 改进随机位置生成策略：
    // 1. 避开屏幕中央区域（0.3-0.7），避免遮挡内容
    // 2. 在屏幕边缘四个象限随机分布
    // 3. 增加随机性，确保每次都在不同位置
    
    final zone = random.nextInt(4); // 0:左上, 1:右上, 2:左下, 3:右下
    double baseX, baseY;
    
    switch (zone) {
      case 0: // 左上区域
        baseX = 0.08 + random.nextDouble() * 0.22;  // 0.08-0.30
        baseY = 0.10 + random.nextDouble() * 0.25;  // 0.10-0.35
        break;
      case 1: // 右上区域
        baseX = 0.70 + random.nextDouble() * 0.22;  // 0.70-0.92
        baseY = 0.10 + random.nextDouble() * 0.25;  // 0.10-0.35
        break;
      case 2: // 左下区域
        baseX = 0.08 + random.nextDouble() * 0.22;  // 0.08-0.30
        baseY = 0.70 + random.nextDouble() * 0.20;  // 0.70-0.90
        break;
      default: // 右下区域（zone 3）
        baseX = 0.70 + random.nextDouble() * 0.22;  // 0.70-0.92
        baseY = 0.70 + random.nextDouble() * 0.20;  // 0.70-0.90
        break;
    }
    
    return StickerPosition(
      id: sticker.id,
      type: sticker.type,
      imagePath: sticker.imagePath,
      emoji: sticker.emoji,
      targetPage: sticker.targetPage,
      positionX: baseX,
      positionY: baseY,
      // 稍微减小默认缩放比例，避免太大遮挡内容
      scale: sticker.scale * 0.85,
      rotation: sticker.rotation,
    );
  }

  CustomSticker toSticker(CustomSticker original) {
    return original.copyWith(
      scale: scale,
      rotation: rotation,
    );
  }
}
