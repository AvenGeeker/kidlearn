# 小小学习家（KidLearn）

给小学 1–6 年级孩子用的 **KOReader 插件**：在 Kindle 墨水屏上做语文、数学练习。
默认离线、无广告、无账号，学习记录只保存在本机；只有家长主动配置并使用的 AI 出题会联网。

> **打开 KOReader 就能练，一轮 10 题，约 5–10 分钟。** 不收集数据，不要求登录，也不需要手机 App 陪跑。

## 预览

> 以下截图来自 KOReader 600×800 macOS 模拟器，使用演示学习数据；墨水屏实机为黑白显示，布局一致。

<table align="center">
  <tr>
    <td align="center" width="220">
      <a href="docs/screenshots/home.png"><img src="docs/screenshots/home.png" width="180" alt="首页：星星、连续学习和今日进度"></a><br>
      <sub>首页 · 今日挑战入口</sub>
    </td>
    <td align="center" width="220">
      <a href="docs/screenshots/daily-quiz.png"><img src="docs/screenshots/daily-quiz.png" width="180" alt="今日挑战：语文拼音选择题"></a><br>
      <sub>今日挑战 · 四选一答题</sub>
    </td>
    <td align="center" width="220">
      <a href="docs/screenshots/answer-feedback.png"><img src="docs/screenshots/answer-feedback.png" width="180" alt="答对反馈和解析"></a><br>
      <sub>即时反馈 · 星星与解析</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="220">
      <a href="docs/screenshots/wrongbook.png"><img src="docs/screenshots/wrongbook.png" width="180" alt="错题本列表"></a><br>
      <sub>错题本 · 快照与复习入口</sub>
    </td>
    <td align="center" width="220">
      <a href="docs/screenshots/badges.png"><img src="docs/screenshots/badges.png" width="180" alt="奖章墙"></a><br>
      <sub>奖章墙 · 10 枚成长奖章</sub>
    </td>
    <td align="center" width="220">
      <a href="docs/screenshots/ai-preview.png"><img src="docs/screenshots/ai-preview.png" width="180" alt="AI 变种题的家长预览"></a><br>
      <sub>AI 变种 · 家长预览后练习</sub>
    </td>
  </tr>
</table>

---

| 项目 | 现状 |
| --- | --- |
| 适用设备 | Kindle（KOReader），其他 KOReader 设备理论可用 |
| 年级 | 小学 1–6 年级（上下册切换） |
| 省份 | 31 个省级行政区 + “其他/不指定”，用于推荐数学教材 |
| 语文 | 统编版，12 册 × 每单元 20 题，共 **1880 题**（含 96 篇原创短文） |
| 数学 | 人教版、北师大版、苏教版、青岛版、沪教版，**程序生成**，另有 17 类拓展题 |
| 交互 | 四选一 + 数字键盘，不需要中文输入法 |
| 数据 | 本地 `koreader/settings/kidlearn.lua`；可选 AI 配置 `kidlearn_ai_config.json`、AI 题库 `kidlearn_ai_bank.json` |
| 许可 | 代码跟随 KOReader 的 AGPL；题目为原创或公版内容 |

> 开发协作规范见同目录 [`AGENTS.md`](AGENTS.md)；构建 KOReader 本身见 [`doc/Building.md`](../../doc/Building.md)。

---

## 目录

- [预览](#预览)
- [功能](#功能)
- [安装](#安装)
- [使用](#使用)
- [出题与练习规则](#出题与练习规则)
- [积分、连续学习与奖章](#积分连续学习与奖章)
- [AI 错题变种](#ai-错题变种可选联网)
- [数据存储](#数据存储)
- [内容维护：语文题库](#内容维护语文题库)
- [数学出题器](#数学出题器)
- [开发与测试](#开发与测试)
- [代码结构](#代码结构)
- [已知限制与常见问题](#已知限制与常见问题)
- [参与贡献](#参与贡献)
- [许可](#许可)

---

## 功能

- **今日挑战**：语文 5 题 + 数学 5 题，约 5–10 分钟做完一轮。
- **语文练习**：按当前年级/教材的单元或综合练习；拼音、识字、量词、近反义词、句子、积累、阅读。
- **数学练习**：按当前年级/教材的单元或综合练习；口算、乘法口诀、除法、混合运算、单位、时间、搭配、推理等。
- **多年级 / 多教材**：设置里选择省份、年级、学期、语文教材、数学教材；省份会自动推荐常用数学版本，家长仍可手动覆盖。
- **拓展挑战**：每轮从 17 类拓展题中随机抽 10 类（同一轮不重复），覆盖数感、量感、推理意识、几何直观、数据意识、应用意识、创新意识；包含鸡兔同笼、排队、周期、植树、移多补少等经典题型。
- **即时反馈**：答对给星星，答错可再试一次，也可以直接看答案和解析。
- **激励系统**：星星积分、连对奖励、连续学习天数、10 枚奖章、错题本与错题复习。
- **自适应难度**：每个学科独立记录水平，按最近 10 次首次作答的正确率自动升降。
- **AI 错题变种（可选联网）**：配置 OpenAI、DeepSeek、通义千问、Kimi、智谱、豆包、Gemini、Claude、硅基流动、OpenRouter、Ollama 或自定义 OpenAI 兼容服务，从错题生成同知识点变种题；单题 3 道、批量最多 10 道，生成后先给家长预览。
- **家长设置**：切换学期、每日目标（5/10/15/20 题）、答错是否可重试、AI 服务、重置进度。

墨水屏适配：单窗口内切换页面，不做动画，按钮和字号按屏幕缩放，避免频繁整屏刷新。

---

## 安装

### Kindle

1. 用 USB 连接 Kindle。
2. 把 **整个** `kidlearn.koplugin` 文件夹复制到：

   ```text
   /Volumes/Kindle/koreader/plugins/kidlearn.koplugin/
   ```

   最终必须存在：

   ```text
   /Volumes/Kindle/koreader/plugins/kidlearn.koplugin/main.lua
   ```

3. 安全弹出 Kindle，重启 KOReader。
4. 主菜单 → **更多工具** → **小小学习家**。

也可以使用打包脚本生成的 `install/kidlearn/kidlearn.koplugin.zip`，解压后得到同名文件夹，放到上面的位置即可。

### 升级

覆盖 `kidlearn.koplugin` 文件夹不会影响学习记录：记录在 `koreader/settings/kidlearn.lua`；使用过 AI 出题时，变种题库在 `koreader/settings/kidlearn_ai_bank.json`。

### 绑定快捷键（可选）

插件注册了 Dispatcher 动作：

- 动作 ID：`kidlearn_open`
- 事件：`KidLearnOpen`

可以在 KOReader 的「手势管理 / 快捷键」里绑定它，一键打开。

---

## 使用

首页显示总星星、连续学习天数、今日进度和奖章数，并提供：

| 入口 | 说明 |
| --- | --- |
| 今日挑战 | 语文 5 题 + 数学 5 题 |
| 语文练习 | 综合练习或具体单元 |
| 数学练习 | 综合练习、具体单元、拓展挑战 |
| 错题本 | 查看错题、重做单题、复习全部错题、AI 强化、AI 题库 |
| AI 题库 | 查看、预览、练习、删除已生成的 AI 变种题 |
| 奖章墙 | 已获得 / 未解锁奖章及进度 |
| 设置 | 省份、年级、学期、语文教材、数学教材、每日目标、重试开关、AI 出题、重置进度、关于 |

答题流程：选择答案（或数字键盘输入）→ 点「确认答案」→ 立即判题 → 查看解析 → 继续下一题。
答错时如果开启了重试，可以「再试一次」；也可以「看答案」，此时显示正确答案和解析。

---

## 出题与练习规则

一轮固定 10 题，不同入口的组成不同：

| 模式 | 题量 | 组成 |
| --- | --- | --- |
| 今日挑战 | 10 | 语文 5 + 数学 5 交替；数学第 4 题应用题、第 5 题拓展题 |
| 语文练习 | 10 | 指定单元，或按当前年级的单元轮换（综合练习） |
| 数学练习 | 10 | 第 4、8 题拓展题，第 6 题应用题，其余按单元轮换 |
| 拓展挑战 | 10 | 从 17 类中随机抽 10 类，同一轮不重复（可限定单元） |
| 错题复习 | ≤10 | 按最久未复习优先，最多 10 题 |
| AI 强化 | ≤10 | 取最久未复习的 5 道错题，每题 AI 生成 2 道变种；每次重新生成 |

### 难度

- 每道题难度为 1–3；语文题库固定标注，数学由生成器按难度出题。
- 每个“学科 + 年级”有独立的 `adaptive.level`（1–3），初始为 2；切换年级不会串难度。
- 每 10 次**首次作答**结算一次：正确率 ≥ 90% 升一级，≤ 50% 降一级。
- 按当前等级抽题的概率：

  | 等级 | 难度 1 | 难度 2 | 难度 3 |
  | --- | --- | --- | --- |
  | 1 | 70% | 30% | 0% |
  | 2 | 30% | 50% | 20% |
  | 3 | 10% | 40% | 50% |

### 去重

最近答过的 30 道题会记录在 `recent_ids`，抽题时优先避开；题库不够时才允许重复。

---

## 积分、连续学习与奖章

### 星星

| 场景 | 星星 |
| --- | --- |
| 首次答对 | +10 |
| 第二次答对 | +5 |
| 连对 3 题（首次答对） | 额外 +5 |
| 连对 5 题 | 额外 +10 |
| 连对 10 题 | 额外 +20 |
| 完成一轮 | +10 |
| 单轮 10 题全部首次答对 | 额外 +20 |
| 当天第一轮 | 额外 +10 |
| 错题复习首次答对 | +5 |
| 错题复习第二次答对 | +2 |

错题复习不参与连对奖励，也没有「完成一轮 / 满分 / 当天首轮」奖励。

### 连续学习

- 当天首次作答累计达到 **5 题**，记为一个学习日（答错也算）。
- 连续的自然日累加；断一天从 1 重新开始。
- 历史最长连续天数会保留，用于奖章判定。

### 奖章（10 枚）

| 奖章 | 条件 |
| --- | --- |
| 初次闯关 | 完成第一轮练习 |
| 小试牛刀 | 累计答对 20 题 |
| 百题达人 | 累计答对 100 题 |
| 满分王 | 单轮 10 题全部首次答对 |
| 三日坚持 | 连续学习 3 天 |
| 一周之星 | 连续学习 7 天 |
| 识字小博士 | 语文累计答对 50 题 |
| 口算小能手 | 数学累计答对 50 题 |
| 十连对 | 连续 10 题首次答对 |
| 错题克星 | 掌握 5 道错题 |

### 错题本

- 首次答错时把整道题快照存入错题本（含题干、选项、答案、解析）。
- 错题最多保留 200 道，超出时淘汰最久未复习的。
- 对错题本里的题，首次作答答对累计 2 次即视为「掌握」，移出错题本（普通练习和错题复习都算）。
- 因为存的是快照，之后修改题库不会改变已存在的错题。
- 错题详情可点「AI 出 3 道变种」；错题本可点「AI 强化」批量生成。生成结果先进入「家长预览」，确认后再练。
- AI 变种答错会作为普通错题进入错题本；答对不推进原错题的掌握进度。
- 所有生成结果长期保存在独立 AI 题库，可按组删除或清空；清空 AI 题库不会删除错题本。

---

## AI 错题变种（可选联网）

AI 出题未配置时不可用；家长在「设置 → AI 出题」里配置 API Key 和模型后即可使用。调用时只发送当前选中的错题快照（题干、选项、答案、解析、年级/单元/难度），不会发送孩子姓名或设备信息。

支持多个服务配置并选择一个当前服务：

| 预设 | 协议 | 默认接口 |
| --- | --- | --- |
| OpenAI | OpenAI 兼容 | `https://api.openai.com/v1` |
| DeepSeek | OpenAI 兼容 | `https://api.deepseek.com/v1` |
| 通义千问 | OpenAI 兼容 | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| Kimi | OpenAI 兼容 | `https://api.moonshot.cn/v1` |
| 智谱 GLM | OpenAI 兼容 | `https://open.bigmodel.cn/api/paas/v4` |
| 豆包/火山方舟 | OpenAI 兼容 | `https://ark.cn-beijing.volces.com/api/v3` |
| Google Gemini | Gemini 原生 | `https://generativelanguage.googleapis.com/v1beta` |
| Anthropic Claude | Anthropic 原生 | `https://api.anthropic.com/v1` |
| 硅基流动 | OpenAI 兼容 | `https://api.siliconflow.cn/v1` |
| OpenRouter | OpenAI 兼容 | `https://openrouter.ai/api/v1` |
| Ollama（局域网） | OpenAI 兼容 | 家长填写，例如 `http://<电脑IP>:11434/v1` |
| 自定义 | OpenAI 兼容 | 家长填写 |

- 每个配置只需要选预设、填 API Key 和模型；自定义服务还需要填接口地址。
- 「测试连接」会发送一条极短请求，可能消耗少量 token。
- API Key 明文保存在 `koreader/settings/kidlearn.lua`，设置页只显示末 4 位。KOReader 没有系统钥匙串，请使用低额度 Key，并避免在共用设备上保存。
- 公网服务请使用 `https://`；自定义 `http://` 只建议在可信局域网（如 Ollama）使用。
- AI 生成内容不保证完全正确；预览页会显示答案和解析，请家长检查后再让孩子练习。
- 不实现 token/额度统计、套餐自动切换、流式输出、取消请求或生成题编辑；费用由服务商账户管理。
- 阅读题沿用原阅读材料，只改变提问角度和选项；数学和字词题会更换数字、词语或情境。
- 生成结果会做结构校验（题量、四个不重复选项、答案 1–4、解析、阅读材料），但无法自动验证所有学科答案，仍需家长预览。
- 批量模式取最久未复习的 5 道错题，每题 2 道，最多 10 道；每次批量都会新建一组。

### 用配置文件免手填（推荐）

如果不想在 Kindle 上逐项输入 API Key 和模型，可以在电脑上准备：

```text
koreader/settings/kidlearn_ai_config.json
```

Kindle 用 USB 连接后通常就是：

```text
/Volumes/Kindle/koreader/settings/kidlearn_ai_config.json
```

最小配置示例（`preset`、`api_key`、`model` 必填；`base_url` 可省略，省略时用预设默认地址）：

```json
{
  "preset": "deepseek",
  "base_url": "https://api.deepseek.com/v1",
  "api_key": "sk-你的Key",
  "model": "deepseek-chat"
}
```

`preset` 可用值：`openai`、`deepseek`、`qwen`、`kimi`、`zhipu`、`doubao`、`gemini`、`claude`、`siliconflow`、`openrouter`、`ollama`、`custom`。使用第三方中转或自定义 OpenAI 兼容地址时，写 `"preset": "custom"` 并填写 `base_url`。

仓库里有一份模板：[`tools/kidlearn/kidlearn_ai_config.example.json`](../../tools/kidlearn/kidlearn_ai_config.example.json)。复制为 `kidlearn_ai_config.json`、改好三个值，再推到上面的路径即可。**不要把填好 Key 的文件提交到 Git。**

也可以用脚本生成并直接推送到 Kindle（Kindle 挂载点通常是 `/Volumes/Kindle`）：

```bash
python3 tools/kidlearn/make_ai_config.py \
  --preset deepseek \
  --api-key sk-你的Key \
  --model deepseek-chat \
  --mount /Volumes/Kindle
```

不加 `--mount` 时只生成当前目录下的 `kidlearn_ai_config.json`；自定义接口地址用 `--base-url`，自定义显示名用 `--name`，预设用 `--preset custom`。

配置规则：

- 放入文件后重启 KOReader，插件会读入文件并在「设置 → AI 出题」显示「当前 AI 配置来自 …」。
- 文件内容变化后重启会重新导入；导入会**替换**插件里现有的 AI 服务列表，请把要保留的服务都写进同一个文件。
- 导入成功后可继续在插件里临时修改；只要文件内容不再变化，重启不会把临时修改改回去。删除配置文件并重启后，导入记录会清除，之后以插件内设置为准。
- 文件是 JSON，不能写注释；API Key 和 `kidlearn.lua` 一样是明文，请给 Key 设置低额度，并避免放在共用设备或公开仓库。
- 多个服务可以写成数组，并指定当前服务：

```json
{
  "active_id": "aip-2",
  "profiles": [
    { "id": "aip-1", "preset": "deepseek", "api_key": "sk-aaa", "model": "deepseek-chat" },
    { "id": "aip-2", "preset": "qwen", "api_key": "sk-bbb", "model": "qwen-plus" }
  ]
}
```

## 数据存储

进度文件：

```text
koreader/settings/kidlearn.lua
```

可选 AI 配置（推到设置目录后自动导入）：

```text
koreader/settings/kidlearn_ai_config.json
```

可选 AI 题库（只有使用过 AI 出题才会生成）：

```text
koreader/settings/kidlearn_ai_bank.json
```

Kindle 上通常对应 `/mnt/us/koreader/settings/`。`kidlearn.lua` 是 KOReader `LuaSettings` 序列化的 Lua 表，主要字段：

| 字段 | 内容 |
| --- | --- |
| `schema_version` | 存档版本，当前为 3 |
| `total` | 总星星、答题数、正确数、轮数、满分轮数、最高连对、掌握错题数 |
| `by_subject` | 语文 / 数学各自的答题数与正确数 |
| `streak` | 当前连续天数、历史最长、最后学习日 |
| `daily` | 按日期统计的答题数、正确数、星星、轮数；保留 90 天 |
| `wrong` | 错题快照，最多 200 条 |
| `badges` | 已解锁奖章及时间戳 |
| `adaptive` | 旧版各学科难度等级（用于迁移） |
| `adaptive_by_grade` | 各“学科 + 年级”的难度等级与最近 10 次统计 |
| `settings` | 省份、年级、学期、语文教材、数学教材、每日目标、重试开关、AI 服务配置 |
| `recent_ids` | 最近 30 道题 ID |

- **备份 / 换机**：复制 `kidlearn.lua`；如需保留 AI 变种题，再复制 `kidlearn_ai_bank.json`；用配置文件部署 AI 时，再带上 `kidlearn_ai_config.json`。
- **重置进度**：设置 → 重置学习进度。只清空星星、打卡、奖章和错题，保留省份、年级、学期、教材、每日目标、重试开关、AI 服务配置和 AI 题库。AI 题库可在题库页单独清空。
- 存档结构变化时必须在 `core/progress.lua` 的 `normalize()` 里做兼容处理，见 [`AGENTS.md`](AGENTS.md)。

---

## 内容维护：语文题库

语文题不是运行时随机生成的，而是由脚本从人工整理的数据生成 JSON，插件只读 JSON。

```text
tools/kidlearn/build_catalog.py       # 省份 / 年级 / 教材 / 单元目录
tools/kidlearn/build_bank.py          # 语文题目源数据 + 生成逻辑（唯一事实来源）
        │
        ├──> plugins/kidlearn.koplugin/data/catalog.json            运行时目录
        └──> plugins/kidlearn.koplugin/data/chinese/tongbian/
             ├── g1_upper.json ... g6_upper.json                    12 册题库
             └── g1_lower.json ... g6_lower.json
```

常用命令：

```bash
# 1. 修改教材目录后重新生成 catalog.json
python3 tools/kidlearn/build_catalog.py

# 2. 修改语文源数据后重新生成 12 册 JSON
python3 tools/kidlearn/build_bank.py

# 3. 校验题库（结构、选项、答案、拼音、每单元 20 题、难度分布）
python3 tools/kidlearn/validate_bank.py --all

# 4. 校验目录与数学知识点映射
python3 tools/kidlearn/validate_catalog.py

# 5. 导出家长抽查清单（每单元默认 5 题）
python3 tools/kidlearn/export_review.py
python3 tools/kidlearn/export_review.py --all          # 全部导出
python3 tools/kidlearn/export_review.py --per-unit 3   # 自定义抽样数量
```

> 生成拼音需要 `pypinyin`：`pip install -r tools/kidlearn/requirements.txt`。

`export_review.py` 输出到 `install/kidlearn/review/`（该目录被 `.gitignore` 忽略，不随仓库提交）。

### 每单元 20 题的构成

| 题型 | 数量 | 说明 |
| --- | --- | --- |
| 拼音 → 汉字 | 3 | 给拼音和组词提示，选汉字 |
| 汉字 → 拼音 | 3 | 给词语，选加点字读音 |
| 量词（低年级）/ 词语运用（中高年级）、近义词、反义词、句子、词语 | 5 | 各 1 题 |
| 综合词语与句子 | 3 | 近义词、句子、词语各 1 题 |
| 古诗与积累 | 4 | 补全诗句或名句 |
| 阅读理解 | 2 | 共用一段原创短文 |

每个单元固定 20 题，难度为 **8 道难度 1、8 道难度 2、4 道难度 3**。
多数年级每学期 8 个单元；六年级下册按教材实际为 6 个单元，因此该册为 120 题。

### 题目字段

```json
{
  "id": "zh2u-u1-001",
  "unit": "u1",
  "type": "pinyin_to_char",
  "skill": "pinyin",
  "difficulty": 1,
  "answer_mode": "choice",
  "stem": "“kē”对应的汉字是？提示：可以组成“蝌蚪”。",
  "options": ["蝌", "跳", "蚪", "池"],
  "answer": 1,
  "explain": "“蝌”读 kē，可以组词“蝌蚪”。"
}
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 是 | 全局唯一；格式为 `zh{年级}{u/l}-{单元}-{序号}`，如 `zh3u-u1-001` |
| `unit` | 是 | 必须是 `data/catalog.json` 中该年级/学期的单元 ID |
| `type` | 是 | `pinyin_to_char`、`char_to_pinyin`、`measure_word`、`synonym`、`antonym`、`sentence_choice`、`word_choice`、`accumulation`、`reading` |
| `skill` | 是 | 展示用技能标签，如 `pinyin`、`word`、`sentence`、`accumulation`、`reading` |
| `difficulty` | 是 | 1–3 |
| `answer_mode` | 是 | 语文目前都是 `choice` |
| `stem` | 是 | 题干 |
| `passage` | 阅读题必填 | 共用短文 |
| `options` | 是 | 恰好 4 个，互不重复、非空 |
| `answer` | 是 | 正确选项序号，1–4 |
| `explain` | 是 | 解析，至少 4 个字符 |

> ⚠️ **不要直接改生成出来的 JSON**：下次运行 `build_bank.py` 会被覆盖。要改题目，改 `tools/kidlearn/build_bank.py` 后重新生成。

### 校验脚本会检查什么

- `schema_version`、`subject`、`grade`、`semester` 正确；
- ID 跨 12 册全局唯一，单元存在，每单元恰好 20 题；
- 选项恰好 4 个且互不重复，答案在 1–4；
- 同一单元内题干不重复，解析不为空；
- 阅读题必须有 `passage`；
- 拼音题的声调正确（依赖 `pypinyin` 做深度校验）；
- 每单元难度必须为 8/8/4。

---

## 数学出题器

数学题全部在运行时由 `core/mathgen.lua` 生成，不占存储空间，也不会做完。

- 教材版本：**人教版、北师大版、苏教版、青岛版、沪教版**。
- 年级：1–6 年级，上下册；每个版本的单元名、顺序和知识点绑定在 `data/catalog.json`。
- 单元：每个单元绑定 1–3 个 `skills`，出题时在单元内轮换，避免一轮全是同一类题。
- 每个单元有对应的生成器或知识点题库，接收 `difficulty`（1–3）和可注入的 `rng`。
- 综合练习会轮换当前教材的单元；另外按规则穿插应用题和拓展题。
- **拓展题**：`challenge_generators` 注册了 17 个生成器，每个标注一项核心素养（数感、量感、推理意识、几何直观、数据意识、应用意识、创新意识）。

新增数学知识点需要：

1. 在 `tools/kidlearn/build_catalog.py` 给对应单元加上 `skills`；
2. 在 `core/mathgen.lua` 的 `skill_generators` 注册生成器；
3. 运行 `build_catalog.py`、`validate_catalog.py` 和插件测试。

---

## 开发与测试

### 前置条件

- 能构建 KOReader 模拟器（见 [`doc/Building.md`](../../doc/Building.md)）。
- 初始化子模块：

  ```bash
  git submodule update --init --recursive
  ```

- macOS 建议用 Homebrew 安装 `bash`、`gnu-getopt`、`coreutils`、`make`、`findutils`；`run_emulator.command` 里已经预置了 Intel Homebrew（`/usr/local`）路径。

### 运行模拟器

```bash
./kodev build
./kodev run -b -W 600 -H 800 -D 167
```

或直接双击 / 执行：

```bash
tools/kidlearn/run_emulator.command
```

该脚本会设置 `KIDLEARN_AUTOSTART=1`，启动后约 1 秒自动打开插件。也可以手动设置这个环境变量：

```bash
KIDLEARN_AUTOSTART=1 ./kodev run -b -W 600 -H 800 -D 167
```

### 单元测试

插件的测试放在 `spec/unit/kidlearn_*.lua`，运行时会被链接到模拟器的 `spec/front/unit/` 下，所以要用 `front` 套件：

```bash
# 只跑插件的 7 个测试
./kodev test front kidlearn_bank kidlearn_catalog kidlearn_mathgen kidlearn_progress kidlearn_session kidlearn_ui kidlearn_ai

# 只跑一个
./kodev test front kidlearn_session

# 复用已有构建，跳过重新编译
./kodev test -b front kidlearn_session
```

| 测试 | 覆盖内容 |
| --- | --- |
| `kidlearn_bank` | 12 册题库加载、单元覆盖、阅读短文、旧接口兼容 |
| `kidlearn_catalog` | 省份/年级/教材目录、推荐教材、每个知识点的生成校验 |
| `kidlearn_mathgen` | 5 个版本 × 6 个年级 × 12 册单元的大量生成结果校验、拓展题 |
| `kidlearn_progress` | 积分、连对、连续天数、分年级自适应、错题掌握、存档兼容 |
| `kidlearn_session` | 满分一轮、每日挑战、跨年级/教材、错题复习、重试与奖励 |
| `kidlearn_ui` | 首页 / 单元选择 / 省份/年级/教材选择 / 设置 / 奖章 / 错题本 / AI 设置与预览页面 |
| `kidlearn_ai` | 厂商协议、请求构建、响应解析、变种校验、AI 题库、AI 会话与存档兼容 |

### 打包

```bash
tools/kidlearn/package_plugin.sh
# 输出：install/kidlearn/kidlearn.koplugin.zip
```

`install/` 被 `.gitignore` 忽略，打包产物和导出的抽查清单都不会进入仓库。

---

## 代码结构

```text
plugins/kidlearn.koplugin/
├── _meta.lua              # 插件名与描述（KOReader 插件元信息）
├── main.lua               # 入口：菜单注册、Dispatcher 动作、开发环境自动打开
├── core/
│   ├── catalog.lua        # 省份/年级/教材/单元目录读取
│   ├── bank.lua           # 语文题库：加载、校验、缓存、按单元/难度/最近题抽题
│   ├── session.lua        # 会话构建（学科/今日/拓展/错题）、判题、连对、结算
│   ├── progress.lua       # 本地存档、每日统计、连续天数、分年级自适应、错题本
│   ├── badges.lua         # 10 枚奖章的定义与解锁判断
│   ├── mathgen.lua        # 数学题与 17 类拓展题的程序生成器
│   ├── ai_config.lua      # AI 厂商预设、服务配置、Key 校验
│   ├── ai_http.lua        # LuaSocket/LuaSec + Turbo 的 HTTPS POST 传输
│   ├── ai_client.lua      # OpenAI / Anthropic / Gemini 请求与响应
│   ├── ai_variant.lua     # 变种提示词、严格 JSON 校验、题目标准化
│   └── ai_bank.lua        # 独立 AI 变种题库 JSON 存储
├── ui/
│   ├── mainview.lua       # 单窗口状态机：首页/选单元/答题/反馈/总结/错题/AI/奖章/设置
│   └── widgets.lua        # 按钮、卡片、标签、进度条等墨水屏小组件
├── docs/screenshots/      # README 预览截图（600×800）
├── data/
│   ├── catalog.json       # 省份/年级/教材/单元目录
│   └── chinese/tongbian/  # 1-6 年级语文题库（生成产物）
└── README.md

tools/kidlearn/            # 题库构建、校验、抽查导出、打包、模拟器启动
spec/unit/kidlearn_*.lua   # 插件单元测试
```

一次答题的调用链：

```text
main.lua → ui/mainview.lua（状态机）
              ├── core/catalog.lua  读取省份/年级/教材/单元
              ├── core/session.lua  构建题目、判题、连对
              ├── core/bank.lua     语文题读取与抽取
              ├── core/mathgen.lua  数学题生成
              ├── core/progress.lua 记分、存档、错题、自适应
              ├── core/ai_*.lua     可选 AI 配置、请求、变种校验与题库
              └── core/badges.lua   轮次结束时结算奖章
```

---

## 已知限制与常见问题

**菜单里找不到插件？**
确认文件夹名以 `.koplugin` 结尾、`main.lua` 在文件夹根部，然后重启 KOReader。

**中文或拼音显示成方块？**
确认没有删除 `koreader/fonts`；插件依赖 KOReader 的 CJK 字体回退。

**进度没有保存？**
检查 `koreader/settings/` 是否可写。

**想重新开始？**
设置 → 重置学习进度。只清空星星、打卡、奖章和错题；省份、年级、学期、教材、每日目标、重试开关、AI 服务配置和 AI 题库都会保留。

**能多设备同步吗？**
不能。除家长主动使用的 AI 出题外，插件是单机离线的；没有账号、云同步或统计上报。换设备需要手动复制 `kidlearn.lua`，需要保留 AI 变种题时再复制 `kidlearn_ai_bank.json`；部署 AI 配置可复制 `kidlearn_ai_config.json`。

**AI 出题失败怎么办？**
先检查 Wi-Fi、API Key、模型名称和接口地址；用配置文件部署时，确认文件在 `koreader/settings/kidlearn_ai_config.json` 且是合法 JSON，改完文件后重启 KOReader。401 通常是 Key 无效，404 通常是模型或接口不存在，429 通常是请求太频繁或额度不足。AI 返回格式不合格时不会保存，点「重试」即可。

**AI 生成的题一定正确吗？**
不保证。生成后会做结构校验（四个不重复选项、答案序号、解析、阅读材料），但学科答案仍需家长在「家长预览」里检查。AI 出题会消耗服务商 token，批量模式消耗更多。

**多教材的单元名一定和纸质课本完全一样吗？**
目录按公开教材目录整理，并支持家长在设置中选择版本；不同地区、不同年份的印次可能有少量差异。发现不一致时改 `tools/kidlearn/build_catalog.py` 后重新生成。

**为什么语文题不能完全自动扩充？**
语文题需要人工把关（答案唯一、拼音声调、解析难度），所以走「源数据 → 生成 → 校验 → 抽查」流程；数学题才是程序生成的。公开生字表整理出的题库建议家长用 `export_review.py` 抽查一次。

**模拟器脚本报找不到 `getopt` / `make`？**
脚本里写死了 Intel Homebrew 路径（`/usr/local`）。Apple Silicon 请改成 `/opt/homebrew`，或手动把对应 `bin` 目录加进 `PATH`。

**为什么 `./kodev test unit ...` 跑不了？**
模拟器只把 `spec` 链接到 `spec/front` 下，插件测试要按 `front` 套件运行，测试名是 `kidlearn_*`（不带 `_spec`）。

**改了 `data/*.json` 但界面没变化？**
`core/bank.lua` 有内存缓存，重启 KOReader；另外确认改的是 `build_bank.py`，不是只改了生成结果。

---

## 参与贡献

- Bug / 设备兼容问题：请附上 KOReader 版本、设备型号、复现步骤和相关日志。
- 修改代码或题库前，先读 [`AGENTS.md`](AGENTS.md)；题库 JSON 是生成产物，不要直接手改。
- 提交前至少运行插件单测：

  ```bash
  ./kodev test front kidlearn_bank kidlearn_catalog kidlearn_mathgen kidlearn_progress kidlearn_session kidlearn_ui kidlearn_ai
  ```

- 用户可见行为变化时同步更新本 README；新增内容应保持适龄、离线优先和墨水屏友好。

---

## 许可

插件代码跟随 KOReader 仓库的 **AGPL** 许可。
题目内容为原创或使用公版古诗/名句，不复制教材长课文。
