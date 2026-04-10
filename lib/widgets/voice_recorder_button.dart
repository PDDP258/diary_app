import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config/app_theme.dart';
import '../services/voice_diary_service.dart';
import '../providers/theme_provider.dart';

/// 语音录音按钮组件
class VoiceRecorderButton extends StatefulWidget {
  final Function(VoiceEntry)? onRecordingComplete;
  final String? date; // 关联的日记日期

  const VoiceRecorderButton({
    super.key,
    this.onRecordingComplete,
    this.date,
  });

  @override
  State<VoiceRecorderButton> createState() => _VoiceRecorderButtonState();
}

class _VoiceRecorderButtonState extends State<VoiceRecorderButton>
    with SingleTickerProviderStateMixin {
  final VoiceDiaryService _service = VoiceDiaryService.instance;
  
  RecordingState _state = RecordingState.idle;
  int _duration = 0;
  bool _showRecorder = false;
  
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _service.initialize();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    
    _animationController.repeat(reverse: true);
    
    // 监听状态变化
    _service.onStateChanged = (state) {
      if (mounted) {
        setState(() {
          _state = state;
        });
      }
    };
    
    _service.onDurationChanged = (duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    };
  }

  @override
  void dispose() {
    _animationController.dispose();
    _service.dispose();
    super.dispose();
  }

  String get _formattedDuration {
    final minutes = _duration ~/ 60;
    final seconds = _duration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _startRecording() async {
    HapticFeedback.mediumImpact();
    
    final hasPermission = await _service.requestPermission();
    if (!hasPermission) {
      _showPermissionDeniedDialog();
      return;
    }
    
    setState(() {
      _showRecorder = true;
      _duration = 0;
    });
    
    final success = await _service.startRecording();
    if (!success && mounted) {
      setState(() {
        _showRecorder = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('录音启动失败，请检查权限')),
      );
    }
  }

  Future<void> _stopRecording() async {
    HapticFeedback.mediumImpact();
    
    final entry = await _service.stopRecording(date: widget.date);
    
    if (mounted) {
      setState(() {
        _showRecorder = false;
        _duration = 0;
      });
      
      if (entry != null) {
        widget.onRecordingComplete?.call(entry);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('录音已保存 (${entry.formattedDuration})'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    await _service.cancelRecording();
    
    if (mounted) {
      setState(() {
        _showRecorder = false;
        _duration = 0;
      });
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要录音权限'),
        content: const Text('请在设置中允许应用使用麦克风，以录制语音日记。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // 打开应用设置
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    if (_showRecorder) {
      return _buildRecorderPanel(scheme);
    }
    
    return GestureDetector(
      onTap: _startRecording,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [scheme.darkColor, scheme.primaryColor],
          ),
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          boxShadow: AppTheme.floatingShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mic,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              '语音日记',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecorderPanel(ThemeScheme scheme) {
    final isRecording = _state == RecordingState.recording;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
        border: Border.all(
          color: isRecording ? Colors.red.withOpacity(0.3) : scheme.lightColor,
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 录音状态文字
          Text(
            isRecording ? '正在录音...' : '录音已暂停',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isRecording ? Colors.red : scheme.textMediumColor,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 时长显示
          Text(
            _formattedDuration,
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: scheme.textDarkColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // 录音波形动画
          if (isRecording)
            _buildWaveformAnimation(scheme),
          
          const SizedBox(height: 24),
          
          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 取消按钮
              GestureDetector(
                onTap: _cancelRecording,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.backgroundColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    color: scheme.textMediumColor,
                  ),
                ),
              ),
              
              const SizedBox(width: 24),
              
              // 录音/暂停按钮
              GestureDetector(
                onTap: () {
                  if (_state == RecordingState.recording) {
                    _service.pauseRecording();
                  } else if (_state == RecordingState.paused) {
                    _service.resumeRecording();
                  }
                },
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: isRecording ? _pulseAnimation.value : 1.0,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isRecording
                                ? [Colors.red, Colors.red.shade700]
                                : [scheme.primaryColor, scheme.darkColor],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (isRecording ? Colors.red : scheme.primaryColor)
                                  .withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: isRecording ? 5 : 0,
                            ),
                          ],
                        ),
                        child: Icon(
                          isRecording ? Icons.pause : Icons.mic,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              const SizedBox(width: 24),
              
              // 完成按钮
              GestureDetector(
                onTap: _stopRecording,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.success, AppTheme.success.withOpacity(0.8)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformAnimation(ThemeScheme scheme) {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(20, (index) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 4,
            height: 10 + (index % 5) * 6.0,
            decoration: BoxDecoration(
              color: scheme.primaryColor.withOpacity(0.5 + (index % 3) * 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

/// 语音播放器组件
class VoicePlayerWidget extends StatefulWidget {
  final VoiceEntry entry;
  final VoidCallback? onDeleted;

  const VoicePlayerWidget({
    super.key,
    required this.entry,
    this.onDeleted,
  });

  @override
  State<VoicePlayerWidget> createState() => _VoicePlayerWidgetState();
}

class _VoicePlayerWidgetState extends State<VoicePlayerWidget> {
  final VoiceDiaryService _service = VoiceDiaryService.instance;
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.entry.duration);
    
    _service.onPlayerStateChanged = (state) {
      if (mounted) {
        setState(() {
          _playerState = state;
        });
      }
    };
    
    _service.onPlayerPositionChanged = (position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    };
  }

  Future<void> _togglePlay() async {
    if (_playerState == PlayerState.playing) {
      await _service.pausePlayback();
    } else if (_playerState == PlayerState.paused) {
      await _service.resumePlayback();
    } else {
      await _service.playVoice(widget.entry.filePath);
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除语音'),
        content: const Text('确定要删除这条语音日记吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _service.deleteVoiceEntry(widget.entry);
      if (success) {
        widget.onDeleted?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final isPlaying = _playerState == PlayerState.playing;
    final progress = _duration.inSeconds > 0
        ? _position.inSeconds / _duration.inSeconds
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.mediumRadius),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // 播放/暂停按钮
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [scheme.primaryColor, scheme.darkColor],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // 进度条
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题和时间
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.entry.title ?? '语音日记',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: scheme.textDarkColor,
                          ),
                        ),
                        Text(
                          '${_formatDuration(_position)} / ${widget.entry.formattedDuration}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.textLightColor,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // 进度条
                    GestureDetector(
                      onTapDown: (details) {
                        final box = context.findRenderObject() as RenderBox;
                        final localPosition = box.globalToLocal(details.globalPosition);
                        final width = box.size.width - 72; // 减去按钮宽度
                        final newProgress = (localPosition.dx - 60) / width;
                        if (newProgress >= 0 && newProgress <= 1) {
                          final newPosition = Duration(
                            seconds: (_duration.inSeconds * newProgress).round(),
                          );
                          _service.seekTo(newPosition);
                        }
                      },
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.backgroundColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          widthFactor: progress,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [scheme.primaryColor, scheme.darkColor],
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 12),
              
              // 删除按钮
              GestureDetector(
                onTap: _delete,
                child: Icon(
                  Icons.delete_outline,
                  color: scheme.textLightColor,
                  size: 20,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
