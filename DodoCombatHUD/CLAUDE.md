# DodoCombatHUD — 自绘战斗监控 HUD(暗牧优先)

**它是干嘛的**:把「打极限单体时眼睛要盯的东西」摆到视线中心一叠。
从上到下 **目标 DoT 图标 / 目标血量 / 疯狂 / 施法引导** —— 三根条同宽同锚点,
DoT 那排图标锚在血条左上角,全部一起拖、一起显隐。

**它不是出招提示。** 产品定位是**监控面板** —— Jerry 原话:「只要监控到位且方便,
我可以自己不需要技能提示也能打出来极限 dps」。同族的 `DodoNext`(读暴雪出招建议)
正是因为目标是这个才被废弃删掉的,别再造一遍。

`/dch` 看全部命令。当前版本以 `DodoCombatHUD.toc` 的 `## Version` 为准。

---

## 🔴 铁律:Secret Values(12.x)

`UnitPower` / `UnitHealth` **恒 secret**。本插件永远不许对那些值做
**读 / 比较 / 格式化 / tostring / 算术** —— 任何一样都是硬 Lua error。

它们只走两条路,都是实测过吃 secret 的控件 setter:

```
StatusBar:SetValue / SetMinMaxValues      (AllowedWhenTainted)
FontString:SetText                        (AllowedWhenTainted,实测真渲染出数字)
```

⇒ **条的长度自己就是百分比,本插件没有任何一处在算百分比。**
阈值一律是**静态刻度**(纯明文几何),玩家用眼睛比。

**唯一允许拿 secret 做判断的形状** = `PlainNumber(v)`:先问 `issecretvalue`,
是 secret 就当「没有明文」。**绝不写 `v > 0`。**

⛔ **「按值自动变色」做不成。** 那需要一个 secret 布尔,而 secret 数值 → 布尔
那一步是比较运算。实测坐实:`Curve:Evaluate(secret)` = ERROR,而同一条 curve
喂明文 50 = ok(**带负对照,不是猜的**)。

---

## 三根条的数据来源各不相同 —— 这是本插件最要紧的一件事

| 条 | 数据 | 能力 |
|---|---|---|
| 疯狂 | `UnitPower` secret / `UnitPowerMax` **明文 100** | 能画不能算 |
| 目标血量 | `UnitHealth` secret / `UnitHealthMax` **也是 secret(已验)** | 能画不能算 |
| 施法引导 | 自己的施法信息 **全明文** | **能读能算** ← 唯一 |

**施法条是唯一能做真逻辑的一根**(跳数刻度就建在这上面)。谓词按**单位**判:
「被查的不是玩家本人或其宠物」才 secret ⇒ 查 `"player"` 不满足条件。

✅ **那个缺口 2026-08-15 补上了**(选中目标 + 战斗中跑一次 `/dp`):
`UnitHealthMax(target)` = **SECRET**、`SetMinMaxValues(0, secret)` = **set-ok**、
回读 `GetMinMaxValues()` = **SECRET**(不是 0)⇒ 它**真收下了**那个值,
血条从「能用但没证明」变成「证明了」。补验只花了一次带目标的 `/dp`。

---

## 每根条一个独立的错误闸

`Feed()` 里的 `dead` 标记是**逐条**的,不是全局的。血条走的那条路没验过,
它挂了不许把已经好用的疯狂条一起停掉。报错**只报一次** ——
挂在 OnUpdate 上的报错会每帧刷屏,把真正有用的信息冲掉。

## 刷新走 OnUpdate 不走事件

事件驱动要赌「`UNIT_POWER_FREQUENT` 在值 secret 时照样开火」,而那个赌注验不了。
OnUpdate 无脑但**结构上不可能漏刷** —— 一个测不了的机制不如一个无聊但一定对的。

---

## 引导跳数:没有 API,只能人肉定一个数

🔴 **全量 grep 过整份 `UnitDocumentation`:`numTicks` / `tickPeriod` 这类字段一个都没有。**
`UnitChannelInfo` 只多给 `isEmpowered` / `numEmpowerStages` —— 那是**充能法术**专用,
暴雪自己的施法条里 `AddStages()` 就卡在 `isEmpowered` 上。
⇒ **暴雪自己的施法条根本不给普通引导画跳,这块「搬它别重造它」不成立。**

**Quartz(最主流那个)也是硬编码**,`modules/Player.lua`:

```lua
channelingTicks[GetSpellName(47540)] = IsPlayerSpell(193134) and 4 or 3   -- 苦修
bar.channelingTickTime = bar.channelingDuration / bar.channelingTicks     -- 就是等分
```

而且**正式服它只覆盖 4 个法术(苦修 / 奥术飞弹 / 唤醒 / 裂解),没有精神鞭笞**
⇒ 连「抄一张现成的表」都没得抄。

**本插件的做法**:`/dch chan <n>` 现场校准,按 spellID 存 SavedVariables。
`DEFAULTS.chanTicks` 里烤了一个量出来的默认值,**SavedVariables 优先**
(`CopyDefaults` 只填空不覆盖)⇒ 随时能覆盖。
⚠ 天赋改了跳数 / 暴雪重做了法术时,烤死的默认值**不会报错、只会静静画错**。

**没校准过的法术不画刻度**,不拿「1 秒一跳」这种猜测顶上 ——
**画错的刻度比不画更坏**:它教你一个错的节奏,而且看起来完全像个正经功能。

---

## 目标 DoT 那一排:数据我们一个字都读不到,画的人是暴雪

自己读目标光环是死路(战斗中三种读法全 `ERROR` = **没值**,不是 secret ⇒ 画都没得画)。
走的是暴雪的 `CustomAuraContainerTemplate`:我们只递筛选条件,它去取数据、画图标和倒计时。
**机制、四个坑、`includeSpellIDs` 的准入规则全在 canon `rules/wow-addons.md`,别在这儿抄第二份。**

本插件自己的三个决策:

- **一格一个独立容器**,各自锚死在固定 x 偏移。不是「一个容器三个 group」——
  flow layout 会跳过空组 ⇒ 掉一个 DoT 后面的全部左移。**监控面板要的就是「该在的不在」
  一眼看出来**,位置每次都一样比省两个框体重要。
- **spellID 烤在 `DEFAULTS.dots` 里,但配了 `/dch dot` 当纠正入口。** 天赋 / 改版让某个 ID 失效时
  **不报错、只是那一格永远空着** —— 跟「这功能没做好」分不出来。`/dch dot` 无参列出每格的
  ID 和法术名,那是唯一能发现这件事的地方。⚠ 它跟 `chanTicks`、两个 ticks 一样是**变长数组**,
  PLAYER_LOGIN 里单独拎出来不参与 `CopyDefaults`,否则你删掉一格下次登录会被补回来。
- **`maxFrameCount` 用 6 不用 1。** 语义上每格最多也只有 1 个,但 6 是探针里实测跑通过的值,
  1 没试过,而 DodoNameplate 那边 0 又是另一个意思 —— 三个候选三种语义,这种地方别赌。

`/dch blizzcast` 藏暴雪自己那根施法条(官方开关 + 单向守护,理由见 canon)。

## 🔴 三个真栽过的坑

**1. `UnitChannelInfo` 和 `UnitCastingInfo` 的返回顺序从第 7 位起就分叉**
(引导是 `notInterruptible`,施法是 `castID`),`spellID` 一个在第 8 位一个在第 9 位。
抄错了**条照画、只是画的是别的东西,而且不报错**。
⇒ 顺序取自暴雪自己的 `Blizzard_UIPanels_Game/Shared/CastingBarFrame.lua`,别凭印象。

**2. `modRate` 不是急速,`GetTotalDuration(BaseTime)` 里照样含急速。**
`UnitChannelDuration` 确实能用(契约这次是对的),但实测 `BaseTime` 读数 **== `RealTime`**、
`modRate` 恒 `1.000`。曾据此写过一个「基础时长 ÷ 基础跳间隔」的自动推导 ——
**那会在急速变化时悄悄给出错误跳数**(按 3.82s 校 3 跳,到 3.0s 会算成 2 跳),已整段删除。
⇒ 跳数只有「你校准的那个整数」一条路。**没做成"永不开火的分支"。**

**3. 引导一结束就清 `castCur` ⇒ `/dch chan` 永远用不了。**
它是给「刚才那个引导」定跳数的,而人手打字必然发生在引导**结束之后**。
更坑的是提示语还写着「刚才那个」——**提示语和行为对不上**。⇒ 不清,留作「最后见过的引导」。

---

## 已知缺口(现在不做,判据留着)

- **引导被 pushback 缩短时刻度会错**:我们是把 N 根线重新均分到新时长上,
  而 Quartz 是保持跳间隔往后补跳。Gnosis 专门宣传它支持 pushback 刻度,说明这在实践中是真事。
  12.x 还有没有玩家引导 pushback **没验**,做了也验不了。
  **判据:哪天挨打时发现刻度跟节奏对不上,就是这条。**
- **斩杀线只有线、不会报警**:要让它真的闪,取决于 `C_Spell.IsSpellUsable(暗言术:灭)`
  会不会随目标血量翻面(它是**明文**布尔,已实测)。
  **验法:对满血目标和残血目标各跑一次 `/dp`,比 `U=` 那一列。**

## 相关

- `DodoProbe/` —— secret value 探针,`/dp`。上面每一条「实测」都出自它,补丁后重量一次。
- 技术地图(Secret Values 全景 / 显示通道白名单)住 canon `~/.claude/canon/rules/wow-addons.md`,
  别在这里复制一份。
