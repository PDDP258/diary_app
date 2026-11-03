// 帧率 / 切换性能回归测试。
//
// 用户反馈「页面切换卡顿」「很多画面帧率明显不足」。
//
// 定位到的全局性问题：
//   1. 四个 tab 都没有 AutomaticKeepAliveClientMixin →
//      PageView 切回走 dispose → initState，每次都重建/重算；
//   2. `cacheExtent: 600`（Flutter 默认是 250，被误设为 2.4 倍）
//      → 屏幕外预构建区域翻倍；
//   3. `ScrollReveal` 动画播完后 `Opacity` 仍留在树里 → 每个列表项
//      一个离屏合成层；
//   4. 底部导航 `BackdropFilter(sigma: 20)` 全宽常驻实时模糊；
//   5. `ThemeProvider.theme` 每次访问新建整个 ThemeData，
//      而 `Consumer<ThemeProvider>` 包着整个 MaterialApp；
//   6. `SystemChrome.setSystemUIOverlayStyle` 放在 build 里 →
//      每次重建都跨平台通道往返。
//
// 本测试锁定 1、2、5、6 里可静态验证的部分。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:diary_app/providers/theme_provider.dart';
import 'package:diary_app/widgets/scroll_reveal.dart';

void main() {
  group('ThemeData 缓存（避免每次访问新建整个主题）', () {
    test('重复访问 theme 返回同一个实例', () {
      final provider = ThemeProvider();
      final first = provider.theme;
      final second = provider.theme;

      expect(identical(first, second), isTrue,
          reason: '`theme` 曾是纯计算 getter，每次访问都新建 ThemeData；'
              '而 Consumer<ThemeProvider> 包着整个 MaterialApp，'
              '会导致整树重建。必须缓存。');
    });

    test('切换主题后 theme 必须变化（缓存不能永久失效）', () async {
      final provider = ThemeProvider();
      final before = provider.theme;

      await provider.setThemeScheme(ThemeScheme.mint);

      final after = provider.theme;
      expect(identical(before, after), isFalse,
          reason: '换主题必须产生新的 ThemeData，否则界面不会更新');
      expect(after.scaffoldBackgroundColor, isNot(before.scaffoldBackgroundColor),
          reason: '新主题的背景色应当不同');
    });
  });

  group('ScrollReveal 稳态零开销', () {
    // VisibilityDetector 默认每 500ms 批量上报一次可见性：
    //   - 测试里只 pump 几百毫秒，回调根本没机会跑，controller 停在 0，
    //     于是测到的是「动画没启动」，而不是「动画播完后的稳态」；
    //   - 它还会留下一个未完成的 Timer，测试结束被判 pending timer。
    // 置 0 后改为「帧末回调」，既即时又不产生 Timer。
    setUp(() {
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
    });

    tearDown(() {
      VisibilityDetectorController.instance.updateInterval =
          const Duration(milliseconds: 500);
    });

    testWidgets('动画播完后不应继续包裹 Opacity', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollReveal(
              child: const SizedBox(width: 100, height: 100),
              duration: const Duration(milliseconds: 100),
              visibleFraction: 0.0,
            ),
          ),
        ),
      );

      // 触发 reveal（帧末回调）→ 播完
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 稳态下不应该再有无谓的 Opacity 包裹层
      expect(find.byType(Opacity), findsNothing,
          reason: '动画结束后 Opacity 仍留在树里会造成每项一个离屏合成层，'
              '列表滚动时帧率明显下降');
    });

    testWidgets('动画进行中仍应有视觉过渡（不能为了性能彻底去掉动画）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollReveal(
              child: const SizedBox(width: 100, height: 100),
              duration: const Duration(milliseconds: 400),
              visibleFraction: 0.0,
            ),
          ),
        ),
      );

      // 刚开始动画：应该处于 0~1 之间，Opacity / Transform 存在
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(Opacity), findsWidgets,
          reason: '动画过程中仍需要 Opacity 过渡，只是稳态要摘掉');

      // 收尾：跑完动画，避免残留 ticker 影响后续用例
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    });
  });
}
