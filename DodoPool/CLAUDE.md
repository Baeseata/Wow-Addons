# DodoPool - 开发简报 (read me first)

> 单人 **9 球台球** 小游戏,World of Warcraft 插件,Dodo 系列之一。
> 仓库: `github.com/Baeseata/Wow-Addons` (public)。本插件在 `DodoPool/`。
> **跨机协作**: 换机器先 `git pull`,Claude 先读本文件接上进度。UI 文案用**中文**(Dodo 系列惯例)。
> 当前游戏版本: 正式服 至暗之夜 (Midnight) 12.0.5,Interface 120005。

---

## 1. 怎么跑 / 开发环境

- 这是 WoW retail 插件,要放进 `World of Warcraft\_retail_\Interface\AddOns\DodoPool\` 才能在游戏里加载。
- **依赖**: 同仓库的 `Dodo` 父插件(提供 `_G.Dodo` 公共库 + 共享图标 `Dodo.tga`)。装 DodoPool 时**必须也装 Dodo**。
- **dev 设置(本机用的法子,推荐另一台也这么搞)**: 用目录 junction 把 repo 里的文件夹链进 AddOns,这样在 repo 里改、游戏里直接生效,不用每次拷:
  ```
  REM cmd (或 PowerShell New-Item -ItemType Junction),WoW 路径按本机实际改
  mklink /J "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\DodoPool" "<repo路径>\Wow-Addons\DodoPool"
  mklink /J "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\Dodo"     "<repo路径>\Wow-Addons\Dodo"
  ```
  junction 不需要管理员权限(AddOns 目录对用户可写)。不想用 junction 就直接拷文件夹,改完再拷一次。
- **加载规则**: 全新插件首次出现要**完全重启魔兽**(光 /reload 不认新文件夹);之后改代码 **`/reload`** 即可。
- **打开游戏**: 小地图上的**粉色 D 图标**左键,或斜杠命令 `/pool`(亦 `/dodopool`)。

---

## 2. 操控方案(最终版)

- **鼠标拖动 = 瞄准 + 蓄力**: 左键按住,以母球为圆心,鼠标方向角 = 出杆方向,鼠标离母球的距离 = 力度(满力到 `MAX_PULL`)。**拉弓式**: 往哪边拉,白球往**反方向**飞。松开左键 = 击出,右键 = 取消。
- **WASD = 击球点(塞)**: W/S 上/下塞(跟杆 / 缩杆),A/D 左/右侧塞。
- **QE = 抬杆(masse)**: 0~45 度。抬杆 + 侧塞 = 母球走弧线(纯侧塞不抬杆只影响吃库,不拐弯)。
- 瞄准时**键盘被接管**(WASD/QE 不会走人物);**ESC 关窗**;**进战自动暂停 + 放开键盘**让你打架,脱战恢复。
- **自由球(犯规后)**: 鼠标移动放母球(压着球/袋时母球半透明=放不下),左键确认。
- HUD: 杆数 / 剩球 / 蓄力条(CastingBar 材质)/ 击球点圆盘 / 抬杆侧视球杆模型 / "保存"按钮。

---

## 3. 文件结构(加载顺序见 DodoPool.toc)

| 文件 | 职责 |
|------|------|
| `DodoPool.toc` | TOC,加载顺序: Geometry -> Render -> Physics -> Game -> Core。`## Group: Dodo` 归入整合包,`## OptionalDeps: Dodo`,SavedVariables `DodoPoolDB` |
| `Geometry.lua` | 球桌几何常量(felt 局部像素坐标,原点左下 +x 右 +y 上)、6 袋位置、9 球钻石摆球位置 |
| `Render.lua` | 球视觉(圆形遮罩 + 渐变球面 + 高光 + 号码 + 目标高亮层)、`BuildTable`(木框/绿绒/球带/袋/标记)、1-9 号球职业配色 |
| `Physics.lua` | 运动(子步进、球-球弹性碰撞、库边反弹、滚动摩擦、落袋)、旋转(spinF 跟/缩杆、spinS 侧塞+throw、curve masse)、`PredictCuePath`(瞄准轨迹)、`ShotActive`(停球判定)、犯规记录(out.firstHit / out.railAfter) |
| `Game.lua` | 状态机(AIM/SHOOT/PLACE/OVER)、输入、HUD、**严格 9 球规则**、自由球、存读档、进战暂停、目标球高亮 |
| `Core.lua` | 小地图按钮、主窗口、开始界面(开始新局 / 继续 / 最佳杆数)、`/pool` 命令、初始化 |

模块通过全局表 `_G.DodoPool`(代码里 `DP`)串联;`DP.geo` / `DP.Render` / `DP.Physics` / `DP.Game`。

---

## 4. 当前进度 (state)

**已实现(代码层面)**:
- 台面渲染 + 摆球 + 开窗 + 小地图按钮 + 开始界面 [已实机验证]
- 运动物理(碰撞/库边/摩擦/进袋,防穿模子步进)[已验证,手感 OK]
- 鼠标瞄准蓄力出杆 [已验证]
- 旋转: 跟杆/缩杆(缩杆能"前进后回滚")、侧塞吃库 + throw、QE 抬杆 masse 弧线 [已验证 draw + curve]
- 动态虚线瞄准(前向模拟轨迹,带弧线,行进虚线)[已验证]
- HUD: 蓄力条(CastingBar 材质 + spark)、击球点圆盘(白球底)、抬杆侧视球杆模型、杆数/剩球 [已验证]
- 球 + 球桌材质(渐变球面/高光、木框/绿绒渐变、球带、开球线/置球点)[已验证]
- 目标球高亮(最小号在台球脉冲变亮)[已验证]
- **严格 9 球规则 + 自由球 + 9 号非法进袋重摆 + 存读档(1 档)+ 最佳杆数记录** [**已写,尚未实机测试**]
- **袋口"喉咙"吸入修复**: 球漏过库边线进入无库袋口区会被拉向袋心落袋(`POCKET_PULL` + `MouthPocket` + `ShotActive` 库外保活),治"母球卡在角袋颚口/库边外"的死区 bug [已写,待实机验证]。⚠️ **行为变化**: 蹭进袋口喉咙的球现在一律落袋 → 母球进喉咙 = scratch(自由球),不再"挂"在库上(符合真实台球)。
- **HUD "返回开始" 按钮**: 随时回开始界面(打完一局也用它);开始面板抬到 HUD 之上 + 不透明 + 吃鼠标,避免 HUD 透底(`G.ReturnToMenu` + `DP.ShowStartScreen`)[已写,待实机验证]。

**最近一步改了(本 session)**: Physics.lua(袋口吸入 `POCKET_PULL`/`MouthPocket`,`ShotActive` 库外保活)、Game.lua(`G.ReturnToMenu` + HUD"返回开始"按钮)、Core.lua(开始面板遮挡 HUD + 暴露 `DP.ShowStartScreen`)。上一 session: Physics(firstHit/railAfter)、Game(规则/自由球/存读档重写)、Core("继续"按钮)。

---

## 5. 待办 / 下一步 (TODO)

1. **【最优先】实机验证(都还没测过)**:
   - **袋口吸入**(本 session): 把母球/目标球往**角袋、中袋喉咙**蹭 -> 是否干脆落袋、不再卡库?母球进喉咙是否判 scratch + 自由球?台面上正常贴近袋口的球是否**不**被误吸?太"吸"或还卡就调 `POCKET_PULL`(Physics 顶部,现 1400)。
   - **返回开始按钮**(本 session): 游戏中 / 打赢后点"返回开始" -> 是否干净回菜单(无 HUD 透底)、最佳杆数刷新?
   - **规则 + 存读档**(上一 session 写的): 碰错球 / 空杆 / scratch -> 罚 +1 杆 + 自由球?合法进 9 号判胜 + 记录最佳?犯规进 9 号重摆?"保存" -> "继续上次进度" -> 局面恢复?
   - 任何 Lua 报错都记下来修。
2. **物理手感继续调**(常数见 §6),按实测反馈。
3. **可选润色(未开始)**:
   - 音效(出杆/碰球/进袋/撞库,复用魔兽自带 SoundKit,带静音开关)
   - 动画(球滚动高光、进袋动画、出杆动作)
   - 瞄准辅助 3 档开关(全预测 / 短线 / 无;目前固定为全预测)
   - 开球自由球限制在 kitchen(目前开球母球自动摆在开球区,不强制 ball-in-hand)
   - 推杆(push-out)规则(暂未做)

---

## 6. 可调参数 (tunables) — 改手感看这里

**Physics.lua**(顶部常量):
- `ROLL_DECEL = 135` 滚动摩擦减速(越小滚越远)
- `WALL_REST = 0.72` 库边反弹系数 · `BALL_REST = 0.96` 球-球反弹
- `MAX_SPEED = 1500` 满力球速 · `POCKET_PULL = 1400` 袋口喉咙吸力(球漏过库边线就被拉进袋;嫌太吸调小,嫌还卡调大)
- `SPINF_ACCEL = 480` 跟/缩杆力度(缩杆回滚靠它)· `SPINF_DECAY = 0.5` 跟/缩杆衰减(越小回滚越久越夸张)
- `SPIN_DECAY = 0.7` 侧塞衰减 · `THROW_K = 0.05` 目标球 throw 角 · `ENGLISH_K = 160` 侧塞吃库切向
- `CURVE_ACCEL = 2600` masse 弧线弯度 · `CURVE_DECAY = 1.0` 弧线衰减

**Game.lua**(顶部常量):
- `MAX_PULL = 230` 满力拉杆距离 · `MIN_PULL = 14` 最小有效力度
- `MISCUE_SAFE = 0.82` 击球点幅度超此值开始有概率滑杆(概率封顶 50%,见 Fire)
- `STRIKE_RATE = 1.6` WASD 调点速率 · `ELEV_RATE = 55` QE 抬杆速率 · `MAX_ELEV = 45` 最大抬杆角
- `STRIKE_RAD = 28` 击球点圆盘半径 · `DASH_LEN/DASH_GAP/DASH_SPEED` 瞄准虚线

**Geometry.lua**: `FELT_W=860 FELT_H=430`(2:1)· `RAIL=32` · `BALL_R=13` · `POCKET_R=22` · `HEAD_X` 开球线 · `FOOT_X` 置球点。

**球的配色**(Render.lua `BALL_CLASS`,读 `RAID_CLASS_COLORS`): 1 盗贼黄 / 2 萨满蓝 / 3 DK 红 / 4 术士淡紫 / 5 德鲁伊橙 / 6 武僧玉绿 / 7 战士棕 / 8 圣骑粉 / 9 法师青;母球白。

---

## 7. 踩坑 / 经验(别重蹈)

- **圆形遮罩**: `Interface\CharacterFrame\TempPortraitAlphaMask` + 两个 `CLAMPTOBLACKADDITIVE` wrap mode 把方块裁圆。`MakeCircle` 里贴图**必须 SetPoint**(居中),否则不渲染(踩过: 白球底没出来)。
- **缩杆(draw)物理**: 摩擦那步要用"**施力后**的实时速度"重算(`fsp`),否则缩杆反向那一下被旧速度错误抹掉,球只会缓缓停不回滚。`SPINF_ACCEL > ROLL_DECEL` 才能反向;`ShotActive` 在"残余塞已不足以推动静止母球"时结束这杆(否则停球后干等旋转衰减,延迟 1 秒多)。
- **蓄力条材质**: `Interface\CastingBar\UI-CastingBar-Background/-Border/-Spark` + 填充用 `Interface\TargetingFrame\UI-StatusBar`(染金色)。
- **SetGradient**: 球面阴影 + 木框/绿绒渐变用它,`CreateColor ~= nil` 守一下;VERTICAL 方向 min=底 max=顶。
- **键盘捕获**: `EnableKeyboard(true)` + OnKeyDown 里 `SetPropagateKeyboardInput(false)` 吞键;ESC 那一下 propagate(true) 放行关窗。进战必须 `EnableKeyboard(false)` 放开(10.1.5 起非安全代码战斗中不能调 SetPropagateKeyboardInput)。
- **度数符号 °**: Lua 字符串里用字节转义 `\194\176`(UTF-8 的 °),别直接打字符。
- **9 球规则裁定**(EndShot): 优先级 进袋 > 空杆 > 未先碰最小号 > 碰球后无球到库且未进球。合法进 9 号才判胜,犯规进 9 号 RespotNine 重摆。
- **12.0 机密值(Secret Values)**: `UnitStat`/`GetCritChance`/`GetCombatRatingBonus` 等战斗属性 API **进战斗后返回 secret 值**:插件能存能传能 `string.format`,但**不能比较 / 加减 / `math.floor` / `tostring`**(否则报 "a secret number value, while execution tainted")。检测用 `issecretvalue(v)`;无法转回普通数字,只能跳过/占位。本 session 因此修了**同仓库 DodoStatHUD**(进战每帧刷屏报错):把属性计算 `pcall` 包住,战斗中算不出就沿用脱战前的值、脱战恢复。DodoPool 不读战斗属性,暂不受影响;但**任何读玩家战斗数值的功能都得防这条**。

---

## 8. 跨机 / git

- 仓库 `github.com/Baeseata/Wow-Addons`(public)。`git pull` 拿更新,改完 `git add . && git commit && git push` 同步回去。
- 另一台机器开工 checklist: ① `git pull` ② 读本文件 ③ 确认 `DodoPool` + `Dodo` 都链进/拷进该机 AddOns ④ 进游戏 `/pool` 测 §5.1 待办 ⑤ 记录报错 -> 修。
- 设计讨论的完整来龙去脉在跟 Claude 的对话里;本文件是浓缩后的"够接着干"的上下文。
