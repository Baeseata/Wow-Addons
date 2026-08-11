# DodoBricks - 开发简报 (read me first)

> 单人数字打砖块 (Ballz/Bricks n Balls 类),WoW 插件,Dodo 系列之一。仓库: `Baeseata/Wow-Addons` (public),插件在 `DodoBricks/`。
> 换机器先 `git pull` + 读本文件。**UI 文案用英文**(中文是 Jerry 跟 Claude 的设计沟通语言)。
> 当前游戏版本: 正式服 至暗之夜 (Midnight) 12.1.0,Interface 120100。
> 姊妹项目 DodoPool(九球)有自己的 `DodoPool/CLAUDE.md`,音效/窗口/小地图按钮套路同源。

---

## 1. 玩法规则(设计定稿)

**核心循环**: 底边发射台,每回合把一串球(数量=当前球数)依次射出(间隔 0.07s),匀速 900px/s,无重力无摩擦,碰墙/砖弹性反弹,球球不互撞。砖数字=血量,被球碰-1,归零消失。棋盘 **8 列 x 12 行**(0.3.0,原 7x9)。球落底回收,**首颗落地 X = 下回合发射点**。全部回收后砖整体下压一行(0.28s 动画),顶部刷新一行(关数+1)。**游戏结束**: 砖在 row 1 时再下压(判定 row<=2)。无胜利条件。

**刷新行规则**: 必有一个 "+1 球" 圆环道具(吃到即收,压到底前自动吃);22% 概率出特殊道具(见道具节)。~20% 三角砖(45deg 斜边,四朝向随机)。

**操控(定稿)**: 按住左键瞄准(直接指向),虚线=首段+反弹短段;松开发射;右键或仰角<8deg 取消。

**存档**: 回到 AIM 状态自动存档(1档),游戏结束清档。旧版存档兼容(缺字段按缺省读)。

**不做**: 手动加速 / 提前回收按钮;回血脉冲事件(治疗砖替代)。

**难度曲线(0.3.0)**: 出砖率 0.45->每关+0.0045,封顶 0.68(~52关);双倍硬砖率 0.12->每关+0.0032,封顶 0.28;三倍砖 35关起(每关+0.5%,封顶15%)。三角率 0.20 不变。

**计分(0.3.0)**: 每滴血=1分;最底2行命中 x2(险区);全部 x 全清连锁倍率(连续全清 x1->x2->..x10,没清干净归x1)。全清仍+2球。碎砖飘金"+N";HUD金色分数+倍率后缀;bestScore+bestLevel 并列,破纪录="New record!"+钟声。宝箱+25x倍率;boss击杀+maxHp。

**道具(0.3.0,7种,圆环 glyph=效果微缩预览)**: 刷新行 22% 概率出,加权池: 横激光22/竖激光22/炸弹20/斜激光"/"9/斜激光"\"9/分裂12/十字激光4(稀有)。斜激光沿45deg双向扫;十字=整行+整列。**分裂球**: 真球碰到->分裂1颗临时球(偏18-36deg)。临时球铁律: 不进ballTotal,落地蒸发,**不触发任何道具**(防指数);全场活动球上限140保帧率。特殊道具整回合常驻、每颗真球各触发一次,回合结束消失。每种道具首次触发->0.45s慢动作(DB.seen记账号级)。

**特殊砖(0.3.0)**: 宝箱砖(8关起6%/行): 金"?",固定2血,碎了变随机道具圆环+25x倍率分。治疗砖(30关起8%/行): 绿十字角标,血量=ceil(关/5),**每回合结束给周围8格普通砖+1血**(不奶治疗砖/宝箱/boss),绿圈脉冲。固定色砖受击白闪不变色。

**事件(0.3.0)**: 30关起,每回合18%概率排事件(冷却>=4回合),**提前一回合预告**(顶行红光呼吸)。唯一事件=**双压**: 一次压2行+刷2行(各带+1球/各roll道具),动画0.40s。boss关/boss在场不排。死亡判定row<=2。

**Boss(0.3.0/0.4.0重平衡)**: 每25关,顶部3x3巨砖替代普通刷新行(吞掉所辖格旧砖并入hp)。血量(0.4.0): `500+(关-25)x14+吞掉量x0.5`(25关~600/50关~1100)。固定深红大数字,正常随场下压。击杀: 底+1行掉3个随机道具圆环+maxHp分+"BOSS DOWN!"+0.6s慢动作+钟声。75关起boss带治疗光环(每回合全场普通砖+1血)。

**基岩砖(0.4.0)**: 12关起淡入,石板灰四角铆钉,**不可击碎**,球/激光/炸弹无效,治疗砖不奶;压底不算输(滑出消失)。每行最多1块+不与上行同列(防封口袋)。**全清判定三处改`AnyBreakableBrick()`**(否则基岩在场全清链永断)。球撞基岩反弹角**+/-3deg微扰**防顶墙缝永动死弹(harness 59关实抓)。Boss吞格时把基岩碾掉(hp并入1点)。

**Juice(0.3.0)**: 卡缝连击音阶(0.30s内连续命中,第4跳起5档爬升音表);最后一砖0.35s慢动作;每10关色板偏移1位;球速回合内快进(3s起step,15s拉满x3.0)。多球散布首颗严格按瞄准线,第2颗起+/-1.5deg。

---

## 2. 开发环境

放入 `WoW\_retail_\Interface\AddOns\DodoBricks\`,**依赖父插件 `Dodo`**。AddOns 目录与 repo 是 junction(改repo=改游戏目录,无需同步)。**全新插件完全重启魔兽**,之后 `/reload`。打开: 小地图粉色D图标(角度235)或 `/bricks`。

---

## 3. 文件结构

| 文件 | 职责 |
|------|------|
| `DodoBricks.toc` | TOC; `## Group: Dodo`; `## OptionalDeps: Dodo`; SavedVariables `DodoBricksDB` |
| `Geometry.lua` | 棋盘常量: 8 列 x 12 行 x 56px 格,FLOOR=30 发射条,board 448x702,原点左下;格子坐标换算 |
| `Sound.lua` | SoundKit 选音表 + 节流 + 勾选框 + 音量滑条 |
| `Render.lua` | 砖(方/三角)/球/道具/虚线点/棋盘;三角=SetVertexOffset 顶点折叠;职业色板按血量循环 |
| `Physics.lua` | 弹球: 子步进 + 最近点法碰撞(方=AABB clamp,三角=三边最近点) + 3x3邻域查找 + 防水平死弹 + 瞄准Raycast |
| `Game.lua` | 状态机(AIM/FLY/DESCEND/OVER)、发射/回收/下压、刷砖、道具、HUD、存档、进战暂停、结束面板 |
| `Core.lua` | 主窗口(竖版 492x792)、开始界面、小地图按钮、斜杠命令、初始化 |

模块经 `_G.DodoBricks`(代码里 `DBR`)串联: `DBR.geo / Sound / Render / Physics / Game`。

---

## 4. 当前进度

**v0.1.0 实机通过(2026-06-10)**: 基础弹球循环跑通,三角砖SetVertexOffset实机成立。
**v0.2.0 实机通过(同日)**: 碎砖闪光/全清+2球/激光+炸弹道具/多球散布。
**v0.2.1 写完未实机**: 球彗星尾迹(1-3节余像,ADD混合,TRAIL_BUDGET=240)。
**v0.2.3(代码现状)**: 球速渐变最终=纯回合内快进(3s起/15s拉满x3.0),无关数提速/无HUD指示。0.2.1尾迹+0.2.3快进随0.3.0一起验。
**v0.3.0 = 插件 1.1.0,实机通过(2026-06-11),已push+CurseForge上线**: sinfulness实测反馈驱动——68关"太简单/球多清屏/看不懂道具"。8x12棋盘/难度曲线/计分/道具glyph/7种道具/宝箱+治疗砖/事件框架+双压/Boss/Juice全部实现。Headless harness 110关 ALL PASS(`test/harness.lua`,LuaJIT)。
**v0.4.0 = 插件 1.2.0,已push+CurseForge上线(2026-06-12),headless ALL PASS,实机未验**: boss重平衡(x14+0.5吞掉约砍半)+基岩砖(详§1)。Jerry实测反馈驱动。

**harness**: `luajit test/harness.lua .` (LuaJIT 在 `%LOCALAPPDATA%\Programs\LuaJIT\bin\`; toc不引用不进游戏)。`luajit -bl *.lua` 纯语法检查。

---

## 5. 待办 / TODO

0. **v0.4.0 实机验证**(已发版未跑): boss新血量手感/基岩观感(石板灰能认出"打不动"?)/球在基岩缝弹跳(+/-3deg微扰够不够自然)。
1. **v0.3.0 深关数细项**(25+关才出,玩时留意): 新棋盘492x792在你的UI scale下挤不挤;碎砖飘分密度;双压顶行红光够不够醒目;治疗/宝箱"快打奶妈"压力成不成立;boss 75+光环是否过分;40-70关难度曲线是否"会死";200+球帧率。
2. **音效听感**(从未专门确认): 既有hit/launch/brk+新split(862)/heal(844)/连击音阶5档(857/856/3175/8960/875)。不行按DodoPool迭代路径换ogg。
3. **暂缓**: 分数发聊天框/种子挑战/底行危险警告/开始界面统计/事件池扩充(硬化行等)。
4. 手感调参按用户反馈(见§6)。加速/回收按钮用户已两次说不要。

---

## 6. 可调参数

**Physics.lua**: `SPEED=900` 球速; `SUBSTEP_LEN=6`; `FLAT_VY/FLAT_T/FLAT_EXIT/FLAT_KICK` 防水平死弹。
**Game.lua**: `LAUNCH_GAP=0.07`; `MIN_ANGLE=8`; `DESCEND_T=0.28 / DESCEND_T2=0.40`(单/双行下压); `BRICK_CHANCE=0.45`; `TRI_CHANCE=0.20`; `DOUBLE_CHANCE=0.12`; `SPREAD_DEG=3`(首颗不散); `SPECIAL_CHANCE=0.22`; `CLEAR_BONUS=2`; `TRAIL_MAX=3 / TRAIL_BUDGET=240`(Render.lua `GHOST_SIZE/GHOST_ALPHA`调每节); 快进 `RAMP_START=3/RAMP_FULL=15/RAMP_MAX=3.0`(`RAMP_MAX=1`关闭); 难度曲线 `CHANCE_GAIN=0.0045/CHANCE_CAP=0.68/DBL_GAIN=0.0032/DBL_CAP=0.28/TRIPLE_FROM=35/TRIPLE_GAIN=0.005/TRIPLE_CAP=0.15`; 道具 `SPECIAL_W` 权重表/`SPLIT_CAP=140`; 宝箱 `CHEST_FROM=8/CHEST_CHANCE=0.06/CHEST_BONUS=25`; 治疗砖 `HEALER_FROM=30/HEALER_CHANCE=0.08`; 事件 `EVENT_FROM=30/EVENT_CHANCE=0.18/EVENT_CD=4`; boss `BOSS_EVERY=25/BOSS_BASE=500/BOSS_HP_GAIN=14/BOSS_EAT_RATE=0.5/BOSS_AURA_FROM=75`; 基岩 `BEDROCK_FROM=12/BEDROCK_CHANCE=0.10/BEDROCK_GAIN=0.004/BEDROCK_CAP=0.32`(~67关顶); 计分 `DANGER_ROWS=2/DANGER_MULT=2/MULT_CAP=10/COMBO_WINDOW=0.30/SLOWMO_RATE=0.25`。
**Geometry.lua**: `COLS=8 ROWS=12 CELL=56 FLOOR=30 BALL_R=7 ITEM_R=10 BRICK_PAD=3`(碰撞按整格,PAD仅视觉缝)。
**配色(Render.lua `TIER_CLASS`)**: 血量`(hp-1+colorShift)%9+1`->职业色9色循环;`colorShift`每10关+1。特殊砖固定色`KIND_COLOR`;boss固定深红。

---

## 7. 实现要点 + 踩坑

- **三角砖渲染**: `SetVertexOffset` 把一角折叠到相邻角->实心直角三角形。顶点序 1=左上2=左下3=右上4=右下,y正向上;BL折3(-S,0)/BR折1(0,-S)/TL折4(-S,0)/TR折2(S,0)。边框=外层深色+内层缩2-3px同向三角。
- **碰撞统一最近点法**: 球心到形状最近点距离<r即碰,法线=球心-最近点->镜像反射+推出。方=AABB clamp;三角=三边段最近点+内部判定(斜边实心侧u/v不等式)。
- **性能**: 砖在网格`grid[row][col]`,每子步只查3x3邻域;球球不互撞;百球无压力。
- **下压动画**: 砖/道具挂`gridLayer`,逻辑行号先减一并重摆,动画把gridLayer锚点从+CELL平滑到0;`playArea SetClipsChildren(true)`裁新行和虚线/球。
- **Boss多格砖**: `GridSet`统一管1x1和多格;Physics`ClosestOnBrick`见`brick.w`拉大AABB;激光/炸弹穿boss多格收集多次=吃满AOE(故意);`HitBrick`开头防碎后重复结算。
- **临时球(分裂)**: 复用`G.balls`池`ballsInPlay+1..+tempCount`段,`b.temp=true`;Physics零改动。所有遍历范围=`ballsInPlay+tempCount`; Fire必须重置整池清旧temp标记。temp不触发道具=HitItem第一行守门。
- **道具glyph用`CreateLine()`**: Texture SetRotation只转UV不转形状(画不了斜线);CreateLine(SetStartPoint/SetEndPoint/SetThickness)才是任意角度线段正解。
- **local函数前向引用**: AddBrick/AddItem/AddFloat/SpawnTempBall 都被 HitBrick 调用,定义必须在 HitBrick **之前**(否则解析成nil global)。
- **HUD脏标记**: HitBrick百球时每秒几百次,不能每次SetText->`G.hudDirty=true`,Driver帧末统一刷。
- **事件时序**: roll 在 StartDescend 尾部(为下回合排),执行在头部(消费pendingDouble);排除=下关是boss关/boss在场/冷却未到。预告=`G.warnBar`顶行红条,GameOver/New/Load(无pending)都Hide。
- **治疗结算**: StartDescend里道具清理后、lose判定前(HealerPulse+boss光环同处),只奶`kind==nil`普通砖。
- **存档一致性**: 只在AIM时落盘,飞行中关窗=回本回合开始。
- **12.0注意**: 不碰UIDropDownMenu/战斗属性API,本插件均不涉及。
- **圆形遮罩**: `TempPortraitAlphaMask`+两个CLAMPTOBLACKADDITIVE;贴图必须SetPoint否则不渲染。

---

## 8. 跨机 / git

仓库 `Baeseata/Wow-Addons`(public)。本机AddOns=junction到repo(改repo即改游戏目录)。另一台机器开工: `git pull`->读本文件->确认DodoBricks+Dodo都进AddOns->完全重启魔兽。

**发版**: 提TOC Version->push->打annotated tag `DodoBricks-vX.Y.Z`(tag message=changelog)->GitHub Action自动打包上传;dry-run与细节见`PUBLISHING.md`(local-only)。2026-06-12起全自动(首战踩坑:tag `--cleanup=verbatim`保`##`标题/curl -F分号截断metadata JSON,修法在PUBLISHING.md §7)。
