# DodoInspect 12.1 逐专精发布矩阵

日期：2026-08-13

实现版本：1.9.0（本机，尚未发布）

当前结果：**26/40 个专精可显示，14/40 个专精继续隐藏**

## 发布规则

- 审核单位从“整张 40 专精表”改为单个 `spec × hero tree × content` 格子。
- 两棵英雄树相同就压成一行；团本与 M+ 相同就压成一列。最简单是 1×1，最复杂是 2×2。
- 同一个格子里仍有实质相反的当前资料时，该专精不显示；不能用 `=` 掩盖来源冲突。
- `=` 只用于攻略明确表示相近、可互换或经常翻转的属性。
- 明确的评级目标、目标区间和“达到阈值后换序”进入结构化 tooltip；目标不是硬 cap。
- 所有提示统一带免责声明：仅供通用配装参考，通常先看装等和主属性；坦克默认生存，治疗默认治疗量；最终模拟自己的角色。
- 每个生产 entry 必须显式 `current=true`。没有当前 entry 的专精完全隐藏，不回退 Season 1 数据。

缩写：`C` 暴击、`H` 急速、`M` 精通、`V` 全能。

## 数量

| 最小矩阵 | 数量 | 含义 |
|---|---:|---|
| 1×1 | 15 | 两树相同，团本/M+相同 |
| 1×2 | 2 | 两树相同，只分团本/M+ |
| 2×1 | 4 | 只分英雄树，团本/M+相同 |
| 2×2 | 5 | 英雄树和内容都需要保留 |
| **合计** | **26** | 其余 14 个无可见 fallback |

## 1×1：15 个

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
| 259 | 刺杀潜行者 | `C > H > M > V` | [Wowhead / Whispyr](https://www.wowhead.com/guide/classes/rogue/assassination/stat-priority-pve-dps)、[Icy Veins / Seliathan](https://www.icy-veins.com/wow/assassination-rogue-pve-dps-stat-priority) |
| 262 | 元素萨满祭司 | `M > H=C > V`；精通粗略目标约 1200 评级（约 72%） | [Wowhead / HawkCorrigan](https://www.wowhead.com/guide/classes/shaman/elemental/stat-priority-pve-dps)、[Icy Veins / Stormy](https://www.icy-veins.com/wow/elemental-shaman-pve-dps-stat-priority) |
| 263 | 增强萨满祭司 | `M=H > C > V` | [Wowhead / Wordup](https://www.wowhead.com/guide/classes/shaman/enhancement/stat-priority-pve-dps)、[Icy Veins / Wordup](https://www.icy-veins.com/wow/enhancement-shaman-pve-dps-stat-priority) |
| 71 | 武器战士 | `C=H > M > V` | [Wowhead / Archimtiros](https://www.wowhead.com/guide/classes/warrior/arms/stat-priority-pve-dps)、[Icy Veins / Archimtiros](https://www.icy-veins.com/wow/arms-warrior-pve-dps-stat-priority) |

## 1×2：2 个

| specID | 专精 | 团本 | M+ | 主要依据 |
|---:|---|---|---|---|
| 268 | 酒仙武僧 | 生存：`C=V=M > H` | 综合/伤害：`C > V=M > H` | [Wowhead / Sinzhu](https://www.wowhead.com/guide/classes/monk/brewmaster/stat-priority-pve-tank)、[Method / Nate](https://www.method.gg/guides/brewmaster-monk/stats-races-and-consumables) |
| 73 | 防护战士 | 一般生存：`H > C=V > M` | `H > C > V > M` | [Wowhead / Pumps](https://www.wowhead.com/guide/classes/warrior/protection/stat-priority-pve-tank)、[Icy Veins / Mwahi](https://www.icy-veins.com/wow/protection-warrior-pve-tank-stat-priority) |

防战遇到以魔法伤害为主的战斗时，全能可能升到第一；这是战斗类型例外，不改写一般生存矩阵。

## 2×1：4 个

| specID | 专精 | 英雄树 A（团本 = M+） | 英雄树 B（团本 = M+） | 主要依据 |
|---:|---|---|---|---|
| 102 | 平衡德鲁伊 | Keeper of the Grove `23`：`M > H=C > V` | Elune's Chosen `24`：`M > H > C > V` | [Wowhead / gamz](https://www.wowhead.com/guide/classes/druid/balance/stat-priority-pve-dps) |
| 103 | 野性德鲁伊 | Druid of the Claw `21`：`M > H > C > V` | Wildstalker `22`：`M > C > H > V` | [Wowhead / Guiltyas](https://www.wowhead.com/guide/classes/druid/feral/stat-priority-pve-dps)；[Dreamgrove](https://dreamgrove.gg/blog/feral/compendium)完整场景段落预计 8 月 17 日复核 |
| 1473 | 增辉唤魔师 | Chronowarden `38`：`M > C > H > V` | Scalecommander `36`：`M > C=H > V` | [Icy Veins / Saeldur](https://www.icy-veins.com/wow/augmentation-evoker-pve-dps-stat-priority)、[Wowhead / Jereico](https://www.wowhead.com/guide/classes/evoker/augmentation/stat-priority-pve-dps) |
| 256 | 戒律牧师 | Voidweaver `18`：`H > M > C > V`，急速粗略目标约 1800 评级 | Oracle `20`：`H > M > C > V` | [Icy Veins / Clandon](https://www.icy-veins.com/wow/discipline-priest-pve-healing-stat-priority)、[Wowhead / AutomaticJak](https://www.wowhead.com/guide/classes/priest/discipline/stat-priority-pve-healer) |

增辉两树在约 1840 精通评级后都转为 `M=C=H > V`；这是软转折，不是硬 cap。

## 2×2：5 个

### 噬灭恶魔猎手（1480）

| 英雄树 | 团本 | M+ |
|---|---|---|
| Annihilator `124` | `H > M > C > V` | `M > H > C > V` |
| Void-Scarred `126` | 约 800 急速评级前 `H > C > M > V`；之后 `C > M > V > H` | 约 800 急速评级前 `H > M > C > V`；之后 `M > C > V > H` |

800 评级约对应 17–20% 急速，随当前装备口径浮动。来源：[Icy Veins](https://www.icy-veins.com/wow/devourer-demon-hunter-pve-dps-stat-priority)、[Wowhead / VooDooSaurus](https://www.wowhead.com/guide/classes/demon-hunter/devourer/stat-priority-pve-dps)。

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

来源：[Icy Veins / Mytholxgy](https://www.icy-veins.com/wow/holy-paladin-pve-healing-stat-priority)、[Method / Joki](https://www.method.gg/guides/holy-paladin/stats-races-and-consumables)、[WingsIsUp / Ellesmere](https://wingsisup.com/quickview)。极高层 M+ 若改以生存/伤害为目标，约 25% 急速后会增加全能；该目标与这里的治疗吞吐格不同。

### 暗影牧师（258）

| 英雄树 | 团本/单体 | M+/AoE |
|---|---|---|
| Archon `19` | `M > C > H > V` | `M > H > C > V` |
| Voidweaver `18` | `M > H > C > V` | `H > M > C > V` |

tooltip 同时显示无增益的粗略评级目标：

| 格子 | 精通 | 急速 | 暴击 | 全能 |
|---|---:|---:|---:|---:|
| Archon 团本 | 1200–1400 | 1400–1600 | 800–1200 | ≤400 |
| Archon M+ | 1000–1200 | 1600–1800 | 800–1200 | ≤400 |
| Voidweaver 团本 | 1200–1400 | 1400–1800 | 800–1200 | ≤400 |
| Voidweaver M+ | 1000–1200 | 1600–1800 | 800–1200 | ≤400 |

来源：[Warcraft Priests S2 FAQ](https://github.com/WarcraftPriests/discord/blob/main/shadow-faq/threads/gearing.md)、[Icy Veins / Publik](https://www.icy-veins.com/wow/shadow-priest-pve-dps-stat-priority)、[Method / Jaerv](https://www.method.gg/guides/shadow-priest/stats-races-and-consumables)。这些是目标区间，不是硬上限。

## 继续隐藏：14 个

| specID | 专精 | 当前阻碍 |
|---:|---|---|
| 250 | 鲜血死亡骑士 | Deathbringer 的 M+生存权重在当前来源中实质冲突 |
| 252 | 邪恶死亡骑士 | 同一作者相隔一天把第一属性从暴击改为精通，且缺明确 AoE确认 |
| 1467 | 湮灭唤魔师 | 三位当前作者分别给出三套前三属性顺序 |
| 62 | 奥术法师 | 英雄树分表与同期通用资料在中后位实质冲突 |
| 270 | 织雾武僧 | M+同一治疗目标下，精通从第二到末位均有当前资料支持 |
| 66 | 防护圣骑士 | 团本生存格的精通/全能/暴击顺序没有收敛 |
| 257 | 神圣牧师 | M+资料混合治疗、伤害与生存目标，当前无法形成同口径格子 |
| 260 | 狂徒潜行者 | 第一属性与急速 23%/25–30%目标冲突 |
| 261 | 敏锐潜行者 | 团本第一属性反转，M+急速目标 650–700/1100 评级冲突 |
| 264 | 恢复萨满祭司 | 急速/全能顺序随吞吐、法力与生存目标翻转 |
| 265 | 痛苦术士 | 精通与全能的末两位仍反转 |
| 266 | 恶魔学识术士 | 三套同格口径和 22%急速转折没有互相确认 |
| 267 | 毁灭术士 | 连第一属性是精通还是急速都未收敛 |
| 72 | 狂怒战士 | 同一作者两个当前页面在第一位和末两位互相冲突 |

## 复查时点

- [Season 2 于 2026-08-18 当周开放](https://news.blizzard.com/en-us/article/24294369/the-shadows-deepen-midnight-season-2-begins-august-18)。开季调优后先重审被改动职业。
- 首周团本/M+资料出现后，优先复核低置信/目标限定格：野性、兽王 Dark Ranger、神圣圣骑士 M+。
- Blizzard 已公告后续计划调优窗口；任何职业热修晚于这里的 2026-08-13 review date，都应使对应 entry 回到待复核状态。
