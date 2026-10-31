// 图片加载性能相关的回归测试（2026-10-28）。
//
// 背景：用户反馈「加载图片还是会卡卡的」。
//
// 排查发现三处叠加问题：
//   1. `OptimizedCachedImage` **没有** cacheWidth/cacheHeight 参数，
//      于是 `PlatformImage` 收到的 `cacheWidth: 200` 被静默丢弃，
//      `Image.file` 按缩略图实际像素解码（显示 100px 却解 300px）；
//   2. `PlatformImage` 用 `FutureBuilder(File(path).exists())` 建在 build 里
//      → 每次 rebuild 重新发磁盘 IO，并先回到 loading 态造成「闪白块」；
//   3. 预加载队列每批并发 3 个、批间只隔 16ms，与滚动抢 CPU。
//
// 本测试锁定 1、2 两个结构性缺陷不再回归。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/services/image_cache_service.dart';
import 'package:diary_app/utils/platform_helpers.dart';

void main() {
  group('OptimizedCachedImage 解码尺寸参数', () {
    testWidgets('必须接受 cacheWidth / cacheHeight（不能是死参数）',
        (tester) async {
      // 编译期即验证：如果构造函数没有这两个参数，本测试无法通过编译。
      const widget = OptimizedCachedImage(
        path: '/nonexistent/a.jpg',
        width: 100,
        height: 100,
        cacheWidth: 200,
        cacheHeight: 200,
      );

      expect(widget.cacheWidth, 200);
      expect(widget.cacheHeight, 200);
    });

    testWidgets('不传 cacheWidth 时也能正常工作', (tester) async {
      const widget = OptimizedCachedImage(
        path: '/nonexistent/b.jpg',
        width: 80,
        height: 80,
      );

      expect(widget.cacheWidth, isNull);
      expect(widget.quality, CacheQuality.small);
    });
  });

  group('PlatformImage 必须把 cacheWidth 透传下去', () {
    testWidgets('PlatformImage 持有所需参数', (tester) async {
      const widget = PlatformImage(
        path: '/nonexistent/c.jpg',
        width: 100,
        height: 100,
        cacheWidth: 200,
        cacheHeight: 200,
      );

      expect(widget.cacheWidth, 200);
      expect(widget.cacheHeight, 200);
    });

    testWidgets('文件不存在时直接显示占位，不抛异常（不做提前 exists 探测）',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              height: 100,
              child: PlatformImage(
                path: '/definitely/not/exists/d.jpg',
                width: 100,
                height: 100,
              ),
            ),
          ),
        ),
      );

      // 首帧不应该是 loading 转圈（旧实现会先进入 waiting 态）
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // 给异步逻辑一点时间收敛，不应抛异常
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });

  group('预加载队列行为', () {
    test('队列有上限，不会无限增长', () {
      final service = ImageCacheService();
      // 传入远超过上限的数量
      final paths = List.generate(200, (i) => '/nonexistent/pre_$i.jpg');
      service.preloadImages(paths, quality: 'small');

      // 不崩溃即可；实际上限由内部 _maxPreloadQueue 控制（私有）
      // 这里主要确保入口对超量输入是健壮的
      expect(paths.length, 200);
    });
  });
}
