# Skills 快速使用目录

> 共收录 100 个技能，按场景分类，快速定位所需工具。生成于 2026-07-11。

---

## 目录

- [TRAE 官方技能 (9)](#trae-官方技能)
- [学术写作与研究 (8)](#学术写作与研究)
- [前端设计与 UI (15)](#前端设计与-ui)
- [React / 前端开发 (3)](#react--前端开发)
- [代码质量与架构 (8)](#代码质量与架构)
- [Git 与版本控制 (4)](#git-与版本控制)
- [开发流程与方法论 (14)](#开发流程与方法论)
- [文档与写作 (8)](#文档与写作)
- [游戏开发 (3)](#游戏开发)
- [搜索与信息获取 (4)](#搜索与信息获取)
- [部署与运维 (3)](#部署与运维)
- [工具与自动化 (8)](#工具与自动化)
- [会话与流程管理 (5)](#会话与流程管理)
- [其他专用技能 (8)](#其他专用技能)

---

## TRAE 官方技能

TRAE 平台内置的核心能力，覆盖浏览器自动化、代码审查、调试、小程序生成等。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `TRAE-browseruse` | 内置浏览器自动化，支持网页导航、点击、表单填写、截图、数据提取 | 需要在 IDE 内通过内置浏览器执行多步骤交互 |
| `TRAE-browseruse-external` | 通过 Chrome 扩展控制用户本地浏览器 | 用户要求"用我的浏览器打开"等场景 |
| `TRAE-code-mode-orchestrator` | Code Mode 使用指南，并行扇出、条件分支、循环聚合 | 需要在一个脚本中编排多个工具调用 |
| `TRAE-code-review` | 代码审查，检查 MR/PR 或工作区变更，输出结构化反馈 | 审查代码变更的质量、正确性和最佳实践 |
| `TRAE-computer-use` | 控制本地桌面应用 UI（点击、输入、滚动、拖拽） | 需要操作本地桌面应用 UI 界面 |
| `TRAE-computer-use-ptc` | Computer Use 的 PTC 路径版本 | 通过 MCP 服务器控制 Windows 应用 UI |
| `TRAE-debugger` | 科学调试流程：假设→插桩→复现→分析→修复→验证 | 静态分析无法诊断的 Bug，需要运行时调试 |
| `TRAE-generate-mini-app` | 基于 Taro 生成微信/支付宝/抖音等多端小程序 | 用户提出生成/创建小程序的需求 |
| `TRAE-security-review` | 代码安全扫描，检测 SQL 注入、认证缺陷、密钥泄露等 | 审查代码变更中的安全漏洞 |

---

## 学术写作与研究

涵盖论文写作、审稿、文献综述、LaTeX 排版、深度研究等完整学术工作流。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `academic-paper` | 12 智能体论文写作流水线，10 种模式、6 种论文类型、5 种引用格式 | 撰写学术论文、文献综述、修改论文、检查引用格式 |
| `academic-paper-reviewer` | 模拟 5 位独立审稿人（EIC + 同行评审 + Devil's Advocate） | 审阅论文、模拟同行评审、验证修订效果 |
| `academic-pipeline` | 协调 deep-research → academic-paper → academic-paper-reviewer 全流程 | 从零开始完成科研到论文的端到端流程 |
| `deep-research` | 13 智能体深度研究，7 种模式（系统综述、元分析、事实核查等） | 严谨的学术研究、系统文献综述、证据综合 |
| `latex-paper-en` | 英文 LaTeX 论文助手，15+ 模块（编译、润色、去 AI 化等） | 处理已有英文 LaTeX 论文（IEEE/ACM/Springer/NeurIPS） |
| `latex-thesis-zh` | 中文 LaTeX 学位论文助手，GB/T 7714 参考文献、模板识别 | 处理已有中文硕士/博士 LaTeX 学位论文 |
| `paper-audit` | 深度论文审计，5 种模式（quick-audit、deep-review、gate 等） | 审稿人风格批判、提交前检查、PASS/FAIL 门禁决策 |
| `paper-writing` | 基于 UCSB SNL 实验室方法论的五阶段论文写作流水线 | 撰写、修改、编辑或审阅研究论文 |

---

## 前端设计与 UI

从设计参考图生成、品牌套件到代码实现，覆盖完整的前端视觉设计链路。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `frontend-design` | 创建独特的生产级前端界面，避免通用 AI 模板化美学 | 构建有记忆点的 Web 组件、页面或应用 |
| `design-taste-frontend` | 反"AI 味儿"前端技能，自动推断设计方向 | Landing Page、作品集、网站重设计 |
| `design-taste-frontend-v1` | design-taste-frontend 的原始 v1 版本 | 需要精确向后兼容旧版行为 |
| `gpt-taste` | 精英级 UX/UI 与 GSAP 动效工程，Awwwards 级别创意 | 需要打破 AI 生成模板化布局的创意设计 |
| `minimalist-skill` | 极简主义编辑风格，暖色单色调色板、bento 网格 | 高端文档式 Web 界面 |
| `brutalist-skill` | 工业粗野主义 UI，融合瑞士排版与军事终端美学 | 数据密集型仪表板、作品集 |
| `high-end-visual-design` | 教授 AI 设计高端机构级界面，精确字体、间距、阴影 | 生成"15万美元级别机构"设计感 |
| `imagegen-frontend-web` | 生成 premium 网站设计参考图，每个 section 独立出图 | 需要 Landing Page、营销网站设计参考图 |
| `imagegen-frontend-mobile` | 生成 iOS/Android 移动端 App 屏幕设计图和流程 | 需要移动端 App 设计图（仅图像，不写代码） |
| `image-to-code` | 自生成设计图 → 深度分析 → 匹配实现前端代码 | 视觉质量要求高的 Web 前端完整工作流 |
| `ui-ux-pro-max` | UI/UX 设计智能指导，设计系统、组件、无障碍 | 需要 UI 设计、UX 流程、设计系统指导 |
| `web-artifacts-builder` | React + Tailwind + shadcn/ui 创建复杂前端制品 | 构建需要状态管理、路由的复杂前端制品 |
| `dynamic-ui` | 内联展示图表、架构图、对比卡、交互演示 | 让回答更清晰的可视化辅助 |
| `brandkit` | 高端品牌套件图像生成，Logo 概念图、视觉系统 | 需要品牌标识板、视觉系统展示 |
| `redesign-existing-projects` | 将现有网站/应用升级为高级品质设计 | 改进现有项目的视觉设计，不破坏功能 |

---

## React / 前端开发

React 组合模式、性能优化和 React Native 移动端开发最佳实践。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `composition-patterns` | React 组合模式，避免布尔属性膨胀，涵盖 React 19 变更 | 重构存在大量布尔属性的组件、构建组件库 |
| `react-best-practices` | Vercel 出品 React/Next.js 性能优化，65 条规则 8 大类 | 编写、审查或重构 React/Next.js 代码 |
| `react-native-skills` | React Native/Expo 移动端开发最佳实践 | 构建 React Native 应用、优化列表性能 |

---

## 代码质量与架构

模块设计、接口探索、领域建模、架构改进、设计系统等代码质量相关。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `code-review` | 沿"标准+规格"双轴审查代码变更，并行子智能体 | 审查分支、PR 或工作进展中的变更 |
| `codebase-design` | 深度模块设计词汇表，定义模块、接口、深度、接缝 | 设计或改进模块接口、使代码更可测试 |
| `design-an-interface` | "设计两次"原则，并行生成多个接口设计并比较 | 设计 API、探索接口选项、比较模块形态 |
| `design-system-patterns` | 设计令牌、主题切换、组件架构、Figma 同步 | 构建可扩展设计系统、实现主题切换 |
| `domain-modeling` | 构建项目领域模型，记录架构决策（ADR）和通用语言 | 确定领域术语、记录架构决策 |
| `improve-codebase-architecture` | 扫描代码库发现架构深化机会，可视化 HTML 报告 | 发现模块浅层化、耦合等架构摩擦 |
| `ubiquitous-language` | 从对话中提取 DDD 风格通用语言词汇表 | 定义领域术语、构建词汇表 |
| `request-refactor-plan` | 通过用户访谈创建渐进式重构计划，发布为 GitHub Issue | 规划重构、创建重构 RFC、拆分大型重构 |

---

## Git 与版本控制

规范化提交、安全钩子、CLI 参考和合并冲突解决。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `git-commit` | Conventional Commits 规范，自动分析 diff 生成提交信息 | 规范化 git 提交 |
| `git-guardrails-claude-code` | 设置钩子拦截危险 git 命令（push --force、reset --hard 等） | 阻止破坏性 git 操作 |
| `gh-cli` | GitHub CLI 全面参考，覆盖所有命令行操作 | 需要通过命令行进行 GitHub 操作 |
| `resolving-merge-conflicts` | 分析冲突双方变更意图，智能解决 merge/rebase 冲突 | 遇到 merge/rebase 冲突需要解决 |

---

## 开发流程与方法论

从头脑风暴、方案审讯、原型验证到 TDD 实现和 Issue 管理的完整开发流程。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `brainstorming` | 通过协作对话将想法转化为完整设计和规格 | 创建功能、构建组件、添加功能之前 |
| `grilling` | 一步步深入设计树，对方案进行无情压力测试 | 在动手构建前对方案进行压力测试 |
| `grill-me` | grilling 的快捷入口，用户手动触发 | 快速启动审讯会话 |
| `grill-with-docs` | 审讯过程中同步创建 ADR 和术语表 | 需要审讯+同步产出设计文档 |
| `prototype` | 构建一次性原型验证设计（逻辑原型/UI 原型） | 快速验证逻辑正确性或探索 UI 方案 |
| `implement` | 按 PRD/Issue 实现功能，使用 TDD，完成后代码审查 | 有明确的 PRD 或 Issue 需要实现 |
| `executing-plans` | 加载已写好的实现计划，批判性审阅后逐步执行 | 已有实现方案需要在独立会话中执行 |
| `tdd` | 测试驱动开发，遵循"红-绿-重构"循环 | 想要测试驱动开发或需要集成测试 |
| `wayfinder` | 将超大型工作规划为 Issue 地图，逐一解决 | 面对过于庞大的工作，需要分步规划推进 |
| `to-issues` | 将计划/规格/PRD 拆分为可独立领取的 Issue | 将大型计划分解为独立任务 |
| `to-prd` | 将对话内容合成为 PRD 并发布到 Issue 跟踪器 | 将已有讨论整理为正式 PRD 文档 |
| `triage` | 按状态机流转处理 Issue 和外部 PR | 管理 Issue 跟踪器、分类评估 incoming issue |
| `qa` | 交互式 QA 会话，对话方式报告 Bug 并创建 Issue | 报告 Bug、做 QA、对话方式提交 Issue |
| `diagnosing-bugs` | 构建反馈循环（pass/fail 信号）系统化定位根因 | 报告坏了/抛异常/失败了/变慢了 |

---

## 文档与写作

Word 文档操作、文章编辑、写作方法论和 Skill 编写指南。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `docx` | 全面 Word 操作：创建、编辑、读取、转换 .docx | 程序化创建/编辑 Word 文档、提取内容 |
| `docx-creation` | docx-js + pandoc + LibreOffice 高级 Word 创建 | 专业排版、页眉页脚、高级布局 |
| `docx-tools` | 专业 DOCX 工具包：修订清理、版本比较、批量操作 | 清理大量编辑过的 Word 文件、生成对比文档 |
| `edit-article` | 分节确认、逐节重写，改进文章结构、清晰度和文笔 | 编辑、修订或改进文章草稿 |
| `writing-beats` | 写作"利用"阶段——将素材按节拍组织成结构 | 将原始写作素材逐步组织成结构化文章 |
| `writing-fragments` | 写作"探索"阶段——挖掘原始碎片化素材 | 写作前的头脑风暴，收集零散想法 |
| `writing-shape` | 写作"利用"阶段——将素材塑造成文章 | 将素材一次性组织成完整文章 |
| `writing-great-skills` | 编写和编辑 Skill 的参考指南 | 编写或改进 Skill 时参考 |

---

## 游戏开发

Unity/Unreal Engine 游戏开发、ECS 架构和工作室级编码标准。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `game-developer` | 构建游戏系统，Unity/Unreal、ECS、物理、网络、着色器 | 提到 Unity、Unreal Engine、游戏开发时触发 |
| `theone-unity-standards` | 强制执行 TheOne 工作室 Unity 开发标准 | 编写/审查 Unity C# 代码、设置依赖注入 |
| `unity-ecs-patterns` | Unity DOTS 实现指南，ECS、Job System、Burst 编译器 | 实现 Unity 高性能游戏开发 |

---

## 搜索与信息获取

多引擎搜索、一手来源调研和技能发现。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `baidu-search` | 通过百度 AI 搜索 API 获取中文实时信息 | 获取中文实时信息、研究中文主题 |
| `multi-search-engine` | 集成 16 个搜索引擎（7 国内 + 9 国际），无需 API Key | 多引擎并行搜索并聚合结果 |
| `research` | 基于高信任度一手来源（官方文档、源码、规范）调查 | 调研主题、收集文档/API 事实 |
| `find-skills` | 帮助发现和安装来自开放生态的技能包 | 搜索并推荐合适的技能 |

---

## 部署与运维

项目部署、预提交钩子和 Web 应用测试。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `iga-pages` | 将前端和全栈项目部署到 IGA Pages | 部署应用、发布网站 |
| `setup-pre-commit` | 设置 Husky 预提交钩子（lint-staged、类型检查、测试） | 添加预提交钩子、配置代码格式化 |
| `webapp-testing` | 使用 Playwright 测试本地 Web 应用 | 测试前端功能、调试 UI、捕获浏览器状态 |

---

## 工具与自动化

MCP 开发、浏览器桥接、天气查询、GIS 分析等实用工具。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `mcp-builder` | MCP 服务器开发指南，Python (FastMCP) 和 Node/TypeScript | 创建 MCP 服务器以让 LLM 与外部服务交互 |
| `obsidian-vault` | 在 Obsidian 知识库中搜索、创建和管理笔记 | 在 Obsidian 中查找、创建或组织笔记 |
| `kimi-webbridge` | 通过本地守护进程控制用户真实浏览器（带登录态） | 与网站交互、自动化浏览器任务、抓取内容 |
| `weather-china` | 基于中国天气网获取 7 天天气预报，纯 Python 无需 API Key | 查询中国城市天气、穿衣建议 |
| `wizard` | 生成交互式 Bash 向导，引导手动配置流程 | 引导用户完成繁琐的第三方配置、一次性迁移 |
| `digital-avatar-creator` | 创建数字分身/虚拟角色，定义身份、工作流、工具权限 | 创建数字分身、虚拟角色或专业 AI 助手 |
| `arcpy-gis-analysis` | 基于 ArcPy 的 GIS 空间分析，栅格/矢量分析、遥感 | 空间数据处理、遥感分析（NDVI/LST）、自动制图 |
| `redis-development` | Redis 性能优化，数据结构、向量搜索、语义缓存 29 条规则 | 设计 Redis 数据模型、RAG/向量搜索、优化性能 |

---

## 会话与流程管理

对话交接、工作流发现、完整输出和技能路由。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `claude-handoff` | 将对话交接给新的后台智能体 | 上下文窗口即将耗尽或需要分支处理 |
| `handoff` | 将当前会话压缩成交接文档，供另一个 Agent 继续 | 需要将会话状态移交给另一个 Agent |
| `loop-me` | 有状态审讯，识别可被自动化的循环模式 | 设计或发现可委托给 AI 的工作流 |
| `output-skill` | 强制完整代码生成，禁止占位符，处理 token 限制 | 需要穷尽、完整输出的任务 |
| `ask-matt` | 技能路由器，帮助找到适合的流程路径 | 不确定该使用哪个技能时引导选择 |

---

## 其他专用技能

安全审查、教学、技能创建、TypeScript 迁移等专用场景。

| 技能 | 说明 | 适用场景 |
|------|------|----------|
| `security-best-practices` | 按语言进行安全最佳实践审查（Python/JS/TS/Go） | 要求安全审查、安全编码指导 |
| `teach` | 基于最近发展区理论的多轮交互式教学 | 想要学习某个主题，需要多轮教学 |
| `skill-creator` | 创建新 Skill 的强制性工具 | 创建/添加任何新 Skill |
| `skill-vetter` | 安全优先的技能审查协议，检查危险信号 | 安装未知来源的 Skill 之前进行安全审查 |
| `stitch-design-taste` | 为 Google Stitch 生成语义化设计系统文件 | 为 Stitch 屏幕定义设计语言规则 |
| `migrate-to-shoehorn` | 将 `as` 类型断言迁移到 shoehorn 类型安全替代方案 | 替换测试中的 `as` 断言 |
| `scaffold-exercises` | 创建练习目录结构（problem/solution/explainer） | 为课程搭建练习框架、创建练习桩代码 |
| `setup-matt-pocock-skills` | 为工程技能集配置仓库基础设施 | 首次使用其他工程技能之前运行一次 |

---

> 文档路径: `skills-directory/skills-directory.md`