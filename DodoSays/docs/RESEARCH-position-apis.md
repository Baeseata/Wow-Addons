# 实测:玩家坐标在毒瀑深渊里给不给(2026-08-16)

> **证据等级:我方真机实测。** 采集 = `DodoProbe` 的 `/dp pos`,客户端 build **69299**,
> **副本内 190 条样本 vs 副本外 30 条负对照**,落 SavedVariables 后逐条读。
> 问题来源:能不能做「箭头指向安全区」/「玩家自己躲、插件自动记方向」。

---

## 1. 结论

**坐标不是 secret —— 是 `nil`。** 这是「有值 vs 没值」那条分界线里**没救**的一半:
`SECRET` 还能塞进 FontString / StatusBar 让 C 层自己画,`nil` **画都没得画**。

| API | 副本外(东部王国) | **副本内(毒瀑深渊 / scenario / 3079)** |
|---|---|---|
| `UnitPosition("player")` x / y / z | `6887.2002` / `-11502.1006` / `0` | **`nil`** |
| `UnitPosition` 第 4 个返回值 | `0`(东部王国) | **`3079`** ✅ |
| `GetPlayerFacing()` | `3.1853` | **`nil`** |
| `C_Map.GetPlayerMapPosition` | `0.5125` / `0.3133` | **`nil`** |
| `C_Map.GetBestMapForUnit` | `2512` | **`2634`** ✅ |

🔑 **最硬的一条:`UnitPosition` 的第 4 个返回值照给。**
⇒ 这个调用**没被拒绝、没抛异常**,它老老实实返回了四个值,**只是故意把前三个 nil 掉**。
不是 `Requires*` 拒绝,不是 secret,是「答了,但不告诉你位置」。

⚠ 全程 `InCombatLockdown() == false`。**不影响结论** —— 脱战就已经 `nil`,战斗中只可能一样或更严。
(要证明「能做」才需要补战斗中那一格;证明「不能」不需要。)

## 2. 🔴 契约在这个问题上是**沉默的**,不是在说「能」

build 69214 的生成契约里,这四个 API **三族标注一个都没有**
(`SecretReturns` / `SecretWhen*Restricted` / `Requires*`)⇒ **只读契约会得出「可以用」这个干净的错结论**。

- 限制整个活在 C 层,契约零建模:`UnitPosition` 连 `MayReturnNothing` 都没标、`Nilable = false`,
  按字面读它「永远返回四个数」。
- ⚠ 而 `MayReturnNothing` 在同两个文件里出现 **40 次** —— 「他们确实会标这种事」这个观察
  **反而**让人更信那个沉默。

⇒ 通法已进 canon `rules/wow-addons.md`:**契约只对「是不是 secret」权威,对「给不给值」不是。**

## 3. 有没有别的路 —— 613 份契约全量扫过了

扫的是本地整棵 `Blizzard_APIDocumentationGenerated`(不是搜索,无截断风险),
关键词 position / facing / rotation / direction / distance / speed / moving / coord / yaw /
angle / waypoint / navigation / compass / location / proximity / nearest / range,命中 191 个。
真正沾边的只有这些:

| API | 标注 | 为什么救不了 |
|---|---|---|
| `ClosestUnitPosition` / `ClosestGameObjectPosition` | 🔴 `SecretReturns` **无条件** | 连副本外都 secret |
| `UnitDistanceSquared(unit)` | 无 | **标量** —— 一个距离把你约束成一个圆,不是一个象限 |
| `C_Navigation.GetDistance()` | 无 | 同上,还得先有 supertrack 目标 |
| `GetUnitSpeed` | `SecretWhenUnitStatsRestricted` | 受限时 secret;**而且没有方向** |
| `IsPlayerMoving` | 无 | **只有布尔** —— 知道你动了,不知道往哪 |
| `Minimap:GetPingPosition` | 无 | 要玩家自己 ping = 又变回手动输入 |
| `C_Map.SetUserWaypoint` | 无 | 要 map 坐标才设得了,**而那正是拿不到的东西**(循环) |

**结构性论证(不是「我没找到」)**:把玩家分到 4 个象限之一需要**二维信息**;
活着的只剩**标量和布尔**。要三角定位就得有 **≥2 个位置已知、固定、不共线的锚点** ——
而这副本一个都没有:boss 位置读不到、布莱恩跟着你跑、地上四个标记**没有任何读取 API**
(`C_WorldMarker` 全仓库不存在)。

⚠ 唯一没实测的是 `UnitDistanceSquared`。就算它能用:按「红叉朝 boss」的约定,
到 boss 的距离最多分出 **cross(最近)/ triangle(最远)/ {square, circle}(不分伯仲)**
—— **4 类里 3 类,而剩下那两个是 50/50**。对踩错就死的机制来说比没有更坏。

## 4. 连带确认 / 推翻

- ✅ **`DELVE_MAPS = { [2634] }` 坐实**。它原是抄 SnakeSays 的、注释写着「NOT verified by us」;
  现在是我们自己量的。站立盘面那条路通。
- ❌ **推翻我方 `RESEARCH-snakesays-source.md` §2.4 的措辞**:那句「`UnitPosition` 不给数据」
  是抄作者注释的**二手**结论,且**没分清 `nil` 还是 `SECRET`** —— 而那个区别就是全部。
- ⚠ **「箭头做不了」的理由要说准**:参考插件 `Azta'rec Helper` 的箭头**根本不读坐标** ——
  它默认是 **boss 相对**(前提写在它自己的说明里:「Just always face the boss」),
  compass mode 则让玩家去对**游戏自己的小地图**。⇒ **它把定向外包给了玩家**,跟我们
  「手点四象限」是同一个套路。所以做不了的是**自动定位**,不是**箭头**。
