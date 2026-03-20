import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../services/motion_photo_service.dart';

/// 实况图片预览组件
/// 支持长按播放实况视频
class MotionPhotoWidget extends StatefulWidget {
  final String imagePath;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;

  const MotionPhotoWidget({
    super.key,
    required this.imagePath,
    this.width = 100,
    this.height = 100,
    this.borderRadius,
    this.onTap,
    this.onLongPress,
    this.onDelete,
  });

  @override
  State<MotionPhotoWidget> createState() => _MotionPhotoWidgetState();
}

class _MotionPhotoWidgetState extends State<MotionPhotoWidget>
    with SingleTickerProviderStateMixin {
  bool _isMotionPhoto = false;
  bool _isLoading = true;
  String? _videoPath;
  late AnimationController _badgeController;

  @override
  void initState() {
    super.initState();
    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _checkMotionPhoto();
  }

  @override
  void dispose() {
    _badgeController.dispose();
    super.dispose();
  }

  Future<void> _checkMotionPhoto() async {
    try {
      final isMotion = await MotionPhotoService().isMotionPhoto(widget.imagePath);
      if (isMotion) {
        final info = await MotionPhotoService().getInfo(widget.imagePath);
        if (mounted) {
          setState(() {
            _isMotionPhoto = true;
            _videoPath = info?.videoPath;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isMotionPhoto = false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('MotionPhotoWidget: 检测失败: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showVideoPlayer() {
    if (_videoPath == null || !File(_videoPath!).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('视频文件不存在')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MotionPhotoVideoPlayer(
          videoPath: _videoPath!,
          imagePath: widget.imagePath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        if (_isMotionPhoto && _videoPath != null) {
          _showVideoPlayer();
        }
        widget.onLongPress?.call();
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
          color: Colors.grey[200],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 图片
            Image.file(
              File(widget.imagePath),
              fit: BoxFit.cover,
              width: widget.width,
              height: widget.height,
            ),
            
            // 实况标识
            if (_isMotionPhoto && !_isLoading)
              Positioned(
                top: 6,
                right: 6,
                child: AnimatedBuilder(
                  animation: _badgeController,
                  builder: (context, child) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(
                              0.5 + 0.3 * _badgeController.value,
                            ),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            color: Colors.orange.shade300,
                            size: 12,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '实况',
                            style: TextStyle(
                              color: Colors.orange.shade300,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            
            // 长按提示
            if (_isMotionPhoto && !_isLoading)
              Positioned(
                bottom: 6,
                left: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '长按播放',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
            
            // 删除按钮
            if (widget.onDelete != null)
              Positioned(
                top: 4,
                left: 4,
                child: GestureDetector(
                  onTap: widget.onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 实况视频播放器
class MotionPhotoVideoPlayer extends StatefulWidget {
  final String videoPath;
  final String imagePath;

  const MotionPhotoVideoPlayer({
    super.key,
    required this.videoPath,
    required this.imagePath,
  });

  @override
  State<MotionPhotoVideoPlayer> createState() => _MotionPhotoVideoPlayerState();
}

class _MotionPhotoVideoPlayerState extends State<MotionPhotoVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    try {
      _controller = VideoPlayerController.file(File(widget.videoPath));
      
      await _controller!.initialize();
      
      // 设置循环播放
      await _controller!.setLooping(true);
      
      // 自动开始播放
      await _controller!.play();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isPlaying = true;
        });
      }

      // 监听播放状态
      _controller!.addListener(_onVideoStateChanged);
    } catch (e) {
      print('MotionPhotoVideoPlayer: 初始化失败: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _onVideoStateChanged() {
    if (!mounted || _controller == null) return;
    
    final isPlaying = _controller!.value.isPlaying;
    if (isPlaying != _isPlaying) {
      setState(() => _isPlaying = isPlaying);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoStateChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_controller == null) return;
    
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频播放器
            if (_isInitialized && _controller != null)
              GestureDetector(
                onTap: _togglePlay,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              )
            else if (_hasError)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '视频播放失败',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '加载视频中...',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

            // 播放/暂停按钮（中央）
            if (_isInitialized && !_isPlaying)
              Center(
                child: GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),

            // 顶部控制栏
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                      const Expanded(
                        child: Text(
                          '实况照片',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),

            // 底部控制栏
            if (_isInitialized && _controller != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 进度条
                        VideoProgressIndicator(
                          _controller!,
                          allowScrubbing: true,
                          colors: VideoProgressColors(
                            playedColor: Colors.orange,
                            bufferedColor: Colors.grey.shade600,
                            backgroundColor: Colors.grey.shade800,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        
                        // 控制按钮
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: _togglePlay,
                              icon: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // 显示当前时间/总时长
                            ValueListenableBuilder<VideoPlayerValue>(
                              valueListenable: _controller!,
                              builder: (context, value, child) {
                                final position = value.position;
                                final duration = value.duration;
                                return Text(
                                  '${_formatDuration(position)} / ${_formatDuration(duration)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

/// 实况图片网格组件
class MotionPhotoGrid extends StatelessWidget {
  final List<String> imagePaths;
  final Function(int)? onDelete;
  final Function(int)? onTap;

  const MotionPhotoGrid({
    super.key,
    required this.imagePaths,
    this.onDelete,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(imagePaths.length, (index) {
        return MotionPhotoWidget(
          imagePath: imagePaths[index],
          width: 100,
          height: 100,
          onTap: () => onTap?.call(index),
          onDelete: onDelete != null ? () => onDelete!.call(index) : null,
        );
      }),
    );
  }
}
