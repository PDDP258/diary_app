import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/gacha_service.dart';
import '../services/sound_service.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import 'main_screen.dart';

class GachaScreen extends StatefulWidget {
  const GachaScreen({super.key});

  @override
  State<GachaScreen> createState() => _GachaScreenState();
}

class _GachaScreenState extends State<GachaScreen>
    with TickerProviderStateMixin {
  int _remainingDraws = 0;
  bool _isDrawing = false;
  bool _isShaking = false; // 是否正在晃动等待用户点击
  GachaDrawResult? _lastResult;
  late AnimationController _animationController;
  late AnimationController _shakeController; // 晃动动画控制器
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;
  late Animation<double> _shakeAnimation; // 晃动动画
  bool _showReward = false;

  @override
  void initState() {
    super.initState();
    _loadRemainingDraws();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3)
        .chain(CurveTween(curve: Curves.elasticInOut))
        .animate(_animationController);
    _rotateAnimation = Tween<double>(begin: 0, end: 2 * pi)
        .chain(CurveTween(curve: Curves.elasticInOut))
        .animate(_animationController);
    // 晃动动画 - 左右摇摆（加大晃动幅度）
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.25), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.25, end: 0.25), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.25, end: -0.25), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.25, end: 0.25), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.25, end: 0.0), weight: 1),
    ]).chain(CurveTween(curve: Curves.easeInOut)).animate(_shakeController);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _loadRemainingDraws() async {
    final draws = await GachaService.getRemainingDraws();
    if (mounted) {
      setState(() {
        _remainingDraws = draws;
      });
    }
  }

  Future<void> _startDraw() async {
    if (_isDrawing || _isShaking || _remainingDraws <= 0) return;

    setState(() {
      _isShaking = true;
      _showReward = false;
      _lastResult = null;
    });

    // 开始持续晃动动画
    _startShakeAnimation();
  }

  void _startShakeAnimation() {
    _shakeController.repeat();
  }

  Future<void> _stopShakeAndDraw() async {
    if (!_isShaking || _isDrawing) return;

    // 播放点击音效
    SoundService.playClick();

    _shakeController.stop();
    setState(() {
      _isShaking = false;
      _isDrawing = true;
    });

    // 播放抽奖动画
    await _animationController.forward(from: 0);

    // 延迟执行抽奖逻辑，确保动画播放
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      final result = await GachaService.performDraw();
      if (mounted) {
        setState(() {
          _lastResult = result;
          _showReward = true;
        });
        await _loadRemainingDraws();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('抽奖失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDrawing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    return Scaffold(
      backgroundColor: scheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: scheme.primaryColor,
        title: const Text('扭蛋机'),
        centerTitle: true,
        actions: [
          // 收藏统计按钮
          IconButton(
            icon: const Icon(Icons.collections_bookmark_outlined),
            tooltip: '收藏统计',
            onPressed: () => _showCollectionStats(context),
          ),
          // 历史记录按钮
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '历史记录',
            onPressed: () => _showHistory(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildDrawsInfo(scheme),
                    const SizedBox(height: 20),
                    // 商店快捷入口
                    _buildShopQuickAccess(scheme),
                    const SizedBox(height: 20),
                    _buildGachaMachine(scheme),
                    const SizedBox(height: 30),
                    if (_showReward && _lastResult != null)
                      _buildRewardCard(scheme, _lastResult!),
                    const SizedBox(height: 30),
                    _buildDrawButton(scheme),
                    const SizedBox(height: 30),
                    _buildProbabilityInfo(scheme),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawsInfo(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.lightColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今日剩余',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.textMediumColor.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '写第一篇日记+1次，满3篇再+1次',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.textMediumColor.withOpacity(0.5),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primaryColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$_remainingDraws 次',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: scheme.textDarkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 商店快捷访问
  Widget _buildShopQuickAccess(ThemeScheme scheme) {
    return FutureBuilder<Map<String, int>>(
      future: GachaService.getAllResourceCounts(),
      builder: (context, snapshot) {
        final resources = snapshot.data ?? {};
        final stickerPoints = resources['sticker_points'] ?? 0;
        final decorPoints = resources['profile_decor_points'] ?? 0;
        final hasResources = stickerPoints > 0 || decorPoints > 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.amber.withOpacity(0.15),
                scheme.primaryColor.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasResources
                  ? Colors.amber.withOpacity(0.5)
                  : scheme.lightColor.withOpacity(0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.store_outlined,
                color: hasResources ? Colors.amber : scheme.textLightColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '奖励商店',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: scheme.textDarkColor,
                      ),
                    ),
                    Text(
                      '🧩 $stickerPoints  🎨 $decorPoints',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.textMediumColor,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _showCollectionStats(context),
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('进入'),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primaryColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGachaMachine(ThemeScheme scheme) {
    return GestureDetector(
      onTap: _isShaking ? _stopShakeAndDraw : null,
      child: AnimatedBuilder(
        animation: Listenable.merge([_animationController, _shakeController]),
        builder: (context, child) {
          // 根据状态选择动画
          double scale = 1.0;
          double rotateZ = 0.0;
          double rotateY = 0.0;

          if (_isShaking) {
            // 晃动状态
            rotateY = _shakeAnimation.value;
          } else if (_isDrawing || _showReward) {
            // 抽奖或展示结果状态
            scale = _scaleAnimation.value;
            rotateZ = _rotateAnimation.value;
          }

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..scale(scale)
              ..rotateZ(rotateZ)
              ..rotateY(rotateY),
            child: child,
          );
        },
        child: Container(
          width: 200,
          height: 260,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.primaryColor,
                scheme.darkColor,
              ],
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: scheme.lightColor.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 20,
                left: 20,
                right: 20,
                bottom: 60,
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.lightColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: scheme.textLightColor,
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (int i = 0; i < 12; i++) _buildGachaBall(i),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 60,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 5,
                          offset: const Offset(0, 3),
                        ),
                      ],
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

  Widget _buildGachaBall(int index) {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
      Colors.pink,
    ];
    final color = colors[index % colors.length];

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.9),
            color.withOpacity(0.6),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 5,
            offset: const Offset(2, 2),
          ),
        ],
      ),
    );
  }

  // 生成奖励描述（支持头像个性化）
  // 注意：此方法不再包含"重复获得"说明，因为那只在抽奖结果页面显示
  String _getRewardDescription(GachaReward reward) {
    String baseDesc = reward.description;

    // 如果是静态头像或个性化头像，处理占位符
    if (reward.type == GachaRewardType.avatar &&
        reward.data != null &&
        reward.data!.startsWith('personalize_')) {
      baseDesc = baseDesc.replaceAll('{days}', 'X');
      baseDesc = baseDesc.replaceAll('{streak}', 'X');
      baseDesc = baseDesc.replaceAll('{badges}', 'X');
      baseDesc = baseDesc.replaceAll('{photos}', 'X');
      baseDesc = baseDesc.replaceAll('{words}', 'XXXX');
      baseDesc = baseDesc.replaceAll('{moods}', 'X');
      baseDesc = baseDesc.replaceAll('{tags}', 'X');
      baseDesc = baseDesc.replaceAll('{nightEntries}', 'X');
      baseDesc = baseDesc.replaceAll('{morningEntries}', 'X');
      baseDesc = baseDesc.replaceAll('{totalDiaries}', 'XX');
    }

    return baseDesc;
  }

  Widget _buildRewardCard(ThemeScheme scheme, GachaDrawResult result) {
    final reward = result.reward;
    final rarityColor = GachaService.getRarityColor(reward.rarity);
    final rarityName = GachaService.getRarityName(reward.rarity);
    final description = _getRewardDescription(reward);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: rarityColor,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: rarityColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: rarityColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Text(
              reward.emoji,
              style: const TextStyle(fontSize: 48),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            reward.name,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: scheme.textDarkColor,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: rarityColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              rarityName,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: rarityColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              fontSize: 16,
              color: scheme.textMediumColor.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          if (reward.effect != null && reward.effect!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.primaryColor.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: scheme.primaryColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    reward.effect!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 货币奖励首次获得提示
          if (!result.isDuplicate &&
              reward.type == GachaRewardType.currency) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.green.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    color: Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '已累加到账户！',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (result.isDuplicate && result.duplicateBonus != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.recycling,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      result.duplicateBonus!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDrawButton(ThemeScheme scheme) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _isDrawing || _isShaking || _remainingDraws <= 0
            ? null
            : _startDraw,
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primaryColor,
          disabledBackgroundColor: scheme.primaryColor.withOpacity(0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 5,
        ),
        child: _isDrawing
            ? const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              )
            : _isShaking
                ? const Text(
                    '点击扭蛋机停止',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _remainingDraws <= 0 ? '今日次数已用完' : '点击抽奖',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
      ),
    );
  }

  Widget _buildProbabilityInfo(ThemeScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.lightColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '概率说明',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: scheme.textMediumColor,
            ),
          ),
          const SizedBox(height: 12),
          _buildProbabilityRow(scheme, '普通', 60,
              GachaService.getRarityColor(GachaRarity.common)),
          const SizedBox(height: 8),
          _buildProbabilityRow(scheme, '稀有', 25,
              GachaService.getRarityColor(GachaRarity.uncommon)),
          const SizedBox(height: 8),
          _buildProbabilityRow(
              scheme, '史诗', 12, GachaService.getRarityColor(GachaRarity.rare)),
          const SizedBox(height: 8),
          _buildProbabilityRow(scheme, '传说', 3,
              GachaService.getRarityColor(GachaRarity.legendary)),
        ],
      ),
    );
  }

  Widget _buildProbabilityRow(
      ThemeScheme scheme, String name, int percent, Color color) {
    return Row(
      children: [
        Container(
          width: 60,
          child: Text(
            name,
            style: TextStyle(
              fontSize: 14,
              color: scheme.textMediumColor,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: scheme.textLightColor.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              widthFactor: percent / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$percent%',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: scheme.textLightColor,
          ),
        ),
      ],
    );
  }

  void _showHistory(BuildContext context) async {
    final history = await GachaService.getHistory();
    final scheme = AppTheme.schemeOf(context);

    if (!mounted) return;

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
                    '抽奖历史',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: scheme.textDarkColor,
                    ),
                  ),
                  const Spacer(),
                  if (history.isNotEmpty)
                    TextButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('清空历史'),
                            content: const Text('确定要清空所有抽奖历史记录吗？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('取消'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('确定'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await GachaService.clearHistory();
                          Navigator.pop(context);
                          _showHistory(context);
                        }
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('清空'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history,
                            size: 64,
                            color: scheme.textLightColor,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无抽奖记录',
                            style: TextStyle(
                              fontSize: 16,
                              color: scheme.textMediumColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final record = history[index];
                        return _buildHistoryItem(scheme, record);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(ThemeScheme scheme, GachaRecord record) {
    final reward = record.reward;
    final rarityColor = GachaService.getRarityColor(reward.rarity);
    final timeStr =
        '${record.time.month}/${record.time.day} ${record.time.hour.toString().padLeft(2, '0')}:${record.time.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: rarityColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: rarityColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                reward.emoji,
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      reward.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.textDarkColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: rarityColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        GachaService.getRarityName(reward.rarity),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: rarityColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.textLightColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCollectionStats(BuildContext context) async {
    final stats = await GachaService.getAllCollectionStats();
    final allRewards = await GachaService.getAllRewards();
    final scheme = AppTheme.schemeOf(context);

    int totalCount = stats.values.fold(0, (sum, count) => sum + count);
    int uniqueCount = stats.length;
    int totalRewards = allRewards.length;

    Map<GachaRarity, int> rarityStats = {
      GachaRarity.common: 0,
      GachaRarity.uncommon: 0,
      GachaRarity.rare: 0,
      GachaRarity.legendary: 0,
    };

    for (final reward in allRewards) {
      if (stats.containsKey(reward.id)) {
        rarityStats[reward.rarity] = rarityStats[reward.rarity]! + 1;
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: scheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 顶部固定部分
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
              child: Text(
                '收藏统计',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: scheme.textDarkColor,
                ),
              ),
            ),
            // 可滚动内容区域
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              scheme,
                              '收集进度',
                              '$uniqueCount/$totalRewards',
                              Icons.collections,
                              scheme.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              scheme,
                              '总获得数',
                              totalCount.toString(),
                              Icons.auto_awesome,
                              Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildRarityStatCard(
                              scheme,
                              '普通',
                              rarityStats[GachaRarity.common]!,
                              GachaService.getRarityColor(GachaRarity.common),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildRarityStatCard(
                              scheme,
                              '稀有',
                              rarityStats[GachaRarity.uncommon]!,
                              GachaService.getRarityColor(GachaRarity.uncommon),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildRarityStatCard(
                              scheme,
                              '史诗',
                              rarityStats[GachaRarity.rare]!,
                              GachaService.getRarityColor(GachaRarity.rare),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildRarityStatCard(
                              scheme,
                              '传说',
                              rarityStats[GachaRarity.legendary]!,
                              GachaService.getRarityColor(
                                  GachaRarity.legendary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 资源展示区域
                    FutureBuilder<Map<String, dynamic>>(
                      future: GachaService.getResourceSummary(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox.shrink();

                        final resources =
                            snapshot.data!['resources'] as Map<String, int>;
                        final levelInfo =
                            snapshot.data!['level'] as Map<String, dynamic>;

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                scheme.primaryColor.withOpacity(0.1),
                                scheme.primaryColor.withOpacity(0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: scheme.primaryColor.withOpacity(0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 等级信息
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: scheme.primaryColor,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Lv.${levelInfo['level']} ${levelInfo['title']}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '距离下级还需 ${levelInfo['next_level_need']} 经验',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.textMediumColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // 经验条
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: levelInfo['progress'] as double,
                                  backgroundColor:
                                      scheme.lightColor.withOpacity(0.3),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      scheme.primaryColor),
                                  minHeight: 6,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // 资源列表
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildResourceChip(scheme, '🧩',
                                      resources['sticker_points'] ?? 0, '贴纸碎片'),
                                  _buildResourceChip(
                                      scheme,
                                      '🎨',
                                      resources['profile_decor_points'] ?? 0,
                                      '装饰点'),
                                  _buildResourceChip(scheme, '✨',
                                      resources['user_exp'] ?? 0, '经验'),
                                  _buildResourceChip(scheme, '💝',
                                      resources['mood_energy'] ?? 0, '心情能量'),
                                  _buildResourceChip(
                                      scheme,
                                      '💡',
                                      resources['writing_inspiration'] ?? 0,
                                      '灵感'),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // 兑换按钮 - 始终显示，资源不足时禁用
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed:
                                          (resources['sticker_points'] ?? 0) >=
                                                  5
                                              ? () => _showStickerShop(context)
                                              : null,
                                      icon: const Icon(Icons.shopping_bag,
                                          size: 16),
                                      label: Text(
                                          '贴纸商店 (${resources['sticker_points'] ?? 0}/5)'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: scheme.primaryColor,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor:
                                            scheme.lightColor.withOpacity(0.3),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed:
                                          (resources['profile_decor_points'] ??
                                                      0) >=
                                                  15
                                              ? () => _showThemeShop(context)
                                              : null,
                                      icon: const Icon(Icons.palette, size: 16),
                                      label: Text(
                                          '主题商店 (${resources['profile_decor_points'] ?? 0}/15)'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.amber,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor:
                                            Colors.amber.withOpacity(0.2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text(
                            '已收集奖励',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: scheme.textDarkColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 奖励网格 - 现在在同一个滚动视图中
                    stats.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: 32),
                                Icon(
                                  Icons.card_giftcard,
                                  size: 64,
                                  color: scheme.textLightColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '还没有收集任何奖励',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: scheme.textMediumColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '快去抽奖吧！',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: scheme.textLightColor,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            shrinkWrap: true, // 重要：让 GridView 适应内容高度
                            physics:
                                const NeverScrollableScrollPhysics(), // 禁用 GridView 自身的滚动
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.85,
                            ),
                            itemCount: allRewards.length,
                            itemBuilder: (context, index) {
                              final reward = allRewards[index];
                              final count = stats[reward.id] ?? 0;
                              return _buildCollectionItem(
                                  scheme, reward, count);
                            },
                          ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(ThemeScheme scheme, String title, String value,
      IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.textLightColor,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: scheme.textDarkColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRarityStatCard(
      ThemeScheme scheme, String name, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              color: scheme.textMediumColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionItem(
      ThemeScheme scheme, GachaReward reward, int count) {
    final rarityColor = GachaService.getRarityColor(reward.rarity);
    final isCollected = count > 0;

    return GestureDetector(
      onTap: () => _showRewardDetail(context, reward, count),
      child: Container(
        decoration: BoxDecoration(
          color: isCollected
              ? scheme.cardColor
              : scheme.lightColor.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCollected
                ? rarityColor.withOpacity(0.5)
                : scheme.textLightColor.withOpacity(0.3),
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: isCollected ? 1.0 : 0.3,
                    child: Text(
                      reward.emoji,
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isCollected ? reward.name : '???',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isCollected
                          ? scheme.textDarkColor
                          : scheme.textLightColor,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isCollected && count > 1) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: rarityColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'x$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: rarityColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!isCollected)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  Icons.lock,
                  size: 14,
                  color: scheme.textLightColor,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showRewardDetail(BuildContext context, GachaReward reward, int count) {
    final scheme = AppTheme.schemeOf(context);
    final rarityColor = GachaService.getRarityColor(reward.rarity);
    final isCollected = count > 0;
    final description = _getRewardDescription(reward);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: rarityColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Opacity(
                  opacity: isCollected ? 1.0 : 0.3,
                  child: Text(
                    reward.emoji,
                    style: const TextStyle(fontSize: 48),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isCollected ? reward.name : '???',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: scheme.textDarkColor,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: rarityColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                GachaService.getRarityName(reward.rarity),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: rarityColor,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.lightColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '获得次数',
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.textMediumColor,
                        ),
                      ),
                      Text(
                        count.toString(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: scheme.textDarkColor,
                        ),
                      ),
                    ],
                  ),
                  if (isCollected) ...[
                    const SizedBox(height: 12),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.textMediumColor,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 资源芯片组件
  Widget _buildResourceChip(
      ThemeScheme scheme, String emoji, int count, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.lightColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: scheme.textDarkColor,
            ),
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: scheme.textMediumColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 贴纸商店
  void _showStickerShop(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
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
                  Expanded(
                    child: Text(
                      '贴纸商店',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: scheme.textDarkColor,
                      ),
                    ),
                  ),
                  FutureBuilder<Map<String, int>>(
                    future: GachaService.getAllResourceCounts(),
                    builder: (context, snapshot) {
                      final points = snapshot.data?['sticker_points'] ?? 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Text('🧩'),
                            const SizedBox(width: 4),
                            Text(
                              '$points',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: scheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: GachaService.stickerShop.length,
                itemBuilder: (context, index) {
                  final entry =
                      GachaService.stickerShop.entries.elementAt(index);
                  final item = entry.value;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: scheme.cardColor,
                    child: ListTile(
                      leading: Text(
                        item['emoji'] as String,
                        style: const TextStyle(fontSize: 32),
                      ),
                      title: Text(
                        item['name'] as String,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: scheme.textDarkColor,
                        ),
                      ),
                      subtitle: Text(
                        '${item['description']}',
                        style: TextStyle(color: scheme.textMediumColor),
                      ),
                      trailing: ElevatedButton(
                        onPressed: () =>
                            _buyStickerItem(context, entry.key, item),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primaryColor,
                        ),
                        child: Text('${item['cost']}🧩'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 购买贴纸商品
  Future<void> _buyStickerItem(
      BuildContext context, String itemId, Map<String, dynamic> item) async {
    final scheme = AppTheme.schemeOf(context);

    // 播放点击音效
    SoundService.playClick();

    // 显示确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认购买', style: TextStyle(color: scheme.textDarkColor)),
        content: Text('确定要花费 ${item['cost']}🧩 购买 ${item['name']}？'),
        actions: [
          TextButton(
            onPressed: () {
              SoundService.playClick();
              Navigator.pop(context, false);
            },
            child: Text('取消', style: TextStyle(color: scheme.textMediumColor)),
          ),
          ElevatedButton(
            onPressed: () {
              SoundService.playClick();
              Navigator.pop(context, true);
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: scheme.primaryColor),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await GachaService.exchangeSticker(itemId);
    if (success && mounted) {
      // 播放成功音效
      SoundService.playSuccess();
      // 购买成功动画
      _showPurchaseSuccessAnimation(
          context, item['emoji'] as String, item['name'] as String);
      // 延迟关闭弹窗
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.pop(context);
      }
    } else if (mounted) {
      // 播放错误音效
      SoundService.playError();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('贴纸碎片不足')),
      );
    }
  }

  /// 购买成功动画
  void _showPurchaseSuccessAnimation(
      BuildContext context, String emoji, String name) {
    final scheme = AppTheme.schemeOf(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: scheme.primaryColor.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 礼花动画
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: 0.5 + value * 0.5,
                    child: Transform.rotate(
                      angle: (1 - value) * 0.5,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: scheme.primaryColor.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 48),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                '🎉 购买成功！',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: scheme.textDarkColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '获得 $name',
                style: TextStyle(
                  fontSize: 16,
                  color: scheme.textMediumColor,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '已添加到自定义贴纸',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // 自动关闭
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
  }

  /// 主题商店
  void _showThemeShop(BuildContext context) {
    final scheme = AppTheme.schemeOf(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
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
                  Expanded(
                    child: Text(
                      '主题商店',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: scheme.textDarkColor,
                      ),
                    ),
                  ),
                  FutureBuilder<Map<String, int>>(
                    future: GachaService.getAllResourceCounts(),
                    builder: (context, snapshot) {
                      final points =
                          snapshot.data?['profile_decor_points'] ?? 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Text('🎨'),
                            const SizedBox(width: 4),
                            Text(
                              '$points',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: GachaService.profileThemeShop.length,
                itemBuilder: (context, index) {
                  final entry =
                      GachaService.profileThemeShop.entries.elementAt(index);
                  final item = entry.value;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: scheme.cardColor,
                    child: ListTile(
                      leading: Text(
                        item['preview'] as String,
                        style: const TextStyle(fontSize: 32),
                      ),
                      title: Text(
                        item['name'] as String,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: scheme.textDarkColor,
                        ),
                      ),
                      subtitle: Text(
                        '${item['description']}',
                        style: TextStyle(color: scheme.textMediumColor),
                      ),
                      trailing: ElevatedButton(
                        onPressed: () =>
                            _buyThemeItem(context, entry.key, item),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                        ),
                        child: Text('${item['cost']}🎨'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 购买主题商品
  Future<void> _buyThemeItem(
      BuildContext context, String itemId, Map<String, dynamic> item) async {
    final scheme = AppTheme.schemeOf(context);

    // 显示确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认购买', style: TextStyle(color: scheme.textDarkColor)),
        content:
            Text('确定要花费 ${item['cost']}🎨 购买 ${item['name']}？\n\n购买后主题将立即生效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: scheme.textMediumColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await GachaService.exchangeProfileTheme(itemId);
    if (success && mounted) {
      // 立即应用主题
      final colors = GachaService.getThemeColors(itemId);
      if (colors != null) {
        final themeProvider = context.read<ThemeProvider>();
        final newScheme = ThemeScheme(
          primaryColor: Color(colors['primary'] as int),
          backgroundColor: Color(colors['background'] as int),
          cardColor: colors['card'] != null
              ? Color(colors['card'] as int)
              : Colors.white,
          lightColor: Color(colors['light'] as int),
          darkColor: Color(colors['dark'] as int),
          textDarkColor: Color(colors['textDark'] as int),
          textMediumColor: Color(colors['textMedium'] as int),
          textLightColor: Color(colors['textLight'] as int),
          name: item['name'] as String,
        );
        await themeProvider.setThemeScheme(newScheme);
      }
      // 购买成功动画
      _showThemePurchaseSuccessAnimation(
          context, item['preview'] as String, item['name'] as String);
      // 延迟关闭弹窗
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.pop(context);
        // 主题购买成功后跳转到日记页
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const MainScreen(initialIndex: 0),
          ),
          (route) => false,
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('装饰点不足')),
      );
    }
  }

  /// 主题购买成功动画
  void _showThemePurchaseSuccessAnimation(
      BuildContext context, String preview, String name) {
    final scheme = AppTheme.schemeOf(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 动画
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: 0.5 + value * 0.5,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.amber.withOpacity(0.3),
                            Colors.orange.withOpacity(0.3),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          preview,
                          style: const TextStyle(fontSize: 56),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                '🎉 主题购买成功！',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: scheme.textDarkColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$name 已生效',
                style: TextStyle(
                  fontSize: 16,
                  color: scheme.textMediumColor,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '已自动应用到个人主页',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // 自动关闭
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
  }
}
