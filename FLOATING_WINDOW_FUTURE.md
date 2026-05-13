# 速记浮窗系统 — 未完成任务与未来规划

> 文档版本：v1.0（2026-05-12）
> 关联计划：`quasar-jessica-cruz-kid-flash.md`、`blade-hawkeye-quasar.md`

---

## 一、未完成任务清单

### 🔴 高优先级

| # | 任务 | 状态 | 阻塞原因 | 预计工作量 |
|---|------|------|----------|-----------|
| 1 | **面板大小拖动调节** | ❌ 未开始 | 需重写 Kotlin 触摸逻辑，复杂度高 | 4-6h |
| 2 | **设置面板图标选择器** | ❌ 未开始 | 需设计 emoji/图标网格 UI + 持久化 | 2-3h |
| 3 | **字体大小实时调节** | ❌ 未开始 | 需扩展 MethodChannel 传递字体大小 + Kotlin 侧动态设置 EditText textSize | 2h |

### 🟡 中优先级

| # | 任务 | 状态 | 说明 |
|---|------|------|------|
| 4 | **速记条自动隐藏** | ❌ 未开始 | 面板打开后 N 秒无操作自动收起，需 Handler 定时器 |
| 5 | **标签使用开关** | ❌ 未开始 | 关闭后隐藏面板中的标签 Spinner |
| 6 | **面板位置记忆** | ⚠️ 部分完成 | 按钮位置已记忆，面板弹出位置未记忆 |
| 7 | **振动反馈优化** | ❌ 未开始 | 双击、长按、贴边等操作增加 HapticFeedback |

### 🟢 低优先级 / 体验优化

| # | 任务 | 状态 | 说明 |
|---|------|------|------|
| 8 | **面板展开/收起动画** | ❌ 未开始 | 当前直接 addView/removeView，可加入缩放/淡入动画 |
| 9 | **按钮呼吸动画** | ❌ 未开始 | 未操作时微弱缩放提示用户 |
| 10 | **多语言支持** | ❌ 未开始 | 面板和设置面板目前只有中文 |
| 11 | **深色模式适配** | ❌ 未开始 | 面板背景/文字色应随系统主题变化 |
| 12 | **设置面板位置跟随** | ❌ 未开始 | 当前面板固定在按钮上方，超边界时未自适应 |

---

## 二、深度思考：悬浮窗的未来计划

### 2.1 当前架构的边界与瓶颈

```
当前架构（原生 Kotlin Service + 原生 Android View）
├─ 优势：100% 兼容性、无 Flutter 渲染限制、性能最优
├─ 劣势：UI 不灵活、主题同步复杂、开发效率低
└─ 瓶颈：任何 UI 变更都需要修改 Kotlin + XML + MethodChannel 三层
```

**核心矛盾**：原生 View 的可靠性 vs Flutter Widget 的灵活性。

**思考结论**：短期内（1-2 个版本）保持原生架构，中期探索 **混合渲染方案**，长期看 Flutter 团队对 overlay 渲染的支持。

### 2.2 短期规划（v1.25.x ~ v1.26.x）

#### 方向 1：补齐基础体验

**面板大小拖动调节（P5）**
```
方案：右下角添加 24x24dp 拖动手柄（⋮⋮ 图标）
实现：
1. OnTouchListener 监听 ACTION_DOWN（记录初始宽高）
2. ACTION_MOVE 计算 deltaX/deltaY，实时更新 WindowManager.LayoutParams.width/height
3. ACTION_UP 保存到 FloatingSettingsService
4. 最小尺寸限制：200x80dp，最大：屏幕宽度-32dp x 屏幕高度/2
```

**设置面板图标选择器**
```
方案：在设置面板中添加「图标」行，点击展开 emoji 网格（3x4）
预设图标：💡 📝 ✏️ 📌 🔔 ⭐ 🌙 ☀️ 🌸 🔥 💎 🎯
实现：
1. XML 中添加 GridLayout 或 RecyclerView
2. 选中后更新 iconEmoji，立即刷新按钮图标
3. 同步到 FloatingSettingsService
```

#### 方向 2：智能行为

**场景化自动隐藏**
```
触发条件：
- 用户打开全屏应用（游戏、视频）→ 自动缩小到最小
- 用户回到桌面 → 恢复上次大小
- 夜间模式（22:00-07:00）→ 降低透明度到 0.4

技术方案：
- 使用 UsageStatsManager 或 AccessibilityService 监听前台应用
- 或使用定时器检查屏幕方向/亮度
- 风险：隐私权限敏感，需用户明确授权
```

**智能贴边位置**
```
当前：拖到左右边缘贴边
改进：
- 记住用户偏好侧（左/右），下次启动直接出现在偏好侧
- 键盘弹出时自动上移，避免被键盘遮挡
- 横屏/竖屏切换时重新计算位置
```

### 2.3 中期规划（v1.27.x ~ v1.28.x）

#### 方向 3：混合渲染探索

**方案 A：FlutterEngineGroup + TextureWidget（实验性）**
```
架构：
Flutter 主引擎          浮窗独立引擎
    │                       │
    └─ MethodChannel ───────┘
            │
    共享 TextureWidget（SurfaceTexture）
            │
    WindowManager.addView(TextureView)

优势：
- 浮窗 UI 可用 Flutter widget 编写
- 主题、字体、动画完全复用 Flutter 生态
- 性能接近原生（GPU 纹理共享）

风险：
- FlutterEngineGroup 内存占用较高（+20-30MB）
- 双引擎同步复杂
- 在目标设备上可能仍有渲染问题
```

**方案 B：WebView 微型 UI（备选）**
```
架构：
Kotlin Service + WebView（加载本地 HTML/CSS/JS）

优势：
- UI 极度灵活，可用现代前端技术
- 体积小，渲染稳定
- 动画/交互丰富

劣势：
- 与 Flutter 数据同步需额外桥接
- 首次加载有延迟
- 输入法兼容性未知
```

**当前判断**：方案 A 在 Flutter 4.x 稳定后值得尝试，当前设备上风险过高。方案 B 过于激进，不适合日记类应用。

#### 方向 4：数据流增强

**速记 ↔ 日记双向同步**
```
当前：速记保存后可同步到自言自语
改进：
- 用户在自言自语中发送的消息，可一键转为速记
- 速记支持标记「重要」，自动在通知中高亮
- 每日速记汇总：晚上 22:00 生成当日速记摘要通知
```

**语音速记**
```
方案：面板中添加麦克风按钮，长按录音 → 语音识别 → 保存
技术：
- Android SpeechRecognizer API（离线/在线）
- 或集成第三方语音识别 SDK
- 识别结果实时显示在输入框中
```

### 2.4 长期规划（v2.x）

#### 方向 5：生态扩展

**跨设备同步**
```
场景：用户在手机上速记，在平板/PC 上查看
方案：
- 速记数据同步到云端（已有 WebDAV 基础设施）
- 浮窗状态（位置、大小、设置）跨设备同步
- 支持 Wear OS / 手表速记
```

**AI 助手集成**
```
场景：用户速记「明天下午3点开会」，AI 自动提取并创建日程
方案：
- 复用现有 SelfTalkTaskParser，在速记保存时自动解析
- 解析结果通过通知提醒用户
- 支持语音速记的实时 AI 转写和摘要
```

#### 方向 6：架构演进

**目标**：如果 Flutter 团队修复了 overlay 渲染问题，逐步迁移回 Flutter UI。

```
迁移路径：
v1.x：原生 Kotlin Service + 原生 View（当前）
  ↓
v2.0（条件：Flutter 4.x 支持 overlay 渲染）：
  - 浮窗按钮：原生 View（轻量、稳定）
  - 速记面板：Flutter Widget（灵活、美观）
  - 设置面板：Flutter Widget（复用现有代码）
  ↓
v2.5（完整 Flutter）：
  - 全部 UI 用 Flutter
  - 仅保留 Kotlin Service 作为生命周期管理
```

**关键前提**：
- Flutter 引擎支持在 `WindowManager` overlay 中初始化渲染管线
- 或 Google 推出官方的 Flutter overlay 方案
- 预计时间：Flutter 4.x（2027年？）

---

## 三、技术债务与风险

### 当前技术债务

| 债务 | 影响 | 建议处理时间 |
|------|------|-------------|
| Kotlin 代码无单元测试 | 重构风险高 | v1.26 |
| XML 布局硬编码尺寸 | 多设备适配差 | v1.25 |
| MethodChannel 无类型安全 | 参数传递易出错 | v1.26（考虑 Pigeon） |
| 设置面板状态管理分散 | Kotlin 和 Dart 各有一份 | v1.25（统一以 Dart 为准） |

### 已知风险

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| 中国 ROM 限制悬浮窗 | 高 | 核心功能不可用 | 引导用户开启权限，提供无浮窗模式 |
| Android 15 后台限制收紧 | 中 | Service 被杀死 | 前台 Service + 电池优化白名单 + 定期检查 |
| 用户反馈 UI 不美观 | 中 | 使用率下降 | 持续优化，引入现代设计语言 |

---

## 四、下一步行动建议

### 立即执行（本周）
1. **面板大小拖动调节** — 用户最可能提到的缺失功能
2. **修复设置面板位置自适应** — 超边界时调整位置

### 近期执行（本月）
3. **图标选择器** — 提升个性化体验
4. **字体大小调节** — 无障碍需求
5. **深色模式适配** — 跟随系统主题

### 中期执行（下季度）
6. **语音速记 POC** — 验证技术可行性
7. **智能贴边位置** — 记住用户偏好
8. **混合渲染技术调研** — FlutterEngineGroup 可行性验证

---

## 五、附录：相关文件索引

| 文件 | 用途 |
|------|------|
| `android/app/src/main/kotlin/.../FloatingWindowService.kt` | 浮窗核心 Service |
| `android/app/src/main/kotlin/.../FloatingWindowPlugin.kt` | MethodChannel 桥接 |
| `lib/services/native_floating_service.dart` | Dart 侧 MethodChannel 封装 |
| `lib/services/floating_window_service.dart` | 对外 API 层 |
| `lib/services/floating_settings_service.dart` | 设置持久化 |
| `lib/services/floating_notification_service.dart` | 通知同步 |
| `lib/services/floating_permission_service.dart` | 权限管理 |
| `lib/services/quick_note_backup_service.dart` | 外部存储备份 |
| `lib/screens/profile_screen.dart` | 浮窗开关入口 |
| `android/app/src/main/res/layout/floating_*.xml` | 原生 UI 布局 |
