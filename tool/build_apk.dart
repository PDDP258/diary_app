#!/usr/bin/env dart
/// APK构建脚本 - 自动版本迭代
/// 每次构建时版本号自动 +0.1
/// 使用方法: dart tool/build_apk.dart

import 'dart:io';

void main() async {
  print('╔══════════════════════════════════════╗');
  print('║      小记日记 APK 构建工具 v1.0       ║');
  print('╚══════════════════════════════════════╝');
  print('');

  // 读取当前版本
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('❌ 错误: 找不到 pubspec.yaml 文件');
    exit(1);
  }

  var content = pubspecFile.readAsStringSync();
  
  // 解析当前版本
  final versionRegExp = RegExp(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)', multiLine: true);
  final match = versionRegExp.firstMatch(content);
  
  if (match == null) {
    print('❌ 错误: 无法解析版本号');
    exit(1);
  }

  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  final patch = int.parse(match.group(3)!);
  final build = int.parse(match.group(4)!);

  print('📦 当前版本: $major.$minor.$patch+$build');
  
  // 版本号 +0.1 (即 minor + 1)
  final newMinor = minor + 1;
  final newBuild = build + 1;
  final newVersion = '$major.$newMinor.$patch+$newBuild';
  
  print('📦 新版本: $newVersion');
  print('');

  // 更新 pubspec.yaml
  final newContent = content.replaceFirst(
    versionRegExp,
    'version: $newVersion',
  );
  
  pubspecFile.writeAsStringSync(newContent);
  print('✅ 版本号已更新');
  print('');

  // 执行 flutter clean
  print('🧹 清理构建缓存...');
  var result = await Process.run('flutter', ['clean']);
  if (result.exitCode != 0) {
    print('⚠️ 清理警告: ${result.stderr}');
  } else {
    print('✅ 清理完成');
  }
  print('');

  // 执行 flutter pub get
  print('📥 获取依赖...');
  result = await Process.run('flutter', ['pub', 'get']);
  if (result.exitCode != 0) {
    print('❌ 依赖获取失败: ${result.stderr}');
    exit(1);
  }
  print('✅ 依赖获取完成');
  print('');

  // 构建 APK
  print('🔨 开始构建 APK...');
  print('   这可能需要几分钟时间，请耐心等待...');
  print('');
  
  result = await Process.run(
    'flutter',
    ['build', 'apk', '--release'],
    runInShell: true,
  );
  
  if (result.exitCode != 0) {
    print('');
    print('❌ 构建失败!');
    print(result.stderr);
    exit(1);
  }

  print('');
  print('╔══════════════════════════════════════╗');
  print('║           ✅ 构建成功!               ║');
  print('╚══════════════════════════════════════╝');
  print('');
  print('📱 版本: $newVersion');
  print('📂 输出路径: build/app/outputs/flutter-apk/app-release.apk');
  print('');
  
  // 显示文件大小
  final apkFile = File('build/app/outputs/flutter-apk/app-release.apk');
  if (apkFile.existsSync()) {
    final size = apkFile.lengthSync();
    final sizeInMB = (size / 1024 / 1024).toStringAsFixed(1);
    print('📊 文件大小: ${sizeInMB}MB');
    print('');
  }
  
  print('💡 提示: 安装到设备请运行:');
  print('   flutter install');
  print('');
}
