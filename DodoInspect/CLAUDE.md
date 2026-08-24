# DodoInspect — 交接文档(改之前先读这个)

> 本文档随仓库同步,CurseForge 打包时排除(workflow 里 `-not -name CLAUDE.md`)。
> 这是**跨机器传递"坑"的唯一可靠渠道** —— 本地 memory 不跨机器同步,git 仓库才共享。

## 这是什么
背包物品覆盖层 + 角色装备栏侧面板 + 目标信息行,Raider.IO 风格装等渐变。
文件:Config(可调参数)/ Locales(本地化,唯一含非 ASCII)/ Gradient / ItemInfo /
Overlay(物品按钮字串/图标覆盖层 + 共享 `SetEnchantAndGems`)/ Equipment(角色面板:装等+附魔+宝石)/
Inspect(检视框装备覆盖层:装等+附魔+宝石)/ Bags(背包覆盖 + 共享 `ns.ApplyItemOverlay`)/
Bank(玩家银行复用 ApplyItemOverlay + 公会银行链接版覆盖)/ SidePanel(角色装备侧栏)/
StatPriority(属性优先级行 + 英雄天赋检测; 数据在 Data/StatPriority.lua)/
StatPriorityConfig(玩家自定义优先级:存储 / 排序形状 / 编辑窗)/
InspectPanel(检视简化侧栏)/ Durability(平均耐久并入物品等级行 `286.1 ｜ 88%`)/
StatRatings(强化属性栏:百分比+评级三列 + 装等渐变/小数)/
TargetInfo(目标信息行)/ Options(ESC 设置 + `/dins`)/ Core。

## ⚠️ 头号坑:Secret Values —— ~~只在 TargetInfo.lua~~ **不只**(2026-08-11 更正)

> 🔴 **这个标题以前写的是"只在 TargetInfo.lua",那句话本身就是 2026-08-11 那次崩溃的帮凶之一** ——
> 新写 `StatPriority.lua` 的时候,读到"只在 TargetInfo"就没去想 guard。**下面那条
> `grep -n "Secret 审计结论" CLAUDE.md` 命中的结论同样有过期风险:它是 2026-06-13 的快照,
> 不是不变量。** 加任何读非玩家单位的代码,都自己重新点一遍。
> ⚠ 这里原文写的是「下面**第 41 行**那条」——**那个行号在写下的那一刻就已经是错的**
> (写它的那个 commit 里,「审计结论」在第 45 行;41 行是不相干的另一句)。
> **别再往 doc 里写行号,写 grep 得到的文字锚点。**
**血泪史(2026-06-13,同一个功能连踩 3 次崩溃)**:战场/竞技场里**敌对玩家的单位字段
是 secret value**。被污染的插件代码对它做**比较 / 算术 / 拼接 / `#` / `math.floor` /
`tostring`** 都会抛 `attempt to compare ... a secret ... value, while execution
tainted by 'DodoInspect'`。

踩过的三颗雷(都在目标信息行):
1. 计分板 `C_PvP.GetScoreInfo(i).guid` 是 secret → 按 guid 匹配,比较即崩。
2. 改按名字 → `GetUnitName("target")` 读目标 secret 名字/服务器崩。
   (`GetUnitName` 是 FrameXML **Lua**,被我们调用时跟着污染跑;`C_*` 是引擎 **C**,安全。)
3. `UnitClass("target")` 的本地化 `className` 是 secret → 拼进行内后
   `measure:GetStringWidth()` 返回 secret 数字,换行宽度比较崩。

**交叉封锁**:目标的 GUID 可读、名字 secret;计分板的 GUID secret、名字可读 ——
暴雪故意让插件无法把"敌方目标"和"计分板某行"关联起来。这功能本就是它要挡的。

**现行解法(别 regress 回去)**:
- 职业名:用**可读的 `classToken`** 查常量表 `LOCALIZED_CLASS_NAMES_MALE`,
  **不要**用 secret 的 `className`。
- 战场专精:引擎 C 函数 `C_PvP.GetScoreInfoByPlayerGuid(可读 UnitGUID)` 让引擎在
  安全上下文里定位行,**不要**自己遍历计分板比较。
- 每个文本字段经 `AddPart`(`issecretvalue` 先挡)。宽度测量/换行整段套 `pcall` 兜底。
- **`issecretvalue(x)` 永远第一个检查**(它接受 nil、对 secret 不抛)。

**Secret 审计结论(2026-06-13)**:secret value 只来自**敌对单位身份**(战场/竞技场)+
**战斗中属性**。`TargetInfo` 读**敌对目标**(高危,已全面加固);`Inspect`/`InspectPanel`
读**被检视单位**(只能检视友方/同阵营 → 装备链接可读、非 secret),但仍 `issecretvalue`
先挡(链接/装等/属性)做防御,与全局姿态一致。`Bags`/`Bank`/`Equipment`/`SidePanel`/`ItemInfo`
只读**你自己的**物品(玩家银行=自己的容器;公会银行=公会物品链接,均**永不 secret**)。**🆕 1.5.0 起 `StatRatings` 是唯一读战斗属性 API 的文件**
(`GetCombatRating`;玩家自己的属性**仅战斗中 secret**)—— 进战斗直接 bail(根本不调用)+ `issecretvalue` 兜底
+ 整段 `pcall`,战斗中冻结显示、脱战刷新。现实终态:战场敌方只能
显示种族 + 职业;竞技场专精走 `GetArenaOpponentSpec`,不受影响。

### 🔴 第四颗雷(2026-08-11,12.1,BugSack `12x`):`StatPriority.lua:47` 的 `id > 0`
`ns.InspectSpecID` 少了 `issecretvalue` guard,`GetInspectSpecialization("target")` 对**敌对玩家**
返回 secret number → `id > 0` 当场崩。**四条独立的失效原因,每条单独都够让它发生**:

1. **`type(id) == "number"` 挡不住 secret** —— secret 保留原生 type,报错 locals 里那个
   `(*temporary)="number"` 就是它顺利通过的证据。**`issecretvalue` 是唯一的闸,而且必须排第一。**
2. **两份平行实现,只有一份有 guard** —— `TargetInfo.GetInspectSpecID` 早就写对了
   (`SpecNameByID` 里 `issecretvalue` 打头),新写的 `ns.InspectSpecID` 没抄到。
   **已合并成一个入口**:TargetInfo 那份现在委托 `ns.InspectSpecID`(TOC 里 StatPriority 先加载)。
   顺带修掉 `GetInspectHeroTalentName` 里第二处裸 `specID <= 0`(它当时只被 `HasValidInspectData`
   偶然挡着 —— 典型的"免检口没人验过")。
3. **`InspectPanel` 的 `unit` 根本不保证是友方** —— 上面那句"检视只能对友方 → 非 secret"
   **被 unit token 的本质破坏了**:`InspectFrame.unit` 存的是**unit token**(通常就是 `"target"`,
   这正是 `or "target"` 那条 fallback 能成立的原因),**它跟着你的目标走**。检视窗口开着 + 目标切到
   敌对玩家 = 这个"只对友方"的面板正指着一个满身 secret 的人。
   ⚠ **第一版修复只给 fallback 那个分支加了 `CanInspect`,恰好漏掉主场景**(`.unit` 非 nil 时);
   现在 `CanInspect(unit)` 无条件 qualify unit 本身。
4. **fail-closed 闸门装错了层** —— 1.8.0 明明把整个功能关了
   (`STAT_PRIORITY_DATA_CURRENT=false`),照崩。因为闸门在 `Resolve()` **函数体内**,而
   `ns.UpdateStatPriorityHeader(panel, ns.InspectSpecID(unit), …)` 的**实参先于调用求值** ——
   崩在参数上,闸门那行根本没机会跑。**新增 `ns.StatPriorityActive()`,两个面板都在查 spec 之前 gate。**
   ⚠ 仍然要用 `nil` specID 调一次 `UpdateStatPriorityHeader`,布局靠它把 `dodoPriorityHeight` 归零。
   🔑 **可迁移心法:"功能已关闭"不等于"那条代码不会跑" —— 闸门必须在最外层的求值之前。**
5. 🔴 **修完上面四条,把一个从没被执行到的隐患 unshadow 了**(发版前审计抓到,**本次最值钱的一条**):
   row 循环里 `if row.slotID == 17 and not GetInventoryItemLink(unit, 17)` —— **裸布尔测试,无 guard**。
   而 `not <secret>` **本身就是对该值的操作、会抛**(见 `DodoNameplate/GOTCHAS.md` S1,同一条规则
   游戏内验证过;本文件 `UpdateRow` 对**同一个 API、同一个 unit** 写的正是 `issecretvalue(x) or not x`,
   那个短路顺序只有在这条成立时才有意义)。它一直没炸,**只因为 1.8.0 时 `StatPriority:47` 先崩、
   执行压根走不到 row 循环**。我把前面那个修好 → 它第一次够得着 → 崩溃会原地**换个行号复活**,
   而读起来像"根本没修好"。来源还是**抄代码丢 guard**:这行抄自 `SidePanel`,那边 unit 硬编码
   `"player"` 永不 secret。
   🔑 **心法:修掉一个早退型崩溃 = 把它后面所有代码第一次暴露出来。改完必须问「现在能走到哪儿了?」**

`12x` = 同一行被连打 12 下:`GET_ITEM_INFO_RECEIVED` 每个未缓存物品都发一次,
每次都 `C_Timer.After(0, ns.UpdateInspectPanel)`。

**复现姿势**(修完想验就这么点):开着检视窗口 → 目标切到敌对玩家(战场最快)→ 旧版必进 BugSack。

### 🔴 第五颗雷(2026-08-14,发版后静态审计抓到)—— **同一条路径,但根本不是 secret value**

复现路径跟第四颗一模一样(检视窗口开着 → 目标切敌对玩家 → **点部位按钮**),
而根因是另一回事,**所有 secret 防护在结构上都看不见它**。

`InspectPanel` 给部位按钮传的不是 unit token,是一个**解析函数**,好让 unit 在**点击那一刻**
现读(`InspectFrame.unit` 跟着目标走,见第四颗雷第 3 条)。这个设计是对的。坏在取值那一行:

```lua
local resolved = type(self.unit) == "function" and self.unit() or self.unit
```

`CurrentInspectableUnit()` **恰恰在目标不可检视时返回 nil**(敌对玩家 = 战场最快),
于是 `and` 那支求出 nil → 掉进 `or` → **`resolved` 变成那个解析函数本身**。
接着 `state.unit = unit or "player"`(函数是 truthy,兜底不开火)→ `ViewedSpec()` →
`ns.InspectSpecID(<function>)`,而它当时只挡 `if not unit` ⇒ 函数照样放行 ⇒
一个函数被当成 unit token 送进 `C_SpecializationInfo.GetInspectSpecialization`。

🔑 **为什么「三重防护」挡不住**:`pcall` + `issecretvalue` + `type` 全是冲着 **secret value** 去的,
而这个值**一点都不 secret —— 它只是不是一个 unit**。`EquippedID` 因为外面套了 `pcall` 侥幸没事,
spec 那条没有。⇒ **同一条高危路径上可以有两种完全不同的坏法;把它整个归类成「secret 问题」,
就只会去审 secret。**

**修法(三层,每层单独就够)**:
1. 抽出 `ns.ResolveSlotUnit()`,**展开写、不用 `and/or` 那个惯用法**,nil 有地方可去。
2. `ns.ToggleGearPanel` 要求 unit 必须是 string,**并删掉 `or "player"` 那个兜底** ——
   从检视面板兜回 "player" = 拿**自己的**排名顶着**别人的**部位名(canon:标签的主体和数字的
   主体必须是同一个东西)。解析不出 unit 时**关掉面板**,不是静默 no-op:屏幕上那份数据
   属于一个已经读不到的人。
3. `ns.InspectSpecID` 改成 `type(unit) ~= "string"` 才放行 —— 它是**所有**非玩家 spec 查询的
   唯一入口(TargetInfo 一并保住)。这层是「修类不修例」。

**离线测试 + A/B**:`tools/test_gearrank.lua` 从 77 → **86 checks**。把两处原样种回去,
**精确红 3 条**,且断言文字点名 battleground path。
⚠ **第一版那两条 `InspectSpecID` 断言是空转的** —— harness 里 `C_SpecializationInfo` 压根不存在,
有没有 guard 都返回 nil,红绿零信息量。补了 stub + 一条「真 unit token 必须答出 258」的**反向断言**
证明桩真被走到,`sawBadUnit` 才是那个会翻的量。(canon `rules/engineering.md` guard 家族第 (a)/(d) 型。)

⚠ **未真机验证**:`GetInspectSpecialization(<function>)` 到底是**抛错**(多半)还是静默返回 nil,
本机验不了。两种都是 bug、修法相同,但严重度从「BugSack 报错」到「面板静默空白」都有可能 ——
**别把「它会崩」当成已证实的事**。

## 掉落来源 + 部位候选面板(2026-08-14 写完并发版)

> ⚠ **本节的横幅原来写的是「🚧 未发版 / 游戏内零验证」—— 那句已经不成立**
> (HOME 真机跑过一部分,之后发了版)。**发版状态一律别在这份 doc 里读**:查
> `gh run list --repo Baeseata/Wow-Addons`(**CI 的运行记录是一次性写入的,不会被编辑**,
> 比 tag 和 doc 都可靠;点进去看 CurseForge 那步回的 file id 就是上传回执)
> + `git ls-remote --tags origin 'DodoInspect-*'`(有 `^{}` peel 行才是 annotated)。
> ⚠ 原文这里指向 `Wow-Addons/PUBLISHING.md` §8 —— **那个文件在 repo 里不存在**
> (2026-08-14 `git ls-files` 实查,带负对照)。别再去找它。
> 本节只留技术内容;还欠着的真机验证见下面那张清单。

**新增文件**:`Data/Loot.lua`(生成物)· `LootSource.lua` · `GearRank.lua` · `GearPanel.lua`
· `tools/gen_loot.py`(生成器)· `tools/test_gearrank.lua` + `tools/fixture_itemshape.lua`(离线测试)。

**两个功能默认都是开的** —— ⚠ **这里原来写的是「都默认关」(opt-in),那句已作废**:
2026-08-14 Jerry 拍板改成默认 ON,`AddOptInCheckbox` 已删(见下面「HOME 续作」那节)。
本节没跟着改,于是 2026-08-14 晚上有人照它去 ESC 里找开关勾——**doc 里同一件事写两处,
一处更新一处没更新,先读到的那处就是坑**:
- `showLootSource`:物品 tooltip 加一行来源。团本 `副本名 #N Boss名`,大秘境只给副本名。
- `showGearPanel`:两个侧栏最左列部位名变可点,点开右侧挂载窗口列该部位候选,按属性契合排序。

**数据怎么来 / 怎么重生成**(换赛季就跑这个,改 `gen_loot.py` 顶部的 `RAIDS`/`DUNGEONS` 常量):
```
python tools/gen_loot.py          # 重写 Data/Loot.lua + tools/fixture_itemshape.lua
lua tools/test_gearrank.lua       # 60 项离线测试,必须 0 failures
```
本机 `luac` / `lua` 已装(`~/AppData/Local/Programs/Lua/`),`luac -p <file>` 可做语法验证 ——
**这是本插件第一次有可自动跑的验证手段,别丢掉**。

**零翻译原则**:数据文件只存 ID。物品名走 `C_Item.GetItemInfo`、副本/Boss 名走
`EJ_GetInstanceInfo`/`EJ_GetEncounterInfo`、部位全名走全局串 `_G["INVTYPE_HEAD"]` ——
**中英法西四语全部由客户端本地化,插件一个装备名都不存**。只有 7 个自己的 UI 串进 Locales。

**边界(设计上就不做,不是没做完)**:护腕/披风显示"通常用制造装备"静态提示(缀饰件不在任何
掉落表里,而且它的副属性是玩家做的时候自选的)。

> ⚠ **这一节原本还有三条,现在**三条都不成立了**,留着当反面教材**:
> ① ~~武器不排序~~ → 2026-08-14 第三轮已做(按配装形态分,见下面武器两行那节);
> ② ~~不看装等~~ → Jerry 拍板让 344 档进排序,而且装等后来查得到了(见 `ItemScalingConfig` 那节);
> ③ ~~饰品不排序(价值在特效)~~ → **那个理由已被证伪** —— sim 数据本来就把特效算进去了,
> 而且存在可用的免费结构化数据源。调研与判据见
> [`TRINKET_DATA_RESEARCH_2026-08-14.md`](TRINKET_DATA_RESEARCH_2026-08-14.md)。
> **2026-08-14 晚 Jerry 拍板并已施工**(全开按钮 + 没数据显式文案 / 钉死单目标 /
> 跟赛季手动重抓)—— 见下面「饰品排序」那节。**这条边界现在整条作废,三条全部作废了。**
>
> 🔑 心法:**「设计上就不做」的理由会过期,而写下它的那句话不会自己更新。**
> 每条边界都该能说出**它依赖的那个前提**,下次碰到时先问那个前提还在不在。

### 🔴 这轮踩到的坑(每条都真的咬过一次)

1. **`ItemSparse.ItemLevel` 在这个场景完全不可用**:烈毒之渊 219 / Midnight 地牢 108 /
   诸王之眠·塞塔里斯 **59**(BfA 原值)/ 红玉 250。老本回归靠 bonusID 在运行时拉装等,
   静态表里那个数字是假的。⇒ **面板绝不显示装等数字**,否则会显示 59。
   「不看装等只按属性排」不是简化,是**唯一可行**。
2. **披风的护甲类型是 `Cloth`**(`cls4 sub1`),主属性 `SAI`。按 subclass 过滤 = 只有布甲职业
   看得到披风,其他职业那一行**空白**,而空白读起来像数据缺失。⇒ `GearRank.ARMOR_TYPE_SLOTS`
   白名单只对真护甲部位开过滤。**这个 bug 是测试抓到的,A/B 种回去精确报两条红。**
3. **`JournalEncounter.OrderIndex` 基数不一致**:8-boss 团本是 **1..8**,单 boss 团本是 **0**。
   直接打印会出 `#0` 和 `#9`。⇒ 生成器按 OrderIndex 排序后**重编号成 1..N**。
4. **武器/副手在 `StatModifier` 里有第二个主属性条目**(单手武器既有 `Int:5259` 又有
   `Int:25370`),循环里后者会覆盖前者。⇒ 取**第一个**;并加断言:**护甲**若出现多主属性
   条目直接报错退出(护甲一旦中招,主属性过滤就静默失效,板甲职业会互相看到对方的装备)。
5. **`ClassID ∈ {2,4}` 过滤不干净**:混进 3 件**幻化头饰**(Armor subclass 5,ilvl 1,零属性)。
   ⚠ 但 subclass 5 只对 **Armor** 是幻化,对 **Weapon** 是**法杖** —— 别无条件排除 subclass 5。
6. **49 件装备零副属性**,分三类:饰品 33(正常)· 武器 2(不做)· **护甲 14**。那 14 件全是
   ilvl 59 的 **BfA azerite 头/肩/胸**(那个年代就没有副属性),只出现在诸王之眠和塞塔里斯神庙。
   ⇒ 保留并标记 `unranked` 排在最后,**不删掉** —— 装备从列表里消失读起来像数据不全。
7. **`tools/` 里的 `.lua` 会被打进 CurseForge 包**,而那个防泄漏 guard 只查 `CLAUDE.md`
   和 `/test/`,**会绿着放行**。已同时补 `find` 排除和 guard 的 grep(两处都改,只改一处等于没改)。
8. **`ns.StatPrioritySpecCurrent` 返回 boolean**,不是 `"provisional"` —— provisional 要直接读
   `ns.StatPriority[specID].provisional`。我一开始按名字猜了语义,猜错。

### ⚠ 真机第一次跑必须验的(按风险排)

- **EJ API 冷启动**:`EJ_GetInstanceInfo` / `EJ_GetEncounterInfo` 在 `Blizzard_EncounterJournal`
  没加载时能不能答。`LootSource.lua` 做了 lazy `LoadAddOn` + `pcall` + 缓存,**拿不到就不显示
  那一行**(不显示占位符)。→ 验:全新登录后直接开背包看 tooltip 有没有来源行。
- **secret value**:`InspectPanel` 的 unit **跟着目标走**,开着检视窗口把目标切到敌对玩家
  (战场最快)→ 点部位按钮。`ViewedSpec` 走 `ns.InspectSpecID`(已 guard),`EquippedID` 自己
  `pcall` + `issecretvalue` + `type` 三重挡。**这是本插件历史上崩得最多的一条路。**
- **`_G["INVTYPE_HEAD"]` 这类全局串是否真的存在** —— 面板标题靠它出四语部位全名,不存在时
  回落到两字母缩写(标题会变成 "HD",丑但不炸)。
- **`panel:SetParent(anchorFrame)`** 让面板跟着侧栏一起隐藏(角色框关 → 侧栏隐 → 它隐)。
  验:开着面板关角色框、以及关检视窗口。
- 部位按钮的**可发现性**:悬停要变亮 + 出下划线,已打开的那行下划线常驻。

### 2026-08-14 HOME 续作(真机跑过一部分,**尾巴全未验证**)

Jerry 在 HOME 上装了上面那批未发版代码并实测,以下为这一轮的结果与改动。

**真机确认可用**(有截图):掉落来源 tooltip 行 · 部位按钮 · 候选面板 · 四列属性网格 · 去重 · 344 标记。

**🔴 修的第一个 bug —— 又是「FontString 没字体」**:`GearPanel.NewCell` 用
`CreateFontString(nil,"OVERLAY")` 且**没跟 `SetFont`** → 点开面板必崩 `3x FontString:SetText(): Font not set`。
**这是本插件第二次栽在同一个坑**(1.1.1 TargetInfo 那次)。本次顺带把全插件 13 处
`CreateFontString` 全扫了一遍,其余都合规(另外 3 处可疑是假红,字体在 `SetText` 前一两行设了)。
⇒ **本仓约定:`CreateFontString` 不带模板时,下一句必须是 `ns.SetOverlayFont`。**

**Jerry 拍板的设计变更**(推翻了原设计,理由记在各自代码注释里):
- **两个开关默认 ON**(原为 opt-in)。他自己管赛季数据更新,不需要插件替他保守。
  改了**三处**:`Options` 的 checkbox(`AddOptInCheckbox` 已删)+ `LootSourceEnabled` + `GearPanelActive`。
- **装等进入排序**(原设计明写「不看装等」)。烈毒之渊 **#7/#8 且带主属性**的 → 排该部位最前;
  **戒指/项链不吃这个提升**(`[4]` 为 nil),因为那 10 点装等买的是主属性。见 `GearRank.NINE_SIX_SOURCES`。
- **面板新增装等列**:344 金 / 334 灰 / azerite 件留空(它们不在任何当前轨道上,报任何数都是撒谎)。
- 属性列改为**四列缩写网格**(同侧栏那套:同列序、同色、dominant 下划线),去掉百分比与契合度。
- 字号改为**跟随侧栏字号**,几何全部由它推导。

**⚠ 未验证清单(2026-08-14 OMEN 续作后更新)**:
1. ~~bonusID 那条路~~ ✅ **已实测 + 已落地**(见下节)
2. ~~`TooltipLink` 走百科全书那条~~ ✅ **整条已删** —— bonusID 路通了就不必再借
   EJ 的选中状态,连带 `FirstItemLink` / `linkCache` / `MYTHIC_RAID` 一起清掉。
   (`ns.EnsureEncounterJournal` / `ns.LootEntry` **没删**,掉落来源那条路还在用)
3. ~~制造装等 `331` 待验~~ 🔴 **已查:game data 里没有任何东西支持 331**(2026-08-14 OMEN,
   见下面「12.1 升级轨道」节)。三条:① 全 build 里**只有一条** bonus list 能出 331,
   就是 `12853` = **Myth 5/9**;② 337 是 **Myth 7/9** ⇒ 那批 pre-season 来源不是编数字,
   是**把中间档当成了顶**;③ 本赛季**所有**制造装备走的是**制造品质组**(591:
   +0/+3/+6/+9/+13),`ItemContext=13`(TradeSkill)的节点**一个都没有**指向
   614–618 任何升级轨道。**真正的制造上限没查出来** —— 这是「没查到」不是「等于某个数」。
   ⇒ **Jerry 看完上面三条后拍板:331 保留不动**(2026-08-14)。这是决定不是遗漏 ——
   **别看到 Config 那段注释就顺手把它改成 `nil`**,那段他读过了
4. ~~`INVTYPE_FINGER` 空真~~ ✅ **已显式化**:改成问「把主属性条件拿掉它会不会被促」
   (调 `ns.ReachesTopItemLevel` 真函数,不复刻 `NINE_SIX_SOURCES`),
   并把「本赛季没有 9/6 戒指」本身断言成一条 tripwire —— 哪个赛季掉了戒指它就变红,
   而那正是上面那条断言开始有意义的时刻。NECK 侧配了反空转断言。A/B 两条各自精确变红
5. 🔴 **新的 tooltip 渲染路径游戏内零验证** —— 只跑过离线测试 + 构造串跟实测有效串
   逐字符比对。真机第一次跑先 hover 一件老本装备看是不是紫的 334/344
6. **武器两行:UI 侧已验过一部分** —— 2026-08-14 Jerry 在 OMEN 上验过**双手/单手 + 副手切换**
   和**副手三种空状态文案**,均 OK;**其余验收点仍未测**,更精确的那份清单在
   `grep -n "真机验收:2026-08-14" CLAUDE.md` 命中的那一条(纯双手专精无副手行 / 猎人只出远程 /
   21 个切换专精名单 / 神圣骑 6 面盾 / 恢复萨·元素萨单手 / 面板高度封顶 + 截断标题的 `N/M`)。
   ⚠ 本条原文写的是「🔴 **整个没上过真机**(已拷进游戏目录未 reload)」——**两句都作废**:
   前半句被同文件那条更精确的验收记录推翻,后半句是一个早已过期的**机器状态**。
   而且这功能**早已发版** —— 发到哪一版**别在这儿读**,查
   `git tag -l 'DodoInspect-*' | sort -V` + TOC 的 `## Version`。
   ⚠ 离线测试到 **128 checks**,但那证明的是排序和过滤,**不覆盖 UI**

### ✅ 已落地:tooltip 按 6/6 / 9/6 渲染(2026-08-14 OMEN,实测 + 代码已改)

Jerry 的需求:面板里 hover 一件老本装备,tooltip 显示的是 **ilvl 28 蓝色**(`SetItemByID` 渲染的是
**不带任何 bonusID 的基础形态** —— 不是 bug,那字面上就是赛季 bonus 应用前的样子)。他要看升满后的属性。

**挖法(可复用,比翻攻略网站可靠得多)**:让 Jerry 跑
`/run for _,s in ipairs({1,2,3,5,15}) do local l=GetInventoryItemLink("player",s) if l then print(s,(l:gsub("\124","\124\124"))) end end`
把自己装备的 link 打出来 → 提取 bonusID → 去 `wago.tools` 的 `ItemBonusListGroupEntry` 反查它属于哪个轨道组。
**他自己的客户端是权威源,版本必然对得上。**

**已得结论**(2026-08-14,用他三件装备校验过):

| 观测 | bonusList | 所属 group | 结论 |
|---|---|---|---|
| 肩/背 285 | `12827` | 615 rank3 | — |
| 头 292 | `12833` | 616 rank1 | 616 = **Champion**(1/6=292) |
| 颈 305 | `12841` | 617 rank1 | 617 = **Hero**(1/6=305) |

⇒ **`group 618` = Myth 轨道**,而且是全表**唯一一条 9 rank 的**(其余皆 8),第 9 段 bonusList `13848`
**不连号**(前 8 段 12849–12856 连号)= 赛季中期补上 9/6 在数据里的样子。

- **Myth 6/6 → bonusList `12854`**
- **Myth 9/6 → bonusList `13848`**

⚠ `ItemLevelSelector` 里查不到 334/344(**全量扫过 1971 行,各 0 命中**)—— 这句仍然成立,
但**结论「只能进游戏量」已经过时**:装等确实读得到,只是在**另一张表**里。
见下面「12.1 升级轨道:装等在 `ItemScalingConfig`」。

**✅ 实测结果(2026-08-14,item 250243)**:`12854` → ilvl **334** / quality 4;
`13848` → ilvl **344** / quality 4。两个都跟预期一致,已进 `Config.GEAR_MYTH_BONUS_ID`
/ `GEAR_TOP_BONUS_ID`,`GearPanel.TooltipLink` 改为自己构造 link。

🔴 **两个坑,都真咬过一次**:
1. **冒号数原本写错了** —— 交接里那条命令写的是 itemID 后 **13** 个冒号,正确是 **12**
   (11 个空字段 enchant/四宝石/suffix/unique/level/spec/modifiers/context,然后才到
   `numBonusIDs`)。多一个 = 每个字段整体错位一格,而 `GetItemInfo` **只回 nil,不给任何提示**。
   ⇒ 代码里写成 `string.rep(":", 11)` 让数量是**声明的**而不是数出来的;
   验收时拿构造串跟「游戏里真的成功过」那个串逐字符比,并用 `rep(10)`/`rep(12)` 当负对照
   证明这个比对不是恒真。
2. **第一枪必然全 nil** —— `GetItemInfo` 对没缓存的物品**本来就返回 nil**(只触发异步加载)。
   跟第 1 条叠在一起时特别难分辨:两个原因产出的症状**一模一样**。
   ⇒ 诊断要拆开问:`GetItemInfoInstant`(同步,验 itemID 有效)+ 裸 ID 查询(验缓存)
   + 打印构造串(肉眼核字段)+ 带 bonus 查询,一条命令四个探针。

⚠ **`GEAR_TOP_ITEM_LEVEL` / `GEAR_MYTH_ITEM_LEVEL` 故意没改成「从游戏现读」**(HOME 建议过):
收益只有省两个常量,代价是要硬编码一个探针 itemID;而**每赛季 bonusID 本来就得重挖**,
所以「不必每赛季手改」只成立一半 —— 那两个数跟 bonusID 是同一批要换的东西,放一起手改反而清楚。

**下面是原始挖法记录**(换赛季重挖时照走):
```
/run local id=250243 for _,b in ipairs({12854,13848}) do local l="item:"..id..":::::::::::::1:"..b local n,lk,q,i=C_Item.GetItemInfo(l) print(b,n,"ilvl",i,"quality",q) end
```
期望:`12854` → ilvl **334**,`13848` → **344**,quality 均为 4。
- 对上 ⇒ 两个 ID 进 Config,tooltip 改 `SetHyperlink` 构造串,**并删掉 `TooltipLink` 那条百科全书路径**;
  顺带 `GEAR_TOP_ITEM_LEVEL`/`GEAR_MYTH_ITEM_LEVEL` 两个手填数字可改成**从游戏现读**,不必每赛季手改
- 对不上 ⇒ 多半还需带上同行的其他 bonusID(他装备上还挂着 `6652` / `13662` 这类),调 link 再试

⚠ **这些 bonusList ID 是赛季性的**,换赛季必须重挖(方法同上,几分钟)。

### 🔑 12.1 升级轨道:装等住 `ItemScalingConfig`(2026-08-14 OMEN)

**这条把「换赛季的装等只能进游戏一个个量」变成了一次表查询。** 链路:

```
ItemBonusListGroupEntry   ItemBonusListGroupID -> ItemBonusListID + SequenceValue
  -> ItemBonus            ParentItemBonusListID, Type=49, Value_0
       -> ItemScalingConfig.ID -> .ItemLevel      <-- 真装等在这儿
  (老一点的轨道用 Type=48,装等直接就在 Value_1,不用再跳这一次)
```

**校准集(不是推出来的,是对上的)**:五个**游戏内实测过**的装等,五个全中 ——
`12827`→285(肩/背)· `12833`→292(头)· `12841`→305(颈)· `12854`→**334** · `13848`→**344**。
外加一条结构佐证:每条轨道的第 5 段 == 下一条轨道的第 1 段(279 / 292 / 305 / 318 逐级咬合),
那是 WoW 轨道本来的形状,不是凑出来的。

**12.1 Season 2 六条轨道**(`?build=` 的值去 `https://wago.tools/api/builds` 查 `wow` 分支):

| 轨道 | group | 装等阶梯 |
|---|---|---|
| Explorer | 607 | 245 248 252 255 258 261 265 268 |
| Adventurer | 614 | 266 269 272 276 279 282 285 289 |
| Veteran | 615 | 279 282 285 289 292 295 298 302 |
| Champion | 616 | 292 295 298 302 305 308 311 315 |
| Hero | 617 | 305 308 311 315 318 321 324 328 |
| **Myth** | **618** | 318 321 324 328 331 334 **337 340 344** |

⚠ **group 626–630 是下个赛季的**(336–411),形状跟 614–618 一模一样,别当现状。
判据:拿**真机实测过的装等**去认哪一套是当前赛季,别按 group 号大小猜。

**这套表顺手证伪了三个数**(三个全出自同一批 pre-season 来源):
- **337** 不是 Myth 顶,是 **Myth 7/9**(顶是 344);
- **341**(旧 Config 注释说 Ascendant Venomstone 到这儿)—— **全 build 就没有 341 这个装等**;
  而且叫 "Venomstone" 的东西不存在,只有 `Venomcursed`,它给的是**效果、零装等**;
- **331** 全 build 只出现一次,是 **Myth 5/9**,不是制造上限。

⇒ 🔑 **心法:一个数「出自被证伪过的那批来源」不等于它是编的 —— 更常见的是它是真值、
但被挂错了档位。** 分清这两种,才知道该丢掉它还是该改用法。

### 2026-08-14 OMEN 第二轮:面板瘦身 + 权重曲线(Jerry 看过真机后提的 4 条)

1. **武器 / 饰品这期不做** —— ⚠ **本条已整条作废**:武器 1.11.0 放出来了,饰品 1.12.0 放出来了,
   `UNRANKED_SLOTS` **现在是空的**。留着是因为下面那句「不建按钮而不是给空列表」的理由仍然有效。
   〔原文〕`GearPanel.UNRANKED_SLOTS` 里的 3 个 key
   (`INVTYPE_TRINKET` / `WEAPONMAINHAND` / `WEAPONOFFHAND`)**不给部位按钮**。
   过滤放在 `AttachSlotButton` 一处,同时覆盖侧栏和检视面板。
   ⚠ 做法是**不建按钮**而不是"点开后给空列表" —— 看着能点、点开是空的比不能点更糟。
   要做回来:删对应 key 即可,数据层什么都不用动。
2. **装等列删了**。`topItemLevel` 仍然活着(决定排序 + tooltip 用哪个 bonusID),只是不占一列。
   连带清掉三个变成零引用的 Config 项(`GEAR_TOP_ITEM_LEVEL` / `GEAR_MYTH_ITEM_LEVEL` /
   `GEAR_TOP_ILVL_COLOR`)—— 334/344 这两个数字记在 bonusID 注释里没丢。
3. **属性四列 → 固定两列**,第一列是该装备**数值大**的那条绿字。理由:一件装备最多两条副属性,
   列-per-属性的网格永远空着四分之三。⚠ 代价:**不再跟侧栏同列序**(那边"列 = 属性",
   这边"列 = 名次");dominant 下划线一并去掉,位置已经表达主次。平手时按 `ns.STAT_ORDER`
   稳定排,免得同一件装备每次刷新换位置。
4. 🔴 **权重曲线 `{1.00,0.70,0.45,0.25}` → `{1.00,0.80,0.60,0.15}`**,正文见
   `GearRank.POSITION_WEIGHT` 注释。**这条最值钱的是它的排错过程**:

   - **症状**:暗牧(急>精>爆>全)的戒指列表里,#2 和 #4 都带全能。
   - **不是全能权重高**:#2 = 急78%+全22% = 0.780+0.055,它赢在**急速占比**(78 vs 64),
     全能那 0.055 反而在拖后腿。
   - 🔴 **只降末位权重完全无效**:0.25 → 0.10 实测那个列表**零位移**(两边算出来都是 0.802)。
     真正的旋钮是**把中间档抬起来** —— 暴击 0.45→0.60 让它那 36% 立刻多值 0.09。
   - ⚠ **我第一次量错了**:量的是「**第一名**变了几个」,而问题发生在第 2/3 名之间,
     第一名压根不动 ⇒ 得出「这旋钮基本失效」的**相反结论**并报给了 Jerry。
     **度量选错了量,结论就是反的**(canon `rules/engineering.md` 那条 (f) 的实例)。
   - **曲线形状是设计决策**:Jerry 原话「本来应该跟 sim 走,但没空每个职业跑」⇒
     这条曲线是 sim 的**自认近似**:前三接近、末位单独拉开。测试里
     `curve shape` 那条断言把它锁住了(旧的均匀衰减曲线会红,A/B 验过)。
   - **测试的两条硬编码权重值改成了从 `ns.StatWeights` 推导** —— 否则每次调参都会冒出
     两条"看起来跟 tie group 有关、其实只是数值变了"的假失败。

### 2026-08-14 OMEN 第三轮:武器两行

> ⚠ 本节标题原来带着「**已写完,未发版**」—— 那是 2026-08-14 写下的**状态快照**,当天晚上就不成立了。
> 本节只记**做了什么**(内容不变);「发没发 / 发到哪一版」按本文「版本历史」那节的规矩查,
> 别在这儿读。

武器主手/副手从 `UNRANKED_SLOTS` 放出来了。核心不是「把武器加进来」,是**先解决那两行是耦合的**:
主手选双手武器 ⇒ 副手根本没有装备。按旧模型两行各排各的,会推荐出**不可能存在的组合**
(主手法杖 + 副手圣物)—— 那是错误建议,不是排版问题。

**模型分两半,混起来就是坑**:
- **CAN(能不能装)= 推导**,`ns.SpecWeapons` / `ns.SpecShield`,生成器从
  `SkillLine` + `SkillLineAbility.ClassMask` 推。⛔ 永不许手改。
- **SHOULD(该不该用)= 手写**,`GearRank.WEAPON_SHAPE` 40 行。推不出来:
  武器战**能**装单手+盾,只是不该,DB2 里没有任何一列说这个。

**8 种形态**(主手池 / 副手池),其中 **21 个专精是模糊的**(副手可空)⇒ 面板右上角出
**`双手 | 单手` 切换**(复用团/米 那个控件),**切一下两行一起变** ⇒ 结构上构造不出坏组合。
默认值**从被查看单位身上穿的推**(副手有东西=单手),**故意不持久化** —— 存一份会跟他换装打架。
其余 19 个专精**不显示**这个切换(缺席即信息;显示它等于邀请一个错误配装 ——
这跟旁边团/米 那个「总是显示」的先例**故意相反**,理由写在代码注释里)。

**面板高度封顶 = 左边侧栏的高度**(Jerry 拍板),每次刷新重算(字号滑条同时动两边)。
截断时标题右边出灰色 `12/17` —— **静默截断读起来像「就这些了」**,而那正是它不是的。

### 🔴 同轮修的两个 bug,都不在武器功能里

1. **所有盾被标成力量,智力用户一件看不到**(神圣骑副手空)。游戏用**两种方式**编码
   「多主属性可用」:单条混合码(74=SI),或**两条分开写**(`STR:5259`+`INT:16132`)。
   生成器只认前者,后者取第一条 ⇒ 丢掉 INT。
   🔑 **护栏的作用域就是那个 bug**:`armor_multi` 断言只查 `ClassID==4 且 SubclassID∈1..4`,
   **盾是 subclass 6**,一直落在「武器豁免」桶里。规则没写错,**够不着的地方才是问题**
   (canon「guard 的覆盖范围 ≠ 规则的适用范围」的活标本)。
   修 = **折叠**(每个码展开成 `{S,A,I}` 求并集再映射回),护栏改成「任何多条目必须能折成
   已知码」——**不再需要作用域**。实测 315 件里 25 件多条目:16 件同属性重复(取第一个一直是对的)、
   9 件不同属性(6 盾 `STR`→`SI`;3 件武器已经是 `AI`,之前碰巧蒙对)。
2. 🔴 **`gen_loot.py` 的 `main()` 每个 guard 都靠 `return 1` 报错,而结尾是裸 `main()`**
   ⇒ **所有护栏一直以 exit 0 结束**:打印 ERROR、拒绝写文件、然后告诉调用方一切正常。
   已改 `sys.exit(main())`。**发现它纯属做 A/B 时管道到 `tail` 看错了 `$?`** —— 两个坑叠在一起。

**还欠着的**:
- 🔴 **「排序口径要不要改成装等档优先」这个问题的前提不成立**(2026-08-14 OMEN 查证):
  ① **它现在就已经是装等档优先** —— `table.sort` 的**第一个**比较键就是 `topItemLevel`,
  属性分数排在它后面(实测恶魔猎手浩劫主手 18 行,前两行正是烈毒之渊 #8/#7 的 344 件);
  ② **再往下分不出更细的档,因为 `Data/Loot.lua` 里根本没有装等字段** ——
  344 是从 `(instanceID=1320, boss #7/#8)` **推**的,不是存的。全季 78 件武器/副手只有 8 件够 344;
  剩下 70 件里 22 件团本、56 件地牢,而**地牢掉落装等取决于钥匙层数,结构上没有单一值可填**。
  ⇒ 真正还剩的选项只有「**要不要把团本 vs 地牢也当一档**」,而那需要回 wago.tools 再挖一轮
  (`ItemContext` / 难度维度)。⚠「地牢通常更低」是游戏常识,**不是从数据查出来的**,别当事实收。
- **截断没有想象中严重**(同日实测,可复算):最长的是 DUAL_1H 那几个专精(双持 DK / 盗贼 /
  增强萨 / 浩劫DH)**主手 18 / 副手 16**;**绝大多数专精只有 5~10 件,压根不截断**。
  面板行数上限 = `floor((侧栏高度 - HEADER_H - 8) / ROW_HEIGHT)`,`MAX_ROWS = 12` 只是 fallback。
  ⇒ 最坏情况只截掉 ~6 行,且只在 6 个专精上发生。
- **类型角标列没做** —— 切换让主手在每个模式内同质了,但**萨满的副手是盾+副手物品混排**,
  这一列重新有意义。
- 真机验收:2026-08-14 Jerry 在 OMEN 上验过**双手/单手 + 副手切换**、**副手三种空状态文案**,
  均 OK;**其余验收点仍未测**(纯双手专精无副手行 / 猎人只出远程 / 21 个切换专精的名单 /
  神圣骑 6 面盾 / 恢复萨·元素萨单手 13 件 / 面板高度封顶 + 截断标题的 `N/M`)。

**那 21 个带「双手 | 单手」切换的专精**(从 `WEAPON_SHAPE` 实际数出来的,验收时照这个核):
法师 3(62/63/64)· 德鲁伊平衡+恢复(102/105)· 冰DK(251)· 生存猎(255)· 牧师 3(256/257/258)·
元素萨(262)· 恢复萨(264)· 术士 3(265/266/267)· 酒仙(268)· 踏风(269)· **织雾(270)** ·
唤魔师 3(1467/1468/1473)。⚠ **织雾僧容易被漏掉** —— 交接口述清单里就漏过一次,数出来只有 20 个。

## 饰品排序(1.12.0)—— 唯一一个不按副属性排的部位

**为什么非要外部数据**:42 件饰品里 **33 件零副属性** ⇒ `ns.StatFit` 对它们全返回 nil,
排其他所有部位的那套逻辑**结构上无从下手**。价值在 on-item 效果(42/42 都有),
而效果正是 sim 定价、副属性排序永远看不见的东西。

**换赛季怎么重跑**(跟 `gen_loot.py` 一个节奏,手动):
```
python tools/gen_trinkets.py --dry-run    # 先看覆盖率,不写文件
python tools/gen_trinkets.py              # 重写 Data/Trinkets.lua
lua tools/test_gearrank.lua               # 必须 0 failures
```

**生成器里那三条断言别删**,每条对应一个实测过的坑:
1. **spec slug 从 bloodmallet 自己的 `classes_specs.js` 取,不手打** —— slug 写错和该专精真没数据
   **返回一模一样的 `{"status":"error"}`**,手打清单会产出读起来完全像真缺口的假阴性。
2. **所有 payload 的 `simc_settings.tier` 必须一致** —— 🔴 端点会**不吭声地端出上赛季数据**
   (实测德鲁伊平衡的 `phials` 是 `tier=MID1`),HTTP 200、格式全对、没有任何字段说它过期。
   漏了这条就会静默发布上赛季的排名。
3. **specID 必须跟 `ns.SpecGear` 逐个对上** —— 两份手写的专精清单必然漂。

**三个设计决定**(Jerry 2026-08-14 拍板,理由与实测量在
[`TRINKET_DATA_RESEARCH_2026-08-14.md`](TRINKET_DATA_RESEARCH_2026-08-14.md)):
- **钉死单目标**(`castingpatchwerk`)。⚠ `castingpatchwerk5` **不是第三个选项**,它是单目标那批的
  **严格子集**(15/40),拿它当 AOE 口径会同时丢覆盖率和两个专精。
- **40 个专精全给按钮**;没数据的**照常列出该部位的饰品**(每行标 unranked)+ 上方一行说明。
  ⚠ 不列 = 「装备从列表里消失读起来像数据不全」,跟 azerite 那 14 件保留并标记同一条理由。
- **sim 名次压过 344 装等档**。sim 已经拿每件在**它自己的装等上限**上比过,再套 344 提升
  = **把那十点装等算两遍**。A/B 实测:去掉那个分支,270173 当场跳到第一。

⚠ **别拿某个装等去横向比** —— 每件饰品只在**它自己那条轨道**上有数据点(14 件只有 298),
没有任何一个装等能比全部。用 `sorted_data_keys`(= 每件在自己上限上比),它已经解决了这个问题。

⚠ **同一个 itemID 会出现多行**(`Ruby Whelp Shell` 四种配置各一行)—— 生成器取名次最好那个变体。

### 🔴 三切片纹理:texcoord 必须**抄暴雪的模板**,别按图片尺寸推(2026-08-14,烧了四轮)

给部位标签加暴雪按钮面时,我按「128px 宽的图,左右各切一小条」推出
`0/0.09` · `0.09/0.91` · `0.91/1.0`。**错的** —— `UI-Panel-Button-Up` 的按钮 art
**只占左边约 62%**,右边是空的。`UIPanelButtonTemplate` 的真值:

| 块 | texcoord(横) | 原生宽 |
|---|---|---|
| 左帽 | `0 → 0.09375` | 12 |
| 中段 | `0.09375 → 0.53125` | 拉伸 |
| 右帽 | `0.53125 → 0.62109375` | 12 |

竖直一律 `0 → 0.6875`。

🔑 **这条最值钱的是它的症状,不是那几个数**:**矩形完美对称,而画面偏。**
我实测过 —— 文字格 `0→48` 居中、按钮面 `2.17→45.83` 中心 24.0、字左右各空 11.0px,
**几何严格对称**;而 Jerry 眼里字一直偏右。因为右帽采到的是**空白**,真正的右侧立体边缘
被塞在拉伸的"中段"里、出现在偏左的位置 ⇒ 可见按钮左移 ⇒ 字看着右移。

⇒ **判据:量出来对称、看上去偏 ⇒ 别再调几何,去查矩形里画的是什么。**
我在横轴上白调了三轮(改对齐、改列宽、改成从中心往外长),因为我一直假设
「看着偏 = 位置偏」。**位置和图像是两回事,而只有后者用眼睛才看得见。**

⚠ 连带教训:`ipairs({frame:GetRegions()})` **中间遇到 nil 会当场停**,一条都不打 ——
我头两条诊断命令因此完全静默,而「没输出」被读成了「结构跟我想的不一样」。
量 region 用定长 `for i=1,N`。**又是探针自己报的"没有"。**

### 🔴 首日就撞的坑:`unranked` 一个字段背着三件事(2026-08-14,Jerry 真机抓到)

`entryRow.unranked` 当时同时驱动 **① 排序 ② 属性列打 `-` ③ tooltip 给不给升级 bonusID**。
在 armor 上这三件事**恰好永远重合**(那 14 件 ilvl 59 azerite 既没副属性、也不在当前轨道),
所以从来没人发现它是三个意思。

我把饰品行的 `unranked` 改成「sim 没覆盖」⇒ **神牧(无数据)每一行都 unranked**
⇒ 每行属性列是 `-`、**每行 tooltip 掉回原始装等**(回归饰品会差好几百级)。
`GearRank` 和 `GearPanel` **各自单独看都完全正确**,坏在接缝上。

**修法 = 把三个意思拆成三个字段,别让它们互相推断**:
- `unranked` —— 排不排得了序(饰品 = sim 没覆盖;其余 = 没副属性)。只管排序。
- `statless` —— `score == nil`。只管属性列那个 `-`。
- `offTrack` —— 不在当前升级轨道上。只管 tooltip 的 bonusID。
  **饰品恒为 false** ——**池子里每件饰品都是本赛季掉落**,回归的那几件正因为静态装等没意义
  才必须靠 bonusID 拉。

⛔ **`tools/test_gearrank.lua` 覆盖不到 `GearPanel`**(要真 frame)⇒ **字段有测试,面板怎么用它没有** ——
而这个 bug 恰恰住在那段接缝上。改这三个字段的**消费方**时,自动化测试不会替你兜底,只能真机点。
🔑 判据:**改一个字段的含义之前,先 grep 它的全部读取点** —— 我第一次只 grep 了 `GearRank`。

## 🚧 施工中:大秘境掉落查询侧栏(数据层已落地)

打开史诗钥石地下城界面时挂两级侧栏:8 张大秘境卡片 → 该本 + 该专精可拾取的装备列表。
**设计稿 = [`MPLUS_LOOT_PANEL_DESIGN_2026-08-22.md`](MPLUS_LOOT_PANEL_DESIGN_2026-08-22.md)**,
开工前读它,里面有已经查实的八本简称表 / ID 映射 / 311 的 bonusID / 施工顺序。

两条**别再重新调研**的结论(证据都在设计稿里):
- 🔴 **「已拥有-勇士/英雄」做不成** —— 全量扫过 612 个 API 契约,没有按装等档记录的收集系统;
  而 `appearanceModID` 在 M+ 装备上只有一个值(团本才有四个)。落地口径改成**只扫实物**。
- 🔴 **M+ 掉落上限是 311 不是 334** —— 334 是团本档。现有 `GearPanel` 用 334/344 没错,
  因为它排的是全部来源;这个新面板只排 M+,照抄会让玩家系统性高估。

**2026-08-22 数据层(施工顺序第 1 步)已落地**,进度以 `git log` 为准,这里只留不会漂的:
- `Data/Loot.lua` 多了 `ns.ChallengeMap`(journalInstanceID -> challengeMapID,**生成的**)。
  卡片简称是这个功能里**唯一手写**的东西,住 `Locales.lua`:`ns.DungeonShort`(中性缩写)
  + `cn` 块的 `dungeonShort` 覆盖 —— **不进 `Data/Loot.lua`**,那份是 ids-only / ASCII-only。
  别把简称抄进三个语言块:缩写不是翻译,复制三份就是三份会各自漂的同一个事实。
- `gen_loot.py` 加了 `--build`(钉客户端 build)。**改这个脚本本身时先钉住 build 跑一次** ——
  不钉,你的改动会跟暴雪同期发的数据混在同一份 diff 里,分不开。
  (实测:69299 → 69404 会顺带改 2 件团本装备的副属性 + 2 把武器的 equipLoc。)
- `tools/test_gearrank.lua` 多了一节 guard,`tools/fixture_dungeonnames.lua` 是它的夹具
  (**UTF-8**,本仓唯一一个;装客户端原文的副本名,好让中文简称跟**客户端说的**比,
  而不是跟这里再打一遍的名字比)。A/B 验过 7 种真实坏法,每种精确红。

### ✅ 已实测:`12843` 真给 311(2026-08-22 HOME 游戏内量到)

**三行实测值**(物品 `250243` =「魔力之心的联结烈焰」,Jerry 在 HOME 上跑下面那条 `/run`):

| bonusID | ilvl | quality | 身份 |
|---|---|---|---|
| `12854` | **334** | 4 | 对照组 —— Myth 6/6,跟离线推导一致 |
| `13848` | **344** | 4 | 对照组 —— Myth 9/6,跟离线推导一致 |
| **`12843`** | **311** | 4 | **被测项 —— `GEAR_HERO_BONUS_ID`,坐实 311** |

⚠ **第一次跑三行全 `nil`,第二次全出** —— 那就是下面写的物品缓存没到,**不是命令写错**
(两种原因症状一模一样,所以对照组不能省;下次谁再量,照样先看对照组那两行对不对)。

🔴 **轨道名叫不叫 "Hero" 仍未验**(下面那条「顺带看一眼 tooltip」还欠着)——
这一枪只答了装等,没答名字。**别把它顺手记成已验。**

> **2026-08-24 追加(仍未闭环,别当已验)**:让 Jerry 跑那条只打物品链接的命令去悬停看 tooltip,
> 他回报「是 nil」—— **这句有两种读法,当时他要上班,没来得及澄清**:
> ① **打印结果是 nil** = 物品缓存没到(跟第一次量 ilvl 时三行全 nil 一模一样),再跑一次就有;
> ② **tooltip 里确实没有轨道名那一行** = 结论成立,DB2 没这个字段,"Hero" 纯属按位置推的。
> **两种读法的结论完全相反,所以这条仍然算未验。**
> 下次谁量先把两者分开:链接**打不出来**就是 ①(重跑);打得出来了再去看 tooltip,才回答得了 ②。

<details><summary>当初那条量法(留着复用:换赛季 / 换 bonusID 照抄)</summary>

游戏里贴这一条。**前两个是已经量过的对照组** —— 它俩对了才说明命令本身没问题;
第一次可能全 `nil`,那是物品缓存没到,**再跑一次**就有(这两种原因症状一模一样,
所以对照组不能省)。

```
/run local id=250243 local E=string.rep(":",11) for _,b in ipairs({12854,13848,12843}) do local n,_,q,i=C_Item.GetItemInfo("item:"..id..E..":1:"..b) print(b,n,"ilvl",i,"quality",q) end
```

期望 `12854 -> 334` · `13848 -> 344` · **`12843 -> 311`** —— 2026-08-22 实测三个全中(见上表)。
顺带看一眼 tooltip 里轨道叫不叫 "Hero" —— DB2 里没有轨道名这个字段,那是按位置推的。
**⚠ 这一问至今没人回报,仍然未验。**
⚠ 链接的冒号数用 `string.rep` **声明**而不是数出来的,跟 `GearPanel.LINK_EMPTY_FIELDS`
同一个写法;多一个冒号会让每个字段错位一格,而 `GetItemInfo` 只回 `nil` 不给任何提示。

</details>

- ✅ **`GEAR_HERO_BONUS_ID = 12843` = 311:2026-08-22 HOME 游戏内实测坐实**(三行值见上表)。
  在此之前它是「三条离线推导互相对上、但没量过」——**那句现在作废**,但它当初的写法是对的:
  **别把「三条推导对上」读成「已实测」**,这条心法留着。
  🔴 **同一枪本来还想顺带答「轨道是不是真叫 Hero」,那一问没人回报,至今未验。**
  (另一个未知「分母 3/6 还是 3/8」不靠这一枪 —— 已由 `ItemExtendedCostID` 的形状定案成 3/6,
  正文在 `Config.lua` 的 `GEAR_HERO_BONUS_ID` 注释块里。)
  ⚠ `Config.lua` 那段注释仍写着「DERIVED …, no measurement」并让人量完就删它 ——
  **它比本节陈**,以本节为准;那段该由改 `Config.lua` 的那条线顺手收掉。
- ✅ **下拉栏定案:新 API**(`WowStyle1DropdownTemplate` + `SetupMenu` + `CreateRadio`),
  老 `UIDropDownMenu_*` 是 deprecated-but-alive(照老写法写**不会报错**,所以没有信号会拦你)。
  **最省事的参照是本机自家插件**:`DodoGuanzhu/Options.lua` 的 513 / 550 行就是整套写法。
  取专精名走 `C_SpecializationInfo.GetSpecializationInfoByID`(本插件 `TargetInfo.lua:102-105`
  已有带回落的写法);`GetSpecializationInfoForSpecID` **不存在**。

## 版本历史 —— ⚠ **「当前是哪版」别在这儿读**

这份 doc 记的是**每版做了什么**(内容不变),不是**现在发到哪版**(会烂,而且烂过:
本节开头长期停在 1.9.0,那时 1.10.0 已经上了 CurseForge)。
**现版本查这三处**:`gh run list --repo Baeseata/Wow-Addons`(最可靠 —— 运行记录不可编辑)
· `git ls-remote --tags origin 'DodoInspect-*'` · TOC 的 `## Version`。
⚠ **不是 `PUBLISHING.md`,那个文件不存在**(2026-08-14 实查)。

### 🔴 TOC 里那个号会撒谎 —— 「树里这份」和「CF 上那份」可以同名不同码

**这不是假设,2026-08-22 就是这个状态**(那天 tag 之后又落了改 runtime lua 的 commit)。
判据别记数字,记这条命令 —— 在 repo 根跑:

```
V=$(grep -i '^## Version:' DodoInspect/DodoInspect.toc | cut -d: -f2- | tr -d ' \r')
git log --oneline "DodoInspect-v$V"..HEAD -- DodoInspect/
git diff --stat "DodoInspect-v$V"..HEAD -- DodoInspect/
```

**空 = 干净**;列出来的 commit 里只要有一个动了**会被打进包的文件**,这个号就在撒谎。
哪些会被打进包 = 看 `.github/workflows/curseforge-release.yml` 的 Build 步骤那条 `find`
(`*.lua` `*.toc` `README.md` `LICENSE` + 媒体;**排除** `tools/` `test/` `CLAUDE.md`)——
所以「只改了 `tools/` 和这份 doc」不算撒谎,**改了任何一个 `.lua` 就算**。

**为什么要紧**:这个号是**给人看的** —— `Options.lua` 的 `GetVersion()` 用
`C_AddOns.GetAddOnMetadata` 把 TOC 的 `## Version` 画在 ESC 设置面板顶部。
撒谎的版本号比没有版本号更坏:没有的时候你知道自己不知道,撒谎的时候你会拿它当证据去排错。
⇒ **有人报「x.y.z 有问题」,第一句先问他跑的是 CF 装的还是从这棵树拷的**,
否则你会拿一份代码去解释另一份代码的症状。

**下次发版:先 bump TOC 的 `## Version`,再打 tag。** workflow 会校验
「tag 的 `-vX.Y.Z` == TOC Version」并在不一致时当场失败,**但它不校验「tag 之后有没有新 commit」**
—— 那个洞只能靠上面那条命令。⚠ 想在开发中途把号停在一个非发布值(`1.14.0-dev` 之类)也行,
但 **CF 收不收这种串没验过**,真要用先 `workflow_dispatch` 跑一次 dry-run。

## 1.13.1:S2 开季后的攻略数据复核(2026-08-22)

改了 **3 个专精**,其余 37 个**核过没变**。⚠ 三条的性质不一样,别当成一批:

| spec | 改动 | 性质 |
|---|---|---|
| 252 邪DK | `M>C>H>V` → **`C>M>H>V`** | 作者 08-17 真改了(正文写明 "Crit tends to be slightly better than Mastery") |
| 261 敏锐 | `M>H>C>V` → **`M>H>V>C`**;两条急速目标(1100/650-700)合成一个 `~700` | 作者 08-19 真改了 |
| 1468 恩护 | **删掉 builds,压成 1×1 `M>C>H>V`** + 标 provisional | **我们当初读错了**,不是数据更新 |

🔴 **1468 那条值得记**:原来按 Flameshaper(37) / Chronowarden(38) 分了两个英雄树 ——
而源页面上那两个并排 box 的标题是 **"Preservation Raid Stat Priority"** 和
**"Preservation Mythic+ Stat Priority"**,是**内容分格**。**把「两个并排的框」默认读成了「两个英雄树」。**
判据(一次 grep 就能验):Wowhead 分英雄树时会在列表前放 `[symbol=wow-hero-talent-<树名>]`,
**恩护那页 `wow-hero-talent` 零命中**。M+ 取治疗向(= raid 序)是照本文既定口径
「坦克默认生存,治疗默认治疗量」,而两个源在 M+ 上确实分歧 ⇒ 挂 `provisional`。

### 🔑 换季 / 调优后怎么复核(**下次照这个走,别再手点 40 页**)

⚠ **本文别处那句「Wowhead 攻略页 WebFetch 抓不到,只回导航」对 `curl` 不成立** ——
正文是 BBCode,完整躺在 HTML 里,`dateModified` 也在。40 页一次扫完:

```bash
curl -s -A "Mozilla/5.0" "https://www.wowhead.com/guide/classes/<职业>/<专精>/stat-priority-pve-<dps|tank|healer>"
```
- **更新时间** = `"dateModified":"…"`。⚠ **34/37 页会挤在同一分钟**(Wowhead 批量重发布,
  2026-08-12 那次就是)—— **同一分钟 = 一次机器动作,不是 34 个作者各自改了**,
  真正动过的是那几个时间戳落单的。Icy Veins 同理(13/13 同一秒),但它的 **changelog 逐页不同**,
  可以拿来验这个量还有没有分辨力。
- **顺序** = 抓 `[ol]…[/ol]`。⚠ **两种写法都要认**:`[li][b]Haste[/b] (~700)` **和**
  裸的 `[li]Strength[/li]` —— 只认前者会静默漏掉一批(武器战就是,第一版 0 命中)。
- **分不分英雄树** = 列表前 320 字符内有没有 `wow-hero-talent-<树名>`;**分不分内容** = `[tab name="…"]`。
  ⚠ 摆成 2×2 不代表内容不同 —— 敏锐那页 2 树 × 2 tab **四格完全一样**,所以仍是 1×1。
- **Method.gg 的正文是 JS 渲染的,curl 只拿得到日期**(`Last Updated: 17th Aug, 2026`,
  逐页不同 = 有分辨力),正文要走 WebFetch。

**时机比方法重要**:攻略作者**滞后于暴雪调优**。2026-08-18 第一轮调优落地后,
Icy Veins **13/13 零更新**、Wowhead **34/37 零更新** ⇒ 开季当天去抓等于抓开季前的数据。
⇒ **等调优落地 + 作者跟进(约 3~7 天)再抓**,别在调优当周抓。

### 🔴 顺带补的 guard:那份数据文件此前是**完全裸奔**的

A/B 实测:在 252 里种一个 `"critt"`,`test_statpriority.lua` + `test_gearrank.lua`
**198 条断言全绿** —— 因为前者的断言全打在它自己注入的 fake spec(9901+)上,
**加载了 `Data/StatPriority.lua` 却一条都没断言它**。
现补一节形状 guard(51 → **527 checks**):stat key 合法 · 每条 order 恰好四个副属性各一次 ·
`current` 显式 · 有 source/date · flat 与 builds 二选一 · goals 的 stat key 合法。
**只查形状不查具体顺序** —— 换季刷新数据不该让它变红。
末尾两条**反向断言**(`seenSpecs >= 40` / `seenOrders >= 45`)防的是「循环一个都没匹配到、
干干净净报了个 pass」那种真空绿。
A/B 三种**真实**手改失败模式各精确红一条:打错 stat key(`data[252].raid: unknown stat key "critt"`)·
重排时漏一个(`got 3, expected 4`)· 忘了 `current=true`。

## 1.13.0:属性优先级可自定义(**未上过真机**)

侧栏顶部那行右侧的齿轮 → 开编辑窗:4 项绿字属性排序(`>` / `=`)、团/米各一条、
每项可设上限和/或下限(**纯数字,不带单位**)、一键恢复默认。

**存储 = `DodoInspectDB.statPriorityCustom`**,键是 **specID × 英雄树**(无树用 `0`):
```lua
{ version = 1, specs = { [specID] = { [treeKey] = {
    raid = <order>, mythic = <order>,
    goals = { raid = { [stat] = { unit = "percent"|"rating", min = n, max = n } },
              mythic = { ... } } } } } }
```
**没动过的专精一个字节都不存** —— 这就是「玩家设置扛得住插件更新」和「没配过的专精自动吃新数据」
同时成立的原因:**缺席 = 读默认**。「恢复默认」是**删 key**,不是存一份当时的默认快照。

🔑 **按 spec × 树存,把「检视别人」这件事化简掉了**:不需要「这是不是我」这个判断,
只要拿**被查看单位**的 (spec, tree) 去查表,查到就用 + 行首挂金色标记,查不到走默认。
同专精同树用你的、同专精不同树走默认 —— 结构上不可能出现「拿你 San'layn 的顺序套在
Deathbringer 身上」。⚠ 编辑入口只给角色面板(`panel.dodoPriorityConfigurable`),
检视面板那份**只显示不可点**:那上面是别人的角色。

⚠ **一个主动决定:自定义 override 掉 `current ~= true` 那道闸。** 那道闸挡的是「**我们**的数据过期了
还在误导人」,玩家自己填的东西不在此列;副作用是赛季初数据没跟上时玩家能自己先填。
`ns.StatPrioritySpecCurrent` 也跟着认自定义 —— 两个面板都在 Resolve **之前**调它,
不改那里的话自定义会被这道前置 gate 直接挡掉(测试里有单独一条覆盖)。

### 🔴 百分比↔评级换算:**做过,同日拿掉了**(2026-08-15 Jerry 拍板,分两步)
① 看到换算那一列:「**感觉可能不太准,让玩家自己研究去,我们不给计算**」⇒ 换算删掉,
单位降级成一个「标签」按钮。② 看到那排按钮:「**不想要评级的那些按钮**」⇒ **单位概念整个去掉**。
**终态:一行 = 一个属性 + 两个纯数字框。** 那个数是百分比还是评级,是玩家自己的事。

⚠ **连带的一条,别当 bug 修回去**:seed 攻略目标时**跳过 `unit == "percent"` 的那些**
(暗牧的「急速 23%」这类)。没有单位栏时,把 `23` 填进一个同列都是 `1600` 的框
**不是「信息少了」,是「信息错了」** —— 空框让玩家自己填才是诚实的。带评级的照常 seed。

⚠ **算式本身没错,错的是「声称」太宽** —— 这条区分值得留着,不然下次会当成 bug 重修一遍:
- 公式(扒的 `Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua`,**不是 wiki**):
  `GetCombatRatingBonus(cr) / GetCombatRating(cr)` = 每点评级买到的百分比,**不硬编码任何表**,
  自动跟等级和赛季走。**精通要额外乘 `GetMasteryEffect()` 的第二个返回值**(专精系数)——
  漏了它数值「看着像那么回事」,只是**正好一半**。
- 它回答的是「**这些评级点买到多少百分比**」,**不是角色面板上那个数**(那个还含基础值和光环,
  急速更是乘算叠加)。玩家读到「20% = 5800」,堆到 5800 之后面板显示 23%。
- ⇒ **拿掉的是那个会撒谎的换算,不是那个公式。** 想做回来,要先决定做的是哪个口径。

**函数删干净了,没留在代码里** —— `ns.StatPerPoint` / `ns.ConvertStatTarget` 连同它们的
9 条测试一起删。理由:**一个没人调的函数配一套绿测试,比一段注释更坏**(测试会一直替一个
不存在的功能背书)。知识留在这一节,`tools/test_statpriority.lua` 里另配了两条断言
**断言这两个名字不存在** —— 谁把死代码加回来而不接 UI,当场红。

### 🔴 首次真机就撞的:**给 FontString 设了宽度 = 它会自动换行**
换算那格同时锚了 `LEFT` 和 `RIGHT` ⇒ 有了宽度 ⇒ **默认 wrap**。一个属性同时有下限和上限时,
`~17.4% - ~26.1%` 超过格宽就折成两行,而**折下去那行正好画在下一行的位置上** ——
屏幕上是两行数字叠在一起。只填了一个界的那行(截图里的全能)不重叠,这就是判据。
⇒ **凡是给 FontString 设了宽度(SetWidth,或同时设左右两个锚点),
`SetWordWrap(false)` + `SetMaxLines(1)` 必须一起配。** 裁掉比折行好:
这里同样的数字在输入框里还有一份,而折行会破坏它下面所有东西的布局。
顺带把窗宽按**英文最坏情况**重算(`Critical Strike` + 两个界的换算),不是按先看到的中文版。

### 🔑 hover 提示对「发现功能」是无效的(Jerry 真机反馈,当场推翻)
第一版只做了「鼠标移上去整行泛青 + tooltip 写着点击自定义」。他的原话是
**「需要给顶部加一个自定义 config 的按钮,否则玩家不知道有这个功能」**——
**hover 只有在光标已经在上面时才说话,而不知道这行能点的人永远不会把光标放上去。**
现在 header 右侧有个常驻齿轮(`Interface\Buttons\UI-OptionsButton` —— **12.1 实测渲染正常**,
`h.config`,只在 `configurable` 的面板上建),两行文字同时限宽给它让位。
⇒ 跟部位标签当初从「能点」升级到「看得出能点」是同一条教训,这次又栽了一遍。
- ⚠ **尺寸调了三轮**:固定 14「太小」→ `fontSize * 1.7`(默认字号下 20)「又太大」→
  现在 **`fontSize * 1.35`,夹在 15..22**(`ConfigButtonSize`)。**保持从字号推、别写死 px**:
  写死的话字号滑条一拉大它就又缩成一个点。要再调只动那个系数和上下夹值。
- 锚点用 **`RIGHT` 居中**不用 `TOPRIGHT`:按钮比它旁边那行字高,居中让溢出**上下均摊**进
  padding,顶对齐则会把溢出全压到下面第一行装备上。

### 顺手修的两个,都不在新功能里
1. 🔴 **收起侧栏后换一件装备,属性优先级行会弹回来**,悬在那个只有按钮高的 stub 上。
   1.12.0 就有。`ApplyCollapsed` 会 `dodoPri:Hide()`,但它**只在点收起那一下跑**;
   之后任何 `UpdateSidePanel` 都会走到 `UpdateStatPriorityHeader`,而那个函数结尾是 `h:Show()`。
   跟 1.12.0 修过的 `row:Show()` 无条件那条**是同一个病,当时只修了行没修 header**。
2. **候选面板的「暂定数据」标记**在玩家自定义后要抑制掉:那句话描述的是**攻略数据**的状态,
   而面板已经按**玩家的**顺序排了 —— 留着就是把我们的免责声明贴在他的答案上。

### 测试:`tools/test_statpriority.lua`(新,可单独跑)
`lua tools/test_statpriority.lua`。覆盖排序形状 / flatten↔build 往返 / seeding 的五种 goal 形状 /
存储往返 / 深拷贝 / 换算数学 / **哪一份答案赢**(自定义 vs 默认 vs 英雄树隔离 vs 过期数据)。
⚠ **fake specID(9901+)自己造,不绑活数据** —— 攻略 goals 每赛季会重写,绑上去的测试会在
数据更新那天变红,而它报的是错的东西。

**A/B 跑过 7 个探针,每个都精确变红**(脚本形状:备份 → 种 → 跑 → 还原 → **回读核对**):
精通系数漏乘 → 只红换算那 1 条;树 key 塌成一桶 → 只红隔离那 2 条;浅拷贝 → 只红 order 那 2 条
(goals 那条**没红**,因为它仍是深拷贝 = 指得准);自定义整个不接 → 红一片;
**自定义被 current 闸挡住 → 精确红「stale spec」那 1 条**;seeding 让团/米共享一张表 → 只红 M+ 那 2 条。
- 🔑 **第 7 个探针值得单独说**:测试里有一条 `load: the addon files create no globals`。
  它抓的是 **`local Refresh` 这个前向声明被删掉**的情况 —— 那时 `function Refresh()`
  会**静默建一个全局**,而 `StoreOrder` 里引用的那个 local 永远是 nil ⇒
  **点一下上移箭头才炸**,离线测试原本一条都够不着。A/B 实测精确报 `found: Refresh`。

### ⚠ 真机验收进度
- ✅ **已看过**(2026-08-15 HOME,两轮截图):编辑窗、四行排序、四行目标、输入框、
  齿轮图标渲染都正常(那条纹理在 12.1 还在)。
- 🔴 **最后一轮改动没上过屏**:单位按钮拿掉 · 窗宽 320→**290** · 齿轮改 1.35x ·
  **补上了列头**(`Min`/`Max` —— 之前那两个 FontString 建了却从没 `SetText`,
  所以目标区上方一直是**空白一条**,截图里看得到)。
  重点看:右边**不该留空**(少了一列)· 列头**对得上两个框** ·
  底下两个按钮**不该重叠**(reset 110 + copy 140 + padding = 264,窗宽 290)。
- **剩下没验的交互**:排序箭头 / `>`↔`=` 切换 / 输入框两条提交路径(Enter、点别处失焦)/
  团-米切换 / 恢复默认 / 复制到其它英雄天赋。
- **`C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, nil)`** 只查过 API 文档(`MayReturnNothing`,
  `AllowedWhenUntainted`),**没在游戏里调过**。它返回 nil 或只有一棵树时「复制」按钮整个不显示 ——
  验的时候先确认按钮**该出现的时候出现了**,别只看它没报错。
- **收起 bug 的修复**:收起侧栏 → 换一件装备 → 那行**不该**冒出来。
- **检视别人**:自定义一个你自己的专精 → 检视同专精同树的人,行首该有金色标记且**点不动**;
  检视同专精**不同树**的人,该是默认顺序、**无标记**。
- **候选面板跟着变**:改优先级后打开部位候选面板,排序应当当场不同(它吃同一个 `StatPriorityOrder`)。
- 侧栏字号滑条拉到两端,齿轮该跟着变大变小,且**不压到第一行装备上**。

### ⚠ 一条已知边界,**故意没修**
`InspectPanel` 在 `INSPECT_READY` 之前把 `heroSub` 传成 nil(它只在 GUID 对上之后才信任树,
见 1.9.0 的防串线),而 `TreeKey(nil)` 落在 `0` 桶里。⇒ 如果你**为「无英雄树」配过**某专精
(只有你自己当时没解锁英雄树才会产生这种记录),检视同专精玩家时,**树 ready 之前那一瞬**
会闪一下你那份 `[0]` 设置,ready 后自己切回正确的树。
判断:触发面很窄、带金色标记(不会被读成攻略数据)、且**下一帧自愈**;
而几种修法都要引入「树未知」和「确实没有树」的新区分,那个概念比这个闪烁贵。
**这是取舍不是遗漏** —— 真机上要是发现它比预计显眼,再回来处理。

## 1.12.0:饰品进候选面板 + 侧栏收起 + 部位做成真按钮

**饰品**(技术内容全在上面「饰品排序」那节):
- 饰品从 `UNRANKED_SLOTS` 放出来 —— 那张表**现在空了**,所有部位都有按钮。排序来自
  bloodmallet.com 的 SimulationCraft 结果(新增 `Data/Trinkets.lua` + `tools/gen_trinkets.py`)。
- **覆盖不全是这个功能的形状,不是 bug**:数据源只覆盖一部分专精。覆盖到的列表基本是满的
  (只漏 1~2 件);**没覆盖的专精什么都不列,只出一行「本专精暂无模拟数据」**。
  ⚠ **治疗一个都没有。** ⚠ 第一版是「照常列出 + 每行标 unranked」,真机上**照样读成一个排名**
  (一堆物品挂在这个面板的标题下,那就是排名的样子),Jerry 当场推翻 —— 这里没有次优顺序可退。
- Options 那条开关的说明改了 —— 原文写着「trinket procs are not scored」,**对饰品行已经不成立**,
  顺带加了 bloodmallet 署名(它的许可要求)。

**侧栏收起 / 展开**(`SidePanel.lua`):左上角 `UIPanelButtonTemplate` 按钮,状态存
`DodoInspectDB.sidePanelCollapsed`,跨登录保持。三个要点:
- 收起时**下锚点要摘掉**,否则只改宽度会留一条跟角色框等高的窄条。
- **候选面板不是侧栏的子帧**,收缩带不走它 ⇒ 显式 `CloseGearPanel()`。
- `UpdateSidePanel` 里那行 `row:Show()` 是**无条件**的 ⇒ 收起后换件装备行就全弹回来了。
  已改 `SetShown(not collapsed)`。
- 属性优先级行靠 `panel.dodoPriorityIndent` 给按钮让位(检视面板不设 ⇒ 宽度不变)。

**部位标签做成暴雪按钮**:旋钮全在 `GearPanel.lua` 顶上 ——
`ns.SLOT_GAP_FACTOR`(列间距) · `ns.SLOT_FACE_PAD`(列给面留的余量) ·
`FACE_TEXT_PAD`(面比文字宽多少) · `CAP_W`(**别动,跟 texcoord 绑死**) ·
`SidePanel.COLLAPSE_BTN`。⚠ 三切片 texcoord 的坑见上面那节,**烧了四轮**。

## 历史:1.11.0:武器主手 / 副手进候选面板
内容全在上面「2026-08-14 OMEN 第三轮:武器两行」那节,这里不重复。三条:
- 武器主手/副手从 `UNRANKED_SLOTS` 放出来,**两行按专精真实配装形态耦合**排序
  (CAN 从 `SkillLine` 推导、SHOULD 手写 `WEAPON_SHAPE`);21 个模糊专精出「双手 | 单手」切换,
  切一下两行一起变 ⇒ 结构上构造不出「法杖 + 圣物」这种不可能组合。
- 修:**所有盾被标成力量**,智力职业副手一件看不到(神圣骑空)。多主属性有两种编码方式,
  生成器只认单条混合码,两条分写的取第一条就把 INT 丢了。
- 修:`gen_loot.py` 的护栏全部以 exit 0 结束(裸 `main()`)——开发工具,玩家侧无影响。

## 历史:1.10.0(tag `DodoInspect-v1.10.0`):掉落来源 tooltip + 部位候选面板首发
内容全在上面那几节(掉落来源 / 部位候选面板 / bonusID tooltip / 面板瘦身 + 权重曲线),
这里不重复。

## 历史:1.9.0(tag `DodoInspect-v1.9.0`)
1.8.1 → **1.9.0**:属性优先级改为**逐专精放行 + hero × content 矩阵**,不再等 40/40 一起开。
- 当前 12.1 已覆盖 **40/40**:26 个采用已基本收敛的矩阵,14 个按 Jerry 的产品口径采用
  最新/最细来源的 `provisional=true` 最佳可用基线。完整格子和来源见
  [`STAT_PRIORITY_RELEASE_2026-08-13.md`](STAT_PRIORITY_RELEASE_2026-08-13.md)。不回退 2026-06 Season 1 数据。
- 数据 entry 必须显式 `current=true` 才能 Resolve;全局只留
  `Config.STAT_PRIORITY_FEATURE_ENABLED` 作为 renderer/Options 总开关。玩家开关继续是
  `showStatPriority`,所以已有 SavedVariable 不迁移。
- 每专精最多 hero tree × Raid/M+ 的 2×2;相同内容省略 `mythic`,相同英雄树省略 `builds`。
  build-only entry 在英雄树未知时**隐藏**,不猜默认树,避免 inspect 数据还没 ready 时短暂显示错行。
- 属性行是**静态答案**,只由 `specID × hero tree × Raid/M+` 决定。
  `goals` / `contentGoals` 只在 tooltip 显示攻略给出的粗略参考目标;不支持 cap、threshold 或 after-order。
  英雄树专属目标放 `goalBuilds[subTreeID]`,与 order 用的 `builds` 分轴;目标未知就不猜。
  当前参考目标覆盖戒律、暗牧、狂徒、敏锐、元素。目标行固定按 C/H/M/V 显示,header 不加 `*`。
  source/date 从旧全局串改成每专精元数据。
- tooltip 免责声明改为:仅供通用配装参考;装等/主属性通常优先;坦克默认生存、治疗默认治疗量;
  最终模拟自己角色。`provisional=true` 另显示橙色“当前来源存在分歧”提示。TOC 升 1.9.0。
- tooltip 属性全名和目标文案跟插件 locale,不再被客户端语言锁定;英雄树名仍由游戏 API 本地化。
- **检视英雄树归属防串线**:`configID=-1` 是所有 addon 共用的全局 inspect config;另一插件对玩家 B
  `NotifyInspect` 时,不能让当前面板玩家 A 误读 B 的英雄树。`InspectPanel` hook 每次请求先 invalidate,
  只在 `INSPECT_READY` 的可读 GUID 与当前可检视 unit GUID 一致后重新信任;读取前还要求
  `C_Traits.HasValidInspectData()`。不匹配时 1×1 专精仍可显示,build-only 专精 fail-closed 隐藏。

## 历史:1.8.1(2026-08-11 发布,tag `DodoInspect-v1.8.1`)
1.8.0 → **1.8.1**:secret-value 崩溃 hotfix(BugSack 报 `12x`)。技术细节全在上面
「第四颗雷」那节,这里只记做了什么:
- `ns.InspectSpecID` 补 `issecretvalue` guard,并成为**所有**非玩家单位 spec 查询的唯一入口
  (`TargetInfo.GetInspectSpecID` 改为委托它,顺带修掉那边第二处裸 `specID <= 0`)。
- 新增 `ns.StatPriorityActive()`,`SidePanel` / `InspectPanel` 都在**查 spec 之前** gate ——
  1.8.0 的 fail-closed 闸门在 `Resolve()` 函数体内,而实参先于调用求值,所以功能关着照样崩。
- `InspectPanel` 的 `InspectFrame.unit → "target"` fallback 加 `CanInspect("target")` 前提。
- **无功能变化**:属性优先级总闸门仍是 `false`,UI 上依旧什么都不显示。
- **2026-08-13 属性增量复核**:最初沿用“40/40 一起开”的严格门槛得出 0/40;同日 Jerry 改为
  逐专精矩阵放行后,该产品决策被上面的 1.9.0 取代。原始审计仍保留在
  [`STAT_PRIORITY_RESEARCH_2026-08-13.md`](STAT_PRIORITY_RESEARCH_2026-08-13.md),不要把旧结论当当前状态。

## 历史:1.8.0(2026-08-11 发布,tag `DodoInspect-v1.8.0`)
1.7.0 → **1.8.0**:12.1 `Curse of Ula'tek` / Season 2 兼容更新。
- **属性优先级暂时隐藏**:`Config.STAT_PRIORITY_DATA_CURRENT=false` 是总闸门;
  `Resolve` 在数据入口 fail-closed,Options 也不注册开关。旧 `showStatPriority` SavedVariable
  和 `Data/StatPriority.lua` 都保留;拿到 12.1 确切资料后更新全表 + source/date,再把闸门改回 true。
- **12.1 属性研究档案**:见 [`STAT_PRIORITY_RESEARCH_2026-08-11.md`](STAT_PRIORITY_RESEARCH_2026-08-11.md)。
  本轮未跑模拟,审计公开攻略、职业社区文档和论坛后只有 5/40 个粗粒度候选,但 **0/40**
  达到“独立社区确认 + 场景/英雄树无冲突”的重新开放标准,所以总闸门继续保持 false。
- **装等渐变**:12.1 S2 标准轨道 Adventurer 266 起、Myth 6/6=334;
  Ascendant Venomstone 上限 341,末两名史诗团本首领/Very Rare 的 Myth-9 等效上限 344。
  Blizzard 确认 S2 相对 S1 整体 +46,故三个旧锚 216/280/298 同步平移为
  **262/326/344**,保留原有白→冷色→橙→暖色→红的视觉语义。
- **元数据**:TOC Interface 加 120100、保留既有 12.0 接口号,版本升 1.8.0。

## 历史:1.7.0(2026-06-24 本机发布)
1.6.1 → **1.7.0**:新增 **PvE 属性优先级行**(角色侧栏 + 检视侧栏顶部),按**英雄天赋**(build)区分。
- **显示**:侧栏最上方一行,用和下面属性格子**同一套缩写 + 颜色**(`ns.L.stats` + `Config.STAT_COLORS`),
  `>` 分隔、`=` 表示约等价(tie group)。团本=大米合一行;不同则分两行带 `团`/`米` 标签。顶部预留区高度
  写进 `panel.dodoPriorityHeight`,行块**紧贴 header 顶对齐**(SidePanel/InspectPanel 的 LayoutRows 都改;
  无 header 时仍居中)。开关 `showStatPriority`。header 字号跟 `FS`。
- **tooltip**:全名(游戏全局 `STAT_CRITICAL_STRIKE` 等,四语免费)+ 软上限(结构化 `softcap={haste=20}` 套
  本地化模板)+ `构建: <英雄天赋名>` + 来源 + 免责声明。**无逐专精散文**,只 8 个模板串进 Locales
  (`priTitle/priRaid/priMythic/priSame/priSoftcap/priSource/priDisclaimer/priBuild`,fr/es 无重音)。
- **数据**:`Data/StatPriority.lua` 按 **specID** 索引,**40 专精全覆盖**。order = stat key 数组,子数组 =
  tie group;`mythic` 与 raid 相同则省略;`softcap` 仅在有具体数字时写。来源/日期是全局
  `ns.STAT_PRIORITY_SOURCE/_DATE`(换季只改一处)。文件**纯 ASCII**(非 ASCII 只在 Locales)。
- **build-aware(英雄天赋)**:专精条目可带 `builds = { [subTreeID] = { raid=…, mythic=…, softcap=… } }`,
  `Resolve(specID, subTreeID)` 命中 build 用其(自包含,不继承默认 mythic/softcap),否则用默认。目前 6 个:
  血DK(Deathbringer 33 / San'layn 31)、生存猎(Sentinel 42 / Pack Leader 43)、暗牧(Voidweaver 18 /
  Archon 19)、增强萨(Totemic 54 / Stormbringer 55)、噬灭DH(Annihilator 124 / Void-Scarred 126)、
  奶骑(Herald 50 / Lightsmith 49)。subTreeID 取自 wago.tools `db2/TraitSubTree`,已游戏内验证(DK+奶骑)。
- **英雄天赋 API**(都 `AllowedWhenUntainted`,非 secret):
  - 自己:`C_ClassTalents.GetActiveHeroTalentSpec()` → subTreeID;名字 `C_Traits.GetSubTreeInfo(
    C_ClassTalents.GetActiveConfigID(), subTreeID).name`。刷新事件 `TRAIT_CONFIG_UPDATED`(Core 已注册)。
  - 检视别人:检视配置 `configID = -1`,遍历 `GetConfigInfo(-1).treeIDs` → `GetTreeNodes` →
    `GetNodeInfo(-1, node)` 找 `subTreeActive` 节点取 `subTreeID`(`ns.InspectHeroSubTree`)。友方非 secret。
- **12.0 新专精**:恶魔猎手第三专精 **Devourer(噬灭, specID 1480)** —— 虚空系**智力**远程 DPS,吃法系装备。
  全游戏现为 **40 专精**(39+1),其它职业无增改。`ns.PlayerSpecID`/`ns.InspectSpecID` 走 specID。
- **换季维护**:重抓各专精 order(团/米/tie)+ 校验 `subTreeID`(若 Blizzard 重排)+ bump `STAT_PRIORITY_DATE`。

## 历史:1.6.1(2026-06-21 本机发布)
1.6.0 → **1.6.1**:**平均耐久度并入物品等级行**(用户要求,更美观)。
- 不再单独占属性栏底部一行;改成把暴雪的物品等级数字**藏掉**,在**同一行**
  (`CharacterStatsPane.ItemLevelFrame`)用一个**居中**的合并字串替代:`286.1 ｜ 88%`
  (物品等级金色 `|cffffd200` + 耐久百分比红→黄→绿 `|cffRRGGBB`,中间**全角竖线 U+FF5C**)。
- 单一 FontString → 物品等级与耐久**字号一致**(修了之前"装等偏小")。分隔符在字串自身白色,
  可改 `Config.DURABILITY_SEPARATOR`(**字节转义**存,Config.lua 仍纯 ASCII;默认 `\239\189\156`=U+FF5C)。
- 实现:`hooksecurefunc("PaperDollFrame_SetItemLevel", …)`(仅 `unit=="player"` 且 statFrame==本 pane 的
  ItemLevelFrame)里重渲染;读暴雪 `ItemLevelFrame.Value:GetText()` 拿装等文本 → `Value:Hide()` 藏原数字 →
  自己的居中 FontString 显示合并行。耐久变化(repair)仍走原 `UPDATE_INVENTORY_DURABILITY` →
  `UpdateAllVisible` → `UpdateDurability` 路径刷新。关 `showDurability` 时 `Value:Show()` 还原、隐藏合并行。
- Config 耐久段重写:**去掉** `DURABILITY_POINT`;**新增** `DURABILITY_MIN_FONT_SIZE` / `MAX_WIDTH` /
  `SEPARATOR`;`X/Y` 改为相对居中的微调。安全:仍只读自己装备 + 自己的物品等级文本,**永不 secret**。
- 走位踩坑(留给后人):一开始想塞进**两把武器格中间**的空隙——结果 12.0 主手/副手是**紧贴的**
  (实测 gap=5px),字被压成 1px 宽=隐形。教训:角色面板底部那俩武器格没有宽空隙;别往那放。
  (定位手段:临时 `Debug.lua` 丢几条带标签彩条 + 打印 slot 坐标/gap/`ItemLevelFrame.Value` 状态,
  一次 reload 截图就看清,定位完即删。)

## 历史:1.6.0(2026-06-20 发布:main `1544146`,tag `DodoInspect-v1.6.0`,CF 产物 `DodoInspect-1.6.0.zip`)
1.5.0 → **1.6.0**,两个新功能:
1. 🆕 **两个侧栏字号可调**(选项里):角色侧栏(SidePanel)与检视侧栏(InspectPanel)以前
   共用 `Config.PANEL_FONT_SIZE`,现在各有一个 px 滑条(ESC 选项面板,`Settings.CreateSlider`,
   范围 `Config.PANEL_FONT_MIN`..`MAX` = 8..36)。存 `DodoInspectDB.sidePanelFontSize` /
   `inspectPanelFontSize`,未设=Config 默认。读取走 `ns.SidePanelFontSize()` /
   `ns.InspectPanelFontSize()`(Core.lua,带 clamp),两个面板 `ComputeGeometry` 改用它们。
   **实时预览不重建帧**:把行的几何(SetPoint/SetWidth/SetSize)抽到 `ApplyRowGeometry(row)`,
   CreateRow 末尾调一次;滑条变化触发 `ns.RebuildSidePanel` / `ns.RebuildInspectPanel`,
   重算几何 + 对**现有行**逐个 ApplyRowGeometry(命中框 `SetAllPoints` 自动跟随,下划线在
   UpdateRow 重锚)——拖动时零帧创建,不泄漏。Settings API 无文本输入控件,故用滑条带 " px" 标签
   (`MinimalSliderWithSteppersMixin.Label.Right` + formatter,带存在性兜底)。
2. 🆕 **银行覆盖层**(Bank.lua,开关 `showBankOverlays`,默认开):
   - **玩家银行**(TWW 新银行 `BankPanel` / `AccountBankPanel`):每件物品 button 有
     `GetBankTabID()`+`GetContainerSlotID()`=合法 C_Container 容器坐标 → **直接复用** Bags 抽出的
     `ns.ApplyItemOverlay`,装等/部位/BOE/套装/类型标签全套和背包一致。刷新靠 hook 面板的
     `GenerateItemSlotsForSelectedTab`+`RefreshAllItemsForSelectedTab`(切页/移动跟随)+
     `BANKFRAME_OPENED` 兜底重画。Hook 幂等(本地 `bankHooked` 表)。
   - **公会银行**(LoD `Blizzard_GuildBankUI`,`GuildBankFrame`):**不是** C_Container,只能按
     **链接**做 → 装等(`ns.GetLinkItemLevel`)+部位(`ns.GetSlotLabel`)+类型标签;BOE/套装跳过
     (公会银行不暴露 per-instance 绑定态)。遍历 `GuildBankFrame.Columns[c].Buttons[r]`(回退老
     全局名 `GuildBankColumn{c}Button{r}`),button `:GetID()` = 1..98 slot index,
     `GetGuildBankItemLink(GetCurrentGuildBankTab(), index)`。只在 `frame.mode=="bank"`(物品页,
     非记账页)画。Hook `GuildBankFrame:Update`(回退老全局 `GuildBankFrame_Update`)+
     `GUILDBANKBAGSLOTS_CHANGED`(异步查询回来重画)。
   - **配套抽取**:`ns.ApplyItemOverlay`(Bags.lua,背包/玩家银行共用,内含 ItemLocation 失败时
     回退链接装等——只在仓库容器触发,背包永不触发);`ns.GetLinkQuality`(ItemInfo.lua);
     `IsQuestItem` 加 nil-safe(公会银行无 bag/slot,传 nil 时只靠 classID)。

## 历史:1.5.0(2026-06-19 发布)
1.4.1 → **1.5.0**,三个新功能(都在角色面板):
1. 🆕 **平均耐久度**(Durability.lua):属性栏底部一行 `耐久度 XX%`,红→黄→绿渐变。锚
   `CharacterStatsPane` 底部,`Config.DURABILITY_*` 可调。开关 `showDurability`,四国语言
   (Locales `durability`)。`GetInventoryItemDurability` 读自己装备(永不 secret),
   `UPDATE_INVENTORY_DURABILITY` 刷新。
2. 🆕 **强化属性三列 + 装等渐变/小数**(StatRatings.lua):强化属性行 = `部位 | 百分比 | 评级`
   三列对齐(暴雪百分比左移 `Config.STAT_RATING_COL_W`,评级单独 FontString 右对齐,按
   `STAT_COLORS`/`TERT_COLORS` 上色),百分比保留一位小数,物品等级用插件渐变 + 一位小数。
   开关 `showStatRatings`。**⚠️ 读战斗属性 API(secret),见上 Secret 节**。坑:
   - **帧池跨 category 复用**:强化属性的行 frame 下次刷新可能拿去显示主属性(急速→耐力),
     加的评级/位移会泄漏过去。解法:每次刷新后 `C_Timer.After(0)` 调度一次**清扫**,把本轮没被
     当强化属性刷新的行还原(隐藏评级、百分比挪回)。清扫**不依赖** `PaperDollFrame_UpdateStats`
     的函数名(靠 setter hook 触发),稳。
   - **绝不碰主属性**:只 hook 那 7 个强化属性 setter + `PaperDollFrame_SetItemLevel`,从不 hook
     `PaperDollFrame_SetStat`(力量/耐力/护甲)。
   - 暴击 setter 名两种拼法都试(`SetCritChance` / `SetCriticalChance`)。
   - 百分比小数只在暴雪原始 `numericValue` 与已显示整数吻合(±1)时才改(防它不是百分比时显示错值)。
     装等颜色用**内联色码写进文本**(非 `SetTextColor`),复用行被暴雪重写时自愈、不泄漏。
3. 🆕 **角色装备栏附魔/宝石**(Equipment.lua):玩家自己的装备格现在和检视框一样显示附魔(左下)
   + 宝石(右下)。复用既有开关 `showEquipmentIlvl`(标签改 "Equipment slot overlays")。抽出共享
   `ns.SetEnchantAndGems`(Overlay.lua),Equipment 与 Inspect 共用保持同步。

## 历史:1.4.0(2026-06-13 发布)
1.3.1 → **1.4.0** 一波发布,含:
1. 战场 secret 崩溃**全面修复**(TargetInfo.lua,见上)。
2. ESC 设置面板顶部**版本号横幅**(Options.lua,`C_AddOns.GetAddOnMetadata` 读 TOC
   + `CreateSettingsListSectionHeaderInitializer`)。
3. 背包**类型标签移到右上角** + 非中文 **−2 字号**(Config `TYPE_POINT`、Overlay 右对齐、
   Locales en/fr/es `sizeBump=-2`)。
4. 角色侧栏**列间距收紧**(SidePanel `ComputeGeometry`:`STAT_X` `FS*0.7→0.3`、`TERT_W` `FS*1.4→1.0`)。
5. 🆕 **检视框装备覆盖层**(Inspect.lua):每件装备 装等(左上)+ 附魔(左下绿/红)+ 宝石(右下)。
   开关 `showInspectIlvl`(标签 "Inspect window gear overlays")。覆盖层原语在 Overlay.lua
   (`SetEnchantTag`/`SetGemOverlay`),位置 Config `ENCH_OVL_*` / `GEM_OVL_*`。
6. 🆕 **检视简化侧栏**(InspectPanel.lua):部位 + 装等 + 四属性。开关 `showInspectPanel`。

**共享层(B 方案,零回归)**:SidePanel 用 `ns.X = X` 把数据 helper 导出
(`ParseItemLink`/`GetStatsTable`/`CountTemplateSockets`/`IsEnchantableSlot`/`GEAR_SLOTS`/
`STAT_ORDER`/`STAT_KEYS`/`EMPTY_SOCKET_TEXTURE`/`MAX_SOCKETS`),Inspect/InspectPanel 复用;
Inspect 导出 `ns.GetLinkItemLevel`(检视装等按**链接**读,`ItemLocation` 仅 player)。
**角色侧栏渲染逻辑没动**,只加了导出别名。

**检视框 = 按需加载**(`Blizzard_InspectUI`):等其 `ADDON_LOADED` 再 hook(或事件里 lazy);
刷新走 `INSPECT_READY` + `GET_ITEM_INFO_RECEIVED` + 框 `OnShow`;被检视单位 = `InspectFrame.unit`
(回退 `"target"`)。装等/附魔/宝石都共用 `showInspectIlvl` 一个开关。

## 关键约定 / 可调参数
- 渐变三阈值在 Config(MIN 262 / ORANGE 326 / MAX 344,每季调;当前为12.1 S2)。
- 属性优先级全局功能闸门=`Config.STAT_PRIORITY_FEATURE_ENABLED`;数据新鲜度由每个 entry 的
  `current=true` 控制。来源仍有分歧但获准显示的 entry 加 `provisional=true`;不要恢复全局
  “全表一起 current”的设计,也不要把暂定行伪装成已收敛行。
  `showStatPriority` SavedVariable 保持不变。build-only entry 不得设置臆测 fallback。
- 背包标签 & 格子缩写字号 = `*_FONT_SIZE + ns.L.sizeBump`(per-locale:cn **+2**、
  其它 **−2**)。这是 CJK-only 字号调整的范式。tag 最多 4 拉丁 / 2 CJK 字符。
- 侧栏布局 = `ComputeGeometry` 里的**累加链**(全是 FS 倍数);改一个间距,它右边所有列
  整体平移、`PANEL_W` 跟着变。`FS` 现在来自 `ns.SidePanelFontSize()` / `ns.InspectPanelFontSize()`
  (DB 覆盖 `Config.PANEL_FONT_SIZE`,clamp 到 `PANEL_FONT_MIN/MAX`),不再直接读 Config。
  字号变了走 `RebuildSidePanel`/`RebuildInspectPanel`(重算几何 + ApplyRowGeometry 复用现有行)。
- 目标信息行的文字跟**客户端语言**(种族/职业/专精来自游戏本地化),addon locale
  只决定字体 + 背包标签翻译。

## 发布
CF 项目 id **1572493**;tag `DodoInspect-v<版本>`(annotated,**`--cleanup=verbatim`**
保留 `##` markdown 标题);workflow 校验 tag 版本 == TOC `## Version`,打包排除
CLAUDE.md / test。PS 5.1 提交用 `git commit -F <文件>`(`-m` 带引号会被拆碎)。

⚠️ **两个发版顺序 / 形态的坑(2026-08-11 发版前审计抓到,v1.8.0 已中过第 2 条)**:
1. **workflow 打包的是 tag 指向的那个 commit** —— 代码必须**先 commit + push 进 repo,再打 tag**。
   顺序反了 = 版本号是新的、包里代码是旧的,而且**全程绿灯没有任何人报错**。
2. 🔴 **lightweight tag 会把 commit message 当 changelog 发上 CurseForge,而且完全不报错**。
   必须 `git tag -a -F <文件> --cleanup=verbatim`。**`DodoInspect-v1.8.0` 就是 lightweight 打的**,
   所以它在 CF 上的更新说明是那条 commit message,不是写好的 release notes。
   **验法**(不用翻本地 tag):`git ls-remote --tags origin 'DodoInspect-*'` ——
   annotated tag 会**多一行 `refs/tags/X^{}`**(peel 行);**没有那行 = lightweight**。
   实测 v1.6.1 / v1.7.0 有,**v1.8.0 没有**。打完 tag 推上去后用这条自查一遍。
   🔴 **pattern 千万别收窄成那一个 tag 名**(2026-08-22 实撞):`'DodoInspect-v1.13.1'`
   **匹配不到 `DodoInspect-v1.13.1^{}`** ⇒ 只回一行 ⇒ 读起来正好像「这是个 lightweight tag」,
   而下一步(重打)会覆盖一个其实完全正确的 tag。**要么保留 `DodoInspect-*`,要么写
   `DodoInspect-v1.13.1*`(带尾 `*`)。** 判据本身也要有负对照:拿一个**已知 annotated**
   的旧 tag 跑同一条命令,它要是也只回一行,那就是 pattern 的问题不是 tag 的问题。
   ✅ **更省事的独立判据**:`git cat-file -t <tag 的 sha>` —— annotated 回 `tag`,
   lightweight 回 `commit`。它不吃 pattern。
