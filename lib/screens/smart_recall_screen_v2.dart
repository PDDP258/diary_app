import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';
import '../services/smart_recall_service.dart';
import '../providers/theme_provider.dart';
import 'diary_detail_screen.dart';

/// 智能回忆页面 - 重新设计版
class SmartRecallScreen extends StatefulWidget {
  const SmartRecallScreen({super.key});

  @override
  State<SmartRecallScreen> createState() => _SmartRecallScreenState();
}

class _SmartRecallScreenState extends State<SmartRecallScreen> {
  List<RecallItem> _recalls = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecalls();
  }

  Future<void> _loadRecalls() async {
    setState(() => _isLoading = true);
    
    final recalls = await SmartRecallService.getSmartRecalls(limit: 5);
    
    if (mounted) {
      setState(() {
        _recalls = recalls;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '智能回忆',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: scheme.textDarkColor,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: scheme.primaryColor),
            onPressed: _loadRecalls,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _recalls.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadRecalls,
                  color: scheme.primaryColor,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _recalls.length,
                    itemBuilder: (context, index) {
                      return _RecallCard(
                        recall: _recalls[index],
                        onTap: () async {
                          HapticFeedback.mediumImpact();
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DiaryDetailScreen(
                                diary: _recalls[index].diary,
                              ),
                            ),
                          );
                          _loadRecalls();
                        },
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    final scheme = AppTheme.schemeOf(context);
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: scheme.lightColor.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history,
                size: 36,
                color: scheme.primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有足够的日记',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: scheme.textDarkColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '多写几篇日记，我们会为你发现\n值得回味的精彩瞬间',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: scheme.textLightColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 回忆卡片
class _RecallCard extends StatelessWidget {
  final RecallItem recall;
  final VoidCallback onTap;

  const _RecallCard({
    required this.recall,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final color = Color(recall.color);
    
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部标签栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Text(recall.icon, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(
                    recall.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      recall.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: color.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 内容区
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (recall.diary.moodEmoji != null) ...[
                    Row(
                      children: [
                        Text(
                          recall.diary.moodEmoji!,
                          style: const TextStyle(fontSize: 20),
                        ),
                        if (recall.diary.moodName != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            recall.diary.moodName!,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.textLightColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (recall.highlight != null)
                    Text(
                      recall.highlight!,
                      style: TextStyle(
                        fontSize: 15,
                        color: scheme.textDarkColor,
                        height: 1.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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


class SmartRecallHomeCard extends StatefulWidget {
  const SmartRecallHomeCard({super.key});

  @override
  State<SmartRecallHomeCard> createState() => _SmartRecallHomeCardState();
}

class _SmartRecallHomeCardState extends State<SmartRecallHomeCard>
    with SingleTickerProviderStateMixin {
  RecallItem? _todayRecall;
  bool _isLoading = true;
  bool _isExpanded = true;

  late AnimationController _controller;
  late Animation<double> _rotationAnimation;
  Timer? _autoCollapseTimer;

  @override
  void initState() {
    super.initState();
    _loadTodayRecall();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _scheduleAutoCollapse();
  }

  @override
  void dispose() {
    _autoCollapseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleAutoCollapse() {
    _autoCollapseTimer?.cancel();
    _autoCollapseTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isExpanded) {
        _collapse();
      }
    });
  }

  void _collapse() {
    if (!_isExpanded) return;
    setState(() {
      _isExpanded = false;
      _controller.reverse();
    });
  }

  void _expand() {
    if (_isExpanded) return;
    setState(() {
      _isExpanded = true;
      _controller.forward();
    });
    _scheduleAutoCollapse();
  }

  Future<void> _loadTodayRecall() async {
    final recalls = await SmartRecallService.getSmartRecalls(limit: 1);
    if (mounted) {
      setState(() {
        _todayRecall = recalls.isNotEmpty ? recalls.first : null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    if (_isLoading || _todayRecall == null) {
      return const SizedBox.shrink();
    }

    final color = Color(_todayRecall!.color);

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: _isExpanded ? 0.25 : 0.15),
              width: _isExpanded ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: _isExpanded ? 16 : 10,
                offset: const Offset(0, 4),
                spreadRadius: _isExpanded ? 0 : -2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部胶囊条
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: _isExpanded ? _collapse : _expand,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              _todayRecall!.icon,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (_isExpanded)
                          Expanded(
                            child: Text(
                              _todayRecall!.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else
                          Expanded(
                            child: Text(
                              '珍贵的回忆',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ),
                        RotationTransition(
                          turns: _rotationAnimation,
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            color: color,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 展开内容 - 原地显示摘要
              if (_isExpanded)
                Material(
                  color: Colors.transparent,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                  child: InkWell(
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DiaryDetailScreen(
                            diary: _todayRecall!.diary,
                          ),
                        ),
                      );
                      _loadTodayRecall();
                    },
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Divider(
                            height: 1,
                            color: scheme.dividerColor,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _todayRecall!.highlight ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.textMediumColor,
                              height: 1.45,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.date_range,
                                size: 13,
                                color: scheme.textLightColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _todayRecall!.subtitle,
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
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
