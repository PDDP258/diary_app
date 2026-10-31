# 🔴 事故三次续报：「搜索能搜到，主界面没有」的最终根因

> 2026-10-28 17:00
> 前两份：`INCIDENT-data-loss.md`、`INCIDENT-2-restore-invisible.md`

---

## 一、你提供的三条信息，构成了完整的证据链

| # | 你反馈的现象 | 推出的结论 |
|---|---|---|
| 1 | 打开 App 日记全部变 0 | 读取路径有问题 |
| 2 | **恢复备份显示成功**，统计有数据 | 数据写进去了 |
| 3 | **搜索能搜到并查看**，主界面依旧没有 | **数据层完全正常**，只有主界面这条链路断了 |

第 3 条是关键：搜索页调 `DatabaseService.getAllDiaries()`，主界面读 `DiaryProvider.diaries`。
**同一份数据，直接查得到，走 Provider 得不到** → 问题在 Provider 没被填充。

---

## 二、最终根因：`_ensureInitialized()` 的并发竞态

```dart
// 修复前
static Future<void> _ensureInitialized() async {
  if (_initialized) return;                         // ① 标志要等「整段跑完」才置位
  _prefs = await SharedPreferences.getInstance();   // ② 这里有 await 悬挂点
  await EncryptionService.initialize();             // ③ 又一个 await
  await _loadData();                                // ④ 再一个 await
  ...
  _initialized = true;                              // ⑤ 到这里才置位
}
```

因为 ⑤ 在整段的**末尾**，而 ②③④ 有多个 `await` 悬挂点，所以：

**启动瞬间若有两处并发调用，它们都会看到 `_initialized == false`，于是初始化被执行多遍。**

两遍初始化会**互相覆盖**静态的 `_diaries` / `_moods`：
- A 路径（主界面 `getRecentDiaries`）先进入，跑到一半
- B 路径（搜索页 `getAllDiaries`）也进入，又跑一遍
- 后完成的那一遍把 `_diaries` 覆盖成它自己中途的（可能空的）状态

**为什么偏偏表现为「搜索能搜到、主界面没有」**：

| 路径 | 方法 | 是否 `await _ensureInitialized()` | 结果 |
|---|---|---|---|
| 搜索页 | `getAllDiaries()` | ✅ 会等初始化完成 | 拿到正确数据 |
| 主界面 | `getRecentDiaries()` → `loadRecentDiaries()` | ❌ 只读内存 `_diaries` | 读到被覆盖后的空列表 |

### 修复

经典 async-once 模式 —— 缓存初始化过程本身，让并发调用**共享同一个 Future**：

```dart
static Future<void>? _initFuture;

static Future<void> _ensureInitialized() {
  return _initFuture ??= _doInitialize();   // 只跑一次，并发共享
}
```

初始化失败时清空 `_initFuture` 允许重试，并把错误暴露出来。

---

## 三、同时修掉的三个「静默失败」

这次事故之所以难查，是因为**四处错误都被吞掉了**，每一处单独都足以让界面空白却不报错：

| 位置 | 原来的写法 | 后果 | 现在 |
|---|---|---|---|
| `MainScreen._loadData` | 图片缓存初始化 + 日记加载放同一个 try | **图片缓存失败 → 日记永远不加载** | 拆开，各级独立容错 |
| `DiaryProvider.loadRecentDiaries` | `catch (e) { _error = ...; notifyListeners(); }` | 静默拿空列表 | 打堆栈 + **自动全量兜底** |
| `DatabaseService._loadData` | `catch (e) { print('加载数据失败'); }` | 致命错误降级成日志 | 单独捕获日记失败 + 记录到 `diaryLoadError` |
| `DatabaseService._ensureInitialized` | `if (_initialized) return;` | 并发重复初始化 | `_initFuture` async-once |

---

## 四、本次新增的能力

### 4.1 `hasDiaryDataOnDisk()`

直接检查磁盘上是否存在日记数据（任一 `diary_<id>` 键或旧键 `diaries_data` 非空），**不依赖索引、不依赖解密成功**。

用途：区分「用户真的没有日记」和「有数据但读不出来」。后者绝不能显示「还没有日记」误导用户。

### 4.2 时间线空状态的自愈入口

当 `hasDiaryDataOnDisk() == true` 但列表为空时，时间线会显示：

> ⚠️ 检测到本地仍有日记数据，但未能加载出来
> 　　**[修复并恢复日记]**

点击 → `DatabaseService.recoverFromDisk()` 以磁盘为准重建 → 刷新 Provider。

### 4.3 启动兜底

`loadAllData()` 里：若快速路径拿到空列表但磁盘有数据，自动切全量加载。
`MainScreen._loadData()` 里：加载后仍为空且磁盘有数据，再强制拉一次。

---

## 五、你现在要做的

### 第 1 步：安装修复版 APK（已重新构建）

```
build/app/outputs/flutter-apk/app-release.apk   (89.1 MB)
```

### 第 2 步：打开 App，看时间线

- **能直接看到日记** → 说明竞态修复生效，问题解决。
- **看到「⚠️ 检测到本地仍有日记数据」+「修复并恢复日记」** → 点按钮，会恢复并提示「已恢复 N 篇」。
- **仍然显示「还没有日记」** → 说明 `hasDiaryDataOnDisk()` 返回 false，即磁盘真的读不到数据，进入第 3 步。

### 第 3 步：手机连 USB、开 USB 调试，运行诊断脚本

```
tool/diagnose_diary_data.bat
```

它会直接 grep 手机上的 `FlutterSharedPreferences.xml`，看 `diaries_data` / `diary_*` 键**是否还在**。

**这是决定性证据**：
- 键在 → 数据一定没丢，告诉我输出，我给下一步恢复方案
- 键不在 → 数据目录被清过（卸载重装 / 系统清理），只能走自动备份或云同步

---

## 六、验证证据

| 项目 | 结果 |
|---|---|
| 并发竞态回归测试 | 4 条路径同时访问，**全部读回 3 篇**，id 集合一致 |
| 全量单测 | **180 passed**（新增 4 条：并发初始化 + Provider 同步） |
| `dart analyze` | **0 error，warning 114（与改动前完全一致）** |
| APK 构建 | ✅ 成功，89.1 MB |

新增测试文件：
- `test/concurrent_init_test.dart` —— 锁住并发初始化竞态
- `test/provider_sync_test.dart` —— 锁住「Provider 与数据层必须一致」
- `test/diary_storage_migration_test.dart` —— 锁住「索引缺失必须自愈」

---

## 七、我的复盘

三轮下来，问题从「读不出来」→「恢复了不刷新」→「并发初始化互相覆盖」，**本质是同一个系统性缺陷**：

> **存储层与 UI 层之间没有状态一致性契约。**
> `DiaryProvider` 是手工维护的内存副本，每个调用点都得「记得刷新」；
> 而 `DatabaseService` 有多条初始化和写入路径，谁都可以改 `_diaries` 而不通知任何人。

具体到这次：并发初始化会覆盖数据，Provider 无从知晓。

### 必须做（下一轮，不再往后再拖）

1. **存储层变更广播**：`DatabaseService` 任何写操作后发通知，`DiaryProvider` 订阅自动重载 —— 从机制上消灭「忘记刷新」。
2. **初始化改为显式单例**：`Future<DatabaseService> instance` 模式，把「已初始化」变成类型约束而不是运行期标志。
3. **启动自检**：比对 `diaries_data` 条数 / 分键条数 / 索引条数，不一致自动修复并记录。
4. **数据层失败必须在 UI 可见**：不能再有 `catch → print` 后当作「空数据」的模式。
5. **存储相关改动单独分支单独发版**，不与其他性能优化混在一起。
