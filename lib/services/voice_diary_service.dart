import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// 语音日记条目
class VoiceEntry {
  final int? id;
  final String filePath;     // 音频文件路径
  final int duration;        // 时长（秒）
  final DateTime createdAt;  // 创建时间
  final String? title;       // 可选标题
  final String? date;        // 关联的日记日期

  VoiceEntry({
    this.id,
    required this.filePath,
    required this.duration,
    required this.createdAt,
    this.title,
    this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_path': filePath,
      'duration': duration,
      'created_at': createdAt.toIso8601String(),
      'title': title,
      'date': date,
    };
  }

  factory VoiceEntry.fromMap(Map<String, dynamic> map) {
    return VoiceEntry(
      id: map['id'] as int?,
      filePath: map['file_path'] as String,
      duration: map['duration'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
      title: map['title'] as String?,
      date: map['date'] as String?,
    );
  }

  // 格式化时长显示
  String get formattedDuration {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // 获取相对时间描述
  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    
    if (diff.inDays > 30) {
      return '${diff.inDays ~/ 30}个月前';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }
}

/// 录音状态
enum RecordingState {
  idle,       // 空闲
  recording,  // 录制中
  paused,     // 暂停
  stopped,    // 已停止
}

/// 语音日记服务 - 本地录音和播放
class VoiceDiaryService {
  VoiceDiaryService._();
  
  static final VoiceDiaryService _instance = VoiceDiaryService._();
  static VoiceDiaryService get instance => _instance;

  // 录音器
  final AudioRecorder _recorder = AudioRecorder();
  // 播放器
  final AudioPlayer _player = AudioPlayer();
  
  // 当前状态
  RecordingState _state = RecordingState.idle;
  RecordingState get state => _state;
  
  // 当前录音路径
  String? _currentRecordingPath;
  
  // 录音开始时间
  DateTime? _recordingStartTime;
  
  // 已录音时长（用于暂停后累加）
  int _recordedDuration = 0;

  // 状态监听
  Function(RecordingState)? onStateChanged;
  Function(int)? onDurationChanged; // 录音时长变化（秒）
  Function(PlayerState)? onPlayerStateChanged;
  Function(Duration)? onPlayerPositionChanged;

  // 初始化
  Future<void> initialize() async {
    // 监听播放状态
    _player.onPlayerStateChanged.listen((state) {
      onPlayerStateChanged?.call(state);
    });
    
    _player.onPositionChanged.listen((position) {
      onPlayerPositionChanged?.call(position);
    });
  }

  // 检查权限
  Future<bool> checkPermission() async {
    return await _recorder.hasPermission();
  }

  // 请求权限
  Future<bool> requestPermission() async {
    return await _recorder.hasPermission();
  }

  /// 开始录音
  Future<bool> startRecording() async {
    try {
      // 检查权限
      if (!await checkPermission()) {
        return false;
      }

      // 获取存储目录
      final dir = await _getVoiceDirectory();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = '${dir.path}/$fileName';

      // 开始录音
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _currentRecordingPath = path;
      _recordingStartTime = DateTime.now();
      _recordedDuration = 0;
      _state = RecordingState.recording;
      onStateChanged?.call(_state);
      
      // 开始监听时长
      _startDurationTimer();
      
      return true;
    } catch (e) {
      print('开始录音失败: $e');
      return false;
    }
  }

  /// 暂停录音
  Future<bool> pauseRecording() async {
    try {
      await _recorder.pause();
      _recordedDuration += DateTime.now().difference(_recordingStartTime!).inSeconds;
      _state = RecordingState.paused;
      onStateChanged?.call(_state);
      return true;
    } catch (e) {
      print('暂停录音失败: $e');
      return false;
    }
  }

  /// 恢复录音
  Future<bool> resumeRecording() async {
    try {
      await _recorder.resume();
      _recordingStartTime = DateTime.now();
      _state = RecordingState.recording;
      onStateChanged?.call(_state);
      return true;
    } catch (e) {
      print('恢复录音失败: $e');
      return false;
    }
  }

  /// 停止录音并保存
  Future<VoiceEntry?> stopRecording({String? title, String? date}) async {
    try {
      final path = await _recorder.stop();
      
      if (path == null) return null;
      
      // 计算总时长
      int duration = _recordedDuration;
      if (_state == RecordingState.recording && _recordingStartTime != null) {
        duration += DateTime.now().difference(_recordingStartTime!).inSeconds;
      }
      
      _state = RecordingState.stopped;
      onStateChanged?.call(_state);
      
      // 创建条目
      final entry = VoiceEntry(
        filePath: path,
        duration: duration,
        createdAt: DateTime.now(),
        title: title,
        date: date,
      );
      
      // 保存到本地
      await _saveVoiceEntry(entry);
      
      return entry;
    } catch (e) {
      print('停止录音失败: $e');
      return null;
    }
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    try {
      await _recorder.stop();
      
      // 删除临时文件
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      
      _state = RecordingState.idle;
      _currentRecordingPath = null;
      _recordedDuration = 0;
      onStateChanged?.call(_state);
    } catch (e) {
      print('取消录音失败: $e');
    }
  }

  /// 播放语音
  Future<bool> playVoice(String filePath) async {
    try {
      if (_player.state == PlayerState.playing) {
        await _player.stop();
      }
      
      await _player.play(DeviceFileSource(filePath));
      return true;
    } catch (e) {
      print('播放语音失败: $e');
      return false;
    }
  }

  /// 暂停播放
  Future<void> pausePlayback() async {
    await _player.pause();
  }

  /// 恢复播放
  Future<void> resumePlayback() async {
    await _player.resume();
  }

  /// 停止播放
  Future<void> stopPlayback() async {
    await _player.stop();
  }

  /// 跳转到指定位置
  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  /// 获取所有语音条目
  Future<List<VoiceEntry>> getAllVoiceEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('voice_entries') ?? [];
    
    return jsonList
        .map((json) => VoiceEntry.fromMap(jsonDecode(json)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// 获取指定日期的语音
  Future<List<VoiceEntry>> getVoiceEntriesByDate(String date) async {
    final all = await getAllVoiceEntries();
    return all.where((e) => e.date == date).toList();
  }

  /// 删除语音条目
  Future<bool> deleteVoiceEntry(VoiceEntry entry) async {
    try {
      // 删除文件
      final file = File(entry.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      
      // 从列表中移除
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList('voice_entries') ?? [];
      
      jsonList.removeWhere((json) {
        final map = jsonDecode(json);
        return map['file_path'] == entry.filePath;
      });
      
      await prefs.setStringList('voice_entries', jsonList);
      
      return true;
    } catch (e) {
      print('删除语音失败: $e');
      return false;
    }
  }

  /// 保存语音条目
  Future<void> _saveVoiceEntry(VoiceEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('voice_entries') ?? [];
    
    jsonList.add(jsonEncode(entry.toMap()));
    await prefs.setStringList('voice_entries', jsonList);
  }

  /// 获取语音存储目录
  Future<Directory> _getVoiceDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final voiceDir = Directory('${appDir.path}/voice_diary');
    
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }
    
    return voiceDir;
  }

  /// 获取录音时长监听
  void _startDurationTimer() {
    Future.doWhile(() async {
      if (_state != RecordingState.recording) return false;
      
      await Future.delayed(const Duration(seconds: 1));
      
      if (_state == RecordingState.recording && _recordingStartTime != null) {
        final currentDuration = _recordedDuration + 
            DateTime.now().difference(_recordingStartTime!).inSeconds;
        onDurationChanged?.call(currentDuration);
      }
      
      return _state == RecordingState.recording;
    });
  }

  /// 获取总录音时长
  int getTotalRecordingSeconds() {
    return _recordedDuration + (
      _state == RecordingState.recording && _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inSeconds
          : 0
    );
  }

  /// 释放资源
  Future<void> dispose() async {
    await _recorder.dispose();
    await _player.dispose();
  }
}
