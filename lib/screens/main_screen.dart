import 'dart:async';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/diary_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/theme_backgrounds.dart';
import '../services/badge_service.dart';
import '../services/milestone_service.dart';
import '../services/image_cache_service.dart';
import '../services/sound_service.dart';
import '../widgets/custom_bottom_nav.dart';
import 'timeline_screen.dart';
import 'calendar_screen.dart';
import 'stats_screen.dart';
import 'profile_screen.dart';
import 'write_diary_screen.dart';

class MainScreen extends StatefulWidget {
  final int initialIndex;
  
  const MainScreen({super.key, this.initialIndex = 0});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> 
    with WidgetsBindingObserver, RouteAware {
  late int _currentIndex;
  bool _isLoading = true;

  // ✅ 移除：IndexedStack 不需要 PageController

  // 导航栏显示/隐藏控制
  bool _isNavVisible = true;
  double _lastScrollPixels = 0;

  // 5秒无操作计时器
  Timer? _inactivityTimer;
  static const _inactivityDuration = Duration(seconds: 5);

  // 标记是否刚处理过点击，防止点击触发的微滚动干扰
  bool _justTapped = false;

  // 标记是否强制显示导航栏（用于页面切换时立即显示，无动画）
  bool _forceShowNav = false;
  
  // ✅ 添加：防止快速点击导航栏导致异常
  bool _isNavigating = false;
  
  // ✅ 添加：用于检测从子页面返回
  bool _wasInBackground = false;

  // ✅ 修复：使用 final 字段，只创建一次页面实例
  // 避免每次 build 都创建新实例导致页面状态丢失
  final List<Widget> _screens = const [
    TimelineScreen(),
    CalendarScreen(),
    StatsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    // 注册生命周期监听
    WidgetsBinding.instance.addObserver(this);
    // 延迟加载数据，避免在构建过程中调用 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      // 启动3秒无操作计时器
      _resetInactivityTimer();
    });
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    // 移除生命周期监听
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 监听应用生命周期变化
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 应用从后台返回前台，显示导航栏并重新开始3秒计时
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

  // ✅ 简化：IndexedStack 不需要 onPageChanged 回调
  // 页面切换逻辑已在 _onNavTap 中处理

  void _onNavTap(int index) async {
    // ✅ 修复：防止快速点击导致异常
    if (_isNavigating || _currentIndex == index) return;
    
    _isNavigating = true;
    
    // 播放点击音效
    SoundService.playClick();

    // 点击导航栏时：立即显示导航栏（无动画）并重置3秒计时器
    _showNavBarImmediately();
    _resetInactivityTimer();

    // ✅ 修复：使用 IndexedStack 直接切换索引，无需动画
    setState(() => _currentIndex = index);
    
    // 300ms 后允许再次点击
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      _isNavigating = false;
    }
  }

  /// 处理滚动通知，控制导航栏显示/隐藏
  /// 下滑（向下滚动）：立即隐藏导航栏
  /// 上滑（向上滚动）：立即显示导航栏，3秒后隐藏
  bool _onScrollNotification(ScrollNotification notification) {
    // 如果刚点击过，只忽略小的滚动事件（防止点击触发的微滚动干扰）
    // 但用户主动的大幅度滑动应该正常处理
    // 注意：这里不再完全阻止滚动处理，只在滚动幅度小的时候可能忽略
    
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
        // 上滑（向上滚动）时立即显示导航栏并重新开始3秒计时
        else if (scrollDelta < -5) {
          _showNavBar();
          _resetInactivityTimer();
        }

        _lastScrollPixels = pixels;
      }
    }
    // 滚动到顶部时显示导航栏并重新开始3秒计时
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
    // 导航到其他页面前取消计时器
    _inactivityTimer?.cancel();
    
    // ✅ 修复：导航前确保导航栏显示（避免跳转时导航栏隐藏）
    _showNavBarImmediately();
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WriteDiaryScreen(),
      ),
    );
    
    // ✅ 修复：从子页面返回后，确保导航栏显示并重新开始3秒计时
    if (mounted) {
      _showNavBarImmediately();
      _resetInactivityTimer();
    }
    
    if (result == true && mounted) {
      // 刷新数据
      context.read<DiaryProvider>().loadDiaries();
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
    
    // ✅ 修复：检测从子页面返回（在 build 中检测最可靠）
    // 当 ModalRoute 变为当前路由时，说明从子页面返回了
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null && modalRoute.isCurrent && _wasInBackground) {
      // 从子页面返回，显示导航栏并重置计时器
      _wasInBackground = false;
      // 使用 addPostFrameCallback 避免在 build 中调用 setState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showNavBarImmediately();
          _resetInactivityTimer();
        }
      });
    } else if (modalRoute != null && !modalRoute.isCurrent) {
      // 当前不是顶层路由（在子页面中），标记为后台状态
      _wasInBackground = true;
    }

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
            child: Listener(
              // ✅ 修复：使用 onPointerDown 捕获所有指针按下事件
              // 无论子页面是否消费点击事件，都能捕获到
              onPointerDown: (_) {
                // 标记刚点击过，防止点击触发的微滚动干扰
                _justTapped = true;
                _showNavBar();
                _resetInactivityTimer();
                // ✅ 修复：减少延迟到100ms，避免影响用户主动滑动
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (mounted) _justTapped = false;
                });
              },
              behavior: HitTestBehavior.translucent,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: SafeArea(
                  bottom: false, // 让内容延伸到屏幕底部
                  child: ThemeBackgroundFactory.wrap(
                    themeName: currentTheme,
                    // ✅ 修复：使用 IndexedStack 替代 PageView
                    // IndexedStack 保持所有页面的状态，切换时不重建
                    child: IndexedStack(
                      index: _currentIndex,
                      children: _screens,
                    ),
                  ),
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
