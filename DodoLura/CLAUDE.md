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

- PA 对插件完全不可读(无事件/无 UnitAura/无 CLEU)。仅有两个托管接口:
  - `C_UnitAuras.AddPrivateAuraAppliedSound` —— **按 spellID 精确**,本插件用这个(Master 通道,开怪注册/结束注销,见 Core.lua)。
  - `C_UnitAuras.AddPrivateAuraAnchor` —— 按 auraIndex 槽位**不认 spellID**,同场其他 PA(蚀变吸收/黑暗符文等)会混入 → "仅星辰裂片图标"做不到,DBM/BigWigs 同样做不到。讨论过,放弃。

## 发布

- CF project **1602130**(Wow-Addons 家族 workflow,case map 已注册);发版 = 改 TOC `## Version:` → commit → tag `DodoLura-vX.Y.Z`(annotated,tag message = changelog,`--cleanup=verbatim`)→ push。
- zip 只收 lua/toc/README/媒体文件 —— AirHorn.ogg 能进包,本文件(CLAUDE.md)和 .txt 不进包。AirHorn.ogg = CC-BY 3.0 Mike Koenig(README 已署名,勿删)。
- 1.0.0 于 2026-07-08 上传成功(HTTP 200),等 CF 首次人工审核后公开。

## 未来风险(唯一的维护点)

DBM 的 MidnightFalls.lua TODO 预言:玩家摸清哪个 PA 对应哪机制后,**暴雪可能直接禁用这批 PA** → 本插件会**无声失效**(注册照样成功,只是永远不响)。到时候的出路:抄 DBM 的新方案(它计划切到 Dark Rune 类 encounter event / 官方 timeline 事件 437),或者看 BigWigs 怎么改。症状 = "打鲁拉被点名但没喇叭",先查 DBM 更新日志。
