import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/custom_goal.dart';
import '../providers/custom_goal_provider.dart';
import '../providers/theme_provider.dart';

/// 自定义目标卡片（日历页迷你版）
class CustomGoalMiniCard extends StatefulWidget {
  final VoidCallback? onTapSettings;

  const CustomGoalMiniCard({super.key, this.onTapSettings});

  @override
  State<CustomGoalMiniCard> createState() => _CustomGoalMiniCardState();
}

class _CustomGoalMiniCardState extends State<CustomGoalMiniCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Consumer<CustomGoalProvider>(
      builder: (context, provider, child) {
        final activeGoal = provider.activeGoal;
        final otherGoals = provider.otherGoals;
        final hasGoals = provider.hasGoals;
        final canAddMore = provider.goalCount < provider.maxGoals;
        final goalCount = provider.goalCount;
        final maxGoals = provider.maxGoals;

        // 如果没有目标，显示创建提示
        if (!hasGoals) {
          return _buildEmptyCard(scheme);
        }

        return GestureDetector(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.cardColor,
                  scheme.cardColor.withOpacity(0.9),
                ],
              ),
              borderRadius: BorderRadius.circular(AppTheme.xlRadius),
              boxShadow: AppTheme.cardShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 主目标显示（始终显示激活的目标）
                _buildMainGoalRow(activeGoal!, otherGoals.length, scheme, canAddMore, goalCount, maxGoals),
                
                // 展开后的其他目标列表
                if (_isExpanded && otherGoals.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Divider(height: 1, color: scheme.lightColor.withOpacity(0.3)),
                  const SizedBox(height: 12),
                  ...otherGoals.map((goal) => _buildOtherGoalItem(goal, scheme)),
                ],
                
                // 展开后的添加按钮（如果还能添加）
                if (_isExpanded && canAddMore) ...[
                  const SizedBox(height: 8),
                  _buildAddGoalButton(scheme),
                ],
                
                // 展开后的提示（如果已满）
                if (_isExpanded && !canAddMore) ...[
                  const SizedBox(height: 8),
                  Text(
                    '已达到最大目标数（$maxGoals个）',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.textLightColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建主目标行（激活的目标）
  Widget _buildMainGoalRow(
    CustomGoal goal, 
    int otherCount, 
    ThemeScheme scheme,
    bool canAddMore,
    int goalCount,
    int maxGoals,
  ) {
    return Row(
      children: [
        // 进度圆环（小）
        SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            value: goal.progress,
            strokeWidth: 3,
            backgroundColor: scheme.lightColor.withOpacity(0.3),
            valueColor: AlwaysStoppedAnimation<Color>(
              goal.isCompleted ? Colors.green : scheme.primaryColor,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 进度文字
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    goal.icon ?? '🎯',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      goal.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.textDarkColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${goal.currentCount} / ${goal.targetCount}${goal.unit} · ${goal.periodDisplay}',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.textMediumColor,
                ),
              ),
            ],
          ),
        ),
        
        // 其他目标数量提示
        if (otherCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: scheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '还有$otherCount个',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: scheme.primaryColor,
              ),
            ),
          ),
        
        // 展开/收起图标
        AnimatedRotation(
          turns: _isExpanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 300),
          child: Icon(
            Icons.keyboard_arrow_down,
            color: scheme.textLightColor,
          ),
        ),
        
        // 设置按钮（编辑当前目标）
        GestureDetector(
          onTap: () => _showEditGoalSheet(goal),
          child: Container(
            padding: const EdgeInsets.all(6),
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: scheme.lightColor.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.edit_outlined,
              size: 16,
              color: scheme.textMediumColor,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建其他目标项
  Widget _buildOtherGoalItem(CustomGoal goal, ThemeScheme scheme) {
    return GestureDetector(
      onTap: () => _switchActiveGoal(goal.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.lightColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // 进度指示
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                value: goal.progress,
                strokeWidth: 2.5,
                backgroundColor: scheme.lightColor.withOpacity(0.3),
                valueColor: AlwaysStoppedAnimation<Color>(
                  goal.isCompleted ? Colors.green : scheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 目标信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        goal.icon ?? '🎯',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          goal.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.textDarkColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${goal.currentCount}/${goal.targetCount}${goal.unit}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.textMediumColor,
                    ),
                  ),
                ],
              ),
            ),
            // 切换按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '切换',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: scheme.primaryColor,
                ),
              ),
            ),
            // 编辑按钮
            GestureDetector(
              onTap: () => _showEditGoalSheet(goal),
              child: Container(
                padding: const EdgeInsets.all(6),
                margin: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: scheme.textLightColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建添加目标按钮
  Widget _buildAddGoalButton(ThemeScheme scheme) {
    return GestureDetector(
      onTap: () => _showAddGoalSheet(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: scheme.primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.primaryColor.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add,
              size: 18,
              color: scheme.primaryColor,
            ),
            const SizedBox(width: 6),
            Text(
              '添加新目标',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 切换激活目标
  void _switchActiveGoal(String goalId) async {
    await context.read<CustomGoalProvider>().setActiveGoal(goalId);
    setState(() {
      _isExpanded = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已切换目标')),
      );
    }
  }

  /// 显示编辑目标弹窗
  void _showEditGoalSheet(CustomGoal goal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => CustomGoalSettingSheet(editGoal: goal),
    );
  }

  /// 显示添加目标弹窗
  void _showAddGoalSheet() async {
    final provider = context.read<CustomGoalProvider>();
    final canAdd = await provider.canAddMoreGoals();
    if (!canAdd) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('最多只能设置5个目标')),
        );
      }
      return;
    }
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const CustomGoalSettingSheet(),
    );
  }

  Widget _buildEmptyCard(ThemeScheme scheme) {
    return GestureDetector(
      onTap: widget.onTapSettings ?? _showAddGoalSheet,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.cardColor.withOpacity(0.5),
          borderRadius: BorderRadius.circular(AppTheme.xlRadius),
          border: Border.all(
            color: scheme.primaryColor.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.lightColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add,
                color: scheme.primaryColor.withOpacity(0.5),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '设置自定义目标',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '例如：每天喝水8杯、每周运动3次',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.textMediumColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: scheme.textLightColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// 目标设置弹窗
class CustomGoalSettingSheet extends StatefulWidget {
  /// 要编辑的目标（为null表示创建新目标）
  final CustomGoal? editGoal;
  
  const CustomGoalSettingSheet({
    super.key,
    this.editGoal,
  });

  @override
  State<CustomGoalSettingSheet> createState() => _CustomGoalSettingSheetState();
}

class _CustomGoalSettingSheetState extends State<CustomGoalSettingSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _targetController;
  late GoalPeriod _selectedPeriod;
  late String _selectedIcon;
  final bool _isCustomInput = false;
  
  bool get _isEditMode => widget.editGoal != null;

  final List<String> _commonIcons = [
    '💧',
    '🏃',
    '📚',
    '🧘',
    '📝',
    '🍎',
    '😴',
    '💪',
    '🥗',
    '💊',
    '🦷',
    '🧹',
    '💰',
    '🎸',
    '🎨',
    '💻',
  ];

  @override
  void initState() {
    super.initState();
    // 如果是编辑模式，使用现有目标的数据
    if (_isEditMode) {
      final goal = widget.editGoal!;
      _nameController = TextEditingController(text: goal.name);
      _targetController = TextEditingController(text: goal.targetCount.toString());
      _selectedPeriod = goal.period;
      _selectedIcon = goal.icon ?? '💧';
    } else {
      _nameController = TextEditingController();
      _targetController = TextEditingController(text: '8');
      _selectedPeriod = GoalPeriod.daily;
      _selectedIcon = '💧';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Row(
                children: [
                  Text(
                    _isEditMode ? '编辑目标' : '设置目标',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const Spacer(),
                  if (_isEditMode)
                    TextButton.icon(
                      onPressed: _deleteGoal,
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      label: const Text('删除', style: TextStyle(color: Colors.red)),
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: scheme.textMediumColor),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 快捷模板（仅在创建模式下显示）
              if (!_isEditMode) ...[
                Text(
                  '快捷模板',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.textDarkColor,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: GoalTemplate.presets.map((template) {
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _nameController.text = template.name;
                          _targetController.text =
                              template.targetCount.toString();
                          _selectedPeriod = template.period;
                          _selectedIcon = template.icon;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: scheme.cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: scheme.lightColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(template.icon,
                                style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 4),
                            Text(
                              template.name,
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.textDarkColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),
                Divider(height: 1, color: scheme.lightColor.withOpacity(0.3)),
                const SizedBox(height: 24),
              ],

              // 自定义设置
              Text(
                '自定义设置',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
              const SizedBox(height: 16),

              // 图标选择
              Text(
                '选择图标',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.textMediumColor,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _commonIcons.map((icon) {
                  final isSelected = _selectedIcon == icon;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIcon = icon),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? scheme.primaryColor.withOpacity(0.15)
                            : scheme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? scheme.primaryColor
                              : scheme.lightColor.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        icon,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // 目标名称
              Text(
                '目标名称',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.textMediumColor,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: '例如：喝水、运动、阅读',
                  hintStyle: TextStyle(color: scheme.textLightColor),
                  filled: true,
                  fillColor: scheme.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                style: TextStyle(color: scheme.textDarkColor),
              ),

              const SizedBox(height: 16),

              // 周期选择
              Text(
                '目标周期',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.textMediumColor,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: GoalPeriod.values.map((period) {
                  final isSelected = _selectedPeriod == period;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedPeriod = period),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? scheme.primaryColor
                              : scheme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          period.displayName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : scheme.textDarkColor,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // 目标数量
              Text(
                '目标数量',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.textMediumColor,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '输入数量',
                        hintStyle: TextStyle(color: scheme.textLightColor),
                        filled: true,
                        fillColor: scheme.cardColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: scheme.textDarkColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '次/${_selectedPeriod.shortName}',
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.textMediumColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // 保存按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isEditMode ? _updateGoal : _saveGoal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _isEditMode ? '更新目标' : '保存目标',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
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

  void _saveGoal() {
    final name = _nameController.text.trim();
    final target = int.tryParse(_targetController.text) ?? 8;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入目标名称')),
      );
      return;
    }

    if (target <= 0 || target > 999) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的目标数量（1-999）')),
      );
      return;
    }

    final goal = CustomGoal(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      icon: _selectedIcon,
      targetCount: target,
      period: _selectedPeriod,
    );

    context.read<CustomGoalProvider>().addGoal(goal).then((_) {
      Navigator.pop(context);
    }).catchError((e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加失败：$e')),
      );
    });
  }
  
  void _updateGoal() {
    final name = _nameController.text.trim();
    final target = int.tryParse(_targetController.text) ?? 8;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入目标名称')),
      );
      return;
    }

    if (target <= 0 || target > 999) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的目标数量（1-999）')),
      );
      return;
    }

    // 创建更新后的目标
    final updatedGoal = widget.editGoal!.copyWith(
      name: name,
      icon: _selectedIcon,
      targetCount: target,
      period: _selectedPeriod,
    );

    context.read<CustomGoalProvider>().updateGoal(updatedGoal).then((_) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目标已更新')),
      );
    });
  }
  
  void _deleteGoal() {
    final scheme = AppTheme.schemeOf(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除？', style: TextStyle(color: scheme.textDarkColor)),
        content: Text(
          '删除后无法恢复，确定要删除目标"${widget.editGoal!.name}"吗？',
          style: TextStyle(color: scheme.textMediumColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: scheme.textLightColor)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // 关闭确认对话框
              context.read<CustomGoalProvider>().deleteGoal(widget.editGoal!.id).then((_) {
                Navigator.pop(context); // 关闭设置弹窗
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('目标已删除')),
                );
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
