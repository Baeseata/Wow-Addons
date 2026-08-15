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

## 多职业资源条(0.9.0)—— 分两层,两层的**规矩完全相反**

> 🔴 分层依据是 `C_Secrets.GetPowerTypeSecrecy` 实测(canon `rules/wow-addons.md` 有全表),
> **不是**从 `UnitPower` 的契约标注推的 —— 那么推过一次,方向是错的,白烧一轮调研。

| 层 | 是什么 | secrecy | 规矩 |
|---|---|---|---|
| **主资源** | `UnitPowerType` 给的那个(法力/怒气/能量/疯狂…) | `Ctx` | **一个数都别读**,喂进 StatusBar 让它自己画 |
| **次要资源** | 离散那批(圣能/连击点/碎片/真气/符文/奥术充能/精华) | `Never` | **明文,随便读随便算** |

- **主资源不再写死**:`UnitPowerType("player")` 零 secret 标注,换专精 / 德鲁伊变形自动跟上
  (`UNIT_DISPLAYPOWER` → `RefreshResources()` + `ApplyLayout()` + `RefreshAvailability()`,
  **三个都要调** —— 只刷显隐的话「变了形还是上一形态的颜色和格数」)。
- **次要资源靠探测,不查专精 ID 表**:`UnitPowerMax` 对「该单位没有的资源」返明文 0。
  ⚠ 但 `AlternateQuest` / `AlternateEncounter` 的 max **也是 100 且几乎总在**(暗牧身上就有),
  必须显式排除(`ns.EXCLUDE`);另配一道 `max <= 12` 防守 —— 万一哪个「离散」资源 max 是 100,
  画 100 格等于毁掉这根条,而那读起来像布局算错了。
- 🔴 **颜色不能靠 `UnitPowerType`** —— 它那三个 rgb **实测是 nil**(不是 secret,是没值)。
  走 `ns.ColorFor`:玩家覆盖 > 我们自己调的表 > 官方 `PowerBarColor` > 灰。
  **故意不默认用官方色**:那是给暴雪带厚边框的框体调的,搬到裸条上会糊
  (疯狂条就是这么退回素图 + 自选亮紫的)。

### 为什么单独开一个 `Resource.lua`

它**一个框体都不建、一点状态都不存** ⇒ 算法那一半能被离线测试够得着
(`tools/test_resource.lua` 43 项 + `tools/test_migrate.lua` 16 项,`lua tools/xxx.lua` 直接跑)。
这是本插件第一次有可自动跑的验证手段,**别把逻辑挪回主文件**。
三个 A/B 都精确变红过:拆掉上限钳制 / 忘记减段间缝 / 把平手 tiebreak 反过来。

⚠ **平手 tiebreak 那条测试是换过一次量的**:第一版三个符文 `duration` 全一样 ⇒ 平手时 `frac`
也一样 ⇒ 顺序怎么变 fills 都相同,**那个量对乱序完全免疫**(A/B 实测:拆掉 tiebreak 照样全绿)。
改成「remaining 相同但 frac 不同」才测得出来。

### 🔴 0.9.0 首次真机就崩:`local segHost` 声明写晚了 = 赋成了全局

`local segHost` 原本写在 `LayoutSegs` 那节(文件中部),而 `BuildHUD` 在它**上面**
⇒ BuildHUD 里那句 `segHost = CreateFrame(...)` **赋的是全局变量**,
而 `ApplyLayout` 读的 local upvalue 恒为 nil ⇒ 登录即
`attempt to index upvalue 'segHost' (a nil value)`(骑士,0.9.0)。

**为什么当时所有检查都放过它**:
- `luac -p` —— **写全局是合法 Lua**,语法层面挑不出任何毛病
- `tools/test_resource.lua` —— 只覆盖 `Resource.lua` 的纯函数,**够不着框体装配**

两套检查各自完备,坏的是**接缝**(canon guard 家族 (i))。
⇒ 补了 `tools/test_scope.lua`:断言模块级 local 的声明行 < 第一次被函数体赋值的行。
A/B 验过 —— 把声明挪回原位,精确报 `第 413 行赋值,但 local 到第 488 行才声明`。
🔑 **以后新增任何模块级状态变量,都要加进那份 `NAMES` 清单**,否则它守不到。

⚠ DodoInspect 栽过同一条(`local Refresh` 前向声明被删 ⇒ 静默建全局,点一下上移箭头才炸),
那边的守法是「断言插件不产生全局」。**同族第三次了 —— 这个坑在 Lua 里是结构性的。**

### 毁灭术的「半颗豆」不需要特殊代码

`UnitPower(unit, SoulShards, true)` 给 0..50、`UnitPowerDisplayMod(SoulShards)` 给 **10**
(明文,而且**不吃 unit** —— 在暗牧身上就问得出来)⇒ `ns.ExactValue` 一除得到 3.5,
`ns.SegmentFill(3.5, i)` 就把「前 3 格满、第 4 格半、第 5 格空」算出来了。
其余离散资源 mod = 1,**走同一条代码路径**。
🔑 反过来说:暴雪自己那套 `ClassPowerBar:TurnOn/TurnOff` 是布尔的,**结构上表达不了半颗**。

### 符文:每格独立冷却,`GetRuneCooldown` **完全明文**

⚠ **别从「CD 都是 secret」推到这里** —— 那说的是法术冷却和 `Cooldown:SetCooldown`,
跟 `GetRuneCooldown` 是三个互不相干的机制(这个错本仓犯过)。
`ns.RuneFills`:就绪的排前面填满,冷却中的按**剩余时间**升序、按进度部分填充
⇒ 屏幕上永远「谁先好谁在前」。**平手必须按槽位稳定排**,否则一排格子每帧抖,
而那看起来像渲染 bug 不像排序问题。形状对照 `VinkyDev/VFlow` 的 `BuildRuneSegmentState`。

### 布局锚链是**活的**

从上到下:DoT / 血条 / 主资源 / **次要资源** / 施法条。次要资源那根插在中间 ⇒
它显示时施法条挂它下面,不显示时施法条直接挂 `root`。少这一步的症状是
「关掉它以后中间空一条」或者「两根条叠在一起」。

### 迁移:`powerColor` → `powerColors.Insanity`

老键是**全局一个色**(那时只有暗牧疯狂)。**丢了他手调的紫就没了;留着当全局色则换骑士
法力条也是紫的 —— 两头都错** ⇒ 搬进按资源分的那张表。跟 dot 那次一样,
判据用「老键还在不在」(自证 + 幂等,不另记标记),而且**必须跑在 `CopyDefaults` 之前**。

### ⚠ 真机第一次跑要确认的

- `/dch res` 先看探测对不对(**换职业第一件事**)。没有它的话「次要资源条没出现」跟
  「这专精本来就没有」分不出来。
- **骑士**:主资源该是法力(蓝)、次要该是圣能 5 格。
- **毁灭术**:碎片该显示成「三颗半」——**那半颗的进度画得出来**才算对。
- **DK**(如果要验):符文 6 格,冷却中的按谁先好排在前面。
- 关掉次要资源条,施法条该**贴上来**(不是留一条空隙)。
- 德鲁伊变形(如果有号):形态一换,颜色和格数该当场跟着变。

## ESC 选项面板(`Options.lua`)

ESC → 选项 → 插件 → DodoCombatHUD,两层:**主页 = 「要显示什么」· UI 子页 = 「显示成多大」**。
子页用 `Settings.RegisterVerticalLayoutSubcategory(parent, name)`(**返回 `(category, layout)`
两个值** —— 小节标题要挂子页那个 layout,挂错会把标题加到另一页去);
`RegisterAddOnCategory` **只对顶层调一次**,而且要放在子页挂完之后。

🔴 **这套 API 只造得出四种控件:checkbox / slider / dropdown / colorswatch —— 没有任何文本输入。**
(查的是 `Blizzard_Settings_Shared/Blizzard_Settings.lua` 的导出函数表,不是 wiki。)
⇒ **DoT 法术 ID / 两根条的刻度 / 引导跳数这三样结构上进不了面板**,只能留 `/dch`。
主页最底下那行小标题就是干这个用的 —— 没有它,人会在面板里翻找一个不在这儿的东西,
然后得出「这功能没做」。⚠ 颜色**能**进(有 ColorSwatch),只是这轮没做。

⚠ `getValue` 里**展开写,别用 `db and db[k] ~= false or default`** —— 值确实是 `false` 时
那个惯用法会走进 `or` 那支把默认值(true)端回去,症状是「我关掉的开关,下次打开面板又勾上了」。
(DodoInspect 在同族的 `and/or` 写法上栽过一次,见它 CLAUDE.md 第五颗雷。)

### 🔴 `dotFontScale` → `dotFontSize`:一个**被推翻**的设计决定,别当退步改回去

原来的字号是「图标边长 × 比例」,理由白纸黑字写着「不写死 px,否则图标一改字就相对缩成一个点」。
2026-08-15 改成绝对 px,**因为那条理由的前提没了**:它成立于只有 slash 命令的年代
(改完看不见,得进游戏再来一轮反馈);ESC 面板里三个滑条并排、拖动实时预览,反馈当场闭环。
而且宽高一拆,「乘哪条边」本身也没有答案了。
**代价照实记着**:改完图标大小,字号不会自己跟上,得再拉一下那个滑条。

⚠ 这跟 canon「控件尺寸从字号推、别写死 px」是**同一条经验的两面**,不是它的反例 ——
那条的射程是「没有即时反馈的调参」。**换了反馈通道就要重判,别照搬结论。**

### 宽高拆开 / 疯狂条开关,两处一改就半生效

- `dotWidth`/`dotHeight` 有**两个消费方**:按钮自己 `SetSize` + AuraGroup 的
  `layout.elementWidth/Height`。只改一处 = 「排列间距变了、图标没变」,半生效比不生效更难看出是 bug。
  另外**横向步距只跟宽有关**(`(i-1)*(w+sp)`),照抄成 `h` 会让「压扁图标」把横向间距一起改掉。
- `powerOn` 关掉时 **root 要塌成 1px**:root 的盒子**就是**疯狂条那一格
  (`power.frame:SetAllPoints(root)` ⇒ 真正决定它高度的是 `root:SetSize`,不是 `LayoutBar` 里那个),
  而血条锚它上沿、施法条锚它下沿 ⇒ 不塌就留一条等高空隙,读起来像「条没画出来」。
- 显隐归 `RefreshAvailability`、盒子大小归 `ApplyLayout` —— **切 `powerOn` 要两个都调**,
  少一个的症状是「盒子塌了、条还在」。

### SavedVariables 迁移:**必须跑在 `CopyDefaults` 之前**

`CopyDefaults` 一跑,`dotWidth`/`dotHeight` 就被填成默认值(非 nil)⇒ 迁移块里 `== nil` 的判据
永远不成立 ⇒ **他调过的尺寸静默丢掉**,而症状只是「下次登录图标变回 36」,零报错。
判据用「老键还在不在」而不是加 `uiPassXXX` 标记:老键被搬空本身就是「搬过了」,自证且幂等。

**离线验过**(`scratchpad/test_migrate.lua`,15 项):从真文件里**抠出** DEFAULTS / CopyDefaults /
迁移块来跑,不手抄第二份(手抄的那份会跟 bug 共享同一个误解)。覆盖全新用户 / 老用户带自定义值 /
改过比例 / 幂等重跑;**第 5 条是负对照 —— 故意把顺序调反,必须丢值**(实测 45 → 36),
否则前面四条的绿是空转。

### ⚠ 真机第一次跑要确认的

- **子页真的出现在左边**(`RegisterVerticalLayoutSubcategory` 的挂载形状是照源码写的,没在游戏里验过)。
  没出现 = 这里少一次注册。
- 关掉疯狂条,血条和施法条**靠拢**(不是留一条空隙)。
- 面板里改完,HUD **当场**变(所有 `onChanged` 都接了 `ns.ApplyLayout`)。
- 老 SavedVariables 里 `dotSize` 被搬进 `dotWidth`/`dotHeight` 且**老键消失**
  (`/dch dsize` 无参会打印现在的宽 x 高)。

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
