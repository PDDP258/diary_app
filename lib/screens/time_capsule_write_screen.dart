import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_theme.dart';
import '../models/mood.dart';
import '../services/time_capsule_service.dart';
import '../providers/diary_provider.dart';
import '../widgets/interactive_button.dart';
import '../providers/theme_provider.dart';
import 'package:provider/provider.dart';

/// 创建时间胶囊页面
class TimeCapsuleWriteScreen extends StatefulWidget {
  const TimeCapsuleWriteScreen({super.key});

  @override
  State<TimeCapsuleWriteScreen> createState() => _TimeCapsuleWriteScreenState();
}

class _TimeCapsuleWriteScreenState extends State<TimeCapsuleWriteScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _imagePicker = ImagePicker();
  
  DateTime _unlockDate = DateTime.now().add(const Duration(days: 30));
  List<String> _images = [];
  Mood? _selectedMood;
  bool _isSaving = false;
  final int _maxImageCount = 5;
  final int _maxTitleLength = 100;
  final int _maxContentLength = 5000;

  // 预设的解锁日期选项
  final List<Map<String, dynamic>> _quickDateOptions = [
    {'label': '1个月后', 'days': 30},
    {'label': '3个月后', 'days': 90},
    {'label': '6个月后', 'days': 180},
    {'label': '1年后', 'days': 365},
    {'label': '2年后', 'days': 730},
    {'label': '3年后', 'days': 1095},
  ];

  @override
  void initState() {
    super.initState();
    // 默认心情为平静
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<DiaryProvider>();
      if (provider.moods.isNotEmpty) {
        setState(() {
          _selectedMood = provider.moods.firstWhere(
            (m) => m.name == '平静',
            orElse: () => provider.moods.first,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_images.length >= _maxImageCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('最多添加$_maxImageCount张图片'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() {
        _images.add(pickedFile.path);
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final maxDate = now.add(const Duration(days: 365 * 5)); // 最多5年

    final picked = await showDatePicker(
      context: context,
      initialDate: _unlockDate,
      firstDate: now.add(const Duration(days: 1)), // 至少明天
      lastDate: maxDate,
      builder: (context, child) {
        final scheme = AppTheme.schemeOf(context);
        return Theme(
          data: Theme.of(context).copyWith(
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

    if (picked != null) {
      setState(() {
        _unlockDate = picked;
      });
    }
  }

  Future<void> _saveCapsule() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入标题'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入内容'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await TimeCapsuleService.createCapsule(
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        unlockDate: _unlockDate,
        images: _images.isNotEmpty ? _images : null,
        moodEmoji: _selectedMood?.emoji,
      );

      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
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
        leading: InteractiveButton(
          onPressed: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.cardColor,
              borderRadius: BorderRadius.circular(AppTheme.smallRadius),
              boxShadow: AppTheme.softShadow,
            ),
            child: Icon(
              Icons.arrow_back_ios_new,
              size: 18,
              color: scheme.textDarkColor,
            ),
          ),
        ),
        title: const Text(
          '写给未来的自己',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          InteractiveButton(
            onPressed: _isSaving ? null : _saveCapsule,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isSaving
                      ? [Colors.grey, Colors.grey.shade400]
                      : [scheme.darkColor, scheme.primaryColor],
                ),
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Text(
                      '封存',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 解锁日期选择
            _buildDateSelector(scheme),
            const SizedBox(height: AppTheme.spacingLg),
            
            // 标题输入
            _buildTitleInput(scheme),
            const SizedBox(height: AppTheme.spacingMd),
            
            // 内容输入
            _buildContentInput(scheme),
            const SizedBox(height: AppTheme.spacingLg),
            
            // 心情选择
            _buildMoodSelector(scheme),
            const SizedBox(height: AppTheme.spacingLg),
            
            // 图片选择
            _buildImageSelector(scheme),
            const SizedBox(height: AppTheme.spacingXxl),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector(ThemeScheme scheme) {
    return Container(
      padding: AppTheme.cardPadding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryColor.withValues(alpha: 0.1),
            scheme.lightColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        border: Border.all(
          color: scheme.primaryColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 20,
                color: scheme.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                '选择开启日期',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),
          
          // 当前选择显示
          InteractiveButton(
            onPressed: _selectDate,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              decoration: BoxDecoration(
                color: scheme.cardColor,
                borderRadius: BorderRadius.circular(AppTheme.mediumRadius),
                boxShadow: AppTheme.softShadow,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 20,
                    color: scheme.primaryColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_unlockDate.year}年${_unlockDate.month}月${_unlockDate.day}日',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: scheme.textDarkColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getRemainingTimeText(),
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.textMediumColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: scheme.textLightColor,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: AppTheme.spacingMd),
          
          // 快捷选项
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickDateOptions.map<Widget>((option) {
              final days = option['days'] as int;
              final isSelected = _isQuickOptionSelected(days);
              
              return InteractiveButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _unlockDate = DateTime.now().add(Duration(days: days));
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? scheme.primaryColor
                        : scheme.cardColor,
                    borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                    boxShadow: isSelected ? AppTheme.softShadow : null,
                  ),
                  child: Text(
                    option['label'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Colors.white : scheme.textMediumColor,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleInput(ThemeScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: TextField(
        controller: _titleController,
        maxLength: _maxTitleLength,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: scheme.textDarkColor,
        ),
        decoration: InputDecoration(
          hintText: '给这封信起个标题...',
          hintStyle: TextStyle(
            color: scheme.textLightColor.withValues(alpha: 0.5),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          counterText: '',
          contentPadding: AppTheme.cardPadding,
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildContentInput(ThemeScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: TextField(
        controller: _contentController,
        maxLength: _maxContentLength,
        maxLines: 10,
        style: TextStyle(
          fontSize: 15,
          color: scheme.textDarkColor,
          height: 1.6,
        ),
        decoration: InputDecoration(
          hintText: '亲爱的未来的我：\n\n此刻的我有很多话想对你说...',
          hintStyle: TextStyle(
            color: scheme.textLightColor.withValues(alpha: 0.5),
            fontSize: 15,
            height: 1.6,
          ),
          counterText: '',
          contentPadding: AppTheme.cardPadding,
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildMoodSelector(ThemeScheme scheme) {
    return Consumer<DiaryProvider>(
      builder: (context, provider, child) {
        if (provider.moods.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: AppTheme.cardPadding,
          decoration: BoxDecoration(
            color: scheme.cardColor,
            borderRadius: BorderRadius.circular(AppTheme.largeRadius),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '此刻的心情',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.textMediumColor,
                ),
              ),
              const SizedBox(height: AppTheme.spacingMd),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: provider.moods.take(8).map<Widget>((mood) {
                  final isSelected = _selectedMood?.id == mood.id;
                  
                  return InteractiveButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedMood = mood;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Color(int.parse(mood.color)).withValues(alpha: 0.2)
                            : scheme.backgroundColor,
                        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                        border: Border.all(
                          color: isSelected
                              ? Color(int.parse(mood.color))
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            mood.emoji,
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            mood.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Color(int.parse(mood.color))
                                  : scheme.textMediumColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageSelector(ThemeScheme scheme) {
    return Container(
      padding: AppTheme.cardPadding,
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.largeRadius),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '添加照片（可选）',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.textMediumColor,
                ),
              ),
              Text(
                '${_images.length}/$_maxImageCount',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.textLightColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              // 添加按钮
              if (_images.length < _maxImageCount)
                InteractiveButton(
                  onPressed: _pickImage,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: scheme.backgroundColor,
                      borderRadius: BorderRadius.circular(AppTheme.mediumRadius),
                      border: Border.all(
                        color: scheme.lightColor.withValues(alpha: 0.5),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 28,
                      color: scheme.primaryColor,
                    ),
                  ),
                ),
              
              // 已选图片
              ..._images.asMap().entries.map((entry) {
                final index = entry.key;
                final path = entry.value;
                
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.mediumRadius),
                      child: Image.file(
                        File(path),
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InteractiveButton(
                        onPressed: () => _removeImage(index),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  bool _isQuickOptionSelected(int days) {
    final now = DateTime.now();
    final targetDate = now.add(Duration(days: days));
    return _unlockDate.year == targetDate.year &&
           _unlockDate.month == targetDate.month &&
           _unlockDate.day == targetDate.day;
  }

  String _getRemainingTimeText() {
    final now = DateTime.now();
    final difference = _unlockDate.difference(now);
    final days = difference.inDays;
    
    if (days > 365) {
      final years = days ~/ 365;
      final months = (days % 365) ~/ 30;
      return '约$years年$months个月后开启';
    } else if (days > 30) {
      final months = days ~/ 30;
      return '约$months个月后开启';
    } else {
      return '$days天后开启';
    }
  }
}
