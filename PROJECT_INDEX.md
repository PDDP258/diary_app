# diary_app - Project Index

## Overview
小记日记 - Flutter 个人日记应用，支持富文本编辑、图片、音频、标签分类、日历、统计分析、云同步、PDF 导出等功能。

## Directory Structure

- `lib/` - Dart 源代码（核心功能）
  - `config/` - 主题配置
  - `models/` - 数据模型
  - `providers/` - 状态管理（Provider）
  - `screens/` - 页面（Screen）
  - `services/` - 业务逻辑服务
  - `utils/` - 工具类
  - `widgets/` - 可复用组件
  - `main.dart` - 应用入口
- `android/` - Android 平台原生代码（Kotlin）
- `assets/` - 静态资源（字体、图标、图片）
- `test/` - 测试文件
- `tool/` - 构建/发布脚本
- `web/` - Web 平台配置
- `windows/` - Windows 平台配置

## Key Files

- [pubspec.yaml](pubspec.yaml) - Flutter 依赖与项目配置
- [AGENTS.md](AGENTS.md) - AI 协作指南（项目规范、架构说明）
- [TRAE_PROJECT_RULES.md](TRAE_PROJECT_RULES.md) - 项目结构规则
- [lib/main.dart](lib/main.dart) - 应用入口
- [android/app/src/main/kotlin/com/example/diary_app/](android/app/src/main/kotlin/com/example/diary_app/) - Android 原生代码

## Recent Changes

- 2026-05-13: 浮窗系统体验优化（设置持久化修复、图片图标、呼吸动画、UI 美化）
- 2026-04-22: 自言自语完全独立 + 速记功能 + PDF 字体修复
- 2026-04-10: 自言自语 + 设计系统全面升级
