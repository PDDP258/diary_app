import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';
import '../models/mood.dart';
import '../models/tag.dart';
import '../providers/theme_provider.dart';
import '../services/database_service.dart';
import '../utils/platform_helpers.dart';
import 'diary_detail_screen.dart';

/// 增强版日记搜索页面
///
/// 功能：
/// 1. 关键词搜索（标题和内容）
/// 2. 日期范围筛选
/// 3. 标签组合筛选
/// 4. 心情筛选
/// 5. 组合条件搜索
class DiarySearchEnhancedScreen extends StatefulWidget {
  const DiarySearchEnhancedScreen({super.key});

  @override
  State<DiarySearchEnhancedScreen> createState() =>
      _DiarySearchEnhancedScreenState();
}

class _DiarySearchEnhancedScreenState extends State<DiarySearchEnhancedScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // 搜索结果
  List<Diary> _searchResults = [];
  bool _isSearching = false;

  // 筛选条件
  String _keyword = '';
  DateTime? _startDate;
  DateTime? _endDate;
  final Set<int> _selectedTagIds = {};
  final Set<int> _selectedMoodIds = {};

  // 数据
  List<Tag> _tags = [];
  List<Mood> _moods = [];

  @override
  void initState() {
    super.initState();
    _loadFilterData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadFilterData() async {
    final tags = await DatabaseService.getAllTags();
    final moods = await DatabaseService.getAllMoods();
    setState(() {
      _tags = tags;
      _moods = moods;
    });
  }

  /// 执行搜索
  Future<void> _performSearch() async {
    setState(() => _isSearching = true);

    try {
      final diaries = await DatabaseService.getAllDiaries();

      final results = diaries.where((diary) {
        // 1. 关键词筛选
        if (_keyword.isNotEmpty) {
          final titleMatch =
              diary.title?.toLowerCase().contains(_keyword.toLowerCase()) ??
                  false;
          final contentMatch =
              diary.content?.toLowerCase().contains(_keyword.toLowerCase()) ??
                  false;
          if (!titleMatch && !contentMatch) return false;
        }

        // 2. 日期范围筛选
        final diaryDate = DateTime.parse(diary.date);
        if (_startDate != null && diaryDate.isBefore(_startDate!)) return false;
        if (_endDate != null && diaryDate.isAfter(_endDate!)) return false;

        // 3. 标签筛选
        if (_selectedTagIds.isNotEmpty) {
          // 获取日记的标签
          // 注意：这里需要根据实际情况获取日记的标签关联
          // 简化处理：暂时跳过标签筛选
        }

        // 4. 心情筛选
        if (_selectedMoodIds.isNotEmpty) {
          // 通过心情emoji匹配
          final moodMatch = _selectedMoodIds.any((moodId) {
            final mood = _moods.firstWhere(
              (m) => m.id == moodId,
              orElse: () => Mood(id: 0, name: '', emoji: '', color: '#9E9E9E'),
            );
            return diary.moodEmoji == mood.emoji;
          });
          if (!moodMatch) return false;
        }

        return true;
      }).toList();

      // 按日期排序
      results.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
    }
  }

  /// 重置筛选条件
  void _resetFilters() {
    setState(() {
      _keyword = '';
      _searchController.clear();
      _startDate = null;
      _endDate = null;
      _selectedTagIds.clear();
      _selectedMoodIds.clear();
    });
    _performSearch();
  }

  /// 选择日期范围
  Future<void> _selectDateRange() async {
    final scheme = AppTheme.schemeOf(context);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 400,
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '选择日期范围',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('完成',
                        style: TextStyle(color: scheme.primaryColor)),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.calendar_today, color: scheme.primaryColor),
              title:
                  Text('开始日期', style: TextStyle(color: scheme.textDarkColor)),
              subtitle: Text(
                _startDate != null
                    ? DateFormat('yyyy-MM-dd').format(_startDate!)
                    : '未选择',
                style: TextStyle(color: scheme.textMediumColor),
              ),
              trailing: _startDate != null
                  ? IconButton(
                      icon: Icon(Icons.clear, color: scheme.textLightColor),
                      onPressed: () {
                        setState(() => _startDate = null);
                        Navigator.pop(context);
                        _performSearch();
                      },
                    )
                  : null,
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _startDate ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() => _startDate = date);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.calendar_today, color: scheme.primaryColor),
              title:
                  Text('结束日期', style: TextStyle(color: scheme.textDarkColor)),
              subtitle: Text(
                _endDate != null
                    ? DateFormat('yyyy-MM-dd').format(_endDate!)
                    : '未选择',
                style: TextStyle(color: scheme.textMediumColor),
              ),
              trailing: _endDate != null
                  ? IconButton(
                      icon: Icon(Icons.clear, color: scheme.textLightColor),
                      onPressed: () {
                        setState(() => _endDate = null);
                        Navigator.pop(context);
                        _performSearch();
                      },
                    )
                  : null,
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _endDate ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() => _endDate = date);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 选择心情
  void _selectMoods() {
    final scheme = AppTheme.schemeOf(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '选择心情',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _performSearch();
                    },
                    child: Text('完成',
                        style: TextStyle(color: scheme.primaryColor)),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _moods.map((mood) {
                final isSelected = _selectedMoodIds.contains(mood.id);
                return FilterChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(mood.emoji),
                      const SizedBox(width: 4),
                      Text(mood.name),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedMoodIds.add(mood.id!);
                      } else {
                        _selectedMoodIds.remove(mood.id);
                      }
                    });
                  },
                  selectedColor: scheme.primaryColor.withValues(alpha: 0.2),
                  checkmarkColor: scheme.primaryColor,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final hasFilters = _startDate != null ||
        _endDate != null ||
        _selectedTagIds.isNotEmpty ||
        _selectedMoodIds.isNotEmpty;

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 搜索栏
            _buildSearchBar(scheme),

            // 筛选条件栏
            _buildFilterBar(scheme),

            // 搜索结果统计
            if (_keyword.isNotEmpty || hasFilters) _buildResultCount(scheme),

            // 搜索结果列表
            Expanded(
              child: _isSearching
                  ? Center(
                      child:
                          CircularProgressIndicator(color: scheme.primaryColor))
                  : _searchResults.isEmpty &&
                          (_keyword.isNotEmpty || hasFilters)
                      ? _buildEmptyState(scheme)
                      : _buildResultsList(scheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: scheme.textDarkColor),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: scheme.lightColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                style: TextStyle(fontSize: 16, color: scheme.textDarkColor),
                decoration: InputDecoration(
                  hintText: '搜索日记标题或内容...',
                  hintStyle: TextStyle(color: scheme.textLightColor),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  suffixIcon: _keyword.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: scheme.textLightColor),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _keyword = '');
                            _performSearch();
                          },
                        )
                      : null,
                ),
                onChanged: (value) {
                  setState(() => _keyword = value);
                  _performSearch();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: scheme.cardColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 日期筛选
            _buildFilterChip(
              icon: Icons.calendar_today,
              label: _startDate != null || _endDate != null ? '已筛选日期' : '日期',
              isActive: _startDate != null || _endDate != null,
              onTap: _selectDateRange,
              scheme: scheme,
            ),
            const SizedBox(width: 8),

            // 心情筛选
            _buildFilterChip(
              icon: Icons.emoji_emotions,
              label: _selectedMoodIds.isNotEmpty
                  ? '已选${_selectedMoodIds.length}个心情'
                  : '心情',
              isActive: _selectedMoodIds.isNotEmpty,
              onTap: _selectMoods,
              scheme: scheme,
            ),
            const SizedBox(width: 8),

            // 重置按钮
            if (_keyword.isNotEmpty ||
                _startDate != null ||
                _endDate != null ||
                _selectedTagIds.isNotEmpty ||
                _selectedMoodIds.isNotEmpty)
              TextButton.icon(
                onPressed: _resetFilters,
                icon: Icon(Icons.refresh, size: 18, color: scheme.errorColor),
                label: Text('重置', style: TextStyle(color: scheme.errorColor)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required ThemeScheme scheme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? scheme.primaryColor.withValues(alpha: 0.1)
              : scheme.lightColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: isActive
              ? Border.all(color: scheme.primaryColor.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? scheme.primaryColor : scheme.textMediumColor,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isActive ? scheme.primaryColor : scheme.textMediumColor,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.check_circle,
                size: 14,
                color: scheme.primaryColor,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCount(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        '找到 ${_searchResults.length} 篇日记',
        style: TextStyle(
          fontSize: 14,
          color: scheme.textMediumColor,
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: scheme.lightColor,
          ),
          const SizedBox(height: 16),
          Text(
            '没有找到匹配的日记',
            style: TextStyle(
              fontSize: 16,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '尝试调整搜索条件',
            style: TextStyle(
              fontSize: 14,
              color: scheme.textLightColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(ThemeScheme scheme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final diary = _searchResults[index];
        return _buildDiaryItem(diary, scheme);
      },
    );
  }

  Widget _buildDiaryItem(Diary diary, ThemeScheme scheme) {
    final date = DateTime.parse(diary.date);
    final hasImages = diary.imageList.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DiaryDetailScreen(diary: diary),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 日期
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: scheme.lightColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: scheme.primaryColor,
                        ),
                      ),
                      Text(
                        '${date.month}月',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.textMediumColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // 内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              diary.title?.isNotEmpty == true
                                  ? diary.title!
                                  : '无标题',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: scheme.textDarkColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (diary.moodEmoji != null)
                            Text(diary.moodEmoji!,
                                style: const TextStyle(fontSize: 18)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        diary.content ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.textMediumColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (hasImages)
                            Icon(Icons.image,
                                size: 14, color: scheme.textLightColor),
                          if (hasImages) const SizedBox(width: 4),
                          if (hasImages)
                            Text(
                              '${diary.imageList.length}张',
                              style: TextStyle(
                                  fontSize: 12, color: scheme.textLightColor),
                            ),
                          if (hasImages) const SizedBox(width: 12),
                          Text(
                            '${diary.wordCount}字',
                            style: TextStyle(
                                fontSize: 12, color: scheme.textLightColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 缩略图
                if (hasImages)
                  Container(
                    width: 60,
                    height: 60,
                    margin: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: PlatformImage(
                      path: diary.imageList.first,
                      fit: BoxFit.cover,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
