# DodoRush - 开发简报 (read me first)

> 单人**人海快跑**(Count Masters / Join Clash 类人海跑酷)小游戏,World of Warcraft 插件,Dodo 系列之一。
> 仓库: `github.com/Baeseata/Wow-Addons` (public)。本插件在 `DodoRush/`。
> **跨机协作**: 换机器先拿到最新代码(**两台机的形状不一样,见 §8**),Claude 先读本文件接上进度。
> ⚠️ **本插件 shipped 内容已全英文化(2026-06-11,同 DodoPool/DodoBricks)**:.lua/.toc 的注释 +
> UI 字符串**零中文**,改 UI 文案**务必继续用英文**,别手滑写回中文。本 CLAUDE.md 保持中文(不进发布包)。
> **支持到哪个客户端版本 = 查 `DodoRush.toc` 的 `## Interface`** —— doc 不复述版本号(复述一遍就是第二份会漂的真相)。
> 姊妹项目 DodoPool(九球)/ DodoBricks(打砖块)各有自己的 CLAUDE.md,套路(音效/窗口/小地图/键盘)同源。

---

## 1. 玩法规则(设计定稿,与用户两轮讨论确认 2026-06-11)

- **纯 2D 俯视**(用户拍板,不做伪 3D):世界向下滚动,蓝色人群固定在跑道下方 1/4 处,
  **按住 A/D(或左右方向键)横移**,自动向前跑。窗口竖版 436×624,跑道 392×534。
- **门**:一排两块(绿 = `+N`/`×k` 增益,红 = `-N`/`÷2` 减益),中线虚线分左右;
  门排滑过人群线那一刻,看**人群中心**在哪半边就吃哪个门。数字封顶 9999。
- **敌军(红色)**,接战 = **二元全额对账**:碰上就双方各扣 `min(我, 敌)`,摊在 0.5~2 秒里
  按帧扣(数字哒哒掉 + poof),**边跑边磨**(用户拍板):不停下,只减速 ×0.55,
  接战的敌阵被"钉住"缓退。我方先归零 = 全军覆没。
  - **敌墙 wall**:横排方阵占满路宽,必打;人数 = α × 过门后基准。
  - **散兵 blob**:圆阵只占半幅路,**可以绕开**(白省一笔,躲开有飘字);≈ 基准的 10~18%。
  - **BOSS 墙**:每 5 关一个,α×1.18;Boss 后一关固定送 ×3 / ×2 奖励门。
- **数值模型**(核心,Track.lua):基准曲线 P(i) = 完美玩家人数;敌人锚**基准**而非玩家实际
  (失误才会累积);压力 α: 0.38→0.86,目标净增长 ρ: 1.28→0.90 + 乘法门封顶 ×6
  => 后期必死,**无尽模式**记最高关数 + 最远距离(用户授权我定的)。
  门成对设计在加/乘交叉点附近(人少 +N 香、人多 ×k 香);第 4 关起 15% 陷阱门,
  第 8 关起 10% "两害相权"(两门都负)。
- **不做局中落盘存档**(单局 3~5 分钟):开始界面"继续本局"只续接**内存里**还活着的一局
  (关窗不丢,/reload 丢)。只存最高纪录/音效/窗口位/小地图角度。
- **二期(确定要做,未开始)**:小人"换脸"——我方发 13 职业圆形图标,敌方按关卡主题发怪物
  头像(`INV_Misc_Head_*` 鱼人/狗头人/豺狼人等),圆形遮罩 `TempPortraitAlphaMask` 套路;
  `Render.NewUnit` 已预留 `f.face` 挂点,纯贴图替换不动逻辑。

---

## 2. 怎么跑 / 开发环境

- 放进 `<WoW>\_retail_\Interface\AddOns\DodoRush\`;**依赖父插件 `Dodo`**(共享库 + 图标)。各机 WoW 路径不同,**见该机 `~/.claude/CLAUDE.md`**。
- 🔴 **两台机都不是 junction,改完必须拷**(2026-08-22 在 HOME 实测:24/24 个 `Dodo*` 目录 `LinkType=(none)`、无 `.git`):
  - **HOME**: 就地在该机 AddOns 里改(那个目录不是 git tree),推送走 §8。
  - **OMEN**: 在 `~/Code/Wow-Addons` clone 里改,**再拷进它自己的 AddOns** 才进游戏。
  - ⚠ 本行原文写的是「本机(主力机)AddOns 就是工作目录」+「另一台机器建议 junction」——「本机」这个词在一份两台机共享的 repo 里**无法解析**,而 junction 那半句已实测为假(DodoPool/CLAUDE.md §1 原来那段 `mklink` 也一并改掉了)。⚠ **别顺手真去建一个 junction**:两台机的推送流程都建立在「不是链接」这个前提上。
- **全新插件首次出现要完全重启魔兽**(/reload 不认新文件夹);之后改代码 `/reload` 即可。
- 打开: 小地图粉色 D 图标(默认角度 265,错开 Pool 205 / Bricks 235)或 `/rush`(亦 `/dodorush`)。

---

## 3. 文件结构(加载顺序见 DodoRush.toc)

| 文件 | 职责 |
|------|------|
| `DodoRush.toc` | TOC;`## Group: Dodo`、`## OptionalDeps: Dodo`、SavedVariables `DodoRushDB` |
| `Geometry.lua` | 跑道常量:392×534,人群线 CROWD_Y=120,门排尺寸/中心坐标;原点左下 |
| `Sound.lua` | SoundKit 选音表 + 同类节流 + 勾选框 + 音量滑条(同帧叠播);抄 Bricks 验证过的套路 |
| `Render.lua` | 路面/小人(圆形遮罩,蓝我方红敌方,f.face 预留换脸)/数字牌/门板/poof/过门闪光 |
| `Track.lua` | **数值大脑**:基准曲线 + α/ρ + 门对生成(交叉点/陷阱/两害相权)+ 关卡元素队列 |
| `Game.lua` | 驱动(滚动/横移/生成)、过门结算、接战对账、人群/敌阵渲染同步、HUD、结算面板、键盘、进战暂停 |
| `Core.lua` | 主窗口(竖版 436×624)、开始界面、小地图按钮、斜杠命令、初始化 |

模块经全局表 `_G.DodoRush`(代码里 `DR`)串联: `DR.geo / Sound / Render / Track / Game`。

---

## 4. 当前进度 (state)

**0.1.1(2026-06-11)— 难度曲线已锁定(Jerry 实测 12 关后拍板"可以"),shipped 内容已全英文化**。
- 0.1.0 全链路实机验证通过(加载/开窗/横移/过门/接战/结算);实测死第 6 关 → 0.1.1 调参:
  ALPHA0 0.50→0.38、GAIN 0.016→0.012、BOSS_MULT 1.28→1.18、TRAP 3关18%→4关15%、
  BOTHBAD 6关12%→8关10%、SKIRM_FRAC 12~22%→10~18%(数学详 Track.lua 顶部注释)。
- 0.1.1 实测到第 12 关,曲线 = 无加成新手基线,先不再调。
- **大方向:养成式(meta-progression)** — 天赋点等局外成长叠在当前曲线上。
  **具体创意 Jerry 亲自构思中,Claude 不要自行设计**;等设计出来再排实现。
- 0.1.0 已实现全套核心:路面滚动/人群螺旋/门排/敌阵三类(墙/散兵/BOSS)/接战对账/无尽 Track/
  HUD/结算面板/键盘吞键+进战暂停/开始界面/小地图/窗口记忆/10 种音效。

---

## 5. 待办 / 下一步 (TODO)

1. **【主线】养成式设计 — 等 Jerry**:天赋点等局外成长,**Claude 不要抢跑**;聊定后再动工。
   届时 Track 的 α/ρ/START_PAR 大概率变"基础值 x 天赋修正"形态,设计时记得这层。
2. **英文化回归一眼**(/reload):开始界面/HUD/结算/暂停提示/小地图 tooltip 不超框
   (English 比中文长,重点看 "Menu" 按钮和 hint 五行)。
3. **边角确认**(散兵绕开手感/进战暂停+脱战缓起/ESC 关窗/"Continue Run"/结算纪录/音效响度)。
4. **二期换脸**(职业图标/怪物头像,见 §1 末);可顺带敌方主题化。
5. **可选润色**:三门排混入、摆动门、人群密度感(count>48 挤一点)、开局 3-2-1 倒数、
   音效不满意换 KITS(终极方案 media/ 自带 ogg)。

---

## 6. 可调参数 (tunables)

**Game.lua**(顶部): `SCROLL=240` 滚动速度 · `SCROLL_STAGE_GAIN=0.015/MAX=1.35` 关数提速 ·
`GRIND_SLOW=0.55` 接战减速 · `PUSH_FRAC=0.12` 接战敌人被推速度 · `STRAFE=320` 横移速度 ·
`CROWD_VIS=48` 我方可见小人上限 · `KILL_PER_DUR=55 / KILL_DUR_MIN=0.5 / MAX=2.0` 对撞节奏
(时长 = clamp(总消耗/55, 0.5, 2)) · `GRACE_T=0.8` 开跑/脱战缓起 · `INITIAL_RUNWAY=430` 开局留白 ·
`DIST_PER_M=40` 距离换算 · `DASH_N=8/DASH_GAP=80` 中线虚线。

**Track.lua**(顶部,数值平衡): `START_PAR=10` 开局人数 · `ALPHA0=0.38/GAIN=0.012/CAP=0.86` 压力 ·
`RHO0=1.28/DECAY=0.012/MIN=0.90` 净增长 · `MULT_CAP=6` 乘法门封顶 · `TRAP_CHANCE=0.15`(第 4 关起)·
`BOTHBAD_CHANCE=0.10`(第 8 关起)· `SKIRM_CHANCE=0.60` + `SKIRM_FRAC 0.10~0.18`(第 2 关起)·
`BOSS_EVERY=5 / BOSS_ALPHA_MULT=1.18 / CAP=0.90` · 元素间距 `GAP_*`(门210散兵230墙340,无散兵门→墙360)。
**调难度主杠杆 = ALPHA0/ALPHA_GAIN**(容错余量 = 1-α;need = ρ/(1-α) 决定门倍率,
need>3.3 后加法门消失 = 落后玩家失去追赶机制,调参时注意这个临界点别太早到)。

**Render.lua**: `UNIT_STYLE` 小人尺寸/配色(friend 13px 蓝 / foe 13px 红 / boss 17px 深红)。
**Game.lua 内嵌**: `ENEMY_CAP` 敌阵可见上限(wall 36 / boss 30 / blob 24);
人群/散兵半径公式 `12 + 4.0*sqrt(vis)`(改"人堆大小"看这)。

---

## 7. 设计/实现要点 + 踩坑预警

- **数值模型**:敌人锚定**基准曲线**(par)而非玩家实际人数 —— 选错门的劣势会滚雪球,
  这是"选门有意义"的根。par 在 Track.GenStage 里随生成推进:`P' = max(两门结果)`,`P_next = P' - E`。
- **接战对账是二元的**:碰上瞬间就锁定 `kills = min(我, 敌)`,之后只是把这笔账摊到时间里播,
  与穿过速度/帧率无关 => 平衡只看人数一个维度。刮蹭散兵边 = 全额开打,想省就绕干净。
- **接战的敌阵"钉住"**(只按 PUSH_FRAC 缓退),否则磨到一半敌阵滑出屏幕。墙后→下一门留了
  340px,磨满 2 秒(减速后 ≈264px)刚好来得及,改 KILL_DUR_MAX 时注意联动。
- **键盘**(DodoPool 套路):OnKeyDown 里 ESC `SetPropagateKeyboardInput(true)` 放行、其余吞;
  **进战必须 `EnableKeyboard(false)`**(战斗中插件不能调 SetPropagateKeyboardInput,会报错);
  脱战恢复 + `grace=0` 缓起(滚动 smoothstep 从 0 拉满,不糊脸)。
- **层级**(playArea 基准 +N):路面 0 / 虚线 ~1 / 门 3 / 敌阵 4(数字牌 +9)/ 我方人群 6 /
  特效 8 / 飘字层 12 / 结算面板 30。人群盖在门板上 = "从门里穿过"。
- **圆形遮罩**: `TempPortraitAlphaMask` + 两个 CLAMPTOBLACKADDITIVE;**贴图必须 SetPoint 否则不渲染**。
- **热路径**: `Render.MoveAt` 同名 CENTER 锚直接替换(省 ClearAllPoints);只能用在"从来只用
  CENTER 锚"的帧上。敌阵小人是容器的孩子,容器一动全动(便宜);我方小人各自独立(拖尾感)。
- **特效结构**:锚点占位帧 + 缩放视觉子帧(SetScale 连锚点偏移一起缩放,直接缩放会漂移);
  小 poof 有预算节流(`poofBudget` 每秒 ~14 个),混战不爆帧。
- **PlaySound**: 无音量参数 => 同帧叠播 N 次;第三参 forceNoDuplicates 必须显式 `false`。
- **12.0 注意**: 不碰 UIDropDownMenu(已删)/ 战斗属性 API(机密值),本插件均不涉及。
- **驱动挂在 playArea OnUpdate**:菜单时 playArea 隐藏 = 天然停摆;局中开菜单/关窗不清局,
  "继续本局"接回(无落盘,/reload 即丢,§1 有写)。

---

## 8. 跨机 / git

- 仓库 `github.com/Baeseata/Wow-Addons`(public)。**两台机的形状不一样**(都不是 junction,见 §2):
  - **HOME**: AddOns 目录**不是 git clone** ⇒ 推送 = 临时目录 clone → 拷贝 `DodoRush/` 进去 → commit + push
    (沙箱禁在同一条命令里 `Remove-Item` + 提 `D:\` 路径,用 `[System.IO.File]::Delete` 或 `Copy-Item` 覆盖)。
  - **OMEN**: 有 `~/Code/Wow-Addons` clone ⇒ 在 clone 里改 → `git pull`/`commit`/`push`,**再拷进该机 AddOns**。
- **per-addon CLAUDE.md 已入库**(2026-06-11 起,用户要求跨机可拉):.gitignore 不再排除 CLAUDE.md。
  ⚠️ `DODO_ADDONS.md` / `PUBLISHING.md` 被 .gitignore 排除 ⇒ **它们永不跨机**,而 `PUBLISHING.md`
  2026-08-22 在 HOME 上全盘搜索**零命中** —— **别把任何一条发版知识指向它**(发版正文见 DodoBricks/CLAUDE.md §8
  + `.github/workflows/curseforge-release.yml`,后者 tracked、两台机都读得到)。
  ✅ **CLAUDE.md 不用手工剔除**:打包白名单里有 `-not -name 'CLAUDE.md'`,而且紧接着一条硬 guard
  (grep `Forbidden files leaked`)泄进去就 `exit 1`。⚠ 原文那句「发布打包时**记得**剔除」是手工纪律,已被工具取代。
- 任一台开工 checklist: ① 拿到最新代码 ② 读本文件 ③ 确认 `DodoRush` + `Dodo` 都拷进了**该机** AddOns
  ④ 完全重启魔兽 ⑤ 跑 §5.1 ⑥ 报错记下来修。
