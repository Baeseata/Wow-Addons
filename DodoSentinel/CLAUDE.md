# DodoSentinel — 项目入口

> Entombed Sentinels「数字游戏」的报到、展示与人工打标工具。
> **2026-08-24：P0 探针期，不是正式插件。** 先读本文，再读 `PROBE-PLAN.md`；实测填 `TEST-RESULTS.md`。

## 1. 范围与事实边界

| 项 | 值 |
|---|---|
| DungeonEncounterID | **3445**（mapID 3004 / journalEncounterID 2874） |
| 机制 debuff | Helical Toxins **1284590** |
| 上球施法 | Vitriolic Stasis **1284588** |
| 史诗额外机制 | Shifting Protovenom **1296878 / 1296880** |

- 规则是两人的绿球合计为 4；1 绿与 3 绿互配，2 绿互配。
- **“10 人 2 绿、5 人 3 绿、5 人 1 绿”只是预期/观测假设**，不得把人数或“绿总数 40”硬编码成机制不变量。
- `expectedReporterCount = 5` 只能是可配置团队预期。到达数是事件数，不等于唯一玩家数。
- 受限遭遇战中不读球数、不自动认人、不自动打标；插件只渲染，团长完成每次硬件点击。

## 2. 主数据流

1. 战斗外按当前 raid roster 快照，把每个 `raidN` 映射为 `<小队>-<队内位次>`，为玩家准备 `/raid` 宏。
2. 1 绿玩家各自按宏；团长端同时监听 `CHAT_MSG_RAID` 与 `CHAT_MSG_RAID_LEADER`。
3. secret payload 只安全渲染，并作为不透明贴图地址输入；Lua 不解析、比较、筛选或去重。
4. 团长依据视觉格，点击预建的 secure `raidN` cell，依次设置 1–5 号标记。
5. 轮次结束逐单位点击清除，或留到下一轮覆盖；不存在“一次点击只清这五人”。

`/raid` 是受限遭遇战中允许的团队内宏聊天路线，但有频率/同副本条件；目标首领端到端仍按探针计划实测。

## 3. Secret 渲染铁律

- 聊天 `text`、`playerName`、`guid` 都按 secret 对待；不得用 `UnitTokenFromGUID(secretGuid)` 恢复 raid 地址。
- 玩家输入先经 `C_StringUtil.EscapeQuotedCodes`，再交给 `SetText` / `SetFormattedText`；固定行高列宽。
- 禁止 Lua 拼接、模式匹配、相等判断、表索引、排序、去重和基于 payload 的业务分支。
- 重复宏各占一行；明文到达序号只表示事件顺序。清理文本用官方复位路线，不把沾 secret aspect 的对象放入 secure pool。
- 职业色是后续兼容性探针，不是 P0 前提。

贴图路线固定为：

```text
C_StringUtil.WrapString(secretCode, prefix, suffix)
→ success = Texture:SetTexture(path)
→ Texture:SetAlphaFromBoolean(success, 1, 0)
```

- 不在 Lua 中拼接路径或判断 `success`；每条到达使用独立预建 overlay，才能累积五条。
- 只 ship 合法坐标资源；无效路径必须透明，不能出现 placeholder 或全格误亮。
- 聊天 payload、玩家身份和 texture success 可能是 secret，**绝不写 SavedVariables**；仅人工看屏幕并填结果。

## 4. SecureMarkGate 铁律

- 五名测试者必须转换成 **RAID**（party 没有 `raid1`…`raid5`）；点击者须有团长/助理权限。
- controller 显式使用 `SecureHandlerBaseTemplate`；cell 使用 `SecureActionButtonTemplate`，战斗外静态绑定 `raidN`。
- `SecureHandlerWrapScript(cell, "OnClick", controller, prebody)` 中 `self`=cell、`control`=controller；共享 `n` 放 controller，marker 放 cell。
- `RegisterForClicks("AnyDown")` 与 `useOnKeyDown = true` 成对；只让 `LeftButton` 推进 1→5，右键清除不推进。
- cell 必须具备完整属性：`*type1=raidtarget`、`*action1=set`、`*type2=raidtarget`、`*action2=clear`。
- 计数器无法可靠回读真实标记，是开环状态；必须有 secure Reset、Back/Retry、指定 Next 1–5 控件。
- 第 4/5 次是否受 3-unit 标记节流影响是 **P0 核心未知项**；源码旁证不能替代 RAID 真机录像。

## 5. 标记语义与已删除 fallback

- 单位只能有一个 raid target icon；设置 1–5 会覆盖原 6–8，清除后不会恢复旧标记。
- 选择性清五个单位需要五次硬件点击；`clear-all` 会连坦克/击杀顺序的 6–8 一起抹掉，不进默认主流程。
- 禁止“20 坐标静态均分到 1–5，让玩家各自标自己”：恰好各一个号的概率
  `4^5 / C(20,5) ≈ 6.60%`，约 93.4% 会撞号，且普通团员通常无权限。
- 若单客户端五连失败，只另立“团长+助理 3/2”探针；先验权限、顺序、同步和 marker steal，不直接实现。

## 6. Roster、UI 与生命周期

- OOC `GROUP_ROSTER_UPDATE`：重建坐标、宏、标签和 secure 映射。
- 战斗中 roster 变化：快照立刻 stale；普通 blocker 拦住点击，整轮 fail-closed；脱战后再重建。
- protected click layer 战斗外预建并保持就位，不在战斗中普通 Show/Hide。
- grid/panel/overlay/blocker 是独立普通 sibling，分别锚 `UIParent` 固定坐标，不挂 protected 子件/锚点链。
- 非中场隐藏普通视觉层并用 blocker 防误点；中场只切普通视觉层/blocker。
- `ENCOUNTER_START/END` 负责 encounter 3445 + 史诗难度的外层重置；真实标记只提醒人工处理，绝不自动清。
- MVP 中场开始/结束由团长手动。Timeline 的 spellID/name 可能 secret；Stasis 与 Shifting 可同为 20 秒，
  且 Stasis Finished 更像阶段开始、通用 EVENT_REMOVED 不是阶段结束。P0 后另做 TimelineProbe。

## 7. 证据与出口

- 明文命令、counter 迁移等才可写 `DodoSentinelProbeDB`；运行后 `/reload` 落盘，`/dsprobe copy` 复制查看。
- SavedVariables 日志不能证明屏幕真的上了标、渲染了 secret 或隐藏了缺图；这些必须人工截图/录像。
- P0 出口：五连 1–5、右清不推进与纠偏控件、双聊天事件、secret 文本渲染、合法/无效贴图路由均有实证。
- 未执行项目保持未执行；第三方插件、FrameXML 和源码只算旁证。完整步骤与裁决见 `PROBE-PLAN.md`。

## 8. 分发

- OMEN 在 `C:\Users\Doodo\Code\Wow-Addons\DodoSentinel\` 开发、commit、push；HOME 临时拉仓再复制整目录到 live AddOns。
- live AddOns 不是 Git tree/junction；新插件文件夹首次部署后必须**完整重启客户端**，`/reload` 不会重新扫描目录。
- 自用探针不打 release tag；CRLF/LF 比对忽略行尾差异。

## 9. 本仓路由

- secure/protected：`DodoGrid/Core.lua`、`DodoGrid/Dispel.lua`
- secret 探针与 sink：`DodoProbe/CLAUDE.md`、`DodoNameplate`
- 私有/通用光环边界：`DodoLura/CLAUDE.md`
