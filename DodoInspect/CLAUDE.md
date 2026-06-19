# DodoInspect — 交接文档(改之前先读这个)

> 本文档随仓库同步,CurseForge 打包时排除(workflow 里 `-not -name CLAUDE.md`)。
> 这是**跨机器传递"坑"的唯一可靠渠道** —— 本地 memory 不跨机器同步,git 仓库才共享。

## 这是什么
背包物品覆盖层 + 角色装备栏侧面板 + 目标信息行,Raider.IO 风格装等渐变。
文件:Config(可调参数)/ Locales(本地化,唯一含非 ASCII)/ Gradient / ItemInfo /
Overlay(物品按钮字串/图标覆盖层 + 共享 `SetEnchantAndGems`)/ Equipment(角色面板:装等+附魔+宝石)/
Inspect(检视框装备覆盖层:装等+附魔+宝石)/ Bags / SidePanel(角色装备侧栏)/
InspectPanel(检视简化侧栏)/ Durability(角色属性栏底部平均耐久)/
StatRatings(强化属性栏:百分比+评级三列 + 装等渐变/小数)/
TargetInfo(目标信息行)/ Options(ESC 设置 + `/dins`)/ Core。

## ⚠️ 头号坑:12.0 Secret Values —— 只在 TargetInfo.lua
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
先挡(链接/装等/属性)做防御,与全局姿态一致。`Bags`/`Equipment`/`SidePanel`/`ItemInfo`
只读**你自己的**物品(永不 secret)。**🆕 1.5.0 起 `StatRatings` 是唯一读战斗属性 API 的文件**
(`GetCombatRating`;玩家自己的属性**仅战斗中 secret**)—— 进战斗直接 bail(根本不调用)+ `issecretvalue` 兜底
+ 整段 `pcall`,战斗中冻结显示、脱战刷新。现实终态:战场敌方只能
显示种族 + 职业;竞技场专精走 `GetArenaOpponentSpec`,不受影响。

## 当前状态:1.5.0(2026-06-19 发布)
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
- 渐变三阈值在 Config(MIN 216 / ORANGE 280 / MAX 298,每季调)。
- 背包标签 & 格子缩写字号 = `*_FONT_SIZE + ns.L.sizeBump`(per-locale:cn **+2**、
  其它 **−2**)。这是 CJK-only 字号调整的范式。tag 最多 4 拉丁 / 2 CJK 字符。
- 侧栏布局 = `ComputeGeometry` 里的**累加链**(全是 FS 倍数);改一个间距,它右边所有列
  整体平移、`PANEL_W` 跟着变。
- 目标信息行的文字跟**客户端语言**(种族/职业/专精来自游戏本地化),addon locale
  只决定字体 + 背包标签翻译。

## 发布
CF 项目 id **1572493**;tag `DodoInspect-v<版本>`(annotated,**`--cleanup=verbatim`**
保留 `##` markdown 标题);workflow 校验 tag 版本 == TOC `## Version`,打包排除
CLAUDE.md / test。PS 5.1 提交用 `git commit -F <文件>`(`-m` 带引号会被拆碎)。
