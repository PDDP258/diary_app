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

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;
  bool _isLoading = true;
  
  // 使用 PageController 来管理页面切换，提高性能
  late PageController _pageController;

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
    // 延迟加载数据，避免在构建过程中调用 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
    }
  }

  void _onNavTap(int index) {
    // 播放点击音效
    SoundService.playClick();
    
    // 使用 PageController 跳转页面，提高性能
    if (_currentIndex != index) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onAddTap() async {
    // 播放点击音效
    SoundService.playClick();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WriteDiaryScreen(),
      ),
    );
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

    return Scaffold(
      backgroundColor: isSpecialTheme ? themeProvider.currentScheme.backgroundColor : null,
      // 让 body 延伸到 bottomNavigationBar 下方
      extendBody: true,
      body: SafeArea(
        // 底部不处理，让内容延伸到屏幕底部
        bottom: false,
        child: ThemeBackgroundFactory.wrap(
          themeName: currentTheme,
          child: PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            physics: const NeverScrollableScrollPhysics(), // 禁用滑动，使用底部导航切换
            children: _screens,
          ),
        ),
      ),
      // bottomNavigationBar 被 SafeArea 包裹，自动避开系统导航栏
      bottomNavigationBar: SafeArea(
        top: false,
        left: false,
        right: false,
        child: CustomBottomNav(
          currentIndex: _currentIndex,
          onTap: _onNavTap,
          onAddTap: _onAddTap,
        ),
      ),
    );
  }
}
