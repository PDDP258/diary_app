import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/diary.dart';
import '../providers/diary_provider.dart';
import '../providers/theme_provider.dart';
import 'diary_detail_screen.dart';

/// 日记搜索页面
class DiarySearchScreen extends StatefulWidget {
  const DiarySearchScreen({super.key});

  @override
  State<DiarySearchScreen> createState() => _DiarySearchScreenState();
}

class _DiarySearchScreenState extends State<DiarySearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Diary> _searchResults = [];
  bool _isSearching = false;
  String _lastQuery = '';
  
  @override
  void initState() {
    super.initState();
    // 自动聚焦搜索框
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
  
  /// 执行搜索
  void _performSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _lastQuery = '';
      });
      return;
    }
    
    setState(() {
      _isSearching = true;
      _lastQuery = query.trim();
    });
    
    final provider = context.read<DiaryProvider>();
    final allDiaries = provider.diaries;
    final lowerQuery = query.toLowerCase();
    
    // 搜索标题和内容
    final results = allDiaries.where((diary) {
      final titleMatch = diary.title?.toLowerCase().contains(lowerQuery) ?? false;
      final contentMatch = diary.content?.toLowerCase().contains(lowerQuery) ?? false;
      return titleMatch || contentMatch;
    }).toList();
    
    // 按日期排序（最新的在前）
    results.sort((a, b) => b.date.compareTo(a.date));
    
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }
  
  /// 高亮搜索关键词
  List<TextSpan> _highlightText(String text, String query, Color textColor) {
    if (query.isEmpty) {
      return [TextSpan(text: text, style: TextStyle(color: textColor))];
    }
    
    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    int start = 0;
    
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        if (start < text.length) {
          spans.add(TextSpan(
            text: text.substring(start),
            style: TextStyle(color: textColor),
          ));
        }
        break;
      }
      
      // 添加匹配前的文本
      if (index > start) {
        spans.add(TextSpan(
          text: text.substring(start, index),
          style: TextStyle(color: textColor),
        ));
      }
      
      // 添加高亮的匹配文本
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: TextStyle(
          color: textColor,
          backgroundColor: AppTheme.selectedGreen.withValues(alpha: 0.4),
          fontWeight: FontWeight.bold,
        ),
      ));
      
      start = index + query.length;
    }
    
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 搜索栏
            _buildSearchBar(scheme),
            
            // 搜索结果统计
            if (_lastQuery.isNotEmpty && !_isSearching)
              _buildResultCount(scheme),
            
            // 搜索结果列表
            Expanded(
              child: _isSearching
                  ? Center(
                      child: CircularProgressIndicator(
                        color: scheme.primaryColor,
                      ),
                    )
                  : _searchResults.isEmpty
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: scheme.cardColor,
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
          // 返回按钮
          IconButton(
            icon: Icon(Icons.arrow_back, color: scheme.textDarkColor),
            onPressed: () => Navigator.pop(context),
          ),
          
          // 搜索输入框
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: scheme.lightColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                style: TextStyle(
                  fontSize: 16,
                  color: scheme.textDarkColor,
                ),
                decoration: InputDecoration(
                  hintText: '搜索日记标题或内容...',
                  hintStyle: TextStyle(
                    color: scheme.textLightColor,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: 20,
                            color: scheme.textLightColor,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _performSearch('');
                          },
                        )
                      : null,
                ),
                onChanged: (value) {
                  setState(() {});
                  // 防抖搜索
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (_searchController.text == value) {
                      _performSearch(value);
                    }
                  });
                },
                textInputAction: TextInputAction.search,
                onSubmitted: _performSearch,
              ),
            ),
          ),
          
          // 搜索按钮
          IconButton(
            icon: Icon(Icons.search, color: scheme.primaryColor),
            onPressed: () => _performSearch(_searchController.text),
          ),
        ],
      ),
    );
  }
  
  Widget _buildResultCount(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      alignment: Alignment.centerLeft,
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 14,
            color: scheme.textMediumColor,
          ),
          children: [
            const TextSpan(text: '找到 '),
            TextSpan(
              text: '${_searchResults.length}',
              style: TextStyle(
                color: scheme.primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const TextSpan(text: ' 篇相关日记'),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEmptyState(ThemeScheme scheme) {
    if (_lastQuery.isEmpty) {
      // 初始状态
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: scheme.lightColor,
            ),
            const SizedBox(height: 16),
            Text(
              '输入关键词搜索日记',
              style: TextStyle(
                fontSize: 16,
                color: scheme.textLightColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '可以搜索标题或正文内容',
              style: TextStyle(
                fontSize: 13,
                color: scheme.textLightColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }
    
    // 无结果状态
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
            '未找到相关日记',
            style: TextStyle(
              fontSize: 16,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '试试其他关键词',
            style: TextStyle(
              fontSize: 13,
              color: scheme.textLightColor,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildResultsList(ThemeScheme scheme) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final diary = _searchResults[index];
        return _buildDiaryCard(diary, scheme);
      },
    );
  }
  
  Widget _buildDiaryCard(Diary diary, ThemeScheme scheme) {
    // 提取匹配的文本片段
    String snippet = '';
    if (diary.content != null && diary.content!.isNotEmpty) {
      final content = diary.content!;
      final lowerContent = content.toLowerCase();
      final lowerQuery = _lastQuery.toLowerCase();
      final index = lowerContent.indexOf(lowerQuery);
      
      if (index != -1) {
        // 找到匹配位置，提取前后文本
        final start = index > 20 ? index - 20 : 0;
        final end = (index + _lastQuery.length + 50 < content.length)
            ? index + _lastQuery.length + 50
            : content.length;
        snippet = '${start > 0 ? '...' : ''}${content.substring(start, end)}${end < content.length ? '...' : ''}';
      } else {
        snippet = content.length > 70 ? '${content.substring(0, 70)}...' : content;
      }
    }
    
    return GestureDetector(
      onTap: () => _viewDiary(diary),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                // 心情表情
                if (diary.moodEmoji != null)
                  Text(
                    diary.moodEmoji!,
                    style: const TextStyle(fontSize: 20),
                  ),
                if (diary.moodEmoji != null)
                  const SizedBox(width: 8),
                
                // 日期
                Text(
                  DateFormat('yyyy年M月d日').format(DateTime.parse(diary.date)),
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.textLightColor,
                  ),
                ),
                
                const Spacer(),
                
                // 字数
                Text(
                  '${diary.wordCount}字',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.textLightColor,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // 标题
            if (diary.title != null && diary.title!.isNotEmpty)
              RichText(
                text: TextSpan(
                  children: _highlightText(
                    diary.title!,
                    _lastQuery,
                    scheme.textDarkColor,
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            
            // 内容片段
            if (snippet.isNotEmpty) ...[
              const SizedBox(height: 6),
              RichText(
                text: TextSpan(
                  children: _highlightText(
                    snippet,
                    _lastQuery,
                    scheme.textMediumColor,
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Future<void> _viewDiary(Diary diary) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiaryDetailScreen(diary: diary),
      ),
    );
    
    if (result == true) {
      // 刷新搜索结果
      _performSearch(_lastQuery);
    }
  }
}
