# DodoProbe — Secret Value 探针（诊断插件，非功能插件）

**它是干嘛的**：Midnight 12.0 起暴雪上了 Secret Values，插件在战斗中读不到血量/资源/CD/光环。
**但哪些 API 具体被封、封的条件是什么，每个补丁都会变**。这个插件就是每次补丁后花 30 秒把它量出来。

**默认完全静默**，不注册任何自动打印。装着不碍事。

## 用法

```
/dp          立刻跑一次，打印一张表（脱战/战斗中都能跑）
/dp arm      武装：进战 3 秒后跑一次，跑完自动解除
```

`/dp arm` 是为了量「战斗中」那一列——手动在战斗里打字来不及。

⚠ **表头括号里那句 `(IN COMBAT)` / `(out of combat)` 才算数,`=== COMBAT ===` 只是标签。**
v0.3.0 之前 arm 是"进战 3 秒后无条件跑",而短战斗可能在 3 秒内就结束 ⇒
**把脱战样本打上 COMBAT 表头**,读起来完全像战斗列已经拿到了。
现在到点会先查 `InCombatLockdown()`,不在战斗中就不跑、**继续保持 armed**(会提示"拉个耐揍点的")。
交叉核对用 `GetAuraDataByIndex(target,1)`:脱战 `nil` / 战斗 `ERROR` —— 它是唯一一行会随战斗翻面的探针。

屏幕上方会出现**一行文字 + 一根橙条**：那是在测「secret 能不能被塞进 FontString / StatusBar 显示出来」。
读那两个控件**看屏幕**，不要看打印出来的值（打印的是 `SetText` 有没有报错，不是渲染结果）。

## 输出怎么读

每行是 `API 名  →  真实值 / SECRET / SECRET-TABLE / nil / ERROR`。

- `SECRET` = 拿得到但碰不得（比较/运算/取长度一律 Lua error）
- `nil` = **最阴的那种**：不报错，直接不给值（`RequiresNonSecretAura` 就是这个行为）
- `ERROR` = 调用本身被拒（`FailureMode = Error` 的那些）

## 分段资源条探针（0.12.0 新增）—— **结论只能从屏幕读**

屏幕上会多出**两排各 5 小段**（在原来那个图标下面）：

- **上排（蓝）= 明文 65 对照** —— 该是「前 3 段满 / 第 4 段 1/4 / 第 5 段空」
- **下排（橙）= secret 当前资源** —— 待验的那个

**判据 = 两排形状是不是同一个套路。** 打印那两行只说明 `SetValue` 没报错；
`GetValue` 回读永远是 `SECRET`（跟主条那两行同一个道理）。

⚠ **只画下排是没有判据的** ——「全空 / 全满 / 正确」三种结果在屏幕上长得都像
「它本来就这样」。上排存在的唯一理由就是把判据变成一个能一眼读出的对比，
顺带它还验证了「我对 StatusBar 钳制行为的理解」本身对不对。

**它在验什么**：分段资源（圣能 / 连击点 / 灵魂碎片）在 secret 下有没有活路。
每段一个 StatusBar、量程各自 `[(i-1)*step, i*step]`、**五段全喂同一个值** ——
钳制和填充比例都在 C 层算，插件一次比较都不做。这是「逐颗点亮」
（暴雪 `ClassPowerBar:TurnOn/TurnOff`，需要 `i <= 当前值`）在 secret 下唯一可能的替代形状。

🔴 **真正的判据是「下排跟着资源涨落而变」** —— 跑完 `/dp` 后下排会**实时刷新 60 秒**，
打两下看它涨落。因为 `/dp` 本身只是一次快照，而**静态一帧读不出结论**：

| 静态看到 | 可能是 | 也可能是 |
|---|---|---|
| 五段全空 | 资源真的是 0（暗牧**脱战恒 0**） | 钳制没生效 |
| 五段全满 | 资源真的满了（**法力脱战恒满**） | 值低于 min 时被显示成满 |

⇒ **两个静态状态各自撞上一种失败模式的长相**，所以必须**在战斗中、资源处于中间值时看，
而且要看它动**。`/dp arm`（进战 3 秒后自动跑）就是为这个准备的。

🔑 **跟职业无关**：这一组拿疯狂（0..100 分五段）验的就是钳制机制本身，
换成圣能 / 连击点只是 step 变了。⇒ **暗牧一个号就能验完，不用切职业。**

### 调研背景（2026-08-15）：这条路没有先例

GitHub 全站搜过，**没找到任何插件在 12.x 做出战斗中可用的分段资源条**：

- **暴雪自己** `ClassPowerBar` 逐颗点亮 —— untainted 特权，插件抄不了
- **主线 oUF** `classpower.lua` **零 secret 处理**（`UnitPower(...,true) / UnitPowerDisplayMod(...)`
  那个除法在 secret 下是硬崩）；**RealUI** `ClassResource.lua` 同样零处理
- **AzeriteUI5** 是唯一一个 classpower 里带 `issecretvalue` 的，而它的「适配」是
  **读不到就 `return nil`**、功能降级
- **NorskenUI** 有专门的 `Core/Secret.lua`，模型是「战斗中冻结 / 脱战补算」—— 对资源条不适用
  （资源条恰恰就是要在战斗中看）

⚠ 措辞照实：这是「GitHub code search 上没找到」，**不是**「不存在」。
但官方 / 框架 / 成品 UI / 专门适配层四个方向都撞同一堵墙，而墙本身是结构性的：
**任何「第 i 颗该不该亮」都是对 secret 的一次比较。**

⚠ 搜的时候栽过一次:`gh search code "issecretvalue UnitPower"` **带引号是短语搜索**
（要求两词相邻）⇒ 返回 0 命中，读起来完全像「没人做过」。
**不带引号才是 AND**（25 条）。凡拿搜索结果下「没有人 X」的结论，先用一组
**已知共存**的词做负对照验口径。

## `/dp lat` —— DoT 上身到图标出现,慢在哪一段(0.13 新增)

```
/dp lat     武装(再按一次关);放「痛」/「吸血鬼之触」/「癫」任一个开始计时
            4 秒后自动打印时间轴,**并自动收起**(不留常驻监听)
```

🔴 **它不测「图标什么时候出现」——那个量测不出来。** `button:IsShown()` 是 secret,
一做布尔测试当场崩。所以它测 `UNIT_AURA` **事件**几点到,并把「事件到了」画成
**屏幕上闪一个绿块** —— 参照物必须跟图标在**同一个视野**里,否则「事件的时刻」活在聊天框、
「图标的时刻」活在眼睛里,两个世界没法比。

**判据**(绿块 vs 名条图标):同时 = 事件层没问题 · 图标晚一拍 = 卡在暴雪容器的渲染/节流 ·
**绿块本身就晚 = 慢在事件层**,插件无能为力。

**2026-08-15 实测**:施法成功 → `UNIT_AURA(target)` = **3 毫秒**。
⇒ 事件通道本身不是瓶颈。⚠ 但那一跑的采样对象不对(见下),这条**只对那次施法成立**,
真要给 DoT 定性得重跑一次确认。

### 🔴 这个探针第一版栽的两个坑(都是「量错了对象」)

1. **触发条件太宽 ⇒ 忠实地测量了另一个事件。** 原本是「arm 后第一个施法就计时」,
   结果采到了**触须猛击**(一键输出建议的那个),而**输出看起来完全正常** ——
   一整屏漂亮的时间轴,没有任何迹象说明量的不是要查的那个东西。
   🔑 **救回来的是「它打印了法术名」** ⇒ 探针必须报出**它这次测的是谁**,
   否则量错对象时你看到的是一份可信的、干净的、无关的数据。现在只认 DoT 那三个 ID。
2. **身份从事件流里"推"= 被后续事件覆盖。** `plateN` 原本记「最后一个收到 UNIT_AURA 的 nameplate」,
   而周围的怪一直在刷 ⇒ 最后留下的是隔壁那只,于是容器状态那三行查了个不相干的单位。
   ⇒ 身份要在**触发那一刻**钉死(`GetNamePlateForUnit("target").namePlateUnitToken`)。

⚠ `c:IsEventRegistered("UNIT_AURA")` 对 AuraContainer 返回 **ERROR**(调用被拒),
**不是 false** —— 读不出「注册没有」这个结论,别把它当答案。

## 🔑 别在 wiki 上查 API 到底给不给数据 —— 查 Blizzard 自己生成的契约

warcraft.wiki.gg 是二手且大量残缺（实撞：同一个问题翻 6 个页面，关键页全写「本页未包含该信息」）。

**权威源**：
```
repo    Gethe/wow-ui-source      分支 live      (commit message 就是 build 号，可核新鲜度)
路径    Interface/AddOns/Blizzard_APIDocumentationGenerated/*.lua        (624 个文件)
```

关键文件：
| 文件 | 内容 |
|---|---|
| `SecretPredicatesDocumentation.lua` | **所有 secret 条件的定义**（`SecretWhenInCombat` / `SecretWhenCooldownsRestricted` / …），带原文说明 |
| `SecretAspectConstantsDocumentation.lua` | secret 能被塞进哪些视觉通道 |
| `UnitDocumentation.lua` / `SpellDocumentation.lua` / `UnitAuraDocumentation.lua` | 逐个 API 的限制标注 |
| `AssistedCombatDocumentation.lua` | `C_AssistedCombat` 全名单 |

扫法（拉下来 grep 就行）：
```bash
curl -s "https://api.github.com/repos/Gethe/wow-ui-source/git/trees/live?recursive=1"   # 找路径
curl -s https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua
```
标注长这样，直接在函数条目上：
```lua
{ Name = "UnitPower", Type = "Function", SecretWhenUnitPowerRestricted = true, ... }
```

🔴 **批量扫之前，先 dump 一条你已经知道答案的条目验口径。**
标注**一共三族,扫漏任何一族都会报出「这批 API 零限制」这个干净的错结论**:

| 族 | 长相 | 含义 |
|---|---|---|
| 无条件 | `SecretReturns = true` | 返回值恒 secret。**`UnitHealth` 用的就是这个** |
| 条件式 | `SecretWhen<条件>Restricted = true` | 满足条件才 secret(十几个名字,定义见 SecretPredicates) |
| 前置条件 | `Requires<X>` | 不给 secret、直接**拒绝**;`FailureMode` = `ReturnNothing`(静默 nil)/ `ReturnWithError` / `Error` |

⚠ 另有 `SecretArguments = "AllowedWhenTainted" / "AllowedWhenUntainted"` —— 那是说它**接受 secret 当入参**,
**不是**说它返回 secret。光 UnitDocumentation 里就出现 205 次,当成限制扫会把几乎所有 API 误判成被封。

> **校准记录(2026-08-14 第二轮)**:本节原文写的是「`SecretReturns = true` 是反的,真实标注名是
> `SecretWhen*` 一族」—— **那句本身是错的**。负对照(`grep -A6 '"UnitHealth"' UnitDocumentation.lua`)
> 当场推翻:`SecretReturns` 是真标注,而且正挂在最要紧的那个 API 上。照原句扫会整族漏掉无条件那类。
> ⇒ 印证了本节自己那条心法:**口径没验过的扫描结果不许写进结论** —— 包括这条心法上一版的结论。
> (通用版已进 canon `rules/engineering.md`。)

## 已知结论（2026-08-14 扫 12.1.0 build 69299 — **下个补丁重扫，别照抄**）

> ⚠ **2026-08-15 又跑了一轮，下面若干条被推翻或补充了** —— 例如「战斗中 per-spell `Aura=Never`
> 也失效」是**错的**（实测 `BySpellID 1/12`，命中的正是那个 `Never` 的；死的是枚举不是定点查）；
> `SetMinMaxValues` 吃 secret 已证；`GetSpellCooldown` 的字段确认是 secret。
> **完整且会继续更新的一份在 canon `rules/wow-addons.md`**，本节是当时那一次的快照。

> **活体实测已跑**(暗牧,受限地图,脱战 + 战斗中各一次)。下面 🟢/🔴 是**实跑结果**,不是只读契约。

**🟢 出招通道整条明文,战斗中不降级** —— 这是本次最重要的结论:

| 探针 | 脱战 | 战斗中 |
|---|---|---|
| `GetNextCastSpell()` / `(true)` | `1227280` | `1227280` |
| `→ GetSpellName(next)` | 触须猛击 | 触须猛击 |
| `→ GetSpellTexture(next)` | `7439212` | `7439212` |
| `IsAvailable()` | true,reason 空 | 同左 |
| `#GetRotationSpells()` + 名字 | 12,可遍历 | 同左 |
| 自己施法的 spellID | `589` | `589` |

⇒ **`GetNextCastSpell` → `GetSpellName` / `GetSpellTexture` 可以直接当插件引擎**,全程不碰 secret。

🔑 **`GetActionSpell()` ≠ `GetNextCastSpell()`**(实测 `1229376` vs `1227280`,别混用)。
查暴雪自己的 `Blizzard_ActionBar/Mainline/AssistedCombatManager.lua`:
`GetActionSpell` = "一键输出"**那个宏按钮自己**的 ID,`SPELLS_CHANGED` 时取一次的固定值;
`GetNextCastSpell(checkForVisibleButton)` 才是建议,暴雪在 `OnUpdate` 里轮询、变了才刷高亮,
频率走 cvar `assistedCombatIconUpdateRate`(**默认 0 = 每帧**)⇒ 调用开销可忽略。
暴雪传 `checkForVisibleButton = true`(只建议动作条上可见的);实测两者返回相同。

**🔴 死掉的(脱战就死,不用等战斗)**:

- `UnitHealth` —— `SecretReturns = true` **无条件**,脱战也 SECRET
- `UnitPower` —— 谓词原文是「除非该能量类型被显式标为永不 secret,否则一律 secret」,**跟战斗无关**;
  而 `UnitPowerMax` 给真值(100)。⇒ 「读当前资源排优先级」这条路 12.1 焊死,`DodoUnholy` 那套只能换引擎
- 光环:`GetPlayerAuraBySpellID` → nil;`GetAuraDataByIndex(target,1)` **脱战 nil / 战斗 ERROR**
  (`RequiresUnitAuraAccess` 的 FailureMode = `Error`)。🎁 **这一行是现成的负对照** ——
  它是脱战与战斗**唯一**行为不同的探针,拿它判「这份样本是不是真战斗中跑的」比看表头可靠

**⚠ 存疑,别当能用**:`C_Spell.GetSpellCooldown` **战斗中仍返回 `table(open)`**,与契约标注
`SecretWhenCooldownsRestricted` 不符。但 `table(open)` 只证明**表本身**不是 secret table,
**字段完全可能是 secret** —— 探针没往里读。要用它得先加一条「取 `.startTime` 出来 tag 一下」的探针。
- 🔴 **12.1 新收紧**：`UnitClass` / `UnitClassBase` / `UnitGUID` 现在带 `SecretWhenUnitIdentityRestricted`；
  `UnitIsUnit` 不再是无条件布尔（要求两个 token「可比较」）—— 旧插件里照老假设写的地方要复查

## 生命周期

一次性诊断工具，**不发 CurseForge**。留着是因为每个补丁都要重量一次。
真不要了：删 `DodoProbe/` 文件夹即可，没有任何插件依赖它。
