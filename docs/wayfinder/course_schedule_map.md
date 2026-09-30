# Wayfinder 地图：课表功能

> 本地 Markdown 追踪器（项目未配置 issue tracker，按 wayfinder 默认回退）。
> 规则：每个会话最多消化一张票；消化后在「Decisions so far」追加一行；新发现的问题开新票；说不清的进 Fog。
> 词汇表见 /CONTEXT.md；需求见 ../course_schedule_prd.md。

## Notes

- 技术栈：Flutter 3.x + Provider + SQLite（原生）/ SharedPreferences（Web 双端）
- 代码库已回滚至 v1.3.0+130，无日程/提醒/小组件遗留代码
- 每条命令前导：`export PATH="$PATH:/c/WINDOWS/System32/WindowsPowerShell/v1.0:/c/flutter/flutter/bin"`；测试用 `cmd //c "set PROGRAMFILES(X86)=C:\Program Files (x86)&& flutter test --no-pub"`
- ⚠️ 在 WorkBuddy/AI 会话里跑 Flutter 命令要先 `unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY`：环境里注入了指向本地代理的 `http_proxy`，会让 `flutter test` 的 flutter_tester WebSocket 握手失败（报 `Invalid WebSocket upgrade request`）。
- ⚠️ `flutter analyze` 会隐式跑 `pub get` 并重写 `pubspec.lock`；只做检查请用 `dart analyze lib test`（不触发 pub get，也不碰 Windows 插件符号链接）。
- ✅ **不再有 glance_widget 补丁这回事**（2026-09-30）：小组件改为 App 模块内自绘 RemoteViews，`glance_widget` 已从 `pubspec.yaml` 移除。任何 `pub get` 之后**不需要**再跑 `tool/repatch_glance_widget.py`（脚本保留但已无用）。⚠️ 唯一仍需注意的是：**新增/移除原生插件后必须 `flutter pub get`** 以重生成 `GeneratedPluginRegistrant.java`。
- 构建用 `flutter build apk --release --no-pub`。
- ⚠️⚠️ **小组件布局与渲染有硬约束**（2026-09-30 踩到「无法加载小部件」）：RemoteViews 是在**启动器进程**里 inflate / apply 的，框架有两道**运行时**校验 ——
  ① 布局里每个 View 类必须带 `@RemoteView`（`INFLATER_FILTER`）。白名单＝`FrameLayout / LinearLayout / RelativeLayout / GridLayout` ＋ `Button / Chronometer / ImageButton / ImageView / ProgressBar / TextView / ViewFlipper / ListView / GridView / StackView / AdapterViewFlipper / ViewStub`；**`<View>`（分隔线常用）不在里面**，要用 1dp 的 ImageView/TextView 代替。
  ② `setInt(id, "方法名", v)` 的方法必须带 `@RemotableViewMethod`（`getMethod()` 强校验）。`setBackgroundResource` **不带**该注解 → 背景改用官方 API `setImageViewResource`（配 `widget_bg` ImageView 图层）；改颜色用 `setBackgroundColor`（带注解，安全）。
  两条违反都会让桌面显示「无法加载小部件」/「problem loading widget」，而 **App 侧完全看不到异常**（是对方进程在炸）。回归测试：`test/course_widget_layout_test.dart`（6 项）。
- ⚠️ **`--no-pub` 不重生成 Android 插件注册表**：`GeneratedPluginRegistrant.java` 由 `pub get` 阶段生成。**新增/移除原生插件后必须先 `flutter pub get`**，否则 APK 里插件类在但没注册，真机报 `MissingPluginException`。核查：`unzip -p <apk> classes.dex | grep -a -o "<插件类名>" | wc -l`，已注册的通常 ≥2。2026-09-29 加 `flutter_inappwebview` 时踩到。
- 设计遵循 AGENTS.md 屏幕布局规范与主题规范（禁止硬编码颜色）
- 参考资料：`docs/skills_ref/`（wayfinder/to-prd/domain-modeling/design-an-interface/research）

### 教务系统（jwapp）实测契约 —— 2026-09-29 于西北农林科技大学

- 系统：`ehall` + `/jwapp/`（**金智教育**标准产品），hash 路由 SPA
- 采集方式：Edge `--remote-debugging-port=9222` + `tool/cdp.js`（只读 CDP 客户端，含网络录制）。原始响应在 `.capture/`（已 gitignore，含学号姓名，**勿提交**）
- **课表**：`POST /jwapp/sys/wdkbby/modules/xskcb/cxxszhxqkb.do`，body 只需 `XNXQDM=2026-2027-1`
- **学期配置**：`POST /jwapp/sys/wdkbby/modules/jshkcb/cxjcs.do`（一次返回全部 80 个学期：`XN` 学年 / `XQ` 学期号 / `XQKSRQ` 开学日 / `ZZC` 总周数 / `PX` 排序权重 / `SFSY` 是否在用）
- 信封统一为 `{"code":"0","datas":{"<表名>":{"rows":[…]}}}`。**两种失败形态**：CAS 过期回 HTML 错误页（`<title>系统异常</title>` / 403），业务错回 `code != "0"` —— 都必须与「这学期没课」区分开
- `xswpkc.do`（时间待定课）与 `dqzc.do` 实测返回空或异常，**暂未依赖**
- ⚠️ **四个必须小心的坑**（均有单测锁定，详见 `jwapp_course_parser.dart` / `jwapp_semester_parser.dart` 头部注释）：
  1. `SKZC` 位图**长度不固定**（同一次响应里 20 位与 17 位混用）→ 按实际长度解析，不能用学期总周数截断
  2. 调课会把同一时段**拆成多条**（`周3 第1-4节 [1,2,3]` + `[4]`）→ 必须按「课程+周几+节次+地点」合并 weeks 并集，否则课表画出重叠格子
  3. 课程标识**不能用 `KCH`+`KXH`**（同一门课 `01S01` 与 `01` 并存）→ 按「课程名 + 归一化教师」合并
  4. **当前学期不能用 `PX` 判定**（2026-09-29 真机踩到，PD 反馈「0 课 + 开学日错」）：`cxjcs.do` 的 80 行里有一条 `PX=null` 的脏行（`2025-2026-3` 暑假小学期，`SFSY=1`、开学日 `2026-08-31`、总周数 1），把 null 当 0 参与排序会把它选成当前学期 → 课表按 `XNXQDM=2025-2026-3` 查询**返回空**，学期配置也被写成错的开学日。改为**按日期判定**：今天落在 `[开学日, 开学日 + 总周数×7)` 内的学期优先（`JwappSemesterParser.pickCurrent(all, now:)`，`now` 可注入以便单测）
- ⚠️ **fixture 不要做有损裁剪**：`make_jwapp_fixture.js` 原本只留最新 12 条学期，恰好把上面那条毒行截掉了 —— bug 在单测里完全看不见。现在全量保留（80 条）
- ⚠️ 页面上的「列表导出」按钮实测**点击无任何反应**（不发请求、不下载）—— 「用户自己导出文件 → 文件导入」这条零插件路线对本校**不成立**
- fixture 生成：`node tool/make_jwapp_fixture.js`（读 `.capture/` → 脱敏 → 写 `test/fixtures/jwapp/`，含泄漏自检）
- 实现落点：`lib/services/course_import/jwapp/`（解析 + 取数）、`lib/screens/jwapp_login_screen.dart`（WebView 登录）、`lib/screens/jwapp_endpoints_dialog.dart`（选校）、`lib/services/course_import/jwapp_import_source.dart`（接入导入管线）。四个坑 + 桌面/缩放的单测见 `test/jwapp_import_test.dart`（67 个用例）。
- **WebView 内置桌面模式**（2026-09-29 PD 反馈：移动 UA 下课表页显示不正常）：教务系统是面向桌面的 SPA，所以登录页固定用桌面 Chrome UA（`JwappClient.desktopUserAgent`）+ iOS 的 `preferredContentMode: DESKTOP`，并用 `useWideViewPort` 让页面自己的 viewport meta 生效、`supportZoom` 允许双指缩放、`thirdPartyCookiesEnabled` 应对嵌 iframe 的 CAS 登录。设置抽成 `buildJwappWebViewSettings()` 以便单测锁定。
- **↳ 修正（2026-09-30 PD 三次反馈：只能放大不能缩小）**：根因有两层。① `loadWithOverviewMode: true` 会把「铺满宽度」的那个缩放当成**缩放下限**；② 旧脚本往 viewport 里写死 `minimum-scale=0.5`，而手机上看桌面页的铺满缩放约 0.3 —— 最小值比铺满值还大，等于把下限钉死在 0.5。现在 `loadWithOverviewMode` **关掉**，viewport 改由 `JwappClient.buildViewportScript()` 整串重写：布局宽度钉在 `desktopLayoutWidth = 1280`（尊重页面自带的数字宽度），`initial-scale` 按实际算（打开即铺满），`minimum-scale = max(0.15, fit*0.5)`（按实际算，**不写死**），`maximum-scale=5`。6 个单测锁定。
- **取数兜底：学期码查不到课就退回无参重取**（2026-09-29）：`JwappLoginScreen._startImport` 带 `XNXQDM` 取数后若一条记录都没有，自动不带参数重取一次（接口默认返回当前学期）。宁可多一次请求，也不给用户「这学期没课」的错觉。学期配置最终以**课表行里的 `XNXQDM`** 为准（`findByCode`），不依赖 `pickCurrent` 猜得对。

## Decisions so far

- [课表功能 PRD](../course_schedule_prd.md) — 三导入路径统一标准模型；WebView+JS 适配器；腾讯云 OCR；滚动窗口提醒；glance_widget 小组件
- [导入路径调研](../course_schedule_import_research.md) — 三路径成本/覆盖/风险对比，原推荐落地顺序 模板→OCR→教务
- **2026-09-29 PD 决定：OCR 暂缓，不做。** 已写好的 OCR 管线（T9/T10）保留在仓库但不接入 UI，课表页导入菜单只剩 模板 / ICS；M3 整体标 🔒。**注意：PRD `D4`、调研文档、User Story #4/#5 仍写着要做 OCR——这些是历史文本，未改；以本条和 M3 的 🔒 标注为准，重新推进前必须先问 PD。**
- **2026-09-29 PD 决定：先做教务系统（WebView 方案），解析层先行，至少打通西农（西北农林科技大学）。** 落地为 T11（框架）+ T12（西农这一所）。关键取舍：
  - **先纯 Dart 解析层，再插件/登录层** —— 解析能吃 fixture 单测，不依赖真机；插件层做薄（只负责登录 + 取原文）。
  - 实测西农是金智教育 ehall，**回结构化 JSON，不需要 DOM 适配器** —— 这直接推翻了 T11 原设想里「SchoolAdapter JSON schema（Provider/Parser/Timer 三段）」的复杂度：没有 DOM 选择器要配置，适配器退化成「接入点（校名/门户/模块路径/表 key）+ 解析器」，将来加学校大概率只需加一条 `JwappEndpoints` 预设。
  - 取数**只能**在 WebView 内注入 `fetch`（接口要 CAS 登录态，原生 HTTP 带不上 Cookie）；App 只存学校地址，**不存账密**。
  - 登录成功**不做自动探测**，改为手动「读取课表数据」按钮 —— 各校登录流程差异太大，猜不准。
- **2026-09-29 真机反馈后的修正（PD）**：首次真机跑出「0 课 + 开学日错」，根因是 `cxjcs.do` 里 `PX=null` 的脏行被当成排序权重 0。由此确立两条原则：
  - **当前学期按「日期落在学期区间内」判定**，不依赖任何排序字段（`PX` 只在开学日都不可解析时兜底，且 null 排最后）。
  - **学期码只当「取数参数」，不当最终依据** —— 学期配置最终用课表行自带的 `XNXQDM` 反查（`findByCode`），并且带码取不到课时自动退回无参重取。这样即使学期判定再出错，也不至于既丢课表又写错开学日。
- **2026-09-30 PD 真机反馈三条，据此重做（小组件 + 缩放）**：
  - **小组件不再用第三方模板，改成自绘 RemoteViews** —— 模板的布局/文案改不动（`+1 more events` 英文、方形色块），改不出品牌质感；而自绘还能顺手拿到「刷新不依赖 App 进程」。**代价**是多了 ~7 个 Kotlin 文件（渲染 / 提供者 / 开机接收器 / 排期 / Worker / 后台引擎 / MethodChannel），换来的是可控性与可测性。
  - **刷新靠「预计算 + 三层触发」而不是「后台常驻」**：Dart 算好未来 14 天计划交给原生，原生在系统定时（≥30 分钟）/ 开机 / 每日 11 点三个时机重画。**关键判断：小组件的正确性不能依赖 App 进程存活** —— 这是 `updatePeriodMillis=0` 那次踩坑的根本教训。
  - **每日后台任务要「再拉起 Dart」而不是只做原生刷新**：因为课前提醒的滚动窗口（14 天）只有 Dart 会续排。用 WorkManager 而不是广播接收器的 `goAsync()` —— 后者 ~10 秒窗口起不动 Flutter 引擎。
  - **WebView 缩放：`minimum-scale` 必须按实际铺满缩放算**，不能写死。写死 0.5 而实际铺满约 0.3 时，最小值反而把下限钉住 → 只能放大不能缩小。同时 `loadWithOverviewMode` 关掉（它本身就带「铺满即下限」的语义）。
  - **【同日第二轮回】小组件「无法加载小部件」真机复现，根因是违反了两条 RemoteViews 运行时校验**（PD 反馈旧实例 / 删除重加 / 全新添加**三种场景全挂**）：① `<View>` 当 1dp 分隔线 —— `android.view.View` 没有 `@RemoteView`，被 `INFLATER_FILTER` 拒绝；② 根布局 `setInt(..., "setBackgroundResource", ...)` —— 该方法没有 `@RemotableViewMethod`，被 `getMethod()` 拒绝。**关键判断：这类异常抛在启动器进程，App 侧完全不可观测**，所以只能靠「事前把约束写成测试」而不是「事后看日志」——于是新增了 `test/course_widget_layout_test.dart`，把布局标签白名单 + 渲染器 `setInt` 方法名白名单一起锁死。顺带把根容器换成 `FrameLayout` + 背景 ImageView 图层，渲染器**不再有任何反射调用**。
- 节次标签有三种形态：`第1节 08:00-08:45`（剥掉时间取序号）、纯时间（无序号）、`上午/下午` 块词（含义依赖学校作息）——后两种一律退回行序编号，避免硬取错节次

- （暂缓中）OCR 云函数输出契约：`{ok, angle, requestId, tables:[{type,rows,cols,cells:[{r,c,rs,cs,text,confidence}]}]}`，`rs/cs` 由腾讯云的**开区间** `RowBr/ColBr` 相减得到（两侧各有测试锁定）

## Tickets

> 状态：⬜ 未认领 | 🔒 被阻塞 | ✅ 已关闭。缩进表示被谁阻塞。

### M1 里程碑：数据模型 + 手动/模板导入（可用版）

- ✅ **T1「课表数据模型与数据库层」**（2026-09-08 完成）
  产出：`lib/models/course.dart`（Course/CourseSession/SemesterConfig）、`lib/utils/week_parser.dart`（解析/格式化/当前周，22 个单测全过）、原生 SQLite v14 三表 + CRUD、Web SharedPreferences 双端、`CourseProvider` 并在 main.dart 注册。analyze 新代码 0 error。

- ✅ **T2「课表网格视图 + 学期配置页」**（2026-09-08 完成）
  产出：`course_schedule_screen.dart`（7 列周网格、课程块跨节次、周切换、未配置学期引导页）、`semester_settings_screen.dart`（开学日/总周数/节次时间编辑）。「我的」页新增课程表入口。

- ✅ **T3「手动添加/编辑课程」**（2026-09-08 完成）
  产出：`course_edit_screen.dart`（课程信息 + 8 色选择 + 多上课安排编辑弹层，周次输入实时校验）。analyze 0 error，24 测试全过。

- ✅ **T4「Excel/CSV 模板导入」**（2026-09-08 完成）
  产出：`course_import/` 模块（ImportSource 抽象 + ImportDraft + mergeCoursesByName）、`template_import_source.dart`（xlsx via excel 包 + CSV 兼容 GBK）、`course_import_preview_screen.dart` 公共预览页、课表页导入菜单 + 模板说明弹窗（一键复制模板）。新增依赖 excel、charset_converter。OCR 占位 `ocr_import_source.dart` 已预留不进 UI。

- ✅ **T5「ICS 导入」**（2026-09-08 完成）
  产出：`ics_import_source.dart`（VEVENT/RRULE WEEKLY/UNTIL/COUNT/INTERVAL 解析、SUMMARY@地点 约定、节次推断），7 个测试全过。总计 31 测试通过，analyze 0 error。

### M2 里程碑：提醒 + 小组件（好用版）

- ✅ **T6「课前提醒」**（2026-09-08 完成）
  产出：`course_reminder_service.dart`（滚动窗口 14 天调度、inexact 免权限策略、id 命名空间隔离）、设置持久化（开关 + 提前量 5/10/15/30/60 分钟）、课表页提醒设置弹层、CourseProvider 变更自动续排、Manifest 补开机重排接收器。

- ✅ **T7「今日课程桌面小组件」**（2026-09-08 完成，2026-09-30 重做）
  初版用 glance_widget Calendar 模板。**2026-09-30 PD 真机反馈两条，已重做**：① 「开机后还显示昨天的课」——模板 `updatePeriodMillis=0`（系统永不唤醒）+ 只在 App 前台同步；② 「UI 很粗糙」——模板布局/文案写死（方形色块、`+1 more events` 英文、Material 蓝日期块）。
  现方案：**App 模块内自绘 RemoteViews**（`android/.../CourseWidget*.kt`），暖纸手账风、课程色条、进行中/下一节标记、行数随小组件尺寸自适应。刷新三层兜底：系统 `updatePeriodMillis=1800000`（≥30 分钟）→ 开机/应用更新接收器立刻重画 → **每日 11 点 WorkManager** 起无界面 Flutter 引擎跑 Dart 续排提醒窗口 + 重算计划。数据上 Dart 预计算未来 14 天计划（`course_widget_plan.dart`）推给原生落盘，原生按日期查表渲染，**刷新不需要 App 进程**。
  顺带移除 `glance_widget` 依赖 → 「pub 缓存补丁会被 pub get 冲掉」的老坑一并消失。
  **↳ 同日第二轮回（PD 真机：三种场景全挂，桌面显示「无法加载小部件」）**：自绘版违反了两条 RemoteViews 运行时校验 —— ① 拿 `<View>` 当 1dp 分隔线（`android.view.View` 无 `@RemoteView`，被 `INFLATER_FILTER` 拒）；② 根布局背景用 `setInt(..., "setBackgroundResource", ...)`（该方法无 `@RemotableViewMethod`，被 `getMethod()` 拒）。已改为「1dp ImageView 分隔线 + `widget_bg` ImageView 背景图层 + 官方 `setImageViewResource`」，渲染器里**不再有任何反射调用**；并新增 `test/course_widget_layout_test.dart`（6 项）把两条约束写成测试，避免再犯。布局细节见 Notes 的「小组件布局与渲染有硬约束」。

- ✅ **T8「日记联动」**（2026-09-08 完成）
  产出：写日记页日期卡片下方「当日课程」卡片（随所选日期变化、无课自动隐藏、显示节次时间与课程色块）。课程转日程与徽章联动留待日程模块重建（见 Fog）。

### M3 里程碑：OCR 导入 —— 🔒 已暂缓（2026-09-29，PD 决定）

> **做还是不做，由 PD 重新确认后才动。** 代码已写好并留在仓库，但**用户不可达**（导入菜单里没有入口）。
> 恢复入口的三个改动点写在 `course_schedule_screen.dart` 的注释里，原接线版本备份在 `.rollback/ocr-20260929/`。

- 🔒 **T9「腾讯云账号 + OCR 开通 + 云函数中转」**（人工清单，暂缓）
  代码侧已就绪（2026-09-29）：`cloud/ocr-proxy/`（index.js 云函数 + package.json + README 部署清单 + 7 个归一化单测）。
  剩余人工动作（未执行）：注册/实名 → 开通 OCR → 建函数绑运行角色 → 上传代码 → 设 `APP_KEY` → 建函数 URL。

- 🔒 **T10「图片识别导入管线」**（实现完成、未接线，2026-09-29 暂缓）
  代码保留：`lib/services/course_import/ocr/`（ocr_models 双 schema 解析、ocr_grid 合并单元格还原+表头/节次定位、course_cell_parser 单元格语义、ocr_client 压缩+HTTP+配置持久化、ocr_pipeline 归一化为 ImportDraft）、`ocr_import_source.dart`、`ocr_service_settings_dialog.dart`、`test/ocr_import_test.dart`（32 个 fixture 测试）。
  **已摘除的 UI 入口**：课表页导入菜单原「图片识别导入」+「识别服务设置」两项已移除，`_runImport` 的进度弹窗与 `OcrException` 分支一并摘掉——菜单现在只剩 模板 / ICS 两项可用，教务项仍为灰显占位。
  未接云端时引导配置，不硬编码密钥。**新增依赖 0 个**（复用已有 `image` / `http` / `image_picker` / `shared_preferences`）。

### M4 里程碑：教务适配（生态版）

- ✅ **T11「WebView 导入框架 + 适配器格式」**（2026-09-29 完成）
  产出：`lib/services/course_import/jwapp/`（`jwapp_endpoints` 接入点定义 + `jwapp_config` 持久化 + `jwapp_client` 注入脚本与回传解析 + `jwapp_response` 信封拆包 + `jwapp_course_parser` 课表解析 + `jwapp_semester_parser` 学期配置解析）、`jwapp_import_source.dart`（接入 `CourseImportSource` 管线）、`jwapp_login_screen.dart`（`InAppWebView` 登录 + 手动取数）、`jwapp_endpoints_dialog.dart`（选校 / 手填域名）。课表页导入菜单接线 + `_applyJwappResult` 写入学期配置。
  关键结论：**不做 DOM 适配器** —— 西农（金智）回结构化 JSON，适配器 = 接入点 + 解析器。新增依赖 `flutter_inappwebview ^6.1.5`（三路径里唯一要原生插件的）。
  验证：`test/jwapp_import_test.dart` 52 用例全绿；`dart analyze lib test` 0 error；全量 `flutter test` 123 passed。

- 🟡 **T12「首批学校适配」**（进行中 —— 2026-09-29 已收西农一家）
  ✅ 西北农林科技大学（`JwappEndpoints.nwafu`）：真实抓包 fixture 端到端跑通（14 条原始记录 → 3 门课 / 10 个上课段，0 解析告警）。
  ⬜ 其余学校：金智系（同类 ehall）预计只需加一条 `JwappEndpoints` 预设 + 一份 fixture；正方系（另一套产品）需要新写一个 `*_parser`。
  ⚠️ **真机登录链路未验**：解析层全绿，但「WebView 里登录 → 取到真实数据 → 入库」这段要 PD 本人操作 CAS 登录才能验。

## Fog

- **小组件新机制未真机验证（2026-09-30）**：Dart 侧计划生成有 17 个单测、布局/渲染约束有 6 个、viewport 脚本有 6 个，但下面这些只有真机能验：
  ① **小组件能不能正常加载出来**（2026-09-30 第二轮修复后待复验；之前三种场景全挂，根因是 `<View>` 分隔线 + `setBackgroundResource`，见 Decisions）；
  ② 开机后小组件是否**立刻**显示当天（不是等 30 分钟）；
  ③ 每日 11 点的 WorkManager 任务在国产 ROM 上会不会被压（被压的话，提醒窗口就只能靠开 App 续排）；
  ④ 后台无界面引擎能否真的跑起来 —— 它依赖 `DartExecutor.DartCallback(assets, "flutter_assets", FlutterCallbackInformation)` 这套 API，`Log` tag 是 `CourseWidgetBg` / `CourseWidgetWorker`，adb logcat 能直接看；
  ⑤ 小组件在 2×2 / 4×2 等不同尺寸下显示几行是否合适（`rowCapacity()` 按 `OPTION_APPWIDGET_MIN_HEIGHT` 估）。
  若 ④ 起不来：**小组件照常正确**（纯原生重画），只有「长期不开 App 时提醒窗口排空」这个退化。

  ⚠️ **诊断经验**：小组件渲染出问题时，`onUpdate` 里的 `try/catch` **什么都看不到** —— 异常是在**启动器进程** apply RemoteViews 时抛的。所以 PD 拿不到日志时不要靠猜，按顺序核对两项：布局标签是否都在 `@RemoteView` 白名单、`setInt` 的方法是否都带 `@RemotableViewMethod`（`test/course_widget_layout_test.dart` 已把两者锁死）。
- **`flutter_assets` 是硬编码字符串**（`CourseWidgetBackgroundRunner`）：与 `FlutterLoader.findAppBundlePath()` 的默认值一致，但若将来项目自定义了 asset bundle 名，这里要同步改。
- **（暂缓中）OCR 端到端未经真机验证**：Dart 侧管线有 32 个 fixture 测试兜底，但「拍照 → 真腾讯云识别 → 正确入库」这条链路没验过（云函数未部署、UI 入口已摘）。若 PD 决定启用，优先拿东/西/南/北四种版式的课表截图各试一张。
- **教务 jwapp 端到端**：2026-09-29 首次真机验过一轮（PD），暴露出「0 课 + 开学日错」并已修（见 Decisions）。**修复后尚未复验**，需要 PD 再跑一次。复验重点：① 是否导入出正确的 3 门课 / 10 个时段；② 学期配置是否自动带上「2026-09-07 开学、20 周」；③ 桌面模式下页面能否正常缩放；④ 登录态过期时接口回 HTML 错误页，App 有没有给出「登录已失效」而不是当成「这学期没课」；⑤ CAS 登录后被弹到别的域时取数是否仍命中（脚本已用门户 `origin` 拼绝对地址规避）。
- **`cxjcs.do` 裸调用（无参）返回什么没实测过**：真机那一轮学期数据是读出来了（否则不会写错开学日），所以裸调用应该有数据；但教务页面自己调这个接口时是带 `XN=2026-2027&XQ=1` 的。另外 `net_log` 里还有个**无参数**的 `dqxnxq.do`（当前学年学期）—— 那是教务系统自己判当前学期的权威来源，将来若能抓到它的响应样本，可把「按日期推断」升级为「直接问」。
- **教务适配的学校扩展**：目前只有西农一家。金智教育系（`ehall` + `/jwapp/`）理论上是同一套接口，加学校预计只需一条 `JwappEndpoints` 预设 + 一份脱敏 fixture；正方系是另一套产品，得新写解析器。接入点是否要做**云端清单下发 + 本地缓存**（免得发版才能加学校）目前没做——T11 原设想里有，但一家学校还不值得。
- **教务接入点的手填域名风险**：`JwappEndpoints.fromHostInput` 允许用户填任意域名，会去那个域注入脚本。当前无白名单/无校验。真要放开给用户用，得想一下「用户被诱导填恶意域」这个面。
- **（暂缓中）识别服务被白嫖的风险**：云函数 URL + `APP_KEY` 都在客户端，理论上可被逆向提取。当前 `APP_KEY` 只挡「URL 被扫到就被刷额度」，挡不住专门逆向的人。真要上量需换方案（客户端 attestation、按设备发短期令牌、或把额度按用户维度隔离）。
- **一格多课的切分边界**：目前按「同一格出现第二个周次区间」切分，并用「无名块并回上一块」兜底。若真实课表出现「同名课程两组周次分别写在不同格」等形态，需要再收一版规则。
- ~~**glance_widget 缓存补丁（重要，反复踩）**~~ **已消解（2026-09-30）**：`glance_widget` 已从依赖里移除（小组件改自绘 RemoteViews），补丁与 `tool/repatch_glance_widget.py` 都不再需要。保留这段历史是为了记住教训：**依赖一个「要靠打补丁才能编译」的包，代价是每次 `pub get` 都可能炸**，而且它的模板改不出我们想要的质感。真要继续用它，长期方案是升 Flutter ≥3.47 或给上游提 issue。
- **课程转日程 + 课表徽章**：日程/徽章模块随 v1.28 回滚丢失，重建后接入。
- **课表数据 WebDAV 同步**：是否纳入备份体系，量小但表结构要进备份格式版本。
- **多学期/多课表管理**：转专业、双学位、新学期切换的课表并存需求。
- **适配器社区投稿机制**：审核、签名、防恶意 JS（适配器有读用户教务 Cookie 的能力，安全模型要想清楚）。
- **（暂缓中）OCR 用量超免费额度后的策略**：付费资源包 vs 限制次数 vs 引导其他导入路径。
- **软著申请**：不阻塞开发，阻塞上架分发，建议尽早启动（人工事项）。
