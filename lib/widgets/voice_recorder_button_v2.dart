import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config/app_theme.dart';
import '../services/voice_diary_service.dart';
import '../providers/theme_provider.dart';

/// 语音录音按钮组件 - 重新设计版
class VoiceRecorderButton extends StatefulWidget {
  final Function(VoiceEntry)? onRecordingComplete;
  final String? date;

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

  @override
  void initState() {
    super.initState();
    _service.initialize();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    _service.onStateChanged = (state) {
      if (mounted) setState(() => _state = state);
    };
    
    _service.onDurationChanged = (duration) {
      if (mounted) setState(() => _duration = duration);
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
      setState(() => _showRecorder = false);
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
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('需要录音权限'),
        content: const Text('请在设置中允许应用使用麦克风，以录制语音日记。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
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
    
    return ElevatedButton.icon(
      onPressed: _startRecording,
      icon: const Icon(Icons.mic, size: 18),
      label: const Text('语音日记'),
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildRecorderPanel(ThemeScheme scheme) {
    final isRecording = _state == RecordingState.recording;
    
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isRecording ? Colors.red.withValues(alpha: 0.3) : scheme.lightColor,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isRecording ? '正在录音...' : '录音已暂停',
              style: TextStyle(
                fontSize: 14,
                color: isRecording ? Colors.red : scheme.textMediumColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _formattedDuration,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: scheme.textDarkColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildControlButton(
                  icon: Icons.close,
                  color: scheme.textLightColor,
                  onTap: _cancelRecording,
                ),
                const SizedBox(width: 20),
                _buildRecordButton(isRecording, scheme),
                const SizedBox(width: 20),
                _buildControlButton(
                  icon: Icons.check,
                  color: AppTheme.success,
                  onTap: _stopRecording,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Widget _buildRecordButton(bool isRecording, ThemeScheme scheme) {
    return GestureDetector(
      onTap: () {
        if (_state == RecordingState.recording) {
          _service.pauseRecording();
        } else if (_state == RecordingState.paused) {
          _service.resumeRecording();
        }
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: isRecording ? Colors.red : scheme.primaryColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (isRecording ? Colors.red : scheme.primaryColor).withValues(alpha: 0.3),
              blurRadius: 16,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Icon(
          isRecording ? Icons.pause : Icons.mic,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }
}

/// 语音播放器组件 - 重新设计版
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
      if (mounted) setState(() => _playerState = state);
    };
    
    _service.onPlayerPositionChanged = (position) {
      if (mounted) setState(() => _position = position);
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

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final isPlaying = _playerState == PlayerState.playing;
    final progress = _duration.inSeconds > 0
        ? _position.inSeconds / _duration.inSeconds
        : 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.lightColor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 播放按钮
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 进度条
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.entry.title ?? '语音日记',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: scheme.lightColor.withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation(scheme.primaryColor),
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatDuration(_position)} / ${widget.entry.formattedDuration}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.textLightColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 删除按钮
            GestureDetector(
              onTap: widget.onDeleted,
              child: Icon(
                Icons.delete_outline,
                color: scheme.textLightColor,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
