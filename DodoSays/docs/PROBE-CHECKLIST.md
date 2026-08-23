# ⛔ 开工前先跑这个：DodoProbe 探针清单

> 2026-08-15 立。**写第一行 DodoSays 代码之前跑完。**
> 依据：canon `rules/wow-addons.md`「遇事不决,用探针 —— 别靠记忆、也别只读契约」。
> 探针加在 **DodoProbe** 的 `Run()` 里（它跟本插件同在该机的 AddOns 目录下；绝对路径见该机 `~/.claude/CLAUDE.md`），进副本 `/dp` 跑一次。

## 为什么必须先跑

契约（`docs/RESEARCH-secret-values.md`）明确留了一句口子：

> *"Individual spells may be flagged as never or always secret, **which takes priority**."*

**契约回答不了「这几个法术到底被标成什么」** —— 只有探针能。而第 3/4 条的结果**直接决定工作量差一倍**：
明文 ⇒ 一行 `==` 比较；secret ⇒ 得写 SnakeSays 那样的三层降级链。

## 在哪跑

**`?` 单问号现在就开着**（通关任意 T11 地下堡开门）→ 毒瀑深渊，盘卷蛇岛北部 `/way #2512 51.2 31.0`。
机制同族、只是序列短一截（3/4/5）。`??` 随 S2 赛季开服开放（2026-08-18）。
⚠ **`??` 量没量过别看本文写的,查 [`RESEARCH-live-trace.md`](RESEARCH-live-trace.md) 里有没有 `??`（encounterID 3525）的场次。**

---

## 清单

| # | 问题 | 怎么量 | 为什么要它 |
|---|---|---|---|
| 1 | `ENCOUNTER_START` 在地下堡 nemesis **触发吗** | 注册它，打印 encounterID + name | 整个状态机的 arm/disarm 靠它；不触发就得换别的 arm 条件 |
| 2 | nemesis 是不是 **`boss1`** | `UnitExists("boss1")` + `INSTANCE_ENCOUNTER_ENGAGE_UNIT` 时打印 | `RegisterUnitEvent` 的过滤依据；错了整条链收不到 |
| 3 | 🔴 `UNIT_SPELLCAST_START` 的 **`spellID` 是不是 secret** | 事件里 `issecretvalue(spellID)`，**别直接 print 那个值**（tostring 是一次使用，会抛） | **决定要不要写三层降级链** |
| 4 | 🔴 `UnitCastingInfo("boss1")` 的 **`name` 是不是 secret** | `pcall` 包住取值 → `issecretvalue(name)` | 降级链第 2 层（按名字比）成不成立 |
| 5 | 一次中场里 `UNIT_SPELLCAST_START` **真实触发几次** | 计数器 + 时间戳，跟屏幕上实际波数对 | 验证「一波 = 一次 cast」这个地基假设；同时量出杂散施法有多少（围栏要多严） |
| 6 | 布道走 **CHANNEL**、回响走 **CAST** 吗 | 两组事件各打一条带时间戳的日志 | 状态机切换全靠这个区分。目前只有 Wowhead 文字 + SnakeSays 事件注册两个间接证据 |

| 7 | 🔴 **`??` 场上两个 boss 时，`UNIT_SPELLCAST_START` 从哪个 unit token 来** | 记下每次 cast 的 unit + 是否等于「展示这一轮的那个 unit」 | 分身「Echo of Azta'rec」技能名也读作 "Echo of …"，作者实测**一轮 5 次报点被骗走 2 次**。不验这条，`??` 上会直接报错点 |

⚠ **第 1 / 2 / 6 条现在有预期答案了**（[`RESEARCH-snakesays-source.md`](RESEARCH-snakesays-source.md)：
`ENCOUNTER_START` 确实触发且带 encounterID `?`=3508 / `??`=3525；候选 unit 不止 `boss1`）——
所以这三条跑的时候是**核对**不是发现。**这更好**：对不上说明「客户端变了」或「探针没装上」，
而这两种**只有在有预期时才分得开**。第 3 / 4 条仍是纯发现（作者留三层降级链 = 他也没拿到稳定答案）。

---

## ✅ 实测结果 2026-08-15（`?` 单问号，build 69299）

**正文 → [`RESEARCH-live-trace.md`](RESEARCH-live-trace.md)。** 逐条对账：

| # | 结果 |
|---|---|
| 1 | ✅ `ENCOUNTER_START` **触发**，id=**3508**，name=阿兹塔雷克，diff=208 |
| 2 | ✅ **`boss1` 存在**。同一施法在 `nameplate2`/`boss1`/`target` 三个 token 各报一次 |
| 3 | 🔴 **`spellID` 是 secret**（事件 payload 和 `UnitChannelInfo` 都是）⇒ 三层降级链**必须留着**，且实际只走第 3 层 |
| 4 | 🔴 **`name` 也是 secret** ⇒ 降级链第 2 层在真机上**永远走不到** |
| 5 | ✅ **一波一次 cast，精确对上**：第一轮 3 次、第二轮 4 次。**杂散施法比预想多得多** —— 整场 114 次 `UNIT_SPELLCAST_START` 里只有 **7 次**是 echo |
| 6 | ✅ **布道走 CHANNEL、回响走 CAST，坐实**。且交接在**同一时间戳** |
| 7 | ⏳ **`??` 双 boss** —— 唯一还会改代码的一条。**量没量过 → 查 [`RESEARCH-live-trace.md`](RESEARCH-live-trace.md) 有没有 `??`（3525）场次**，查不到就是还没量 |

🔴 **额外发现（清单上没有、但更要命）**：**`COMBAT_LOG_EVENT_UNFILTERED` 注册被拒**
（`ADDON_ACTION_FORBIDDEN`，**加载期也拒**）⇒ 12.x 游戏内战斗日志对插件**整个关闭**。
配合「布道半场零 `UNIT_*` 事件」⇒ **布道的逐波时刻在 12.x 拿不到，只能靠时钟推**。

## 探针纪律（canon + SnakeSays 源码，别踩）

- 🔴 **不许 `print(spellID)` / `tostring(spellID)`** —— `tostring` 本身就是一次「使用」，secret 会抛，**而抛出去会把整个 handler 干掉且无声无息**。一律先 `issecretvalue()` 判、再决定要不要碰。
- 🔴 **先判 unit、再碰 spellID**。副本里绝大多数施法不是 boss 的，没必要为它们去摸一个可能是地雷的值。
- 🔴 **每个字段用之前都 `pcall` 证明可用** —— SnakeSays 的原话是 *"every field is proved usable before it is used"*。
- ⚠ **「没触发」和「探针没装上」从外面看一模一样** —— 先塞一条必定会打印的行当对照，确认 `/dp` 真的跑到了这段。

## 跑完之后

把每条的实测结果**直接写回本文件**（在表格下面加一节「实测结果 YYYY-MM-DD」），
并回头修正 `RESEARCH-secret-values.md` 里那两条标着「未经实测」的断言。
⚠ **别只在聊天里说** —— 下一个 session 读的是文件。
