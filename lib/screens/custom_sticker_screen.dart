// ignore: unused_import
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config/app_theme.dart';
import '../utils/platform_helpers.dart';

/// 自定义贴图类型
enum CustomStickerType {
  image,  // 图片
  emoji,  // 表情
}

/// 自定义贴图模型
class CustomSticker {
  final String id;
  final CustomStickerType type;
  final String? imagePath;
  final String? emoji;
  double scale;
  double rotation;
  double offsetX;
  double offsetY;
  String targetPage; // 'calendar', 'diary', 'all'

  CustomSticker({
    required this.id,
    required this.type,
    this.imagePath,
    this.emoji,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.targetPage = 'all',
  }) : assert(type == CustomStickerType.image ? imagePath != null : emoji != null);

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'imagePath': imagePath,
    'emoji': emoji,
    'scale': scale,
    'rotation': rotation,
    'offsetX': offsetX,
    'offsetY': offsetY,
    'targetPage': targetPage,
  };

  factory CustomSticker.fromMap(Map<String, dynamic> map) => CustomSticker(
    id: map['id'],
    type: CustomStickerType.values.firstWhere(
      (e) => e.name == (map['type'] ?? 'image'),
      orElse: () => CustomStickerType.image,
    ),
    imagePath: map['imagePath'],
    emoji: map['emoji'],
    scale: (map['scale'] ?? 1.0).toDouble(),
    rotation: (map['rotation'] ?? 0.0).toDouble(),
    offsetX: (map['offsetX'] ?? 0.0).toDouble(),
    offsetY: (map['offsetY'] ?? 0.0).toDouble(),
    targetPage: map['targetPage'] ?? 'all',
  );

  CustomSticker copyWith({
    String? id,
    CustomStickerType? type,
    String? imagePath,
    String? emoji,
    double? scale,
    double? rotation,
    double? offsetX,
    double? offsetY,
    String? targetPage,
  }) {
    return CustomSticker(
      id: id ?? this.id,
      type: type ?? this.type,
      imagePath: imagePath ?? this.imagePath,
      emoji: emoji ?? this.emoji,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      targetPage: targetPage ?? this.targetPage,
    );
  }
}

/// 自定义贴图管理页面
class CustomStickerScreen extends StatefulWidget {
  const CustomStickerScreen({super.key});

  @override
  State<CustomStickerScreen> createState() => _CustomStickerScreenState();
}

class _CustomStickerScreenState extends State<CustomStickerScreen> {
  List<CustomSticker> _stickers = [];
  bool _isLoading = true;

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
      _stickers = list.map((e) => CustomSticker.fromMap(e)).toList();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveStickers() async {
    final prefs = await SharedPreferences.getInstance();
    final stickersJson = jsonEncode(_stickers.map((e) => e.toMap()).toList());
    await prefs.setString('custom_stickers', stickersJson);
  }

  Future<void> _addSticker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.path != null) {
        final sticker = CustomSticker(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: CustomStickerType.image,
          imagePath: file.path!,
        );
        setState(() {
          _stickers.add(sticker);
        });
        await _saveStickers();
      }
    }
  }

  Future<void> _addEmojiSticker(String emoji) async {
    final sticker = CustomSticker(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: CustomStickerType.emoji,
      emoji: emoji,
    );
    setState(() {
      _stickers.add(sticker);
    });
    await _saveStickers();
  }

  Future<void> _editSticker(CustomSticker sticker) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StickerEditorScreen(sticker: sticker),
      ),
    );

    if (result != null && result is CustomSticker) {
      final index = _stickers.indexWhere((s) => s.id == sticker.id);
      if (index != -1) {
        setState(() {
          _stickers[index] = result;
        });
        await _saveStickers();
      }
    }
  }

  Future<void> _deleteSticker(CustomSticker sticker) async {
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
      setState(() {
        _stickers.removeWhere((s) => s.id == sticker.id);
      });
      await _saveStickers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('自定义贴图', style: TextStyle(color: scheme.textDarkColor)),
        iconTheme: IconThemeData(color: scheme.textDarkColor),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _stickers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 64,
                        color: scheme.textLightColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无自定义贴图',
                        style: TextStyle(
                          fontSize: 16,
                          color: scheme.textMediumColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '点击下方按钮添加贴图',
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.textLightColor,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _stickers.length,
                  itemBuilder: (context, index) {
                    final sticker = _stickers[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 0,
                      color: scheme.cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 50,
                            height: 50,
                            color: scheme.lightColor.withOpacity(0.2),
                            child: Center(
                              child: sticker.type == CustomStickerType.emoji
                                  ? Text(
                                      sticker.emoji!,
                                      style: const TextStyle(fontSize: 32),
                                    )
                                  : PlatformImage(
                                      path: sticker.imagePath!,
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      cacheWidth: 100,
                                      cacheHeight: 100,
                                    ),
                            ),
                          ),
                        ),
                        title: Text(
                          sticker.type == CustomStickerType.emoji ? '表情贴图' : '贴图 ${index + 1}',
                          style: TextStyle(color: scheme.textDarkColor),
                        ),
                        subtitle: Text(
                          '${sticker.type == CustomStickerType.emoji ? sticker.emoji! : ''} 缩放: ${(sticker.scale * 100).toInt()}% | 旋转: ${(sticker.rotation * 180 / 3.14159).toInt()}°',
                          style: TextStyle(color: scheme.textLightColor),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit, color: scheme.primaryColor),
                              onPressed: () => _editSticker(sticker),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteSticker(sticker),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSticker,
        backgroundColor: scheme.primaryColor,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 贴图编辑器页面 - 简化版，仅保留缩放、旋转和页面选择
/// 位置调整改为在目标页面直接拖拽
class StickerEditorScreen extends StatefulWidget {
  final CustomSticker sticker;

  const StickerEditorScreen({super.key, required this.sticker});

  @override
  State<StickerEditorScreen> createState() => _StickerEditorScreenState();
}

class _StickerEditorScreenState extends State<StickerEditorScreen> {
  late double _scale;
  late double _rotation;
  late String _targetPage;

  @override
  void initState() {
    super.initState();
    _scale = widget.sticker.scale;
    _rotation = widget.sticker.rotation;
    _targetPage = widget.sticker.targetPage;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('调整贴图', style: TextStyle(color: scheme.textDarkColor)),
        iconTheme: IconThemeData(color: scheme.textDarkColor),
        actions: [
          TextButton(
            onPressed: () {
              final result = widget.sticker.copyWith(
                scale: _scale,
                rotation: _rotation,
                targetPage: _targetPage,
              );
              Navigator.pop(context, result);
            },
            child: Text('保存', style: TextStyle(color: scheme.primaryColor)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 预览区域
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: scheme.cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Transform.rotate(
                  angle: _rotation,
                  child: Transform.scale(
                    scale: _scale,
                    child: widget.sticker.type == CustomStickerType.emoji
                        ? Text(
                            widget.sticker.emoji!,
                            style: const TextStyle(fontSize: 100),
                          )
                        : PlatformImage(
                            path: widget.sticker.imagePath!,
                            width: 150,
                            height: 150,
                            fit: BoxFit.contain,
                            cacheWidth: 300,
                            cacheHeight: 300,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 说明文字
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.lightColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: scheme.primaryColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '位置调整：在日历或日记页面长按贴图并拖动即可调整位置',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.textMediumColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 缩放滑块
            Text('缩放: ${(_scale * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                )),
            const SizedBox(height: 8),
            Slider(
              value: _scale,
              min: 0.3,
              max: 2.0,
              divisions: 17,
              activeColor: scheme.primaryColor,
              onChanged: (value) => setState(() => _scale = value),
            ),
            const SizedBox(height: 16),

            // 旋转滑块
            Text('旋转: ${(_rotation * 180 / 3.14159).toInt()}°',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                )),
            const SizedBox(height: 8),
            Slider(
              value: _rotation,
              min: -3.14159,
              max: 3.14159,
              divisions: 36,
              activeColor: scheme.primaryColor,
              onChanged: (value) => setState(() => _rotation = value),
            ),
            const SizedBox(height: 24),

            // 显示位置选择
            Text('显示位置',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.textDarkColor)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                ChoiceChip(
                  label: const Text('所有页面'),
                  selected: _targetPage == 'all',
                  onSelected: (selected) {
                    if (selected) setState(() => _targetPage = 'all');
                  },
                ),
                ChoiceChip(
                  label: const Text('仅日历'),
                  selected: _targetPage == 'calendar',
                  onSelected: (selected) {
                    if (selected) setState(() => _targetPage = 'calendar');
                  },
                ),
                ChoiceChip(
                  label: const Text('仅日记'),
                  selected: _targetPage == 'diary',
                  onSelected: (selected) {
                    if (selected) setState(() => _targetPage = 'diary');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
