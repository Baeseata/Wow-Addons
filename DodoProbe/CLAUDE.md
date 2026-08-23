# DodoProbe — Secret Value 探针（诊断插件，非功能插件）

**它是干嘛的**：Midnight 12.0 起暴雪上了 Secret Values，插件在战斗中读不到血量/资源/CD/光环。
**但哪些 API 具体被封、封的条件是什么，每个补丁都会变**。这个插件就是每次补丁后花 30 秒把它量出来。

**默认完全静默**，不注册任何自动打印。装着不碍事。

## 用法

**权威清单 = `DodoProbe.lua` 底部那个 slash 分发表**(`/dp` 与 `/dodoprobe` 是同一个)。
下表是它的注释版,**加了子命令请回来补这里**;怀疑漂了就当场重数一遍:

```bash
grep -nE 'cmd == "' DodoProbe/DodoProbe.lua
```

```
/dp              立刻跑一次主表,打印 + 自动落盘(脱战/战斗中都能跑)
/dp arm          武装:进战 3 秒后跑一次,跑完自动解除
/dp copy         把上一次 /dp 的输出重新弹一次复制窗(Ctrl+A / Ctrl+C)

/dp lat          开关「DoT 上身 → 名条图标出现」的延迟探针(见下面 /dp lat 一节)
/dp tint         建 DoT 染色钻机:条按 DoT 组合变色(判据只能是眼睛)
/dp dot <数字>   设染色 / 光环探针盯的那个 DoT 的 spellID
/dp exec <数字>  设斩杀探针的 spellID
/dp aura         开关 aura 探针那几排(要先脱战 /dp 跑过一次才建得起来)

/dp class        跑一次职业色探针:target + nameplate1..N,连区域上下文一起落盘
/dp macro        跑一次「宏 / 灌注顺位」开工前置探针 —— 有副作用(临时建一个宏再删),
                 所以只走手敲、不进默认 /dp。DodoGuanzhu 那条阻塞项的验法就是它

/dp pos          开关玩家坐标采样(每 POS_TICK 秒一次,没动就不记)
/dp mark <名字>  在坐标流里打一个具名点,如 /dp mark cross(身份在打点那刻钉死)
/dp posclear     清空坐标记录

/dp log          报落盘日志条数 + 文件路径
/dp clear        清空落盘日志(只清 log,不碰 pos)
```

⚠ **拼错的子命令、以及 `/dp dot` / `/dp exec` 忘了带数字,都会静默落进 else 分支跑一次完整主表**
—— 不报「未知命令」。想设 id 却看到一整张表刷出来,就是漏了那个数字。
⚠ 凡带「记录 / 清空」的(`pos` / `posclear` / `log` / `clear`),**都要再 `/reload` 一次才真的落到文件**。

`/dp arm` 是为了量「战斗中」那一列——手动在战斗里打字来不及。

⚠ **表头括号里那句 `(IN COMBAT)` / `(out of combat)` 才算数,`=== COMBAT ===` 只是标签。**
v0.3.0 之前 arm 是"进战 3 秒后无条件跑",而短战斗可能在 3 秒内就结束 ⇒
**把脱战样本打上 COMBAT 表头**,读起来完全像战斗列已经拿到了。
现在到点会先查 `InCombatLockdown()`,不在战斗中就不跑、**继续保持 armed**(会提示"拉个耐揍点的")。
交叉核对用 `GetAuraDataByIndex(target,1)`:脱战 `nil` / 战斗 `ERROR` —— 它是唯一一行会随战斗翻面的探针。

屏幕上方会出现**一行文字 + 一根橙条**：那是在测「secret 能不能被塞进 FontString / StatusBar 显示出来」。
读那两个控件**看屏幕**，不要看打印出来的值（打印的是 `SetText` 有没有报错，不是渲染结果）。

## 输出怎么读

每行是 `API 名  →  真实值 / SECRET / SECRET-TABLE / nil / ERROR`。

- `SECRET` = 拿得到但碰不得（比较/运算/取长度一律 Lua error）
- `nil` = **最阴的那种**：不报错，直接不给值（`RequiresNonSecretAura` 就是这个行为）
- `ERROR` = 调用本身被拒（`FailureMode = Error` 的那些）

## 📤 落盘通道 `_G.DodoProbeLog(tag, text)` —— 结果给 Claude 读,别让玩家截屏

任何插件都能写:`if DodoProbeLog then DodoProbeLog("dch", s) end`(**探测式调用,被测插件零依赖**,
没装 DodoProbe 也不崩)。`/dp` 整跑一次的结果**自动**进日志;`/dp log` 报条数;`/dp clear` 清空。

🔴 **机制 / 三步流程 / 那条「只在 `/reload` 或退出游戏时才落盘」的坑,正文在 canon
`rules/wow-addons.md`** —— 别在这儿抄第二份。这里只记本插件侧的三个位置:

- `LogPush` 必须放在 `StripColors` **之后**(要用它剥颜色码 —— 进文件的颜色码只是噪音还干扰 grep)
- `LOG_MAX = 3000` 上限:不设它只增不减,迟早撑大存档而没人发现
- `P:Run()` 结尾自动落一份 ⇒ 玩家不用记额外命令

⚠ `/dp clear` **只清 `DodoProbeDB.log`**,不碰 `pos` 那类别的字段。

## 分段资源条探针（0.12.0 新增）—— **结论只能从屏幕读**

屏幕上会多出**两排各 5 小段**（在原来那个图标下面）：

- **上排（蓝）= 明文 65 对照** —— 该是「前 3 段满 / 第 4 段 1/4 / 第 5 段空」
- **下排（橙）= secret 当前资源** —— 待验的那个

**判据 = 两排形状是不是同一个套路。** 打印那两行只说明 `SetValue` 没报错；
`GetValue` 回读永远是 `SECRET`（跟主条那两行同一个道理）。

⚠ **只画下排是没有判据的** ——「全空 / 全满 / 正确」三种结果在屏幕上长得都像
「它本来就这样」。上排存在的唯一理由就是把判据变成一个能一眼读出的对比，
顺带它还验证了「我对 StatusBar 钳制行为的理解」本身对不对。

**它在验什么**：分段资源（圣能 / 连击点 / 灵魂碎片）在 secret 下有没有活路。
每段一个 StatusBar、量程各自 `[(i-1)*step, i*step]`、**五段全喂同一个值** ——
钳制和填充比例都在 C 层算，插件一次比较都不做。这是「逐颗点亮」
（暴雪 `ClassPowerBar:TurnOn/TurnOff`，需要 `i <= 当前值`）在 secret 下唯一可能的替代形状。

🔴 **真正的判据是「下排跟着资源涨落而变」** —— 跑完 `/dp` 后下排会**实时刷新 60 秒**，
打两下看它涨落。因为 `/dp` 本身只是一次快照，而**静态一帧读不出结论**：

| 静态看到 | 可能是 | 也可能是 |
|---|---|---|
| 五段全空 | 资源真的是 0（暗牧**脱战恒 0**） | 钳制没生效 |
| 五段全满 | 资源真的满了（**法力脱战恒满**） | 值低于 min 时被显示成满 |

⇒ **两个静态状态各自撞上一种失败模式的长相**，所以必须**在战斗中、资源处于中间值时看，
而且要看它动**。`/dp arm`（进战 3 秒后自动跑）就是为这个准备的。

🔑 **跟职业无关**：这一组拿疯狂（0..100 分五段）验的就是钳制机制本身，
换成圣能 / 连击点只是 step 变了。⇒ **暗牧一个号就能验完，不用切职业。**

### 调研背景（2026-08-15）：这条路没有先例

GitHub 全站搜过，**没找到任何插件在 12.x 做出战斗中可用的分段资源条**：

- **暴雪自己** `ClassPowerBar` 逐颗点亮 —— untainted 特权，插件抄不了
- **主线 oUF** `classpower.lua` **零 secret 处理**（`UnitPower(...,true) / UnitPowerDisplayMod(...)`
  那个除法在 secret 下是硬崩）；**RealUI** `ClassResource.lua` 同样零处理
- **AzeriteUI5** 是唯一一个 classpower 里带 `issecretvalue` 的，而它的「适配」是
  **读不到就 `return nil`**、功能降级
- **NorskenUI** 有专门的 `Core/Secret.lua`，模型是「战斗中冻结 / 脱战补算」—— 对资源条不适用
  （资源条恰恰就是要在战斗中看）

⚠ 措辞照实：这是「GitHub code search 上没找到」，**不是**「不存在」。
但官方 / 框架 / 成品 UI / 专门适配层四个方向都撞同一堵墙，而墙本身是结构性的：
**任何「第 i 颗该不该亮」都是对 secret 的一次比较。**

⚠ 搜的时候栽过一次:`gh search code "issecretvalue UnitPower"` **带引号是短语搜索**
（要求两词相邻）⇒ 返回 0 命中，读起来完全像「没人做过」。
**不带引号才是 AND**（25 条）。凡拿搜索结果下「没有人 X」的结论，先用一组
**已知共存**的词做负对照验口径。

## `/dp lat` —— DoT 上身到图标出现,慢在哪一段(0.13 新增)

```
/dp lat     武装(再按一次关);放「痛」/「吸血鬼之触」/「癫」任一个开始计时
            4 秒后自动打印时间轴,**并自动收起**(不留常驻监听)
```

🔴 **它不测「图标什么时候出现」——那个量测不出来。** `button:IsShown()` 是 secret,
一做布尔测试当场崩。所以它测 `UNIT_AURA` **事件**几点到,并把「事件到了」画成
**屏幕上闪一个绿块** —— 参照物必须跟图标在**同一个视野**里,否则「事件的时刻」活在聊天框、
「图标的时刻」活在眼睛里,两个世界没法比。

**判据**(绿块 vs 名条图标):同时 = 事件层没问题 · 图标晚一拍 = 卡在暴雪容器的渲染/节流 ·
**绿块本身就晚 = 慢在事件层**,插件无能为力。

**2026-08-15 实测**:施法成功 → `UNIT_AURA(target)` = **3 毫秒**。
⇒ 事件通道本身不是瓶颈。⚠ 但那一跑的采样对象不对(见下),这条**只对那次施法成立**,
真要给 DoT 定性得重跑一次确认。

### 🔴 这个探针第一版栽的两个坑(都是「量错了对象」)

1. **触发条件太宽 ⇒ 忠实地测量了另一个事件。** 原本是「arm 后第一个施法就计时」,
   结果采到了**触须猛击**(一键输出建议的那个),而**输出看起来完全正常** ——
   一整屏漂亮的时间轴,没有任何迹象说明量的不是要查的那个东西。
   🔑 **救回来的是「它打印了法术名」** ⇒ 探针必须报出**它这次测的是谁**,
   否则量错对象时你看到的是一份可信的、干净的、无关的数据。现在只认 DoT 那三个 ID。
2. **身份从事件流里"推"= 被后续事件覆盖。** `plateN` 原本记「最后一个收到 UNIT_AURA 的 nameplate」,
   而周围的怪一直在刷 ⇒ 最后留下的是隔壁那只,于是容器状态那三行查了个不相干的单位。
   ⇒ 身份要在**触发那一刻**钉死(`GetNamePlateForUnit("target").namePlateUnitToken`)。

⚠ `c:IsEventRegistered("UNIT_AURA")` 对 AuraContainer 返回 **ERROR**(调用被拒),
**不是 false** —— 读不出「注册没有」这个结论,别把它当答案。

## 🎨 `/dp class` —— 战场里能不能拿到敌对玩家的职业色

```
/dp class            采一次:target + nameplate1..10,连区域上下文一起落盘
```

**起因**(2026-08-17):DodoNameplate 在战场里所有敌对玩家血条都是红的。`/dnp test` 回
`class: SECRET`,契约对上 —— `UnitClassBase` 标着 `SecretWhenUnitIdentityRestricted`。

**被测的线索** = `UnitClassFromGUID`。契约上 `SecretArguments = "AllowedWhenTainted"`
(⇒ 允许把一个 secret 的 GUID 递进去,而 `UnitGUID` 在受限内容里正是 secret),而三个返回值里
**只有本地化 `className` 带 `ConditionalSecret`**,`classFilename`(token)和 `classID` 都没标。

⚠ **第一次提取标注时 `ConditionalSecret` 被整个漏掉**,当时读出来就是「这函数完全没限制」——
干净、可复述、而且是错的。逐字重读才抓出来。**契约要逐字读,别信摘要。**

### 🔴 结论(2026-08-17 实测,寇魔古寺 `pvp`,已定案 —— 不用再跑)

```
target      GUID=SECRET   ClassBase=SECRET   || cName=SECRET   cFile=SECRET   cID=SECRET => rgb=n/a
nameplate1  GUID=SECRET   ClassBase=SECRET   || cName=SECRET   cFile=SECRET   cID=SECRET => rgb=n/a
nameplate3  GUID=T:string ClassBase=T:string || cName=T:string cFile=T:string cID=6      => rgb=0.77/0.12/0.23
```

**GUID 是 secret 时,`UnitClassFromGUID` 三个返回值全 secret** —— 包括契约上**没标**
`ConditionalSecret` 的 `classFilename` 和 `classID`。

🔑 **可迁移的那条:`SecretArguments = "AllowedWhenTainted"` 是「允许你递进去」,不是「允许你知道」。**
secret 从参数**传导**到返回值。看起来像洗白漏洞的标注其实不是 —— 正因为输出照样 secret,
输入才允许是 secret。凡看到这个标注就想「那我把 secret 喂进去换明文出来」的,先按传导假设。
配套:**per-return 的 `ConditionalSecret` 只标了三个里的一个,而实测三个全变** ⇒
canon 那条「契约只对『是不是 secret』权威」还要再弱一档 —— **它连这个都可能说不全。**

🎁 `nameplate3` 是**白捡的正对照**:同一战场同一瞬间,一个 GUID 明文的单位(队友)整条链一路明文、
颜色查出来了 ⇒ 排除「探针坏了」,并坐实这是**按单位身份开关的墙**,不是「没值」。
⇒ 野外那趟负对照因此**不需要**(它只在结果是 `nil` 时才有用)。

⚠ 这一轮暴露的探针缺陷,已修:`cell()` 对字符串一律返回 `T:string` ⇒ name / token 两格
打成类型名,拿不到「被测对象是谁」。现在照实打出来(超 24 字截断)。

**流程**(还要重跑时):进战场选个敌对玩家 → `/dp class` → 只有结果是 `nil` 才需要**出来野外再跑一次
(对照)** → `/reload` → 读 `DodoProbeDB.log` 里 `[class]` 那些行。

每行三态照实记(真值 / `nil` / `SECRET` / `ERR`),`ClassBase` 那格是已知被墙的对照:
```
nameplate3  name=某人  player=true atk=true | GUID=SECRET | ClassBase=SECRET ||
            FromGUID: cName=SECRET cFile=MAGE cID=8 => rgb=0.41/0.80/0.94
```

🔴 **判据是最后那格 `rgb`,不是 `cFile`。** token 明文但查不出颜色完全可能,那种情况这条路
仍然不通 —— 所以探针直接去查 `RAID_CLASS_COLORS` / `C_ClassColor`,查出数字才算通。

🔴 **契约只对「是不是 secret」权威,对「给不给值」不权威** —— 这条目自己写着
`MayReturnNothing = true`。前科:位置那四个 API 契约零 secret 标注,真机在副本里 x/y/z 全 `nil`。

🔴 **负对照做成可见的**:探针记下每种区域类型采过几次,跑完当场报「还缺野外 / 还缺战场那一半」。
没有基线,「战场里是 nil」跟「它本来就 nil」长得一模一样 —— 这条不靠谁记得。

## 📍 `/dp pos` —— 玩家坐标到底给不给值(0.14 新增)

```
/dp pos              开/关连续采样(每 0.4s;没动就不记)
/dp mark cross       站在某个标记上打一个**带名字**的点(square / triangle / circle)
/dp posclear         清空
```

**流程**:`/dp pos` → **先在副本外面走两步** → 进副本晃悠 → 站到四个标记上各 `/dp mark <名>`
→ `/dp pos` 关 → **`/reload`** → 读
`WTF\Account\<账号>\SavedVariables\DodoProbe.lua` 里的 `DodoProbeDB.pos`。

每条样本长这样,**三态照实记**(真值 / `nil` / `SECRET` / `ERR`),绝不对 secret 做运算:
```
W t=12.40 | x=1234.5678 y=-987.6543 z=55.12 wmap=2634 face=3.1416 |
           ui=2634 nx=0.4821 ny=0.5310 | boss=…,… tgt=…,… | c=0 | 名字/类型/实例id
```

🔴 **负对照是免费的,但漏了它整轮白跑**:先在副本**外面**采几条。没有基线,
「副本里 `nil`」跟「这台机器上它本来就 `nil`」**长得一模一样**。

🔴 **打点的名字必须在打点那一刻钉死**,不能事后从采样流里推 —— 推出来的会被
周围噪声覆盖成不相干的东西,而那几行读起来照样像回事(`/dp lat` 上栽过一次)。

🔴 **采样失败会落盘一行 `ERR!` 并停止**,不静默猝死 ——
「文件里只有前 20 条」跟「他走了 20 步就不走了」从外面看一模一样。

🔴 **自证**:每次加载都往 `DodoProbeDB.log` 写一行 `boot`。
⇒「文件里没有这次的东西」从此只可能是**忘了 `/reload`**,不会跟「插件没加载」混。
跟 canon 那条 `/dp log` 报条数是一对:**条数是"内存里有没有",boot 行是"文件里有没有"**,
两个一起才分得清「没跑」/「跑了没 reload」/「reload 了但 SavedVariables 声明没吃到」。

> ⚠ **一条自我更正(2026-08-16)**:本条最初写的理由是「落盘通道写在代码里却从没真产出过
> 一次文件」,并引了 canon「从没真跑过正是它长期零信号的原因」。**观察对,故事错了** ——
> 查 canon `git log` 才知道那条通道是**同一个上午 09:23 另一个 session 刚加的**,
> 我 08:2x 看到目录里没有 `DodoProbe.lua`,只是因为它**还是新的**,不是烂了很久没人跑。
> ⇒ **「我看到 X 不存在」和「X 一直是坏的」之间隔着一个「它存在多久了」** ——
> 那一步只要 `git log -S` 一次就能查,而不查就会给一个正确的观察配上一个错误的因果。

⚠ **想拿坐标硬编码四个象限的话,还差一问**:同一个点**两趟副本**读到的数一不一样。
不一样(每个 instance 一套坐标系)⇒ 硬编码这条路直接死。所以第二趟也要 `/dp mark` 同一个点。

**离线测试**(不用进游戏):
```
cd D:\World of Warcraft\_retail_\Interface\AddOns\DodoProbe
lua tools/test_cell.lua
```
它**从 `DodoProbe.lua` 里切出真的 `cell()` / `num()` 来跑**(不留手抄副本,免得漂),
并内联做 A/B:把 secret 守卫抽掉,`cell` 会把 `7000001.0000` 当成一个漂亮坐标写进文件、
`num` 会把它交给算术 —— 两条都必须红。

## 🔑 别在 wiki 上查 API 到底给不给数据 —— 查 Blizzard 自己生成的契约

warcraft.wiki.gg 是二手且大量残缺（实撞：同一个问题翻 6 个页面，关键页全写「本页未包含该信息」）。

**权威源**：
```
repo    Gethe/wow-ui-source      分支 live      (commit message 就是 build 号，可核新鲜度)
路径    Interface/AddOns/Blizzard_APIDocumentationGenerated/*.lua        (624 个文件)
```

关键文件：
| 文件 | 内容 |
|---|---|
| `SecretPredicatesDocumentation.lua` | **所有 secret 条件的定义**（`SecretWhenInCombat` / `SecretWhenCooldownsRestricted` / …），带原文说明 |
| `SecretAspectConstantsDocumentation.lua` | secret 能被塞进哪些视觉通道 |
| `UnitDocumentation.lua` / `SpellDocumentation.lua` / `UnitAuraDocumentation.lua` | 逐个 API 的限制标注 |
| `AssistedCombatDocumentation.lua` | `C_AssistedCombat` 全名单 |

扫法（拉下来 grep 就行）：
```bash
curl -s "https://api.github.com/repos/Gethe/wow-ui-source/git/trees/live?recursive=1"   # 找路径
curl -s https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua
```
标注长这样，直接在函数条目上：
```lua
{ Name = "UnitPower", Type = "Function", SecretWhenUnitPowerRestricted = true, ... }
```

🔴 **批量扫之前，先 dump 一条你已经知道答案的条目验口径。**
标注**一共三族,扫漏任何一族都会报出「这批 API 零限制」这个干净的错结论**:

| 族 | 长相 | 含义 |
|---|---|---|
| 无条件 | `SecretReturns = true` | 返回值恒 secret。**`UnitHealth` 用的就是这个** |
| 条件式 | `SecretWhen<条件>Restricted = true` | 满足条件才 secret(十几个名字,定义见 SecretPredicates) |
| 前置条件 | `Requires<X>` | 不给 secret、直接**拒绝**;`FailureMode` = `ReturnNothing`(静默 nil)/ `ReturnWithError` / `Error` |

⚠ 另有 `SecretArguments = "AllowedWhenTainted" / "AllowedWhenUntainted"` —— 那是说它**接受 secret 当入参**,
**不是**说它返回 secret。光 UnitDocumentation 里就出现 205 次,当成限制扫会把几乎所有 API 误判成被封。

> **校准记录(2026-08-14 第二轮)**:本节原文写的是「`SecretReturns = true` 是反的,真实标注名是
> `SecretWhen*` 一族」—— **那句本身是错的**。负对照(`grep -A6 '"UnitHealth"' UnitDocumentation.lua`)
> 当场推翻:`SecretReturns` 是真标注,而且正挂在最要紧的那个 API 上。照原句扫会整族漏掉无条件那类。
> ⇒ 印证了本节自己那条心法:**口径没验过的扫描结果不许写进结论** —— 包括这条心法上一版的结论。
> (通用版已进 canon `rules/engineering.md`。)

## 已知结论（2026-08-14 扫 12.1.0 build 69299 — **下个补丁重扫，别照抄**）

> ⚠ **2026-08-15 又跑了一轮，下面若干条被推翻或补充了** —— 例如「战斗中 per-spell `Aura=Never`
> 也失效」是**错的**（实测 `BySpellID 1/12`，命中的正是那个 `Never` 的；死的是枚举不是定点查）；
> `SetMinMaxValues` 吃 secret 已证；`GetSpellCooldown` 的字段确认是 secret。
> **完整且会继续更新的一份在 canon `rules/wow-addons.md`**，本节是当时那一次的快照。

> **活体实测已跑**(暗牧,受限地图,脱战 + 战斗中各一次)。下面 🟢/🔴 是**实跑结果**,不是只读契约。

**🟢 出招通道整条明文,战斗中不降级** —— 这是本次最重要的结论:

| 探针 | 脱战 | 战斗中 |
|---|---|---|
| `GetNextCastSpell()` / `(true)` | `1227280` | `1227280` |
| `→ GetSpellName(next)` | 触须猛击 | 触须猛击 |
| `→ GetSpellTexture(next)` | `7439212` | `7439212` |
| `IsAvailable()` | true,reason 空 | 同左 |
| `#GetRotationSpells()` + 名字 | 12,可遍历 | 同左 |
| 自己施法的 spellID | `589` | `589` |

⇒ **`GetNextCastSpell` → `GetSpellName` / `GetSpellTexture` 可以直接当插件引擎**,全程不碰 secret。

🔑 **`GetActionSpell()` ≠ `GetNextCastSpell()`**(实测 `1229376` vs `1227280`,别混用)。
查暴雪自己的 `Blizzard_ActionBar/Mainline/AssistedCombatManager.lua`:
`GetActionSpell` = "一键输出"**那个宏按钮自己**的 ID,`SPELLS_CHANGED` 时取一次的固定值;
`GetNextCastSpell(checkForVisibleButton)` 才是建议,暴雪在 `OnUpdate` 里轮询、变了才刷高亮,
频率走 cvar `assistedCombatIconUpdateRate`(**默认 0 = 每帧**)⇒ 调用开销可忽略。
暴雪传 `checkForVisibleButton = true`(只建议动作条上可见的);实测两者返回相同。

**🔴 死掉的(脱战就死,不用等战斗)**:

- `UnitHealth` —— `SecretReturns = true` **无条件**,脱战也 SECRET
- `UnitPower` —— 谓词原文是「除非该能量类型被显式标为永不 secret,否则一律 secret」,**跟战斗无关**;
  而 `UnitPowerMax` 给真值(100)。⇒ 「读当前资源排优先级」这条路 12.1 焊死,`DodoUnholy` 那套只能换引擎
- 光环:`GetPlayerAuraBySpellID` → nil;`GetAuraDataByIndex(target,1)` **脱战 nil / 战斗 ERROR**
  (`RequiresUnitAuraAccess` 的 FailureMode = `Error`)。🎁 **这一行是现成的负对照** ——
  它是脱战与战斗**唯一**行为不同的探针,拿它判「这份样本是不是真战斗中跑的」比看表头可靠

**⚠ 存疑,别当能用**:`C_Spell.GetSpellCooldown` **战斗中仍返回 `table(open)`**,与契约标注
`SecretWhenCooldownsRestricted` 不符。但 `table(open)` 只证明**表本身**不是 secret table,
**字段完全可能是 secret** —— 探针没往里读。要用它得先加一条「取 `.startTime` 出来 tag 一下」的探针。
- 🔴 **12.1 新收紧**：`UnitClass` / `UnitClassBase` / `UnitGUID` 现在带 `SecretWhenUnitIdentityRestricted`；
  `UnitIsUnit` 不再是无条件布尔（要求两个 token「可比较」）—— 旧插件里照老假设写的地方要复查

## 生命周期

一次性诊断工具，**不发 CurseForge**。留着是因为每个补丁都要重量一次。

🔴 **删这个文件夹之前先读这条 —— 它不是零依赖的。**
`DodoCombatHUD` 通过 `_G.DodoProbeLog` 拿它当落盘诊断通道(调用点在 `DodoCombatHUD.lua`,
搜 `DodoProbeLog`)。那是**探测式调用**(`if _G.DodoProbeLog then …`)⇒ 删了**不崩、不报错**,
只是 `/dch probe` 的落盘输出**安静地消失**,而那条通道正是「Claude 直接读文件、别让 Jerry 截屏」
的主路径 —— 症状会晚很久才被发现,且看起来像 DodoCombatHUD 自己坏了。
⚠ `DodoCombatHUD.toc` 的 `## OptionalDeps` 里**没有** `DodoProbe`,所以加载顺序也不保证。

**「还有没有别人依赖它」别信这一行,当场重数**(2026-08-22 全量核过 = 只有上面这一个):

```bash
git grep -n "DodoProbe" -- '*.lua' '*.toc' | grep -v '^DodoProbe/'
```

判命中的方法:**只有出现在可执行语句里的才算依赖**。当天 6 条命中里,真依赖只有
`DodoCombatHUD.lua:1469` 那一行 `if _G.DodoProbeLog then …`;其余(`DodoSays/Macros.lua`、
`DodoUnholy/Rotation.lua` 里指回本文的那几条,以及 DodoCombatHUD 自己的两句注释)全是**注释/散文**。
⚠ 别按「命中几条」下结论 —— 散文引用会越攒越多,而它们删了什么都不会坏。
