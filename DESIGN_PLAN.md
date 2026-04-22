# 自言自语重构 + 速记功能 + PDF导出修复 — 设计文档

> 版本：1.0 | 日期：2026-04-10
> 原则：功能优先，美观其次，用户用得放心

---

## 一、PDF 导出修复（P0，单点故障）

### 1.1 根因
`assets/fonts/` 下实际文件是 `NotoSerifCJKsc-VF.ttf`（可变字体），但代码找的是 `NotoSerifCJKsc-Regular.otf` / `NotoSerifCJKsc-Bold.otf`，文件名完全不匹配，字体加载永远失败。

### 1.2 修复
让代码加载实际存在的 `.ttf` 文件。可变字体一个文件即可支持 Regular + Bold（通过 `pw.TextStyle.fontWeight` 控制）。

修改文件：
- `pdf_export_service.dart`：加载路径改为 `.ttf`
- `font_download_service.dart`：配置名同步改为 `.ttf`

---

## 二、自言自语完全重构（P1）

### 2.1 核心问题
- "我"的消息追加到日记正文 → 数据耦合
- 删除自言自语要改日记 → 责任不清
- Alter Ego 和"我"感知不够强

### 2.2 重构原则
1. **自言自语是完全独立模块**，与日记零耦合
2. 不再把消息内容追加到日记正文
3. 删除自言自语不影响日记
4. 界面直观：一眼看出每条消息的身份

### 2.3 数据模型变更

```dart
// SelfTalkMessage：移除 diaryId，不再关联日记
class SelfTalkMessage {
  final int? id;
  final String date;        // yyyy-MM-dd
  final String content;
  final SelfTalkSenderType senderType;  // me / alterEgo / system
  final String createdAt;
}

// SelfTalkTask：不变，但只通过 messageId 关联 self_talk_messages
class SelfTalkTask {
  final int? id;
  final int messageId;
  final String date;
  final String content;
  final String? deadline;
  final bool isCompleted;
  final String createdAt;
}
```

### 2.4 数据库（版本 9）
- `self_talk_messages`：保留现有字段，不再使用 `diary_id`
- `self_talk_tasks`：不变

### 2.5 服务层关键变更
- `sendMessage()`：不再读写 `Diary` 表
- `deleteMessage()`：只删 `self_talk_messages` + 级联删 `self_talk_tasks`
- 任务解析：仅在 `senderType == me && aiEnabled` 时触发
- Alter Ego：纯聊天，不触发任何 AI 逻辑

### 2.6 UI 身份区分（功能级）

| 身份 | 对齐 | 颜色 | 头像 | 可删除 |
|------|------|------|------|--------|
| 我 | 右侧 | 主题主色 | 无 | ✅ |
| 另一个我 | 左侧 | 紫色 `#7C4DFF` | 🧠 | ✅ |
| 系统 | 左侧 | 灰色 | 📝 | ❌ |

底部输入区：「我」/「另一个我」两个切换按钮，选中态实心背景+粗体，发送按钮颜色随身份变化。

---

## 三、速记功能（P2）

### 3.1 定位
**速记 ≠ 日记**

| 维度 | 日记 | 速记 |
|------|------|------|
| 目的 | 有结构的记录 | 快速捕捉想法 |
| 字段 | 标题、内容、心情、天气、图片、标签 | 只有纯文本 + 可选标签 |
| 操作 | 多步骤 | 打开→打字→保存（2步） |
| 查看 | 时间轴、日历 | 独立速记列表 |

### 3.2 数据模型
```dart
class QuickNote {
  final int? id;
  final String content;      // 纯文本，必填
  final String createdAt;    // ISO8601
  final String? updatedAt;
  final bool isPinned;       // 置顶
  final String? tag;         // 可选单个标签
}
```

### 3.3 数据库
```sql
CREATE TABLE quick_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  is_pinned INTEGER DEFAULT 0,
  tag TEXT
);
```

### 3.4 服务层
- `insert(content, {tag})`
- `update(id, content, {tag})`
- `delete(id)`
- `togglePin(id)`
- `getAll({tag, pinnedFirst})`
- `search(keyword)`

### 3.5 UI
- **速记列表页**：搜索框 + 标签筛选，按时间倒序，置顶优先，左滑删除/右滑置顶
- **速记编辑页**：全屏只有一个多行文本框 + 保存按钮，无标题/心情/图片

### 3.6 与自言自语的区别
- 自言自语：对话形式，有 AI 互动，按天归档
- 速记：笔记形式，无 AI，按条独立，支持搜索和标签

---

## 四、实施顺序

| 优先级 | 任务 | 说明 |
|--------|------|------|
| P0 | PDF 导出修复 | 改字体文件名，立即可用 |
| P1 | 自言自语服务层重构 | 移除日记耦合 |
| P1 | 自言自语数据库迁移 v9 | 升级版本号 |
| P2 | 自言自语 UI 简化 | 强化身份区分 |
| P3 | 速记数据模型 + 数据库 | 新增表和模型 |
| P3 | 速记服务层 | CRUD + 搜索 |
| P3 | 速记 UI | 列表页 + 编辑页 |
| P4 | 速记入口集成 | 在时间轴或其他位置添加入口 |

---

## 五、需要确认的问题

1. **速记入口放哪里？**
   - A. 时间轴页面顶部（推荐）
   - B. 底部导航栏新增 Tab
   - C. FAB 长按菜单

2. **自言自语旧数据怎么处理？**
   - A. 保留旧数据，新逻辑只对新消息生效（推荐）
   - B. 清空所有自言自语数据
   - C. 把旧"我"的消息反向迁移回日记

3. **速记是否参与全局搜索？**
   - A. 先只做速记独立搜索
   - B. 全局搜索同时搜日记和速记

请确认方案，我将按顺序逐步实现。
