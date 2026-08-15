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
