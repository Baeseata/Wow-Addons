# DodoNameplate

A lightweight, category-based nameplate addon for World of Warcraft Retail (Midnight 12.1). It combines per-unit-category styling with threat, target, cast, raid-marker, and secure enemy-aura displays while respecting WoW's Secret Values rules.

## Features

- **Per-category styling** for party/raid members, other friendly players, friendly NPCs, hostile creatures, and enemy players.
- **Role-aware threat colors** for hostile creatures, plus class/reaction colors and a secret-safe health-percent display.
- **Cast bars** with spell name, icon, countdown, important-cast styling, uninterruptible stripes, and cast-target name/class color when available.
- **Secure 12.1 enemy auras** using Blizzard `CustomAuraContainerTemplate`: personal priority debuffs, other personal nameplate debuffs, shared crowd control, purgeable buffs, defensive buffs, and optional generic buffs.
- **Raid markers, target/focus highlights, target scale, and target arrows.**
- **English and Simplified Chinese options.**

## Install and configure

Copy the `DodoNameplate` folder into `World of Warcraft/_retail_/Interface/AddOns/`, then restart the client or run `/reload`. Use `/dnp` or ESC -> Options -> AddOns -> DodoNameplate to open settings. Changing the options-panel language requires `/reload`.

## Midnight limitations

- Enemy health is percentage-only where the underlying value is secret.
- Aura choices are limited to Blizzard's secure filters and candidate metadata; arbitrary per-spell inspection or whitelists are unavailable for restricted enemy auras.
- Friendly party/raid nameplates inside PvE instances retain Blizzard's appearance because those frames are protected.
- Restricted enemy identity can make class colors fall back to reaction colors.
- Enemy cooldown, diminishing-return, healer, and NPC-ID combat-intelligence tracking remain out of scope.

## Supported version

Version **0.9.0**, Retail / Midnight 12.1, Interface **120100**.

## License

All Rights Reserved. Copyright (c) 2026 Doodo. See [LICENSE](LICENSE).
