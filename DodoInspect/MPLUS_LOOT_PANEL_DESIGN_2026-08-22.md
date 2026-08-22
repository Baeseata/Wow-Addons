# 大秘境掉落查询侧栏 — 设计稿

日期：2026-08-22（12.1 Season 2）。**零代码，本文只是开工依据。**

> ⛔ 本文是**设计定稿 + 调研结论**，不是进度快照。「做到哪儿了」去查 `git log` 和 TOC；
> 本文里任何一条读起来像状态的句子，都以代码为准。

## 需求(Jerry 2026-08-22 口述 + 当场拍板)

打开史诗钥石地下城界面(`ChallengesFrame`)时右侧挂一个侧栏，高度跟该界面一致：

- **侧栏一**：从上到下 8 张卡片 = 本赛季 8 个大秘境，每张是按钮。
- **点卡片 → 侧栏二**(同样固定高度)：列出该本**当前选中专精可拾取的装备掉落**。
  顶部一个下拉栏切职业/专精，样式照暴雪。行放不下加滚动条。
- 侧栏二的列：① 装备名(hover 出属性 tooltip) ② 大绿字 ③ 小绿字 ④ 持有状态。
  ②③ 复用角色侧栏候选面板(`GearPanel`)那套。

### 当场拍板的两条

1. **第四列只做「当前持有」**，不做「拥有过」，也不分勇士/英雄档 —— 理由见下面「做不成的」。
   显示形如 `已装备 311` / `背包 305`，装等是从实物 link 读的真值。
2. **卡片 = 游戏图标 + 手写简称**(中英)。图标和全名走游戏 API，简称手写。

## 已经查实的数据(开工时直接用，别重查)

### 八本的 ID 与简称

中文简称由 Jerry 给，**八个全部是该本官方中文全名的真子串**(拿 `wago.tools`
`JournalInstance?locale=zhCN` 逐个核过，零歧义)。老本三个的中英简称同时也是社区通用值
(本机 RaiderIO 的 locale 包里就有 `诸王` / `红玉` / `神庙`)。

| journalInstanceID | challengeMapID | 官方中文全名 | 中文简称 | 英文 |
|---:|---:|---|---|---|
| 1322 | 588 | 毒牙祭坛 | 毒牙 | `AOF` |
| 1304 | 587 | 密谋小径 | 密谋 | `MR` |
| 1311 | 586 | 纳洛拉克的洞穴 | 洞穴 | `DON` |
| 1309 | 584 | 夺目谷 | 夺目 | `BV` |
| 1313 | 585 | 虚空之痕竞技场 | 虚空 | `VA` |
| 1041 | 249 | 诸王之眠 | 诸王 | `KR` |
| 1030 | 250 | 塞塔里斯神庙 | 神庙 | `TOS` |
| 1202 | 399 | 红玉新生法池 | 红玉 | `RLP` |

⚠ **新本那五个英文简称是我们自己拟的，不是社区通用值** —— 2026-08-22 搜过，赛季刚开、
社区还没形成约定。拟的规范抄 RaiderIO 的实际用法(取实词首字母、`of` 保留如
`POS`=Pit **o**f Saron、冠词跳过、2–4 字母)。**哪天社区定了别的叫法，以社区的为准。**
老本那三个不用改，它们本来就是通用值。

### challengeMapID ↔ journalInstanceID:**要生成，不要手写**

`JournalInstance` 有一个 `MapID` 字段，跟 `MapChallengeMode.MapID` 能直接 join
(八本逐个对上;老本三个的 MapID 是 `1762 / 1877 / 2521` —— 原文这里写的 `2859` 是**新本**夺目谷,不是老本)。⇒ `gen_loot.py` 顺手生成这张表，
换赛季时它跟着 `DUNGEONS` 常量自动更新。**手写的那份必然会漂**
(canon `rules/engineering.md`「同一个不变式两份手写实现 = 静默分歧发生器」)。

🎁 **2026-08-22 补:连「哪八本」本身都有权威源** —— `MythicPlusSeasonTrackedMap`
(`DisplaySeasonID` → `MapChallengeModeID`)。`DisplaySeason 37` 实测**正好**是我们这 8 个,
而且 37 是表里最大的季 ⇒ 这个 build 上没有下季数据可混。生成器已挂上这条交叉核对。
- ⚠ **必须钉死季号,不许 `max(DisplaySeasonID)`** —— wago 同时供 PTR build,
  下个季会在**上线前**就出现在这张表里,`max()` 会在一次例行重跑里把整个面板换成未发布的副本。
  钉死 ⇒ 换季那天**吵着报错**,谁改 `DUNGEONS` 就同一笔改季号。
- ⚠ 三个「看起来能判季」的字段**别用**:`Flags` / `ExpansionLevel` 在这 8 本上区分不出来
  (`ExpansionLevel` 实为 `{11:5, 7:2, 9:1}`,诸王和神庙都是 7);
  `RequiredWorldStateID == 0` 在**这个 build 上**恰好是完美判据(8/8),
  但它显然会随季变 —— **一个今天成立的判据不等于一个可以依赖的判据**。
- 🔴 **join 不是天然唯一的**:全表有 **5 个 MapID 各带两条** challenge mode
  (卡拉赞上下 / 麦卡贡两半 / 塔扎维什两半 / 时光之末两半 / **1753 三巨头之座**)。
  最后那个**两条的 `Name_lang` 一模一样** ⇒ **靠比名字发现不了**,必须断言候选数 == 1。
  五个全都进过往季的 M+ 池,所以这是活的风险不是假想。A/B 已验:喂 945 进去精确报出 `239/583`。

### 装等:M+ 掉的是 311，不是 334

**地下城内掉落上限 = ilvl 311**(group 617 序列 3,+10 就封顶)。

> 🔴 **2026-08-22 复核:原文这里的「M+ 宝箱 321、大宝库 337」两个数都是错的。**
> 客户端 `MythicPlusSeasonRewardLevels`(season 120 / ActivityTier 256 = M+ 那一档)
> 直接读出 +2..+10 的大宝库是 `305 305 308 308 311 315 315 315 **318**` ——
> **大宝库 +10 = 318**(= Myth 1/9,所以 M+ **确实**产 Myth 轨道的装备,只走宝库);
> 337 是 Myth 7/9,M+ 任何渠道都够不到。**宝箱不是 321**:`ItemBonusTreeNode` 里
> 副本内掉落(ItemContext 16)和结算宝箱(33)两条通道映射**逐字节相同**,
> ⇒ 宝箱 = 掉落 = 311(此条是推出来的,没有直接读到宝箱那一列)。
> ⚠ **「3/6」这个分母未经证实**:group 617 有 **8** 条,末两条带一个 Flags 位,
> 被读作「超出显示上限」⇒ 显示成 6 档 —— **没有人拿真 tooltip 核过**。
> 真机点一次 12843 就同时答了分母和轨道名。
>
> 🔑 **元教训**:这两个错数跟当初「Myth 顶是 337」是**同一批 pre-season 来源**。
> 参考数字也要有出处,不然它会被下一个人当依据用。
**334 是 Myth 6/6 = 团本档，M+ 打死掉不到** —— 现有 `GearPanel` 用 334/344 是对的，
因为它排的是**全部来源含团本**；这个面板只排 M+，用 334 会让玩家系统性高估。

- **Hero 3/6 的 bonusID = `12843`**(`ItemBonusListGroupEntry` 里 group 617 的 `SequenceValue=3`)。
- 交叉验证:同一张表 `SequenceValue=1` 是 `12841`，而 CLAUDE.md 记录 Jerry
  **游戏内实测过 `12841` → ilvl 305**。表和实测对得上。
- ⚠ 仍然建议开工时游戏内点一次(方法见 CLAUDE.md「已落地:tooltip 按 6/6 / 9/6 渲染」那节)，
  **别把「两条线索对上」当成「已实测」**。

### 数据量

八本共 **223 件**装备(`LootData` 按 `[1]` = journalInstanceID 过滤)。
按专精过滤后每本十几件，侧栏量级合理。

## 🔴 做不成的:「已拥有-勇士 / 已拥有-英雄」(带证据,别再试一遍)

原始需求是第四列显示 `已拥有-勇士` / `已拥有-英雄` 这种**带装等档**的状态。**做不成。**

**证据一 —— 没有那种 API。** 全量扫了 **612 个**生成契约文档
(`Gethe/wow-ui-source` 的 `Blizzard_APIDocumentationGenerated`)，跟「玩家有没有这件东西」
相关的只有 transmog 一族(`PlayerHasTransmog` / `PlayerHasTransmogByItemInfo` /
`PlayerHasTransmogItemModifiedAppearance` / `PlayerKnowsSource`)。
**没有任何按装等档记录的收集系统。** 它们的参数只有 `itemID + appearanceModID`，没有装等维度。
⚠ 这是**全量**扫的结论 —— 按文件名猜会漏，因为 `C_TransmogCollection` 住在
`TransmogItemsDocumentation.lua` 里(canon:`Name` 不是命名空间，`Namespace` 才是)。

**证据二 —— `appearanceModID` 顶替不了档位。** 拿 223 件真数据点了 `ItemModifiedAppearance`：

| | 外观行数 | 说明 |
|---|---:|---|
| 团本装备(**对照组**) | 4 | modID `0/4/1/3` = 四个难度各一个外观 ⇒ **这个字段本身有分辨力** |
| 七本 M+ 装备 | 1 | 所有档共享一个外观 ⇒ **区分不了** |
| 塞塔里斯神庙的 36 件 | 3 | 是 **BfA 当年的 N/H/M**，不是本赛季轨道 ⇒ 拿它标「已拥有-英雄」是**假的** |
| **39 件(17.5%)** | **0** | 饰品/戒指/项链**压根没有外观** ⇒ transmog 完全答不了 |

对照组那一行是关键:少了它，「M+ 装备只有 1 行」这个观测**在「字段没分辨力」和「M+ 确实不分档」
两种情况下读起来一模一样**(canon guard 家族 (f):判据必须在真假两种情况下给出不同答案)。

**证据三 —— 那 39 件是这一列最危险的地方。** 如果「我们答不出」和「你没有」显示成同一个样子，
这一列会对 **17.5%** 的装备撒谎，而且是那种**没人会发现**的撒谎。

⇒ **落地口径:只扫实物(装备栏 / 背包 / 银行)，读 item link 的真实装等。**
这条路顺带把上面那个坑绕过去了 —— 它扫的是实物不是外观，**那 39 件照样准确**。
这才是选它的真正理由，不只是「更准」。

## 设计骨架(标出跟现有代码的接缝)

**侧栏一(卡片)**
- 图标 + 全名走 `C_ChallengeMode.GetMapUIInfo(challengeMapID)` → `texture` / `name`
  (⚠ 它 `MayReturnNothing = true`，要 nil-safe)。**四语零翻译**，只有简称是手写的。
- `Blizzard_ChallengesUI` 是按需加载 —— 照抄插件已有的 lazy 模式
  (`Blizzard_InspectUI` / `Blizzard_EncounterJournal` 两处先例，`LoadAddOn` + `pcall` + 缓存)。
- 高度锚 `ChallengesFrame`；面板 `SetParent` 到它，跟着一起隐藏(候选面板那条教训:
  **不是子帧就带不走**，得显式关)。

**侧栏二(掉落列表)**
- 过滤 = `ns.SpecGear[specID]`(护甲类型 + 主属性)，现成，40 个专精全在。
- 排序 / `unranked` / `statless` 三个字段的语义 = `GearRank` 现成 —— ⚠ **那三个字段是分开的，
  别再合并**(1.12.0 用一个 `unranked` 背三件事，在饰品上当场炸)。
- ②③ 两列 = `GearPanel` 1.13.0 之后那套「第一列 = 数值大的那条绿字」，正好是需求要的形状。
- 高度封顶 + 截断标题 `N/M` = `GearPanel` 现成
  (`floor((高度 - HEADER_H - 8) / ROW_HEIGHT)`)。需求说的滚动条可以先用这个顶着。
- ① 的 tooltip 用 `12843`(311)构造 link，写法抄 `GearPanel.TooltipLink`
  (⚠ `string.rep(":", 11)` 那个坑:冒号数是**声明的**不是数出来的)。

**下拉栏(切职业/专精)**
- ✅ **已定案(2026-08-22,不必再探)**:用**新** API ——
  `CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")`
  + `:SetupMenu(function(_, root) ... end)` + `root:CreateRadio(text, isSelected, setSelected)`
  + `:SetDefaultText(...)`;要在外部状态变了之后刷新按钮文字就再调一次 `:GenerateMenu()`。
  老的 `UIDropDownMenu_*` 是 **deprecated-but-alive**(`Blizzard_SharedXML.toc` 仍在加载它,
  文件里也没有任何弃用告警 ⇒ **照老写法写不会报错,只是没人再该这么写**)。
- **三条互不依赖的证据**:① 12.1.0(69404)的暴雪源码里模板真实存在;
  ② RaiderIO 按能力分支(`Menu and MenuUtil and AnchorUtil` 有就走新的,老那支是给 Classic 的死代码);
  ③ **本机四个自家插件已经在产跑着这个写法** —— `DodoGuanzhu/Options.lua:513,550`
  是最贴近本需求的现成范例(`CreateRadio` + `SetDefaultText` + `GenerateMenu`)。
- 🔴 **心智模型别搞错**:**没有「从控件读回选中项」这回事。** 状态归你自己存,
  `isSelected` 是一个**对你自己状态求值的谓词**,按钮文字是从「谁报告自己被选中」派生出来的。
- 🔴 **取专精名用 `C_SpecializationInfo.GetSpecializationInfoByID`**
  (照本插件 `TargetInfo.lua:102-105` 已有的写法,带全局回落)。
  `GetSpecializationInfoForSpecID` **不存在** —— 本机 687 个 lua 文件零调用,照着写必报 nil。

**自检**
- `C_ChallengeMode.GetMapTable()` 是游戏自己的本赛季 M+ 池，**是权威源**。
  拿它跟我们那 8 本对一遍，**对不上就在侧栏顶部说一句「数据可能过期」**，
  而不是安静地少一张卡(canon:宽容的默认值会替 bug 遮丑)。

## 施工顺序建议

1. **数据层**:`gen_loot.py` 生成 challengeMap 映射表 + 简称表进 `Data/Loot.lua`；
   `Config` 加 `GEAR_HERO_BONUS_ID = 12843`。跑 `lua tools/test_gearrank.lua` 保持绿。
2. ~~**真机点两件事**~~ —— **下拉栏那条已定案**(见上面「下拉栏」节,零代码结论)。
   **只剩一件真机的活**:`12843` 是不是真给 311。三条离线推导已经互相对上
   (见 `Config.lua` 的 `GEAR_HERO_BONUS_ID` 注释),但**三条推导对上不等于量过**。
   顺带同一枪还能答分母(3/6 还是 3/8)和轨道名(是不是真叫 Hero)。
3. **侧栏一**:卡片 + 挂载 + 跟随隐藏。先不接侧栏二，单独能开能关。
4. **侧栏二**:列表 + 四列 + tooltip。
5. **下拉栏**:切职业/专精。
6. 第四列持有状态扫描。

## 开工前值得先读的两节

- `CLAUDE.md`「掉落来源 + 部位候选面板」—— `GearRank` / `GearPanel` 的全部坑。
- `CLAUDE.md`「🔴 首日就撞的坑:`unranked` 一个字段背着三件事」—— 这个面板会**再次**
  消费那三个字段，而 `tools/test_gearrank.lua` **覆盖不到 UI 层**，只能真机点。
