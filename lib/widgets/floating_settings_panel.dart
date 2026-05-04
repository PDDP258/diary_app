import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/floating_settings_service.dart';

/// 浮窗设置面板（两页）
///
/// 第一页：功能设置
/// 第二页：浮窗外观设置
class FloatingSettingsPanel extends StatefulWidget {
  final FloatingSettings initialSettings;
  final ValueChanged<FloatingSettings> onSettingsChanged;

  const FloatingSettingsPanel({
    super.key,
    required this.initialSettings,
    required this.onSettingsChanged,
  });

  @override
  State<FloatingSettingsPanel> createState() => _FloatingSettingsPanelState();
}

class _FloatingSettingsPanelState extends State<FloatingSettingsPanel> {
  late FloatingSettings _settings;
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  Future<void> _updateSettings(FloatingSettings newSettings) async {
    setState(() => _settings = newSettings);
    await FloatingSettingsService.save(newSettings);
    widget.onSettingsChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: scheme.surface.withValues(alpha: 0.98),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 320,
        height: 480,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题 + 分页指示器
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PageIndicator(
                  label: '功能',
                  isActive: _currentPage == 0,
                  onTap: () => _pageController.animateToPage(
                    0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  ),
                ),
                const SizedBox(width: 16),
                _PageIndicator(
                  label: '外观',
                  isActive: _currentPage == 1,
                  onTap: () => _pageController.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 分页内容
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildFunctionPage(),
                  _buildAppearancePage(),
                ],
              ),
            ),
            // 关闭按钮
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  // ========== 第一页：功能设置 ==========
  Widget _buildFunctionPage() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _SwitchTile(
          title: '使用标签',
          value: _settings.useTags,
          onChanged: (v) => _updateSettings(_settings.copyWith(useTags: v)),
        ),
        _SliderTile(
          title: '字体大小',
          value: _settings.fontSize,
          min: 12,
          max: 24,
          divisions: 12,
          label: '${_settings.fontSize.toInt()}',
          onChanged: (v) => _updateSettings(_settings.copyWith(fontSize: v)),
        ),
        _SwitchTile(
          title: '同步到通知',
          subtitle: '存储后更新通知栏内容',
          value: _settings.syncToNotification,
          onChanged: (v) => _updateSettings(_settings.copyWith(syncToNotification: v)),
        ),
        _SwitchTile(
          title: '字数统计',
          subtitle: '在速记条底部显示字数',
          value: _settings.showWordCount,
          onChanged: (v) => _updateSettings(_settings.copyWith(showWordCount: v)),
        ),
        _SwitchTile(
          title: '自动隐藏速记条',
          subtitle: '空内容时自动关闭',
          value: _settings.autoHideBar,
          onChanged: (v) => _updateSettings(_settings.copyWith(autoHideBar: v)),
        ),
        if (_settings.autoHideBar)
          _SliderTile(
            title: '自动隐藏延迟',
            value: _settings.autoHideDelaySeconds.toDouble(),
            min: 3,
            max: 30,
            divisions: 27,
            label: '${_settings.autoHideDelaySeconds}秒',
            onChanged: (v) => _updateSettings(
              _settings.copyWith(autoHideDelaySeconds: v.toInt()),
            ),
          ),
      ],
    );
  }

  // ========== 第二页：外观设置 ==========
  Widget _buildAppearancePage() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _SliderTile(
          title: '输入框透明度',
          value: _settings.inputOpacity,
          min: 0.3,
          max: 1.0,
          divisions: 14,
          label: '${(_settings.inputOpacity * 100).toInt()}%',
          onChanged: (v) => _updateSettings(_settings.copyWith(inputOpacity: v)),
        ),
        _SliderTile(
          title: '双击灵敏度',
          value: _settings.doubleTapSensitivityMs.toDouble(),
          min: 100,
          max: 800,
          divisions: 14,
          label: '${_settings.doubleTapSensitivityMs}ms',
          onChanged: (v) => _updateSettings(
            _settings.copyWith(doubleTapSensitivityMs: v.toInt()),
          ),
        ),
        _SwitchTile(
          title: '靠边自动隐藏',
          subtitle: '拖到边缘缩小为小线',
          value: _settings.autoHideToEdge,
          onChanged: (v) => _updateSettings(_settings.copyWith(autoHideToEdge: v)),
        ),
        // 悬浮窗大小选择
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('悬浮窗大小', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: FloatingWindowSize.values.map((size) {
                  final isSelected = _settings.windowSize == size;
                  final label = switch (size) {
                    FloatingWindowSize.small => '小',
                    FloatingWindowSize.medium => '中',
                    FloatingWindowSize.large => '大',
                  };
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        onSelected: (_) => _updateSettings(
                          _settings.copyWith(windowSize: size),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        // 自定义图标
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('自定义图标', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  // 图标预览
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _settings.iconColor.withValues(
                        alpha: _settings.iconOpacity,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _settings.iconEmoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 颜色选择
                  _ColorDot(
                    color: Colors.purple,
                    isSelected: _settings.iconColor == Colors.purple,
                    onTap: () => _updateSettings(
                      _settings.copyWith(iconColor: Colors.purple),
                    ),
                  ),
                  _ColorDot(
                    color: Colors.blue,
                    isSelected: _settings.iconColor == Colors.blue,
                    onTap: () => _updateSettings(
                      _settings.copyWith(iconColor: Colors.blue),
                    ),
                  ),
                  _ColorDot(
                    color: Colors.green,
                    isSelected: _settings.iconColor == Colors.green,
                    onTap: () => _updateSettings(
                      _settings.copyWith(iconColor: Colors.green),
                    ),
                  ),
                  _ColorDot(
                    color: Colors.orange,
                    isSelected: _settings.iconColor == Colors.orange,
                    onTap: () => _updateSettings(
                      _settings.copyWith(iconColor: Colors.orange),
                    ),
                  ),
                  _ColorDot(
                    color: Colors.pink,
                    isSelected: _settings.iconColor == Colors.pink,
                    onTap: () => _updateSettings(
                      _settings.copyWith(iconColor: Colors.pink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 图标透明度
              _SliderTile(
                title: '图标透明度',
                value: _settings.iconOpacity,
                min: 0.3,
                max: 1.0,
                divisions: 14,
                label: '${(_settings.iconOpacity * 100).toInt()}%',
                onChanged: (v) => _updateSettings(
                  _settings.copyWith(iconOpacity: v),
                ),
              ),
            ],
          ),
        ),
        // 还原默认
        ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('还原所有默认设置'),
          onTap: () {
            HapticFeedback.heavyImpact();
            _updateSettings(const FloatingSettings());
          },
        ),
      ],
    );
  }
}

// ========== 通用设置组件 ==========

class _PageIndicator extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _PageIndicator({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? scheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? scheme.primary : scheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(fontSize: 11))
          : null,
      value: value,
      onChanged: onChanged,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 14)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: Colors.white, width: 2)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
