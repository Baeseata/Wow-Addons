# Dodo — 父包 / 公共库(Project Notes)

> **它是什么**:整个 Dodo 全家桶的**父包**,不是一个功能插件。三个文件而已:
> `Dodo.toc` + `Shared.lua`(公共库,挂在全局表 `_G.Dodo`)+ `Media/Dodo.tga`(共享图标)。
> 装它不干任何事,只是把 `_G.Dodo` 和那张图标摆出来给子插件用。

---

## 它提供什么(权威 = `Shared.lua`,下面是注释版)

| 名字 | 干嘛的 |
|---|---|
| `Dodo.CopyDefaults(dst, src)` | 递归补默认值,**不覆盖已有值**,返回 `dst`。子插件的 DB 初始化几乎都用它 |
| `Dodo.Clamp(x, lo, hi)` | 数值夹取(`tonumber` 失败回落 `lo`) |
| `Dodo.Print(tag, msg)` | 带彩色前缀的打印 —— `Dodo.Print("Pool", "x")` → `Dodo[Pool] x` |
| `Dodo.Money(copper)` | 铜钱 → `"12g 34s"` 文本 |
| `Dodo.Register(name, module)` | 把子插件挂进 `Dodo.modules`,给将来的包级面板留的钩子 |
| `Dodo.Media(file)` / `Dodo.mediaPath` / `Dodo.icon` | 共享素材路径(`icon` = `Media/Dodo.tga` 全路径) |
| `Dodo.db` / `Dodo.version` | 包级 SavedVariables(`DodoDB`,`ADDON_LOADED` 时挂上)/ 库版本串 |

**这个库里有些东西没有任何调用方**(纯预留)。别照着表凭感觉判,当场数:

```bash
grep -rnE '_G\.Dodo\.(CopyDefaults|Clamp|Print|Money|Register|Media|icon|db)' --include=*.lua . | grep -v '^\./Dodo/'
```

---

## 🔴 唯一一条要记住的契约:**不是每个 Dodo 插件都够得着 `Dodo.*`**

只有 TOC 里写了 **`## OptionalDeps: Dodo`** 的插件,才保证 `Dodo` 已经先加载完
(`## Group: Dodo` 只管在插件列表里折叠显示,跟加载顺序无关)。

**`DodoInspect` 和 `DodoNameplate` 故意两个都不挂** —— 它们要能**独立发 CurseForge**,
装它们的人多半没装 `Dodo` 包。这不是漏写,**别"顺手补上"**。谁挂了谁没挂,当场数:

```bash
for f in */*.toc; do grep -qE '^## OptionalDeps:.*Dodo' "$f" || echo "$f"; done
```

⚠ **这条契约的实际后果:往 `Shared.lua` 加一个新的共享 API 时,
你等于给「不是所有插件」加了个功能** —— 有插件永远调不到它。
所以每个新 API 都要么只服务于挂了 `OptionalDeps` 的那批,要么在调用方配本地兜底。

### 子插件该怎么调(照抄 `DodoBricks/Core.lua` 那个形状)

```lua
local function Print(msg)
    if _G.Dodo and _G.Dodo.Print then _G.Dodo.Print("Bricks", msg)
    else print("|cff33ff99DodoBricks:|r " .. tostring(msg)) end
end
```

**探测 + 本地兜底,永不裸调 `Dodo.X`。** 挂了 `OptionalDeps` 也一样要兜 ——
玩家可以单独把 `Dodo` 关掉,而 optional 依赖缺席**不报错、只是 `_G.Dodo` 是 nil**。

⚠ 同理:**别在要独立发 CF 的插件里引用 `Interface\AddOns\Dodo\Media\...`** ——
CF 包只装那一个插件的文件夹,图标会指向一个不存在的路径。
自带一份 `<自己>/Media/Dodo.tga` 就行(现在上 CF 的那几个都是这么干的)。

---

## ⛔ 为什么 `isSecret` **不在**这个库里(有人一定会想搬进来)

Secret Values 是整个仓库里跨插件出现频率最高的技术主题,而 `Shared.lua` 里
**一个 secret 相关的东西都没有** —— 这看起来像个明显的遗漏,**它不是**。

`DodoInspect` / `DodoNameplate` 按上面那条契约**运行时根本调不到 `Dodo.*`**,
而它们恰恰是 secret 判定用得最重的两个。把 `Dodo.IsSecret` 立成"唯一实现",
只会让最需要它的两个插件继续用自己那份,而现在大家至少**知道**自己在用副本。

⇒ 现状是**几份刻意的手写副本**(`DodoNameplate/Guards.lua` · `DodoSays/Util.lua` ·
`DodoUnholy/Rotation.lua` · `DodoGuanzhu/Macro.lua`,另有几个插件内联裸调 `issecretvalue`)。
**规矩:每一份都必须是同一个形状**(type 探测 + `pcall` + 归一成布尔),
并且**在自己旁边写清「这是刻意的副本、改一处要改全部」+ 一条重新数出全部副本的命令**。
新写一份而不照这条办 = 又造了一个静默分歧发生器。当场数一遍是哪几处:

```bash
grep -rnE 'issecretvalue|canaccessvalue|C_Secrets' --include=*.lua . | grep -v '^\./Dodo/'
```

---

## 改这个包要小心什么

- **它是纯加法安全、减法危险**:加函数不影响任何人;**改签名 / 改返回值 / 删函数**会同时打到
  所有挂了 `OptionalDeps` 的插件,而它们**各自还有本地兜底** ⇒ 行为漂了不会报错,
  只会两条路各走各的(canon:同一不变式两份手写实现 = 静默分歧发生器)。
- `Dodo` 不上 CurseForge(monorepo 的发版 workflow 只对 `<Addon>-vX.Y.Z` tag 开火,
  它的名单见 `.github/workflows/curseforge-release.yml`)。
- 版本 / 支持的客户端 build 一律读 `Dodo.toc` 的 `## Version` / `## Interface`,别信任何抄本。
