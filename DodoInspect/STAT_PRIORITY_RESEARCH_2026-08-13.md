# DodoInspect 12.1 属性优先级增量复核

日期：2026-08-13

版本：Midnight 12.1 / Season 2 开启前五天

结论状态：暂不恢复显示，`Config.STAT_PRIORITY_DATA_CURRENT` 继续保持 `false`

## 本轮结论

- 重新检查全部 40 个专精，并优先复核 2026-08-10 至 2026-08-13 更新的 Blizzard、职业社区、Wowhead、Icy Veins 和 Method 资料。
- 多数主流攻略已经换成 12.1 页面，但 Season 2 团本和 Mythic+ 尚未开放，因此还没有可用于交叉验证的正式赛季实战资料。
- Blizzard 在 2026-08-13 公布了新的职业调优计划：开季维护时进行一轮，之后 8 月 26 日、9 月 2 日和 9 月 23 日继续调优。晚于攻略的调优会令对应数据单元自动失效。
- 严格按 8 月 11 日制定的生产门槛，当前仍为 **0/40 可发布**。不能把旧 12.0.7 / Season 1 全表改个日期后重新展示。
- 资料本身已经较完整、但被开季调优时间阻挡的专精有 2 个：浩劫恶魔猎手和惩戒圣骑士。
- 另保留 14 个候选；其余 24 个仍有来源、英雄树、内容类型、属性目标或阈值冲突。

官方时间线：

- [Season 2 于 2026-08-18 当周开启](https://news.blizzard.com/en-us/article/24294369/the-shadows-deepen-midnight-season-2-begins-august-18)，届时开放新团本和 Season 2 Mythic+。
- [Season 2 职业调优计划](https://us.forums.blizzard.com/en/wow/t/season-2-class-tuning-plans/2335871)列出开季、8 月 26 日、9 月 2 日和 9 月 23 日四个计划窗口；必要时还会追加调整。

## 资料层面已就绪，但暂不发布

这两行的现有资料足以形成低风险静态提示；它们仍不写入生产表，因为五天内就有已公告的职业调优，而且还没有 Season 2 团本/M+实战验证。

| specID | 专精 | 当前一致顺序 | 英雄树与内容覆盖 | 独立证据 | 阻挡项 |
|---:|---|---|---|---|---|
| 577 | 浩劫恶魔猎手 | 暴击 > 精通 > 急速 > 全能 | 两棵英雄树、单体与多目标未发现实质翻转 | [Icy Veins / Wordup](https://www.icy-veins.com/wow/havoc-demon-hunter-pve-dps-stat-priority)、[Method / Hype](https://www.method.gg/guides/havoc-demon-hunter/stats-races-and-consumables)、[Wowhead / Shadarek](https://www.wowhead.com/guide/classes/demon-hunter/havoc/stat-priority-pve-dps) | 等开季调优和首批 Season 2 数据 |
| 70 | 惩戒圣骑士 | 精通 > 急速 > 暴击 > 全能 | 两棵英雄树；AoE 仍使用同一粗粒度顺序 | [Wowhead / Bolas](https://www.wowhead.com/guide/classes/paladin/retribution/stat-priority-pve-dps)、[Icy Veins / Bolas](https://www.icy-veins.com/wow/retribution-paladin-pve-dps-stat-priority)、[Method / Seqq](https://www.method.gg/guides/retribution-paladin/stats-races-and-consumables)；前两者按作者去重 | 等开季调优和首批 Season 2 数据 |

## 14 个候选

以下顺序只记录当前资料的共同部分，不能直接复制进 `Data/StatPriority.lua`。`≈` 只表示来源明确认为接近；花括号表示来源尚未解决内部次序，不得在 UI 中伪装成并列。

| specID | 专精 | 当前共同部分 | 主要阻碍 |
|---:|---|---|---|
| 251 | 冰霜死亡骑士 | 暴击 > 精通≈急速 > 全能 | 中间两项仍随来源、构筑或目标翻转 |
| 1473 | 增辉唤魔师 | 精通 > 暴击≈急速 > 全能 | 约 1840 精通评级后的权重趋近；缺明确的团本/M+双重确认 |
| 254 | 射击猎人 | 暴击 > 精通 > 全能 > 急速 | 两位作者大体一致，但第二条证据没有完整覆盖英雄树和内容维度 |
| 255 | 生存猎人 | 精通 > {暴击、急速} > 全能 | 8 月 12 日 Method 的 AoE 顺序与 Wowhead/Icy Veins 冲突 |
| 63 | 火焰法师 | 急速 > 精通 > {全能、暴击} | 8 月 12 日 Method 将末两项换位，旧候选不能升级 |
| 64 | 冰霜法师 | 精通≈暴击≈急速 > 全能 | 前三项实际很接近且会随装备变化，固定顺序会过度承诺 |
| 269 | 踏风武僧 | 急速=暴击=精通 > 全能 | [Peak of Serenity](https://www.peakofserenity.com/tww/windwalker/pve-guide/)明确要求把前三项视为动态集群；独立确认不足 |
| 256 | 戒律牧师 | 急速 > 精通 > 暴击 > 全能 | 两棵英雄树和团本/M+大体兼容，但第二来源覆盖不足 |
| 258 | 暗影牧师 | 按英雄树与内容拆分 | [Warcraft Priests S2 FAQ](https://github.com/WarcraftPriests/discord/blob/main/shadow-faq/threads/gearing.md)给出不同目标区间；现有 schema 不能表达区间 |
| 259 | 刺杀潜行者 | 暴击 > 急速 > 精通 > 全能 | [Icy Veins](https://www.icy-veins.com/wow/assassination-rogue-pve-dps-stat-priority)与 8 月 12 日 [Wowhead](https://www.wowhead.com/guide/classes/rogue/assassination/stat-priority-pve-dps)一致，但仍缺新鲜的独立职业社区原站确认 |
| 262 | 元素萨满祭司 | 精通 > {急速、暴击} > 全能 | 72%/76%/86% 等精通阈值口径没有统一，现有 schema 难以准确表达 |
| 263 | 增强萨满祭司 | 精通≈急速 > 暴击 > 全能 | 新资料认为两棵英雄树已趋同，但 Icy Veins/Wowhead 均由 Wordup 撰写，只算一条证据链 |
| 71 | 武器战士 | 暴击≈急速 > 精通 > 全能 | 两站均为 Archimtiros，同一作者链；静态 `>` 会夸大前两项差异 |
| 73 | 防护战士 | 急速 > 暴击≈全能 > 精通 | 团本魔法伤、生存目标与 M+ 伤害目标会让全能/暴击换位，英雄树也未逐项确认 |

暗影牧师当前至少需要四个数据单元，而不是一条通用顺序：

| 英雄树 | 团本/单体 | M+/AoE |
|---|---|---|
| Archon | 精通 > 暴击 > 急速 > 全能 | 精通 > 急速 > 暴击 > 全能 |
| Voidweaver | 精通 > 急速 > 暴击 > 全能 | 急速 > 精通 > 暴击 > 全能 |

这些只是粗略顺序；FAQ 还给出了随目标数和装备变化的区间，因此当前 Lua 结构仍不足以完整发布。

## 24 个仍不确定的专精

这些专精不是没有检查，而是至少有一个会使静态提示误导玩家的未解决问题：

- 死亡骑士：鲜血（250）、邪恶（252）
- 恶魔猎手：复仇（581）、吞噬（1480）
- 德鲁伊：平衡（102）、野性（103）、守护（104）、恢复（105）
- 唤魔师：湮灭（1467）、恩护（1468）
- 猎人：兽王（253）
- 法师：奥术（62）
- 武僧：酒仙（268）、织雾（270）
- 圣骑士：神圣（65）、防护（66）
- 牧师：神圣（257）
- 潜行者：狂徒（260）、敏锐（261）
- 萨满祭司：恢复（264）
- 术士：痛苦（265）、恶魔（266）、毁灭（267）
- 战士：狂怒（72）

代表性反证：

- [Dreamgrove 野性 12.1 指南](https://dreamgrove.gg/blog/feral/compendium)明确写着不要遵循固定 Stat Priority，并预告 8 月 17 日才补完整团本和地下城细节。
- 生存猎人和火焰法师在 8 月 12 日的新 Method 页面中出现了新的内容维度冲突，因此没有从 8 月 11 日候选升级。
- 三系术士仍未收敛：痛苦只稳定到前两项，恶魔有三套口径，毁灭连第一属性是精通还是急速都冲突。
- 狂怒战士由同一作者维护的两个当前页面仍给出不同第一属性，不能任选一边。
- 坦克和治疗专精普遍需要先说明“生存、输出或治疗吞吐”的目标；把不同目标压成单行会制造错误确定性。

## 与 2026-08-11 记录相比的变化

- 浩劫恶魔猎手：新增/更新的多条独立作者证据继续一致，升级为“资料就绪、时间阻挡”。
- 惩戒圣骑士：新增为“资料就绪、时间阻挡”。
- 增辉唤魔师、刺杀潜行者：证据更新、置信度提高，但仍未跨过全部生产门槛。
- 生存猎人、火焰法师：新页面增加冲突，不能沿用旧候选的完整四项顺序。
- 增强萨满祭司：旧 Season 1 的 Stormbringer“急速第一”分支已过时；当前同一作者链倾向两树统一为精通≈急速。
- 三系术士：8 月 12–13 日资料变新，但冲突没有消失。

## 最快安全更新路线

1. 2026-08-18/19 开季调优上线后，先复核浩劫和惩戒；若排序未变，可考虑只显示通过验证的专精，而不是等待 40/40 后一次性全开。
2. 2026-08-20 至 2026-08-25 用首周团本/M+资料复核 14 个候选，并更新每个 `spec × hero build × content` 单元。
3. 2026-08-26 和 2026-09-02 的计划调优后，只重审受改动的专精；资料时间早于热修时间的一律失效。
4. 若采用“已验证专精先行”，需要把现在的全局布尔闸门改为逐专精有效期；未验证专精继续隐藏。该行为变更应单独实现和测试，不能通过打开当前全局闸门完成。

在上述复核完成前，生产数据仍是 2026-06 的 12.0.7 / Season 1 表，`Config.STAT_PRIORITY_DATA_CURRENT=false` 必须保持不变。
