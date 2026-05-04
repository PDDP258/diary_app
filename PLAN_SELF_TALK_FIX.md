# 自言自语（Self Talk）修复计划

## 问题描述

用户报告自言自语页面存在以下问题：

| 期望行为 | 实际行为 |
|----------|----------|
| "我"发送 → **右边**（主色气泡） | ✅ 正确 |
| "另一个我"发送 → **左边**（紫色气泡） | ❌ 也在右边 |
| 系统回复"我" → **左边** | ❌ 在右边 |
| 系统回复"另一个我" → **右边** | ❌ 也在右边 |
| AI开关：ON=生成回复，OFF=不回复 | ✅ 基本实现 |

## 问题根因分析

经过代码审查，发现了 **两个关键问题**：

### 问题 1：发送按钮闭包捕获时机错误

在 `_buildInputArea` 中，`_buildSendButton` 接收 `_senderType` 作为参数：

```dart
// self_talk_screen.dart Line 771
_buildSendButton(_senderType, scheme),
```

但 `_buildSendButton` 内部的 `onTap` 闭包捕获的是 `_buildInputArea` 调用时传入的 `senderType` 参数值，这个值是 `_senderType`（即 Widget 的实例变量）。

关键在于：当 `_senderType` 切换后，如果 Widget 没有及时 rebuild，`_buildInputArea` 中的 `_senderType` 仍然是旧值。虽然我们在 `setState` 中更新了 `_senderType`，但还存在以下隐患：

1. **键盘回车提交**（Line 757）：`onSubmitted: (_) => _sendMessage()` —— **没有传 `explicitSenderType`**，依赖 `SharedPreferences` 回退，存在时序问题。

2. `_senderType` 切换时调用 `setState`，但 `_buildInputArea` 的参数是在 `build()` 方法中传递的，理论上每次 rebuild 应该获取最新值。

### 问题 2（核心）：系统回复的 `senderType` 存储与显示逻辑

在 `self_talk_service.dart` 的 `sendMessage` 方法中：

```dart
// Line 60-106
if (senderType != SelfTalkSenderType.system && aiEnabled) {
  // 1. 生成聊天式系统回复
  final chatReply = _generateChatReply(content);
  // 保存为 senderType: SelfTalkSenderType.system
  await DatabaseService.insertSelfTalkMessage(SelfTalkMessage(
    senderType: SelfTalkSenderType.system,
    ...
  ));
  
  // 2. 任务检测回复
  // 保存为 senderType: SelfTalkSenderType.system
  await DatabaseService.insertSelfTalkMessage(SelfTalkMessage(
    senderType: SelfTalkSenderType.system,
    ...
  ));
}
```

系统回复的 `senderType` 保存为 `system`，但是 **没有携带它回复的是谁**的信息。

在 `_buildMessageBubble` 中通过 `_findRepliedUserMessage(index)` 回溯找到被回复的用户消息，这依赖于数据库中的**插入顺序**。如果插入顺序不对或者有多条连续的系统回复，可能导致判断错误。

### 问题 3（潜在）：Row 布局中的 mainAxisSize.min + Align 组合

`_buildMessageBubble` 使用 `Align` + `Row(mainAxisSize: MainAxisSize.min)`，在某些情况下 `Flexible` 包裹的 `Container` 可能不会正确地在 Row 中展开，导致所有气泡表现一致。需要验证布局行为。

## 修复计划

### 步骤 1：添加调试日志

在 `_sendMessage`、`_buildMessageBubble`、`_buildInputArea` 和 `SelfTalkService.sendMessage` 中添加 `debugPrint`，输出每条消息的 `senderType` 值，确认数据流是否正确。

检查点：
- 消息保存到数据库时 `sender_type` 的值
- 从数据库加载后 `senderType` 的值
- 显示时 `isRight` 的判定结果

### 步骤 2：修复发送按钮——确保 senderType 传递正确

修改 `_buildInputArea` 和 `_buildSendButton`，**不再通过闭包捕获 senderType**，而是：

```dart
// 方案：在 _buildSendButton 中直接读取实例变量 _senderType
Widget _buildSendButton(ThemeScheme scheme) {
  // 移除 senderType 参数
  // 在 onTap 回调中直接读取 this._senderType
  onTap: () => _sendMessage(explicitSenderType: _senderType),
}
```

同时修复 `onSubmitted`：
```dart
onSubmitted: (_) => _sendMessage(explicitSenderType: _senderType),
```

### 步骤 3：修复 _buildMessageBubble 布局

将 `Align` + `Row(mainAxisSize.min)` 改为更可靠的布局方式：

**当前方案（有风险）**：
```dart
Align(
  alignment: isRight ? centerRight : centerLeft,
  child: Padding(padding: ..., child: Row(mainAxisSize: min, ...)),
)
```

**修复方案**：使用 `Row` 控制对齐，或改用 `Container` + `margin`：
```dart
Container(
  margin: EdgeInsets.only(
    left: isRight ? 48 : 0,
    right: isRight ? 0 : 48,
  ),
  child: Row(
    mainAxisAlignment: isRight ? MainAxisAlignment.end : MainAxisAlignment.start,
    children: [
      if (!isRight && avatar != null) _buildAvatar(avatar, bgColor, borderColor),
      Flexible(child: _buildBubbleContent(...)),
      if (isRight && avatar != null) _buildAvatar(avatar, bgColor, borderColor),
    ],
  ),
)
```

### 步骤 4：增强系统回复的上下文信息

为 `SelfTalkMessage` 添加 `repliedToSenderType` 字段（可选，不影响向后兼容），使系统回复明确知道自己回复的是谁：

```dart
class SelfTalkMessage {
  // ...existing fields...
  final SelfTalkSenderType? repliedToSenderType; // 系统回复时，记录被回复者的类型
  
  // 新增字段不改变原有 toMap/fromMap 逻辑（nullable，兼容旧数据）
}
```

在 `_buildMessageBubble` 中使用此字段替代 `_findRepliedUserMessage` 回溯查找。

### 步骤 5：清理和验证

- 移除调试日志
- 确保 AI 开关行为正确（ON=生成回复，历史保留；OFF=不生成，历史保留）
- 确认"我"/"另一个我"切换后发送消息位置正确
- 确认系统回复位置正确

## 影响范围

| 文件 | 修改类型 |
|------|----------|
| `lib/screens/self_talk_screen.dart` | 重构消息气泡布局 + 修复发送逻辑 |
| `lib/models/self_talk_message.dart` | 新增 `repliedToSenderType` 字段 |
| `lib/services/self_talk_service.dart` | 添加 repliedTo 上下文 + 调试日志 |
| `lib/services/database_service_native.dart` | 可能需添加新列（向后兼容迁移） |

## 风险评估

- **低风险**：修改集中在 self_talk 模块，不影响日记、日历等其他功能
- **向后兼容**：`repliedToSenderType` 为 nullable 新字段，旧数据不受影响
- **测试建议**：测试新旧消息混合显示、AI 开关切换后发送消息
