import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';
import '../services/database_service.dart';
import '../utils/platform_helpers.dart';
import '../screens/diary_detail_screen.dart';
import '../screens/write_diary_screen.dart';
import '../widgets/smart_notifications.dart';
import '../providers/theme_provider.dart';
import '../widgets/diary_interactions.dart';
import '../widgets/skeleton_loading.dart';

/// 分页日记列表
/// 
/// 功能：
/// 1. 分页加载日记数据
/// 2. 支持下拉刷新
/// 3. 支持上拉加载更多
/// 4. 显示加载状态和空状态
class PagedDiaryList extends StatefulWidget {
  final int pageSize;
  final Function(List<Diary>)? onDataLoaded;
  final Widget? emptyWidget;
  final EdgeInsetsGeometry? padding;

  const PagedDiaryList({
    super.key,
    this.pageSize = 20,
    this.onDataLoaded,
    this.emptyWidget,
    this.padding,
  });

  @override
  State<PagedDiaryList> createState() => _PagedDiaryListState();
}

class _PagedDiaryListState extends State<PagedDiaryList> {
  final List<Diary> _diaries = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  String? _error;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadData({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
      if (refresh) {
        _diaries.clear();
        _currentPage = 0;
        _hasMore = true;
      }
    });

    try {
      final diaries = await DatabaseService.getDiariesPaged(
        page: 0,
        pageSize: widget.pageSize,
      );

      setState(() {
        _diaries.addAll(diaries);
        _isLoading = false;
        _hasMore = diaries.length >= widget.pageSize;
        _currentPage = 1;
      });

      widget.onDataLoaded?.call(_diaries);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final diaries = await DatabaseService.getDiariesPaged(
        page: _currentPage,
        pageSize: widget.pageSize,
      );

      setState(() {
        _diaries.addAll(diaries);
        _isLoadingMore = false;
        _hasMore = diaries.length >= widget.pageSize;
        _currentPage++;
      });

      widget.onDataLoaded?.call(_diaries);
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refresh() async {
    await _loadData(refresh: true);
  }

  void _viewDiary(Diary diary) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiaryDetailScreen(diary: diary),
      ),
    );
  }

  void _editDiary(Diary diary) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WriteDiaryScreen(
          diary: diary,
          selectedDate: DateTime.parse(diary.date),
        ),
      ),
    );
    if (result == true && mounted) {
      _refresh();
    }
  }

  void _onDiaryLongPress(Diary diary) {
    HapticFeedback.mediumImpact();
    final scheme = AppTheme.schemeOf(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: scheme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.edit_outlined, color: scheme.primaryColor),
                title: Text('编辑日记', style: TextStyle(color: scheme.textDarkColor)),
                onTap: () {
                  Navigator.pop(context);
                  _editDiary(diary);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.errorColor),
                title: Text('删除日记', style: TextStyle(color: scheme.errorColor)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteDiary(diary);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteDiary(Diary diary) async {
    final scheme = AppTheme.schemeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('删除日记？', style: TextStyle(color: scheme.textDarkColor)),
        content: Text(
          '此操作不可恢复，确定要删除这篇日记吗？',
          style: TextStyle(color: scheme.textMediumColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: scheme.textLightColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('删除', style: TextStyle(color: scheme.errorColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await DatabaseService.deleteDiary(diary.id!);
        if (mounted) {
          _refresh();
          ToastManager().show(context, message: '日记已删除', type: ToastType.success);
        }
      } catch (e) {
        if (mounted) {
          ToastManager().show(context, message: '删除失败：$e', type: ToastType.error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    if (_isLoading && _diaries.isEmpty) {
      return _buildLoadingState(scheme);
    }

    if (_error != null && _diaries.isEmpty) {
      return _buildErrorState(scheme);
    }

    if (_diaries.isEmpty) {
      return widget.emptyWidget ?? _buildEmptyState(scheme);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: scheme.primaryColor,
      child: ListView.builder(
        controller: _scrollController,
        padding: widget.padding ?? const EdgeInsets.all(16),
        itemCount: _diaries.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _diaries.length) {
            return _buildLoadMoreIndicator(scheme);
          }
          return _buildDiaryItem(_diaries[index], scheme);
        },
      ),
    );
  }

  Widget _buildLoadingState(ThemeScheme scheme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) => const DiaryCardSkeleton(),
    );
  }

  Widget _buildErrorState(ThemeScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: scheme.errorColor),
          const SizedBox(height: 16),
          Text(
            '加载失败',
            style: TextStyle(
              fontSize: 16,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(
              fontSize: 12,
              color: scheme.textLightColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadData,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.book_outlined,
            size: 64,
            color: scheme.lightColor,
          ),
          const SizedBox(height: 16),
          Text(
            '还没有日记',
            style: TextStyle(
              fontSize: 18,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '开始记录你的第一篇日记吧',
            style: TextStyle(
              fontSize: 14,
              color: scheme.textLightColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreIndicator(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: _isLoadingMore
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '加载更多...',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.textMediumColor,
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildDiaryItem(Diary diary, ThemeScheme scheme) {
    final hasImages = diary.imageList.isNotEmpty;
    final date = DateTime.parse(diary.date);
    final dateStr = '${date.month}月${date.day}日';

    return TiltCard(
      maxTilt: 0.05,
      onTap: () => _viewDiary(diary),
      onLongPress: () => _onDiaryLongPress(diary),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    // 标题和心情
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
                          Text(
                            diary.moodEmoji!,
                            style: const TextStyle(fontSize: 20),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // 日记内容预览
                    Text(
                      diary.content ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.textMediumColor,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // 底部信息（图片数量、字数）
                    Row(
                      children: [
                        if (hasImages)
                          Icon(
                            Icons.image_outlined,
                            size: 14,
                            color: scheme.textLightColor,
                          ),
                        if (hasImages) const SizedBox(width: 4),
                        if (hasImages)
                          Text(
                            '${diary.imageList.length}张',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.textLightColor,
                            ),
                          ),
                        if (hasImages) const SizedBox(width: 12),
                        Text(
                          '${diary.wordCount}字',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.textLightColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 图片缩略图
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
    );
  }
}

/// 分页日记网格
class PagedDiaryGrid extends StatefulWidget {
  final int pageSize;
  final int crossAxisCount;
  final Function(List<Diary>)? onDataLoaded;
  final Widget? emptyWidget;

  const PagedDiaryGrid({
    super.key,
    this.pageSize = 20,
    this.crossAxisCount = 2,
    this.onDataLoaded,
    this.emptyWidget,
  });

  @override
  State<PagedDiaryGrid> createState() => _PagedDiaryGridState();
}

class _PagedDiaryGridState extends State<PagedDiaryGrid> {
  final List<Diary> _diaries = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadData({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      if (refresh) {
        _diaries.clear();
        _currentPage = 0;
        _hasMore = true;
      }
    });

    try {
      final diaries = await DatabaseService.getDiariesPaged(
        page: 0,
        pageSize: widget.pageSize,
      );

      setState(() {
        _diaries.addAll(diaries);
        _isLoading = false;
        _hasMore = diaries.length >= widget.pageSize;
        _currentPage = 1;
      });

      widget.onDataLoaded?.call(_diaries);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final diaries = await DatabaseService.getDiariesPaged(
        page: _currentPage,
        pageSize: widget.pageSize,
      );

      setState(() {
        _diaries.addAll(diaries);
        _isLoadingMore = false;
        _hasMore = diaries.length >= widget.pageSize;
        _currentPage++;
      });

      widget.onDataLoaded?.call(_diaries);
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refresh() async {
    await _loadData(refresh: true);
  }

  void _viewDiary(Diary diary) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiaryDetailScreen(diary: diary),
      ),
    );
  }

  void _editDiary(Diary diary) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WriteDiaryScreen(
          diary: diary,
          selectedDate: DateTime.parse(diary.date),
        ),
      ),
    );
    if (result == true && mounted) {
      _refresh();
    }
  }

  void _onDiaryLongPress(Diary diary) {
    HapticFeedback.mediumImpact();
    final scheme = AppTheme.schemeOf(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: scheme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.edit_outlined, color: scheme.primaryColor),
                title: Text('编辑日记', style: TextStyle(color: scheme.textDarkColor)),
                onTap: () {
                  Navigator.pop(context);
                  _editDiary(diary);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.errorColor),
                title: Text('删除日记', style: TextStyle(color: scheme.errorColor)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteDiary(diary);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteDiary(Diary diary) async {
    final scheme = AppTheme.schemeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('删除日记？', style: TextStyle(color: scheme.textDarkColor)),
        content: Text(
          '此操作不可恢复，确定要删除这篇日记吗？',
          style: TextStyle(color: scheme.textMediumColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: scheme.textLightColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('删除', style: TextStyle(color: scheme.errorColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await DatabaseService.deleteDiary(diary.id!);
        if (mounted) {
          _refresh();
          ToastManager().show(context, message: '日记已删除', type: ToastType.success);
        }
      } catch (e) {
        if (mounted) {
          ToastManager().show(context, message: '删除失败：$e', type: ToastType.error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    if (_isLoading && _diaries.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: scheme.primaryColor),
      );
    }

    if (_diaries.isEmpty) {
      return widget.emptyWidget ??
          Center(
            child: Text(
              '还没有日记',
              style: TextStyle(color: scheme.textMediumColor),
            ),
          );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: scheme.primaryColor,
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.8,
        ),
        itemCount: _diaries.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _diaries.length) {
            return _buildLoadMoreIndicator(scheme);
          }
          return _buildDiaryCard(_diaries[index], scheme);
        },
      ),
    );
  }

  Widget _buildLoadMoreIndicator(ThemeScheme scheme) {
    return Container(
      alignment: Alignment.center,
      child: _isLoadingMore
          ? CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primaryColor,
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildDiaryCard(Diary diary, ThemeScheme scheme) {
    final hasImages = diary.imageList.isNotEmpty;
    final date = DateTime.parse(diary.date);

    return TiltCard(
      maxTilt: 0.08,
      onTap: () => _viewDiary(diary),
      onLongPress: () => _onDiaryLongPress(diary),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppTheme.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图片或占位
            Expanded(
              child: hasImages
                  ? PlatformImage(
                      path: diary.imageList.first,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: scheme.lightColor.withValues(alpha: 0.3),
                      child: Center(
                        child: Text(
                          diary.moodEmoji ?? '📝',
                          style: const TextStyle(fontSize: 32),
                        ),
                      ),
                    ),
            ),

            // 信息
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    diary.title?.isNotEmpty == true ? diary.title! : '无标题',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.textDarkColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.month}月${date.day}日 · ${diary.wordCount}字',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.textLightColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
