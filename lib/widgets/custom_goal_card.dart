import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/custom_goal.dart';
import '../providers/custom_goal_provider.dart';
import '../services/custom_goal_service.dart';
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
        final goal = provider.activeGoal;
        
        // 如果没有目标，显示创建提示
        if (goal == null) {
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
                // 迷你进度条（始终显示）
                Row(
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
                              Text(
                                goal.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.textDarkColor,
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
                    // 展开/收起图标
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: scheme.textLightColor,
                      ),
                    ),
                    // 设置按钮
                    GestureDetector(
                      onTap: widget.onTapSettings,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        margin: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          color: scheme.lightColor.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.settings_outlined,
                          size: 16,
                          color: scheme.textMediumColor,
                        ),
                      ),
                    ),
                  ],
                ),
                // 展开后的详细内容
                if (_isExpanded) ...[
                  const SizedBox(height: 12),
                  Divider(height: 1, color: scheme.lightColor.withOpacity(0.3)),
                  const SizedBox(height: 12),
                  // 快捷操作按钮
                  Row(
                    children: [
                      // 减少按钮
                      _buildActionButton(
                        icon: Icons.remove,
                        onTap: () => provider.decrementGoal(goal.id),
                        scheme: scheme,
                      ),
                      const SizedBox(width: 12),
                      // 进度条
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: goal.progress,
                            minHeight: 8,
                            backgroundColor: scheme.lightColor.withOpacity(0.3),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              goal.isCompleted ? Colors.green : scheme.primaryColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 增加按钮
                      _buildActionButton(
                        icon: Icons.add,
                        onTap: () => provider.incrementGoal(goal.id),
                        scheme: scheme,
                        isPrimary: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '完成度 ${(goal.progress * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.textMediumColor,
                        ),
                      ),
                      if (goal.isCompleted)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, size: 12, color: Colors.green),
                              const SizedBox(width: 4),
                              Text(
                                '已达成',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          '还差 ${goal.remaining}${goal.unit}',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.textLightColor,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required ThemeScheme scheme,
    bool isPrimary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isPrimary 
              ? scheme.primaryColor 
              : scheme.lightColor.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 16,
          color: isPrimary ? Colors.white : scheme.textMediumColor,
        ),
      ),
    );
  }
  
  Widget _buildEmptyCard(ThemeScheme scheme) {
    return GestureDetector(
      onTap: widget.onTapSettings,
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
  const CustomGoalSettingSheet({super.key});
  
  @override
  State<CustomGoalSettingSheet> createState() => _CustomGoalSettingSheetState();
}

class _CustomGoalSettingSheetState extends State<CustomGoalSettingSheet> {
  final _nameController = TextEditingController();
  final _targetController = TextEditingController(text: '8');
  GoalPeriod _selectedPeriod = GoalPeriod.daily;
  String _selectedIcon = '💧';
  bool _isCustomInput = false;
  
  final List<String> _commonIcons = [
    '💧', '🏃', '📚', '🧘', '📝', '🍎', '😴', '💪', 
    '🥗', '💊', '🦷', '🧹', '💰', '🎸', '🎨', '💻',
  ];
  
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
                    '设置目标',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: scheme.textMediumColor),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // 快捷模板
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
                        _targetController.text = template.targetCount.toString();
                        _selectedPeriod = template.period;
                        _selectedIcon = template.icon;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          Text(template.icon, style: const TextStyle(fontSize: 16)),
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
                            color: isSelected ? Colors.white : scheme.textDarkColor,
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
                  onPressed: _saveGoal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '保存目标',
                    style: TextStyle(
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
    });
  }
}
