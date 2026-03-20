import 'package:flutter/material.dart' hide Badge;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../models/anniversary.dart';
import '../models/diary.dart';
import '../models/mood.dart';
import '../services/database_service.dart';
import '../providers/diary_provider.dart';
import '../providers/theme_provider.dart';
import '../services/badge_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/milestone_service.dart';
import '../services/gacha_service.dart';
import '../utils/platform_helpers.dart';
import '../widgets/custom_sticker_overlay.dart';
import '../widgets/random_sticker_overlay.dart';
import '../widgets/motion_photo_widget.dart';
import '../services/motion_photo_service.dart';
import '../services/sound_service.dart';
import '../services/tag_system_service.dart';
import '../models/tag_system.dart';
import '../widgets/tag_selector_v3.dart';
import 'dart:io';

class WriteDiaryScreen extends StatefulWidget {
  final Diary? diary;
  final DateTime? selectedDate;

  const WriteDiaryScreen({
    super.key,
    this.diary,
    this.selectedDate,
  });

  @override
  State<WriteDiaryScreen> createState() => _WriteDiaryScreenState();
}

class _WriteDiaryScreenState extends State<WriteDiaryScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _scrollController = ScrollController();

  // 输入验证常量
  static const int _maxTitleLength = 200;
  static const int _maxContentLength = 50000;
  static const int _maxImageCount = 20;

  List<String> _images = [];
  List<String> _selectedTagIds = [];  // 改为String类型，支持三级标签系统
  late DateTime _selectedDate;
  Mood? _selectedMood;
  Mood? _secondMood; // 第二心情（双心情功能）
  bool _isEditing = false;
  bool _isSaving = false;
  int _moodEnergy = 0; // 心情能量

  // 保存刚保存的日记，用于徽章检查
  Diary? _savedDiary;

  // 验证错误状态
  String? _titleError;
  String? _contentError;
  String? _imageError;

  // 图片区域提示
  bool _showImageHint = true;
  bool _imageSectionVisible = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate ?? DateTime.now();
    _loadMoodEnergy();

    if (widget.diary != null) {
      _isEditing = true;
      _titleController.text = widget.diary!.title ?? '';
      _contentController.text = widget.diary!.content ?? '';
      if (widget.diary!.images != null && widget.diary!.images!.isNotEmpty) {
        _images = widget.diary!.images!.split(',');
      }
      _selectedDate = DateFormat('yyyy-MM-dd').parse(widget.diary!.date);

      // 加载心情
      if (widget.diary!.moodId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final provider = context.read<DiaryProvider>();
          final mood = provider.moods.firstWhere(
            (m) => m.id == widget.diary!.moodId,
            orElse: () => Mood.defaultMoods.first,
          );
          setState(() => _selectedMood = mood);
        });
      }

      // 加载标签
      _loadDiaryTags();
    }

    // 添加滚动监听
    _scrollController.addListener(_onScroll);

    // 加载提示设置
    _loadImageHintSetting();
  }

  /// 加载图片提示设置
  Future<void> _loadImageHintSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final hintDismissed = prefs.getBool('image_hint_dismissed') ?? false;
    if (mounted) {
      setState(() {
        _showImageHint = !hintDismissed;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动监听 - 检测图片区域是否可见
  void _onScroll() {
    if (!_showImageHint) return;

    // 估算图片区域的位置（大约在屏幕高度的60%处）
    final scrollOffset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // 当滚动超过一定距离时，认为图片区域可见
    final imageSectionThreshold = maxScroll * 0.3; // 滚动30%时图片区域可见

    final isVisible = scrollOffset >= imageSectionThreshold;

    if (isVisible != _imageSectionVisible) {
      setState(() {
        _imageSectionVisible = isVisible;
      });
    }
  }

  /// 关闭图片提示（永久保存）
  Future<void> _dismissImageHint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('image_hint_dismissed', true);

    if (mounted) {
      setState(() {
        _showImageHint = false;
      });

      // 显示提示已关闭的反馈
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('提示已关闭，可在设置中重新开启'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadDiaryTags() async {
    if (widget.diary?.id != null) {
      // 使用新的三级标签系统加载标签
      final tagIds = await TagSystemService.getDiaryTagIds(widget.diary!.id!);
      setState(() {
        _selectedTagIds = tagIds;
      });
    }
  }

  /// 加载心情能量
  Future<void> _loadMoodEnergy() async {
    final resources = await GachaService.getAllResourceCounts();
    if (mounted) {
      setState(() {
        _moodEnergy = resources['mood_energy'] ?? 0;
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // 检查图片数量限制
      if (_images.length >= _maxImageCount) {
        _showSnackBar('最多只能添加 $_maxImageCount 张图片');
        return;
      }

      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _images.add(image.path);
        });
      }
    } catch (e) {
      _showSnackBar('选择图片失败: $e');
    }
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final scheme = AppTheme.schemeOf(context);
        return Container(
          decoration: BoxDecoration(
            color: scheme.cardColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.largeRadius),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.lightColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: scheme.lightColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child:
                          Icon(Icons.photo_library, color: scheme.primaryColor),
                    ),
                    title: const Text('从相册选择'),
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: scheme.lightColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.camera_alt, color: scheme.primaryColor),
                    ),
                    title: const Text('拍照'),
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showMoodSelector({bool isSecondMood = false}) {
    final provider = context.read<DiaryProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final scheme = AppTheme.schemeOf(context);
        return Container(
          decoration: BoxDecoration(
            color: scheme.cardColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.largeRadius),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.lightColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isSecondMood ? '选择第二心情' : '选择心情',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isSecondMood) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.pink.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '消耗 1 点心情能量',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.pink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: provider.moods.map((mood) {
                      final isSelected = isSecondMood
                          ? _secondMood?.id == mood.id
                          : _selectedMood?.id == mood.id;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSecondMood) {
                              _secondMood = mood;
                            } else {
                              _selectedMood = mood;
                            }
                          });
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Color(int.parse(
                                        mood.color.replaceFirst('#', '0xFF')))
                                    .withValues(alpha: 0.2)
                                : scheme.lightColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected
                                ? Border.all(
                                    color: Color(int.parse(
                                        mood.color.replaceFirst('#', '0xFF'))),
                                    width: 2,
                                  )
                                : null,
                          ),
                          child: Column(
                            children: [
                              Text(
                                mood.emoji,
                                style: const TextStyle(fontSize: 32),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                mood.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected
                                      ? Color(int.parse(
                                          mood.color.replaceFirst('#', '0xFF')))
                                      : scheme.textMediumColor,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showTagSelector() {
    // 使用新的三级标签选择器
    showTagSelectorBottomSheet(
      context,
      selectedTagIds: _selectedTagIds,
      onChanged: (newSelectedIds) {
        setState(() {
          _selectedTagIds = newSelectedIds;
        });
      },
      maxSelection: 5,
    );
  }

  /// 验证输入数据
  bool _validateInput() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    // 清除之前的错误
    setState(() {
      _titleError = null;
      _contentError = null;
      _imageError = null;
    });

    bool isValid = true;

    // 验证标题长度
    if (title.length > _maxTitleLength) {
      setState(() {
        _titleError = '标题不能超过 $_maxTitleLength 个字符';
      });
      isValid = false;
    }

    // 验证内容长度（排除纪念日文字）
    // 纪念日文字会在保存时自动添加，不应计入用户输入的字数限制
    final userContentLength = _calculateUserContentLength(content);
    if (userContentLength > _maxContentLength) {
      setState(() {
        _contentError = '内容不能超过 $_maxContentLength 个字符';
      });
      isValid = false;
    }

    // 验证图片数量
    if (_images.length > _maxImageCount) {
      setState(() {
        _imageError = '图片不能超过 $_maxImageCount 张';
      });
      isValid = false;
    }

    return isValid;
  }

  /// 计算用户实际输入的内容长度（排除纪念日文字）
  int _calculateUserContentLength(String content) {
    if (content.isEmpty) return 0;

    // 纪念日文字的特征：以🎉或⏰开头，包含"纪念日"或"倒数日"
    // 使用正则表达式匹配并排除纪念日文字
    final anniversaryPattern = RegExp(
      r'[\n]*[🎉⏰][^\n]*(?:纪念日|倒数日)[^\n]*',
      multiLine: true,
    );

    // 移除所有纪念日文字
    final userContent = content.replaceAll(anniversaryPattern, '').trim();
    return userContent.length;
  }

  Future<void> _saveDiary() async {
    var title = _titleController.text.trim();
    var content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty && _images.isEmpty) {
      _showSnackBar('请输入标题、内容或添加图片');
      return;
    }

    // 输入验证
    if (!_validateInput()) {
      _showSnackBar('输入内容超出限制，请检查后重试');
      return;
    }

    setState(() => _isSaving = true);

    // 检查是否有相关的纪念日/倒数日，自动添加纪念文字
    final anniversaryText = await _generateAnniversaryText();
    if (anniversaryText != null && anniversaryText.isNotEmpty) {
      // 如果有正文内容，在正文后添加换行再添加纪念文字
      if (content.isNotEmpty) {
        content = '$content\n\n$anniversaryText';
      } else {
        content = anniversaryText;
      }
    }

    // 处理双心情：如果有第二心情，在内容中添加标记并扣除心情能量
    var finalContent = content;
    if (_secondMood != null && _moodEnergy > 0) {
      finalContent =
          '$finalContent\n\n[双心情:${_secondMood!.emoji} ${_secondMood!.name}]';
      // 扣除心情能量
      await GachaService.useMoodEnergy();
      _moodEnergy--;
    }

    final diary = Diary(
      id: widget.diary?.id,
      title: title.isEmpty ? null : title,
      content: finalContent.isEmpty ? null : finalContent,
      date: DateFormat('yyyy-MM-dd').format(_selectedDate),
      images: _images.isEmpty ? null : _images.join(','),
      moodId: _selectedMood?.id,
      moodName: _selectedMood?.name,
      moodEmoji: _selectedMood?.emoji,
      isFavorite: widget.diary?.isFavorite ?? false,
    );

    final provider = context.read<DiaryProvider>();
    bool success = false;
    Diary? savedDiary;

    if (_isEditing) {
      success = await provider.updateDiary(diary, _selectedTagIds);
      if (success) {
        savedDiary = diary;
      }
    } else {
      savedDiary = await provider.addDiary(diary, _selectedTagIds);
      success = savedDiary != null;
    }

    // 自动同步到云端（延迟执行，避免阻塞UI）
    if (success) {
      Future.delayed(const Duration(seconds: 3), () async {
        try {
          final syncService = CloudSyncFactory.instance;
          if (syncService.isLoggedIn && syncService.autoSyncEnabled) {
            // 获取日记标签关联
            final diaryTags = await DatabaseService.getAllDiaryTags();
            // 在后台线程执行同步
            await syncService.syncToCloud(
              diaries: provider.diaries,
              moods: provider.moods,
              tags: provider.tags,
              diaryTags: diaryTags,
            );
            debugPrint('自动同步完成');
          }
        } catch (e) {
          debugPrint('自动同步失败: $e');
        }
      });
    }

    if (success && savedDiary != null) {
      // 保存成功，记录日记对象用于徽章检查
      _savedDiary = savedDiary;
    }

    setState(() => _isSaving = false);

    if (success && mounted) {
      // 播放保存成功音效
      SoundService.playSuccess();

      // 检查是否触发扭蛋奖励
      if (!_isEditing) {
        await GachaService.onDiarySaved();
      }
      // 检查是否触发里程碑
      await _checkMilestoneAfterSave();
      if (mounted) {
        Navigator.pop(context, true);
      }
    } else if (mounted) {
      // 播放错误音效
      SoundService.playError();
      _showSnackBar(provider.error ?? '保存失败');
    }
  }

  /// 生成纪念日/倒数日文字
  /// 返回需要追加到日记内容的文字，如果没有相关纪念日则返回 null
  Future<String?> _generateAnniversaryText() async {
    try {
      // 获取所有纪念日/倒数日
      final allAnniversaries = await DatabaseService.getAllAnniversaries();

      if (allAnniversaries.isEmpty) return null;

      final diaryDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // 检查是否是编辑模式，如果是，获取原日记内容
      String? existingContent;
      if (_isEditing && widget.diary != null) {
        existingContent = widget.diary!.content;
      }

      // 分离纪念日和倒数日
      final anniversaries = allAnniversaries
          .where((a) => a.type == AnniversaryType.anniversary)
          .toList();
      final countdowns = allAnniversaries
          .where((a) => a.type == AnniversaryType.countdown)
          .toList();

      final List<String> texts = [];

      // 处理纪念日（优先）
      for (final anniversary in anniversaries) {
        // 检查是否应该在日记日期显示此纪念日
        final text = await _shouldAddAnniversary(
            anniversary, _selectedDate, existingContent);
        if (text != null && text.isNotEmpty) {
          texts.add(text);
        }
      }

      // 处理倒数日
      for (final countdown in countdowns) {
        // 检查是否应该在日记日期显示此倒数日
        final text = await _shouldAddCountdown(
            countdown, _selectedDate, existingContent);
        if (text != null && text.isNotEmpty) {
          texts.add(text);
        }
      }

      if (texts.isEmpty) return null;

      // 用换行符连接多个纪念文字（另起一行）
      return texts.join('\n');
    } catch (e) {
      print('生成纪念日文字失败: $e');
      return null;
    }
  }

  /// 判断是否应添加纪念日文字
  /// 规则：
  /// 1. 如果纪念日日期在日记日期之后，不添加（还没发生）
  /// 2. 如果已经写过此纪念日，不添加
  /// 3. 否则添加
  Future<String?> _shouldAddAnniversary(Anniversary anniversary,
      DateTime diaryDate, String? existingContent) async {
    final anniversaryDate = DateTime.parse(anniversary.date);
    final diaryDateOnly =
        DateTime(diaryDate.year, diaryDate.month, diaryDate.day);
    final anniversaryDateOnly = DateTime(
        anniversaryDate.year, anniversaryDate.month, anniversaryDate.day);

    // 规则1：纪念日日期在日记日期之后，不添加
    if (anniversaryDateOnly.isAfter(diaryDateOnly)) {
      return null;
    }

    // 规则2：检查是否已写过此纪念日
    if (existingContent != null && existingContent.isNotEmpty) {
      // 检查内容中是否已包含此纪念日的标识
      final identifier =
          anniversary.subjectName != null && anniversary.subjectName!.isNotEmpty
              ? '${anniversary.subjectName}：距离${anniversary.name}'
              : '距离${anniversary.name}';
      if (existingContent.contains(identifier)) {
        return null;
      }
    }

    // 生成纪念文字
    return Anniversary.generateAnniversaryText(anniversary, diaryDate);
  }

  /// 判断是否应添加倒数日文字
  /// 规则：
  /// 1. 如果倒数日设立时间（createdAt）在日记日期之后，不添加（当时还没设立）
  /// 2. 如果已经写过此倒数日，不添加
  /// 3. 否则添加
  Future<String?> _shouldAddCountdown(Anniversary countdown, DateTime diaryDate,
      String? existingContent) async {
    // 规则1：检查设立时间
    if (countdown.createdAt != null) {
      final createdDateOnly = DateTime(countdown.createdAt!.year,
          countdown.createdAt!.month, countdown.createdAt!.day);
      final diaryDateOnly =
          DateTime(diaryDate.year, diaryDate.month, diaryDate.day);

      // 如果设立时间在日记日期之后，不添加
      if (createdDateOnly.isAfter(diaryDateOnly)) {
        return null;
      }
    }

    // 规则2：检查是否已写过此倒数日
    if (existingContent != null && existingContent.isNotEmpty) {
      // 检查内容中是否已包含此倒数日的标识
      final identifier =
          countdown.subjectName != null && countdown.subjectName!.isNotEmpty
              ? '${countdown.subjectName}：距离${countdown.name}'
              : '距离${countdown.name}';
      if (existingContent.contains(identifier)) {
        return null;
      }
    }

    // 生成倒数日文字
    return Anniversary.generateCountdownText(countdown, diaryDate);
  }

  /// 保存后检查里程碑和徽章
  Future<void> _checkMilestoneAfterSave() async {
    final provider = context.read<DiaryProvider>();
    final diaries = provider.diaries;

    // 计算实际记载日记的唯一天数
    final uniqueDates = diaries.map((d) => d.date).toSet();
    final uniqueDays = uniqueDates.length;

    // 计算日记总数
    final totalCount = diaries.length;

    // 检查是否触发里程碑动画
    final milestone = await MilestoneService.checkMilestone(uniqueDays);

    if (milestone != null && mounted) {
      await MilestoneDialog.show(context, milestone);
    }

    // 收集所有新获得的徽章
    final allNewBadges = <Badge>[];

    // 1. 检查里程碑徽章
    allNewBadges.addAll(await BadgeService.checkMilestoneBadges(uniqueDays));

    // 2. 检查连续记录徽章
    allNewBadges.addAll(await BadgeService.checkStreakBadges(diaries));

    // 3. 检查日记总数徽章
    allNewBadges.addAll(await BadgeService.checkTotalCountBadges(totalCount));

    // 4. 检查刚保存的日记相关内容徽章
    if (_savedDiary != null) {
      // 内容徽章（字数、标题、多照片）
      allNewBadges.addAll(await BadgeService.checkContentBadges(
        _savedDiary!,
        writeTime: DateTime.now(),
        allDiaries: diaries,
      ));

      // 时间徽章（午餐、下午茶、周末等）
      allNewBadges.addAll(await BadgeService.checkTimeBadges(DateTime.now()));

      // 情感徽章
      allNewBadges.addAll(await BadgeService.checkEmotionBadges(
        _savedDiary!,
        allDiaries: diaries,
      ));
    }

    // 5. 检查照片徽章
    allNewBadges.addAll(await BadgeService.checkPhotoBadges(diaries));

    // 6. 检查隐藏徽章
    allNewBadges.addAll(await BadgeService.checkHiddenBadges(diaries));

    // 去重
    final uniqueBadges = allNewBadges.toSet().toList();

    // 批量显示新获得的徽章（替代逐个显示，大幅提升速度）
    if (uniqueBadges.isNotEmpty && mounted) {
      await BatchBadgeUnlockDialog.show(context, uniqueBadges);
    }
  }

  Future<void> _deleteDiary() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.mediumRadius),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('确认删除'),
          ],
        ),
        content: const Text('确定要删除这篇日记吗？删除后无法恢复。'),
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

    if (confirm == true && widget.diary?.id != null) {
      final provider = context.read<DiaryProvider>();
      final success = await provider.deleteDiary(widget.diary!.id!);
      if (success && mounted) {
        Navigator.pop(context, true);
      } else if (mounted) {
        _showSnackBar('删除失败');
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.smallRadius),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        title: Text(_isEditing ? '编辑日记' : '写日记'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _deleteDiary,
            ),
          TextButton(
            onPressed: _isSaving ? null : _saveDiary,
            child: _isSaving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(scheme.primaryColor),
                    ),
                  )
                : Text(
                    '保存',
                    style: TextStyle(
                      color: scheme.textMediumColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 日期卡片
                _buildDateCard(),
                const SizedBox(height: 16),

                // 心情选择
                _buildMoodSelector(),
                // 双心情按钮
                _buildSecondMoodButton(AppTheme.schemeOf(context)),
                const SizedBox(height: 16),

                // 标签选择
                _buildTagSelector(),
                const SizedBox(height: 16),

                // 标题输入
                _buildTitleInput(),
                const SizedBox(height: 16),

                // 内容输入
                _buildContentInput(),
                const SizedBox(height: 16),

                // 图片区域
                _buildImageSection(),
              ],
            ),
          ),
          // 自定义贴图
          const CustomStickerOverlay(targetPage: 'diary'),
          // 随机贴图装饰
          const RandomStickerOverlay(
            targetPage: 'diary',
            appearProbability: 0.8,
          ),
          // 图片区域滑动提示
          if (_showImageHint && !_imageSectionVisible) _buildImageSectionHint(),
        ],
      ),
    );
  }

  void _showDatePicker() async {
    // 使用 listen: false 避免在异步回调中调用 Provider
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final scheme = themeProvider.currentScheme;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (dialogContext, child) {
        return Theme(
          data: Theme.of(dialogContext).copyWith(
            colorScheme: ColorScheme.light(
              primary: scheme.primaryColor,
              onPrimary: Colors.white,
              surface: scheme.cardColor,
              onSurface: scheme.textDarkColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Widget _buildDateCard() {
    final scheme = AppTheme.schemeOf(context);
    return GestureDetector(
      onTap: _showDatePicker,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.cardColor,
              scheme.lightColor.withOpacity(0.2),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.xlRadius),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primaryColor,
                    scheme.darkColor,
                  ],
                ),
                borderRadius: BorderRadius.circular(AppTheme.mediumRadius),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primaryColor.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('dd').format(_selectedDate),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    DateFormat('MMM', 'zh_CN').format(_selectedDate),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('yyyy年M月d日', 'zh_CN').format(_selectedDate),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.lightColor.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          DateFormat('EEEE', 'zh_CN').format(_selectedDate),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: scheme.textMediumColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.edit_calendar_rounded,
                        size: 14,
                        color: scheme.primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '点击修改',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: scheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.lightColor.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                color: scheme.textMediumColor,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodSelector() {
    final scheme = AppTheme.schemeOf(context);
    return GestureDetector(
      onTap: _showMoodSelector,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: _selectedMood != null
              ? LinearGradient(
                  colors: [
                    Color(int.parse(
                            _selectedMood!.color.replaceFirst('#', '0xFF')))
                        .withOpacity(0.15),
                    scheme.cardColor,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: _selectedMood == null ? scheme.cardColor : null,
          borderRadius: BorderRadius.circular(AppTheme.xlRadius),
          boxShadow: AppTheme.cardShadow,
          border: _selectedMood != null
              ? Border.all(
                  color: Color(int.parse(
                          _selectedMood!.color.replaceFirst('#', '0xFF')))
                      .withOpacity(0.3),
                  width: 1.5,
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _selectedMood != null
                    ? Color(int.parse(
                            _selectedMood!.color.replaceFirst('#', '0xFF')))
                        .withOpacity(0.2)
                    : scheme.lightColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.sentiment_satisfied_rounded,
                color: _selectedMood != null
                    ? Color(int.parse(
                        _selectedMood!.color.replaceFirst('#', '0xFF')))
                    : scheme.textMediumColor.withOpacity(0.6),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '今天的心情',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.textLightColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _selectedMood != null
                            ? '${_selectedMood!.emoji} ${_selectedMood!.name}'
                            : '选择心情',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _selectedMood != null
                              ? scheme.textDarkColor
                              : scheme.textLightColor.withOpacity(0.6),
                        ),
                      ),
                      // 双心情显示
                      if (_secondMood != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.pink.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.pink.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '${_secondMood!.emoji} ${_secondMood!.name}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.pink,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.lightColor.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                color: scheme.textMediumColor,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建双心情按钮
  Widget _buildSecondMoodButton(ThemeScheme scheme) {
    // 如果没有主心情或没有心情能量，不显示
    if (_selectedMood == null || _moodEnergy <= 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => _showMoodSelector(isSecondMood: true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.pink.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.pink.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('💖', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(
                _secondMood != null ? '更换第二心情' : '添加第二心情',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.pink,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.pink.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_moodEnergy',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.pink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagSelector() {
    final scheme = AppTheme.schemeOf(context);
    
    return FutureBuilder(
      future: TagSystemService.getTagSystem(),
      builder: (context, snapshot) {
        final tagSystem = snapshot.data;
        final selectedTags = <TagLevel3>[];
        
        if (tagSystem != null) {
          for (final tagId in _selectedTagIds) {
            final tag = tagSystem.findTagById(tagId);
            if (tag != null) {
              selectedTags.add(tag);
            }
          }
        }

        return GestureDetector(
          onTap: _showTagSelector,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.cardColor,
              borderRadius: BorderRadius.circular(AppTheme.mediumRadius),
              boxShadow: AppTheme.softShadow,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.label_outline,
                  color: scheme.textMediumColor.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: selectedTags.isEmpty
                      ? Text(
                          '选择标签',
                          style: TextStyle(
                            fontSize: 15,
                            color: scheme.textLightColor.withValues(alpha: 0.6),
                          ),
                        )
                      : Wrap(
                          spacing: 8,
                          children: selectedTags.map((tag) {
                            // 获取标签所属分类的颜色
                            final category = tagSystem?.findCategoryByTagId(tag.id);
                            final tagColor = category?.color ?? scheme.primaryColor;
                            
                            return Chip(
                              avatar: tag.emoji != null
                                  ? Text(tag.emoji!, style: const TextStyle(fontSize: 12))
                                  : null,
                              label: Text(tag.name),
                              backgroundColor: tagColor.withOpacity(0.15),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                color: tagColor,
                              ),
                              side: BorderSide(color: tagColor.withOpacity(0.3)),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                        ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: scheme.textLightColor.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitleInput() {
    final scheme = AppTheme.schemeOf(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.cardColor,
            scheme.lightColor.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.xlRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: TextField(
        controller: _titleController,
        decoration: InputDecoration(
          hintText: '给今天起个标题（可选）',
          hintStyle: TextStyle(
            color: scheme.textLightColor.withOpacity(0.5),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(20),
          prefixIcon: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.lightColor.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.title_rounded,
              color: scheme.primaryColor,
              size: 20,
            ),
          ),
        ),
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: scheme.textDarkColor,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Widget _buildContentInput() {
    final scheme = AppTheme.schemeOf(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.cardColor,
            scheme.lightColor.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.xlRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.lightColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: scheme.primaryColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '日记内容',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.textDarkColor,
                  ),
                ),
                const Spacer(),
                // 灵感按钮
                _buildInspirationButton(scheme),
                const SizedBox(width: 8),
                // 模板按钮
                _buildTemplateButton(scheme),
              ],
            ),
          ),
          TextField(
            controller: _contentController,
            decoration: InputDecoration(
              hintText: '今天发生了什么有趣的事情？\n记录下美好的瞬间，留住珍贵的回忆...',
              hintStyle: TextStyle(
                color: scheme.textLightColor.withOpacity(0.5),
                height: 1.6,
                fontSize: 15,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(20),
            ),
            style: TextStyle(
              fontSize: 16,
              color: scheme.textDarkColor,
              height: 1.8,
              letterSpacing: 0.2,
            ),
            maxLines: 12,
            keyboardType: TextInputType.multiline,
          ),
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    final scheme = AppTheme.schemeOf(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.cardColor,
            scheme.lightColor.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.xlRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.lightColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.photo_library_rounded,
                  color: scheme.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '添加图片',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
              const Spacer(),
              if (_images.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_images.length}/20',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.primaryColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              GestureDetector(
                onTap: _showImagePicker,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.lightColor.withOpacity(0.4),
                        scheme.lightColor.withOpacity(0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.largeRadius),
                    border: Border.all(
                      color: scheme.lightColor.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.cardColor,
                          shape: BoxShape.circle,
                          boxShadow: AppTheme.softShadow,
                        ),
                        child: Icon(
                          Icons.add_photo_alternate_rounded,
                          size: 28,
                          color: scheme.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '添加图片',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: scheme.textMediumColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 图片列表
              Expanded(
                child: SizedBox(
                  height: 100,
                  child: _images.isEmpty
                      ? Center(
                          child: Text(
                            '点击左侧按钮添加照片',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.textLightColor,
                            ),
                          ),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _images.length,
                          itemBuilder: (context, index) {
                            return Container(
                              margin: const EdgeInsets.only(right: 12),
                              child: MotionPhotoWidget(
                                imagePath: _images[index],
                                width: 100,
                                height: 100,
                                borderRadius:
                                    BorderRadius.circular(AppTheme.largeRadius),
                                onTap: () => _showImageViewer(index),
                                onDelete: () => _removeImage(index),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建图片区域滑动提示
  Widget _buildImageSectionHint() {
    final scheme = AppTheme.schemeOf(context);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 100, // 距离底部100，不遮挡输入
      child: Center(
        child: GestureDetector(
          onLongPress: _dismissImageHint,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primaryColor.withValues(alpha: 0.9),
                  scheme.darkColor.withValues(alpha: 0.9),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: scheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_downward,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  '向下滑动添加图片',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_downward,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showImageViewer(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageViewerScreen(
          images: _images,
          initialIndex: index,
        ),
      ),
    );
  }

  /// 构建写作灵感按钮
  Widget _buildInspirationButton(ThemeScheme scheme) {
    return FutureBuilder<int>(
      future: GachaService.getAllResourceCounts()
          .then((r) => r['writing_inspiration'] ?? 0),
      builder: (context, snapshot) {
        final inspirationCount = snapshot.data ?? 0;

        if (inspirationCount <= 0) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: () => _useWritingInspiration(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('💡', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(
                  '灵感($inspirationCount)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.amber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 使用写作灵感
  Future<void> _useWritingInspiration() async {
    // 获取即将到来的纪念日/倒数日用于联动
    final upcomingAnniversaries =
        await _getUpcomingAnniversariesForInspiration();

    final prompt = await GachaService.useWritingInspiration(
      upcomingAnniversaries: upcomingAnniversaries,
    );

    if (prompt != null && mounted) {
      // 在内容框插入灵感提示
      final currentText = _contentController.text;
      if (currentText.isEmpty) {
        _contentController.text = '💡 $prompt';
      } else {
        _contentController.text = '$currentText\n\n💡 $prompt';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('灵感已添加！跟随心声写下你的回答'),
          duration: Duration(seconds: 2),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有写作灵感了')),
      );
    }
  }

  /// 获取即将到来的纪念日/倒数日用于灵感联动
  Future<List<Map<String, dynamic>>>
      _getUpcomingAnniversariesForInspiration() async {
    try {
      final allAnniversaries = await DatabaseService.getAllAnniversaries();
      final now = DateTime.now();
      final upcoming = <Map<String, dynamic>>[];

      for (final anniversary in allAnniversaries) {
        final anniversaryDate = DateTime.parse(anniversary.date);
        // 计算距离今年的这个日期还有多少天
        var thisYearDate =
            DateTime(now.year, anniversaryDate.month, anniversaryDate.day);
        if (thisYearDate.isBefore(now)) {
          thisYearDate = DateTime(
              now.year + 1, anniversaryDate.month, anniversaryDate.day);
        }
        final difference = thisYearDate.difference(now).inDays;

        // 即将到来的纪念日（一周内）
        if (difference >= 0 && difference <= 7) {
          upcoming.add({
            'title': anniversary.name,
            'days': difference,
            'isCountdown': anniversary.type == AnniversaryType.countdown,
          });
        }
      }

      return upcoming;
    } catch (e) {
      return [];
    }
  }

  /// 构建模板按钮
  Widget _buildTemplateButton(ThemeScheme scheme) {
    return FutureBuilder<List<GachaReward>>(
      future: GachaService.getUnlockedDiaryTemplates(),
      builder: (context, snapshot) {
        final templates = snapshot.data ?? [];

        if (templates.isEmpty) {
          // 没有解锁模板时显示提示
          return GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('还没有解锁日记模板，去扭蛋机抽奖吧！'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.lightColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: scheme.textLightColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '模板',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.textLightColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 有解锁的模板
        return GestureDetector(
          onTap: () => _showTemplatePicker(scheme, templates),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: scheme.primaryColor.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 16,
                  color: scheme.primaryColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '模板 (${templates.length})',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 显示模板选择器
  void _showTemplatePicker(ThemeScheme scheme, List<GachaReward> templates) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: scheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.lightColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '选择日记模板',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.textDarkColor,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: templates.length,
                itemBuilder: (context, index) {
                  final template = templates[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: scheme.cardColor,
                    child: ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: GachaService.getRarityColor(template.rarity)
                              .withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            template.emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                      title: Text(
                        template.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: scheme.textDarkColor,
                        ),
                      ),
                      subtitle: Text(
                        template.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.textMediumColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: ElevatedButton(
                        onPressed: () {
                          // 插入模板内容
                          final templateContent =
                              template.data ?? template.description;
                          final currentText = _contentController.text;

                          if (currentText.isNotEmpty) {
                            // 如果已有内容，在开头添加模板
                            _contentController.text =
                                '$templateContent\n\n$currentText';
                          } else {
                            _contentController.text = templateContent;
                          }

                          Navigator.pop(context);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('已插入模板：${template.name}'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('使用'),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// 图片查看器页面 - 支持滑动浏览和缩放
class ImageViewerScreen extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const ImageViewerScreen({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  final MotionPhotoService _motionPhotoService = MotionPhotoService();
  final Map<int, bool> _isMotionPhotoMap = {};
  final Map<int, String?> _videoPathMap = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _checkMotionPhotos();
  }

  Future<void> _checkMotionPhotos() async {
    for (int i = 0; i < widget.images.length; i++) {
      final isMotion =
          await _motionPhotoService.isMotionPhoto(widget.images[i]);
      if (isMotion) {
        final videoPath =
            await _motionPhotoService.extractVideo(widget.images[i]);
        if (mounted) {
          setState(() {
            _isMotionPhotoMap[i] = true;
            _videoPathMap[i] = videoPath;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _playMotionPhoto(int index) {
    final videoPath = _videoPathMap[index];
    if (videoPath != null && File(videoPath).existsSync()) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MotionPhotoVideoPlayer(
            videoPath: videoPath,
            imagePath: widget.images[index],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${widget.images.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          final isMotionPhoto = _isMotionPhotoMap[index] ?? false;

          return GestureDetector(
            onLongPress: isMotionPhoto ? () => _playMotionPhoto(index) : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 图片
                InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: PlatformImage(
                      path: widget.images[index],
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                // 实况标识
                if (isMotionPhoto)
                  Positioned(
                    top: 40,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            color: Colors.orange.shade300,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '实况',
                            style: TextStyle(
                              color: Colors.orange.shade300,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // 长按提示
                if (isMotionPhoto)
                  Positioned(
                    bottom: 100,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '长按播放实况',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
