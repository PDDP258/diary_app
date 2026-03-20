import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';

/// 日记模板数据
class DiaryTemplate {
  final String id;
  final String name;
  final String icon;
  final String title;
  final String content;
  final List<String> prompts;
  final Color color;

  const DiaryTemplate({
    required this.id,
    required this.name,
    required this.icon,
    required this.title,
    required this.content,
    required this.prompts,
    required this.color,
  });
}

/// 预定义的日记模板
class DiaryTemplates {
  static const List<DiaryTemplate> templates = [
    // 日常记录
    DiaryTemplate(
      id: 'daily',
      name: '日常记录',
      icon: '📝',
      title: '',
      content: '''今天发生了一些有趣的事情...

早上：

中午：

晚上：

今天的心情：

明天的计划：''',
      prompts: ['今天最开心的事是什么？', '有什么值得记录的吗？', '今天学到了什么？'],
      color: Colors.blue,
    ),
    
    // 旅行日记
    DiaryTemplate(
      id: 'travel',
      name: '旅行日记',
      icon: '✈️',
      title: '',
      content: '''旅行地点：

同行的人：

今天的行程：

印象深刻的景点：

美食推荐：

旅行心得：''',
      prompts: ['今天去了哪里？', '有什么特别的经历？', '拍到了什么好看的照片？'],
      color: Colors.green,
    ),
    
    // 工作记录
    DiaryTemplate(
      id: 'work',
      name: '工作记录',
      icon: '💼',
      title: '',
      content: '''今日工作内容：

1. 
2. 
3. 

遇到的问题：

解决方案：

明日计划：''',
      prompts: ['今天完成了什么任务？', '遇到了什么挑战？', '有什么收获？'],
      color: Colors.orange,
    ),
    
    // 心情随笔
    DiaryTemplate(
      id: 'mood',
      name: '心情随笔',
      icon: '💭',
      title: '',
      content: '''此刻的心情：

想对自己说：

感恩的事：

期待的事：

...''',
      prompts: ['现在感觉怎么样？', '有什么想倾诉的吗？', '今天感谢什么？'],
      color: Colors.purple,
    ),
    
    // 读书笔记
    DiaryTemplate(
      id: 'reading',
      name: '读书笔记',
      icon: '📚',
      title: '',
      content: '''书名：

作者：

今日阅读章节：

精彩内容摘录：

个人感悟：

行动计划：''',
      prompts: ['今天读了什么书？', '有什么触动你的内容？', '有什么启发？'],
      color: Colors.teal,
    ),
    
    // 美食记录
    DiaryTemplate(
      id: 'food',
      name: '美食记录',
      icon: '🍜',
      title: '',
      content: '''餐厅/地点：

菜品名称：

味道评价：⭐⭐⭐⭐⭐

环境评价：⭐⭐⭐⭐⭐

服务评价：⭐⭐⭐⭐⭐

推荐理由：''',
      prompts: ['今天吃了什么好吃的？', '味道怎么样？', '会推荐给朋友吗？'],
      color: Colors.red,
    ),
    
    // 运动健身
    DiaryTemplate(
      id: 'workout',
      name: '运动健身',
      icon: '💪',
      title: '',
      content: '''运动项目：

运动时长：

消耗卡路里：

运动感受：

身体状态：

明日计划：''',
      prompts: ['今天做了什么运动？', '感觉怎么样？', '达到了什么目标？'],
      color: Colors.cyan,
    ),
    
    // 学习笔记
    DiaryTemplate(
      id: 'study',
      name: '学习笔记',
      icon: '🎓',
      title: '',
      content: '''学习主题：

学习时间：

学习内容：

重点笔记：

疑问与思考：

下一步计划：''',
      prompts: ['今天学了什么？', '有什么新的理解？', '还有什么需要深入研究？'],
      color: Colors.indigo,
    ),
    
    // 感恩日记
    DiaryTemplate(
      id: 'gratitude',
      name: '感恩日记',
      icon: '🙏',
      title: '感恩的一天',
      content: '''今天我要感谢：

1. 

2. 

3. 

让我开心的小事：

今天学到的东西：

对自己的肯定：''',
      prompts: ['今天有什么值得感恩的事？', '谁帮助了你？', '你帮助了谁？'],
      color: Colors.amber,
    ),
    
    // 梦境记录
    DiaryTemplate(
      id: 'dream',
      name: '梦境记录',
      icon: '🌙',
      title: '奇妙的梦',
      content: '''梦境时间：

梦境场景：

梦中人物：

梦境情节：

梦境感受：

现实联想：''',
      prompts: ['梦到了什么？', '梦里有什么特别的人或事？', '这个梦让你想到什么？'],
      color: Colors.deepPurple,
    ),
    
    // 情感记录
    DiaryTemplate(
      id: 'emotion',
      name: '情感记录',
      icon: '❤️',
      title: '',
      content: '''今天的情绪：

情绪触发原因：

身体感受：

想法与认知：

应对方式：

自我关怀：''',
      prompts: ['今天心情如何？', '是什么影响了你的情绪？', '你如何应对的？'],
      color: Colors.pink,
    ),
    
    // 目标规划
    DiaryTemplate(
      id: 'goal',
      name: '目标规划',
      icon: '🎯',
      title: '我的目标',
      content: '''目标名称：

目标期限：

具体行动：

1. 

2. 

3. 

可能遇到的困难：

应对策略：

奖励机制：''',
      prompts: ['你想达成什么目标？', '需要做什么？', '如何保持动力？'],
      color: Colors.lightGreen,
    ),
    
    // 观影记录
    DiaryTemplate(
      id: 'movie',
      name: '观影记录',
      icon: '🎬',
      title: '',
      content: '''影片名称：

观影时间：

影片类型：

剧情简介：

精彩台词：

个人评价：⭐⭐⭐⭐⭐

推荐理由：''',
      prompts: ['看了什么电影/剧？', '最打动你的地方？', '会推荐给朋友吗？'],
      color: Colors.redAccent,
    ),
    
    // 财务记录
    DiaryTemplate(
      id: 'finance',
      name: '财务记录',
      icon: '💰',
      title: '今日收支',
      content: '''今日收入：

今日支出：

大额支出项目：

消费反思：

储蓄计划：

理财心得：''',
      prompts: ['今天花了什么钱？', '有必要吗？', '如何更好地管理财务？'],
      color: const Color(0xFF388E3C),
    ),
    
    // 人际关系
    DiaryTemplate(
      id: 'relationship',
      name: '人际关系',
      icon: '👥',
      title: '',
      content: '''今天互动的人：

印象深刻的对话：

关系进展：

需要改进的地方：

感恩的人：

明日互动计划：''',
      prompts: ['今天和谁有重要互动？', '关系有什么变化？', '如何维护这段关系？'],
      color: const Color(0xFFF57C00),
    ),
    
    // 创意灵感
    DiaryTemplate(
      id: 'creative',
      name: '创意灵感',
      icon: '💡',
      title: '灵感闪现',
      content: '''灵感主题：

灵感来源：

具体想法：

可行性分析：

实施步骤：

需要的资源：''',
      prompts: ['今天有什么新想法？', '这个想法从何而来？', '如何实现它？'],
      color: const Color(0xFFFBC02D),
    ),
    
    // 健康记录
    DiaryTemplate(
      id: 'health',
      name: '健康记录',
      icon: '🏥',
      title: '健康日记',
      content: '''今日身体状况：

睡眠质量：⭐⭐⭐⭐⭐

饮食情况：

运动记录：

情绪状态：

健康目标：''',
      prompts: ['今天身体感觉如何？', '饮食运动情况？', '有什么健康目标？'],
      color: Colors.lightBlue,
    ),
  ];

  /// 根据ID获取模板
  static DiaryTemplate? getById(String id) {
    try {
      return templates.firstWhere((t) => t.id == id);
    } catch (e) {
      return null;
    }
  }
}

/// 日记模板选择器
class DiaryTemplateSelector extends StatelessWidget {
  final Function(DiaryTemplate) onSelect;

  const DiaryTemplateSelector({
    super.key,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Container(
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '选择日记模板',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: scheme.textDarkColor,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: scheme.textMediumColor),
                ),
              ],
            ),
          ),

          // 提示文字
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '选择一个模板快速开始写日记',
              style: TextStyle(
                fontSize: 14,
                color: scheme.textMediumColor,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 模板网格
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.8,
              ),
              itemCount: DiaryTemplates.templates.length,
              itemBuilder: (context, index) {
                final template = DiaryTemplates.templates[index];
                return _buildTemplateItem(context, template, scheme);
              },
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTemplateItem(BuildContext context, DiaryTemplate template, ThemeScheme scheme) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        onSelect(template);
      },
      child: Container(
        decoration: BoxDecoration(
          color: template.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: template.color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              template.icon,
              style: const TextStyle(fontSize: 32),
            ),
            const SizedBox(height: 8),
            Text(
              template.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: scheme.textDarkColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 日记模板提示卡片
class DiaryTemplatePrompts extends StatelessWidget {
  final DiaryTemplate template;
  final Function(String) onPromptTap;

  const DiaryTemplatePrompts({
    super.key,
    required this.template,
    required this.onPromptTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: template.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: template.color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                template.icon,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              Text(
                '${template.name}模板',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '点击提示快速添加内容：',
            style: TextStyle(
              fontSize: 12,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: template.prompts.map((prompt) {
              return GestureDetector(
                onTap: () => onPromptTap(prompt),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: template.color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    prompt,
                    style: TextStyle(
                      fontSize: 12,
                      color: template.color.withOpacity(0.8),
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
}

/// 显示模板选择器
void showDiaryTemplateSelector(
  BuildContext context, {
  required Function(DiaryTemplate) onSelect,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: DiaryTemplateSelector(onSelect: onSelect),
    ),
  );
}
