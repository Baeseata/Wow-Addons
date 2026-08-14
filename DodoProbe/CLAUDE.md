# DodoProbe — Secret Value 探针（诊断插件，非功能插件）

**它是干嘛的**：Midnight 12.0 起暴雪上了 Secret Values，插件在战斗中读不到血量/资源/CD/光环。
**但哪些 API 具体被封、封的条件是什么，每个补丁都会变**。这个插件就是每次补丁后花 30 秒把它量出来。

**默认完全静默**，不注册任何自动打印。装着不碍事。

## 用法

```
/dp          立刻跑一次，打印一张表（脱战/战斗中都能跑）
/dp arm      武装：下次进战 3 秒后自动跑一次，跑完自动解除
```

`/dp arm` 是为了量「战斗中」那一列——手动在战斗里打字来不及。

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
第一版正则找 `SecretReturns = true` → 报「这批 API 全都零限制」，**是反的** ——
真实标注名是 `SecretWhen<条件>Restricted` 一族十几个名字。
**漏报的方向读起来正好像「没有限制」**，是个干净的错结论。
（通用版已进 canon `rules/engineering.md`。）

## 已知结论（2026-08-14 扫 12.1.0 build 69299 — **下个补丁重扫，别照抄**）

- 🟢 `C_AssistedCombat` 四个函数（`GetNextCastSpell` / `GetRotationSpells` / `IsAvailable` / `GetActionSpell`）**零限制**
- 🟢 `UnitReaction` / `UnitIsPlayer` / `UnitLevel` / `UnitExists` / `GetSpellInfo` / `IsSpellUsable`
- 🔴 血量 / 资源 / 技能 CD / 充能 / 光环 —— 战斗中全 secret
- 🔴 **12.1 新收紧**：`UnitClass` / `UnitClassBase` / `UnitGUID` 现在带 `SecretWhenUnitIdentityRestricted`；
  `UnitIsUnit` 不再是无条件布尔（要求两个 token「可比较」）—— 旧插件里照老假设写的地方要复查

## 生命周期

一次性诊断工具，**不发 CurseForge**。留着是因为每个补丁都要重量一次。
真不要了：删 `DodoProbe/` 文件夹即可，没有任何插件依赖它。
