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
InspectPanel(检视简化侧栏)/ Durability(平均耐久并入物品等级行 `286.1 ｜ 88%`)/
StatRatings(强化属性栏:百分比+评级三列 + 装等渐变/小数)/
TargetInfo(目标信息行)/ Options(ESC 设置 + `/dins`)/ Core。

## ⚠️ 头号坑:Secret Values —— ~~只在 TargetInfo.lua~~ **不只**(2026-08-11 更正)

> 🔴 **这个标题以前写的是"只在 TargetInfo.lua",那句话本身就是 2026-08-11 那次崩溃的帮凶之一** ——
> 新写 `StatPriority.lua` 的时候,读到"只在 TargetInfo"就没去想 guard。**下面第 41 行那条"审计结论"
> 同样有过期风险:它是 2026-06-13 的快照,不是不变量。** 加任何读非玩家单位的代码,都自己重新点一遍。
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

## 当前状态:1.9.0(2026-08-13 已发布,tag `DodoInspect-v1.9.0`,CurseForge file 8643276)
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
