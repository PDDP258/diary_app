import 'dart:async';
import 'dart:math';
// ignore: unused_import
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';
import '../providers/diary_provider.dart';
import '../utils/platform_helpers.dart';
import 'diary_detail_screen.dart';

/// 日记电影放映模式
/// 以电影字幕的方式快速预览所有日记，带有动态字体大小效果
class DiaryCinemaScreen extends StatefulWidget {
  const DiaryCinemaScreen({super.key});

  @override
  State<DiaryCinemaScreen> createState() => _DiaryCinemaScreenState();
}

class _DiaryCinemaScreenState extends State<DiaryCinemaScreen>
    with TickerProviderStateMixin {
  final Random _random = Random();
  List<Diary> _diaries = [];
  int _currentIndex = 0;
  final bool _isPlaying = true;
  bool _isPaused = false;
  double _playbackSpeed = 2.0;

  // 动画控制器
  late AnimationController _textController1;
  late AnimationController _textController2;
  late AnimationController _bgController;

  // 当前显示的文本片段
  List<TextSegment> _currentSegments1 = [];
  List<TextSegment> _currentSegments2 = [];
  Timer? _autoPlayTimer;

  // 背景颜色动画
  late Animation<Color?> _bgColorAnimation;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _loadDiaries();
  }

  void _initControllers() {
    _textController1 = AnimationController(
      duration: const Duration(milliseconds: 500), // 原来是1000，加快
      vsync: this,
    );

    _textController2 = AnimationController(
      duration: const Duration(milliseconds: 500), // 原来是1000，加快
      vsync: this,
    );

    _bgController = AnimationController(
      duration: const Duration(seconds: 5), // 原来是10秒，加快
      vsync: this,
    );

    _bgColorAnimation = TweenSequence<Color?>([
      TweenSequenceItem(
        tween: ColorTween(
          begin: const Color(0xFF1a1a2e),
          end: const Color(0xFF16213e),
        ),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: ColorTween(
          begin: const Color(0xFF16213e),
          end: const Color(0xFF0f3460),
        ),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: ColorTween(
          begin: const Color(0xFF0f3460),
          end: const Color(0xFF1a1a2e),
        ),
        weight: 1,
      ),
    ]).animate(_bgController);

    _bgController.repeat();
  }

  void _loadDiaries() {
    final provider = context.read<DiaryProvider>();
    _diaries = List.from(provider.diaries)
      ..sort((a, b) => b.date.compareTo(a.date));

    if (_diaries.isNotEmpty) {
      _processCurrentDiaries();
    }
  }

  /// 处理当前两篇日记
  void _processCurrentDiaries() {
    if (_currentIndex >= _diaries.length) {
      _currentIndex = 0; // 循环播放
    }

    // 第一篇日记
    final diary1 = _diaries[_currentIndex];
    _currentSegments1 = _extractSegments(diary1);

    // 第二篇日记（循环）
    final secondIndex = (_currentIndex + 1) % _diaries.length;
    final diary2 = _diaries[secondIndex];
    _currentSegments2 = _extractSegments(diary2);

    if (mounted) {
      setState(() {});
      _startTextAnimation();
    }
  }

  /// 获取第一篇日记的图片列表
  List<String> get _currentImages1 {
    if (_diaries.isEmpty || _currentIndex >= _diaries.length) return [];
    return _diaries[_currentIndex].imageList;
  }

  /// 获取第二篇日记的图片列表
  List<String> get _currentImages2 {
    if (_diaries.isEmpty) return [];
    final secondIndex = (_currentIndex + 1) % _diaries.length;
    return _diaries[secondIndex].imageList;
  }

  /// 从日记中提取文本片段，生成动态大小效果
  List<TextSegment> _extractSegments(Diary diary) {
    final List<TextSegment> segments = [];
    final String text = diary.content ?? diary.title ?? '无内容';

    // 分句
    final sentences = text
        .split(RegExp(r'[。！？.!?\n]+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    if (sentences.isEmpty) {
      return [TextSegment(text: text, size: 20, isHighlight: false)];
    }

    // 为每个句子分配字体大小
    for (final sentence in sentences) {
      final trimmed = sentence.trim();
      if (trimmed.length < 2) continue; // 至少2个字符才处理

      // 将长句分成多个片段
      if (trimmed.length > 30) {
        final words = trimmed.split('');
        int i = 0;

        while (i < words.length) {
          // 决定这个片段的长度（4-12个字）
          final segmentLength = 4 + _random.nextInt(9);
          final end = (i + segmentLength < words.length)
              ? i + segmentLength
              : words.length;

          // 提取片段
          String segmentText = words.sublist(i, end).join('');

          // 决定这个片段的样式
          final isHighlight = _random.nextDouble() < 0.2; // 20%概率高亮
          final double size;

          if (isHighlight) {
            // 高亮片段：大字体
            size = 28 + _random.nextDouble() * 12; // 28-40
          } else {
            // 普通片段：中等或小字体
            final sizeRoll = _random.nextDouble();
            if (sizeRoll < 0.3) {
              size = 14 + _random.nextDouble() * 4; // 14-18 小字
            } else if (sizeRoll < 0.7) {
              size = 18 + _random.nextDouble() * 6; // 18-24 中字
            } else {
              size = 24 + _random.nextDouble() * 4; // 24-28 大字
            }
          }

          segments.add(TextSegment(
            text: segmentText,
            size: size,
            isHighlight: isHighlight,
            diary: diary,
          ));

          i = end;
        }
      } else {
        // 短句作为一个片段
        final isHighlight = _random.nextDouble() < 0.25;
        final double size = isHighlight
            ? 28 + _random.nextDouble() * 8
            : 18 + _random.nextDouble() * 8;

        segments.add(TextSegment(
          text: trimmed,
          size: size,
          isHighlight: isHighlight,
          diary: diary,
        ));
      }
    }

    // 确保至少有5个片段用于展示
    if (segments.length < 5 && text.length > 20) {
      // 重新切分
      return _extractFineSegments(text, diary);
    }

    return segments;
  }

  /// 精细切分，确保片段数量足够
  List<TextSegment> _extractFineSegments(String text, Diary diary) {
    final List<TextSegment> segments = [];
    final words = text.split('');
    int i = 0;

    while (i < words.length && segments.length < 15) {
      final segmentLength = 3 + _random.nextInt(6);
      final end =
          (i + segmentLength < words.length) ? i + segmentLength : words.length;

      final segmentText = words.sublist(i, end).join('');

      // 确保高亮比例约 1:5
      final isHighlight = segments.length % 5 == 0;
      final double size = isHighlight
          ? 28 + _random.nextDouble() * 12
          : 16 + _random.nextDouble() * 10;

      segments.add(TextSegment(
        text: segmentText,
        size: size,
        isHighlight: isHighlight,
        diary: diary,
      ));

      i = end;
    }

    return segments;
  }

  void _startTextAnimation() {
    _textController1.forward(from: 0);
    _textController2.forward(from: 0);

    // 根据内容长度和播放速度计算展示时间
    // 基础时间 + 每段文字额外时间 + 图片额外时间
    // 速度加快三倍：将时间除以3
    final segmentCount = _currentSegments1.length + _currentSegments2.length;
    final imageCount = _currentImages1.length + _currentImages2.length;
    const baseTime = 1333; // ~4000/3 基础展示时间
    const segmentTime = 267; // ~800/3 每段文字
    const imageTime = 667; // ~2000/3 每张图片

    final totalDuration = Duration(
      milliseconds:
          ((baseTime + segmentCount * segmentTime + imageCount * imageTime) /
                  _playbackSpeed)
              .toInt(),
    );

    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer(totalDuration, () {
      if (_isPlaying && !_isPaused && mounted) {
        _nextDiaries();
      }
    });
  }

  void _nextDiaries() {
    setState(() {
      _currentIndex += 2;
      if (_currentIndex >= _diaries.length) {
        _currentIndex = 0;
      }
    });
    _processCurrentDiaries();
  }

  void _previousDiaries() {
    setState(() {
      _currentIndex -= 2;
      if (_currentIndex < 0) {
        _currentIndex = _diaries.length - 2;
        if (_currentIndex < 0) _currentIndex = 0;
      }
    });
    _processCurrentDiaries();
  }

  void _togglePause() {
    setState(() {
      _isPaused = !_isPaused;
      if (_isPaused) {
        _textController1.stop();
        _textController2.stop();
        _autoPlayTimer?.cancel();
      } else {
        _textController1.forward();
        _textController2.forward();
        _startTextAnimation();
      }
    });
  }

  void _setSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    if (!_isPaused) {
      _startTextAnimation();
    }
  }

  @override
  void dispose() {
    _textController1.dispose();
    _textController2.dispose();
    _bgController.dispose();
    _autoPlayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_diaries.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF1a1a2e),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.movie_outlined,
                size: 64,
                color: Colors.white30,
              ),
              const SizedBox(height: 16),
              const Text(
                '还没有日记',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    final currentDiary1 = _diaries[_currentIndex];
    final currentDiary2 = _diaries[(_currentIndex + 1) % _diaries.length];

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _bgController,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _bgColorAnimation.value ?? const Color(0xFF1a1a2e),
                  const Color(0xFF0f0f1a),
                ],
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  // 双栏主要内容区域
                  _buildDualContent(currentDiary1, currentDiary2),

                  // 顶部控制栏
                  _buildTopBar(currentDiary1, currentDiary2),

                  // 底部控制栏
                  _buildBottomBar(),

                  // 进度条
                  _buildProgressBar(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 双栏布局 - 同时显示两篇日记
  Widget _buildDualContent(Diary diary1, Diary diary2) {
    return GestureDetector(
      onTap: _togglePause,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 60, 8, 100),
        child: Row(
          children: [
            // 左侧日记
            Expanded(
              child: _buildDiaryCard(
                diary: diary1,
                segments: _currentSegments1,
                images: _currentImages1,
                controller: _textController1,
                onDoubleTap: () => _viewDiary(diary1),
              ),
            ),
            // 分隔线
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: Colors.white.withValues(alpha: 0.2),
            ),
            // 右侧日记
            Expanded(
              child: _buildDiaryCard(
                diary: diary2,
                segments: _currentSegments2,
                images: _currentImages2,
                controller: _textController2,
                onDoubleTap: () => _viewDiary(diary2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单篇日记卡片
  Widget _buildDiaryCard({
    required Diary diary,
    required List<TextSegment> segments,
    required List<String> images,
    required AnimationController controller,
    required VoidCallback onDoubleTap,
  }) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 日期和标题区域
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (diary.moodEmoji != null)
                        Text(
                          diary.moodEmoji!,
                          style: const TextStyle(fontSize: 20),
                        ),
                      if (diary.moodEmoji != null) const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _formatDate(diary.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.6),
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (diary.title != null && diary.title!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      diary.title!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 图片区域（如果有）
            if (images.isNotEmpty) ...[
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    return _buildCinemaImage(images[index]);
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 动态文本区域
            Expanded(
              child: _buildAnimatedText(segments, controller),
            ),
          ],
        ),
      ),
    );
  }

  /// 动态文字显示组件 - 修复文字不显示问题
  Widget _buildAnimatedText(List<TextSegment> segments, AnimationController controller) {
    if (segments.isEmpty) {
      return const Center(
        child: Text(
          '无内容',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 16,
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Wrap(
            spacing: 6,
            runSpacing: 8,
            children: segments.asMap().entries.map((entry) {
              final index = entry.key;
              final segment = entry.value;
              
              // 计算动画进度 - 修复：确保文字能正确显示
              final totalSegments = segments.length;
              final segmentDuration = 1.0 / totalSegments;
              final segmentStart = index * segmentDuration;
              final segmentEnd = segmentStart + segmentDuration;
              
              double segmentProgress;
              if (controller.value >= segmentEnd) {
                // 已完成，完全显示
                segmentProgress = 1.0;
              } else if (controller.value <= segmentStart) {
                // 还未开始，隐藏
                segmentProgress = 0.0;
              } else {
                // 动画中
                segmentProgress = (controller.value - segmentStart) / segmentDuration;
              }
              
              // 淡入效果
              final opacity = Curves.easeOut.transform(
                segmentProgress.clamp(0.0, 1.0)
              );

              // 轻微缩放效果
              final scale = 0.8 + (0.2 * segmentProgress.clamp(0.0, 1.0));

              return Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: segment.isHighlight
                        ? const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          )
                        : EdgeInsets.zero,
                    decoration: segment.isHighlight
                        ? BoxDecoration(
                            color: AppTheme.selectedGreen
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          )
                        : null,
                    child: Text(
                      segment.text,
                      style: TextStyle(
                        fontSize: segment.size * 0.85, // 稍微缩小以适应双栏
                        color: segment.isHighlight
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.9),
                        fontWeight: segment.isHighlight
                            ? FontWeight.bold
                            : FontWeight.normal,
                        height: 1.3,
                        letterSpacing: segment.isHighlight ? 0.5 : 0.3,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildCinemaImage(String path) {
    return Container(
      width: 100,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white.withValues(alpha: 0.1),
      ),
      clipBehavior: Clip.antiAlias,
      child: PlatformImage(
        path: path,
        width: 100,
        height: 80,
        fit: BoxFit.cover,
        cacheWidth: 200,
        cacheHeight: 160,
      ),
    );
  }

  Widget _buildTopBar(Diary diary1, Diary diary2) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            // 日记计数
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${_currentIndex + 1}-${(_currentIndex + 2) > _diaries.length ? _diaries.length : _currentIndex + 2} / ${_diaries.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.9),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 上一条
              IconButton(
                icon: const Icon(Icons.skip_previous, color: Colors.white),
                onPressed: _previousDiaries,
              ),

              const SizedBox(width: 16),

              // 播放/暂停
              GestureDetector(
                onTap: _togglePause,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    _isPaused ? Icons.play_arrow : Icons.pause,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // 下一条
              IconButton(
                icon: const Icon(Icons.skip_next, color: Colors.white),
                onPressed: _nextDiaries,
              ),

              const SizedBox(width: 24),

              // 速度控制
              PopupMenuButton<double>(
                initialValue: _playbackSpeed,
                onSelected: _setSpeed,
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 0.5, child: Text('0.5x 慢速')),
                  const PopupMenuItem(value: 1.0, child: Text('1.0x 正常')),
                  const PopupMenuItem(value: 1.5, child: Text('1.5x 快速')),
                  const PopupMenuItem(value: 2.0, child: Text('2.0x 较快')),
                  const PopupMenuItem(value: 3.0, child: Text('3.0x 高速')),
                  const PopupMenuItem(value: 4.0, child: Text('4.0x 极速')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_playbackSpeed}x',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Positioned(
      bottom: 100,
      left: 32,
      right: 32,
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(2),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: (_currentIndex + 2) / _diaries.length,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.selectedGreen,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('yyyy年M月d日', 'zh_CN').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  Future<void> _viewDiary(Diary diary) async {
    final wasPaused = _isPaused;
    setState(() {
      _isPaused = true;
      _textController1.stop();
      _textController2.stop();
      _autoPlayTimer?.cancel();
    });

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiaryDetailScreen(diary: diary),
      ),
    );

    if (result == true) {
      _loadDiaries();
    }

    if (!wasPaused && mounted) {
      setState(() {
        _isPaused = false;
        _textController1.forward();
        _textController2.forward();
        _startTextAnimation();
      });
    }
  }
}

/// 文本片段
class TextSegment {
  final String text;
  final double size;
  final bool isHighlight;
  final Diary? diary;

  TextSegment({
    required this.text,
    required this.size,
    required this.isHighlight,
    this.diary,
  });
}
