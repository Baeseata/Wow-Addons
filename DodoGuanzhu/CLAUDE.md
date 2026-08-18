# DodoGuanzhu — 能量灌注顺位

牧师技能**能量灌注**(Power Infusion, spellID **10060**)的优先级名单:预配最多 8 人,
生成一个宏;按那个宏时**宏条件自己**从左往右挑第一个可用的人,都给不出去才给自己。

```
#showtooltip
/cast [@focus,help,nodead][@名1,help,nodead][@名2,help,nodead][@player] 能量灌注
```

## 🔑 一句话把握这个设计

**优先级 fallback 完全由宏条件完成,插件在战斗中不做任何决策。**
插件只干三件事:①(战斗外)把名字写进宏 ② 让玩家点鼠标录名单 ③ 显示"下次会给谁"。

这跟 `DodoGrid/Dispel.lua` 是同一个思路 —— 它的注释原话:*让游戏自己挑要驱散的 debuff,
我们从不 READ aura 数据*。12.x Secret Values 挡的是「插件读了去算」,不挡「让引擎自己判」。

## 🔴 开工前必读

1. **[GOTCHAS.md](GOTCHAS.md)** —— 九条**真机实测**事实(12.1.0 build 120100)。
   尤其 §1 那个**未验证假设**:`@名字` 对队友解不解析得成 unit。**它没被验证过**,
   整份代码只把它落在 `Macro.TokenFor` 一处,证伪了只改那一个函数。
2. **[PENDING-WORK.md](PENDING-WORK.md)** —— 剩下什么活。⚠ **进度只看它,别信本文**。
3. 想知道某条实测事实怎么来的:探针是 `DodoProbe` 的 **`/dp macro`** 子命令,
   跑一次就把那批事实重新量一遍(它自己钉了基准值,对不上就是暴雪改了)。
   跨项目通用的那半已升级到 canon [`rules/wow-addons.md`](~/.claude/canon/rules/wow-addons.md)「宏 API 与宏条件」节。

## 模块

| 文件 | 干什么 |
|---|---|
| `Core.lua` | SavedVariables · 名单数据结构 · **`NormalizeName`/`SameName`/`ValidateName` 唯一一份** · dirty 标记 |
| `Macro.lua` | 宏正文生成 + 写入(幂等 / 防撞名 / 长度闸 / 截断回滚 / 战斗中排队) |
| `Capture.lua` | 点鼠标录名单(`PLAYER_TARGET_CHANGED`,不 hook 任何框架) |
| `Preview.lua` | 浮标:下次会给谁 + 射程警告 + dirty 提示 |
| `Slash.lua` | `/dgz` —— **完整后路,面板只是它的皮**(这哲学抄自 `DodoCombatHUD/Options.lua`) |
| `Options.lua` | 设置面板(ESC→选项→插件),骨架抄 `DodoShield/Options.lua` |
| `Minimap.lua` | 小地图按钮,几何和 scale 处理**逐字抄** `DodoSays/Minimap.lua` |

## ⚠ 改之前必须知道的三条

- **名单顺序 = 优先级本身** ⇒ 任何地方**都不许 sort**,行序只能由 ▲▼ 改。
- **一切写宏 / `SetAttribute` 都是 OOC-only** ⇒ 战斗中置 dirty,`PLAYER_REGEN_ENABLED` 补做。
- **Preview 的主判断必须照宏的逻辑算(不考虑射程)**,射程只作附注。
  让 Preview 自作主张跳过超距离的人 = 它跟宏说两件事,而宏才是真执行的那个。

## 🔴 改面板布局:别用 grep 找空位

同一个错误这个 session 犯了**三次**。坐标散在**至少三种写法**里
(`SetPoint("TOPLEFT", x, y)` · `MakeCheck(panel, label, x, y)` 传参 · 相对定位),
而且**光有坐标不够 —— 还要读 `SetSize`** 才知道那个控件占到哪儿。

⇒ 动布局前跑这个(扫**所有** `-数字`,不管什么写法):

```bash
python -c "
import io,re
s=io.open('Options.lua',encoding='utf-8').read()
print(sorted({-int(m.group(1)) for m in re.finditer(r'-([0-9]{3})[,)]', s)}))"
```

批量挪坐标**必须从大到小**改,否则 `-392→-424` 会撞上还没改的原 `-424`。

## 装机

repo ↔ 游戏 AddOns 目录**不是 junction**(至少 OMEN 上不是)⇒ 改完要拷:

```bash
cp -f *.lua *.toc "<该机的 AddOns 路径>/DodoGuanzhu/"
```

各机 AddOns 路径不同,见该机 `~/.claude/CLAUDE.md`。拷完**逐文件比 sha256**,别信 `cp` 没报错。

- 改**已有 .lua 的内容** → `/reload` 就够
- **加了新文件并写进 TOC** → 必须**完整重启客户端**(TOC 只在启动时读一次)
- 改完必跑 `luac -p <file>`(canon 铁律;负对照验过它真会报行号)
