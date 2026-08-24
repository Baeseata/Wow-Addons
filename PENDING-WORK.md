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
   **没有**消除视觉重叠 —— 8 个值全挤在 200°–265°,而环上另外 295° 空着;
   按钮 31px、环半径约 76px ⇒ 不重叠需要约 23° 间隔,现在只有一处够。
   真正的修法是 `Dodo/Shared.lua` 加一张角度登记表 + `Dodo.MinimapAngle(ADDON)`。
   ⚠ 该方案对 **DodoNameplate / DodoInspect 不适用**(它们故意不挂 Dodo,见 DODO_ADDONS.md)。

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
