# DodoSentinel — 设计档案

> **陵寝哨兵（Entombed Sentinels）「数字游戏」中场的报点名 + 打标插件。**
> **2026-08-24 立项，本文写下时零代码** —— 这是一份**设计记录**，不是使用说明。
> 开工前从头读一遍，尤其是 §5「必测项」和 §6「已经被推翻的结论」。

## 0. 一句话

五个「1 绿」玩家各按一个宏报到 → 团长的插件把报到者**渲染**出来（读不了，只能画）
→ 团长在自建 grid 里手点给他们上 1–5 号团队标记 → 中场结束手动清除。

**为什么这么绕**：12.x Secret Values 下，球数读不到、聊天发送者读不到、
自动打标已被 Blizzard 关闭。**唯一没被关的是「人的眼睛」和「人的一次点击」。**

## 1. 关键 ID

| 项 | 值 |
|---|---|
| Boss | Entombed Sentinels，团本 **The Venomous Abyss（烈毒之渊）** 第 2 个 |
| DungeonEncounterID | **3445**（mapID 3004 / journalEncounterID 2874） |
| Boss NPC | Breath of Ula'tek **258557** + Blood of Ula'tek **258558** |
| 机制主 debuff | **Helical Toxins / 螺旋毒素 = 1284590**（可叠层，`CumulativeAura = 99`） |
| 上球的施法 | **Vitriolic Stasis 1284588**（DBM 别名 `MATHPUZZLE`；NSRT 叫 "Number Game"） |
| 配错惩罚 | Cultivated Burst **1284941 / 1284947** |
| 伤害载体 | **1284813**（1284590 自己不带伤害） |
| 史诗额外机制 | Shifting Protovenom **1296878**（施法）/ **1296880**（光环），BigWigs 标 `mythic = true` |
| 同名未排除变体 | **1301776 / 1301777 / 1301779**（各带独立 AreaTrigger，被 **1301781** 统一移除） |

## 2. 机制事实（已核）

- 20 人史诗分布：**10 人 2 绿 · 5 人 3 绿 · 5 人 1 绿**（绿总数 40 = 10 对 × 4）
- 规则只有一条：**两人绿球数加起来 = 4**（红球数是 `4 − 绿`，自动满足，不是第二个条件）
- 凑够 4 层 → 无害解除。wowhead tooltip 原文：
  *"Reaching exactly 4 applications of Helical Toxins neutralizes the venom, removing it harmlessly."*
- **绿球 = 1284590 的层数**（`applications`），**红球没有独立 spellID**
- 它是 **debuff（HARMFUL）**，不是 buff；球是**头顶 3D 特效**，不是图标
  （1284590 的图标是块血石 `inv_112_warlock_bloodstone`）
- debuff 时长 **28 秒**（`SpellDuration` 556）

⚠ **只标 5 个「1 绿」就够** —— 3 绿的人去找带标记的人即可，2 绿的自己凑（Liquid 首杀就是
「2 号全去 boss 脚下、1 号原地跳、3 号去找跳的人」）。

## 3. 市面上没有同类插件（2026-08-24 全网扫过）

全网**只有一条代码**碰过 1284590：一个 wago 包朗读 "group of four"，**纯存在检测**。
BigWigs / DBM / NSRT 对这个机制**都只有一个到点弹的提示**。
WeakAuras 零售已死（2026-01-28 删了 retail toc）。中文圈、韩文圈零插件。

🔑 **Method 4 把、Liquid 7 把过** —— 4 把过的机制不产生工具需求，这可能比任何搜索结果
都更能解释为什么没人做。

## 4. 设计定稿

### 4.1 数据流

```
[1绿玩家] 按宏  →  /raid 3-2          (小队-位次，插件战斗外生成)
                        ↓ CHAT_MSG_RAID（内容和发送者都是 SECRET）
[团长插件] 不解析，只渲染：
    报到行  = [到达序号 明文] [职业图标] [名字 职业色] [3-2]
    grid    = 对应格子亮起（← 见 §5-③，未验）
                        ↓
[团长] 左键连点五格 → 上 1..5 号标记（snippet 自增计数器）
[团长] 右键逐个清 / 或一键 clear-all（⚠ 会抹掉坦克标）
```

### 4.2 三个组件

1. **玩家端**：战斗外按 `GetRaidRosterInfo` 拿自己的小队+位次 → `CreateMacro`/`EditMacro`
   生成 `/raid <小队>-<位次>`。面板上显示"你的宏 = 3-2"供本人自查。
2. **团长端报到列表**：监听 `CHAT_MSG_RAID`，`SetFormattedText` 多个 `%s` 各塞一个 secret，
   **不做任何 Lua 拼接**。固定行高固定列宽。
3. **团长端 grid**：自建，格子是 `SecureActionButtonTemplate`，`unit` 绑静态 `raidN`，
   战斗外全部预建 + 预 wrap。

### 4.3 号段纪律

**机制固定用 1–5（星/圆/钻/三角/月），坦克和击杀顺序用 6–8（方/叉/骷髅）。**
⇒ `clear-all` 会抹掉坦克标，**别放进主流程**，要放也藏在修饰键后面。

## 5. 逐环判定表

| 环 | 判定 | 卡在哪 / 靠什么 | 闸类别 | 置信 |
|---|---|---|---|---|
| 读球数（层数） | ❌ **死** | `applications` 在 `SecretWhenUnitAuraRestricted` 下，谓词原文含 **encounter** | secret | 高 |
| 玩家端生成 `3-2` 宏 | ✅ | `GetRaidRosterInfo` 自己那行明文；`CreateMacro`/`EditMacro` 只在战斗中被 block | — | 高 |
| 宏发 `/raid` 到得了别人吗 | ⚠ **未验** | `SendChatMessage` 带 `RestrictedForMacroChatMessages`：「遭遇战期间限制**宏发起的**、外部玩家可观测的聊天类型」。`/raid` 算不算未定 | combat-blocked? | **必测 ②** |
| addon 消息替代 `/raid` | ❌ **死** | `SendAddonMessageResult.AddOnMessageLockdown = 11`；BigWigs 静音 11、DBM 直接不发 | combat-blocked | 高 |
| 读报到者身份 | ❌ **死** | 17 个玩家频道**全部**带 `SecretInChatMessagingLockdown`，`text`/`playerName`/`guid` 均无 `NeverSecret` | secret | 高 |
| 洗成明文 unit token | ❌ **死** | **secrecy 会传播**：本机 DodoProbe 2026-08-17 实测同刻带明文正对照 | secret | **高（量过）** |
| 渲染名字 | ✅ | `FontString:SetText` = `AllowedWhenTainted` | — | 高 |
| 名字带职业色 | ✅ | `UnitClassFromGUID` → `GetClassColor` → `WrapTextInColor` → `SetText`，四环全吃 secret | — | 中高 |
| **小队号从报到侧推导** | ❌ **死** | 能吃 secret GUID 的函数全网只有 6 个，没一个给小队 | secret | 高 |
| grid 格子自动亮 | ⚠ **未验** | 见 §5-③ 的贴图路径招 | — | **必测 ③** |
| 团长手点上标 | ✅ | `SECURE_ACTIONS.raidtarget`，真人点击 | hardware-event | 高 |
| 连点五次给不同号 | ✅ | snippet 自增，**12.1 有在产先例**（见 §8） | — | 高 |
| 逐个清除 | ✅ | `action="clear"` → `SetRaidTarget(unit, 0)`，按**单位**寻址 | — | 高 |
| **定向清除某个 mark** | ❌ **不存在** | 只有按单位清和全清；`ClearRaidMarker(index)` 是**世界标记**专用 | not-exist | 高 |
| 自动清除（不用人点） | ❌ **死** | `SetRaidTarget`/`RemoveRaidTargets` 都 protected；snippet 的 `HANDLE:` 67 个方法**没有 `Click()`** | protected | 高 |
| 团长权限 | ✅ | 团长本来就有。**普通团员打标会静默失败**（无 ERR_ 字符串） | permission | 高 |

## 6. 🔴 必测项 —— 按优先级，动代码之前先测

### ① 3 单位限流（**最便宜、风险最高，城里五个人就能测**）

> 蓝贴原文："Macros are prevented from setting a target marker on **more than 3 units within a
> very short time**."

**团长方案把 5~10 次标记操作全压在一个客户端上 —— 正好是这条限流针对的形状。**
而 `SetRaidTarget(unit, 0)` 本身就是一次 SetRaidTarget 调用，**清除大概率也算数**。

现网前科：2026-03 有团长/助理被 `/tm` 拒（`ERR_CLIENT_LOCKED_OUT`），报告原话
*"works for first 3 marks, then the bug is back"* —— 计数器不复位。暴雪承认并热修过。

- **判据**：五人组队站城里，团长连点五下，看第 4、5 个上没上
- **失败签名**：**静默** —— `GetRaidTargetIndex` 无条件 secret，**插件测不出来**，只能靠眼睛
- **挂了怎么办**：退回「五人自标」，把 `3-2` 编码搬到玩家那边当**天然不重复的号**
  （20 个坐标 → 1–5 的映射表战斗前算好写进各自的宏）⇒ 每客户端只标 1 个单位，够不着闸

### ② 宏发 `/raid` 在遭遇战中发不发得出去

整个设计最靠前的前提。挂了则**入口就断**，前面所有设计归零。
NSRT 在 L'ura 和 Sszorak 两处在产用 `/raid` 宏是**强旁证，不是证据**。

### ③ 贴图路径找不到时，引擎画什么

**这条决定 grid 能不能自动亮。** 招法：

```
格子 3-2 → SetTexture(".../hl/3-2_" .. secretWord .. ".tga")
只 ship 对角线那 20 个文件（3-2_3-2.tga 等）
⇒ 词是 "3-2" 时只有那一格路径解析得出来
```

**相等判断整个搬进 C 层**：插件不读、不比较、不索引。而且**永远不 Show/Hide**
（路径存不存在决定画不画），绕开"战斗中动不了受保护框体子件"那条。

- **画空白** ⇒ 成立 ✅
- **画占位图** ⇒ **20 格全亮 = 自信的错答案**，比不做更糟 ❌
- 旁证倾向空白：NSRT 整套符文显示压在这条上，有人打字就路径不存在，在产无人抱怨
- ⚠ 但那是**内联 `|T...|t` 标记**，我们用的是 **`Texture:SetTexture`**，**不能直接外推**

### ④ `UnitTokenFromGUID` 在 secret 下的返回形态

已知返回是 secret（不能选格子），但**画出来的 `raid7` 可以当第二个地址**。
待测：字符串形态、非本团 GUID 返回什么、跨花名册变动稳不稳。

### ⑤ 其余

- 战斗中调 `EditMacro` 是抛错还是**静默 no-op**（静默的话天真实现"看起来能跑"）
- `C_ClassColor.GetClassColor(secretToken)` 返回 nil 还是 secret color
- 「一个图标只能在一个单位上」（"偷"行为）—— 依据是模拟器实现，**中高置信、没实测**

## 7. 已经被推翻的结论（**别重走**）

| 曾经的结论 | 实际 |
|---|---|
| 「`CHAT_MSG_ADDON` 无 lockdown 标注 ⇒ addon 通信在遭遇战存活」 | **反的**。拦截在 **send 层**，而生成文档不标注 send 层 |
| 「1284590 是 Private Aura」 | **无证据**。`AddAuraSound` 是**通用**光环 API；BigWigs 真正的私有光环 API 已 `[DEPRECATED]` |
| 「`GetUnitAuraInstanceIDs` 没 secret 标注 ⇒ 能用来差分」 | **反的**。它带 `RequiresUnitAuraAccess`，FailureMode = **Error**。**没标注 ≠ 能用** |
| 「NSRT 的 `UnitClassFromGUID` 证明返回是明文」 | **不证明**。下游全吃 secret，没有一次比较 ⇒ 非判别性实验。真相是**传播**（实测） |
| 「secret 被布尔测试会报错」（我们自己 `DodoNameplate/GOTCHAS.md` §S1） | 对**非布尔**类型的 secret 做真值测试**合法**（恒真）。作为保守家规没问题，**作为契约陈述是错的** ⚠ 改那条 doc 前先实测 |
| 「用 `action="set"` 因为它不读 secret」 | **错**。`set` / `set-unmarked` / `toggle` **都读** `GetRaidTargetIndex`，只有 `clear` / `clear-all` 不读。用 `set` 的真实理由是**确定性** |
| 「到达计数可以防撞号」 | **数学上不成立**：五人同时看到特效同时按，选号发生在消息往返**之前**。T=2s / w=100ms ⇒ **碰撞率 59%**。而且撞号是"**偷**"，先按的人**看不到自己被偷** |
| 「让玩家自编码**团队编号**」 | 团队编号是**紧凑的**，有人离队全体 −1，而战斗中改不了宏，**插件还发现不了过期** |
| 「编**小队号**」 | 20 人 4 队 5 个报到 ⇒ **鸽笼，概率 1 必撞**。⚠ 但 `3-2`（小队+位次，20 个值）**不吃这条**|
| 「本机零个在产插件做 snippet 改属性」 | 真但没用 —— Cell/Grid2/ElvUI/Plumber/MiliUI **本机一个都没装** |

## 8. 实现要点

### 8.1 grid 格子（secure button）

🔴 **裸属性名是查找链的末位** —— `SecureTemplates.lua:29` 注释：裸 `marker` 等价 `*marker*`。
`DodoGrid` 就是因为已经设了 `*type1="target"` / `*type2="togglemenu"`，裸 `type` 不会生效。
**我们从零建，直接设 `*type1` / `*type2`，不留坑。**

🔴 右键更阴：`SecureUnitButton_OnClick` 里
`if expectBinding and bindingType == None then return end` —— `togglemenu` 会让右键
**在任何 action 派发之前就早返回**。

⚠ **`RegisterForClicks` 只注册单边**（`"AnyDown"`）。双边会让 snippet 跑两次而标记只放一次
—— **静默开环漂移，而且查不出来**。

### 8.2 snippet 自增计数器

在产先例（12.1，`## Interface: 120100`）：
`xod-wow/_LiteLite` → `modules/RotatingMarker.lua`

```lua
SecureHandlerWrapScript(b, 'OnClick', b, [[
    local n = ( self:GetAttribute("n") or 0 ) % 5 + 1   -- 我们用 %5,号段 1–5
    self:SetAttribute("n", n)
    ...
]])
```

- 🔑 **计数器放 header 的属性上**，不放格子自己 —— 否则点五个不同格子每个都给 1 号
- 放**帧属性**而非受限环境全局：**不安全 Lua 也能读出来显示**（面板写"下一个：4 号"）
- **wrap `OnClick` 不是 `PreClick`** —— OnClick 与 delegate 读 `marker` 的先后**在 Lua 源码里可证**；PreClick 只有在产行为佐证
- 🔑 **「受保护」不是障碍，是使能条件**：安装 wrap 时暴雪断言 `if not issecure() then error() end`，它没开火 ⇒ **属性写入这层间接把 taint 洗掉了** ⇒ 这才是 protected 的 `SetRaidTarget` 能被调用的原因
- **白名单里没有任何时钟**（`GetTime`/`time`/`date` 全无），`OnUpdate` 不在可 wrap 的 12 个脚本里
  ⇒ **定时自动重置做不到**，重置只能靠修饰键 / state driver 进出战斗 / 专门按钮
- 语法闸：body 里不许有 `function` 这个词（裸子串匹配）、不许有 `{` `}`
- **装 wrap / driver 战斗中硬 error** ⇒ 全部战斗外预建。**开打后进团的人这场没有可用格子**

### 8.3 渲染 secret

- `SetFormattedText` 是**变参**，多个 `%s` 各塞一个独立 secret，**不做 Lua 拼接**
- ⛔ **别抄** `C_ClassColor.GetClassColor(t) or RAID_CLASS_COLORS[t]` —— 后半截**拿 secret 当表 key，当场炸**
- ⛔ **不能用 secure object pool**（暴雪注释：一个 secret 对象进池，之后所有 acquire 都变 secret）。用普通 pool + **`ClearText`**（官方复位，移除 Text secret aspect）
- ⛔ **固定行高固定列宽** —— `GetStringWidth` 在 secret 文本上**也返回 secret**（契约看着像明文，是错的）
- 🔴 **必须 sanitize**：`C_StringUtil.EscapeQuotedCodes` 转义所有 `|`。你在渲染一段**永远读不了的、别的玩家输入的**文本，而它要进 markup 字符串
- `Show()`/`Hide()` 零标注永远安全；`SetShown` 是 `AllowedWhenUntainted`，**别喂 secret bool**

### 8.4 能自动化的（不碰受保护动作）

挂 `ENCOUNTER_TIMELINE_*` 事件：报到面板自动清空（`ClearText`）、高亮贴图自动熄灭
（`SetTexture(nil)`）、面板自动显隐、提示"本轮结束"。
⇒ **屏幕能恢复干净，只有游戏里那五个真标记需要人点。**

## 9. 分发（OMEN 写 → HOME 测）

```
OMEN  ~/Code/Wow-Addons/DodoSentinel/   ← 在 clone 里改 → commit → push
HOME  没有 clone。拉 monorepo 到临时目录 → 把文件夹拷进 live AddOns
```

- 🔴 **live AddOns 不是 git 树也不是 junction** —— clone 改了游戏里不会变，**必须手动拷**
- 🔴 **新建插件文件夹要完整重启客户端**（WoW 只在启动时扫 AddOns，`/reload` 不重扫）
- ⚠ **CRLF/LF**：clone 是 CRLF、live 是 LF ⇒ 裸比哈希会说"全都不一样"。
  比对 `git diff --no-index --ignore-cr-at-eol`，导出 `git -c core.autocrlf=false archive`
- ✅ **别打 tag** —— monorepo 发版 workflow 只在 `DodoSentinel-vX.Y.Z` 上触发。自用件不打就不会上 CF
- 🎁 迭代期走 `~/Sync/`（两机 Syncthing）比 git 快，但**每个能跑的版本仍要 push**，
  否则没历史没回滚

## 10. 参照物（照抄这些，别照抄 wiki）

| 要抄什么 | 去哪看 |
|---|---|
| snippet 自增 + 战斗中改属性 | `xod-wow/_LiteLite` → `modules/RotatingMarker.lua` |
| `type1="raidtarget"` 标记网格 | `MiliUIPackage/MiliUI` → `AddOns/MiliUI_Focus/Modules/MarkBar.lua` |
| secret 当贴图路径渲染 + 到达顺序占坑 | 本机 `NorthernSkyRaidTools/EncounterAlerts/MidnightS1/MidnightFalls.lua` |
| secure button + macrotext + 战斗外 dirty flag | 本机 `DodoGrid/Dispel.lua` |
| 受保护传播给子帧（高亮框要挂 UIParent） | 本机 `DodoGrid/Core.lua:499-501` |
| secret 三态探针 + 明文正对照 | 本机 `DodoProbe/CLAUDE.md` |
| 私有光环 / AddAuraSound | 本机 `DodoLura/CLAUDE.md` |

🔑 **这个 session 里有三次，答案就躺在本机自己的 doc 里**（DodoProbe 的实测、DodoGrid 的
protected 传播注释、DodoLura 的 PA 笔记）。**开工前先 grep 一遍 `AddOns/Dodo*/`。**

