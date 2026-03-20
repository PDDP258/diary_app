import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../services/gacha_service.dart';
import '../services/icon_theme_service.dart';
import '../widgets/sound_button.dart';
import 'main_screen.dart';

/// 图标主题选择页面
///
/// 「笔迹·成长」图标换色功能
/// 4种配色：珊瑚红/青绿色/樱花粉（默认解锁）+ 星空主题（商店购买解锁）
class IconThemeScreen extends StatefulWidget {
  const IconThemeScreen({super.key});

  @override
  State<IconThemeScreen> createState() => _IconThemeScreenState();
}

class _IconThemeScreenState extends State<IconThemeScreen> {
  String _currentTheme = 'coral';
  bool _isLoading = true;
  bool _isSupported = true;
  bool _isStarryUnlocked = false;
  bool _isPinkUnlocked = false;
  bool _isMintUnlocked = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _isSupported = IconThemeService.isSupported;
    if (_isSupported) {
      final theme = await IconThemeService.getCurrentTheme();
      final starryUnlocked = await IconThemeService.isStarryThemeUnlocked();
      final pinkUnlocked = await IconThemeService.isPinkThemeUnlocked();
      final mintUnlocked = await IconThemeService.isMintThemeUnlocked();
      setState(() {
        _currentTheme = theme;
        _isStarryUnlocked = starryUnlocked;
        _isPinkUnlocked = pinkUnlocked;
        _isMintUnlocked = mintUnlocked;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _setTheme(String themeName) async {
    // 检查星空主题是否锁定
    if (themeName == 'starry' && !_isStarryUnlocked) {
      _showUnlockDialog('星空主题');
      return;
    }

    // 检查樱花粉主题是否锁定
    if (themeName == 'pink' && !_isPinkUnlocked) {
      _showUnlockDialog('樱花主题');
      return;
    }

    // 检查青绿色主题是否锁定
    if (themeName == 'mint' && !_isMintUnlocked) {
      _showUnlockDialog('极光主题');
      return;
    }

    if (themeName == _currentTheme) return;

    final success = await IconThemeService.setIconTheme(themeName);

    if (success) {
      setState(() {
        _currentTheme = themeName;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('桌面图标已更换为「${IconThemeService.getThemeName(themeName)}」'),
            duration: const Duration(seconds: 2),
          ),
        );
        // 图标主题切换后跳转到日记页
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const MainScreen(initialIndex: 0),
          ),
          (route) => false,
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('图标更换失败，请稍后重试'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showUnlockDialog(String themeName) {
    final scheme = AppTheme.schemeOf(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.cardColor,
        title: Text(
          '解锁$themeName',
          style: TextStyle(color: scheme.textDarkColor),
        ),
        content: Text(
          '$themeName需要在扭蛋商店中购买解锁。前往商店兑换？',
          style: TextStyle(color: scheme.textMediumColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: scheme.textMediumColor)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // 跳转到扭蛋商店
              Navigator.pushNamed(context, '/gacha');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.primaryColor,
            ),
            child: const Text('前往商店'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.backgroundColor,
        elevation: 0,
        leading: SoundButton(
          onPressed: () => Navigator.pop(context),
          child: Icon(Icons.arrow_back, color: scheme.textDarkColor),
        ),
        title: Text(
          '桌面图标',
          style: TextStyle(
            color: scheme.textDarkColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: scheme.primaryColor,
              ),
            )
          : !_isSupported
              ? _buildUnsupportedView(scheme)
              : _buildThemeGrid(scheme),
    );
  }

  Widget _buildUnsupportedView(ThemeScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            size: 64,
            color: scheme.textMediumColor,
          ),
          const SizedBox(height: 16),
          Text(
            '此功能仅在 Android 设备上可用',
            style: TextStyle(
              color: scheme.textDarkColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeGrid(ThemeScheme scheme) {
    final themes = IconThemeService.themeMap;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 说明文字
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.palette_outlined,
                  color: scheme.primaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '选择你喜欢的图标颜色，更换手机桌面上「小记日记」的图标外观。更换可能需要几秒生效。',
                    style: TextStyle(
                      color: scheme.textDarkColor,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 图标预览
          Text(
            '图标预览',
            style: TextStyle(
              color: scheme.textDarkColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          Center(
            child: _buildIconPreview(scheme, _currentTheme),
          ),
          const SizedBox(height: 32),

          // 主题选择
          Text(
            '选择主题',
            style: TextStyle(
              color: scheme.textDarkColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          ...themes.entries.map((entry) {
            final key = entry.key;
            final data = entry.value;
            final isSelected = key == _currentTheme;
            final color = Color(data['color'] as int);
            final isLocked = (data['locked'] == true &&
                ((key == 'starry' && !_isStarryUnlocked) ||
                    (key == 'pink' && !_isPinkUnlocked) ||
                    (key == 'mint' && !_isMintUnlocked)));

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SoundButton(
                onPressed: () => _setTheme(key),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        isSelected ? color.withOpacity(0.15) : scheme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? color : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // 颜色圆点
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isLocked ? Colors.grey[400] : color,
                          shape: BoxShape.circle,
                          boxShadow: isLocked
                              ? []
                              : [
                                  BoxShadow(
                                    color: color.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                        ),
                        child: Center(
                          child: isLocked
                              ? Icon(Icons.lock,
                                  color: Colors.white.withOpacity(0.7))
                              : Text(
                                  data['emoji'] as String,
                                  style: const TextStyle(fontSize: 24),
                                ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // 文字信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  data['name'] as String,
                                  style: TextStyle(
                                    color: isLocked
                                        ? scheme.textMediumColor
                                        : scheme.textDarkColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (isLocked) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '未解锁',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data['description'] as String,
                              style: TextStyle(
                                color: scheme.textMediumColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 选中标记
                      if (isSelected)
                        Icon(
                          Icons.check_circle,
                          color: color,
                          size: 28,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildIconPreview(ThemeScheme scheme, String themeKey) {
    final color = Color(IconThemeService.getThemeColor(themeKey));
    final isStarry = themeKey == 'starry';

    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 「笔迹·成长」图标预览
            Stack(
              alignment: Alignment.center,
              children: [
                // 螺旋轨迹示意
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withOpacity(0.6),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                // 笔尖
                Positioned(
                  left: 20,
                  top: 25,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.rectangle,
                    ),
                    transform: Matrix4.rotationZ(0.785398),
                  ),
                ),
                // 星星 - 星空主题显示红色星星，其他显示白色
                Positioned(
                  right: 18,
                  top: 18,
                  child: Icon(
                    Icons.star,
                    color: isStarry
                        ? const Color(0xFFFF6B6B).withOpacity(0.9) // 红色星星
                        : Colors.white.withOpacity(0.9),
                    size: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
