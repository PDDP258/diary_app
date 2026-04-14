import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../providers/goal_provider.dart';
import '../services/goal_service.dart';

/// 目标进度卡片组件
class GoalProgressCard extends StatelessWidget {
  final VoidCallback? onTapSettings;
  
  const GoalProgressCard({super.key, this.onTapSettings});
  
  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    return Consumer<GoalProvider>(
      builder: (context, goalProvider, child) {
        final goal = goalProvider.currentGoal;
        
        if (goal == null) {
          return _buildEmptyCard(context, scheme);
        }
        
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: goal.isCompleted
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.green.shade50,
                      Colors.green.shade100.withValues(alpha: 0.5),
                    ],
                  )
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.cardColor.withValues(alpha: 0.9),
                      scheme.cardColor.withValues(alpha: 0.7),
                    ],
                  ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: goal.isCompleted
                  ? Colors.green.withValues(alpha: 0.3)
                  : scheme.primaryColor.withValues(alpha: 0.1),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (goal.isCompleted ? Colors.green : scheme.primaryColor)
                    .withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: -2,
              ),
            ],
          ),
          child: Row(
            children: [
              // 左侧：环形进度
              _buildProgressRing(goal, scheme),
              const SizedBox(width: 16),
              // 右侧：文字信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题行
                    Row(
                      children: [
                        Icon(
                          goal.type.icon,
                          size: 16,
                          color: goal.isCompleted
                              ? Colors.green
                              : scheme.primaryColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${goal.type.displayName}目标',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.textDarkColor,
                          ),
                        ),
                        const Spacer(),
                        // 设置按钮
                        GestureDetector(
                          onTap: onTapSettings,
                          child: Icon(
                            Icons.settings_outlined,
                            size: 18,
                            color: scheme.textLightColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 进度文字
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${goal.completedCount}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: goal.isCompleted
                                ? Colors.green
                                : scheme.primaryColor,
                          ),
                        ),
                        Text(
                          ' / ${goal.targetCount}${goal.type.unit}',
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.textMediumColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 进度条
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: goal.progress,
                        minHeight: 6,
                        backgroundColor: scheme.lightColor.withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          goal.isCompleted ? Colors.green : scheme.primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 底部信息
                    Row(
                      children: [
                        // 连续天数
                        if (goal.currentStreak > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🔥', style: TextStyle(fontSize: 12)),
                                const SizedBox(width: 2),
                                Text(
                                  '${goal.currentStreak}天',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(width: 8),
                        // 剩余或完成状态
                        if (goal.isCompleted)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 12,
                                  color: Colors.green.shade700,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '已完成',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Text(
                            '还差 ${goal.remaining}${goal.type.unit}',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.textLightColor,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  /// 构建环形进度
  Widget _buildProgressRing(MonthlyGoal goal, ThemeScheme scheme) {
    final color = goal.isCompleted ? Colors.green : scheme.primaryColor;
    
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景圆环
          CircularProgressIndicator(
            value: 1,
            strokeWidth: 8,
            backgroundColor: scheme.lightColor.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(
              scheme.lightColor.withValues(alpha: 0.1),
            ),
          ),
          // 进度圆环
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: goal.progress),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return CircularProgressIndicator(
                value: value,
                strokeWidth: 8,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                strokeCap: StrokeCap.round,
              );
            },
          ),
          // 中心内容
          Center(
            child: goal.isCompleted
                ? Icon(
                    Icons.emoji_events,
                    color: Colors.green,
                    size: 28,
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${(goal.progress * 100).round()}%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
  
  /// 构建空状态卡片
  Widget _buildEmptyCard(BuildContext context, ThemeScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.primaryColor.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.lightColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.flag_outlined,
              color: scheme.primaryColor.withValues(alpha: 0.5),
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '设置本月目标',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.textDarkColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '设定目标，记录成长',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.textMediumColor,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onTapSettings,
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('设置'),
          ),
        ],
      ),
    );
  }
}

/// 目标设置弹窗
class GoalSettingSheet extends StatefulWidget {
  final MonthlyGoal? currentGoal;
  
  const GoalSettingSheet({super.key, this.currentGoal});
  
  @override
  State<GoalSettingSheet> createState() => _GoalSettingSheetState();
}

class _GoalSettingSheetState extends State<GoalSettingSheet> {
  late GoalType _selectedType;
  late int _selectedTarget;
  late TextEditingController _customTargetController;
  bool _isCustomTarget = false;
  
  @override
  void initState() {
    super.initState();
    _selectedType = widget.currentGoal?.type ?? GoalType.diaryCount;
    _selectedTarget = widget.currentGoal?.targetCount ?? 12;
    _customTargetController = TextEditingController(text: _selectedTarget.toString());
    
    // 检查是否是自定义值（不在预设中）
    final presets = GoalPreset.getPresets(_selectedType);
    _isCustomTarget = !presets.any((p) => p.target == _selectedTarget);
  }
  
  @override
  void dispose() {
    _customTargetController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final presets = GoalPreset.getPresets(_selectedType);
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
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
            
            // 目标类型选择
            Text(
              '目标类型',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.textDarkColor,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: GoalType.values.map((type) {
                final isSelected = _selectedType == type;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        type.icon,
                        size: 16,
                        color: isSelected ? Colors.white : scheme.textMediumColor,
                      ),
                      const SizedBox(width: 6),
                      Text(type.displayName),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedType = type;
                        _selectedTarget = GoalPreset.getPresets(type)[1].target;
                      });
                    }
                  },
                  selectedColor: scheme.primaryColor,
                  backgroundColor: scheme.cardColor,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : scheme.textDarkColor,
                    fontSize: 13,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            
            // 目标数量选择
            Text(
              '目标数量',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.textDarkColor,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ...presets.map((preset) {
                  final isSelected = !_isCustomTarget && _selectedTarget == preset.target;
                  return ChoiceChip(
                    label: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${preset.target}${_selectedType.unit}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          preset.description,
                          style: TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _isCustomTarget = false;
                          _selectedTarget = preset.target;
                          _customTargetController.text = preset.target.toString();
                        });
                      }
                    },
                    selectedColor: scheme.primaryColor.withValues(alpha: 0.15),
                    backgroundColor: scheme.cardColor,
                    labelStyle: TextStyle(
                      color: isSelected ? scheme.primaryColor : scheme.textDarkColor,
                      fontSize: 13,
                    ),
                    side: BorderSide(
                      color: isSelected ? scheme.primaryColor : Colors.transparent,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  );
                }),
                // 自定义选项
                ChoiceChip(
                  label: Text('自定义'),
                  selected: _isCustomTarget,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _isCustomTarget = true);
                    }
                  },
                  selectedColor: scheme.primaryColor.withValues(alpha: 0.15),
                  backgroundColor: scheme.cardColor,
                  labelStyle: TextStyle(
                    color: _isCustomTarget ? scheme.primaryColor : scheme.textDarkColor,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: _isCustomTarget ? scheme.primaryColor : Colors.transparent,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ],
            ),
            // 自定义输入框
            if (_isCustomTarget) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customTargetController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: '输入目标数量',
                          hintStyle: TextStyle(
                            color: scheme.textLightColor,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scheme.textDarkColor,
                        ),
                        onChanged: (value) {
                          final number = int.tryParse(value);
                          if (number != null && number > 0 && number <= 999) {
                            setState(() => _selectedTarget = number);
                          }
                        },
                      ),
                    ),
                    Text(
                      _selectedType.unit,
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.textMediumColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
            
            // 保存按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  context.read<GoalProvider>().setGoal(
                    targetCount: _selectedTarget,
                    type: _selectedType,
                  );
                  Navigator.pop(context);
                },
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
    );
  }
}

/// 目标达成庆祝动画
class GoalCelebration extends StatefulWidget {
  final MonthlyGoal goal;
  final VoidCallback onComplete;
  
  const GoalCelebration({
    super.key,
    required this.goal,
    required this.onComplete,
  });
  
  @override
  State<GoalCelebration> createState() => _GoalCelebrationState();
}

class _GoalCelebrationState extends State<GoalCelebration>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  
  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    _scaleController.forward().then((_) {
      Future.delayed(const Duration(seconds: 2), () {
        _fadeController.forward().then((_) {
          widget.onComplete();
        });
      });
    });
  }
  
  @override
  void dispose() {
    _scaleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0).animate(_fadeController),
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.5, end: 1).animate(
              CurvedAnimation(
                parent: _scaleController,
                curve: Curves.elasticOut,
              ),
            ),
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🎉',
                    style: TextStyle(fontSize: 64),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '目标达成！',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '本月${widget.goal.type.displayName}目标已完成',
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.textMediumColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.goal.completedCount}/${widget.goal.targetCount}${widget.goal.type.unit}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
