# DodoLura — 交接档案

> 鲁拉(至暗之夜)星辰裂片点名气喇叭。**零设置是 Jerry 拍板的设计**,别加选项界面。
> 起因:DBM 的点名警报时响时不响,Jerry 嫌烦,要一个"载入就响、没有任何层能吃掉警报"的极简件。

## 关键 ID

- Encounter **3183** = Midnight Falls / 至暗之夜(March on Quel'Danas,zone 2913);boss L'ura/鲁拉 = NPC **240391**(DBM 模块里写的 214650 是军团旧 L'ura,别照抄)。
- 星辰裂片 spell **1282441**;点名 private aura = **1279512 / 1285510**(两个变体,DBM/BigWigs 挂的同一对)。

## 机制调研结论(2026-07-08,多源交叉验证过)

- 星辰裂片只在 **P1→P2 过渡阶段**(完全蚀变 Total Eclipse → 坠入暗渊之井)点名,全难度;**Mythic 另有 P4 斩杀阶段循环点名**(BigWigs:首发 12.7s,之后每 20s;P4 = P3 中 boss2 消失后进入,注册链 Mythic-only)。
- 点随机玩家(复数,无职责限制,无来源给确切人数);点名者朝面向射尖刺光束,队友吃大伤 → 打法 = 拉开朝外放。6/16 官方修复"不再同时双点同一人"。

## 为什么只做声音、不做图标(API 硬限制)

- PA 对插件完全不可读(无事件/无 UnitAura/无 CLEU)。能安全利用的托管接口:
  - 12.1+ `C_UnitAuras.AddAuraSound(Enum.UnitAuraSoundTrigger.Added, soundInfo)` —— **按 spellID 精确**,本插件用这个(Master 通道)。12.0.x 回退到旧名 `AddPrivateAuraAppliedSound(soundInfo)`。
  - `C_UnitAuras.AddPrivateAuraAnchor` —— 按 auraIndex 槽位**不认 spellID**,同场其他 PA(蚀变吸收/黑暗符文等)会混入 → "仅星辰裂片图标"做不到,DBM/BigWigs 同样做不到。讨论过,放弃。
- `AddAuraSound` 在战斗/聊天限制期间不能新增注册。因此 1.1.0 起不再等 `ENCOUNTER_START`:进入 March on Quel'Danas(instanceID **2913**)时预注册,离区注销。若在战斗中 `/reload`,监听 `ADDON_RESTRICTION_STATE_CHANGED` 并在 Chat restriction(5)变为 Inactive(0)后重试,供下一把使用。

## 发布

- CF project **1602130**;发版 = 改 TOC `## Version:` → commit → tag `DodoLura-vX.Y.Z`(annotated,tag message = changelog,`--cleanup=verbatim`)→ push。
  ⚠ 那两个 tag 修饰不是风格,各对应一次真踩过的坑,**打完 tag、push 之前各验一句**:
  **annotated** —— lightweight tag 会把 commit message 当 changelog 甩上 CF(而我们的 commit message 是中文);判据 `git cat-file -t <tag>` 必须回 `tag`,回 `commit` 就是 lightweight。
  **`--cleanup=verbatim`** —— git 默认 strip 模式把 `#` 开头的行当注释删掉,而 changelog 是 Markdown、标题正是 `#` 开头 ⇒ **所有段落标题静默消失,打完毫无提示**;判据 `git tag -l --format='%(contents)' <tag> | grep '^#'` 必须有输出。
  ⚠ 本插件的 project id **走 workflow 里那张 case 表兜底**(`curseforge-release.yml`),TOC 里没有 `## X-Curse-Project-ID` —— 而 workflow **优先读 TOC 那一行**,新插件按 TOC 那条路走、不用改 workflow。
- zip 只收 lua/toc/README/媒体文件 —— AirHorn.ogg 能进包,本文件(CLAUDE.md)和 .txt 不进包。AirHorn.ogg = CC-BY 3.0 Mike Koenig(README 已署名,勿删)。
- 🔴 **`Media/Dodo.tga` 是这个插件自己的副本,别当重复资产删掉。** CF 的 zip **只装 `DodoLura/` 这一个目录**
  (`curseforge-release.yml` 的 Build 步骤 `cd "$ADDON"`),所以从 CF 单独装的用户机器上
  **`Interface\AddOns\Dodo\` 根本不存在** —— TOC 的 `## IconTexture` 一旦指回 `AddOns\Dodo\`,
  那一格图标对**所有外部用户**就是空的,而**在开发机上永远看不出来**
  (HOME 和 OMEN 的 AddOns 目录里 Dodo 整合包都装着,路径永远解析得到)。
  DodoInspect / DodoNameplate / DodoSays 同样各自带一份,四份 md5 相同是**有意的**。
- **发到哪一版 / 过审没有 → 查 `DodoLura.toc` 的 `## Version` + CF 项目 1602130 的 Files 页**,
  别信 doc 里写的数字(1.0.0 首发于 2026-07-08)。
- 1.1.0 = WoW 12.1 兼容版:Interface **120100**,迁移 `AddAuraSound/RemoveAuraSound`,保留 12.0.5/12.0.7 API 回退,并改为 zone-based 预注册。

## 未来风险(唯一的维护点)

12.1 的 `AddAuraSound` 对普通 aura 也有效,所以仅仅把 Starsplinter 从 private aura 改成普通 aura 不一定会弄坏插件。真正的风险是暴雪移除/替换 **1279512 / 1285510**、不再施加 aura,或再次改动声音 API;这些情况会让注册看似成功但永远不响。症状 = "打鲁拉被点名但没喇叭",先查 DBM/BigWigs 的 MidnightFalls 更新和最新 Blizzard API;若机制改成 encounter event / 官方 timeline 事件,跟随它们的新方案。
