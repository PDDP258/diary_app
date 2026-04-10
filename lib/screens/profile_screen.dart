import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../models/mood.dart';
import '../providers/diary_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';
import '../services/app_lock_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/badge_service.dart' as badge_service;
import '../services/database_service.dart';
import '../services/gacha_service.dart';
import '../services/icon_theme_service.dart';
import '../services/sound_service.dart';
import 'app_lock_screen.dart';
import 'backup_manager_screen.dart';
import 'badge_detail_screen.dart';
import 'custom_sticker_screen.dart';
import 'data_management_screen.dart';
import 'icon_theme_screen.dart';
import 'main_screen.dart';
import 'tag_management_screen_v3.dart';
import 'time_capsule_list_screen_v2.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<badge_service.Badge> _unlockedBadges = [];
  bool _hasNewBadge = false;
  bool _appLockEnabled = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  List<Mood> _moods = [];

  @override
  void initState() {
    super.initState();
    _loadBadges();
    _loadAppLockStatus();
    _loadBiometricStatus();
  }

  Future<void> _loadBadges() async {
    final badges = await badge_service.BadgeService.getUnlockedBadges();
    final hasNew = await badge_service.BadgeService.hasNewBadge();
    if (mounted) {
      setState(() {
        _unlockedBadges = badges;
        _hasNewBadge = hasNew;
      });
    }
    if (hasNew) {
      await badge_service.BadgeService.markNewBadgeShown();
    }
  }

  Future<void> _loadAppLockStatus() async {
    await AppLockService.initialize();
    if (mounted) {
      setState(() {
        _appLockEnabled = AppLockService.isEnabled;
      });
    }
  }

  Future<void> _loadBiometricStatus() async {
    await BiometricAuthService.initialize();
    final available = await BiometricAuthService.hasAvailableBiometrics();
    if (mounted) {
      setState(() {
        _biometricEnabled = BiometricAuthService.isEnabled;
        _biometricAvailable = available;
      });
    }
  }

  Future<void> _loadMoods() async {
    final moods = await DatabaseService.getAllMoods();
    if (mounted) {
      setState(() {
        _moods = moods;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 24),
              child: Text(
                '我的',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: scheme.textDarkColor,
                ),
              ),
            ),

            // 用户卡片
            Consumer<SettingsProvider>(
              builder: (context, settings, child) {
                return GestureDetector(
                  onTap: () => _showUserEditDialog(context, scheme),
                  child: _buildUserCard(settings, scheme),
                );
              },
            ),

            const SizedBox(height: 24),

            // 徽章展示区域
            _buildBadgeSection(scheme),

            const SizedBox(height: 24),

            // 数据管理
            _buildMenuGroup([
              _MenuItem(
                icon: Icons.storage_outlined,
                title: '数据管理',
                onTap: () => _navigateTo(const DataManagementScreen()),
              ),
            ], scheme),

            const SizedBox(height: 16),

            // 主题配色
            _buildMenuGroup([
              _MenuItem(
                icon: Icons.palette_outlined,
                title: '主题配色',
                subtitle: '切换整个应用的配色风格',
                onTap: () => _showThemePicker(context),
              ),
            ], scheme),

            // 桌面图标（Android专属）
            if (isAndroid) ...[
              const SizedBox(height: 16),
              _buildMenuGroup([
                _MenuItem(
                  icon: Icons.app_shortcut_outlined,
                  title: '桌面图标',
                  subtitle: '更换手机桌面上的应用图标颜色',
                  onTap: () => _navigateTo(const IconThemeScreen()),
                ),
              ], scheme),
            ],

            const SizedBox(height: 16),

            // 应用锁
            _buildMenuGroup([
              _MenuItem(
                icon: Icons.lock_outline,
                title: '应用锁',
                subtitle: _appLockEnabled ? '已启用' : '未启用',
                trailing: _buildAppLockToggle(),
                onTap: () => _toggleAppLock(),
              ),
              // 指纹验证开关（仅在应用锁开启且设备支持时显示）
              if (_appLockEnabled && _biometricAvailable)
                _MenuItem(
                  icon: Icons.fingerprint,
                  title: '指纹验证',
                  subtitle: _biometricEnabled ? '已开启' : '已关闭',
                  trailing: _buildBiometricToggle(),
                  onTap: () => _toggleBiometric(),
                ),
            ], scheme),

            const SizedBox(height: 16),

            // 时间胶囊
            _buildMenuGroup([
              _MenuItem(
                icon: Icons.mark_email_unread_outlined,
                title: '时间胶囊',
                subtitle: '给未来的自己写一封信',
                onTap: () => _navigateTo(const TimeCapsuleListScreen()),
              ),
            ], scheme),

            const SizedBox(height: 16),

            // 个性化设置
            _buildMenuGroup([
              _MenuItem(
                icon: Icons.sentiment_satisfied_outlined,
                title: '心情管理',
                onTap: () => _showMoodManager(context),
              ),
              _MenuItem(
                icon: Icons.label_outlined,
                title: '标签管理',
                onTap: () => _navigateTo(const TagManagementScreenV3()),
              ),
              _MenuItem(
                icon: Icons.photo_library_outlined,
                title: '自定义贴纸',
                subtitle: '添加图片到日记和日历页面',
                onTap: () => _navigateTo(const CustomStickerScreen()),
              ),
            ], scheme),

            const SizedBox(height: 16),

            // 关于 - 彩蛋
            _buildMenuGroup([
              _MenuItem(
                icon: Icons.info_outline,
                title: '关于日记',
                subtitle: '版本 1.1.5',
                onTap: () => _showAboutWithEasterEgg(context),
              ),
              _MenuItem(
                icon: Icons.copyright,
                title: '版权信息',
                subtitle: '查看使用声明',
                onTap: () => _showCopyrightInfo(context),
              ),
            ], scheme),
          ],
        ),
      ),
    );
  }

  // 构建徽章展示区域
  Widget _buildBadgeSection(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primaryColor, scheme.darkColor],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '我的徽章',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.textDarkColor,
                ),
              ),
              const Spacer(),
              // 徽章数量
              GestureDetector(
                onTap: () => _showAllBadges(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _hasNewBadge
                        ? Colors.red.withValues(alpha: 0.1)
                        : scheme.lightColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: _hasNewBadge
                        ? Border.all(color: Colors.red.withValues(alpha: 0.3))
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_hasNewBadge)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      Text(
                        '${_unlockedBadges.length}/${badge_service.BadgeService.allBadges.length}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color:
                              _hasNewBadge ? Colors.red : scheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 徽章列表
          if (_unlockedBadges.isEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: scheme.lightColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 48,
                      color: scheme.textLightColor.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '还没有徽章',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.textMediumColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '写日记解锁徽章吧',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.textLightColor,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _unlockedBadges.take(10).map((badge) {
                return _buildBadgeItem(badge);
              }).toList(),
            ),

          // 查看更多按钮
          if (_unlockedBadges.length > 10) ...[
            const SizedBox(height: 16),
            Center(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextButton(
                  onPressed: () => _showAllBadges(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: Text(
                    '查看全部 ${_unlockedBadges.length} 个',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.primaryColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadgeItem(badge_service.Badge badge) {
    return GestureDetector(
      onTap: () => _navigateToBadgeDetail(badge),
      child: Tooltip(
        message: '${badge.name}\n${badge.description}',
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                badge.color.withValues(alpha: 0.8),
                badge.color.withValues(alpha: 0.4),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: badge.color.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Text(
              badge.emoji,
              style: const TextStyle(fontSize: 26),
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToBadgeDetail(badge_service.Badge badge) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BadgeDetailScreen(
          badge: badge,
          isUnlocked: true,
        ),
      ),
    );
  }

  /// 展示所有徽章
  void _showAllBadges(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    final allBadges = badge_service.BadgeService.allBadges;
    final unlockedIds = _unlockedBadges.map((b) => b.id).toSet();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: scheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.lightColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    '徽章收藏 (${_unlockedBadges.length}/${allBadges.length})',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: allBadges.length,
                itemBuilder: (context, index) {
                  final badge = allBadges[index];
                  final isUnlocked = unlockedIds.contains(badge.id);
                  return _buildBadgeGridItem(badge, isUnlocked, scheme);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeGridItem(
      badge_service.Badge badge, bool isUnlocked, ThemeScheme scheme) {
    return GestureDetector(
      onTap: isUnlocked
          ? () {
              Navigator.pop(context);
              _navigateToBadgeDetail(badge);
            }
          : null,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: isUnlocked
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        badge.color.withValues(alpha: 0.8),
                        badge.color.withValues(alpha: 0.4),
                      ],
                    )
                  : null,
              color:
                  isUnlocked ? null : scheme.lightColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
              boxShadow: isUnlocked
                  ? [
                      BoxShadow(
                        color: badge.color.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                isUnlocked ? badge.emoji : '?',
                style: TextStyle(
                  fontSize: 28,
                  color: isUnlocked ? null : scheme.textLightColor,
                ),
              ),
            ),
          ),
          if (isUnlocked) ...[
            const SizedBox(height: 6),
            Text(
              badge.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: scheme.textDarkColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUserCard(SettingsProvider settings, ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryColor,
            scheme.darkColor,
            scheme.primaryColor.withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.6, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.primaryColor.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Row(
        children: [
          // 头像/表情/自定义图片
          GestureDetector(
            onTap: () => _showAvatarOptions(context, settings),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: settings.customAvatarPath != null
                    ? Image.file(
                        File(settings.customAvatarPath!),
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Text(
                              settings.userEmoji,
                              style: const TextStyle(
                                fontSize: 36,
                                shadows: [
                                  Shadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : Center(
                        child: Text(
                          settings.userEmoji,
                          style: const TextStyle(
                            fontSize: 36,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          // 用户信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.userName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    settings.userSignature != 'PD inc'
                        ? settings.userSignature
                        : '点击编辑个人信息',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // 编辑图标
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.edit_rounded,
              color: Colors.white.withValues(alpha: 0.9),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  /// 显示头像选项（自定义图片或表情）
  void _showAvatarOptions(BuildContext context, SettingsProvider settings) {
    final scheme = AppTheme.schemeOf(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.lightColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('从相册选择'),
                subtitle: const Text('使用自定义图片作为头像'),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final pickedFile = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 300,
                    maxHeight: 300,
                    imageQuality: 85,
                  );
                  if (pickedFile != null) {
                    await settings.setCustomAvatar(pickedFile.path);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('头像已更新')),
                      );
                    }
                  }
                },
              ),
              if (settings.customAvatarPath != null)
                ListTile(
                  leading: const Icon(Icons.emoji_emotions),
                  title: const Text('恢复默认表情'),
                  subtitle: const Text('使用表情作为头像'),
                  onTap: () async {
                    Navigator.pop(context);
                    await settings.clearCustomAvatar();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已恢复默认表情头像')),
                      );
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑个人信息'),
                onTap: () {
                  Navigator.pop(context);
                  _showUserEditDialog(context, scheme);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showUserEditDialog(BuildContext context, ThemeScheme scheme) {
    final settings = context.read<SettingsProvider>();
    final nameController = TextEditingController(text: settings.userName);
    final signatureController = TextEditingController(
      text: settings.userSignature != 'PD inc' ? settings.userSignature : '',
    );
    String selectedEmoji = settings.userEmoji;

    // 基础头像 + 扭蛋解锁的头像
    final baseEmojis = [
      '👋',
      '😊',
      '🌟',
      '📝',
      '🌈',
      '🎯',
      '💪',
      '🌻',
      '🎨',
      '🌸'
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: scheme.cardColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 头部把手
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.lightColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '编辑个人信息',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 表情选择
                  Text(
                    '选择头像',
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.textMediumColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 头像选择 - 包含基础头像和解锁头像
                  FutureBuilder<List<GachaReward>>(
                    future: GachaService.getUnlockedAvatars(),
                    builder: (context, snapshot) {
                      final unlockedAvatars = snapshot.data ?? [];
                      // 合并基础头像和解锁头像
                      final allEmojis = <String, dynamic>{};
                      // 添加基础头像
                      for (final emoji in baseEmojis) {
                        allEmojis[emoji] = {'type': 'emoji', 'value': emoji};
                      }
                      // 添加解锁的头像
                      for (final avatar in unlockedAvatars) {
                        allEmojis[avatar.emoji] = {
                          'type': 'avatar',
                          'value': avatar.emoji,
                          'name': avatar.name,
                        };
                      }

                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          // 表情头像
                          ...allEmojis.entries.map((entry) {
                            final emoji = entry.key;
                            final data = entry.value;
                            final isSelected = emoji == selectedEmoji;
                            final isAvatar = data['type'] == 'avatar';

                            return GestureDetector(
                              onTap: () {
                                setState(() => selectedEmoji = emoji);
                              },
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? scheme.primaryColor
                                          .withValues(alpha: 0.2)
                                      : isAvatar
                                          ? Colors.amber.withValues(alpha: 0.15)
                                          : scheme.lightColor
                                              .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(24),
                                  border: isSelected
                                      ? Border.all(
                                          color: scheme.primaryColor, width: 2)
                                      : isAvatar
                                          ? Border.all(
                                              color: Colors.amber
                                                  .withValues(alpha: 0.5),
                                              width: 1)
                                          : null,
                                ),
                                child: Center(
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ),
                              ),
                            );
                          }),
                          // 从相册选择按钮
                          GestureDetector(
                            onTap: () async {
                              Navigator.pop(context);
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 300,
                                maxHeight: 300,
                                imageQuality: 85,
                              );
                              if (pickedFile != null) {
                                await settings.setCustomAvatar(pickedFile.path);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('头像已更新')),
                                  );
                                }
                              }
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: scheme.lightColor.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: scheme.primaryColor
                                      .withValues(alpha: 0.3),
                                  width: 1,
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.add_photo_alternate_outlined,
                                  color: scheme.primaryColor,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  // 名字输入框
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: '昵称',
                      hintText: '输入你的昵称',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 签名输入框
                  TextField(
                    controller: signatureController,
                    decoration: InputDecoration(
                      labelText: '签名（显示在启动页）',
                      hintText: '输入启动页显示的签名',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 保存按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final signature = signatureController.text.trim();
                        settings.setUserInfo(
                          name: nameController.text.trim(),
                          emoji: selectedEmoji,
                          signature:
                              signature.isNotEmpty ? signature : 'PD inc',
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
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _navigateTo(Widget screen) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
    // 如果从数据管理页面返回且数据有更改，刷新日记数据
    if (result == true && screen is DataManagementScreen) {
      if (mounted) {
        context.read<DiaryProvider>().loadDiaries();
      }
    }
  }

  // 应用锁开关
  Widget _buildAppLockToggle() {
    return GestureDetector(
      onTap: () => _toggleAppLock(),
      child: Container(
        width: 48,
        height: 28,
        decoration: BoxDecoration(
          color: _appLockEnabled
              ? Colors.black
              : Colors.grey.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(2),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment:
              _appLockEnabled ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggleAppLock() async {
    if (_appLockEnabled) {
      // 关闭应用锁
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('关闭应用锁'),
          content: const Text('关闭后打开应用将不再需要验证密码，确定要关闭吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await AppLockService.disable();
        setState(() {
          _appLockEnabled = false;
        });
      }
    } else {
      // 开启应用锁 - 导航到设置页面
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const AppLockScreen(isSetup: true),
        ),
      ).then((_) {
        _loadAppLockStatus();
      });
    }
  }

  // 指纹开关
  Widget _buildBiometricToggle() {
    return GestureDetector(
      onTap: () => _toggleBiometric(),
      child: Container(
        width: 48,
        height: 28,
        decoration: BoxDecoration(
          color: _biometricEnabled
              ? Colors.black
              : Colors.grey.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(2),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment:
              _biometricEnabled ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggleBiometric() async {
    if (_biometricEnabled) {
      // 关闭指纹验证
      await BiometricAuthService.disable();
      setState(() {
        _biometricEnabled = false;
      });
    } else {
      // 开启指纹验证 - 先测试指纹是否可用
      final success = await BiometricAuthService.enable();
      if (success) {
        setState(() {
          _biometricEnabled = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('指纹验证已开启')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('指纹验证开启失败，请确认已录入指纹')),
          );
        }
      }
    }
  }

  // 主题选择弹窗
  void _showThemePicker(BuildContext context) async {
    final themeProvider = context.read<ThemeProvider>();
    final scheme = AppTheme.schemeOf(context);
    final presetSchemes = ThemeProvider.presetSchemes;

    // 获取已解锁的主题
    final prefs = await SharedPreferences.getInstance();
    final unlockedThemeIds = prefs.getStringList('unlocked_themes') ?? [];

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.lightColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '选择主题',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 预设主题（3x3网格）
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: presetSchemes.map((colorScheme) {
                      final isSelected =
                          themeProvider.currentScheme.primaryColor.value ==
                              colorScheme.primaryColor.value;
                      return GestureDetector(
                        onTap: () async {
                          await themeProvider.setThemeScheme(colorScheme);
                          if (context.mounted) {
                            Navigator.pop(context);
                            // 跳转到日历页
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (context) =>
                                    const MainScreen(initialIndex: 0),
                              ),
                              (route) => false,
                            );
                          }
                        },
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryColor,
                            borderRadius: BorderRadius.circular(28),
                            border: isSelected
                                ? Border.all(color: Colors.white, width: 3)
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.primaryColor
                                    .withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  // 已解锁的商店主题
                  if (unlockedThemeIds.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text(
                          '🎨 已解锁的特殊主题',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: scheme.textMediumColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: unlockedThemeIds.map((themeId) {
                        final themeColors =
                            GachaService.getThemeColors(themeId);
                        if (themeColors == null) return const SizedBox.shrink();

                        final primaryColor =
                            Color(themeColors['primary'] as int);
                        final isSelected =
                            themeProvider.currentScheme.primaryColor.value ==
                                primaryColor.value;
                        final themeName = GachaService.profileThemeShop[themeId]
                                ?['name'] ??
                            '特殊主题';

                        return GestureDetector(
                          onTap: () async {
                            final newScheme = ThemeScheme(
                              primaryColor: primaryColor,
                              backgroundColor:
                                  Color(themeColors['background'] as int),
                              cardColor: themeColors['card'] != null
                                  ? Color(themeColors['card'] as int)
                                  : Colors.white,
                              lightColor: Color(themeColors['light'] as int),
                              darkColor: Color(themeColors['dark'] as int),
                              textDarkColor:
                                  Color(themeColors['textDark'] as int),
                              textMediumColor:
                                  Color(themeColors['textMedium'] as int),
                              textLightColor:
                                  Color(themeColors['textLight'] as int),
                              name: themeName,
                            );
                            await themeProvider.setThemeScheme(newScheme);
                            if (context.mounted) {
                              Navigator.pop(context);
                              // 跳转到日历页
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const MainScreen(initialIndex: 0),
                                ),
                                (route) => false,
                              );
                            }
                          },
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: primaryColor,
                                  borderRadius: BorderRadius.circular(28),
                                  border: isSelected
                                      ? Border.all(
                                          color: Colors.amber, width: 3)
                                      : null,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          primaryColor.withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check,
                                        color: Colors.white)
                                    : Center(
                                        child: Text(
                                          GachaService.profileThemeShop[themeId]
                                                  ?['preview'] ??
                                              '🎨',
                                          style: const TextStyle(fontSize: 24),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                themeName,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.textMediumColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // 自定义颜色
                  ListTile(
                    leading:
                        Icon(Icons.colorize, color: scheme.textMediumColor),
                    title: Text(
                      '自定义颜色',
                      style: TextStyle(color: scheme.textDarkColor),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _showCustomColorPicker(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomColorPicker(BuildContext context) {
    final themeProvider = context.read<ThemeProvider>();
    final scheme = AppTheme.schemeOf(context);
    Color pickerColor = themeProvider.currentScheme.primaryColor;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择自定义颜色'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ColorPicker(
                pickerColor: pickerColor,
                onColorChanged: (color) {
                  pickerColor = color;
                },
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '提示：请勿设置过于黑暗的颜色，可能会导致部分文字无法阅读',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await themeProvider.setPrimaryColor(pickerColor);
              if (context.mounted) {
                Navigator.pop(context);
                // 跳转到日历页
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const MainScreen(initialIndex: 0),
                  ),
                  (route) => false,
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // 心情管理弹窗
  void _showMoodManager(BuildContext context) async {
    await _loadMoods();
    if (!mounted) return;

    final scheme = AppTheme.schemeOf(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.6,
            decoration: BoxDecoration(
              color: scheme.cardColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.lightColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 标题栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '心情管理',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: scheme.textDarkColor,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showAddMoodDialog(context, scheme, () {
                          _loadMoods().then((_) {
                            setState(() {});
                          });
                        }),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add,
                                color: scheme.primaryColor, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              '添加',
                              style: TextStyle(
                                fontSize: 14,
                                color: scheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // 心情列表
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _moods.length,
                    itemBuilder: (context, index) {
                      final mood = _moods[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Text(
                          mood.emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                        title: Text(
                          mood.name,
                          style: TextStyle(
                            fontSize: 16,
                            color: scheme.textDarkColor,
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: Colors.red.withValues(alpha: 0.6),
                            size: 22,
                          ),
                          onPressed: () => _deleteMood(mood, () {
                            _loadMoods().then((_) {
                              setState(() {});
                            });
                          }),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddMoodDialog(
      BuildContext context, ThemeScheme scheme, VoidCallback onAdded) {
    final emojiController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加心情'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emojiController,
              decoration: const InputDecoration(
                labelText: '表情',
                hintText: '例如：😊',
              ),
              maxLength: 2,
            ),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：开心',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final emoji = emojiController.text.trim();
              final name = nameController.text.trim();
              if (emoji.isNotEmpty && name.isNotEmpty) {
                final mood = Mood(
                  name: name,
                  emoji: emoji,
                  color:
                      '#${scheme.primaryColor.value.toRadixString(16).substring(2)}',
                  sortOrder: _moods.length,
                );
                await DatabaseService.insertMood(mood);
                Navigator.pop(context);
                onAdded();
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _deleteMood(Mood mood, VoidCallback onDeleted) async {
    if (mood.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除心情'),
        content: Text('确定要删除"${mood.name}"吗？使用该心情的日记将保留，但不再显示心情图标。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseService.deleteMood(mood.id!);
      onDeleted();
    }
  }

  // 关于日记 - 带彩蛋
  void _showAboutWithEasterEgg(BuildContext context) {
    _AboutEasterEgg.show(context);
  }

  // 版权信息
  void _showCopyrightInfo(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: scheme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.lightColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 应用图标
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: scheme.primaryColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.book,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '小记日记',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: scheme.textDarkColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '版本 1.1.5',
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.textLightColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    // 版权声明
                    Text(
                      '版权声明',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: scheme.textDarkColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '© 2024-2026 PDDP\n保留所有权利',
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.textMediumColor,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 使用声明
                    Text(
                      '使用声明',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: scheme.textDarkColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 允许和禁止放在同一行
                    Row(
                      children: [
                        // 允许使用
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLicenseItem('✓ 个人免费使用'),
                                _buildLicenseItem('✓ 任意设备使用'),
                                _buildLicenseItem('✓ 数据备份导出'),
                                _buildLicenseItem('✓ 分享给朋友'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 禁止使用
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLicenseItem('✗ 禁止修改软件'),
                                _buildLicenseItem('✗ 禁止重新分发'),
                                _buildLicenseItem('✗ 禁止商业使用'),
                                _buildLicenseItem('✗ 禁止去除版权'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 免责声明
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        '本软件按"现状"提供，作者不对使用本软件造成的任何损失承担责任。',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.textMediumColor,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            // 底部按钮
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  '确定',
                  style: TextStyle(
                    fontSize: 16,
                    color: scheme.primaryColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLicenseItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildMenuGroup(List<_MenuItem> items, ThemeScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return Column(
            children: [
              if (index > 0)
                Divider(
                  height: 1,
                  indent: 76,
                  endIndent: 20,
                  color: scheme.lightColor.withValues(alpha: 0.3),
                ),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.lightColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    item.icon,
                    color: scheme.textMediumColor,
                    size: 22,
                  ),
                ),
                title: Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.textDarkColor,
                  ),
                ),
                subtitle: item.subtitle != null
                    ? Text(
                        item.subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.textLightColor,
                        ),
                      )
                    : null,
                trailing: item.trailing ??
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.lightColor.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.chevron_right,
                        color: scheme.textLightColor,
                        size: 20,
                      ),
                    ),
                onTap: () {
                  SoundService.playClick();
                  item.onTap();
                },
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// 菜单项
class _MenuItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });
}

// 关于页面彩蛋
class _AboutEasterEgg {
  static int _titleTapCount = 0;
  static DateTime? _lastTitleTap;

  static void show(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    _titleTapCount = 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: scheme.cardColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.lightColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // 应用图标和名称（可双击触发彩蛋）
                        GestureDetector(
                          onDoubleTap: () => _triggerEasterEgg(context),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: scheme.lightColor.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.book,
                                  size: 48,
                                  color: scheme.primaryColor,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '小记日记',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.textDarkColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '版本 1.1.5',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: scheme.textLightColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // 版本更新
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '📋 版本更新',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: scheme.textDarkColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildVersionItem(
                          'v1.1.5',
                          '☁️ 云备份重构 + 🎨 UI优化',
                          [
                            '云备份按密钥分文件夹存储，支持多设备共存',
                            '新增云端备份扫描，可发现其他设备备份',
                            '支持从其他设备备份导入（合并不覆盖）',
                            '时间轴顶部卡片显示用户头像和签名',
                            '扭蛋入口缩小至80%，整体布局优化',
                          ],
                          scheme,
                        ),
                        const SizedBox(height: 16),
                        // 关于作者
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: scheme.lightColor.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '关于作者',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.primaryColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'PLLL工作室-PD',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.textDarkColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(const ClipboardData(
                                    text: '1638615339@qq.com',
                                  ));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('邮箱已复制')),
                                  );
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.email,
                                      size: 14,
                                      color: scheme.textMediumColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '1638615339@qq.com',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: scheme.textMediumColor,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.copy,
                                      size: 14,
                                      color: scheme.textLightColor,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '点击即可复制邮箱，欢迎提供意见！',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.textLightColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // 标语
                        Text(
                          '记录生活，珍藏回忆 💖',
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.textMediumColor,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // 调试入口（点击v字图标）
                        GestureDetector(
                          onTap: () => _showDebugDialog(context),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: scheme.lightColor.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              color: scheme.textLightColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 底部确定按钮
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      '确定',
                      style: TextStyle(
                        fontSize: 16,
                        color: scheme.primaryColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static Widget _buildVersionItem(
    String version,
    String title,
    List<String> changes,
    ThemeScheme scheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.lightColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  version,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: scheme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.textDarkColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...changes.map((change) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• $change',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.textMediumColor,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  // 触发彩蛋
  static void _triggerEasterEgg(BuildContext context) async {
    // 检查今天是否已经触发过
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastTrigger = prefs.getString('easter_egg_last_trigger');

    bool isFirstTime = lastTrigger != today;
    if (isFirstTime) {
      await prefs.setString('easter_egg_last_trigger', today);
      // 给予奖励
      await GachaService.addDraws(1);
    }

    if (!context.mounted) return;

    // 获取随机徽章tip
    final randomTip = badge_service.BadgeService.getRandomBadgeTip();

    // 显示彩蛋弹窗
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Row(
          children: [
            Icon(Icons.lock_open, color: Colors.amber),
            SizedBox(width: 8),
            Text(
              '发现秘密',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '🔐',
              style: TextStyle(fontSize: 48),
            ),
            const SizedBox(height: 16),
            const Text(
              '你发现了隐藏的秘密！',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            if (isFirstTime)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.card_giftcard, color: Colors.green, size: 18),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '今日首次发现秘密，获得1次额外扭蛋机会！',
                        style: TextStyle(color: Colors.green, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                randomTip,
                style: const TextStyle(color: Colors.amber, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  // 调试模式对话框
  static void _showDebugDialog(BuildContext context) {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('调试模式'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '输入密码',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              // 调试模式密码验证（两个密码都可用）
              final validPasswords = ['23258', '12345'];
              if (validPasswords.contains(passwordController.text)) {
                Navigator.pop(context);
                // 导航到调试页面
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DebugScreen(),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密码错误')),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 调试页面
class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '调试模式',
          style: TextStyle(color: scheme.textDarkColor),
        ),
        leading: IconButton(
          icon: Icon(Icons.close, color: scheme.textDarkColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 作弊功能
          _buildSectionTitle('作弊功能', scheme),
          const SizedBox(height: 12),
          _buildCard([
            ListTile(
              leading: Icon(Icons.palette, color: Colors.purple),
              title: Text('解锁所有特殊主题',
                  style: TextStyle(color: scheme.textDarkColor)),
              subtitle: Text('星空、樱花、海洋、极光、黄金主题',
                  style: TextStyle(color: scheme.textLightColor, fontSize: 12)),
              onTap: () => _unlockAllThemes(context),
            ),
            Divider(
                height: 1,
                indent: 56,
                color: scheme.lightColor.withValues(alpha: 0.3)),
            ListTile(
              leading: Icon(Icons.casino, color: Colors.orange),
              title: Text('获得99次扭蛋机会',
                  style: TextStyle(color: scheme.textDarkColor)),
              subtitle: Text('增加抽奖次数到99次',
                  style: TextStyle(color: scheme.textLightColor, fontSize: 12)),
              onTap: () => _addGachaDraws(context, 99),
            ),
            Divider(
                height: 1,
                indent: 56,
                color: scheme.lightColor.withValues(alpha: 0.3)),
            ListTile(
              leading: Icon(Icons.emoji_events, color: Colors.amber),
              title:
                  Text('解锁所有徽章', style: TextStyle(color: scheme.textDarkColor)),
              subtitle: Text('获得全部78个徽章',
                  style: TextStyle(color: scheme.textLightColor, fontSize: 12)),
              onTap: () => _unlockAllBadges(context),
            ),
          ], scheme),
          const SizedBox(height: 24),
          // 开发者信息
          _buildSectionTitle('开发者选项', scheme),
          const SizedBox(height: 12),
          _buildCard([
            ListTile(
              leading: Icon(Icons.bug_report, color: scheme.primaryColor),
              title:
                  Text('查看日志', style: TextStyle(color: scheme.textDarkColor)),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('日志功能开发中')),
                );
              },
            ),
            Divider(
                height: 1,
                indent: 56,
                color: scheme.lightColor.withValues(alpha: 0.3)),
            ListTile(
              leading: Icon(Icons.storage, color: scheme.primaryColor),
              title:
                  Text('查看数据库', style: TextStyle(color: scheme.textDarkColor)),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('数据库功能开发中')),
                );
              },
            ),
            Divider(
                height: 1,
                indent: 56,
                color: scheme.lightColor.withValues(alpha: 0.3)),
            ListTile(
              leading: Icon(Icons.reset_tv, color: scheme.primaryColor),
              title:
                  Text('重置引导页', style: TextStyle(color: scheme.textDarkColor)),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('has_seen_guide');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('引导页已重置')),
                  );
                }
              },
            ),
            Divider(
                height: 1,
                indent: 56,
                color: scheme.lightColor.withValues(alpha: 0.3)),
            ListTile(
              leading: Icon(Icons.delete_forever, color: Colors.red),
              title: Text('清除所有数据', style: TextStyle(color: Colors.red)),
              onTap: () => _showClearDataDialog(context),
            ),
          ], scheme),
          const SizedBox(height: 24),
          // 版本信息
          _buildSectionTitle('版本信息', scheme),
          const SizedBox(height: 12),
          _buildCard([
            ListTile(
              title: Text('版本号', style: TextStyle(color: scheme.textDarkColor)),
              trailing:
                  Text('1.1.5', style: TextStyle(color: scheme.textLightColor)),
            ),
            Divider(
                height: 1,
                indent: 16,
                color: scheme.lightColor.withValues(alpha: 0.3)),
            ListTile(
              title:
                  Text('构建时间', style: TextStyle(color: scheme.textDarkColor)),
              trailing: Text('2026-03-19',
                  style: TextStyle(color: scheme.textLightColor)),
            ),
          ], scheme),
        ],
      ),
    );
  }

  /// 解锁所有特殊主题
  Future<void> _unlockAllThemes(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 解锁所有特殊主题（使用正确的key）
      final themes = [
        'theme_starry',
        'theme_sakura',
        'theme_ocean',
        'theme_aurora',
        'theme_golden'
      ];

      // 获取已解锁主题列表
      final unlockedThemes = prefs.getStringList('unlocked_themes') ?? [];
      for (final themeId in themes) {
        if (!unlockedThemes.contains(themeId)) {
          unlockedThemes.add(themeId);
        }
      }
      await prefs.setStringList('unlocked_themes', unlockedThemes);

      // 同时解锁个人主页主题（使用相同的key）
      final profileThemes = [
        'theme_starry',
        'theme_sakura',
        'theme_ocean',
        'theme_aurora',
        'theme_golden'
      ];
      final unlockedProfileThemes =
          prefs.getStringList('unlocked_profile_themes') ?? [];
      for (final themeId in profileThemes) {
        if (!unlockedProfileThemes.contains(themeId)) {
          unlockedProfileThemes.add(themeId);
        }
      }
      await prefs.setStringList(
          'unlocked_profile_themes', unlockedProfileThemes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 已解锁所有特殊主题')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解锁失败: $e')),
        );
      }
    }
  }

  /// 添加扭蛋抽奖次数
  Future<void> _addGachaDraws(BuildContext context, int count) async {
    try {
      // 使用 GachaService 提供的方法
      final current = await GachaService.getRemainingDraws();
      await GachaService.addDraws(count);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('✅ 已添加 $count 次扭蛋机会（当前: ${current + count}次）')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    }
  }

  /// 解锁所有徽章
  Future<void> _unlockAllBadges(BuildContext context) async {
    try {
      // 使用 BadgeService 获取所有徽章并解锁
      final allBadges = badge_service.BadgeService.allBadges;
      int unlockedCount = 0;

      for (final badge in allBadges) {
        final newlyUnlocked =
            await badge_service.BadgeService.unlockBadge(badge.id);
        if (newlyUnlocked) {
          unlockedCount++;
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '✅ 已解锁全部 ${allBadges.length} 个徽章（新增: $unlockedCount 个）')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解锁失败: $e')),
        );
      }
    }
  }

  Widget _buildSectionTitle(String title, ThemeScheme scheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: scheme.textDarkColor,
      ),
    );
  }

  Widget _buildCard(List<Widget> children, ThemeScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  void _showClearDataDialog(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('危险操作'),
        content: const Text('确定要清除所有数据吗？此操作不可恢复！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // 清除所有SharedPreferences数据
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('所有数据已清除')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定清除'),
          ),
        ],
      ),
    );
  }
}
