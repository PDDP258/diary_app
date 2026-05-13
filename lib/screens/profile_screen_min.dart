import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';
import '../services/badge_service.dart' as badge_service;
import '../services/sound_service.dart';
import 'icon_theme_screen.dart';
import 'tag_management_screen_v3.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<badge_service.Badge> _unlockedBadges = [];
  bool _hasNewBadge = false;

  @override
  void initState() {
    super.initState();
    _loadBadges();
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

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            _buildUserCard(context),
            const SizedBox(height: 16),
            _buildMenuGroup([
              _MenuItem(
                icon: Icons.palette_outlined,
                title: '主题配色',
                subtitle: '切换整个应用的配色风格',
                onTap: () => _showThemePicker(context),
              ),
            ], scheme),
            const SizedBox(height: 16),
            _buildMenuGroup([
              _MenuItem(
                icon: Icons.sentiment_satisfied_outlined,
                title: '心情管理',
                onTap: () {},
              ),
              _MenuItem(
                icon: Icons.label_outlined,
                title: '标签管理',
                onTap: () => _showTagManager(context),
              ),
            ], scheme),
            const SizedBox(height: 16),
            _buildMenuGroup([
              _MenuItem(
                icon: Icons.info_outline,
                title: '关于日记',
                subtitle: '版本 1.3.0',
                onTap: () => _showAbout(context),
              ),
            ], scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final scheme = AppTheme.schemeOf(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showAvatarSelector(context),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.lightColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.primaryColor.withValues(alpha: 0.3),
                  width: 3,
                ),
              ),
              child: settings.customAvatarPath != null
                  ? ClipOval(
                      child: Image.file(
                        File(settings.customAvatarPath!),
                        fit: BoxFit.cover,
                      ),
                    )
                  : Center(
                      child: Text(
                        settings.userEmoji,
                        style: const TextStyle(fontSize: 36),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.userName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: scheme.textDarkColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  settings.userSignature,
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.textMediumColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAvatarSelector(BuildContext context) {
    final settings = context.read<SettingsProvider>();
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
                  }
                },
              ),
              if (settings.customAvatarPath != null)
                ListTile(
                  leading: const Icon(Icons.emoji_emotions),
                  title: const Text('恢复默认表情'),
                  onTap: () async {
                    Navigator.pop(context);
                    await settings.clearCustomAvatar();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showThemePicker(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const IconThemeScreen()),
    );
  }

  void _showTagManager(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TagManagementScreenV3()),
    );
  }

  void _showAbout(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于日记'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.lightColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Text(
                    '小记日记',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '版本 1.3.0',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('📅 农历日历支持'),
            const Text('🎯 目标系统增强'),
            const Text('🏷️ 三级标签系统'),
            const Text('🎁 扭蛋池优化'),
            const SizedBox(height: 16),
            const Text(
              '作者: PDDP',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Text(
              '版权所有 2024-2026',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuGroup(List<Widget> items, ThemeScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(children: items),
    );
  }
}

class _MenuItem extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);
    return ListTile(
      leading: Icon(icon, color: scheme.textMediumColor),
      title: Text(
        title,
        style: TextStyle(color: scheme.textDarkColor),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(color: scheme.textLightColor),
            )
          : null,
      trailing: trailing ?? Icon(Icons.chevron_right, color: scheme.textLightColor),
      onTap: () {
        SoundService.playClick();
        onTap();
      },
    );
  }
}
