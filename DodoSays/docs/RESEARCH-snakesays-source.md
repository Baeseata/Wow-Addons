# 调研:SnakeSays 源码实读(v3.2.1)

> 2026-08-15 · HOME · 来源 = `github.com/lgkern/SnakeSays` @ v3.2.1(2026-08-12 发布)的
> `Detector.lua` / `Core.lua` 原文 + 作者自己的注释。
>
> ⚠ **证据等级**:这是**竞品作者的实测记录**(他注释里多处引用"the author's own event traces"
> / "a logged pull" / "a logged hard round"),**不是我方实测**。当**高质量的预期答案**用,
> 仍要跑 [`PROBE-CHECKLIST.md`](PROBE-CHECKLIST.md) 核。
> 好处:有了预期,探针就从「发现」变成「核对」—— 而**核对能分辨「探针没装上」和「事实变了」**,
> 光靠发现分辨不了。

---

## 1. 🔴 推翻我方文档的两条

### 1.1 「布道半场」是**看不见**的 —— 没有逐波事件,波数只能靠时钟

我方 `CLAUDE.md` §3 那句「回响的每一波各是一次独立 cast ⇒ 节拍不用推测也不用测量」
**只对回响半场成立**。布道半场**完全相反**,作者原文:

> *"The showing half is invisible: no cast, no damage, no unit event per wave.
> What it does have is the boss channelling Sermon of Ula'tek for exactly one slot per wave,
> so the round announces its own length the moment it starts."*

⇒ **整个布道 = 一次 channel**,波数 = `channel 时长 ÷ 每波秒数`。
所以这插件是**两个半场两套机制**:showing 半场**由时钟驱动**,calling 半场**由事件驱动**——
作者原话「the two halves of this file look nothing like each other on purpose」。

配套硬数据(`SEED_SLOT`,他标明只是种子、`learnSlot()` 会从实战覆盖):
**normal 3.503 秒/波 · hard 3.003 秒/波**。

⚠ **而 channel 的 `startMS`/`endMS` 也常常是 secret** ⇒ 连"这次布道多长"都读不到。
这就是他为什么要硬编码一张 `WAVES_BY_ROUND = { normal={3,4,5}, hard={5,6,7} }` 当兜底 ——
**没有它,波数要到整轮结束才知道,盘面就不是边看边填而是最后一次性砸出来。**

### 1.2 布道的 spellID **在 `?` 上每一轮都不一样**(`??` 上才固定)

我方 `CLAUDE.md` 写「只做这赛季 ⇒ spellID 可硬编码」——**对回响成立,对布道不成立**。作者原文:

> *"the spell id changes between rounds on normal and stays put on hard, so it says
> nothing at all about how long the round is. The duration does."*
> *"…this list is expected to be incomplete, and an unrecognised channel is checked by
> its length instead."*

⇒ 他那两个 id(`1288103` normal / `1306239` hard)是**快捷方式,不是判据**。
真正认布道靠三级:**名字 → id → 形状(时长)**,`findSermonChannel()` 里那个 `how` 变量就是记这个。

---

## 2. 我方文档完全没有的硬事实

### 2.1 encounterID 已知 ⇒ 难度不用猜

```lua
ns.ENCOUNTERS = { { id = 3508, label = "normal" },   -- ?
                  { id = 3525, label = "hard"   } }  -- ??
```
作者标明这是「**facts the client hands over in `ENCOUNTER_START`**」。
⇒ 探针第 1 条(`ENCOUNTER_START` 触发吗)和「怎么知道是 `?` 还是 `??`」**一次解决**,
而序列长度表按难度查即可。

### 2.2 🔴 `??` 的分身**跟回响撞名** —— 围栏不是"防杂散",是防一个会主动骗你的东西

`??` 中场召唤的分身叫 **"Echo of Azta'rec"**,而作者发现:
**它的普通技能名字读起来也是 "Echo of ..."**。后果他有实测:

> *"a logged hard round spent two of its five calls on them."*

**五次报点里两次被分身骗走。** 这比我方文档记的「7 次施法里 3 次是报点」严重得多 ——
那条是**噪声**,这条是**赝品**。

他的解法是**按身份而不是按来源**认:GUID 拿得到就比 GUID;拿不到就认
「**哪个 boss 展示了这一轮,就是哪个 boss 报点**」(`isOurBoss()` 比 `showing.unit`)。
⚠ **只判「来自 boss 框体」会全放行** —— 原文「lets every one of them through」。

⇒ **我方架构表里那句「用 `RegisterUnitEvent(..., "boss1")` 引擎侧过滤」不够**:
它挡得住小怪,挡不住 boss2。

### 2.3 候选 unit 不止 `boss1`,而且他用 0.2s 轮询兜底

```lua
CANDIDATE_UNITS = { "boss1".."boss5", "target", "focus", "nameplate1".."nameplate3" }
POLL_INTERVAL   = 0.2
```
理由(原文):**「地下堡不是团本,没有任何保证说客户端会给 nemesis 一个 boss token」**。
⇒ **探针第 2 条必须真跑**,别照抄"就是 boss1"。

### 2.4 两条 Secret Values 侧的新事实(canon `rules/wow-addons.md` 可吸收)

- 🔴 **`C_UnitAuras` 对 tainted caller 是「前置拒绝」,不是「返回 secret」**——
  原文报错 `GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted`。
  ⇒ 按 canon 三族分类这属于 `Requires*`(拒绝)而非 `SecretWhen*`(脱敏)。
  **所以他的主路是 channel、aura 只是 fallback** —— 跟直觉相反。
- 🔴 **`UnitPosition` 在这个竞技场、战斗中不给数据**(`Core.lua:47` + `Detector.lua:12` 各说一遍)。
  ⇒ 「玩家手动点四象限」**不是产品选择,是技术上唯一可行的路**。
  我方 `CLAUDE.md` §1 把它写成了设计决策 —— 结论对,但**理由记错了会让人以后想去"优化"它**。

### 2.5 两个半场的交接是**精确**的

> *"a logged pull stopped the channel and started the first call in the same hundredth of a second."*

⇒ `CHANNEL_STOP` 直接当"锁序列 + 转回放"的信号是安全的,不用留缓冲。

---

## 3. 攻略侧:序列长度**已被两个独立源交叉确认**

Icy Veins 与 Method 各自给出:触发 **90% / 60% / 30%**,
`?` = **3 / 4 / 5**,`??` = **5 / 6 / 7**,`??` 额外召 Echo of Azta'rec。
⇒ 跟我方 `RESEARCH-boss-mechanics.md` 一致 ✅,且跟 SnakeSays 代码里的 `WAVES_BY_ROUND` 一致(第三个源)。
**这三个源里只有代码那份是从实战校正过的**,但三者不冲突。

## 4. 对 [`PROBE-CHECKLIST.md`](PROBE-CHECKLIST.md) 的影响

**一条都不删** —— 但第 1、2、6 条现在有了预期答案,跑的时候是**核对**:
对不上说明「客户端变了」或「探针没装上」,而这两种**只有在有预期时才分得开**。
第 3、4 条(spellID / name 是不是 secret)仍是**纯发现**,而且仍然决定工作量 ——
作者留三层降级链这件事本身说明**他也没拿到稳定答案**。
**新增建议第 7 条**:`??` 场上同时有两个 boss 时,`UNIT_SPELLCAST_START` 到底从哪个 unit token 来
(见 §2.2 —— 这条不验,`??` 上会直接报错点)。

