# PENDING-WORK — Wow-Addons 单仓级待办

> 规矩:**只装「欠着的活」,不装「要确认的事」**。判据 = 这条做完了交付物是什么 ——
> 代码/功能/数据变更 ✅ 进;一份结论/一次确认 ⛔ 不进(那些写进对应插件的 CLAUDE.md)。
> 完成即删,别留历史(历史归 commit)。各插件自己的待办在各自的 PENDING-WORK.md。

## 🔴 待查:`/dg config` 打了没反应(2026-08-24 Jerry 在 HOME 报)

症状:游戏里 `/dg config` 无任何反应。**不是命令不存在** —— `Core.lua` 里
`SLASH_DODOGRID2 = "/dg"` 且有 `arg == "config"` 分支。

判据链上有**三个静默失败点**,没有一处会报错:

| 环 | 位置 | nil 时的表现 |
|---|---|---|
| `ns.OpenOptions` 有没有定义 | `Options.lua:328` | `Core.lua` 那句 `if ns.OpenOptions then` 直接跳过 |
| `PLAYER_LOGIN` 有没有调 `InitOptions` | `Core.lua:594` | 下一环拿不到 category |
| `category` 有没有被设上 | `Options.lua:317` `InitOptions` 里 | `OpenOptions` 内的 `if` 直接跳过 |

⚠ **先确认跑的是哪份代码**(HOME 的实装目录 2026-08-22 才同步到 0.6.0,要 `/reload` 或重登才加载):

    /run print(C_AddOns.GetAddOnMetadata("DodoGrid","Version"))

打出 0.5.0 = 还没加载新代码,先 reload 再复现。不用命令的分流:ESC → 选项 → 插件
里有没有 DodoGrid 那一页 —— 有 = InitOptions 跑成了,卡在最后一环;没有 = 卡在前两环。

⚠ 别直接读代码找原因 —— 这是「代码看着全对而功能不出现」的形状,
**先把每一环的当前值打出来**(canon `rules/engineering.md` 同名条目)。

## 🟡 待拍板(拍板后要落地,所以进这里)

1. **三个小游戏「依赖 Dodo」三方打架**:`DodoBricks/DodoPool/DodoRush` 的 CLAUDE.md 说
   「依赖/必须装 Dodo」,TOC 写 `## OptionalDeps: Dodo`,而代码全是
   `if _G.Dodo and _G.Dodo.X then … else <回落> end`(运行时三个都不依赖)。
   唯一的真依赖是 Pool/Rush 的 TOC `## IconTexture` 指向 `Interface\AddOns\Dodo\Media\Dodo.tga`。
   ⇒ 这跟「上了 CF 的插件要不要自包含」是同一条规则。**一次定一条,别分三趟改措辞**
   (分三趟正是当初分叉的成因)。

2. **小地图默认角度**:2026-08-24 只消除了「精确叠死」(Airdrop 210→220),
   **没有**消除视觉重叠 —— 多数值挤在环的同一段上。
   耐久的那个数是几何:按钮 31px、环半径约 76px ⇒ **不重叠需要约 23° 间隔**。
   现在有哪些角、分别归谁,**跑这条**(别信这里抄一份,它会烂):

       grep -rniE 'minimapAngle|minimap = \{ angle|MINIMAP_ANGLE' --include='*.lua'

   ⚠ **`-i` 和 `MINIMAP_ANGLE` 是 2026-08-24 补的** —— DodoInspect 那天加了按钮,
   它的默认值叫 `LOOT_MINIMAP_ANGLE`,旧的大小写敏感 pattern **一个都找不到它**,
   于是这条待办自己的复查命令对最新的那个条目是瞎的。
   真正的修法是 `Dodo/Shared.lua` 加一张角度登记表 + `Dodo.MinimapAngle(ADDON)`。
   ⚠ 该方案对 **DodoNameplate / DodoInspect 不适用**(它们故意不挂 Dodo,见 DODO_ADDONS.md)——
   这两个只能继续手挑,所以那条 grep 是它们唯一的防撞手段。

3. **DodoBricks 在 HOME 没装**(repo 有、`D:/World of Warcraft/_retail_/Interface/AddOns/` 下没有)。
   它是 5 个已发布 CF 插件之一 ⇒ HOME 上没法给它做发版前冒烟测。装 = 需要完整重启客户端。

## 🟢 给 DodoUnholy 补一条 guard(照抄 DodoXuefei 的现成写法)

2026-08-24 从 `DodoUnholy/Rotation.lua` 删掉了 `ProbeCombatLog` 与 `/duh cl`
(注册 `COMBAT_LOG_EVENT_UNFILTERED` 在 12.x 是 forbidden action,调用本身会污染调用栈
并把插件记进 badAddons)。**但只留了注释,没有任何东西会在它被加回来时报红。**

`DodoXuefei/tools/test_dxf.lua` 里已经有现成的范本 —— 它把禁用词做成了断言:

    for _, ban in ipairs({ "SetApplicationCount", "COMBAT_LOG_EVENT_UNFILTERED" }) do ... end

⇒ 照它给 DodoUnholy 配一条同形的离线守卫。
⚠ 按 canon:**加完必须种一个真违规做 A/B**(把那行 RegisterEvent 种回去,看它变不变红、
指不指得准),「加完还是绿的」不算验证。

## 🟢 DodoInspect:增强萨(263)要改成分英雄树

2026-08-24 重扫发现,Wowhead 那页在 **08-22 23:48** 改过(比我们发 1.13.1 晚 8 小时),
作者把它拆成了两棵树,而我们 `Data/StatPriority.lua` 里是 1×1:

| | 现在的攻略 | 我们发的 |
|---|---|---|
| Stormbringer | **`C = M > H > V`** ← 变了 | 两树共用 `M = H > C > V` |
| Totemic | `M = H > C > V` | 同上(这支一致) |

作者写明了理由(赛季初关键暴击装被剥了属性,Stormbringer 转向暴击、放弃急速),
并明说**单体/AoE 不变** ⇒ 目标形状是 **2×1**(分树,不分内容)。

⏳ **建议等 08-25 那轮调优 + 作者跟进(约 3~7 天)再一起改**,别为一个格子单发一版 ——
理由跟 CLAUDE.md 1.13.1 节「时机比方法重要」那条一样。
⚠ 重扫时注意提取器的**第三种写法**(`[li][b]Critical Strike = Mastery[/b]`),
增强萨这页正是它 —— 详见 DodoInspect/CLAUDE.md 1.13.1 节。

## DodoInspect 掉落窗口第 4 步 —— 对抗审查留下的活(2026-08-25)

第 4 步(右栏)已发。审查提了 25 条、16 条站住,**修掉 14 条**;剩下这些是**代码 / 数据要动**的:

- 🔴 **`258045`(毒牙 warglaive)的 tooltip 渲染的是裸物品,不是 311。**
  它在 `Data/Loot.lua` 里是 `{1304, 2682, 4, nil, nil, ...}` —— **主属性和副属性全 nil**,
  而一把武器不可能没有主属性 ⇒ 这是 **`gen_loot.py` 的数据缺口**,不是一件「没副属性的装备」。
  于是 `statless` 真、`offTrack` 跟着真、`DetailBonusID` 返回 nil。影响 3 个恶魔猎手专精
  (577 / 581 / 1480),表现是那一行的 tooltip 装等明显偏低。
  ⚠ **别在面板层加启发式绕过去** —— 15 件真·无副属性的遗产装备(1030 / 1041 的艾泽里特件)
  **每一件都有主属性**,而 `offTrack` 的真正含义是「这件东西没有当季升级轨道」,
  那是**来源**的属性,数据里现在没有这个字段。⇒ 修在生成器:要么解析出它的属性,
  要么显式标一个 "on current track" 字段。**动 `gen_loot.py` 前先钉 build 跑一次**(理由见 CLAUDE.md)。
- **配套**:`tools/test_gearrank.lua` 里 statless 那节的 `SPECS = { 72, 258 }` 覆盖不到武器类
  —— 狂暴战和暗牧都拿不了 warglaive,所以上面那条它**一条都看不见**。
  改成遍历全部 40 个专精(**会当场报出 `258045`**,所以必须跟上面那条一起修,否则套件变红)。
- **本季唯一那根法杖对所有 40 个专精都不显示** —— `LOC.RANGED` 只挂在 RANGED 形状上。
  那个取舍是给**部位面板**定的(法杖要跟法杖竞争一个格子);来源列表回答的是
  「这个本掉不掉我能用的东西」,继承过来未必对。**这是设计决定,先问 Jerry,别自己改。**
