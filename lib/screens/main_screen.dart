import 'dart:async';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../providers/diary_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/theme_backgrounds.dart';
import '../services/badge_service.dart';
import '../services/milestone_service.dart';
import '../services/image_cache_service.dart';
import '../services/sound_service.dart';
// import '../services/quick_note_service.dart';
import '../config/app_theme.dart';
import '../widgets/custom_bottom_nav.dart';
import 'timeline_screen.dart';
import 'calendar_screen.dart';
import 'stats_screen.dart';
import 'profile_screen.dart';
import 'write_diary_screen.dart';
import 'quick_note_editor_screen.dart';
import 'quick_notes_screen.dart';
import 'self_talk_screen.dart';

/// 全局路由观察者，用于监听页面导航
class MainScreenRouteObserver extends NavigatorObserver {
  VoidCallback? onRoutePopped;
  VoidCallback? onRoutePushed;
  
  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    // 页面返回时触发回调
    onRoutePopped?.call();
  }
  
  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    onRoutePushed?.call();
  }
}

/// 全局路由观察者实例
final mainScreenRouteObserver = MainScreenRouteObserver();

class MainScreen extends StatefulWidget {
  final int initialIndex;
  
  const MainScreen({super.key, this.initialIndex = 0});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late int _currentIndex;
  bool _isLoading = true;

  // 使用 PageController 来管理页面切换，提高性能
  late PageController _pageController;

  // 导航栏显示/隐藏控制
  bool _isNavVisible = true;
  double _lastScrollPixels = 0;

  // 5秒无操作计时器
  Timer? _inactivityTimer;
  static const _inactivityDuration = Duration(seconds: 5);

  // 标记是否刚处理过点击，防止点击触发的微滚动干扰
  bool _justTapped = false;

  // 长按空白区3秒启动速记的计时器
  Timer? _longPressTimer;
  bool _longPressTriggered = false;

  // 标记是否强制显示导航栏（用于页面切换时立即显示，无动画）
  bool _forceShowNav = false;

  // 速记悬浮按钮显示设置
  bool _quickNoteFabEnabled = true;

  // 标记是否正在切换页面（禁用滚动通知处理，防止导航栏闪烁）
  bool _isPageChanging = false;
  Timer? _pageChangeTimer;

  // 页面列表，动态创建以避免循环依赖
  List<Widget> get _screens => [
    const TimelineScreen(),
    const CalendarScreen(),
    const StatsScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    // 注册生命周期监听
    WidgetsBinding.instance.addObserver(this);
    // 注册路由监听
    mainScreenRouteObserver.onRoutePopped = () {
      // 从其他页面返回时，显示导航栏并重新开始计时
      if (mounted) {
        _showNavBarImmediately();
        _resetInactivityTimer();
      }
    };
    mainScreenRouteObserver.onRoutePushed = () {
      // 跳转到其他页面时，取消计时器
      _inactivityTimer?.cancel();
    };
    // 延迟加载数据，避免在构建过程中调用 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _loadQuickNoteFabSetting();
      // 启动无操作计时器
      _resetInactivityTimer();
    });
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _pageChangeTimer?.cancel();
    _longPressTimer?.cancel();
    _pageController.dispose();
    // 移除生命周期监听
    WidgetsBinding.instance.removeObserver(this);
    // 清理路由监听
    mainScreenRouteObserver.onRoutePopped = null;
    mainScreenRouteObserver.onRoutePushed = null;
    super.dispose();
  }

  /// 监听应用生命周期变化
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 应用从后台返回前台，显示导航栏并重新开始5秒计时
      if (mounted) {
        _showNavBar();
        _resetInactivityTimer();
      }
    }
  }

  /// 显示导航栏
  void _showNavBar() {
    if (!_isNavVisible) {
      setState(() {
        _isNavVisible = true;
        _forceShowNav = false;
      });
    }
  }

  /// 立即显示导航栏（无动画）
  void _showNavBarImmediately() {
    setState(() {
      _isNavVisible = true;
      _forceShowNav = true;
    });
    // 100ms后恢复动画效果
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() => _forceShowNav = false);
      }
    });
  }

  /// 隐藏导航栏
  void _hideNavBar() {
    if (_isNavVisible) {
      setState(() => _isNavVisible = false);
    }
  }

  /// 重置无操作计时器
  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityDuration, () {
      if (mounted) {
        _hideNavBar();
      }
    });
  }

  /// 加载速记悬浮按钮显示设置
  Future<void> _loadQuickNoteFabSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _quickNoteFabEnabled = prefs.getBool('quick_note_fab_enabled') ?? true;
      });
    }
  }

  /// 打开速记编辑器
  Future<void> _openQuickNoteEditor() async {
    _longPressTimer?.cancel();
    _inactivityTimer?.cancel();
    _showNavBarImmediately();

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const QuickNoteEditorScreen()),
    );

    _longPressTriggered = false;
    if (mounted) {
      _showNavBarImmediately();
      _resetInactivityTimer();
    }
  }

  /// 打开速记列表
  Future<void> _openQuickNotesList() async {
    _inactivityTimer?.cancel();
    _showNavBarImmediately();

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuickNotesScreen()),
    );

    if (mounted) {
      _showNavBarImmediately();
      _resetInactivityTimer();
    }
  }

  Future<void> _loadData() async {
    try {
      final provider = context.read<DiaryProvider>();
      
      // 初始化图片缓存服务
      await ImageCacheService().initialize();
      
      // 加载核心数据（只加载最近的日记，快速启动）
      await provider.loadAllData();
      
      // 延迟执行非关键操作（避免阻塞启动）
      if (mounted) {
        _runDeferredTasks(provider);
      }
    } catch (e) {
      debugPrint('加载数据失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  /// 延迟执行的非关键任务
  void _runDeferredTasks(DiaryProvider provider) {
    // 延迟 2 秒后执行徽章检查和里程碑检查
    // 这样不会阻塞应用启动和首屏渲染
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _checkMilestone(provider);
      }
    });
    
    // 延迟 3 秒后预加载更多图片
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _preloadMoreImages(provider);
      }
    });
  }
  
  /// 预加载更多图片（后台执行）
  void _preloadMoreImages(DiaryProvider provider) {
    final diaries = provider.diaries;
    if (diaries.length <= 20) return;
    
    // 预加载第 21-50 篇日记的图片
    final moreDiaries = diaries.skip(20).take(30).toList();
    final allImagePaths = <String>[];
    
    for (final diary in moreDiaries) {
      if (diary.imageList.isNotEmpty) {
        allImagePaths.addAll(diary.imageList);
      }
    }
    
    if (allImagePaths.isNotEmpty) {
      ImageCacheService().preloadImages(
        allImagePaths.take(20).toList(),
        quality: 'small',
      );
    }
  }
  
  /// 检查里程碑和徽章
  void _checkMilestone(DiaryProvider provider) async {
    final diaries = provider.diaries;
    
    // 计算实际记载日记的唯一天数
    final uniqueDates = diaries.map((d) => d.date).toSet();
    final uniqueDays = uniqueDates.length;
    
    // 计算日记总数
    final totalCount = diaries.length;
    
    // 检查是否触发里程碑动画
    final milestone = await MilestoneService.checkMilestone(uniqueDays);
    
    if (milestone != null && mounted) {
      // 延迟一点显示，避免页面加载时弹出
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          MilestoneDialog.show(context, milestone);
        }
      });
    }
    
    // 收集所有新获得的徽章
    final allNewBadges = <Badge>[];
    
    // 1. 检查里程碑徽章（累计不同天数）
    allNewBadges.addAll(await BadgeService.checkMilestoneBadges(uniqueDays));
    
    // 2. 检查连续记录徽章
    allNewBadges.addAll(await BadgeService.checkStreakBadges(diaries));
    
    // 3. 检查日记总数徽章
    allNewBadges.addAll(await BadgeService.checkTotalCountBadges(totalCount));
    
    // 4. 检查照片徽章
    allNewBadges.addAll(await BadgeService.checkPhotoBadges(diaries));
    
    // 5. 检查隐藏徽章（字数、徽章收集等）
    allNewBadges.addAll(await BadgeService.checkHiddenBadges(diaries));
    
    // 去重
    final uniqueBadges = allNewBadges.toSet().toList();
    
    // 批量显示新获得的徽章（替代逐个显示，大幅提升速度）
    if (uniqueBadges.isNotEmpty && mounted) {
      await BatchBadgeUnlockDialog.show(context, uniqueBadges);
    }
  }

  void _onPageChanged(int index) {
    // 只在索引真正改变时才更新状态
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
      // 页面跳转完成后，重新开始5秒倒计时
      _resetInactivityTimer();
    } else {
      // 即使索引相同，也确保导航栏显示并重置计时器
      // 这处理快速点击同一页面的情况
      _showNavBarImmediately();
      _resetInactivityTimer();
    }
  }

  void _onNavTap(int index) {
    // 播放点击音效
    SoundService.playClick();

    // 点击导航栏时：立即显示导航栏（无动画）并重置5秒计时器（最高优先级）
    _showNavBarImmediately();
    _resetInactivityTimer();

    // 使用 PageController 跳转页面，提高性能
    if (_currentIndex != index) {
      // 设置页面切换标志，禁用滚动通知处理
      _isPageChanging = true;
      _pageChangeTimer?.cancel();
      
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      
      // 页面切换动画结束后（350ms），清除标志并强制显示导航栏
      _pageChangeTimer = Timer(const Duration(milliseconds: 350), () {
        if (mounted) {
          _isPageChanging = false;
          _showNavBarImmediately();
          _resetInactivityTimer();
        }
      });
    }
  }

  /// 处理滚动通知，控制导航栏显示/隐藏
  /// 下滑（向下滚动）：立即隐藏导航栏
  /// 上滑（向上滚动）：立即显示导航栏，5秒后隐藏
  bool _onScrollNotification(ScrollNotification notification) {
    // 如果正在切换页面，忽略所有滚动事件（防止导航栏闪烁）
    if (_isPageChanging) return false;
    
    // 如果刚点击过，忽略滚动事件（防止点击触发的微滚动干扰）
    if (_justTapped) return false;
    
    if (notification is ScrollUpdateNotification) {
      final pixels = notification.metrics.pixels;
      final maxScroll = notification.metrics.maxScrollExtent;

      // 只有在可以滚动的情况下才处理
      if (maxScroll > 0) {
        final scrollDelta = notification.scrollDelta ?? 0;

        // 下滑（向下滚动）超过阈值：立即隐藏导航栏
        // 任何时候下滑都隐藏，包括顶部
        if (scrollDelta > 10) {
          _hideNavBar();
          // 取消计时器，因为已经隐藏了
          _inactivityTimer?.cancel();
        }
        // 上滑（向上滚动）时立即显示导航栏并重新开始5秒计时
        else if (scrollDelta < -5) {
          _showNavBar();
          _resetInactivityTimer();
        }

        _lastScrollPixels = pixels;
      }
    }
    // 滚动到顶部时显示导航栏并重新开始5秒计时
    else if (notification is ScrollEndNotification) {
      if (notification.metrics.pixels <= 0) {
        _showNavBar();
        _resetInactivityTimer();
      }
    }

    return false; // 允许事件继续传递
  }

  void _onAddTap() async {
    // 播放点击音效
    SoundService.playClick();
    // 导航到其他页面前取消计时器，防止后台计时导致导航栏隐藏
    _inactivityTimer?.cancel();
    // 强制显示导航栏，确保跳转前是显示状态
    _showNavBarImmediately();
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WriteDiaryScreen(),
      ),
    );
    
    // 返回后一定显示导航栏并重新开始5秒计时（使用finally确保一定执行）
    if (mounted) {
      _showNavBarImmediately();
      _resetInactivityTimer();
    }
    if (result == true && mounted) {
      // 刷新数据
      context.read<DiaryProvider>().loadDiaries();
    }
  }

  void _onAddLongPress() {
    HapticFeedback.mediumImpact();
    final scheme = AppTheme.schemeOf(context);
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final Offset center = box != null
        ? box.localToGlobal(box.size.center(Offset.zero))
        : Offset(MediaQuery.of(context).size.width / 2, MediaQuery.of(context).size.height - 120);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        center.dx - 60,
        center.dy - 100,
        center.dx + 60,
        center.dy,
      ),
      color: scheme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem(
          value: 'diary',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, color: scheme.primaryColor, size: 20),
              const SizedBox(width: 10),
              Text('写日记', style: TextStyle(color: scheme.textDarkColor)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'selftalk',
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline, color: scheme.primaryColor, size: 20),
              const SizedBox(width: 10),
              Text('自言自语', style: TextStyle(color: scheme.textDarkColor)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'diary') {
        _onAddTap();
      } else if (value == 'selftalk') {
        _navigateToSelfTalk();
      }
    });
  }

  void _navigateToSelfTalk() async {
    _inactivityTimer?.cancel();
    _showNavBarImmediately();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SelfTalkScreen(),
      ),
    );

    if (mounted) {
      _showNavBarImmediately();
      _resetInactivityTimer();
    }
    if (result == true && mounted) {
      context.read<DiaryProvider>().loadDiaries();
    }
  }
  
  /// 公共方法：供子页面调用，返回时重置导航栏状态
  void resetNavBarState() {
    if (mounted) {
      _showNavBarImmediately();
      _resetInactivityTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF7DD3C0)),
          ),
        ),
      );
    }

    // 检查是否为特殊主题（需要动画背景）
    final themeProvider = context.watch<ThemeProvider>();
    final currentTheme = themeProvider.currentScheme.name;
    final isSpecialTheme = [
      '星空主题', '樱花主题', '海洋主题', '极光主题', '黄金主题'
    ].contains(currentTheme);

    // 设置系统导航栏颜色
    // 极光主题：导航栏颜色与主题背景一致（特殊处理）
    // 其他主题：导航栏颜色也与主题背景一致（与极光主题统一处理）
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor: themeProvider.currentScheme.backgroundColor,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    // 获取系统导航栏高度
    final systemNavBarHeight = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: isSpecialTheme ? themeProvider.currentScheme.backgroundColor : null,
      // 让 body 延伸到屏幕底部
      extendBody: true,
      // 不使用默认 bottomNavigationBar，在 Stack 中手动布局
      body: Stack(
        children: [
          // 页面内容 - 在系统导航栏上方，延伸到软件导航栏下方
          Positioned.fill(
            bottom: systemNavBarHeight, // 留出系统导航栏高度，确保内容不被系统导航栏挡住
            child: GestureDetector(
              // 点击页面内容时显示导航栏并重置计时器
              onTapDown: (_) {
                // 标记刚点击过，防止点击触发的微滚动干扰
                _justTapped = true;
                _showNavBar();
                _resetInactivityTimer();
                // 300ms后清除标记
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) _justTapped = false;
                });
                // 启动3秒长按计时器（长按空白区打开速记）
                _longPressTriggered = false;
                _longPressTimer?.cancel();
                _longPressTimer = Timer(const Duration(seconds: 3), () {
                  _longPressTriggered = true;
                  HapticFeedback.heavyImpact();
                  _openQuickNoteEditor();
                });
              },
              onTapUp: (_) {
                _longPressTimer?.cancel();
              },
              onTapCancel: () {
                _longPressTimer?.cancel();
              },
              behavior: HitTestBehavior.translucent,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: SafeArea(
                  bottom: false, // 让内容延伸到屏幕底部
                  child: ThemeBackgroundFactory.wrap(
                    themeName: currentTheme,
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: _onPageChanged,
                      physics: const NeverScrollableScrollPhysics(),
                      children: _screens,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 速记悬浮按钮（右上角）
          if (_quickNoteFabEnabled)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: GestureDetector(
                onTap: _openQuickNoteEditor,
                onLongPress: _openQuickNotesList,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: themeProvider.currentScheme.cardColor.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: themeProvider.currentScheme.dividerColor.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: themeProvider.currentScheme.shadowColor.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.lightbulb_outline,
                    size: 22,
                    color: themeProvider.currentScheme.primaryColor,
                  ),
                ),
              ),
            ),
          // 软件导航栏 - 悬浮在页面内容上方（放在Stack顶层，避免被GestureDetector包裹）
          Positioned(
            left: 0,
            right: 0,
            bottom: systemNavBarHeight, // 位于系统导航栏上方
            height: 88, // 从96缩小到88，减少全面屏下巴间距
            child: AnimatedSlide(
              offset: _isNavVisible ? Offset.zero : const Offset(0, 1.5),
              duration: _forceShowNav ? Duration.zero : const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _isNavVisible ? 1.0 : 0.0,
                duration: _forceShowNav ? Duration.zero : const Duration(milliseconds: 200),
                child: CustomBottomNav(
                  currentIndex: _currentIndex,
                  onTap: _onNavTap,
                  onAddTap: _onAddTap,
                  onAddLongPress: _onAddLongPress,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
