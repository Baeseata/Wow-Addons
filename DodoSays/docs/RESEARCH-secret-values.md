# 调研：boss 施法在 12.1 能不能读

> 2026-08-15 · OMEN · 权威源 = 暴雪自己生成的契约（`Gethe/wow-ui-source` @ `live`），**不查 wiki**。
> 口径已验：先 dump 已知答案的 `UnitClass` → 确认是 `SecretWhenUnitIdentityRestricted`，与 canon 记录一致。

## 结论一句话

**事件收得到，内容读不到 —— 而对本插件够用。**

## 1. 函数：`UnitCastingInfo` / `UnitChannelInfo`

两者都带 `SecretWhenUnitSpellCastRestricted = true`。该谓词原文（`SecretPredicatesDocumentation.lua`）：

> *"Guarded APIs and events produce secret values if the unit being queried for cast information is **not the player or their pet**. Individual spells may be flagged as never or always secret, **which takes priority**."*

🔴 **跟在不在地下堡无关** —— boss 永远不是 player/pet ⇒ 恒 secret。同族里这是最严的一档：

| 谓词 | 何时 secret |
|---|---|
| `SecretOnRestrictedMaps` | 只在副本/团本地图 |
| `SecretWhenInCombat` | 只在战斗中 |
| `SecretWhenUnitComparisonRestricted` | 只在 addon-restricted 地图，且看 unit token 组合 |
| **`SecretWhenUnitSpellCastRestricted`** | **只要查的不是自己/宠物** |

**返回值里哪些永远明文**（`NeverSecret = true`）：

| 函数 | NeverSecret 字段 | 受限字段（= 想要的那些） |
|---|---|---|
| `UnitCastingInfo` | `isTradeskill` `castBarID` `delayTimeMs` | `name` `displayName` `textureID` `startTimeMs` `endTimeMs` `castID` `notInterruptible` `castingSpellID` |
| `UnitChannelInfo` | `isTradeskill` `isEmpowered` `numEmpowerStages` `castBarID` | `name` `displayName` `textureID` `startTimeMs` `endTimeMs` `notInterruptible` `spellID` |

⇒ 想算「布道还剩几秒」= **不行**（时间戳 secret，不能比较/运算）。
⇒ 但按 canon 总钥匙，**secret 可以直接喂控件**：`StatusBar:SetMinMaxValues(startMS, endMS)` + `SetValue(...)` 能画出一根读条给人看。**最坏情况的降级路线就是这个。**

## 2. 事件：能触发，payload 部分 secret

`UNIT_SPELLCAST_CHANNEL_START` / `_UPDATE` / `_STOP` / `UNIT_SPELLCAST_START` 全部：

```
SecretWhenUnitSpellCastRestricted = true
SynchronousEvent = true
Payload: unitTarget, castGUID, spellID, castBarID(NeverSecret)
```

🔑 **关键区分（canon 三族分类）**：`SecretWhen*` 是「**返回 secret 值**」，只有 `Requires*` 才是「前置拒绝」。
⇒ **事件照常触发。「这一刻发生了一次引导/施法」本身就是明文信息。** 这就是本插件的地基。

⚠ 契约留的口子：**个别法术可被标 never-secret，优先级高于上述规则。** 契约给不了答案 → 见 `PROBE-CHECKLIST.md` 第 3/4 条。

## 3. SnakeSays 的 secret 处理范式（照抄，别自己重推）

源码 `github.com/lgkern/SnakeSays` → `Detector.lua`。它自己的注释就是最好的说明：

> *"A secret value is **not detectable by `type`**: it reports as the number or string it is standing in for and **only goes off when you use it**."*

```lua
-- 运行时判定（包 pcall 防某些 build 没这函数）
local function isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, v)
    return ok and secret == true
end

-- 三态返回：true / false / nil(不可知)。nil 跟 false 是两个不同的答案,这就是它存在的全部理由
local function equals(a, b)
    if isSecret(a) or isSecret(b) then return nil end
    local ok, same = pcall(function() return a == b end)
    if not ok then return nil end
    return same
end
```

**三条会咬人的纪律，每条都对应它源码里一句注释：**

1. 🔴 **`tostring()` 本身就是一次「使用」，secret 会抛** — *"Never tostring()s anything unproven: that is itself a use."* ⇒ **写调试日志是最容易炸的地方**，得有个 `describe()` 包一层。
2. 🔴 **先查 unit、再碰 spellID，顺序是故意的** — *"touching one is what threw; there is no reason to touch it for a cast that is not our boss', which in an instance is nearly all of them."*
3. 🔴 **一次抛错会静默吃掉整个功能** — *"an error thrown there escapes into a UNIT_AURA handler and takes the whole feature down without a word. So every field is proved usable before it is used."*
   （同族 canon 教训：`catch + log.Debug` = 定时炸弹。）

**它的 `identifyEcho` 是三层降级** —— 作者留三条路本身就说明他也不确定实战读不读得到：
1. `equals(spellID, ECHO_SPELL)` — spellID 明文就直接比
2. 读 `UnitCastingInfo` 的**名字**，规范化后比（去大小写/空格/标点 —— `Ula'tek` 的撇号有直/弯两种写法）
3. 都不行 → 靠时序围栏推断（「必须已有 round 在进行中」）

它硬编码的常量（**未经我方实测,当断言核**）：

```lua
SERMON_SPELLS = { [1288103] = true, [1306239] = true }   -- 两个,大概率 ? / ?? 各一
ECHO_SPELL    = 1288125
```
