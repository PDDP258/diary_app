/// 小组件布局的「白名单」回归测试。
///
/// 背景：RemoteViews 的布局是在**启动器进程**里 inflate 的，框架用
/// `RemoteViews.INFLATER_FILTER = clazz -> clazz.isAnnotationPresent(@RemoteView)` 强校验
/// 每个 View 类。用了不在白名单里的类 → `InflateException: Class not allowed to be
/// inflated ...` → 桌面显示「无法加载小部件」，而 **App 侧完全看不到这条异常**
/// （onUpdate 的 try/catch 拦不住，因为是对方进程在炸）。
///
/// 2026-09-30 就是这么翻的车：`widget_course.xml` 里拿 `<View>` 当 1dp 分隔线，
/// 而 `android.view.View` 没有 @RemoteView。所以这里用测试把白名单焊死。
///
/// 同理，`RemoteViews.getMethod()` 会强校验反射调用的方法带 `@RemotableViewMethod`，
/// 所以 `setInt(id, "方法名", ...)` 里能写的方法名也必须是已知安全的那几个。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// RemoteViews 允许的 View 类（简单名）。
/// 来源：框架 `RemoteViews.INFLATER_FILTER` + 官方文档
/// 「App Widgets → Creating the App Widget Layout」的清单。
/// 注意：**不含 `View`/`ViewGroup`**，也不含任何自定义 View 与其子类。
const Set<String> _allowedWidgetViews = {
  // 容器
  'FrameLayout',
  'LinearLayout',
  'RelativeLayout',
  'GridLayout',
  // 控件
  'AnalogClock',
  'Button',
  'Chronometer',
  'ImageButton',
  'ImageView',
  'ProgressBar',
  'TextView',
  'ViewFlipper',
  'ListView',
  'GridView',
  'StackView',
  'AdapterViewFlipper',
  'ViewStub',
};

/// 允许出现在 `setInt(viewId, "…", value)` 里的方法名 —— 必须是带
/// `@RemotableViewMethod` 的官方方法（框架会在运行时校验，没带就抛 ActionException）。
/// `setBackgroundResource` **不在**此列：它不是 remotable 方法，曾经在这里踩过坑。
const Set<String> _allowedReflectedMethods = {
  'setBackgroundColor',
};

const String _layoutDir = 'android/app/src/main/res/layout';
const String _rendererPath =
    'android/app/src/main/kotlin/com/example/diary_app/CourseWidgetRenderer.kt';
const String _widgetInfoPath =
    'android/app/src/main/res/xml/course_widget_info.xml';

/// 去掉 XML 注释：注释里会拿 `<View>` 当反面教材举例子，不能算进标签统计。
String _stripComments(String src) =>
    src.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// 抽出元素名（不含闭合标签、不含 `<?xml` 声明）。
List<String> _elementNames(String xmlSource) {
  final re = RegExp(r'<\s*([A-Za-z_][A-Za-z0-9_.]*)');
  return re
      .allMatches(_stripComments(xmlSource))
      .map((m) => m.group(1)!)
      .toList();
}

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '找不到文件：$path');
  return file.readAsStringSync();
}

/// 渲染器里所有 `setInt(id, "method", ...)` 的方法名
List<String> _reflectedMethodNames(String kotlinSource) {
  // 先剥掉注释（块注释和行注释）—— 文件头的 KDoc 里就拿
  // `setInt(viewId, "setColorFilter", color)` 当反面教材举过例子，
  // 不剥掉会被当成真实调用。
  final code = kotlinSource
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
  final re = RegExp(r'setInt\(\s*[^,]+,\s*"([A-Za-z0-9_]+)"');
  return re.allMatches(code).map((m) => m.group(1)!).toList();
}

void main() {
  group('小组件布局只使用 RemoteViews 白名单内的 View', () {
    for (final name in ['widget_course.xml', 'widget_course_row.xml']) {
      test('$name 的每个标签都在白名单内', () {
        final tags = _elementNames(_read('$_layoutDir/$name'));
        expect(tags, isNotEmpty, reason: '没解析出任何标签，正则可能失效了');

        final offenders = tags.toSet().difference(_allowedWidgetViews).toList()
          ..sort();
        expect(
          offenders,
          isEmpty,
          reason: '$name 里出现了 RemoteViews 不允许的 View：$offenders。\n'
              '这些类会在启动器进程 inflate 时抛 InflateException，'
              '桌面直接显示「无法加载小部件」。'
              '分隔线请用 1dp 的 ImageView / TextView，别用 <View>。',
        );
      });
    }

    test('根布局本身不是 <View> 或自定义 View', () {
      // 单独锁一条：这次翻车的就是 <View> 分隔线
      final xml = _stripComments(_read('$_layoutDir/widget_course.xml'));
      expect(xml.contains('<View'), isFalse,
          reason: 'android.view.View 没有 @RemoteView，不能出现在小组件布局里');
      expect(xml.contains('<androidx.'), isFalse,
          reason: 'androidx / 第三方 View 都不是 RemoteViews 允许的类型');
      expect(RegExp(r'<com\.').hasMatch(xml), isFalse,
          reason: '自定义 View 不是 RemoteViews 允许的类型');
    });
  });

  group('小组件描述文件', () {
    test('initialLayout 指向的布局同样在白名单内', () {
      final info = _read(_widgetInfoPath);
      final m = RegExp(r'android:initialLayout="@layout/([A-Za-z0-9_]+)"')
          .firstMatch(info);
      expect(m, isNotNull, reason: 'course_widget_info.xml 没有 initialLayout');

      final layoutFile = '${m!.group(1)}.xml';
      final tags = _elementNames(_read('$_layoutDir/$layoutFile'));
      final offenders =
          tags.toSet().difference(_allowedWidgetViews).toList()..sort();
      expect(offenders, isEmpty,
          reason: 'initialLayout=$layoutFile 里有不合规的 View：$offenders');
    });

    test('updatePeriodMillis 不为 0（否则系统永远不唤醒小组件）', () {
      final info = _read(_widgetInfoPath);
      final m = RegExp(r'android:updatePeriodMillis="(\d+)"').firstMatch(info);
      expect(m, isNotNull, reason: '没写 updatePeriodMillis');
      expect(int.parse(m!.group(1)!), greaterThan(0),
          reason: '0 表示「只靠 App 主动刷新」，跨天就会一直显示昨天的课');
    });
  });

  group('渲染器不调用未带 @RemotableViewMethod 的方法', () {
    test('setInt 只用在已知安全的 remotable 方法上', () {
      final calls = _reflectedMethodNames(_read(_rendererPath));
      final offenders = calls.toSet().difference(_allowedReflectedMethods);
      expect(offenders, isEmpty,
          reason: '$_rendererPath 里 setInt 调用了 $offenders。\n'
              '框架 RemoteViews.getMethod() 会校验 @RemotableViewMethod，'
              '没带注解就在启动器进程抛 ActionException。'
              '换官方 API（例如背景改用 setImageViewResource）。');
    });
  });
}
