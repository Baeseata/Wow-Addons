# DodoGuanzhu · PENDING-WORK

> ⚠ **验证基座 = 本机 Lua 5.4 + 手写 stub**(每条修复都配了 A/B,种回缺陷会精确变红)。
> stub 建模的是 GOTCHAS 里那批实测常量,而「stub 对不对」本身没在真机逐条复验过 ⇒
> **凡本文件里的断言,真机第一次走到那条路径时都该当场核一遍。**
>
> ⚠ **别在这儿写「跑没跑过真机」这种会腐烂的状态**(2026-08-22 修:原文写着「一行都没在真
> 客户端上跑过」,而**同一份文件末尾**就有一节「这轮真机验收发现的(2026-08-18 晚)」+ 截图
> 确认 —— 开头和中段自相矛盾,而开头那句是所有人读到的第一句)。
> 要知道真机走到哪儿了:看下面各节的日期戳 + `git log -- DodoGuanzhu/`。

---

## 🔴 阻塞:那个未验证假设

- [ ] **验「队友名字能不能解析成 unit」** —— 组个队,选中队友,`/dp macro`,看
      `[@目标名字,exists]`。成立 ⇒ 什么都不用改;判假 ⇒ `@名字` 整条路线作废,
      **只改 `Macro.TokenFor` 一个函数** + 加 `GROUP_ROSTER_UPDATE` 战斗外重写。
      详见 [GOTCHAS.md](GOTCHAS.md) §1。

## 已知会崩的(路径很窄,但实测崩)

- [ ] **`Slash.lua` 两处 `tostring` 漏包**:`set` 失败路径的 `table.concat` 吃未 tostring 的
      `x.name`(跨 Lua 版本都崩);`rmlist` 成功路径 `ns.Current().name` 未 tostring
      (游戏的 5.1 上抛 `bad argument #4 to 'format'`)。触发条件 = 方案名被写成非字符串。
- [ ] **`Macro.lua:339`** `ipairs((db and db.lists) or {})` —— `db.lists` 非表时抛错,
      而它在 `PLAYER_REGEN_ENABLED` 的 OnEvent 里、外面没 pcall ⇒ **排队的写宏从此一次都补不上**,
      还每次脱战刷一条错误。⚠ 暴露面窄(Core 在 ADDON_LOADED 归一化过 `db.lists`),
      但这是「修类不修例」没走完的那一处 —— 同族的 `list.members` **从来没有任何地方归一化**。

## 结构洞(同一个形状散在三处)

- [ ] **`IsSecret` 的 blanket-false 兜底** 在 `Preview.lua:16` / `Macro.lua:102` 还活着
      (`issecretvalue` 不存在时返回 false)。它在**最该救命的那次**把「结构性保证」变成结构性漏洞。
      Capture 那份已按最保守改;另两处要跟上。⚠ 本机造不出真 secret 值,**验不了** ——
      只能靠写法本身保守。

## 小的

- [ ] `Options.lua` 战斗中开的录入,脱战后设置窗不会自己回来(`StepAside` 只在小窗未显示时调一次)。
- [ ] `Macro.lua:38` / `Core.lua` 各有一处 `pcall(C_Spell.X, ...)` —— **参数在 pcall 之前求值**,
      `C_Spell` 若为 nil 这一步不受保护。12.x 上必在,风险极低,但两处要一起收。
- [ ] `dirty` 是**全局一个 bit**:写方案 B 会把「方案 A 改了还没写」一并清掉,多方案时 Preview 偏乐观。
      要收紧就在 Core 改成 per-list。
- [ ] `Macro.lua:290` 截断判据假定客户端存回来的正文跟送进去的等长。客户端若做 trim /
      换行归一化,会把一次**成功**的写误判成截断并回滚。本机验不了。

## 这轮真机验收发现的(2026-08-18 晚)

- [ ] **面板顶部说明文字第二行超出面板右边** —— 文字没设宽度上限、不换行。
      要给那几行加 `SetWidth` + 自动换行。(截图确认,未修。)
- [ ] **`Options.lua` 还有 4 处、`Preview.lua` 1 处裸 `pcall` 不看返回值** —— 跟
      「左键小地图没反应」那个 bug 同族(失败被完整吞掉 ⇒ 症状是"点了没反应")。
      不一定都是 bug(tooltip 那类失败了确实无所谓),但要**逐个看过**才知道。
- [ ] **`Preview` 浮标宽度 250 是拍的** —— 跨服名 `Phoenìxr-Sargeras` 在 200 下被截断,
      加到 250 够不够**没在真机上确认过**(本机没有字体度量)。
