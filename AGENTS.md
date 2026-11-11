# AGENTS.md — KidLearn 开发指南

> 本文件面向在本仓库里工作的 AI 编码助手（Codex / Claude Code / Cursor 等），人类维护者同样适用。
> **作用域**：本仓库根目录（KidLearn 插件本体）、`tools/kidlearn/`、`spec/unit/kidlearn_*.lua`。
> KOReader 上游核心代码不属于本项目范围，除非任务明确要求，否则不要改。

**只读一段的话：** 这是一个 Lua（LuaJIT / Lua 5.1）写的 KOReader 插件；题库 JSON 是脚本生成的，不要手改；改完必须跑 `tools/kidlearn/test_plugin.sh`；默认离线，只有 AI 子系统在用户配置后可联网；不要新增依赖；改用户可见行为时同步更新 `README.md`。

---

## 目录

- [1. 项目事实](#1-项目事实)
- [2. 常用命令](#2-常用命令)
- [3. 代码地图与数据流](#3-代码地图与数据流)
- [4. 按任务定位修改点](#4-按任务定位修改点)
- [5. 编码约定](#5-编码约定)
- [6. 内容规则](#6-内容规则)
- [7. 测试要求](#7-测试要求)
- [8. 存档与兼容性](#8-存档与兼容性)
- [9. 完成定义](#9-完成定义)
- [10. 边界与禁止事项](#10-边界与禁止事项)
- [11. 已知坑](#11-已知坑)
- [12. 待确认的产品问题](#12-待确认的产品问题)
- [13. 变更记录](#13-变更记录)

---

## 1. 项目事实

| 项目 | 内容 |
| --- | --- |
| 产品名 | 小小学习家（KidLearn） |
| 形态 | KOReader 插件，目录必须以 `.koplugin` 结尾 |
| 运行环境 | KOReader 的 LuaJIT（Lua 5.1 语义），Kindle 等墨水屏设备 |
| 用户 | 小学 1–6 年级孩子 + 家长；界面为简体中文 |
| 网络 | **默认离线**；只有可选的 AI 出题会联网，没有账号、同步、统计上报 |
| 入口 | `main.lua` → 主菜单「更多工具 → 小小学习家」；Dispatcher 动作 `kidlearn_open` / 事件 `KidLearnOpen` |
| 核心依赖 | 仅 KOReader 自带模块（`ui/widget/*`、`luasettings`、`datastorage`、`dispatcher`、`json`、`logger`、`gettext`；AI 另用 `socket.http`/`ssl.https`/`turbo`） |
| 存档 | `koreader/settings/kidlearn.lua`（`LuaSettings`） |
| 题目 | 语文读 12 册 JSON；数学按 5 个教材版本、1–6 年级由 `core/mathgen.lua` 实时生成；知识点模式读 `data/knowledge/`（cn-math-taxonomy 同步，CC BY-NC 4.0） |
| 测试 | busted，`spec/unit/kidlearn_*.lua`；用 `tools/kidlearn/test_plugin.sh` 链接到 KOReader 后运行 |
| 打包 | `tools/kidlearn/package_plugin.sh` → `install/kidlearn/`（该目录被 gitignore） |

### 关键设计约束

1. **墨水屏优先**：不引入动画、不做逐帧刷新、避免每一题新建窗口；所有页面在同一个 `MainView` 里换 body。
2. **零依赖**：不新增 LuaRocks / C 模块 / 外部二进制；能用 KOReader 自带模块就用自带的。
3. **默认离线**：除 `core/ai_*` 的 AI 出题外，任何路径都不得发起网络请求；AI 必须由用户显式配置和触发，不做后台调用。
4. **儿童内容**：题目和文案要适合对应年级，不能出现超纲、歧义、负面或吓唬孩子的内容。
5. **存档兼容**：老版本 `kidlearn.lua` 必须能平滑升级，不能因为加字段导致孩子丢星星。

---

## 2. 常用命令

> 以下命令在 macOS 模拟器环境验证过。KOReader 源码默认在 `~/GitHub/koreader`，其他位置用 `KOREADER_DIR=/path/to/koreader` 指定。

| 目的 | 命令 |
| --- | --- |
| 初始化 KOReader 子模块（首次） | `cd "${KOREADER_DIR:-$HOME/GitHub/koreader}" && git submodule update --init --recursive` |
| 构建 KOReader 模拟器 | `cd "${KOREADER_DIR:-$HOME/GitHub/koreader}" && ./kodev build` |
| 运行并自动打开插件 | `tools/kidlearn/run_emulator.command` |
| 跑插件全部单测 | `tools/kidlearn/test_plugin.sh` |
| 跑单个单测 | `tools/kidlearn/test_plugin.sh kidlearn_session` |
| 复用构建跑单测 | `KODEV_REUSE_BUILD=1 tools/kidlearn/test_plugin.sh kidlearn_session` |
| 重新生成教材目录 | `python3 tools/kidlearn/build_catalog.py` |
| 重新生成语文题库 | `python3 tools/kidlearn/build_bank.py` |
| 校验语文题库 | `python3 tools/kidlearn/validate_bank.py --all` |
| 校验教材目录 | `python3 tools/kidlearn/validate_catalog.py` |
| 导出家长抽查清单 | `python3 tools/kidlearn/export_review.py`（`--all` / `--per-unit N`） |
| 打包安装包 | `tools/kidlearn/package_plugin.sh` |

注意事项：

- macOS 上 `kodev` 依赖 GNU `getopt`、`bash ≥ 4`、`coreutils`、`ginstall` 等；建议 `brew install bash gnu-getopt coreutils make findutils`。脚本会把 Homebrew 的 `gnubin` 加进 `PATH`。
- `test_plugin.sh` 会把本仓库链接为 KOReader 的 `plugins/kidlearn.koplugin`，并把 `spec/unit/kidlearn_*.lua` 链接进 KOReader；测试名是 **`kidlearn_bank`** 这种形式，不要带 `_spec`。
- `build_bank.py` 生成 1–6 年级题库时必须安装 `pypinyin`：`pip install -r tools/kidlearn/requirements.txt`；`validate_bank.py` 的拼音深度校验同样依赖它。

---

## 3. 代码地图与数据流

```text
main.lua                 插件生命周期：注册菜单与 Dispatcher、开发环境自动打开
ui/mainview.lua          单窗口状态机 + 所有页面布局
ui/widgets.lua           墨水屏小组件（label / textbox / button / card / stat / progress）
core/session.lua         组题、判题、连对、重试、轮次结算
core/catalog.lua         省份/年级/教材/单元目录读取与缓存
core/bank.lua            语文 JSON 的加载、规范化、缓存、抽题
core/knowledge.lua       课标知识点分册/先修图谱加载、缓存、分数/小数判分
core/diagnose.lua        自适应诊断引擎（先修回溯、掌握/不稳/薄弱、学习路径）
core/mathgen.lua         数学题与拓展题生成器（保留二年级人教老生成器 + 通用知识点引擎）
core/progress.lua        存档、每日统计、连续天数、分年级自适应等级、错题本
core/badges.lua          奖章定义与解锁判断
core/ai_config.lua       AI 厂商预设、服务配置、Key 掩码与校验
core/ai_http.lua         LuaSocket/LuaSec + Turbo 的 HTTPS POST
core/ai_client.lua       OpenAI / Anthropic / Gemini 请求与响应
core/ai_variant.lua      变种提示词、严格 JSON 校验、题目标准化
core/ai_bank.lua         独立 AI 变种题库（kidlearn_ai_bank.json）
data/catalog.json        省份/年级/教材/单元目录（生成产物，勿手改）
data/chinese/tongbian/   1–6 年级语文题库（生成产物，勿手改）
data/knowledge/          课标知识点分册题库 + 先修图谱（sync_taxonomy.py 生成，勿手改）
```

### 启动与答题链路

```text
KidLearn:init()
  ├─ Dispatcher:registerAction("kidlearn_open", ...)
  ├─ ui.menu:registerToMainMenu()
  └─ KIDLEARN_AUTOSTART=1 → 1 秒后 showMainView()

MainView:init()
  ├─ Progress.open()           读 koreader/settings/kidlearn.lua
  └─ render_home()

start_session(opts)
  ├─ Session.new{ mode, subject, unit, ... }
  │    ├─ mode="daily"     → build_daily()      语文5 + 数学5
  │    ├─ mode="challenge" → build_challenge()  10 道拓展
  │    ├─ mode="wrong"     → build_wrong()      最多 10 道错题
  │    ├─ mode="ai"        → opts.ai_questions  AI 变种题
  │    └─ 其它             → build_subject()    语文/数学单科 10 题
  └─ render_quiz()

submit_answer(value)
  ├─ Session:submit() → Progress:record_answer() 记分/错题/自适应/连续天数
  └─ render_feedback() → next_question() / finish_session()
```

### 状态机

`MainView.state` 取值：`home`、`unit_select`、`quiz`、`feedback`、`summary`、`wrongbook`、`wrong_detail`、`badges`、`settings`、`ai_settings`、`ai_service_edit`、`ai_bank`、`ai_preview`、`kp_subject`、`kp_select`、`kp_learn`、`diagnose_quiz`、`diagnose_feedback`、`diagnose_result`。
新增页面时：设置 `state` → 改标题 → 用 `set_body(widget)` 换内容，不要新开 `UIManager:show` 的全屏窗口。

---

## 4. 按任务定位修改点

| 想改什么 | 主要文件 | 同步事项 |
| --- | --- | --- |
| 题目难度曲线 / 抽题概率 | `core/session.lua`（`choose_difficulty`） | `core/progress.lua` 的自适应阈值、README 难度表、`kidlearn_session_spec` |
| 每轮题量 / 题型组成 | `core/session.lua`（`build_*`） | README「出题与练习规则」、`kidlearn_session_spec` |
| 语文题目内容 | `tools/kidlearn/build_bank.py` | 重新生成 JSON、跑 `validate_bank.py`、抽查导出 |
| 新增语文题型 | `build_bank.py` + `core/bank.lua` + `ui/mainview.lua`（`SKILL_LABEL`）+ `tools/kidlearn/validate_bank.py`（`VALID_TYPES`） | 题目字段、README 题型表、测试 |
| 新增年级/教材/单元 | `tools/kidlearn/build_catalog.py` → `data/catalog.json` | `core/catalog.lua` 读取、README、`kidlearn_catalog_spec` |
| 新增数学知识点 | `tools/kidlearn/build_catalog.py` 的 `skills` + `core/mathgen.lua` 的 `skill_generators` | `validate_catalog.py`、`kidlearn_mathgen_spec`、README |
| 新增拓展题 | `core/mathgen.lua`（生成函数 + `challenge_generators` + `challenge_units` 上下册） | `kidlearn_mathgen_spec`、README |
| 改星星 / 连对 / 首轮奖励 | `core/progress.lua`（`record_answer` / `record_session`）+ `core/session.lua`（`combo_bonus`） | README 积分表、`kidlearn_progress_spec`、`kidlearn_session_spec` |
| 新增奖章 | `core/badges.lua` | README 奖章表、`kidlearn_progress_spec`（注意「奖章墙 x/10」文案） |
| 改首页 / 设置 / 页面布局 | `ui/mainview.lua` | `kidlearn_ui_spec`、README 使用说明 |
| 改存档字段 | `core/progress.lua`（`SCHEMA_VERSION` + `normalize`） | 迁移逻辑、README 字段表、`kidlearn_progress_spec` |
| 改错题规则 | `core/progress.lua`（`record_wrong` / `record_mastery` / `trim_wrong`） | README 错题本说明、测试 |
| 改 AI 出题 | `core/ai_config.lua` / `ai_client.lua` / `ai_variant.lua` / `ai_bank.lua`、`ui/mainview.lua` | `kidlearn_ai_spec`、`kidlearn_ui_spec`、README AI 说明 |
| 同步知识点题库/图谱 | `tools/kidlearn/sync_taxonomy.py` → `data/knowledge/` | `validate_knowledge.py`、`sync_taxonomy.py --check`、`kidlearn_knowledge_spec`、README 统计 |
| 改知识点加载/判分 | `core/knowledge.lua` | `kidlearn_knowledge_spec`、`kidlearn_session_spec` |
| 改诊断规则 | `core/diagnose.lua` | `kidlearn_diagnose_spec`、README 诊断说明 |
| 改知识点掌握度 | `core/progress.lua`（`knowledge` 字段 + `finalize_kp_session`） | `kidlearn_progress_spec`、README 存档字段表 |
| 改打包 / 发布流程 | `tools/kidlearn/package_plugin.sh` | README 打包说明 |

---

## 5. 编码约定

### Lua

- 目标 **Lua 5.1 / LuaJIT**：不要用 `goto`、整型除法 `//`、位运算符、`utf8` 标准库等 5.2+ 特性。
- 所有模块用 `local M = {}` + `return M`；不要污染全局命名空间。
- 优先 `local function`；模块内部函数不要挂到表上。
- 字符串拼接用 `..`；大量拼接用 `table.concat`。
- 用户可见文案用中文；**代码注释用英文**（与现有文件保持一致）。
- 出错时返回 `nil, err`，调用方用 `InfoMessage` 提示；需要记录时用 `logger.warn` / `logger.info`，不要 `print`。

### KOReader API

- 窗口类继承 `InputContainer` / `WidgetContainer`；全屏页面设置 `covers_fullscreen = true`。
- 刷新用 `UIManager:setDirty(self, "ui")`；不要自己造定时动画。
- 尺寸统一用 `Screen:scaleBySize(...)` 或 `Size.*`，不要写死像素。
- 字体用 `cfont` / `smalltfont` 等 KOReader 内置字体，不要打包字体文件。
- 设置持久化用 `LuaSettings` + `DataStorage:getSettingsDir()`，不要自己拼绝对路径。
- 新增可绑定的动作走 `Dispatcher:registerAction`，不要改 KOReader 的核心菜单。

### UI 约定

- 复用 `ui/widgets.lua` 的 `label` / `textbox` / `button` / `card` / `stat` / `progress`，保持视觉一致。
- 按钮高度不小于 `Size.item.height_large`；儿童点击目标宁大勿小。
- 长文本用 `TextBoxWidget` 自动换行，不要手动按字符数截断（错题列表的 `truncate` 只用于按钮标题）。
- 页面切换必须重置临时状态：`selected`、`number_input`、`feedback`。

### 文案与国际化

- 当前产品定位是中文单语，大部分 UI 文案是硬编码中文，只有菜单名等用了 `gettext`。
- 新增文案时：如果所在文件已使用 `_()`，跟随使用；否则保持硬编码中文并在 README 说明，不要半途引入一半 `_()` 一半硬编码的新风格。

---

## 6. 内容规则

### 语文题库

- **唯一事实来源是 `tools/kidlearn/build_bank.py`**；`data/chinese/tongbian/*.json` 是生成产物，禁止手改。
- 每单元必须 20 题，难度分布 8/8/4（每单元）。六年级下册按教材实际 6 个单元，共 120 题。
- 每题 4 个互不相同的选项，答案唯一，解析至少 4 个字符。
- 拼音必须带正确声调；多音字要用组词限定读音。
- 阅读题必须带 `passage`；短文必须原创或公版，**不得复制教材课文**。
- 题干、选项、解析都要适合对应年级：低年级句子短、词汇常见；高年级再提高抽象度。
- 新增/修改后依次运行：`build_bank.py` → `validate_bank.py --all` → `export_review.py`，并人工抽查导出结果。

### 数学题

- 答案不能为负；除法要整除（有余数除法除外，且余数小于除数）。
- 选项不能重复；干扰项要“像错的”，不能出现明显荒谬或两个正确答案。
- 难度 1–3 要有可感知差异：数域、步骤数、是否需要推理。
- 拓展题必须挂一个核心素养（`competency`），并写清楚适合对应年级的解析。
- 生成器必须接受注入的 `rng`，保证测试可复现。

---

## 7. 测试要求

改动以下任一文件后，**必须**跑完整插件测试（9 个 spec 全绿）：

```bash
tools/kidlearn/test_plugin.sh
```

| 改动 | 至少补/改的测试 |
| --- | --- |
| `core/session.lua` | `kidlearn_session_spec.lua` |
| `core/progress.lua` / `core/badges.lua` | `kidlearn_progress_spec.lua` |
| `core/bank.lua` / 题库格式 | `kidlearn_bank_spec.lua` |
| `core/mathgen.lua` | `kidlearn_mathgen_spec.lua` |
| `core/ai_*.lua` | `kidlearn_ai_spec.lua` |
| `core/knowledge.lua` / `data/knowledge/` | `kidlearn_knowledge_spec.lua` |
| `core/diagnose.lua` | `kidlearn_diagnose_spec.lua` |
| `ui/mainview.lua` | `kidlearn_ui_spec.lua` |

测试规则：

- 不修改断言去“迁就”错误实现；先判断是代码错还是测试过时。
- 数学生成器测试用固定/可注入 `rng`，不要依赖真实随机。
- 存档测试必须在 `before_each` 里删除临时文件（参考现有 `kidlearn_progress_spec`）。
- UI 测试只做 smoke：页面能构建、状态正确、能走完一题，不追求像素级断言。

---

## 8. 存档与兼容性

- 存档结构版本在 `core/progress.lua` 的 `SCHEMA_VERSION`（当前 4；v4 新增 `knowledge` 知识点掌握度）。
- 任何字段变更都必须在 `Progress:normalize()` 里补齐默认值，保证旧存档可读；破坏性变更要写迁移。
- `Progress:reset_progress()` 只清空学习数据（含知识点掌握度），**保留 `settings`**（省份、年级、学期、教材、目标、重试开关）。
- `recent_ids` 最多 30 条；`daily` 保留 90 天；`wrong` 最多 200 条 —— 改这些上限要同步 README。
- 错题存的是整题快照，改题库不会影响已有错题；这是有意设计，不要“顺手”改成只存 ID。

---

## 9. 完成定义

一次改动要同时满足：

- [ ] 行为符合任务描述，没有夹带无关重构。
- [ ] 语法/风格符合 Lua 5.1 与现有代码。
- [ ] 7 个插件测试全绿（贴出结果）。
- [ ] `validate_bank.py --all` 通过（如果动了题库）。
- [ ] `validate_catalog.py` 通过（如果动了目录/教材/知识点）。
- [ ] 用户可见行为变化已同步到 `README.md`。
- [ ] 存档字段变化已考虑旧存档兼容。
- [ ] 没有新增依赖、字体或大文件；AI 子系统之外没有网络请求。
- [ ] 回复中说明：改了什么、为什么、怎么验证、还有什么没做。

---

## 10. 边界与禁止事项

**不要做：**

- 不要修改 KOReader 上游核心代码来“方便”插件；优先用插件 API。
- 不要手改 `data/catalog.json` 和 `data/chinese/tongbian/*.json`（会被重新生成覆盖）。
- 除 AI 出题子系统外，不要引入网络请求、账号、云同步、埋点。
- 不要引入新的 Lua 依赖、C 扩展、字体包或二进制资源。
- 不要提交 `install/` 下的打包产物、截图、抽查清单（已被 gitignore）。
- 不要用中文写死新的调试日志后留在代码里；提交前清理 `print` / 临时开关。
- 不要为了让测试通过而放宽断言或跳过用例。

**需要先确认：**

- 改变计分规则、奖章数量、每轮题量等孩子可感知的产品规则。
- 改变存档结构中的既有字段含义。
- 增加英语等新科目；改动六三/五四学制模型。
- AI 子系统之外任何需要联网的功能。

---

## 11. 已知坑

1. **拓展挑战的题型由 `MathGen.challenge_plan()` 决定**：每轮先按注入的 `rng` 洗牌，再取 10 类，同一轮不重复；如果按单元筛选后不足 10 类，会循环使用这些类型。`generate_challenge()` 仍保留 `index`（确定性测试用）和 `id`（指定题型）两种入口，改这里要同步 `kidlearn_session_spec` 与 `kidlearn_mathgen_spec`。
2. **数学有两套生成路径**：二年级人教仍走 `core/mathgen.lua` 的老 `unit_names`/`generators`；其他年级/版本走 `data/catalog.json` + `skill_generators`。改老路径时不要破坏旧测试，改新路径时同步 `build_catalog.py`。
3. **题库有内存缓存**：`core/bank.lua` 按 `plugin_path|subject|grade|semester|edition` 缓存；运行中改 JSON 不会生效，需要重启或调用 `Bank.clear_cache()`。
4. **拼音依赖不是可选的**：生成 1–6 年级题库需要 `pypinyin`；没装会直接退出，避免生成没有声调的坏数据。
5. **`kodev` 的 PATH 很敏感**：macOS 自带 `getopt` 不兼容，缺少 GNU 工具时会报 `unsupported getopt version`。
6. **独立仓库要链接进 KOReader 才能测**：`test_plugin.sh` 会把本仓库链接到 `plugins/kidlearn.koplugin`，并把 `spec/unit/kidlearn_*.lua` 链接进 KOReader；直接在本仓库运行 `kodev` 不可用。
7. **`install/` 被忽略**：打包 zip、截图、抽查清单都不在版本控制里，clone 后需要自己生成。
8. **模拟器脚本依赖 KOReader 检出**：默认使用 `~/GitHub/koreader`，可用 `KOREADER_DIR` 覆盖；脚本会优先使用 `/usr/local/bin/bash`，再回退到 `/opt/homebrew/bin/bash` 或 `/bin/bash`。
9. **`_meta.lua` 里的插件名用 `gettext` 包裹**，但正文 UI 基本没有 i18n；不要以为改 `_meta.lua` 就能整体翻译。
10. **`Session:finish()` 对错题复习不加完成奖励**：`record_session()` 在 `mode == "review"` 时直接返回 0，这是刻意行为。
11. **`data/catalog.json` 是生成产物**：省份/年级/教材/单元目录改 `tools/kidlearn/build_catalog.py`，不要直接编辑 JSON。
12. **AI Key 是明文**：保存在 `kidlearn.lua`，设置页只做掩码；不要打印 Key、请求体或提示词到日志。
13. **AI 题库是独立文件**：`kidlearn_ai_bank.json`，不要塞回 `kidlearn.lua`，否则普通答题每次 flush 都会重写大文件。
14. **AI 配置文件是可选导入源**：`koreader/settings/kidlearn_ai_config.json` 由 `AIConfig.import_file()` 解析，`Progress.open()` 只在默认存档路径下自动导入；单测传临时存档路径时不会读真实设置目录。导入用内容哈希去重，文件内容变化才覆盖插件内配置。
15. **AI 失败不自动重试**：结构校验失败由用户点「重试」；不要在后台悄悄重复消耗 token。
16. **知识点数据是生成产物**：`data/knowledge/` 由 `tools/kidlearn/sync_taxonomy.py` 从 `~/GitHub/cn-math-taxonomy`（CC BY-NC 4.0）生成，禁止手改；源更新后重跑同步并跑 `validate_knowledge.py` 与 `--check`。
17. **知识点题库也有内存缓存**：`core/knowledge.lua` 按 `plugin_path|subject|grade|semester` 缓存分册、按 `plugin_path|subject` 缓存图谱；改 JSON 后需重启或 `Knowledge.clear_cache()`。
18. **诊断是测评不是练习**：`core/diagnose.lua` 不给星星、不进错题本、不影响自适应与连续天数，只回写知识点掌握度；参数 confirm=2、题量上限 12、回溯深度 ≤3，改这些要同步 README 与 `kidlearn_diagnose_spec`。
19. **kp 会话判题走 `Knowledge.judge`**：带 `topic` 的题（含错题快照）支持分数/小数答案；`MainView:start_session` 是白名单传参，新增会话字段记得同时加到 `Session.new` 调用里。
20. **`MainView` 必须整屏绘制**：它是全屏页面而不是对话框；`paintTo` 先铺满白色背景，否则底层 ReaderUI 会透出来，看起来像浮层。

---

## 12. 待确认的产品问题

> 遇到以下需求，先与维护者确认，不要自行决定。

- 是否需要支持英语等其它科目，或五四学制？
- 是否要做多设备同步或家长端报告？（除可选 AI 外仍为单机离线）
- 拓展挑战是否要改成“每轮随机抽取 10 类”（会改变现有测试与体验）？
- 是否需要把 UI 文案完整国际化（gettext）？
- 是否需要为 Kindle 以外的设备（Kobo、Android）做适配与截图？

---

## 13. 变更记录

| 日期 | 变更 | 原因 |
| --- | --- | --- |
| 2026-11-10 | 建立本文件；重写 README 以匹配实际实现 | 插件已合并回主仓库，需要给后续 AI/维护者一份准确说明 |
| 2026-11-10 | 迁移为独立 Git 仓库，迁入题库工具、测试和截图 | 方便单独发布 GitHub，并保留可复现的开发流程 |
| 2026-11-10 | 支持 1–6 年级、31 省预设、5 个数学教材版本、12 册语文题库 | 家长需要按地区/年级/教材出题 |
| 2026-11-10 | 增加可选 AI 错题变种、多厂商服务配置与独立 AI 题库 | 用变种题强化错题学习 |
| 2026-11-10 | 支持 `kidlearn_ai_config.json` 自动导入 API 地址/Key/模型 | 家长可把配置推到 Kindle，免手填 |
| 2026-11-11 | 同步 cn-math-taxonomy 小学数学/语文知识图谱与题库；新增知识点学习、练习、自适应诊断；存档 v4 增加知识点掌握度 | 按课标知识点先学后练，答错沿先修边找薄弱根因 |
