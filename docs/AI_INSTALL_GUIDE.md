# 用 AI 助手把「小小学习家」装进 Kindle（保姆级 · AI 可执行教程）

> **这份教程给谁**：想给孩子的 Kindle 装上「小小学习家」（KidLearn）语文数学练习插件，但自己不会越狱、不会装 KOReader 的家长。
> **怎么用**：把**整份文档**发给你的 AI 助手（ChatGPT / Claude / Kimi / DeepSeek / 豆包 / Codex 等），AI 会一步一步带着你做。AI 如果能在你的电脑上执行命令，大部分步骤可以自动完成；你只需要在 Kindle 屏幕上点几下。
> **耗时**：约 30–60 分钟（大头是等 Kindle 重启）。
> **费用**：插件本身免费、默认离线；AI 出题是可选功能，用你自己的 API Key，按服务商计费（一轮通常几分钱到几毛钱）。
>
> - 插件主页：<https://github.com/AvenGeeker/kidlearn>
> - 教程快照日期：**2026-11-14**（越狱方法与固件范围有时效性，AI 执行时请按附录 D 核对最新数据）
> - 下载链接使用「最新 Release」稳定地址，长期有效，不绑定某个版本号。

---

## 目录

- [0. 开始之前](#0-开始之前)
- [1. AI 执行总纲（AI 先读这节）](#1-ai-执行总纲ai-先读这节)
- [2. 第一步：认识你的 Kindle](#2-第一步认识你的-kindle)
- [3. 第二步：越狱（必做）](#3-第二步越狱必做)
- [4. 第三步：安装 KOReader](#4-第三步安装-koreader)
- [5. 第四步：安装「小小学习家」插件](#5-第四步安装小小学习家插件)
- [6. 第五步（可选）：把 AI API 配置推送到 Kindle](#6-第五步可选把-ai-api-配置推送到-kindle)
- [7. 验收清单](#7-验收清单)
- [8. 常见问题 FAQ](#8-常见问题-faq)
- [9. 附录](#9-附录)

---

## 0. 开始之前

### 0.1 需要准备什么

| 物品 | 说明 |
| --- | --- |
| Kindle | 大多数 2013 年后的型号都可以（具体看固件版本，第一步会查） |
| USB 数据线 | **必须能传数据**（很多线只能充电）。插上后电脑没反应先换线 |
| 电脑 | Windows / macOS / Linux 都行，用来下载和拷贝文件 |
| Wi-Fi | 越狱和安装 KOReader 时 Kindle 需要联网 |
| （可选）AI 服务 API Key | 想用「AI 错题变种」才需要；DeepSeek / 通义 / Kimi / 智谱等均可，见第六步 |

### 0.2 怎么把教程交给 AI

把下面这段话 + **本教程全文**一起发给你的 AI（如果 AI 能联网读网页，也可以直接发本文件链接）：

```text
请按照这份《用 AI 助手把小小学习家装进 Kindle》教程，担任我的 Kindle 安装助手。
请遵守教程第 1 节「AI 执行总纲」：逐步执行、每步验证、不编造链接、API Key 保密。
我的电脑系统是：（Windows 11 / macOS / Linux）
我的 Kindle 型号：（不知道就写「不知道」，请带我查）
固件版本：（不知道就写「不知道」）
是否已经越狱 / 装过 KOReader：（没有 / 越狱过 / 都装过）
我要不要 AI 出题：（要，我用 DeepSeek / 先不要，只装插件）
请一步步问我需要的信息，带我把插件装好。
```

> 本文件在线地址：<https://github.com/AvenGeeker/kidlearn/blob/main/docs/AI_INSTALL_GUIDE.md>

### 0.3 你和 AI 的分工

- **AI 负责**：查资料、做判断、下载文件、解压、执行电脑命令、生成配置文件、排错。
- **你负责 Kindle 上的操作**：看设置页面、点屏幕、在搜索栏输入命令、打开「书」、重启。AI 无法替你点 Kindle 屏幕，它会把每一步说清楚。
- **纯聊天 AI**（没有终端权限）：AI 会生成完整命令和文件内容，你复制粘贴执行，再把结果告诉它。效果一样。

### 0.4 总流程

```text
第一步  认识设备（型号 / 固件 / USB 模式）
   ↓
第二步  越狱（必做；不越狱装不了 KOReader）
   ↓
第三步  安装 KOReader（KPM 一条命令，或手动拷贝）
   ↓
第四步  安装「小小学习家」插件（拷一个文件夹）
   ↓
第五步  （可选）推送 AI API 配置（免去在 Kindle 上手填 Key）
   ↓
验收    做一轮「今日挑战」，星星正常入账
```

已经越狱并装好 KOReader 的用户：直接从[第四步](#5-第四步安装小小学习家插件)开始。

### 0.5 风险提示（越狱前必读）

- 越狱 = 获得运行第三方软件的权限，**不改变 Kindle 原有功能**：原系统还在，买的书照常看。
- 最大的风险是**固件被自动升级**：新固件可能封堵越狱漏洞。所以越狱前要先做第一步的「填满存储」保护；现代越狱方法成功后会**自动屏蔽更新**。
- **不要自行「恢复出厂设置」**，可能丢越狱甚至卡在初始化。出问题先问社区（KindleModding Discord / Reddit r/kindlejailbreak）。
- 建议先把 Kindle `documents` 文件夹里的重要文档备份到电脑。
- 本教程全部使用官方开源工具，不涉及盗版内容。

---

## 1. AI 执行总纲（AI 先读这节）

**角色**：你是一名耐心的 Kindle 安装助手。目标：帮用户把 KOReader 与 KidLearn 插件装进 Kindle，可选推送 AI 配置文件。全程用中文解释，每步只给一小段指令，等用户确认结果再继续。

**执行模式**：

- 你能在用户电脑上执行终端命令、读写文件 → 优先替用户做（下载、解压、拷贝、生成 JSON），Kindle 屏幕操作交给用户。
- 你是纯聊天模式 → 生成完整命令 / 文件内容让用户复制执行，并请用户回报输出。

**入口判断**：先问清「是否已越狱、是否已装 KOReader」。已越狱 → 跳过第二步；已装 KOReader → 跳过第三步；都没有 → 从头开始。

**硬性规则**：

1. 逐步执行。每步都有「验证」，验证通过才继续；**不要假设成功**。
2. **不编造下载链接**，只用本教程附录 A 列出的官方链接。链接失败就重试 / 换网络，不要虚构镜像站。
3. **不凭猜测选越狱方法**。按第二步决策表核对；拿不准就抓取 `jailbreaks.json` + `models.json`（机器可读）或让用户用官方向导。固件太新无方法时，明确告知「暂不支持」并停止，不要乱试工具。
4. **API Key 保密**：不要在对话里复述完整 Key（展示时掩码：前 3 位 + `****` + 后 4 位）；Key 只写入 `kidlearn_ai_config.json`；提醒用户使用低额度 Key、不要上传到网盘 / git / 群聊。
5. 每次 USB 拷贝文件前，确认用户**已退出 KOReader**（KOReader 运行时插 USB 可能崩溃）。
6. 不跳过越狱；不做恢复出厂、降级固件、手动刷机等危险操作。
7. 路径必须**实际探测**（Kindle 卷名 / 盘符 / 挂载点），不要假设 `E:` 或 `/Volumes/Kindle`。
8. 用户的 Kindle 是 MTP 设备（不出现盘符）时，改用 MTP 方案（见 2.3），不要反复让用户「打开 E 盘」。
9. 同一步骤连续失败 2 次 → 停下来按 FAQ 排错或建议社区求助，不要盲目重试。
10. 完成后按第 7 节验收清单逐项确认。

**信息收集清单**（缺什么问什么）：

| 信息 | 哪里查 | 用途 |
| --- | --- | --- |
| 电脑操作系统 | 问用户 | 选择命令 |
| Kindle 型号 / 序列号前 8 位 | Kindle：⋮ → 设置 → 设备选项 → 设备信息 | 选越狱方法 |
| 固件版本（如 `5.18.2`） | 同上 | 选越狱方法 |
| 内部版本号（括号里 10 位数字） | 同上 | 仅 Shadow 需要 |
| 能否注册亚马逊账号 | 尝试注册 | 部分方法要求可注册 |
| 锁屏有无广告 | 看锁屏 | AdBreak 仅适用广告版 |
| USB 模式（有无盘符） | 插上电脑看 | 选拷贝方案 |
| AI 服务商 / Key / 模型 | 问用户 | 第五步（可选） |

---

## 2. 第一步：认识你的 Kindle

### 2.1 查型号与固件（在 Kindle 上）

1. 主页点 **⋮（三个点）→ 设置 → 设备选项 → 设备信息**。
2. 记下三项：
   - **序列号**（前 8 位就够，如 `G000PP05…`）；
   - **固件版本**：「Kindle」后面那串数字加点，如 `5.16.2.1.1`、`5.18.2`；
   - **内部版本号**：括号里的 10 位数字（只有 Shadow 方法需要）。
3. 较新固件会直接显示型号名称（如「Kindle Paperwhite (11th Generation)」）；老固件只有序列号，用下表对照，或让 AI 查 `models.json` 精确匹配。

### 2.2 常见型号速查表

序列号规则：`G` 开头的序列号取**第 4–6 位**为设备码（如 `G000PP…` → `0PP` → PW4）；很老的型号（数字/字母开头）取第 3–4 位。完整对照见 <https://kindlemodding.org/models.json>。

| 设备码（示例） | 代号 | 通俗名称 | 年份 |
| --- | --- | --- | --- |
| `0G1` `0G5` `0KB` … | PW3 | Paperwhite 3 | 2015 |
| `0PP` `0T1` … | PW4 | Paperwhite 4（第 10 代） | 2018 |
| `1PX` `1LG` `1Q0` … | PW5 | Paperwhite 5（第 11 代） | 2021 |
| `349` `346` `33X` … | PW6 | Paperwhite 6（第 12 代） | 2024 |
| `0WF` `10L` … | KT4 | Kindle 10（入门版） | 2019 |
| `22D` `23A` `25T` … | KT5 | Kindle 11（2022 入门版） | 2022 |
| `3L5` `3L6` … | KT6 | Kindle（2024 入门版） | 2024 |
| `27J` `2BL` … | KS | Scribe（2022，大屏手写） | 2022 |
| `3V0` `3V1` … | KS2 | Scribe（2024） | 2024 |
| `3H9` `3H4` … | CS | Colorsoft（彩色） | 2024 |
| `0WQ` `11L` … | KOA3 | Oasis 3 | 2019 |
| `1B` `20` `24` …（老格式） | PW | Paperwhite 1 | 2013 |
| `54` `2A` …（老格式） | KV | Voyage | 2014 |

### 2.3 判断 USB 连接模式（重要）

用数据线把 Kindle 连上电脑（解锁 Kindle 屏幕）：

- **USB 大容量存储模式**（老型号 / 老固件）：电脑出现一个名为 **Kindle** 的盘。
  - macOS：Finder 与 `/Volumes/Kindle`
  - Windows：「此电脑」里出现盘符（如 `E:`）
  - Linux：自动挂载到 `/media/<用户名>/Kindle` 或 `/run/media/<用户名>/Kindle`
- **MTP 模式**（2022 年及以后的第 11 代+ 机型，尤其固件 5.18.x 之后）：**不出现盘符**。
  - Windows：资源管理器出现「Kindle」便携设备（能打开看 `Internal storage`，但没有盘符）
  - macOS：Finder 无反应 → 安装 **OpenMTP**（<https://openmtp.ganeshrvel.com/>，或 `brew install --cask openmtp`）
  - Linux：现代文件管理器（Nautilus / Dolphin）可直接打开；命令行用 gio / gvfs

AI 探测命令：

```bash
# macOS
ls /Volumes
system_profiler SPUSBDataType 2>/dev/null | grep -i -A3 kindle
```

```powershell
# Windows（PowerShell）
Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -match 'Kindle' } | Format-Table FriendlyName, Class, Status
```

```bash
# Linux
lsblk -o NAME,LABEL,SIZE,MOUNTPOINT
gio mount -li 2>/dev/null | grep -i -B2 -A6 kindle
```

**MTP 设备的拷贝方式**：后文所有「复制到 Kindle」的步骤，改用 OpenMTP（macOS）/ 资源管理器拖拽（Windows）/ 文件管理器（Linux）。AI 先把文件在电脑本地准备好，用户拖到对应目录。**目标路径不变**（`koreader/plugins/…`、`koreader/settings/…`）。

### 2.4 本教程的路径约定

| 系统 | 大容量存储挂载点（示例，以实际探测为准） | MTP 方案 |
| --- | --- | --- |
| macOS | `/Volumes/Kindle` | OpenMTP |
| Windows | `E:` | 资源管理器便携设备 |
| Linux | `/media/$USER/Kindle` 或 `/run/media/$USER/Kindle` | 文件管理器 / gio |

后文命令用 `$KINDLE` 指代 Kindle 根目录，**AI 必须替换成实际探测到的路径**。

### 2.5 越狱前保护：防止固件自动升级

原理：越狱需要联网，而亚马逊可能后台下载新固件封堵漏洞。**把存储填满（只剩 50–90 MB）**，更新包就下载不下来。

1. Kindle 打开**飞行模式**。
2. 插上电脑，检查 Kindle **根目录**：如有 `update*.bin`、`update.bin.tmp.partial` 之类文件，**删掉**（这是已下载的更新包）。
3. 填满存储，只剩 **50–90 MB** 可用：
   - 大容量存储模式：从 <https://github.com/bastianmarin/Kindle-Filler-Disk> 下载填充脚本（Windows 用 `Filler.ps1`，macOS/Linux 用 `Filler.sh`），放到 Kindle 根目录运行：

     ```powershell
     # Windows：在 Kindle 盘符目录里执行
     powershell -ExecutionPolicy Bypass -File .\Filler.ps1
     ```

     ```bash
     # macOS / Linux：在 Kindle 挂载目录里执行
     chmod +x Filler.sh && ./Filler.sh
     ```

   - MTP 模式：脚本不适用，手动拷入大文件（视频、安装包等）直到只剩 50–90 MB（可参考 <https://github.com/Crosunt223/Kindle-Filler-Disk/tree/main/MTP>）。
4. **验证**：Kindle 设置 → 设备选项 → 设备信息，剩余存储在 50–90 MB 左右。
5. 之后可以关飞行模式、连 Wi-Fi（越狱需要）。存储已满，更新装不进来。
6. **越狱成功后**再删除填充文件（`fill_disk` 文件夹或你拷的大文件）释放空间；现代越狱方法已自动屏蔽更新。

> Shadow 方法（3.5）例外：Kindle 全程不联网，不需要填充文件（仍建议开飞行模式）。

---

## 3. 第二步：越狱（必做）

### 3.1 选择越狱方法

**首选（人类）**：浏览器打开官方向导 <https://kindlemodding.org/jailbreak-wizard.html>，输入序列号前 8 位、固件版本、能否注册、有无广告，向导会给出唯一推荐。

**AI 自动判断**：抓取两个机器可读 JSON（实时更新）：

- <https://kindlemodding.org/jailbreaks.json>：各方法支持的型号、固件区间、是否要求注册/广告版；
- <https://kindlemodding.org/models.json>：序列号 → 型号。

匹配规则与向导一致：型号在 `models` 中；`registration=true` 的方法要求设备可注册；`ads=true` 的方法要求广告版；固件落在某条 `firmwares` 规则的 `[min, max]` 内（注意 `outliers.accepted/denied` 例外）；按数组顺序取第一个命中。

**快照决策表**（2026-11-14 核对；日期已过或固件不在表内时，务必改查上面的 JSON / 向导）：

| 固件范围 | 适用型号（代号） | 首选方法 | 教程小节 |
| --- | --- | --- | --- |
| 5.6.1.1 – 5.16.3（含 5.16.5） | PW、PW2、KV、KT2、PW3、KOA、KT3、KOA2、PW4、KT4、KOA3、PW5、KT5、KS | WinterBreak2 | 3.4 |
| 5.16.3 – 5.19.5 | PW4、KT4、KOA3、PW5、KT5、KT6、PW6、CS、KS、KS2 | SpiderCat | 3.2 |
| 5.17.1 – 5.20.2 | PW5、KT5、KT6、PW6、CS、KS、KS2 | Véra | 3.3 |
| 5.19.4 – 5.19.6 | KS、KS2、CS、PW6、KT6（MTP 机型） | Shadow | 3.5 |
| 5.18.1 – 5.18.5（仅广告版；PW4/KT4 仅 5.18.1） | PW4、KT4、KOA3、PW5、KT5、KS、KT6、PW6 | AdBreak | 3.6 |
| 5.18.1 – 5.19.2（需可注册；KT4/PW4 仅 5.18.1） | KT4、PW4、KT5、PW5 | SpringBreak | 3.6 |
| 很老固件 / K2、DX、K3、K4、Touch、PW1 | 老设备 | NiLuJe 传统越狱 | 3.6 |

> 多个方法同时适用时以官方向导为准（其优先级：WinterBreak2 → SpiderCat → Véra → Nosebleed → Sanctuary → WinterBreak → SpringBreak → Shadow → AdBreak）。下面四个分支覆盖绝大多数设备。

**通用前提**（除注明外）：

- 已完成 2.5 的填充保护（Shadow 除外）；
- Kindle 已连 Wi-Fi（SpiderCat / Véra / WinterBreak2 需要联网；Shadow 不需要）；
- 过程中不要断网、不要手动重启；
- 出现「应用程序错误 / application error」弹窗一律忽略，不影响越狱。

### 3.2 分支 A：SpiderCat（固件 5.16.3–5.19.5，最常见）

原理：一本特制的「书」，打开后自动执行越狱脚本。

1. 电脑下载越狱书：

   ```bash
   # macOS / Linux
   curl -L --retry 3 -o spidercat.azw3 "https://kindlemodding.org/spidercat/spidercat.azw3"
   ```

   ```powershell
   # Windows PowerShell
   Invoke-WebRequest -Uri "https://kindlemodding.org/spidercat/spidercat.azw3" -OutFile spidercat.azw3
   ```

2. 把 `spidercat.azw3` 复制到 Kindle 的 **`documents`** 文件夹（MTP 设备用 OpenMTP / 资源管理器拖入 `Internal storage/documents`）。
   - 也可以不用电脑：Kindle 浏览器直接访问 <https://kindlemodding.org/spidercat> 下载。
3. 安全弹出 Kindle，**保持 Wi-Fi 连接**。
4. 在 Kindle 书库找到 SpiderCat 这本「书」，打开。
5. 等待：可能先空白几秒 → 屏幕顶部开始向下滚文字。**不要操作屏幕**，忽略错误弹窗。
6. 出现「Restarting Kindle」后 Kindle 自动重启。**验证：重启完成即越狱成功。**
7. 排错：最后一行是 `abort:no-firm` → 型号/固件不匹配，回 2.1 重查；完全无反应 → 确认 Wi-Fi 已连，重试一次。

### 3.3 分支 B：Véra（固件 5.17.1–5.20.2，较新设备）

原理：Kindle 浏览器下载两本「书」，先在一本书里设置指定字体参数，再打开另一本触发越狱。**全程在 Kindle 上操作，不需要电脑。**

1. Kindle：**⋮ → 网页浏览器**，访问 `https://kindlemodding.org/vera`。
2. 按页面选择你的**机型**和**固件版本**（下拉框没有完全一致的固件时选最接近的；不保证成功，可求助社区）。
3. 页面出现两个下载链接：依次下载 **Font Calibration** 书和对应机型的 **Véra** 书（各点一次确认）。下载完点 ✕ 退出浏览器，等 2–3 秒。
4. 打开 **Font Calibration** 书 → 点屏幕顶部 → **Aa**：
   - Font（字体）：Family 选 **Bookerly**，Bold 设 **0**，Size 设**最大**；
   - Layout / Spacing（排版/间距）：选 **medium**（或 Line Spacing 设 **2**）；
   - Themes（主题）：**Save current settings** → Save；
   - 连点左上角 3 次退回书库。
5. 打开 **Véra** 书。几秒后文字从左上角流下，出现「RESTARTING GUI」。GUI 重启后越狱完成。
6. **验证**：两本书可以删了；过程中卡在任何画面都可长按电源键强制重启，安全。
7. 排错：提示「If you have bought this item from amazon…」→ 删掉两本书、重启 Kindle、重来。

### 3.4 分支 C：WinterBreak2（老固件 ≤5.16.3）

1. 电脑下载：<https://github.com/KindleModding/Winterbreak2/releases/latest/download/wb2.zip>
2. **解压**，把解压出的内容复制到 **Kindle 根目录**：完成后 Kindle 根目录应有一个 `winterbreak2` 文件夹。
3. 安全弹出，Kindle 连 Wi-Fi。
4. Kindle 打开**实验性浏览器**：菜单 → Experimental Browser（部分固件在 设置 → 设备选项 → 高级 → 实验性浏览器）。
5. 访问 `https://penguins184.xyz/wb2`，点页面上的 **Jailbreak** 按钮。
6. 等待流程完成，Kindle 重启。**验证：重启完成即越狱成功。**
7. 排错：按钮没反应 → 确认 `winterbreak2` 文件夹在根目录（不是 documents 里），重启 Kindle 再试。

### 3.5 分支 D：Shadow（固件 5.19.4–5.19.6，MTP 新机型；电脑上运行）

原理：通过 USB 利用 Kindle 的 MTP 服务越狱。**Kindle 全程不联网、不需要填充文件**（仍建议开飞行模式）。

1. 记下 Kindle 设备信息里的 **10 位内部版本号**（括号里的数字）。
2. 电脑下载并解压：<https://github.com/KindleModding/Shadow/releases/latest/download/shadow.zip>
3. 释放 MTP 占用：
   - Windows：关闭所有打开 Kindle 的资源管理器窗口，拔插一次 USB；
   - macOS：终端执行 `killall ptpcamerad`，关闭 Finder 窗口；
   - Linux：终端执行 `killall kiod6 kiod5 gvfsd-mtp`，关闭文件管理器。
4. 运行 Shadow：
   - Windows：双击 `shadow-windows.exe`，允许管理员权限（它要临时切换 USB 驱动，结束后自动恢复）；
   - macOS：终端 `chmod +x shadow-darwin && sudo ./shadow-darwin`；
   - Linux：终端 `chmod +x shadow-linux && sudo ./shadow-linux`。
5. 输入 10 位内部版本号（**必须完全一致**），回车。
6. 按提示**拔下 USB，等 1–2 秒再插上**（Windows 会要求两次，macOS/Linux 一次）。
7. Kindle 屏幕左上角流下文字，完成后自动重启。**验证：重启完成即越狱成功。**
8. 排错：「Device busy」/ 找不到设备 → 重做第 3 步，确保没有程序占用 Kindle。

### 3.6 其他情况（按官方 wiki 操作）

| 情况 | 方法 | 官方教程 |
| --- | --- | --- |
| 广告版，5.18.1–5.18.5（PW4/KT4 仅 5.18.1） | AdBreak | <https://kindlemodding.org/jailbreaking/AdBreak/> |
| KT5/PW5 5.18.1–5.19.2；KT4/PW4 仅 5.18.1（需可注册） | SpringBreak | <https://kindlemodding.org/jailbreaking/SpringBreak/> |
| 较新机型 5.16.4–5.18.3 | Sanctuary | <https://kindlemodding.org/jailbreaking/Sanctuary/> |
| KT5/PW5/KOA3 5.16.4–5.18.6；PW6/KT6 ≤5.17.1.0.4 | Nosebleed | <https://kindlemodding.org/jailbreaking/Nosebleed/> |
| 老方法（需注册），≤5.18.0.2 | WinterBreak | <https://kindlemodding.org/jailbreaking/WinterBreak/> |
| K2/DX/K3/K4/Touch/PW1 等老设备 | NiLuJe 传统越狱 | <https://kindlemodding.org/jailbreaking/Legacy/index.html> |
| 固件太新，暂无方法 | 等待社区发布 | 定期看向导；**不要自行降级** |

### 3.7 越狱成功后

- 现代越狱方法会**自动装好**：更新屏蔽、KPM 包管理器等，**不需要手动装 hotfix**。
- 删除 2.5 的填充文件释放空间；确认根目录没有 `update*.bin` 残留。
- **验证（可选）**：Kindle 主页**搜索栏**输入 `;kpm update` 回车，屏幕顶部闪过文字后回到主页 → KPM 就绪（下一步会用到）。

---

## 4. 第三步：安装 KOReader

### 4.1 首选：KPM 一条命令安装

适用：SpiderCat / Véra / Shadow / SpringBreak / Sanctuary 等现代越狱（自带 KPM）。

1. Kindle 连 **Wi-Fi**。
2. 在主页**搜索栏**逐条输入以下命令（**带开头分号**，每条输完按回车）：

   ```text
   ;kpm update
   ;kpm upgrade
   ;kpm install koreader
   ```

3. 稍等片刻，书库出现一本新「书」（KOReader 启动器图标），点它启动 KOReader。
   - 图标没出现：搜索栏输入 `;kpm launch koreader` 启动。
4. **验证**：出现 KOReader 界面（文件管理器样式的阅读软件；首次启动可能几十秒初始化，正常）。
5. KOReader 被安装在 Kindle 根目录的 `koreader/` 文件夹（设备内路径 `/mnt/us/koreader`）——下一步插件就放这里面。

> 输入 `;kpm update` 完全无反应 → 说明没有 KPM（部分老越狱方法），改用 4.2 手动安装。

### 4.2 备选：手动拷贝 + 启动脚本

1. **选安装包**（按固件版本选，不是按型号）：

   | 固件 / 机型 | 下载包名 |
   | --- | --- |
   | 固件 ≥ 5.16.3（任何型号） | `koreader-kindlehf-<版本>.zip` |
   | 固件 ≤ 5.16.2 的触屏设备（PW2/KV/KT2/PW3/KOA/KT3/KOA2/PW4/KT4/KOA3/PW5/KS） | `koreader-kindlepw2-<版本>.zip` |
   | K4 / Kindle Touch / PW1 | `koreader-kindle-<版本>.zip` |
   | K2 / DX / K3（实体键盘） | `koreader-kindle-legacy-<版本>.zip` |

   下载页：<https://github.com/koreader/koreader/releases/latest>（在 Assets 里找对应名字）。

2. **把整个 zip 解压到 Kindle 根目录**：解压后 Kindle 根目录应有 `koreader/` 和 `extensions/` 两个文件夹（已存在则合并覆盖）。
3. **下载启动脚本**（.sh 文件）：<https://scriptlets.notmarek.com/scriptlets/koreader_launcher_asap.sh>
   （内存紧张的设备可用「停框架」版：<https://scriptlets.notmarek.com/scriptlets/koreader_launcher_no_framework.sh>）
4. 把 .sh 文件放进 Kindle 的 **`documents`** 文件夹，安全弹出。
5. Kindle 书库顶部出现一本新「书」（脚本会显示为书），点它启动 KOReader。
6. **验证**：出现 KOReader 界面。

### 4.3 很老的设备（K2/DX/K3/K4/Touch/PW1）

需要传统 KUAL / MRPI 启动器，步骤较繁琐，请按 KOReader 官方 wiki 操作（含 KUAL 安装与 KOL 启动器）：
<https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices>
插件安装方法（第四步）对所有设备一致。

### 4.4 KOReader 使用须知（重要）

- **先退出 KOReader 再插 USB**：KOReader 顶部菜单 → 退出。KOReader 运行时插 USB 可能导致崩溃。
- 首次启动慢（初始化字体缓存），之后快。
- 回 Kindle 原系统：从 KOReader 菜单退出即可。
- 以后升级 KOReader：KOReader 菜单内更新，或搜索栏 `;kpm upgrade`（升级所有 KPM 包，含 KOReader）。**升级前建议备份 `koreader/settings` 文件夹**（小小学习家的全部学习记录在里面）；若升级后插件消失，按第四步重拷一次即可。

---

## 5. 第四步：安装「小小学习家」插件

### 5.1 下载插件包（电脑上）

稳定链接（永远指向最新 Release，约 4 MB）：

```text
https://github.com/AvenGeeker/kidlearn/releases/latest/download/kidlearn.koplugin.zip
```

```bash
# macOS / Linux
cd ~/Downloads
curl -L --retry 3 -o kidlearn.koplugin.zip "https://github.com/AvenGeeker/kidlearn/releases/latest/download/kidlearn.koplugin.zip"
unzip -o kidlearn.koplugin.zip
```

```powershell
# Windows PowerShell
cd $HOME\Downloads
Invoke-WebRequest -Uri "https://github.com/AvenGeeker/kidlearn/releases/latest/download/kidlearn.koplugin.zip" -OutFile kidlearn.koplugin.zip
Expand-Archive -Path kidlearn.koplugin.zip -DestinationPath . -Force
```

**验证**：解压出 `kidlearn.koplugin` 文件夹，里面有 `main.lua`。
（GitHub 下载慢：重试、换手机热点、换时段，或自行使用可信的加速方式；不要从来路不明的第三方站点下载。）

### 5.2 复制到 Kindle

目标位置：Kindle 根目录的 **`koreader/plugins/kidlearn.koplugin/`**。
先**退出 KOReader**，再插 USB。

```bash
# macOS / Linux（$KINDLE 换成实际挂载点，如 /Volumes/Kindle）
KINDLE="/Volumes/Kindle"
ls "$KINDLE/koreader/plugins"    # 确认 plugins 目录存在
rm -rf "$KINDLE/koreader/plugins/kidlearn.koplugin"
cp -R ~/Downloads/kidlearn.koplugin "$KINDLE/koreader/plugins/"
ls "$KINDLE/koreader/plugins/kidlearn.koplugin/main.lua"   # 必须存在
```

```powershell
# Windows PowerShell（$KINDLE 换成实际盘符，如 E:）
$KINDLE = "E:"
Test-Path "$KINDLE\koreader\plugins"
Remove-Item "$KINDLE\koreader\plugins\kidlearn.koplugin" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "$HOME\Downloads\kidlearn.koplugin" "$KINDLE\koreader\plugins\" -Recurse
Test-Path "$KINDLE\koreader\plugins\kidlearn.koplugin\main.lua"   # 必须为 True
```

**MTP 设备**：用 OpenMTP / 资源管理器 / 文件管理器，把整个 `kidlearn.koplugin` 文件夹拖进 `Internal storage/koreader/plugins/`。

**验证（关键）**：必须存在这个文件——

```text
<Kindle根目录>/koreader/plugins/kidlearn.koplugin/main.lua
```

最常见的错误是**多套了一层目录**（如 `plugins/kidlearn.koplugin/kidlearn.koplugin/main.lua`），这样插件不会出现。

### 5.3 启动验证

1. 安全弹出 Kindle（macOS：`diskutil eject "$KINDLE"`；Windows：资源管理器右键盘符 → 弹出；Linux：文件管理器弹出）。
2. 打开 KOReader（点书库里的启动器「书」，或 `;kpm launch koreader`）。
3. KOReader 主菜单 → **更多工具** → **小小学习家**。
4. **验证**：出现插件首页（星星、连续学习天数、「今日挑战」按钮）。
5. 首次使用先进 **设置**：选省份、年级、学期、教材（语文统编版；数学有人教/北师大/苏教/青岛/沪教 5 个版本）。然后做一轮「今日挑战」（10 题，约 5 分钟）。

### 5.4 以后更新插件

不用每次插 USB：插件 **设置 → 检查更新**，直接从 GitHub Release 下载安装（有进度条、可随时取消、**学习记录不受影响**），完成后按提示重启 KOReader。
手动更新也行：重复 5.1–5.3 覆盖即可（学习记录在 `koreader/settings/kidlearn.lua`，不会丢）。

---

## 6. 第五步（可选）：把 AI API 配置推送到 Kindle

> 「小小学习家」**不配置 AI 也完全可用**（离线题库 + 程序生成数学题）。这一步面向想用 **AI 错题变种**（把错题自动改编成同类练习题）的家长：不用在 Kindle 上逐字输入 API Key，让 AI 在电脑上生成配置文件、拷进 Kindle，插件自动导入。

### 6.1 支持的服务商

| preset | 服务商 | 默认接口地址 | 推荐模型 | Key 申请地址 |
| --- | --- | --- | --- | --- |
| `deepseek` | DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` | <https://platform.deepseek.com/> |
| `qwen` | 通义千问 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus` | <https://bailian.console.aliyun.com/> |
| `kimi` | Kimi（月之暗面） | `https://api.moonshot.cn/v1` | `moonshot-v1-8k` | <https://platform.moonshot.cn/> |
| `zhipu` | 智谱 GLM | `https://open.bigmodel.cn/api/paas/v4` | `glm-4-flash`（免费） | <https://open.bigmodel.cn/> |
| `doubao` | 豆包 / 火山方舟 | `https://ark.cn-beijing.volces.com/api/v3` | 你的推理接入点 ID（`ep-…`） | <https://console.volcengine.com/ark> |
| `siliconflow` | 硅基流动 | `https://api.siliconflow.cn/v1` | `Qwen/Qwen2.5-7B-Instruct` | <https://cloud.siliconflow.cn/> |
| `openai` | OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` | <https://platform.openai.com/> |
| `gemini` | Google Gemini | `https://generativelanguage.googleapis.com/v1beta` | `gemini-2.0-flash` | <https://aistudio.google.com/> |
| `claude` | Anthropic Claude | `https://api.anthropic.com/v1` | `claude-3-5-haiku-latest` | <https://console.anthropic.com/> |
| `openrouter` | OpenRouter | `https://openrouter.ai/api/v1` | `openai/gpt-4o-mini` | <https://openrouter.ai/> |
| `ollama` | 局域网 Ollama | 自填，如 `http://192.168.1.10:11434/v1` | `qwen2.5:7b` | 无需 Key |
| `custom` | 自定义 OpenAI 兼容（中转等） | 自填 | 自填 | 视服务商 |

> 中国大陆用户推荐 DeepSeek / 通义 / Kimi / 智谱：直连快、便宜，智谱 `glm-4-flash` 免费。OpenAI / Gemini / Claude 需要能直连其服务的网络环境。

### 6.2 让 AI 生成配置文件

对 AI 说：「我用 ××（服务商），Key 是 sk-…，模型用 …，请生成 `kidlearn_ai_config.json`。」

最小配置（`preset`、`api_key`、`model` 三个字段；`base_url` 省略时用预设默认地址）：

```json
{
  "preset": "deepseek",
  "api_key": "sk-你的Key",
  "model": "deepseek-chat"
}
```

其他示例：

```json
{ "preset": "qwen", "api_key": "sk-你的Key", "model": "qwen-plus" }
```

```json
{ "preset": "custom", "base_url": "https://你的中转地址/v1", "api_key": "sk-你的Key", "model": "gpt-4o-mini" }
```

```json
{ "preset": "ollama", "base_url": "http://192.168.1.10:11434/v1", "model": "qwen2.5:7b" }
```

多个服务（想保留的服务都写进同一个文件；`active_id` 指定当前服务）：

```json
{
  "active_id": "aip-1",
  "profiles": [
    { "id": "aip-1", "preset": "deepseek", "api_key": "sk-aaa", "model": "deepseek-chat" },
    { "id": "aip-2", "preset": "qwen", "api_key": "sk-bbb", "model": "qwen-plus" }
  ]
}
```

**文件要求**：UTF-8 编码；合法 JSON（**不能写注释**、不能有尾逗号、不能用中文引号）；文件名必须是 `kidlearn_ai_config.json`。
Windows 记事本用户：保存时编码选 UTF-8；确认扩展名是 `.json` 而不是 `.json.txt`（资源管理器开启「文件扩展名」显示后检查）。

### 6.3 推送到 Kindle

目标位置：Kindle 根目录的 **`koreader/settings/kidlearn_ai_config.json`**。
注意：`settings` 目录在 KOReader **首次启动后**才存在；没有就先启动一次 KOReader 再退出，然后拷贝。

```bash
# macOS / Linux（AI 先把 JSON 写到 ~/Downloads/kidlearn_ai_config.json）
KINDLE="/Volumes/Kindle"
mkdir -p "$KINDLE/koreader/settings"
cp ~/Downloads/kidlearn_ai_config.json "$KINDLE/koreader/settings/"
ls -l "$KINDLE/koreader/settings/kidlearn_ai_config.json"
```

```powershell
# Windows PowerShell
$KINDLE = "E:"
New-Item -ItemType Directory -Force "$KINDLE\koreader\settings" | Out-Null
Copy-Item "$HOME\Downloads\kidlearn_ai_config.json" "$KINDLE\koreader\settings\"
Test-Path "$KINDLE\koreader\settings\kidlearn_ai_config.json"   # True
```

MTP 设备：把文件拖进 `Internal storage/koreader/settings/`。完成后安全弹出。

### 6.4 验证导入

1. **重启 KOReader**（退出再打开；若本次 KOReader 运行中已打开过插件，必须重启 KOReader 才会重新导入）。
2. 打开 小小学习家 → **设置 → AI 出题设置**。
3. 应看到：**「当前 AI 配置来自 koreader/settings/kidlearn_ai_config.json」**，服务列表里有你的服务商（Key 掩码显示末 4 位）。
4. 点 **测试连接** → 提示「连接成功，可以开始 AI 出题了。」（会发一条极短请求，消耗极少量 token）。
5. 实际使用：错题本 → **AI 强化**（先要有几道错题）。AI 生成变种题后，**家长先在预览页检查答案和解析**，再让孩子练习。

### 6.5 配置文件规则（重要）

- 插件启动时读取文件；**文件内容变化后，下次重启会重新导入**；内容不变时，插件内的临时修改不会被覆盖。
- 导入会**替换**插件里现有的 AI 服务列表：要保留的服务都写进同一个文件。
- 删除文件并重启 → 清除导入记录，之后以插件内设置为准。
- API Key 在 Kindle 上**明文保存**（与 `kidlearn.lua` 相同）。请：使用低额度 Key；避免共用设备；不要把填好 Key 的文件上传网盘 / git / 群聊。
- AI 助手不得在对话中复述完整 Key；展示时掩码。

---

## 7. 验收清单

AI 请逐项确认：

- [ ] Kindle 已越狱（现代方法：`;kpm update` 有响应）
- [ ] KOReader 能正常启动（书库里有启动器「书」）
- [ ] `koreader/plugins/kidlearn.koplugin/main.lua` 存在
- [ ] KOReader 更多工具 → 小小学习家 能打开首页
- [ ] 已设置省份/年级/学期/教材；做完一轮「今日挑战」，星星正常增加
- [ ] （可选）`koreader/settings/kidlearn_ai_config.json` 存在；AI 设置页显示「当前 AI 配置来自…」；测试连接成功
- [ ] 填充文件已删除、空间已释放；根目录无 `update*.bin`
- [ ] 用户知道：如何退出 KOReader、KOReader 运行时不插 USB、插件内置更新怎么用

---

## 8. 常见问题 FAQ

1. **插上电脑没有盘符**：先换数据线 / USB 口（很多线只能充电）；解锁 Kindle 屏幕；2022 年后的新机型多为 MTP 模式（见 2.3，Windows 在资源管理器里是便携设备，macOS 用 OpenMTP）。
2. **固件太新，没有越狱方法**：暂无解。保持当前固件（飞行模式 / 存储填满），定期看官方向导；不要自行降级，也不要专为越狱买新机（出厂固件可能不可破）。
3. **`;kpm update` 没反应**：没有 KPM（老越狱方法），用 4.2 手动安装；确认是在主页**搜索栏**输入、带开头分号、按了回车。
4. **更多工具里没有插件**：目录层级错（核对 `main.lua` 完整路径，别多套一层）；文件夹名必须以 `.koplugin` 结尾；没有重启 KOReader。
5. **AI 配置没导入**：文件名/路径不对（必须 `koreader/settings/kidlearn_ai_config.json`）；JSON 非法（注释、尾逗号、中文引号）；没有重启 KOReader；看 AI 设置页的错误提示。
6. **测试连接失败**：Key / 模型名写错；中转地址 `base_url` 要以 `http(s)://` 开头、通常以 `/v1` 结尾；Kindle 要连 Wi-Fi；Ollama 要填局域网可达地址且 Ollama 允许局域网访问。
7. **GitHub 下载慢 / 失败**：国内常见。重试、换手机热点、换时段，或自行使用可信加速方式。插件内置更新不设超时、有进度条、可随时取消，慢就慢慢等。
8. **Kindle 自动升级后越狱没了**：到社区按「Recovering From a Reset / Legacy Migration」指引恢复；预防：越狱前填满存储，现代方法成功后会自动屏蔽更新。
9. **越狱影响正常看书吗**：不影响。原系统还在，买的书照常看；KOReader 与原系统随时切换。
10. **学习记录会丢吗**：记录在 `koreader/settings/kidlearn.lua`（插件目录之外）。覆盖插件、插件内置更新都不丢；升级 KOReader 前建议备份 `koreader/settings` 文件夹。
11. **Kobo / 安卓能用吗**：本教程面向 Kindle。插件理论上适用于任何 KOReader 设备：把 `kidlearn.koplugin` 放进对应的 `koreader/plugins/` 即可（安卓 KOReader 直接装插件，不需要越狱）。
12. **想卸载**：删 `koreader/plugins/kidlearn.koplugin` 文件夹（学习记录仍在，想彻底清掉再删 `koreader/settings/kidlearn.lua`）；KOReader 用 `;kpm uninstall koreader`；移除越狱见 wiki 的 Unjailbreaking 页面。

---

## 9. 附录

### A. 官方链接清单（AI 只允许使用这些来源）

| 用途 | 链接 |
| --- | --- |
| KidLearn 插件仓库 | <https://github.com/AvenGeeker/kidlearn> |
| KidLearn 插件包（最新 Release，稳定链接） | <https://github.com/AvenGeeker/kidlearn/releases/latest/download/kidlearn.koplugin.zip> |
| KidLearn Release 页 | <https://github.com/AvenGeeker/kidlearn/releases> |
| 越狱官方向导 | <https://kindlemodding.org/jailbreak-wizard.html> |
| 越狱决策数据（机器可读） | <https://kindlemodding.org/jailbreaks.json> |
| 型号数据（机器可读） | <https://kindlemodding.org/models.json> |
| SpiderCat 越狱书 | <https://kindlemodding.org/spidercat/spidercat.azw3> |
| SpiderCat Kindle 端下载页 | <https://kindlemodding.org/spidercat> |
| Véra Kindle 端页面 | <https://kindlemodding.org/vera> |
| WinterBreak2 包 | <https://github.com/KindleModding/Winterbreak2/releases/latest/download/wb2.zip> |
| WinterBreak2 触发页 | <https://penguins184.xyz/wb2> |
| Shadow 包 | <https://github.com/KindleModding/Shadow/releases/latest/download/shadow.zip> |
| 存储填充脚本 | <https://github.com/bastianmarin/Kindle-Filler-Disk> |
| MTP 填充参考 | <https://github.com/Crosunt223/Kindle-Filler-Disk/tree/main/MTP> |
| KOReader Release 页 | <https://github.com/koreader/koreader/releases/latest> |
| KOReader 启动脚本 | <https://scriptlets.notmarek.com/scriptlets/koreader_launcher_asap.sh> |
| KOReader 启动脚本（停框架版） | <https://scriptlets.notmarek.com/scriptlets/koreader_launcher_no_framework.sh> |
| KOReader Kindle 安装 wiki | <https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices> |
| KindleModding wiki 首页 | <https://kindlemodding.org/> |
| macOS MTP 工具 OpenMTP | <https://openmtp.ganeshrvel.com/> |

### B. kidlearn_ai_config.json 字段参考

顶层两种写法：

1. 单服务：直接一个对象 `{ "preset": ..., "api_key": ..., "model": ... }`；
2. 多服务：`{ "profiles": [ {...}, {...} ], "active_id": "aip-1" }`（`active` 也可，数字表示第几个，字符串匹配 id 或 name）。

| 字段 | 必填 | 说明 | 兼容别名 |
| --- | --- | --- | --- |
| `preset` | 是 | 见 6.1 的 12 个预设；未知预设会被拒绝 | `provider`、`provider_id` |
| `api_key` | 除 `ollama`/`custom` 外必填 | API Key | `key` |
| `model` | 是 | 模型名（豆包填推理接入点 ID） | `model_name` |
| `base_url` | `custom`/`ollama` 必填，其他可省略 | 接口地址，必须 `http://` 或 `https://` 开头；省略用预设默认 | `api_url`、`endpoint` |
| `name` | 否 | 显示名称，默认用预设名 | — |
| `id` | 否 | 多服务时建议写（如 `aip-1`），用于 `active_id` | — |

校验规则：JSON 必须是对象；`profiles` 为空报错；每个服务按上表校验；导入成功后插件设置页显示来源文件名。

### C. 机器可读摘要（供 AI 解析）

```json
{
  "guide_snapshot": "2026-11-14",
  "plugin": {
    "name": "kidlearn",
    "repo": "https://github.com/AvenGeeker/kidlearn",
    "download_url": "https://github.com/AvenGeeker/kidlearn/releases/latest/download/kidlearn.koplugin.zip",
    "zip_top_level": "kidlearn.koplugin/",
    "install_dir": "<kindle_root>/koreader/plugins/kidlearn.koplugin/",
    "required_file": "main.lua",
    "menu_path": "更多工具 → 小小学习家",
    "save_file": "<kindle_root>/koreader/settings/kidlearn.lua",
    "ai_config_file": "<kindle_root>/koreader/settings/kidlearn_ai_config.json",
    "in_plugin_update": "设置 → 检查更新"
  },
  "koreader": {
    "releases": "https://github.com/koreader/koreader/releases/latest",
    "kpm_commands": [";kpm update", ";kpm upgrade", ";kpm install koreader"],
    "kpm_launch": ";kpm launch koreader",
    "install_dir": "<kindle_root>/koreader/",
    "manual_package_rule": {
      "fw_ge_5.16.3": "koreader-kindlehf",
      "fw_le_5.16.2_touchscreen_pw2_plus": "koreader-kindlepw2",
      "K4_KT_PW1": "koreader-kindle",
      "K2_DX_K3": "koreader-kindle-legacy"
    },
    "launcher_scriptlets": [
      "https://scriptlets.notmarek.com/scriptlets/koreader_launcher_asap.sh",
      "https://scriptlets.notmarek.com/scriptlets/koreader_launcher_no_framework.sh"
    ],
    "usb_rule": "KOReader 运行时禁止插 USB，先退出"
  },
  "jailbreak": {
    "wizard": "https://kindlemodding.org/jailbreak-wizard.html",
    "data_sources": [
      "https://kindlemodding.org/jailbreaks.json",
      "https://kindlemodding.org/models.json"
    ],
    "methods": {
      "SpiderCat": {
        "fw": ["5.16.3", "5.19.5"],
        "models": ["PW4","KT4","KOA3","PW5","KT5","KT6","PW6","CS","KS","KS2"],
        "book_url": "https://kindlemodding.org/spidercat/spidercat.azw3",
        "copy_to": "documents/",
        "needs_wifi": true
      },
      "Vera": {
        "fw": ["5.17.1", "5.20.2"],
        "models": ["PW5","KT5","KT6","PW6","CS","KS","KS2"],
        "device_url": "https://kindlemodding.org/vera",
        "needs_wifi": true
      },
      "WinterBreak2": {
        "fw": ["5.6.1.1", "5.16.3"],
        "accepted_outliers": ["5.16.5"],
        "zip_url": "https://github.com/KindleModding/Winterbreak2/releases/latest/download/wb2.zip",
        "copy_to": "<kindle_root>/",
        "trigger_url": "https://penguins184.xyz/wb2",
        "needs_wifi": true
      },
      "Shadow": {
        "fw": ["5.19.4", "5.19.6"],
        "models": ["KS","KS2","CS","PW6","KT6"],
        "zip_url": "https://github.com/KindleModding/Shadow/releases/latest/download/shadow.zip",
        "runs_on": "computer",
        "needs_build_number": true,
        "needs_wifi": false
      }
    },
    "filler_repo": "https://github.com/bastianmarin/Kindle-Filler-Disk",
    "fill_target_free_mb": [50, 90]
  },
  "ai_config_schema": {
    "minimal": { "preset": "deepseek", "api_key": "sk-...", "model": "deepseek-chat" },
    "presets": ["openai","deepseek","qwen","kimi","zhipu","doubao","gemini","claude","siliconflow","openrouter","ollama","custom"],
    "multi": { "active_id": "aip-1", "profiles": [ { "id": "aip-1", "preset": "...", "api_key": "...", "model": "..." } ] },
    "import_behavior": "插件启动时读取；内容变化则重启后重新导入；导入替换服务列表；删除文件清除导入记录"
  },
  "safety_rules": [
    "每步验证后再继续",
    "只用附录 A 的官方链接",
    "API Key 掩码展示、不外传",
    "KOReader 运行时不插 USB",
    "不恢复出厂、不降级固件",
    "固件无越狱方法时停止并告知"
  ]
}
```

### D. 数据来源与时效

- 越狱决策数据于 **2026-11-14** 从 kindlemodding.org 抓取核对（`jailbreaks.json` / `models.json` / 各方法页面）。越狱方法与固件范围随时间变化：**AI 执行时若当前日期晚于快照日期，或用户固件不在决策表内，必须重新抓取上述 JSON 或使用官方向导**，不要依赖过期快照。
- KOReader 安装方式参考 KOReader 官方 wiki《Installation-on-Kindle-devices》（2026-08 版）与 Releases 页。
- 插件行为（安装路径、配置导入、更新器）以 KidLearn 仓库 README 与源码为准。
- 插件问题请到 <https://github.com/AvenGeeker/kidlearn/issues>；越狱问题请到 KindleModding Discord / Reddit r/kindlejailbreak（教程附录 A 的 wiki 首页有入口）。
