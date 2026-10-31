# 🔴 事故续报：为什么「恢复备份成功」却看不到日记

> 追加于 2026-10-28 16:30
> 前一份报告：`INCIDENT-data-loss.md`

---

## 一、你描述的现象，精确定位了问题层级

> 「恢复备份显示恢复成功，统计信息也有数据，但是在哪都看不到日记」

这句话本身就排除了「数据没恢复」，因为：

| 界面 | 数据来源 | 你的现象 | 说明 |
|---|---|---|---|
| **统计页** | 直接向 `DatabaseService.getAllDiaries()` 查询 | ✅ 有数据 | **数据库里确实有数据** |
| **时间线 / 日历** | 订阅 `DiaryProvider.diaries`（内存缓存） | ❌ 看不到 | 该缓存**没有刷新** |

**同一份数据，直接查数据库能看到，走 Provider 看不到** —— 这只能是缓存没更新，不可能是数据丢失。

---

## 二、真正的 bug（比第一次更接近你的实际遭遇）

`lib/screens/backup_manager_screen.dart` 的本地备份恢复：

```dart
await AutoBackupService.restoreFromBackup(filePath);   // ← 数据层确实恢复了
await _loadBackups();
showSnackBar(Text('恢复成功'));                          // ← 然后就结束了
```

**缺少 `DiaryProvider` 刷新**。数据层把日记写进内存、写进磁盘了，但 UI 订阅的是 Provider 里那份**旧的空列表**，所以：

- 统计页（直接查库）→ 有数字 ✅
- 时间线（读 Provider）→ 空 ❌

对比：**云端导入路径**（`_importCloudBackup`）是有 `await context.read<DiaryProvider>().loadDiaries()` 的，**本地恢复漏了这一步**。

### 顺带发现的两个同源问题

1. **`_isLoading` 成功路径没复位** —— 恢复成功后 `_isLoading` 一直是 `true`，界面会一直转圈。
2. **恢复成功后不返回值** —— 原代码从不 `Navigator.pop(context, true)`，于是调用方 `data_management_screen._showBackupManager` 永远拿不到 `result == true`，也就不会标记「数据已变更」。

---

## 三、本次修复内容

### 3.1 补齐 Provider 刷新（核心）

```dart
await AutoBackupService.restoreFromBackup(filePath);
await _loadBackups();

// 数据层已恢复，但 Provider 里还是旧列表 → 必须重新加载
if (mounted) {
  await context.read<DiaryProvider>().loadDiaries();   // 全量，不是 loadRecentDiaries
}

if (mounted) {
  setState(() => _isLoading = false);                  // 复位 loading
  ScaffoldMessenger.of(context).showSnackBar(...);
  Navigator.pop(context, true);                        // 通知上层数据已变更
}
```

### 3.2 数据加载失败不再被静默吞掉

事故根因之一是 `_loadData()` 里 `try/catch` 把致命错误降级成一行 `print`。现在：

- 日记加载单独 `try/catch`，失败记录到 `DatabaseService.diaryLoadError`
- 用 `debugPrint` + 完整堆栈输出，不再是静默
- 非日记数据（心情/标签等）失败仍可容忍，但与日记分开处理

### 3.3 新增穿透诊断能力

```dart
static Future<bool> hasDiaryDataOnDisk() async
```

**直接检查磁盘上是否存在日记数据**（任一 `diary_<id>` 键或旧键 `diaries_data` 非空），不依赖索引、不依赖解密成功。

这是区分两种「0 篇」的关键：

- **真的没有日记** → 显示引导，正常
- **有数据但读不出来** → 必须提示用户，而不是骗他说「还没有日记」

### 3.4 时间线空状态加了自愈入口

当 `hasDiaryDataOnDisk() == true` 但列表为空时，时间线会显示：

> ⚠️ 检测到本地仍有日记数据，但未能加载出来
> 　　**[修复并恢复日记]**

点一下就调 `DatabaseService.recoverFromDisk()` → 以磁盘为准重建索引 → 刷新 Provider。

---

## 四、你现在要做的（按顺序）

### 第 1 步：装修复后的包，打开 App

如果回到时间线看到「**检测到本地仍有日记数据，但未能加载出来**」+「修复并恢复日记」按钮 → **点它**，日记就回来了。

### 第 2 步：如果时间线还是显示「还没有日记」

说明 `hasDiaryDataOnDisk()` 返回 false，即**磁盘上真的读不到日记数据**了。这时才需要外部工具。

### 第 3 步：用诊断脚本确认磁盘真相

我已准备好 [tool/diagnose_diary_data.bat](tool/diagnose_diary_data.bat)：

1. **手机连 USB、打开「USB 调试」**
2. 双击运行该脚本

它会依次检查：
- 设备连接 / App 是否安装
- `shared_prefs/FlutterSharedPreferences.xml` 是否存在
- **里面 `diaries_data` / `diary_*` 键还在不在**（这是决定性证据）
- 自动备份目录里的备份文件
- 尝试把 prefs 导出到 `tool/recovered/`

**如果脚本显示 `diaries_data` 或 `diary_<id>` 键存在 → 数据一定在，我能帮你恢复。**

### 第 4 步：如果脚本也找不到数据

那说明 App 数据目录被清过（例如卸载重装、系统清理）。剩下的途径：

1. **自动备份**（App 每次启动自动备份，保留 7 份）：
   `Android/data/com.example.diary_app/files/auto_backups/`
2. **云同步**（如果你开过 WebDAV/坚果云）
3. **手机本地备份**（如果有系统级备份或 GC 备份）

---

## 五、验证证据

| 项目 | 结果 |
|---|---|
| 数据层恢复往返测试 | 恢复 3 篇 → 磁盘 `diary_11/12/13` + `diary_index=[13,12,11]` 全部正确落盘 → 模拟重启可读回 3 篇 |
| 全量单测 | **176 passed** |
| `dart analyze` | **0 error** |
| 回归测试 | `test/diary_storage_migration_test.dart`（索引缺失自愈） |

---

## 六、两次事故的共同教训

| 失误 | 说明 |
|---|---|
| **只测内存、不测持久化** | 第一次事故：迁移后内存 OK，重启读不出来。第二次：恢复后内存 OK，UI 不刷新。**两次都是「写入了但读不回来」** |
| **把致命错误降级成日志** | 数据加载失败 = 用户最痛的状态，必须有可见反馈，不能 `print` 后当作「空数据」 |
| **状态一致性缺少约束** | 数据层改了，`DiaryProvider` 不知道。全局缺少「存储变更 → 通知所有消费者」的机制，靠每个调用点自觉刷新，必然漏 |
| **一次改动过多** | B0-2 存储格式变更 + 9 项其它改动混在一起，风险面被放大 |

### 后续必须做（未完成，见我下一轮）

- [ ] **引入存储层变更广播**：`DatabaseService` 每次写日记后发事件，`DiaryProvider` 订阅自动重载 —— 从机制上消灭「忘记刷新」
- [ ] 启动自检：比对 `diaries_data` 条数 / 分键条数 / 索引条数，不一致即自动修复并提示
- [ ] 补「写入 → 重启 → 重读」的端到端测试（本次只补了 1 条，需覆盖增删改全部路径）
- [ ] 存储相关改动单独分支 + 单独包 + 自用一周
