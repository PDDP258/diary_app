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
                color: scheme.lightColor.withOpacity(0.3),
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
        side: BorderSide(color: color.withOpacity(0.2)),
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
                color: color.withOpacity(0.08),
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
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      recall.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: color.withOpacity(0.8),
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

/// 首页回忆卡片（简化版）
class SmartRecallHomeCard extends StatefulWidget {
  const SmartRecallHomeCard({super.key});

  @override
  State<SmartRecallHomeCard> createState() => _SmartRecallHomeCardState();
}

class _SmartRecallHomeCardState extends State<SmartRecallHomeCard> {
  RecallItem? _todayRecall;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTodayRecall();
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
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withOpacity(0.2)),
        ),
        child: InkWell(
          onTap: () async {
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
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      _todayRecall!.icon,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _todayRecall!.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _todayRecall!.highlight ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.textMediumColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
