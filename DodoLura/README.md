# DodoLura

An air-horn alert for the **Midnight Falls (L'ura)** raid encounter in *March on Quel'Danas*.

When **you** are targeted by **Starsplinter** (the intermission / Mythic stage-four spike mechanic), an air horn sounds immediately. That's all it does.

- **Zero settings, zero UI.** Install it, pull the boss, get honked at.
- Works on all difficulties; only active during the L'ura encounter (encounterID 3183), zero overhead anywhere else.
- Starsplinter targeting is a *private aura*, so no addon can read it directly. DodoLura registers the horn through Blizzard's sanctioned `C_UnitAuras.AddPrivateAuraAppliedSound` API — the game engine itself plays the sound the instant the aura lands on you, with no addon-side option layers that could silently eat the alert.
- `/dodolura` plays the horn once as a sound check.

Part of the **Dodo** addon family by Doodo.

## Credits

- `AirHorn.ogg` by Mike Koenig, licensed [CC-BY 3.0](https://creativecommons.org/licenses/by/3.0/).
