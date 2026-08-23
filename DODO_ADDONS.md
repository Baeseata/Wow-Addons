# Dodo Addons - WoW Retail (Midnight / 至暗之夜)

> 个人自用魔兽世界插件集合，GitHub 单仓 <https://github.com/Baeseata/Wow-Addons>。
> 所有 Dodo 插件由 Baeseata 维护，多数复用粉色 D 图标（`Dodo/Media/Dodo.tga`）。
>
> 🔑 **本文是这个仓库唯一的跨机器约定落脚点。** 凡「两台机都要遵守」的事写这里一处；
> 单个插件自己的坑写那个插件的 `CLAUDE.md`。
>
> ⚠ **本文不记会腐烂的数**（版本号 / 行数 / 插件个数 / 最新 tag / 谁做完了没）。要那些去查：
>
> | 想知道 | 去哪儿查 |
> |---|---|
> | 有哪些插件 | 仓库根 `ls -d Dodo*`（**权威清单是目录本身，不是本文的表**） |
> | 某插件当前版本 | 该插件 `<Addon>/<Addon>.toc` 的 `## Version` |
> | 支持哪些客户端版本 | 同一个 TOC 的 `## Interface`（**各插件不同，见下「Interface 不统一是有意的」**） |
> | 某插件发到 CurseForge 哪一版了 | CurseForge 该项目的 Files 页 + GitHub Actions 的运行记录（**不是 git tag**，tag 会被删） |
> | 发版流程 | `.github/workflows/curseforge-release.yml`（tracked，两台机都读得到） |
>
> 历史注记：本文 2026-06-10（c3d9aec）连同各插件 CLAUDE.md 一起被 `.gitignore` 排除；
> 次日 2447cbf 以「cross-machine dev needs them」为由恢复了 CLAUDE.md，**却漏了本文**，
> 于是「跨机约定」在两个多月里只活在其中一台机的磁盘上。2026-08-22 恢复跟踪。**别再 ignore 它。**

---

## 跨机器布局（**先读这节**）

两台机的工作方式**不一样**，而且差异就在「改完的文件怎么进游戏」这一步上。

| 机器 | 工作树在哪 | 改完怎么进游戏 | 怎么推送 |
|---|---|---|---|
| **HOME** | **就地** `D:\World of Warcraft\_retail_\Interface\AddOns\<Addon>`（**不是 git tree、不是 junction**） | 原地改 → `/reload`；新增文件并写进 TOC 要**完整重启客户端** | 临时目录 `git clone` → 把改动文件拷进去 → commit → push |
| **OMEN** | `~/Code/Wow-Addons`（真 clone） | 从 clone **拷进**该机自己的 AddOns 目录（路径见该机 `~/.claude/CLAUDE.md`） | 直接在 clone 里 commit → push |

取证：HOME 那一行 2026-08-22 实测（24/24 目录零 junction、AddOns 目录 `git rev-parse` 失败）；
OMEN 那一行由 Jerry 提供，**HOME 上验不了** —— 在 OMEN 上干活的 session 若发现不符，请就地改这一行并注明日期。

🔴 **别写「junction / 软链接，所以改完自动同步」。** 那句话在 HOME 上实测为假，
而信了它的代价是**改完的东西永远到不了游戏**，症状是「`/reload` 之后什么都没变」——
读起来像代码 bug，会让人去查 Lua。**两台机都一样：编辑处和游戏加载处是两份文件，必须拷。**
（若哪天真去建了 junction，请回来改这一节并写上是哪台机、哪天建的。）

### 措辞铁律：禁止用「本机 / 这台 / 主力机 / 本地」描述机器布局

这是一个**两台机共享**的仓库 —— 这些词在读到它的人那边**无法解析**，而且默认解析成
「我这台」于是把另一台的布局判成假。一律写显式机器名 **HOME** / **OMEN**，
或写「该机（见该机 `~/.claude/CLAUDE.md`）」。
判据：**凡写布局，句子里必须点得出机器名；出现「本机」就是待修。**
正确范本见 `DodoGuanzhu/CLAUDE.md`。

---

## 仓库级约定（两台机都照这个来）

### 1. TOC `## Author` 一律写 `Doodo`

不是 `Dodo`（少一个 o 是 typo）、不是 `OpenAI`（早期用别的工具生成时留下的）。
2026-08-22 统一过一轮；新插件照抄现有 TOC 即可。

### 2. `## Interface` **不统一，而且不许统一** —— 各插件按自己真实依赖写

| 写法 | 谁用 | 为什么 |
|---|---|---|
| `120005, 120007, 120100` | 绝大多数插件 | 只用跨版本都在的 API，多版本 TOC 让老客户端也能加载 |
| `120100` **单写** | 依赖 12.1 才有的 API 的插件（如 DodoNameplate 的 secure aura container、DodoSays） | **故意的**：声明旧版 = 老客户端会加载它然后调用不存在的 API 崩掉。窄声明是让老客户端**根本不加载**它 |

🔴 **别拿「统一」当理由去给它们补 120005/120007** —— 那会把「加载不了」换成「加载后崩」。
✅ 唯一该统一的是**顺序**：多版本一律**升序**（`120005, 120007, 120100`）。
判据：**改 Interface 前先问「这个插件调的 API 在旧版存在吗」，答不上来就别动。**

### 3. `isSecret` 有**四份刻意重复**的手写实现，改一处必须改全部四处

清单（这就是那份「改全部」的名单，别再另抄一份）：

| # | 位置 |
|---|---|
| ① | `DodoNameplate/Guards.lua` |
| ② | `DodoSays/Util.lua` |
| ③ | `DodoUnholy/Rotation.lua` |
| ④ | `DodoGuanzhu/Macro.lua` |

⛔ **不要把它们收进 `Dodo/Shared.lua`**。`DodoInspect` 和 `DodoNameplate` **故意不挂**
`## OptionalDeps: Dodo` / `## Group: Dodo`（为独立发 CurseForge 而与父包解耦，各自带一份
`Media/Dodo.tga`）—— 它们在玩家机器上**根本没有 `Dodo` 目录**，运行时调不到 `Dodo.*`。
「收进共享库」这个修法在这里是**行不通**的，不是没人想到。

✅ 正确做法：四份**保持同一形状** —— `type(issecretvalue) ~= "function"` 探测 +
`pcall` 兜底 + `== true` 归一成布尔。归一那步不可省：
`issecretvalue` 返回 `nil` 时被 `== true` 折成 `false` 已经真栽过一次
（DodoSays 2026-08-15，整场零报点零报错，详见 `DodoSays/Util.lua` 的注释）。

### 4. 文档放哪（防「同一件事四个副本互相矛盾」）

| 内容 | 放哪 |
|---|---|
| 跨插件、两台机都要遵守的约定 | **本文一处** |
| 某个插件自己的坑 / 设计 / 交接 | 该插件的 `CLAUDE.md`（和它旁边的 `GOTCHAS.md` / `PENDING-WORK.md`） |
| WoW 平台级教训（Secret Values、API 判决） | canon `rules/wow-addons.md`（在另一个 repo，两台机都有） |

⛔ **别把同一段话抄进多个插件的 CLAUDE.md** —— 已经发生过：同一条发版仪式手写了 4 份，
已经在漂了。要引用就写「见 `<文件>:<锚点>`」。
⚠ 反例例外：`DodoSays/CLAUDE.md` 里那段发版仪式是**故意重复**的（同一个坑踩了两次之后特意就地写死的），
那一段旁边有说明，别顺手收成指针。

### 5. 会腐烂的话写成「去哪儿查」，别写成句子

判据（canon 原话）：**「这句话下个月还会是真的吗？不会 ⇒ 它该以查询的形式存在，不是句子。」**
具体到这个仓库：版本号 / 最新 tag / 「尚未实现」/「已全部发版」/ 插件个数 / 行数
—— 一律换成「查 TOC 的 `## Version`」「查 CF Files 页」「查 `git log`」这种指路。

---

## CurseForge：谁在上面、新插件怎么登记

> ⚠ 下表回答的是「**这个插件有没有 CF 项目**」（不会腐烂）。
> 「**发到哪一版了**」不写在这里 —— 查 CF 的 Files 页 + GitHub Actions 运行记录。

| 插件 | CF 项目 id | id 登记在哪 |
|---|---|---|
| DodoNameplate | 1587138 | 自己的 TOC `## X-Curse-Project-ID` ✅ |
| DodoSays | 1654722 | 自己的 TOC `## X-Curse-Project-ID` ✅ |
| DodoBricks | 1571430 | workflow 的 case map（历史回落） |
| DodoInspect | 1572493 | workflow 的 case map（历史回落） |
| DodoLura | 1602130 | workflow 的 case map（历史回落） |

**其余插件只在 GitHub，没有 CF 项目。** 外部插件 Plater 是第三方，不进本仓库。

### 登记一个新插件 = 两处，缺一不可

1. **主路径**：在它的 TOC 里写 `## X-Curse-Project-ID: <id>`。
   workflow 是 **TOC 优先**（`Resolve addon, version and project id` 步骤里先 `grep '^## X-Curse-Project-ID:'`，
   读不到才回落 case map）⇒ **新插件不用改 workflow 的 case map，也别往里加。**
   那张 case map 只为上面三个「TOC 里还没写 id」的老插件兜底；哪天把它们的 id 迁进各自 TOC，
   整张表就能删掉（迁完必须先跑一次 `dry_run=true` 做 A/B，别改完就当好了）。
2. **另加一处**：把文件夹名加进 workflow 的 `workflow_dispatch.inputs.addon.options` 清单
   —— 这处只影响**手动 dry-run 能不能选到它**，tag 触发的正式发版不看它。漏了不会静默出错，
   只是 Actions 页面上选不到这个插件。

两处都没有时 workflow 会 **fail-fast**（`No CurseForge project id for <Addon>` 直接 exit 1），
不会把包传到错的项目上 —— 这是它现在唯一的好消息，别把它改成有默认值。

### 发版仪式（正文在 workflow 里，这儿只列铁律）

完整流程读 `.github/workflows/curseforge-release.yml`（顶部注释 + `Upload to CurseForge` 步骤注释）。
⛔ **别再引用 `PUBLISHING.md`** —— 那个文件从未被 git 跟踪过（`git log --all --diff-filter=A -- '*PUBLISHING*'` 为空），
HOME 上全盘搜索零命中，且被 `.gitignore` 排除 ⇒ **它永不跨机，任何指向它的「详见 §7/§8/§10」都是死链**。

1. **先 push 代码，再打 tag** —— zip 是从 **tag 指向的那个 commit** 打的，反了就发出一个旧包。
2. tag 名 `<Addon>-v<Version>`，**版本必须等于 TOC 的 `## Version`**（workflow 会校验，不等就 exit 1）。
3. **必须是 annotated tag**（`git tag -a -F <file> --cleanup=verbatim`）——
   tag message 就是 CF 的 changelog；**lightweight tag 会把 commit message 静默当成 changelog 发出去**。
   `--cleanup=verbatim` 不能省，否则 `##` 开头的标题行会被 git 当注释剥掉（这个坑被踩过两次）。
   验证：`git ls-remote --tags origin` 里出现 `^{}` 那行才是 annotated。
4. 想干跑一遍：Actions 页手动跑该 workflow，`dry_run = true`（打包 + 校验 token + 解析游戏版本，跳过上传）。
5. 包里**不含** `CLAUDE.md` / `test/` / `tools/`（打包白名单见 `Build addon zip` 步骤，
   而且它会在打完包后再扫一遍，泄漏就 exit 1）。仓库根的 `.md`（含本文）天然进不了包 ——
   打包只走该插件自己的目录。

⚠ **同一个 CF 项目可能被两个 repo 够到**：有些插件是从自己的独立 repo 搬进本单仓的
（实例 = `Baeseata/DodoNameplate`），那个旧 repo 里还留着 `on: push: tags: '**'` 的
BigWigs packager workflow、有效的 `CF_API_KEY`，以及**跟单仓里同一个** `X-Curse-Project-ID`。
在那种 repo 里打**任何** tag 都会往同一个 CF 项目传包。
✅ 挡住它的是**归档**（archived repo 只读，Actions 不再触发）。
⇒ **别在 doc 里写「它归没归档」这种会变的状态，现查**：
`gh repo view Baeseata/<Addon> --json isArchived`（回 `true` = 那条管线是死的）。
搬插件进单仓时，**「归档旧 repo」是这套流程的最后一步，别漏**。

---

## 插件总览

> ⚠ **权威清单 = 仓库根目录本身**（`ls -d Dodo*`），不是本表。本表只记「各插件是干嘛的」这类
> 不会腐烂的事实 —— **没有版本号、没有行数、没有个数**（那些去查 TOC）。
> 新增插件时**补一行**；本表漏了某个插件不代表它不存在。
> 🎮 = 小游戏。「自带 doc」列里有 `CLAUDE.md` 的，**改它之前先读那份**。

| 插件 | 说明 | 自带 doc |
|---|---|---|
| **Dodo**（父包）| 公共库 `_G.Dodo`（`Shared.lua`）+ 共享图标 `Media/Dodo.tga` + `## Group: Dodo` 归组 | — |
| DodoAirdrop | 战争模式空投追踪（钩 TalkingHead、分地图记录、小地图按钮） | — |
| DodoAuction | 拍卖行价格追踪与快捷发布（1% 均价、趋势箭头、自动发布） | — |
| DodoBricks 🎮 | 数字砖块弹球（HP 砖、逐行下压、拾取/宝箱/Boss）；独立品牌，**在 CF 上** | `CLAUDE.md` |
| **DodoCombatHUD** | 自绘战斗监控 HUD：目标血量 / 资源 / 施法引导同宽叠在视线中心。**12.x Secret Values 下的设计范本** | `CLAUDE.md` |
| DodoCursor | 鼠标光标装饰（战斗中圆圈、移动放大、可调大小/透明度） | — |
| DodoGatherMate | 采集节点记录（草药/矿点/空投、大小地图标点、收益统计） | — |
| DodoGrid | 治疗向队伍/团队框体（Cell 风格；自绘 SecureUnitButton、光环指示、点击驱散） | `CLAUDE.md` |
| DodoGuanzhu | 牧师能量灌注顺位：预设名单，一个宏按优先级给人，都给不出去才给自己 | `CLAUDE.md` / `GOTCHAS.md` / `PENDING-WORK.md` |
| DodoInspect | 背包/角色/检视装备覆盖层 + 装备侧栏 + 目标信息行（四国语言）；**在 CF 上** | `CLAUDE.md` + 多份研究 doc |
| DodoLura | 鲁拉（至暗之夜）星辰裂片点名气喇叭，零设置；**在 CF 上** | `CLAUDE.md` |
| DodoMap | 实时坐标显示 + 坐标输入路径点 | — |
| DodoNameplate | 按类别美化姓名板（威胁/目标/施法/12.1 安全光环容器）；**在 CF 上**，且**只声明 `120100`** | `CLAUDE.md` / `GOTCHAS.md` / `DESIGN.md` / `SESSION-LOG.md` / `PENDING-WORK.md` |
| DodoNumbers | 战斗浮动数字自定义（CVar：缩放/暴击/方向/散布） | — |
| DodoPool 🎮 | 单人 9 球台球（自带 2D 物理引擎；依赖父包 Dodo） | `CLAUDE.md` |
| DodoProbe | **Secret Values 探针**（诊断用，默认静默，`/dp` 手动跑）。**要量真机给不给值就往它里面加一行，别靠记忆** | `CLAUDE.md` |
| DodoQuest | 任务自动化（自动接交、最优奖励、Shift 暂停） | — |
| DodoRaidTools | 团本阶段计时（ENCOUNTER_TIMELINE 事件） | — |
| DodoRush 🎮 | 人群奔跑（A/D 选数学门、扩军、撞红敌、无尽） | `CLAUDE.md` |
| DodoSays | Azta'rec（毒瀑深渊）记忆游戏辅助：布道时手点、回响时报点；**在 CF 上**，且**只声明 `120100`** | `CLAUDE.md` / `PENDING-WORK.md` / `docs/` 研究档 |
| DodoShield | 进战定时文字/声音提醒（多方案；如放罩子） | — |
| DodoStatHUD | 实时属性 HUD（套装名、副属性、趋势箭头） | — |
| DodoUnholy | 邪 DK 食尸鬼提醒（专精检测、宠物追踪） | — |
| DodoXuefei | 血 DK「沸点」监视一格：15 秒 proc 显绿 / 3 秒 echo 显红，都发光。**DodoCombatHUD `Boiling.lua` 抄出来的独立版，给不用整套 HUD 的人** —— 两份实现，改一边要看另一边 | `CLAUDE.md` |

**外部插件**：Plater（第三方姓名版，CurseForge 安装，不进本仓库）。

> 下面「各插件详细说明」只覆盖**没有自带 `CLAUDE.md`** 的那些老插件 ——
> 有 `CLAUDE.md` 的以那份为准，**这里不再抄一遍**（抄第二份就是下一个分歧发生器）。

---

## 各插件详细说明（仅限**没有**自带 `CLAUDE.md` 的老插件）

> 有 `CLAUDE.md` 的插件（Bricks / CombatHUD / Grid / Guanzhu / Inspect / Lura / Nameplate /
> Pool / Probe / Rush / Says）**不在这里重复** —— 读它们自己那份。

### Dodo（父包）
- **SavedVariables**: DodoDB（预留）
- 所有 Dodo 子插件的父包，在插件列表中作为「Dodo Pack」父项
  - 共享素材 `Dodo/Media/Dodo.tga`（多数子插件靠 `## IconTexture` 复用同一份）
  - 公共库 `_G.Dodo`（`Shared.lua`）: `Dodo.icon` / `Dodo.Media(file)` / `Dodo.CopyDefaults(dst,src)` /
    `Dodo.Clamp` / `Dodo.Print(tag,msg)` / `Dodo.Money(copper)` / `Dodo.Register(name,module)`
  - 子插件 TOC 加 `## Group: Dodo` 实现列表归组（11.1.0+ 机制）
  - ⚠ 独立发 CF 的插件（DodoInspect / DodoNameplate）**故意不依赖它**，见「仓库级约定 §3」

### DodoAirdrop
- **SavedVariables**: DodoAirdropDB ｜ **命令**: `/dodoairdrop`, `/dodoad`
- 监控战争模式空投事件，通过挂钩 TalkingHeadFrame 系统检测空投通知
  - 追踪 4 张地图，监听空投 NPC，记录每张地图上次空投时间（绝对+相对）
  - 小地图按钮（Shift+左键拖动），团队警告框和音效通知
  - 60 秒去重窗口，50ms 延迟读取 TalkingHead 数据

### DodoAuction
- **SavedVariables**: DodoAuctionDB ｜ **命令**: 通过 UI 操作
- 拍卖行价格历史追踪和快捷发布工具
  - 追踪商品价格（1% 最低加权均价），每件最多 100 条数据
  - 价格历史图表（1/7/30 天或全部），线性回归趋势箭头（▲▼，基于最近 ≤5 点）
  - 右键背包物品搜索拍卖行并追踪；自动发布（历史偏好单价）；品质星级（★）；可排序滚动列表

### DodoCursor
- **SavedVariables**: DodoCursorDB ｜ **命令**: `/dodocursor`, `/dc`
- 在鼠标光标处叠加粉色圆圈装饰，仅战斗中显示
  - 光标持续移动超过 0.5 秒后圆圈放大一倍；可调大小（16-128）、透明度（0.1-1.0）
  - Core.lua（光标逻辑）+ Options.lua（设置面板）

### DodoGatherMate
- **SavedVariables**: DodoGatherMateDB ｜ **命令**: `/dgm`, `/dodogathermate`
- 自动记录采集节点并在地图上显示
  - 监听采集施法（草药/采矿）与战争补给箱开启，记录坐标
  - 小地图 + 大地图标点（随采集专业过滤）；最近 1 小时收益统计（读 DodoAuction 价格）
  - 使用 C_Map / C_Spell / C_TradeSkillUI API

### DodoMap
- **SavedVariables**: DodoMapDB ｜ **命令**: `/dodomap`
- 实时玩家坐标显示和坐标标记
  - 每 100ms 更新坐标（1 位小数）；可拖动坐标框（解锁后可移动）
  - 弹窗输入 X/Y 设置路径点（0-100 校验，暴雪原生路径点系统）
  - 小地图按钮（Shift+左键拖动）；设置面板（字号 8-32、位置持久化）

### DodoNumbers
- **SavedVariables**: DodoNumbersDB
- 浮动战斗文字（FCT）自定义
  - 通过 CVar 调整缩放、暴击放大、存在时间、浮动方向和水平散布
  - 支持 Retail 12.0+ v2 CVar 与旧版双兼容；首次加载捕获原始值用于还原
  - 选项面板带实时预览；宠物/DoT/未命中等显示开关；浮动模式 上/下/弧形；一键还原
  - **文件结构**: Core.lua（CVar 管理）+ Options.lua（UI 面板）

### DodoQuest
- **SavedVariables**: DodoQuestDB
- 轻量级任务自动化
  - 自动接受/提交任务，自动处理单选项对话，多奖励时自动选最高售价物品
  - 按住 Shift 暂停；双 API 支持（C_GossipInfo 新 + 旧版）
  - 处理 QUEST_DETAIL / PROGRESS / COMPLETE / GREETING；异步物品数据等待
  - 选项面板：自动化开关 + 最优奖励开关

### DodoRaidTools
- **SavedVariables**: DodoRaidToolsDB ｜ **命令**: `/drt`, `/dodoraidtools`
- 团本阶段计时辅助（当前仅史诗宇宙之冕自动启用）
  - 屏幕中央显示当前阶段 + 计时 + 即将到来的技能倒计时
  - 通过 12.0 新事件 ENCOUNTER_TIMELINE_EVENT_ADDED 自动切换阶段
  - 手动命令: start / next / phase &lt;n&gt; / reset / show / hide

### DodoShield
- **SavedVariables**: DodoShieldDB ｜ **命令**: 通过设置面板
- 进战斗后按设定时间点做文字/声音提醒（例如「放罩子」）
  - 多方案（preset）管理，每方案独立外观与提醒行
  - 可调字号/颜色/位置/锁定，可选声音提示
  - Core.lua（提醒逻辑）+ Options.lua（方案与外观面板）

### DodoStatHUD
- **SavedVariables**: DodoStatHUDDB
- 实时角色属性 HUD 显示
  - 显示当前套装名、主属性（相对基线百分比）、暴击、急速、精通、全能、移速
  - 属性变化趋势箭头（▲/▼），可配置持续时间后自动隐藏；每项可独立显示/隐藏
  - 自定义颜色选择器；字号（8-40）、可拖动+锁定；主属性基线保存/重置；每 0.2 秒刷新
  - 使用 C_PaperDollInfo / C_EquipmentSet API；已按 Secret Values 加固（战斗中属性 secret）

### DodoUnholy
- **SavedVariables**: DodoUnholyDB ｜ **命令**: `/dodounholy config`, `/duh config`
- 邪恶死亡骑士食尸鬼提醒
  - 检测邪 DK 专精（spec ID 252）；宠物不存在或死亡时显示「宝宝没啦~~」警告
  - 仅地面状态显示（排除骑乘、载具、飞行点、死亡）
  - 可配置: 开关、字号（8-72）、垂直位置（-500~500）；选项面板带实时预览

---

## 通用技术模式

- **语言**: Lua (WoW API)。UI 文本多数中文；`DodoInspect` 四国语言跟随客户端；
  上了 CurseForge 的插件（`DodoBricks` / `DodoLura` / `DodoNameplate` / `DodoSays` …）
  TOC 的 `## Notes` **一律英文**（商店页读它），中文说明另开 `## Notes-zhCN`（可选，现有两个插件带）。
- **整合包结构**: 父包 `Dodo` 提供 `Dodo/Media/` 共享素材与公共库 `_G.Dodo`（`Shared.lua`）；
  子插件 TOC 写 `## Group: Dodo` + `## OptionalDeps: Dodo` 归入「Dodo 插件包」。
  **例外见「仓库级约定 §3」**（独立发版的两个不挂，自带图标）。
- **数据持久化**: SavedVariables + 深拷贝（`CopyDefaults`）保护已有数据。
- **命名规范**: 插件名以 `Dodo` 开头，全局变量 / 函数以插件名为前缀。
- **12.x Secret Values**: 这是本仓库出现频率最高的技术主题（战斗属性 / 敌对单位身份 /
  `spellID` / `UnitGUID` 等大量 API 返回 secret）。
  🔑 **判断某个 API 现在还给不给值，别靠记忆也别只读契约 —— 用 `DodoProbe` 真机量一次**
  （`/dp`，结果落 `WTF/.../SavedVariables/DodoProbe.lua`，`/reload` 才落盘）。
  平台级结论（哪些控件方法吃 secret、契约怎么读、探针怎么用）住 canon `rules/wow-addons.md`；
  各插件自己踩的坑住它自己的 `CLAUDE.md` / `GOTCHAS.md`。
- **错误处理**: `pcall` 包裹 + 安全类型转换；`isSecret` 见「仓库级约定 §3」。
- **设置面板**: `Settings.Register*` 集成进游戏设置。
- **小地图按钮**: 极坐标定位，Shift+左键拖动。

---

## 开发计划 & 备注

- 所有 Dodo 插件为个人自用，按需迭代；上了 CurseForge 的那几个另受发版纪律约束（见上）。
- 新插件：名字以 `Dodo` 开头，TOC 抄现有的一份（`## Author: Doodo` + `## Group: Dodo` +
  `## OptionalDeps: Dodo` + `## IconTexture` 指向父包图标），然后**回来给「插件总览」补一行**。
  - ⚠ **要送出门给外人的插件是个例外**：那两行都指向 `Dodo` 那个父包文件夹，而对方**不会有它**
    —— 指过去只是个空图标。这类插件把 `OptionalDeps` 和 `IconTexture` **去掉**，让它能独立站住。
    （**DodoXuefei 是第一个**；下次看到某个 TOC 少这两行，先想想是不是这个原因，别当漏写补回去。）
- **新增插件文件夹后要完整重启客户端**（`/reload` 不发现新目录）。
- Plater 为外部第三方插件，不做修改。
- **重命名 / 合并史**: DodoItemLevelOverlay → **DodoInspect**（装等覆盖层主体）；
  旧 DodoInspect（目标信息）→ 并入 DodoInspect 的 `TargetInfo.lua`;
  DodoTarget 曾短暂存在后删除并入 DodoInspect。
- **跨机器**: 布局差异见本文「跨机器布局」一节。**各插件的 `CLAUDE.md` + 本文是跨机器传「坑」的
  唯一可靠渠道** —— 各机的 scope memory（`~/.claude/projects/<scope>/memory/`）**不跨机**，
  写在那儿的东西另一台读不到。
