# DodoInspect 12.1 逐专精发布矩阵

日期：2026-08-13

实现版本：1.9.0（本机，尚未发布）

当前结果：**40/40 个专精可显示：26 个已基本收敛，14 个暂定基线**

## 发布规则

- 审核单位从“整张 40 专精表”改为单个 `spec × hero tree × content` 格子。
- 两棵英雄树相同就压成一行；团本与 M+ 相同就压成一列。最简单是 1×1，最复杂是 2×2。
- 同一个格子里仍有实质相反的当前资料时，选更新时间最新、拆分最细且最符合默认场景的一份
  作为 source-of-record，并给 entry 标记 `provisional=true`；tooltip 必须明示来源仍有分歧。
- `=` 只用于攻略明确表示相近、可互换或经常翻转的属性。
- 最终产品只显示固定属性顺序；不读取玩家当前绿字，也不显示目标数值、cap、区间或达标后换序。
- 所有提示统一带免责声明：仅供通用配装参考，通常先看装等和主属性；坦克默认生存，治疗默认治疗量；最终模拟自己的角色。
- 每个生产 entry 必须显式 `current=true`；暂定 entry 还必须显式 `provisional=true`。不回退 Season 1 数据。

缩写：`C` 暴击、`H` 急速、`M` 精通、`V` 全能。

## 数量

| 最小矩阵 | 数量 | 含义 |
|---|---:|---|
| 1×1 | 27 | 两树相同，团本/M+相同 |
| 1×2 | 4 | 两树相同，只分团本/M+ |
| 2×1 | 4 | 只分英雄树，团本/M+相同 |
| 2×2 | 5 | 英雄树和内容都需要保留 |
| **合计** | **40** | 26 个已收敛 + 14 个暂定 |

## 已基本收敛的 1×1：17 个

| specID | 专精 | 团本 = M+、两英雄树相同 | 主要依据 |
|---:|---|---|---|
| 251 | 冰霜死亡骑士 | `C > M > H > V` | [Wowhead / khazakdk](https://www.wowhead.com/guide/classes/death-knight/frost/stat-priority-pve-dps) |
| 577 | 浩劫恶魔猎手 | `C > M > H > V` | [Wowhead / Shadarek](https://www.wowhead.com/guide/classes/demon-hunter/havoc/stat-priority-pve-dps)、[Icy Veins](https://www.icy-veins.com/wow/havoc-demon-hunter-pve-dps-stat-priority)、[Method](https://www.method.gg/guides/havoc-demon-hunter/stats-races-and-consumables) |
| 581 | 复仇恶魔猎手 | 生存：`H > C=V > M` | [Wowhead / Itamae](https://www.wowhead.com/guide/classes/demon-hunter/vengeance/stat-priority-pve-tank) |
| 104 | 守护德鲁伊 | 生存：`H > V > C > M` | [Wowhead / Pumps](https://www.wowhead.com/guide/classes/druid/guardian/stat-priority-pve-tank) |
| 105 | 恢复德鲁伊 | 治疗：`H > M > V > C` | [Wowhead / Voulk](https://www.wowhead.com/guide/classes/druid/restoration/stat-priority-pve-healer) |
| 254 | 射击猎人 | `C > M > V > H` | [Wowhead / Azortharion](https://www.wowhead.com/guide/classes/hunter/marksmanship/stat-priority-pve-dps)、[Method / Qenjua](https://www.method.gg/guides/marksmanship-hunter/stats-races-and-consumables) |
| 255 | 生存猎人 | `M > C=H > V` | [Wowhead / DoolB](https://www.wowhead.com/guide/classes/hunter/survival/stat-priority-pve-dps)、[Method / Symex](https://www.method.gg/guides/survival-hunter/stats-races-and-consumables) |
| 63 | 火焰法师 | `H > M > V > C` | [Wowhead / Preheat](https://www.wowhead.com/guide/classes/mage/fire/stat-priority-pve-dps)、[Icy Veins / Dutchmagoz](https://www.icy-veins.com/wow/fire-mage-pve-dps-stat-priority) |
| 64 | 冰霜法师 | `M > C > H > V` | [Wowhead / Dorovon](https://www.wowhead.com/guide/classes/mage/frost/stat-priority-pve-dps)、[Icy Veins / Kuni](https://www.icy-veins.com/wow/frost-mage-pve-dps-stat-priority) |
| 269 | 踏风武僧 | `H=C=M > V` | [Peak of Serenity / Babylonius](https://www.peakofserenity.com/tww/windwalker/pve-guide/)、[Wowhead](https://www.wowhead.com/guide/classes/monk/windwalker/stat-priority-pve-dps) |
| 70 | 惩戒圣骑士 | `M > H > C > V` | [Wowhead / Bolas](https://www.wowhead.com/guide/classes/paladin/retribution/stat-priority-pve-dps)、[Method / Seqq](https://www.method.gg/guides/retribution-paladin/stats-races-and-consumables) |
| 256 | 戒律牧师 | 治疗：`H > M > C > V` | [Icy Veins / Clandon](https://www.icy-veins.com/wow/discipline-priest-pve-healing-stat-priority)、[Wowhead / AutomaticJak](https://www.wowhead.com/guide/classes/priest/discipline/stat-priority-pve-healer) |
| 258 | 暗影牧师 | `H > M > C > V` | [Warcraft Priests S2 FAQ](https://github.com/WarcraftPriests/discord/blob/main/shadow-faq/threads/gearing.md) 的通用固定顺序；不把英雄树/当前装备目标换算成动态建议 |
| 259 | 刺杀潜行者 | `C > H > M > V` | [Wowhead / Whispyr](https://www.wowhead.com/guide/classes/rogue/assassination/stat-priority-pve-dps)、[Icy Veins / Seliathan](https://www.icy-veins.com/wow/assassination-rogue-pve-dps-stat-priority) |
| 262 | 元素萨满祭司 | `M > H=C > V` | [Wowhead / HawkCorrigan](https://www.wowhead.com/guide/classes/shaman/elemental/stat-priority-pve-dps)、[Icy Veins / Stormy](https://www.icy-veins.com/wow/elemental-shaman-pve-dps-stat-priority) |
| 263 | 增强萨满祭司 | `M=H > C > V` | [Wowhead / Wordup](https://www.wowhead.com/guide/classes/shaman/enhancement/stat-priority-pve-dps)、[Icy Veins / Wordup](https://www.icy-veins.com/wow/enhancement-shaman-pve-dps-stat-priority) |
| 71 | 武器战士 | `C=H > M > V` | [Wowhead / Archimtiros](https://www.wowhead.com/guide/classes/warrior/arms/stat-priority-pve-dps)、[Icy Veins / Archimtiros](https://www.icy-veins.com/wow/arms-warrior-pve-dps-stat-priority) |

## 已基本收敛的 1×2：2 个

| specID | 专精 | 团本 | M+ | 主要依据 |
|---:|---|---|---|---|
| 268 | 酒仙武僧 | 生存：`C=V=M > H` | 综合/伤害：`C > V=M > H` | [Wowhead / Sinzhu](https://www.wowhead.com/guide/classes/monk/brewmaster/stat-priority-pve-tank)、[Method / Nate](https://www.method.gg/guides/brewmaster-monk/stats-races-and-consumables) |
| 73 | 防护战士 | 一般生存：`H > C=V > M` | `H > C > V > M` | [Wowhead / Pumps](https://www.wowhead.com/guide/classes/warrior/protection/stat-priority-pve-tank)、[Icy Veins / Mwahi](https://www.icy-veins.com/wow/protection-warrior-pve-tank-stat-priority) |

防战遇到以魔法伤害为主的战斗时，全能可能升到第一；这是战斗类型例外，不改写一般生存矩阵。

## 已基本收敛的 2×1：3 个

| specID | 专精 | 英雄树 A（团本 = M+） | 英雄树 B（团本 = M+） | 主要依据 |
|---:|---|---|---|---|
| 102 | 平衡德鲁伊 | Keeper of the Grove `23`：`M > H=C > V` | Elune's Chosen `24`：`M > H > C > V` | [Wowhead / gamz](https://www.wowhead.com/guide/classes/druid/balance/stat-priority-pve-dps) |
| 103 | 野性德鲁伊 | Druid of the Claw `21`：`M > H > C > V` | Wildstalker `22`：`M > C > H > V` | [Wowhead / Guiltyas](https://www.wowhead.com/guide/classes/druid/feral/stat-priority-pve-dps)；[Dreamgrove](https://dreamgrove.gg/blog/feral/compendium)完整场景段落预计 8 月 17 日复核 |
| 1473 | 增辉唤魔师 | Chronowarden `38`：`M > C > H > V` | Scalecommander `36`：`M > C=H > V` | [Icy Veins / Saeldur](https://www.icy-veins.com/wow/augmentation-evoker-pve-dps-stat-priority)、[Wowhead / Jereico](https://www.wowhead.com/guide/classes/evoker/augmentation/stat-priority-pve-dps) |

## 已基本收敛的 2×2：4 个

### 噬灭恶魔猎手（1480）

| 英雄树 | 团本 | M+ |
|---|---|---|
| Annihilator `124` | `H > M > C > V` | `M > H > C > V` |
| Void-Scarred `126` | `H > C > M > V` | `H > M > C > V` |

来源：[Icy Veins](https://www.icy-veins.com/wow/devourer-demon-hunter-pve-dps-stat-priority)、[Wowhead / VooDooSaurus](https://www.wowhead.com/guide/classes/demon-hunter/devourer/stat-priority-pve-dps)。

### 恩护唤魔师（1468）

| 英雄树 | 团本 | M+ |
|---|---|---|
| Flameshaper `37` | `M > C > H > V` | `M > C > H > V` |
| Chronowarden `38` | `M > C > H > V` | `M > H > C > V` |

来源：[Wowhead / Voulk](https://www.wowhead.com/guide/classes/evoker/preservation/stat-priority-pve-healer)、[Spiritbloom.Pro](https://spiritbloom.pro/preservation/quick-guide)、[Method / Cryve](https://www.method.gg/guides/preservation-evoker/stats-races-and-consumables)。

### 兽王猎人（253）

| 英雄树 | 团本 | M+ |
|---|---|---|
| Pack Leader `43` | `M > C=H > V` | `M > C > H=V` |
| Dark Ranger `44` | `C > M > H > V` | `M > C > H > V` |

来源：[Wowhead / Tarlo](https://www.wowhead.com/guide/classes/hunter/beast-mastery/stat-priority-pve-dps)、[Method / Qenjua](https://www.method.gg/guides/beast-mastery-hunter/stats-races-and-consumables)。Dark Ranger 的分格目前主要依赖一份明确的树别来源，列为开季后优先复核项。

### 神圣圣骑士（65）

| 英雄树 | 团本 | M+（治疗吞吐） |
|---|---|---|
| Herald of the Sun `50` | `M > H > C > V` | `M > H > C > V` |
| Lightsmith `49` | `M > C > H > V` | `M > H > C > V` |

来源：[Icy Veins / Mytholxgy](https://www.icy-veins.com/wow/holy-paladin-pve-healing-stat-priority)、[Method / Joki](https://www.method.gg/guides/holy-paladin/stats-races-and-consumables)、[WingsIsUp / Ellesmere](https://wingsisup.com/quickview)。

## 暂定基线：14 个

这些专精不再隐藏。插件选定下表的 source-of-record 作为默认参考，并在 tooltip 用橙色提示
“当前来源存在分歧”。这是产品允许的有依据近似值，不表示其他当前作者一定错误。

| specID | 专精 | 最小矩阵 | 插件采用的暂定答案 | source-of-record / 取舍 |
|---:|---|:---:|---|---|
| 250 | 鲜血死亡骑士 | 2×2 | San'layn `31` 团本 `H > M=C=V`；M+ `V > H > M > C`。Deathbringer `33` 团本 `C > M=V > H`；M+ `V > M > C=H` | 团本：[Wowhead / Mandl](https://www.wowhead.com/guide/classes/death-knight/blood/stat-priority-pve-tank)；M+：[Kyrasis 12.1 Advanced BDK](https://docs.google.com/document/d/1FJlB1T8ijaQLjY_cihyoyhLoi6lYRnT-N-ipVFCLidE/edit?usp=sharing)。按内容分别采用更细的生存模型 |
| 252 | 邪恶死亡骑士 | 1×1 | 两树、团本/M+：`M > C > H > V` | [Wowhead / Taeznak](https://www.wowhead.com/guide/classes/death-knight/unholy/stat-priority-pve-dps)：最新逐树完整表 |
| 1467 | 湮灭唤魔师 | 1×1 | 两树、团本/M+：`C > M > H > V` | [Wowhead / Preheat](https://www.wowhead.com/guide/classes/evoker/devastation/stat-priority-pve-dps)：最新逐树表；不混入 Method 的另一顺序 |
| 62 | 奥术法师 | 2×1 | Spellslinger `40`：`H > M > C > V`；Sunfury `39`：`H > V > C > M` | [Wowhead / Porom](https://www.wowhead.com/guide/classes/mage/arcane/stat-priority-pve-dps)：当前资料中拆英雄树最细 |
| 270 | 织雾武僧 | 1×2 | 团本治疗 `H > C > V > M`；M+治疗 `H > M > C > V` | [Wowhead / Swirl](https://www.wowhead.com/guide/classes/monk/mistweaver/stat-priority-pve-healer)：明确分 Raid/M+，并解释 M+精通联动 |
| 66 | 防护圣骑士 | 1×1 | 两树、团本/M+默认生存：`H > M > C > V` | [Wowhead / Pumps](https://www.wowhead.com/guide/classes/paladin/protection/stat-priority-pve-tank)：采用 survivability 完整序，不混 DPS 序 |
| 257 | 神圣牧师 | 1×2 | 团本治疗 `C > M > V > H`；M+治疗吞吐 `C > V > H > M` | [Icy Veins / Niphyr](https://www.icy-veins.com/wow/holy-priest-pve-healing-stat-priority)：选择纯治疗吞吐口径，不混伤害/生存目标 |
| 260 | 狂徒潜行者 | 1×1 | 两树、团本/M+：`H > C > V > M` | [Wowhead / JustGuy](https://www.wowhead.com/guide/classes/rogue/outlaw/stat-priority-pve-dps)：采用专门属性页，不混同作者 overview 的不同目标 |
| 261 | 敏锐潜行者 | 1×1 | 两树、团本/M+：`M > H > C > V` | [Wowhead / fuu1](https://www.wowhead.com/guide/classes/rogue/subtlety/stat-priority-pve-dps)：采用 8 月 13 日更新的固定完整顺序 |
| 264 | 恢复萨满祭司 | 1×1 | 两树、团本/M+默认治疗：`C > H > V > M` | [Wowhead / Harreks](https://www.wowhead.com/guide/classes/shaman/restoration/stat-priority-pve-healer)：最新且明确称两树/各场景同序 |
| 265 | 痛苦术士 | 1×1 | 两树、团本/M+：`H > C > V > M` | [Wowhead / Kalamazi](https://www.wowhead.com/guide/classes/warlock/affliction/stat-priority-pve-dps)：采用更新较晚的职业作者页 |
| 266 | 恶魔学识术士 | 1×1 | 两树、团本/M+：`H=C > M > V` | [Wowhead / NotWarlock](https://www.wowhead.com/guide/classes/warlock/demonology/stat-priority-pve-dps)：保留作者明确的 Haste/Crit 接近关系 |
| 267 | 毁灭术士 | 1×1 | 两树、团本/M+：`H > M=C > V` | [Wowhead / Loozy](https://www.wowhead.com/guide/classes/warlock/destruction/stat-priority-pve-dps)：采用最新专门属性页，不混其他作者的精通第一模型 |
| 72 | 狂怒战士 | 1×1 | 两树、团本/M+：`H > M > C > V` | [Wowhead / Archimtiros](https://www.wowhead.com/guide/classes/warrior/fury/stat-priority-pve-dps)：采用更新较晚的专门属性页 |

## 复查时点

- [Season 2 于 2026-08-18 当周开放](https://news.blizzard.com/en-us/article/24294369/the-shadows-deepen-midnight-season-2-begins-august-18)。开季调优后先重审被改动职业。
- 首周团本/M+资料出现后，优先复核低置信格：野性、兽王 Dark Ranger、神圣圣骑士 M+。
- Blizzard 已公告后续计划调优窗口；任何职业热修晚于这里的 2026-08-13 review date，都应使对应 entry 回到待复核状态。
