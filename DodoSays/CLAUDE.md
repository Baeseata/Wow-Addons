# DodoSays — 开发简报 (read me first)

> 阿兹塔雷克（Azta'rec）地下堡 nemesis 的**记忆游戏辅助**。Dodo 系列之一。
> 仓库 `Baeseata/Wow-Addons`（**public**），插件在 `DodoSays/`。
> **换机器先 `git pull` + 读本文件。UI 文案用英文**（中文是 Jerry 跟 Claude 的设计沟通语言）。
> 立项 2026-08-15（OMEN，纯调研 session，**零代码**）。开工在 HOME。

---

## 1. 这是什么 / 边界（已拍板，别再讨论）

玩家在**布道阶段手动点四象限**记下安全点顺序 → **回响阶段插件按顺序报点**。

| 决定 | 值 | 理由 |
|---|---|---|
| 名字 | **DodoSays** | Simon Says 梗；CF 全站 `Dodo*` 前缀实测独占 |
| 范围 | **只做 12.1 S2 的 Azta'rec** | 不追求跨赛季通用。⚠ **但「spellID 可硬编码」只对「回响」成立** —— 布道的 id **在 `?` 上每轮都变**（详 [`docs/RESEARCH-snakesays-source.md`](docs/RESEARCH-snakesays-source.md) §1.2） |
| 人数 | **只做单人** | 坐骑/传说头衔本来就要求单人；组队同步得走 `/raid` 宏，复杂度翻倍 |
| 难度 | `?` 和 `??` 都吃 | 机制同族，只是序列长度不同（3/4/5 vs 5/6/7） |
| **什么时候生效** | **只有 `ENCOUNTER_START` 的 id ∈ {`3508`=`?`, `3525`=`??`} 才 arm**，其余一概不理，**读不到 id 也不理**（fail-closed） | 2026-08-15 实撞：初版拿 id **只用来查波数、却无条件 arm** ⇒ 打五人本时盘面冒出来了。**每个 boss 都会引导点什么**，所以那个 id 必须是**门**不是提示。⚠ 代价是暴雪哪天把 encounterID 变 secret，插件会**安静地不工作** —— 那也比在每个副本乱弹强 |
| **盘面怎么上色** | **回响半场是个红绿灯**:绿 = 这一波站这儿 · 黄 = 下一波去哪儿 · 其余红。**布道半场不上红绿灯**,点过的格子是**蓝**的。🔴 **四个标记图标永不去色**,任何阶段都保持本色 —— 强调只走透明度,而且**只有「这一波不安全」那两个才变暗** | 2026-08-16 Jerry 拍板(照 CF 上 `Azta'rec Helper` 的画风)。🔑 **蓝不是随便挑的** —— `recorded` 原来是绿,于是绿在同一块盘面上说两件相反的事(「我记下了」vs「现在站这儿」)。⚠ **上色从「锁序列」那一刻开始,不等第一波**:`CHANNEL_STOP` 和第一次 echo 是**同一个时间戳**,等报点才亮 = 最需要提前量的那一波零反应时间。⚠ 最后一波**只有绿没有黄**;`finish` 在最后一波的 **START** 就来,所以 `Board.Finish` **不许**把 phase 打成 `done`(那会在还剩 3 秒施法时把灯灭掉 —— 2026-08-16 离线抓到)。⛔ **箭头 / true-north radar 结构性做不了**(2026-08-16 实测,副本内 190 条 vs 副本外 30 条对照):`UnitPosition` / `GetPlayerFacing` / `GetPlayerMapPosition` 在副本里**全是 `nil`**,外面全给。**是 `nil` 不是 secret** —— secret 还能塞进控件让 C 层画,`nil` 画都没得画。⚠ `UnitPosition` 的**第 4 个返回值照给**(3079)⇒ 调用没被拒、没抛异常,是**故意只 nil 掉那三个坐标**。契约层(build 69214)这四个 API **一个 secret 标注都没有**,照契约读会得出「能用」这个干净的错结论 |
| **象限怎么认** | **团队标记**，开怪前在地上打好，顺时针 **红叉(7) → 方块(6) → 三角(4) → 大饼/橙圈(2)** | 2026-08-15 Jerry 拍板，替换掉初版的东南西北。🔑 **标记画在地上，不随镜头转**；而「北在哪」**每一波都要重新心算一次**，偏偏那是全场最没时间算的两秒。⇒ 盘面和报点**都以图标为主、文字为辅**。⚠ 插件读不到房间朝向（无 `UnitPosition`），所以**顺序约定是插件和玩家之间的口头协议** —— 改这个顺序 = 改协议，`tools/test_detector.lua` 的 `Marker layout` 那条会红 |

⚠ **名字留了活口是故意的**：代码写死这赛季，但 `DodoSays` 不绑 boss 名 ⇒ 下赛季 nemesis 换了能在**同一个 CF 项目**发新版，省掉整套首发手工流程（新项目要过人工审核 + logo/zip 必须 Jerry 亲手点选）。`DodoLura` 是绑死 boss 名的反面样本。

## 2. HOME 机开工第一步 ⛔

> ⚠ 本节原写「**先跑探针，再写一行代码**」。**2026-08-15 HOME 改判**：M1 代码已落地。
> 理由 —— 那条铁律的真实依据是「第 3 条决定工作量差一倍」，而**三层降级链的形状本身就不依赖那个答案**
> （明文走第 1 层、secret 走第 2/3 层，架构一样）。⇒ 探针**仍然要跑**，但它不再是**开工闸**，
> 而是「能不能省掉后两层」+ 核对客户端行为。

探针清单 → [`docs/PROBE-CHECKLIST.md`](docs/PROBE-CHECKLIST.md)（第 7 条 `??` 双 boss 是**唯一还会改代码**的一条）

**离线测试**（不用进游戏，本机 Lua 5.4 直接跑）：
```
cd D:\World of Warcraft\_retail_\Interface\AddOns\DodoSays
lua tools/test_detector.lua
```
它加载**真的** `Util/Board/Announce/Detector`（只 stub 客户端 API），跑真事件 handler。

🔴 **harness 的默认世界 = 真机世界：凡它递给插件的值一律 secret**（2026-08-16 反转，此前是明文，
一晚上因此栽了三次 —— spellID → name → GUID，每次都得再打一趟副本才发现）。
- 想要**明文**必须在调用点写出来：`H.channelStart("boss1", { from = H.plain(1000), to = H.plain(22021) })`，
  并在注释里说清**为什么这条测的是可读那支**。跑完末尾会报「本次共 N 个 client value 声明为可读」——
  **那个数往上走 = 测试正在漂回真机不走的路**。
- **裸字面量直接报错**并点名字段（`cast spellID = 1288125 is a raw literal…`），忘了想 secret 是一声硬错，不是静默。
- 唯一的声明例外 = `ENCOUNTER_START` 的 id（实测**可读**，3508 / 难度 208），
  它是门；想演「哪天它也 secret 了」用 `H.whileSecret(3508, …)` —— ⚠ **必须是替身式**
  （mint 一个新号出来测,它是因为号不对才不 arm，跟 secret 无关，A/B 会直接走过去）。

🔴 **哪几条最值钱（都 A/B 验过，红且指得准）**：`Fence`（拆掉 `isOurBoss` → 3 条红）·
`a SECRET encounter id fails closed too`（Arm 去掉 `usableNumber` → 红）·
`a secret GUID is not stored as though it were one`（`guidOf` 不再滤 secret → 红）·
`main-phase rotation is not mistaken for calls`（去掉「报满即停」→ 红）。
⚠ **`isOurBoss` 里的 `== true` 单独种回去是绿的** —— 它够不着，因为 `guidOf` 已经把 secret 滤成 nil。
**两处一起坏才复现 8/15 那个「整场零报点零报错」**（实测 18 条红）。⇒ 这两道防线是**一对**，
别因为「单独拆掉测试没红」就以为哪一道是多余的。

`?` 单问号**已经开着**（打通任意 T11 地下堡即开门），机制同族、只是短一截，现在就能量。`??` 2026-08-18 赛季开服才开。

## 3. 架构（调研已确认可行，未实测）

| 事件 | 动作 |
|---|---|
| `ENCOUNTER_START` | arm，重置 |
| `UNIT_SPELLCAST_CHANNEL_START` / `_UPDATE` | 布道开始 → **记录态**，亮四象限按钮 |
| `UNIT_SPELLCAST_CHANNEL_STOP` | 布道结束 → 锁序列，转**回放态** |
| `UNIT_SPELLCAST_START`（每次） | 回响的一波 → 报序列里的下一个 |
| `ENCOUNTER_END` | disarm |

🔑 **回响的每一波各是一次独立 cast** ⇒ 节拍不用推测也不用测量，事件来一次报一个。**不需要知道是哪个法术。**
⚠ 但**不能无脑数所有 cast**：实测数据（SnakeSays 作者日志）一次战斗 boss 施法 7 次、只有 3 次是报点 ⇒ 必须有围栏（「已有 round 在进行中」）。

🔴 **但上面那条只对「回响」半场成立 —— 布道半场是看不见的**（无 cast / 无伤害 / 无逐波事件，整段只有一次 channel）
⇒ 那半场的波数**只能靠时钟推**（时长 ÷ 每波秒数），两个半场是两套机制。详 [`docs/RESEARCH-snakesays-source.md`](docs/RESEARCH-snakesays-source.md) §1.1。

用 `RegisterUnitEvent(..., "boss1")` 做过滤 —— **引擎侧过滤，不需要读 unit token**（读了去比较会撞 `SecretWhenUnitComparisonRestricted`）。
🔴 **`??` 上这不够**：分身「Echo of Azta'rec」的技能名也读作 "Echo of …"，**只判「来自 boss 框体」会全放行**
（作者实测：一轮 5 次报点被骗走 2 次）⇒ 必须按「**哪个 boss 展示的这一轮，就认哪个**」。同上文 §2.2。
⚠ 且**地下堡不保证给 nemesis 一个 boss token** —— 探针第 2 条必须真跑，别照抄 `boss1`。

📖 调研正文 → [`docs/RESEARCH-secret-values.md`](docs/RESEARCH-secret-values.md) · [`docs/RESEARCH-boss-mechanics.md`](docs/RESEARCH-boss-mechanics.md) · [`docs/RESEARCH-position-apis.md`](docs/RESEARCH-position-apis.md)(**坐标为什么一条路都没有**,含 613 份契约全量扫)

## 4. 竞品 = 参考实现,不是要打败的东西

**SnakeSays**（作者 lgkern / CF 作者名 Anshlun，~9.5K 下载）做的是**同一件事**，源码开放：`github.com/lgkern/SnakeSays`。它的 `Detector.lua` 已经把 secret 那条路跑通了，**照抄它的 secret 处理范式**（`isSecret` / `equals` 三态 / `usableNumber`），别自己重推。
📖 **源码实读结论 → [`docs/RESEARCH-snakesays-source.md`](docs/RESEARCH-snakesays-source.md)**（2026-08-15 HOME 补，
含 encounterID `?`=3508 / `??`=3525、每波秒数、`??` 分身撞名、`C_UnitAuras` 被前置拒绝、`UnitPosition` 不给数据）。

## 5. 发布

- **CF 项目 `1654722`**(2026-08-16 建;`Boss Encounters` · All Rights Reserved ·
  distribution 选**不给第三方**,跟 DodoInspect 对齐)。
- ⚠ **project id 只写在 TOC 的 `## X-Curse-Project-ID`** —— repo 那个 workflow **优先读它**,
  里面那张 case 表只是老插件的兜底,**新插件不用去改 workflow**。
- **发到哪一版 / 过审没有 → 查 CF 项目 1654722 的 Files 页**,别信 doc 里写的数字。
- 发版顺序:改 TOC `## Version` → **push 代码**(zip 取自 tag 那个 commit)→
  Actions 手动跑一次 **`dry_run=true`**(真打包 + 验 token + 解析游戏版本,不上传 —— 免费的负对照)
  → 打 **annotated** tag `DodoSays-vX.Y.Z` → CI 自动传。
  🔴 **lightweight tag 会把 commit message 当 changelog 甩上 CF**(而我们的 commit message 是中文)
  ⇒ 判据:`git cat-file -t <tag>` 必须回 **`tag`**,回 `commit` 就是 lightweight。
- **发版账本 = Actions 运行记录 + CF 回的 `{"id":…}`**,不是 tag(tag 会被删,那两样不会)。
- **打包白名单实查（2026-08-16 重核 `.github/workflows/curseforge-release.yml:129-131`）**：只有
  `*.lua *.toc README.md LICENSE *.tga *.blp *.png *.ttf *.xml *.mp3 *.ogg` 进包，
  **并且同一条 `find` 带 `-not -path './test/*' -not -path './tools/*' -not -name 'CLAUDE.md'`**
  ⇒ **`tools/` 里的 harness 和测试是被路径排除挡住的，不是靠 `*.lua` 白名单**（`*.lua` 反而会收它们）
  ⇒ **`docs/` 下的调研文档天然进不了 CF 包**（`.md` 不在白名单，只有 `README.md` 例外）
  ⇒ 只动 `tools/` 的改动**不产生可发布内容,不需要发版**
- 🔴 **已知缺口**：`:143` 那道验收闸只 grep `CLAUDE\.md|/test/|/tools/`，**不含 `/docs/`**。
  今天靠白名单挡住，闸没参与。**哪天有人往白名单加 `-o -name '*.md'`，`docs/` 会静默进包而闸不报** ⇒
  真要放宽白名单，**同一个 commit 里把 `/docs/` 加进那条 grep**。
