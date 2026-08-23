# DodoUnholy — 邪 DK 出招助手

只读 + 只显示的单体出招提示(绝不发按键)。`/duh config` 设置 · `scan` 导出技能 ID ·
`debug` 实时读数 · `lock`/`unlock` 锁图标。

> **当前版本 / 支持的客户端 → 看 `DodoUnholy.toc` 的 `## Version` / `## Interface`。**
> 这儿不写死,写死就会腐烂。

---

## 🔴 开工前必读:这个插件的核心引擎在 12.1 下已经失效

**症状是「静默降级」,不是崩** —— 所以它看起来还活着。

`Rotation.lua` 靠读**目标血量**和**符能**来排优先级,而 12.1 实测:

- `UnitHealth` —— `SecretReturns` **无条件**,脱战也 secret
- `UnitPower` —— 谓词是「除非该能量类型被**显式标为永不 secret**,否则一律 secret」,**跟战斗无关**

代码里有 `isSecret` 守卫 ⇒ 这两个读数**每次都返回 nil**,依赖它们的优先级行**永远跳过**。
界面还在、不报错、也不崩,**但它已经不是在按你的资源出招了**。

**证据出处**(实测结论正文只存一处,别在这儿抄):`DodoProbe/CLAUDE.md` 的「已知结论」节,
搜 `UnitPower` —— 那一节直接点名了本插件:「读当前资源排优先级」这条路 12.1 焊死,
**DodoUnholy 那套只能换引擎**。

⛔ **别顺手去「修」那几个读数函数** —— 修不了,那是结构性的。**换引擎是设计决策,归 Jerry 拍板**,
不是清理工作。真要动,方向是「不读值、让引擎自己判」那一类
(参考 `DodoGuanzhu/CLAUDE.md` 的一句话设计 / `DodoGrid/Dispel.lua`,以及
`C_AssistedCombat` 出招建议 —— 后者战斗中不降级,但结构上无前瞻)。

## ⛔ 战斗日志:注册它是一次真伤害,别再加回来

`Rotation.lua` 里原有的 `ProbeCombatLog()`(`/duh cl`)已于 **2026-08-22 删除**,
`DodoUnholy.lua` 里对应的分发分支和帮助行一并删掉。

**理由**:12.x 对插件**彻底关闭**战斗日志 —— 即使干净的加载期 chunk 注册
`COMBAT_LOG_EVENT_UNFILTERED` 也抛 `ADDON_ACTION_FORBIDDEN`,而**一次 forbidden 调用会污染
当时调用栈上的一切**;当晚 boss 血条消失被怀疑(未坐实)就是它。
⇒ 危险不在「探针没用」,在**跑它一次就伤到别的插件 / 暴雪自己的界面**,而症状离肇事点很远。

**证据出处**:`DodoSays/Trace.lua` 顶部那段 `REGISTER_FAILED` 注释(搜
`COMBAT_LOG_EVENT_UNFILTERED`),实测 2026-08-15。

🔴 **别加回来。** 想重新量这件事,只该在 `DodoProbe` 里带一次性开关做,
不该躺在一个日常插件的 slash 命令里。

## 装机

⚠ **repo ↔ 游戏 AddOns 目录不是 junction(两台机都不是,2026-08-22 实测)⇒ 改完必须拷。**
不拷的症状是 `/reload` 后什么都没变,读起来像代码 bug。两台机形状不同、路径见该机
`~/.claude/CLAUDE.md`;完整流程照 [`../DodoGuanzhu/CLAUDE.md`](../DodoGuanzhu/CLAUDE.md) 的「装机」节。

- 改**已有 .lua 内容** → `/reload` 就够;**加新文件并写进 TOC** → 完整重启客户端。
- 改完必跑 `luac -p <file>`(canon 铁律;负对照验过它真会报行号)。
