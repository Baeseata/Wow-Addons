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
| 范围 | **只做 12.1 S2 的 Azta'rec** | 不追求跨赛季通用，spellID 可硬编码 |
| 人数 | **只做单人** | 坐骑/传说头衔本来就要求单人；组队同步得走 `/raid` 宏，复杂度翻倍 |
| 难度 | `?` 和 `??` 都吃 | 机制同族，只是序列长度不同（3/4/5 vs 5/6/7） |

⚠ **名字留了活口是故意的**：代码写死这赛季，但 `DodoSays` 不绑 boss 名 ⇒ 下赛季 nemesis 换了能在**同一个 CF 项目**发新版，省掉整套首发手工流程（新项目要过人工审核 + logo/zip 必须 Jerry 亲手点选）。`DodoLura` 是绑死 boss 名的反面样本。

## 2. HOME 机开工第一步 ⛔

**先跑探针，再写一行代码** → [`docs/PROBE-CHECKLIST.md`](docs/PROBE-CHECKLIST.md)

第 3 条（`UNIT_SPELLCAST_START` 的 `spellID` 到底是不是 secret）**直接决定工作量差一倍**：明文 ⇒ 一行比较；secret ⇒ 得写三层降级链。**契约回答不了这个问题，只有探针能。**

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

用 `RegisterUnitEvent(..., "boss1")` 做过滤 —— **引擎侧过滤，不需要读 unit token**（读了去比较会撞 `SecretWhenUnitComparisonRestricted`）。

📖 调研正文 → [`docs/RESEARCH-secret-values.md`](docs/RESEARCH-secret-values.md) · [`docs/RESEARCH-boss-mechanics.md`](docs/RESEARCH-boss-mechanics.md)

## 4. 竞品 = 参考实现,不是要打败的东西

**SnakeSays**（作者 lgkern / CF 作者名 Anshlun，~9.5K 下载）做的是**同一件事**，源码开放：`github.com/lgkern/SnakeSays`。它的 `Detector.lua` 已经把 secret 那条路跑通了，**照抄它的 secret 处理范式**（`isSecret` / `equals` 三态 / `usableNumber`），别自己重推。详见调研文档。

## 5. 发布（CF 项目**还没建**）

- Title: `DodoSays - Azta'rec Delve Memory Helper` · 分类 `Boss Encounters`
- 首发流程 / 项目 ID 登记两处 → repo 根 `PUBLISHING.md`（local-only）
- **打包白名单实查（2026-08-15，`.github/workflows/curseforge-release.yml:128`）**：只有
  `*.lua *.toc README.md LICENSE *.tga *.blp *.png *.ttf *.xml *.mp3 *.ogg` 进包
  ⇒ **`docs/` 下的调研文档天然进不了 CF 包**（`.md` 不在白名单，只有 `README.md` 例外）
- 🔴 **已知缺口**：`:143` 那道验收闸只 grep `CLAUDE\.md|/test/|/tools/`，**不含 `/docs/`**。
  今天靠白名单挡住，闸没参与。**哪天有人往白名单加 `-o -name '*.md'`，`docs/` 会静默进包而闸不报** ⇒
  真要放宽白名单，**同一个 commit 里把 `/docs/` 加进那条 grep**。
