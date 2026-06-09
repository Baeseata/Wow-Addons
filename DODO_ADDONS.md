# Dodo Addons - WoW Retail (The War Within / 至暗之夜)

> 个人自用魔兽世界插件集合。所有 Dodo 插件由 Baeseata 维护，使用粉色 D 图标 (Dodo.tga)。
> GitHub: https://github.com/Baeseata/Wow-Addons
> 游戏版本: 正式服 至暗之夜 (Midnight) 12.0.5
> Interface: 120005

---

## 插件总览

| 插件 | 用途 | 代码行数 | 核心功能 |
|------|------|----------|----------|
| DodoAirdrop | 战争模式空投追踪 | ~322 | TalkingHead 钩子、分地图记录、小地图按钮 |
| DodoAirdropDebug | 空投事件调试 | ~232 | 事件日志、叠加层显示、聊天输出 |
| DodoAuction | 拍卖行价格追踪与发布 | ~1116 | 1%均价计算、趋势分析、自动发布 |
| DodoInspect | 目标玩家信息显示 | ~301 | 装等/种族/职业/专精/英雄天赋 |
| DodoItemLevelOverlay | 装备/背包装等显示 | ~533 | 品质分级着色、BOE检测、中文部位标签 |
| DodoMap | 坐标显示与标记 | ~613 | 实时坐标、坐标输入标记、设置面板 |
| DodoNumbers | 战斗数字自定义 | ~523 | CVar 管理、缩放/暴击/行为控制 |
| DodoQuest | 任务自动化 | ~471 | 自动接交任务、最优奖励选择、Shift暂停 |
| DodoStatHUD | 属性显示面板 | ~815 | 实时属性、趋势箭头、套装名显示 |
| DodoUnholy | 邪DK食尸鬼提醒 | ~357 | 专精检测、宠物追踪、可配置警告 |

**外部插件**: Plater (第三方姓名版插件，不做修改)

---

## 各插件详细说明

### DodoAirdrop (v0.3.0)
- **SavedVariables**: DodoAirdropDB
- **命令**: `/dodoairdrop`, `/dodoad`
- **功能**: 监控战争模式空投事件，通过挂钩 TalkingHeadFrame 系统检测空投通知
  - 追踪 4 张地图: 永歌森林、祖阿曼、哈籁恩达尔、虚影风暴
  - 监听 NPC: 兹尔丹、维迪奥斯
  - 记录每张地图上次空投时间，显示绝对时间和相对时间
  - 小地图按钮(Shift+左键拖动)，团队警告框和音效通知
  - 60秒去重窗口，50ms 延迟读取 TalkingHead 数据

### DodoAirdropDebug (v0.1.0)
- **SavedVariables**: DodoAirdropDebugDB
- **命令**: `/dadbg on|off`, `/dadbg overlay on|off`, `/dadbg brief|full`, `/dadbg last|clear`
- **功能**: DodoAirdrop 的调试伴侣插件
  - 监控世界事件 (PLAYER_ENTERING_WORLD, ZONE_CHANGED, TALKINGHEAD_REQUESTED 等)
  - 挂钩 TalkingHeadFrame.PlayCurrent 捕获数据
  - 最多存储 100 条日志，900x150 叠加层显示(8秒自动隐藏)
  - 支持简略/详细模式切换

### DodoAuction (v1.0)
- **SavedVariables**: DodoAuctionDB
- **命令**: 通过 UI 操作
- **功能**: 拍卖行价格历史追踪和快捷发布工具
  - 追踪商品价格(1%最低加权均价)，每件商品最多 100 条数据
  - 价格历史图表，支持 1/7/30 天或全部时间范围筛选
  - 线性回归趋势箭头 (▲▼)，基于最近 ≤5 个数据点
  - 右键背包物品搜索拍卖行并追踪新商品
  - 自动发布功能，使用历史偏好单价
  - 商品品质星级指示器 (★)
  - 可排序滚动列表界面

### DodoInspect (v1.0.0)
- **命令**: `/dodoi on|off`, `/dodoi size 16`, `/dodoi twolines on|off`, `/dodoi offset 0 16`
- **功能**: 在目标姓名版上方显示详细玩家信息
  - 显示装等(取整)、种族、职业、专精、英雄天赋
  - 0.6秒检查冷却防止刷屏
  - 门控显示:装等和专精都就绪才显示(英雄天赋可选)
  - 支持双行布局、自定义字号(10-64)和偏移
  - 使用 C_PaperDollInfo, C_Traits, C_ClassTalents API

### DodoItemLevelOverlay (v1.0)
- **功能**: 在角色面板和背包装备图标上叠加信息
  - **装备栏**: 左上角显示装等，按品质分级着色
  - **背包**: 左上装等、左下BOE标签或套装名、右上中文部位标签
  - 品质颜色梯度: 219白 / 220-230绿 / 231-243蓝 / 244-256紫 / 257-269橙 / 270+红
  - 中文部位标签: 头、肩、胸、主、副 等
  - 支持合并和分离背包UI
  - 通过钩子自动更新

### DodoMap (v1.0.0)
- **SavedVariables**: DodoMapDB
- **命令**: `/dodomap`
- **功能**: 实时玩家坐标显示和坐标标记
  - 每100ms更新坐标，1位小数精度
  - 可拖动坐标显示框(解锁后可移动)
  - 弹出对话框输入 X/Y 坐标设置路径点
  - 坐标验证 (0-100 范围)
  - 使用暴雪原生路径点系统
  - 小地图按钮(Shift+左键拖动)
  - 设置面板集成，字号(8-32)、位置持久化

### DodoNumbers (v1.1.0)
- **SavedVariables**: DodoNumbersDB
- **功能**: 浮动战斗文字(FCT)自定义
  - 通过 CVar 调整文字缩放、暴击放大、存在时间、浮动方向和水平散布
  - 支持 Retail 12.0+ v2 CVar 和旧版 CVar 双兼容
  - 首次加载时捕获原始 CVar 值用于还原
  - 选项面板带实时预览
  - 宠物伤害、DoT伤害、未命中/闪避/招架显示开关
  - 浮动模式: 上(1)、下(2)、弧形(3)
  - 一键还原按钮
  - **文件结构**: Core.lua (CVar管理) + Options.lua (UI面板)

### DodoQuest (v1.2.0)
- **SavedVariables**: DodoQuestDB
- **功能**: 轻量级任务自动化
  - 自动接受/提交任务
  - 自动处理单选项对话
  - 多奖励选择时自动选最高售价物品
  - 按住 Shift 暂停自动化
  - 双 API 支持: C_GossipInfo 新 API + 旧版函数
  - 处理多种任务UI: QUEST_DETAIL, QUEST_PROGRESS, QUEST_COMPLETE, QUEST_GREETING
  - 异步物品数据加载等待
  - 选项面板: 自动化开关和最优奖励开关

### DodoStatHUD (v1.1.0)
- **SavedVariables**: DodoStatHUDDB
- **功能**: 实时角色属性 HUD 显示
  - 显示当前套装名、主属性(相对基线百分比)、暴击、急速、精通、全能、移速
  - 属性变化趋势箭头 (▲/▼)，可配置持续时间后自动隐藏
  - 每项属性可独立显示/隐藏
  - 自定义颜色选择器
  - 字号调整(8-40)，可拖动+锁定
  - 主属性基线保存/重置功能
  - 每0.2秒刷新
  - 使用 C_PaperDollInfo, C_EquipmentSet API

### DodoUnholy (v1.1.0)
- **SavedVariables**: DodoUnholyDB
- **命令**: `/dodounholy config`, `/duh config`
- **功能**: 邪恶死亡骑士食尸鬼提醒
  - 检测邪DK专精 (spec ID 252)
  - 宠物不存在或死亡时显示 "宝宝没啦~~" 警告
  - 仅地面状态显示(排除骑乘、载具、飞行点、死亡)
  - 可配置: 开关、字号(8-72)、垂直位置(-500~500)
  - 选项面板带实时预览

---

## 通用技术模式

- **语言**: Lua (WoW API)，所有UI文本中文本地化
- **整合包结构**: 父插件 `Dodo`（`Dodo/` 目录）提供共享素材 `Dodo/Media/` 与公共库 `_G.Dodo`（`Shared.lua`，含 `Dodo.icon` / `Dodo.Media` / `Dodo.CopyDefaults` / `Dodo.Clamp` / `Dodo.Print` / `Dodo.Money` 等）；各子插件 TOC 加 `## Group: Dodo`，在插件列表中归入「Dodo 插件包」之下
- **图标**: 粉色 D 图标 `Dodo.tga`，统一放在共享目录 `Dodo/Media/`，各子插件复用同一份（不再各存副本）
- **数据持久化**: SavedVariables + 深拷贝机制保护已有数据
- **命名规范**: 插件名以 `Dodo` 开头，全局变量/函数以插件名为前缀
- **API 兼容**: 多数插件同时支持 12.0 新 API 和旧版 API
- **错误处理**: pcall 包裹、安全类型转换
- **设置面板**: 使用 Settings.RegisterCanvasLayoutCategory 集成到游戏设置
- **小地图按钮**: 极坐标定位，Shift+左键拖动

---

## 开发计划 & 备注

- 所有 Dodo 插件为个人自用，按需迭代
- 新插件命名继续以 `Dodo` 开头，TOC 加 `## Group: Dodo` 归入整合包，复用 `Dodo/Media/Dodo.tga` 图标与 `_G.Dodo` 公共库
- Plater 为外部第三方插件，不做修改
- 本地文件夹为准，GitHub repo 可能不是最新状态
