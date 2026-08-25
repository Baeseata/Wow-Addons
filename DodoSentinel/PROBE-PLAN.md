# DodoSentinel P0 探针计划

> 版本日期：2026-08-24。目标是用最小代码回答人工闭环能否在 WoW 12.1 真机成立。
> 不验正式样式、配置、职业色、自动 Timeline 或发布流程。

## 1. 探针与裁决顺序

| 顺序 | 探针 | 问题 | 失败影响 |
|---|---|---|---|
| P0-A | SecureMarkGate | 同一有权限客户端快速点击五个 `raidN`，能否依次上 1–5？ | 主方案暂停，才考虑团长+助理 3/2 |
| P0-B | SecretChat | 遭遇战 `/raid` 宏能否到达；RAID/RAID_LEADER 能否只渲染？ | 报到入口不成立 |
| P0-C | TextureRoute | secret 坐标能否只点亮对应 overlay；缺图是否透明？ | 自动亮格退回纯文本肉眼定位 |
| P0-D | CounterRecovery | 右清不推进；Reset/Back/指定 Next 能否恢复开环计数器？ | 偶发失败后无法人工校准 |
| P0-E | RosterStale | OOC 重建、战斗中 roster 变化能否 fail-closed？ | 正式实战前不得放行 |

当前首批代码验证 A–D；E 是核心 gate 通过后的集成探针。A 失败时仍完成 B/C 的技术记录，
但不开始正式产品 UI。

## 2. 证据边界

### 2.1 可持久化的明文证据

探针只把明确为明文的操作记录写入 `DodoSentinelProbeDB`，例如：

- probe 版本、客户端 build（若 API 明文可得）和测试批次时间；
- 用户主动执行的硬编码 probe 命令；
- controller counter 的明文迁移；
- 明文事件计数/探针状态，不附带聊天 payload 或玩家身份。

流程：运行探针 → `/reload` 让 SavedVariables 落盘 → `/dsprobe copy` 打开可复制的明文摘要 →
把摘要贴到 `TEST-RESULTS.md` 对应批次。

### 2.2 绝不持久化、只人工观察的证据

- 聊天正文、发送者、GUID 或任何玩家身份；
- `Texture:SetTexture` 的 success 及由它传播的状态；
- 屏幕上的 secret 文本和 texture route 结果；
- 真实团队标记的回读值。

这些可能是 secret，不能写 SavedVariables、聊天、剪贴板导出或调试表。只用人工截图/录像，
再由测试者把“看到了什么”填入结果模板。

**日志不能替代视觉结论。** counter 日志显示 1→5，只证明软件计数器走了五步；不能证明
第 4/5 个真实标记成功。`/dsprobe copy` 也不得输出任何 secret-derived value。

## 3. 测试前准备

### 3.1 部署与版本

- [ ] 记录待测 Git commit、WoW build、区域/语言、DodoSentinel 版本。
- [ ] 把 `DodoSentinel` 整目录复制到 live AddOns。
- [ ] 首次新增插件目录后**完整重启客户端**；`/reload` 不会重新扫描 AddOns 目录。
- [ ] 登录后确认插件加载，无启动 Lua error；再做一次 `/reload` 验证 SavedVariables 可落盘。
- [ ] 执行 `/dsprobe copy`，确认只包含允许的明文摘要。
- [ ] 开启错误收集并准备连续屏幕录像；真实标记和 secret 渲染以录像为主证据。

### 3.2 命令速查

- `/dsprobe show|hide`：战斗外切换整组探针；战斗中隐藏请求会先用普通 blocker 封锁，离战后再隐藏 protected 层。
- `/dsprobe chat on|off`：开启/关闭双团队聊天事件监听；**默认关闭，B/C 的 secret 路线前必须先 `chat on`**。
- `/dsprobe texture <坐标>`：只用于 C1 明文资源 smoke，例如 `/dsprobe texture 1-1`。
- `/dsprobe reset|back|next 1-5`：仅战斗外校准 counter；战斗中必须点面板上的 protected 纠偏键。
- `/dsprobe clear`：清普通文本/overlay；只在脱战时归零 counter，永远不改变真实团队标记。
- `/dsprobe log|copy|logclear`：查看条数、打开复制框、清空旧日志并留一条固定清理记录；需要落盘时先 `/reload` 再 `copy`。

每批先 `/dsprobe show`；B/C 前再执行 `/dsprobe clear`、`/dsprobe chat on`。命令日志只记固定动作名，
不记原始参数或任何聊天内容。

### 3.3 团队条件

- [ ] 至少五名测试者，队伍已**转换成 RAID**，确认 `raid1`…`raid5` 存在。
- [ ] 指定团长执行主测试；另指定一名助理，仅用于权限/3+2 备选探针。
- [ ] 聊天实战探针时，所有参与者都在同一副本实例。
- [ ] 准备普通成员与团长各一条宏，例如 `/raid 1-1`、`/raid 1-2`。
- [ ] 每轮前截图 raid roster、当前 1–8 标记占用和 probe counter。

### 3.4 重复与判定纪律

- 每个 case 至少重复 3 轮；快速五连分别测正常手速与尽可能快的人类连点。
- 目标环境是 encounter 3445 史诗实战。城里/OOC 结果只算 smoke，不代替遭遇战结果。
- 不为了自动断言而读取、比较、打印或持久化 secret。
- 无系统错误不等于通过；marker throttle 可能静默失败。

**A1/A2 的每轮五连必须彻底复位，不能直接在原标记上重跑。** `action=set` 发现单位已经是
目标号时会跳过 `SetRaidTarget`；若不复位，后续轮次会“看起来全对”却根本没压到限流。
每轮结束后：

1. 右键逐单位清除 1–5，肉眼确认五人都已无标；不用 `clear-all`。
2. 清除本身也调用 `SetRaidTarget`，若静默失败就等待后重试，并单独记录清除失败。
3. 点 protected Reset（脱战可 `/dsprobe reset`），确认下一枚为 1。
4. 从**最后一次成功清除**起至少等待 10 秒，再开始下一轮并保持连续录像。

## 4. P0-A — SecureMarkGate

团队标记编号视觉对照：1 星、2 圆、3 钻、4 三角、5 月。

### A1. OOC smoke

**前置**：RAID，团长权限，脱战；Reset；确认**全团** 1–5 均未占用。

**步骤**：按顺序左键 raid1、raid2、raid3、raid4、raid5。

**通过**：肉眼分别看到 1、2、3、4、5；无重复、偷标或缺失。

**失败**：任一单位无标、编号错位、已有单位被意外清除，或出现限制错误。

**证据**：连续录像 + 点击后截图；DB 摘要只能辅证 counter 迁移。

### A2. 遭遇战 3-unit throttle 压力测试（决定性）

**前置**：活动遭遇战，其他条件同 A1；关闭会抢 1–5 的其他工具。

**步骤**：

1. 正常连续手速点五格，重复 3 轮。
2. 最快可控的人类连点点五格，重复 3 轮。
3. 每轮重点人工观察第 4、5 击，并记录 counter 是否已前进。

六轮之间全部执行 §3.4 的逐单位清标、Reset 与至少 10 秒等待；任一轮未清干净不得计入。

**通过**：6 轮均完整显示 1–5，肉眼状态与 counter 一致。

**失败**：任何一轮第 4/5 次被拒、静默缺失，或 counter 前进但图标没上。

一次可复现失败即判单客户端五连不可靠；不能用“大多数时候成功”放行实战。

### A3. 左键推进、右键不推进

1. Reset；左键 raid1，确认 1 号。
2. 右键 raid1，确认清除。
3. 左键 raid2。

**通过**：raid2 得到 2 号。若得到 3、1 或无标，失败。

### A4. 单位单标记语义

1. 预先给 raid1 放 6–8 中一个并截图。
2. Reset 后左键 raid1，再右键 raid1。

**通过（危险语义确认）**：1 号覆盖旧 6–8；右清后单位无标，旧 6–8 不恢复。

### A5. 权限边界

分别让普通成员、助理、团长设置并清除一个标记，记录成功/静默/系统错误。
普通成员失败不影响主方案；助理结果只决定 3/2 fallback 是否值得另立探针。

## 5. P0-B — SecretChat

### B1. 两类聊天事件

**前置**：真实活动团队遭遇战，发送者都在同一副本。优先 3445 史诗；其他首领只能先验聊天闸。

先执行 `/dsprobe clear`、`/dsprobe chat on`，并确认面板显示“监听：开”。

1. 普通成员按 `/raid 1-1`。
2. 团长按 `/raid 1-2`。
3. 两人各重复一次。

**通过**：界面出现 4 个独立到达行；普通成员覆盖 `CHAT_MSG_RAID`，团长覆盖
`CHAT_MSG_RAID_LEADER`；名字/坐标可见且无 Lua error。

**失败**：宏在遭遇战被拦、只收到一种事件、渲染空白/报错，或实现检查 secret。

事件名和明文计数可进 DB；payload、身份和可见 secret 文本不得进入 DB/copy 摘要。

### B2. 重复输入诚实展示

同一玩家连续按两次同一宏。

**通过**：新增两行、到达序号递增；UI 不宣称它们来自两个唯一玩家。

**失败**：Lua 层按正文/发送者去重或分类。

### B3. markup 转义

在不影响团队沟通的测试环境，发送一条含 `|` 控制字符的测试消息。

**通过**：只显示转义后的字面内容，不执行颜色、贴图、链接 markup，不污染相邻行。

## 6. P0-C — TextureRoute

### C1. 明文资产 smoke

脱战依次执行 `/dsprobe texture 1-1`、`/dsprobe texture 3-2`、`/dsprobe texture 4-5`；
每次前先 `/dsprobe clear`，避免上一张 fixture 干扰单格判断。

**通过**：每个输入只显示对应 fixture。此步只验证资源/路径；明文成功不能证明 secret 路由成功。

### C2. secret 路由与累积

保持 `/dsprobe chat on`，先执行 `/dsprobe clear` 清掉 B1/B2/B3 残留；三名玩家分别发送
`1-1`、`3-2`、`4-5`，确认三格后再追加两个不同合法坐标，扩展到五格。

**通过**：先三格、后五格分别同时可见；不是只剩最后一格，也没有全格亮。

**失败**：overlay 被复用覆盖、路径报错，或必须在 Lua 中比较/索引 secret 才能工作。

可见格和 texture success 都只人工记录，绝不写 DB。

### C3. 无效路径与 placeholder

分别通过 secret 聊天路线发送 `9-9`、`abc` 和含 markup 控制字符的无效值；**每个输入前先
`/dsprobe clear`**，确保判断的是本条无效输入，而不是上一轮残留。

**通过**：对应 overlay 完全透明，不出现问号、默认纹理、绿色方块或全 grid 亮。

**失败**：任何无效值产生可见 placeholder；TextureRoute 不得上线。

### C4. 普通视觉清屏

五个合法 overlay 可见后执行 `/dsprobe clear`。

**通过**：普通 overlay/text 全消失；真实团队标记不被自动改变。

## 7. P0-D — CounterRecovery

这些控件必须在战斗限制下以硬件点击生效。

### D1. Reset

成功设置 1、2、3 → 点 Reset → 点新单位。**通过**：新单位得到 1。

### D2. Back/Retry

1. Reset 后前三击成功，再左键第 4 个目标，确认 counter 已到 4。
2. 若第 4 击本就失败，先等待至少 10 秒再进入下一步；若已成功，等待至少 10 秒后右键清掉
   该目标，肉眼确认 4 号消失且 counter 仍为 4。这样稳定模拟“动作没落地、开环计数器已前进”。
3. 点 protected Back/Retry，再左键同一目标。

**通过**：重试使用 4，不跳到 5；明文日志只辅证 counter 4→3→4，真实图标靠录像。

### D3. 指定 Next

依次指定 Next=5、2、4，每次点不同单位。**通过**：肉眼依次得到 5、2、4。

DB 可记录控件命令和 counter 迁移；真实图标仍靠录像判定。

## 8. P0-E — RosterStale（核心 gate 通过后的集成探针）

### E1. 战斗外重建

脱战交换小队、让一人离队再回队或改变 roster 顺序。

**通过**：短坐标、宏提示、`raidN` 标签按新快照重建；旧坐标不再标为当前。

### E2. 战斗中 fail-closed

在安全测试遭遇中触发 `GROUP_ROSTER_UPDATE`。

**通过**：显示 stale；独立 blocker 拦住 secure cells；不编辑宏/secure 属性；脱战后才恢复重建。

**失败**：继续允许旧映射点击，或战斗中修改 protected state 报错。

## 9. 目标首领生命周期（集成验收）

1. 非 3445 或非史诗：普通 panel/grid 不出现，blocker 保持。
2. 3445 史诗 `ENCOUNTER_START`：进入 armed，清普通视觉残留。
3. 团长手动“本轮开始”：显示普通视觉层、解除 blocker；secure click layer 早已预建。
4. 团长手动“本轮结束”：隐藏普通视觉层、恢复 blocker、清文本/overlay；不自动清真标记。
5. `ENCOUNTER_END` / wipe：外层重置并提示人工清标。

自动 Timeline 不属于本轮通过条件；另开 TimelineProbe 后再替换手动轮次按钮。

## 10. 裁决

### GO

- A1/A2/A3、B1–B3、C2/C3/C4、D1–D3 有录像/截图并通过。
- A4/A5 的危险语义与权限边界已记录。
- E1/E2 在正式实战前通过。

### CONDITIONAL GO

- SecureMarkGate 通过、TextureRoute 失败：保留纯文本/固定 grid 肉眼定位，不自动亮格。
- 单客户端五连失败、助理权限通过：只立项 3/2 双客户端新探针，不直接实现 fallback。

### NO-GO

- 遭遇战 `/raid` 宏无法端到端到达。
- 单客户端五连失败，且 3/2 路线没有可验证权限/同步模型。
- roster stale 无法阻断旧映射误点。

源码、FrameXML、第三方插件和 `DodoSentinelProbeDB` 都只是辅证；没有人工视觉证据的屏幕结果不得填“通过”。
