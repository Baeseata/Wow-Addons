# DodoGuanzhu · GOTCHAS

> 全部条目来自 **2026-08-18 真机实测**(WoW **12.1.0 build 120100**,美服 Illidan,中文客户端),
> 探针 = `DodoProbe` 的 `/dp macro` 子命令,三跑一致。
> ⚠ 「暴雪哪天改了」的判据:重跑 `/dp macro`,跟本文的基准值对不上就是改了。

---

## ⚠ 1. 未验证假设:队友名字能不能解析成 unit —— **整个方案的单点风险**

**现状**:宏里写 `[@张三,help,nodead]`,要求 `张三` 能被解析成一个 unit token 才判得了 `help`/`nodead`。

**已实测**:🔴 **主城陌生人不行** —— `[@Cosini,exists]` 和 `[@Cosini,help]` **都判假**,
而 `UnitName(target)` 同时是明文 `Cosini`(名字读得到,但解析不成 unit)。
⚠ 有意思的是 `[@Cosini]` **裸的会成立** ⇒ 名字被**原样当 target 传给 `CastSpellByName`**,
由 C 层去解析;而条件判断走的是另一条路,那条路要 unit token。

**没测到**:**队友**行不行(测的时候玩家单人,组不上队)。**当前代码假设它行。**

🔴 **⚠ 两边不一致,以本条为准**(2026-08-22 审计发现):canon `rules/wow-addons.md` 把这件事
写成了**既成事实** ——「`@名字` **只在队伍/团队内**解析得成 unit」。那句话的前半(陌生人不行)
是实测的,**后半(队友行)是从前半推出来的,没有任何正面证据**。
而 canon 每个 session **eager 加载**、本文件只有进这个目录才读 ⇒ 下一个 session 会先看到
那句斩钉截铁的结论,据此把 PENDING-WORK 里那条阻塞划掉。**别划。**
判据用 canon 自己那条:**负对照要能在真/假两种情况下给出不同答案** —— 而「陌生人判假」
在「队友能解析」和「队友也不能解析」两个世界里**都成立**,所以它证不了后半句。
(canon 在**另一个 repo**(`claude-canon`),不归本 repo 改;要修那句得单独提给 Jerry。)

**怎么证伪**(10 秒):组个队 → 选中队友 → `/dp macro` → 看 `[@目标名字,exists]`。
- 成立 ⇒ 假设成立,什么都不用改
- 判假 ⇒ **`@名字` 整条路线作废**,得改用 `raid1..40` / `party1..4` 这类 token

**证伪之后改哪里**:🔑 **只改 `ns.Macro.TokenFor(name)` 一个函数**(Macro.lua)。
它是这个假设的**唯一隔离点**,别把假设散到别处。改成"运行时把名字解析成当前 token"之后,
还要加一条 `GROUP_ROSTER_UPDATE` → 战斗外重写宏(因为 token 会随团队重组换人)。

☐ **no-guard**,理由:这个假设只能在**真实组队环境**里证伪,build 期和单人环境都验不了。
代替方案 = `TokenFor` 上方的注释 + 本条 + 面板上"不在你队伍里"的灰标。

---

## 🔴 2. 宏条件里**没有**射程判断 —— 而且它长得像有

**别信 `[@player,inrange]` 会成立这件事。** 完整推理链(三条证据缺一不可):

| 探针 | 结果 |
|---|---|
| `[@player,inrange]` | 成立 |
| `[@player,zzzgarbage]`(纯垃圾条件) | **成立** ⇒ 未识别的条件被**直接忽略** |
| `[@player,noinrange]` | 判假 |
| `[@player,nozzzgarbage]` | **判假** ⇒ `no`+未知 走另一条路,一律判假 |
| `[@target,inrange]` 走近走远各一跑 | **两跑都成立、纹丝不动**,而同屏的 `C_Spell.IsSpellInRange` 从 `false` 翻到 `true` |

⇒ `inrange` 就是个被忽略的未知条件。**宏里写它没有任何作用**(既不会报错,也不会生效 ——
最坏的那种,看着像在工作)。

⚠ **这条踩过一次坑**:只看前三行会得出"`inrange` 是真条件"的**干净的错结论**
(因为真条件确实会让 `noinrange` 判假)。第 4 行才是拆掉它的那条,第 5 行是独立的第二类证据。

☐ **no-guard**,理由:宏条件解析在 C 层,build 期够不着。代替 = `Macro.BuildBody` 里明令不写 inrange。

---

## ✅ 3. 但 `C_Spell.IsSpellInRange` 是明文 —— 射程硬伤的实际解法

- 🔴 `UnitInRange(unit)` 契约标 `SecretReturns = true` = **无条件 secret**,永远读不到。
- ✅ `C_Spell.IsSpellInRange(10060, unit)` **明文**,实测远 `false` / 近 `true`,跟着距离实时变。
- ❌ 旧全局 `IsSpellInRange(name, unit)` **已移除**,调用报 ERROR。只用 `C_Spell.` 那个。

⇒ 插件读得到射程,但**战斗中改不了宏**。所以射程只用于 **UI 提示**(`Preview.lua`):
把"按下去才知道空了"变成"按之前就看得见"。

🔴 **绝不能让 Preview 自作主张跳过超距离的人** —— 宏判不了射程,预览跳过了就跟宏说两件事,
而宏才是真正执行的那个。主判断照宏的逻辑算,射程**只作附注**。
(canon:同一不变式两份手写实现 = 静默分歧发生器。)

---

## 4. 宏正文按**码位**截断,不是字节

实测:写入 300 个汉字(900 字节 / 300 码位)→ 回读 **768 字节 / 256 码位**。768÷256=3 正好是汉字宽度。

- API 层上限 **256 码位**;UI 输入框 `MacroFrameText` 是 `letters="255"` ⇒ **代码里按 255 保守算**。
- ⇒ **中文名不吃亏**,一个汉字算 1。5 个人的名单大约 160~200 码位,很宽松。
- 🔴 超长会**静默截断**,产出一个"能用但少几个人"的宏,**零报错** ⇒ `Options` 必须有实时长度计
  且超长时**拒绝写入**,不能靠玩家自己数。
- ⚠ 自己数码位,别依赖 `strlenutf8`(不保证在):字节 `< 0x80` 或 `>= 0xC0` 才算一个码位。

☑ **guard**:`Macro.Length()` 有单元可测性(纯函数);已在 `DodoProbe` 里钉了基准值做回归对照。

---

## 5. 宏名上限**不是** 16 字符

实测 `"DP"+10 个汉字`(12 码位 / **32 字节**)`EditMacro` 改名后**完整保留、没截断**。

⚠ `DodoSays/Macros.lua` 的注释写着 *"The client's limit is 16 characters"* 并以此为由
"所以不用测量长度" —— **那个理由是错的**(它自己的宏名最长 13,所以实际无害)。
别照那句话推理中文宏名。真实上限**未测到**(12 码位没撞到墙)。

---

## 6. 宏 API 的三个坑

1. 🔴 **战斗中客户端直接 block** `CreateMacro` / `EditMacro` / `DeleteMacro`
   ⇒ 一切写宏前必须 `InCombatLockdown()` 检查,战斗中置 dirty、`PLAYER_REGEN_ENABLED` 补做。
2. ⚠ **`GetMacroBody` 可能不存在** —— 暴雪自己的 `Blizzard_MacroUI.lua` 全程用
   `GetMacroInfo(idx)` 的**第 3 个返回值**,而 `GetMacroBody` 在 12.1 源码里一次都没出现。
   裸调它是 nil 就当场崩。
3. 🔴 **`EditMacro` 撞名会重写玩家自己的宏** ⇒ 宏名必须带独一无二前缀(`Dodo ` + 方案名)。

附:这些全是**老式全局 API**,不在 `C_Macro` 里(`C_Macro` 只有 `GetMacroName` /
`GetSelectedMacroIcon` / `RunMacroText` / `SetMacroExecuteLineCallback` 四个)。
`MAX_ACCOUNT_MACROS` = 120,`MAX_CHARACTER_MACROS` = 30。

---

## 7. `PLAYER_TARGET_CHANGED` 在"点的人已经是当前目标"时**不触发**

录名单靠这个事件(玩家点团队框架/3D世界/名条,共同点都是"选中")。
但重复点同一个人、或打开面板前就已经选中了他 ⇒ **事件不开火,名字进不去**。

⇒ **必须**另有一条"把当前目标加进来"的显式入口。不做的话症状是
「我点了他怎么没反应」,而且完全无从查起。

☐ **no-guard**:事件行为验不了,靠 `Capture.lua` 的注释 + 面板上那个按钮。

---

## 8. 这些 Unit API 是明文,随便读

`UnitIsPlayer` · `UnitCanAssist` · `UnitIsDeadOrGhost` · `UnitIsConnected` · `UnitName` ·
`UnitExists` · `select(2, UnitClass(u))`(返回 `"PRIEST"` 这种,可上职业色)。

⚠ 但 `UnitClass` 的**第 1 个**返回值(本地化职业名)标了字段级 `ConditionalSecret = true`,
**第 2、3 个无标注** ⇒ 上色一律用第 2 个(`classFilename`),别用第 1 个。

⚠ **名字仍可能是 secret**(非玩家控制且不在队伍/团队时)⇒ 拼接前先 `issecretvalue` 检查。
对 secret 做 `tostring`/拼接会**当场崩**。

---

## 9. 天赋前提:Twins of the Sun Priestess

玩家点了这个天赋(spell 336897):**给友方施放 PI 时自己也获得完整效果和持续时间**。

⇒ **给出去永远严格优于给自己** ⇒ `[@player]` 是**止损**不是备选,名单该尽量填满,
排序时"给一个次优的人"也远好过落到自己。

⚠ 这是**玩家的天赋选择**,不是游戏常量。他改天赋的话 `selfLast` 的默认值和
排序建议都要重新想。
