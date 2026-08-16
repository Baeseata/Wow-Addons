# 实测:2026-08-15 单问号一轮完整 trace

> **证据等级:我方真机实测**（本文件是本项目唯一一份这个等级的东西）。
> 采集：HOME · 客户端 build **69299** · `/ds trace` 全程录 · 488 行 · 落 SavedVariables。
> 战斗：`?` 单问号，走完 90% 与 60% 两次中场，**30% 那次开场 3.5 秒团灭**（`success=0`）。
> ⇒ 第三轮只有 `CHANNEL_START`，**没有 `CHANNEL_STOP`，也没有第三轮 echo 数据**。

---

## 1. 三个问题的答案

| # | 问题 | 答案 |
|---|---|---|
| 1 | boss 每轮**开始施放**、以及**开始 echo** 有没有事件 | ✅ **有，而且干净**。`UNIT_SPELLCAST_CHANNEL_START` = 布道开始；`UNIT_SPELLCAST_CHANNEL_STOP` = 布道结束 **= echo 开始**（同一时间戳，见 §3） |
| 2 | **布道**的每个波次 | ❌ **没有。一个信号都没有。** 布道那 10.5 / 14.0 秒里 `boss1` 上**零事件**，而战斗日志**注册不了**（下条）⇒ 波次只能**靠时钟推** |
| 3 | 🔴 **echo 的每个波次** | ✅ **有，一波一次 `UNIT_SPELLCAST_START`**，3.00 秒后配一条 `SUCCEEDED`。第一轮 3 次、第二轮 4 次，跟波数**精确对上** |

🔴 **`COMBAT_LOG_EVENT_UNFILTERED` 注册被拒**（`ADDON_ACTION_FORBIDDEN`，加载期也拒）
⇒ **12.x 游戏内战斗日志对插件整个关闭**，不是脱敏是关闭。
这坐实了 canon `rules/wow-addons.md` 那句「combat-log **FILE** 还 fine offline」的言外之意。
**问题 2 因此没有第二条路可走。**

## 2. 实测数字

| 量 | 实测值 | 对照 |
|---|---|---|
| `ENCOUNTER_START` id（`?`） | **3508**，name=阿兹塔雷克，diff=**208** | ✅ 跟 SnakeSays 的 `ENCOUNTERS` 表一致 |
| boss token | **`boss1` 存在** | 同一次施法在 `nameplate2` / `boss1` / `target` **三个 token 各报一次**，时间戳相同 |
| 三次中场起点 | 19.272 / 135.447 / **250.206** | 按血量触发 |
| 布道时长 | 第一轮 **10.512s**（3 波）· 第二轮 **14.004s**（4 波） | |
| **布道每波** | **3.504 / 3.501 秒** | 🎯 SnakeSays 的 `SEED_SLOT.normal = 3.503` —— **几乎完全命中**，它的数据可信 |
| **echo 施法时长** | **3.00 秒**（START → SUCCEEDED，6 次全部 3.002~3.011） | 🔑 **这就是玩家的反应窗口**，此前没人量过 |
| **echo 波间隔** | **3.25~3.27 秒**（START → START） | ⚠ **跟布道的 3.50 不一样**，两个半场节奏不同 |
| 波数 | 3 / 4 | ✅ 坐实 `WAVES_BY_ROUND.normal = {3,4,5}` |

## 3. 交接是**同一个时间戳**

```
 29.784 UNIT_SPELLCAST_CHANNEL_STOP unit=boss1     <- 布道结束
 29.784 UNIT_SPELLCAST_START        unit=boss1     <- 第一波 echo
```
两轮都如此（29.784 / 149.451）。⇒ **`CHANNEL_STOP` 直接当「锁序列 + 转回放」用是安全的，不用留缓冲。**
✅ 坐实 SnakeSays 那句 "in the same hundredth of a second"。

## 4. 🔴 全部 secret —— 探针清单第 3、4 条的答案

```
UNIT_SPELLCAST_CHANNEL_START unit=boss1 id=<secret> name=<secret> start=<secret> end=<secret> id2=<secret>
```
**`spellID` / `name` / `startTime` / `endTime` 无一例外全是 secret**，`?` 上如此（`??` 未测）。

⇒ 三层降级链的**第 1 层（比 id）和第 2 层（比名字）在真机上永远走不到**，
`identifyEcho` **每一次都落到第 3 层「place」**。硬编码的 `SERMON_IDS` / `ECHO_ID` 实际是死代码
（留着不删：它们无害，且 `??` 或以后补丁可能变）。

⚠ **连带推论**：既然 name 和 id 都读不到，`findSermonChannel` **无法排除别的引导技能** ——
它实际是「boss 引导了任何东西 = 布道开始」。**本轮实测整场只有 3 次 `CHANNEL_START`，全是中场**，
所以这个推论在这个 boss 上成立。⚠ **它依赖「Azta'rec 只有一个引导技能」这个事实**，不是通则。

## 5. 🔴 这份数据当场抓出的一个真 bug

§4 那条推论**反过来咬**：既然 `identifyEcho` 每次都落到「place」，而 place 的判据是
「这是不是我们那个 boss 在施法」—— 那**主阶段的普通输出循环同样满足它**。

trace 里的实证：第一轮三波在 **39.306** 报完，紧接着

```
 41.016 UNIT_SPELLCAST_START unit=boss1     <- 主阶段技能（1 秒后被打断）
 45.855 UNIT_SPELLCAST_START unit=boss1     <- 又一个
```

**这两条在修复前都会被当成第 4、第 5 次报点** —— 而序列只有 3 个，报出来是 `nil`。
整场 114 次 `UNIT_SPELLCAST_START` 里，**真正是 echo 的只有 7 次**。

**修**：`onCall` 开头加 `if callCount >= #seq then return end` ——
**报满即停**，同一个判据顺带挡住开怪前的循环（`0 >= 0`）。

🔑 **为什么 30 条离线测试一条都没抓到它**：测试**只发了正好数量的 cast**，
从没问过「多发一次会怎样」。而且**每一条都跑在明文路径上**，
而真机**一个明文都没有** —— 那些测试验的是一条真实战斗永远不会走的分支。
⇒ 现在补了一节 `The real client: everything secret`，把 `issecretvalue` 照真机建模，
A/B 验过（拆掉围栏 → `got 8, want 6`，精确指出两次主阶段施法被误收）。

## 6. 仍然未知

- **`??` 全部**（8/18 才开）：分身「Echo of Azta'rec」撞名那条围栏、`5/6/7` 波数、`hard` 的 3.003 slot
- **第三轮（30%，5 波）** 本轮团灭没拿到 —— 但 1/2 轮的规律一致，5 波大概率同形
- **布道 spellID 每轮变不变**（SnakeSays 的说法）—— 本轮**验不了**，因为 id 全 secret
