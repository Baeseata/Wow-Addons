# DodoInspect 12.1 属性优先级研究记录

日期：2026-08-11

版本：Midnight 12.1 / Season 2 预赛季周

结论状态：暂不恢复显示，`Config.STAT_PRIORITY_DATA_CURRENT` 继续保持 `false`

## 本轮范围

- 审计全部 40 个专精。
- 检查公开可访问的 12.1 攻略、职业社区网站、社区导出的文档/GitHub FAQ、论坛和 PTR 反馈。
- 按作者去重：同一作者在社区站、Wowhead、Icy Veins、Method 等处的内容只算一条证据链。
- 没有运行 SimulationCraft/Raidbots，也没有用日志中的装备分布反推因果。
- Discord 邀请页只能证明社区存在；无法公开核验的置顶消息不算证据。
- 匿名 PTR 帖只能作线索，不能单独支持生产数据。

## 2026-08-11 决策

1. 新发现的社区资料没有增加任何“可无争议发布”的专精。
2. 综合所有已审计资料，保留 5/40 个**粗粒度候选**，供下次复核；它们不等于可以重新开启 UI。
3. 若要求“至少一份独立、明确标注 12.1 的职业社区确认，并解决英雄树、团本/M+和阈值问题”，当前为 **0/40**。
4. [Season 2 于 2026-08-18 开始](https://worldofwarcraft.blizzard.com/news/24294369/the-shadows-deepen-midnight-season-2-begins-august-18)。至少等赛季开启和第一轮职业调整后复查，再决定是否更新生产 Lua 表。

## 5/40 个粗粒度候选

置信度只评价“作为通用提示的排序”，不代表某个角色、装备组合或首领的精确最优值。

| specID | 专精 | 二级属性顺序 | 置信度 | 关键限制与证据 |
|---:|---|---|---:|---|
| 577 | 浩劫恶魔猎手 | 暴击 > 精通 > 急速 > 全能 | 9/10 | 当前最强候选；不同作者的 [Icy Veins](https://www.icy-veins.com/wow/havoc-demon-hunter-pve-dps-stat-priority)、[Wowhead](https://www.wowhead.com/guide/classes/demon-hunter/havoc/stat-priority-pve-dps)、[Method](https://www.method.gg/guides/havoc-demon-hunter/stats-races-and-consumables) 一致，未发现英雄树或目标数翻转。 |
| 1473 | 增辉唤魔师 | 精通 > 暴击 ≈ 急速 > 全能 | 8/10 | [Icy Veins](https://www.icy-veins.com/wow/augmentation-evoker-pve-dps-stat-priority) 与 [Wowhead](https://www.wowhead.com/guide/classes/evoker/augmentation/stat-priority-pve-dps) 大体一致。精通约 1840 评级前明显领先，之后与暴击/急速趋近而不是固定保持大差距。 |
| 255 | 生存猎人 | 精通 > 暴击 ≈ 急速 > 全能 | 8/10 | [Icy Veins](https://www.icy-veins.com/wow/survival-hunter-pve-dps-stat-priority) 与 [Wowhead](https://www.wowhead.com/guide/classes/hunter/survival/stat-priority-pve-dps) 的粗粒度结论兼容；Pack Leader 为暴击≈急速，Sentinel 为暴击略高于急速。社区机制分析与 Icy Veins 同作者，不增加独立性。 |
| 63 | 火焰法师 | 急速 > 精通 > 全能 > 暴击 | 8/10 | 当前 [Icy Veins 12.1](https://www.icy-veins.com/wow/fire-mage-pve-dps-stat-priority) 与 [Wowhead](https://www.wowhead.com/guide/classes/mage/fire/stat-priority-pve-dps) 的两棵英雄树排序相同；除暴击通常垫底外，其余属性实际很接近。缺少新鲜的独立社区文档。 |
| 259 | 刺杀潜行者 | 暴击 > 急速 > 精通 > 全能 | 8/10 | [Icy Veins](https://www.icy-veins.com/wow/assassination-rogue-pve-dps-stat-priority) 与 Whispyr 的 [Wowhead](https://www.wowhead.com/guide/classes/rogue/assassination/stat-priority-pve-dps)/[Method](https://www.method.gg/guides/assassination-rogue/stats-races-and-consumables) 结论兼容；后两者是同一作者链，社区没有新增独立确认。 |

## 社区资料带来的主要反证

这些资料有价值，但价值主要是证明某些专精不能被压成一条静态顺序。

| 专精/社区 | 当前社区结论 | 对生产数据的影响 |
|---|---|---|
| 鲜血死亡骑士 / [Kyrasis 12.1 文档](https://docs.google.com/document/d/1FJlB1T8ijaQLjY_cihyoyhLoi6lYRnT-N-ipVFCLidE/edit?usp=sharing) | Deathbringer 与 San'layn 不同；团本/M+、纯减伤、纯伤害目标也会翻转属性顺序。 | 不能使用单一默认顺序；必须先定义坦克属性提示的目标口径。 |
| 野性德鲁伊 / [Dreamgrove 12.1](https://dreamgrove.gg/blog/feral/compendium) | 明确建议不要遵循固定 Stat Priority，完整团本/M+建议仍在更新。 | 不生成静态顺序。 |
| 恩护唤魔师 / [Spiritbloom.Pro](https://spiritbloom.pro/preservation/quick-guide) | 同一 Flameshaper：团本为精通 > 暴击 ≥ 急速 > 全能；M+ 为精通 > 急速 > 暴击 > 全能。 | 必须拆团本/M+；不能列入通用候选。 |
| 踏风武僧 / [Peak of Serenity 12.1](https://www.peakofserenity.com/tww/windwalker/pve-guide/) | 急速 = 暴击 = 精通 >>> 全能；前三会随装备和天赋互相领先。 | 最多显示三项并列集群；作者同时维护商业攻略，不能当额外独立来源。 |
| 神圣圣骑士 / [WingsIsUp S2](https://wingsisup.com/quickview) | 先约 25% 急速；之后团本偏精通，M+ 根据高层生存、治疗或填充在全能/暴击/精通间选择。 | 需要阈值、内容和目标三层语境，不能显示单行通用顺序。 |
| 暗影牧师 / [Warcraft Priests S2 FAQ](https://github.com/WarcraftPriests/discord/blob/main/shadow-faq/threads/gearing.md) | 粗略为急速 ≥ 精通 > 暴击 > 全能，但 Archon/Voidweaver、单体/AoE分别有不同目标区间，且明确不是硬上限。 | 现有 Lua schema 无法完整表达目标区间；FAQ 提交者也是 Icy Veins 作者，不算独立确认。 |
| 三系术士 / [Kalamazi](https://www.kalamazi.gg/guides/Midnight) | [痛苦](https://www.kalamazi.gg/guides/affliction)、[恶魔](https://www.kalamazi.gg/guides/demonology)、[毁灭](https://www.kalamazi.gg/guides/destruction) 都给出当前排序，但分别与其他 12.1 来源在末两位、急速阈值或第一属性上冲突。 | 三系都保持隐藏，等待冲突消解。 |

## 其余 35/40 个未批准专精

下列专精不是“没有调查”，而是截至本日期至少存在来源冲突、英雄树/内容/目标差异、阈值未解决，或没有可公开核验的独立 12.1 资料：

- 死亡骑士：鲜血、冰霜、邪恶
- 恶魔猎手：复仇、吞噬
- 德鲁伊：平衡、野性、守护、恢复
- 唤魔师：湮灭、恩护
- 猎人：兽王、射击
- 法师：奥术、冰霜
- 武僧：酒仙、织雾、踏风
- 圣骑士：神圣、防护、惩戒
- 牧师：戒律、神圣、暗影
- 潜行者：狂徒、敏锐
- 萨满祭司：元素、增强、恢复
- 术士：痛苦、恶魔、毁灭
- 战士：武器、狂怒、防护

## 下次复查门槛

每个准备写入 `Data/StatPriority.lua` 的 `spec × hero build × content` 单元都应满足：

1. 至少两位独立作者的当前 12.1/Season 2 资料；同作者跨站转载只算一份。
2. 明确区分团本/单体与 M+/AoE；坦克和治疗还要明确生存、吞吐或伤害目标。
3. 两棵常用英雄树都已核验；若排序不同，必须分别写入 `builds`。
4. tie 只能在来源明确表示相近时使用，不能把来源冲突伪装成 `=`。
5. soft cap 必须说明百分比/评级口径、适用构筑和是否为软上限；不确定时不写。
6. 若最新职业热修晚于资料更新时间，该单元自动失效并重新审计。

建议复查窗口：2026-08-18 Season 2 开启后，优先在 2026-08-20 至 2026-08-25 检查上述公开文档及职业热修；在 40/40 未达到生产标准前，保持全局 fail-closed。
