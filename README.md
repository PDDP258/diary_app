# 小记日记 App

一个支持日历视图的日记软件，可以记录文字、图片。

## 功能特性

- 📅 **日历视图** - 按日期浏览日记
- 📝 **日记编辑** - 支持文字和图片
- 💾 **本地存储** - 数据保存在手机本地，不需要联网
- 🎨 **粉色主题** - 温馨的界面设计

## 安装步骤

### 1. 安装 Flutter SDK

**方式一：手动安装（推荐，更快）**
1. 下载 Flutter SDK: https://docs.flutter.dev/development/tools/sdk/releases?tab=windows
2. 解压到 `C:\flutter`
3. 添加环境变量：将 `C:\flutter\bin` 添加到系统 PATH

**方式二：等待自动解压完成**
（如果后台解压正在进行中，请稍等...）

### 2. 配置 VS Code

在 VS Code 中安装以下扩展：
- Dart Code (Dart 支持)
- Flutter (Flutter 支持)

### 3. 运行项目

打开终端，进入项目目录：
```bash
cd e:\main\work\小记\diary_app
```

获取依赖：
```bash
flutter pub get
```

运行应用：
```bash
flutter run
```

### 4. 构建 APK

```bash
flutter build apk --debug
```

APK 文件将生成在 `build\app\outputs\flutter-apk\app-debug.apk`

## 项目结构

```
diary_app/
├── lib/
│   ├── main.dart              # 应用入口
│   ├── models/
│   │   └── diary.dart         # 日记数据模型
│   ├── screens/
│   │   ├── calendar_screen.dart   # 日历页面
│   │   └── diary_list_screen.dart # 日记编辑页面
│   └── services/
│       └── database_service.dart  # 数据库服务
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml   # Android 配置
└── pubspec.yaml               # 项目依赖配置
```

## 技术栈

- **框架**: Flutter
- **日历组件**: table_calendar
- **数据库**: sqflite (本地 SQLite)
- **图片选择**: image_picker

## 许可证

MIT License
