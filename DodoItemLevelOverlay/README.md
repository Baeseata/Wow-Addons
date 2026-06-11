# DodoItemLevelOverlay

Lightweight item overlays for the default Blizzard bags and character
frame. No minimap button, no dependencies. One glance tells you what is
an upgrade, what is bind-on-equip, what an item is for, and what is
vendor trash.

## Features

**Bags** (combined or separated Blizzard bags), on every equippable item
that is worth wearing:

- **Top-left: item level**, colored with a Raider.IO style gradient. Item
  levels are mapped onto the same color ramp Raider.IO uses for Mythic+
  scores: white at the bottom of the window, blending smoothly through
  green, blue, purple and pink up to legendary orange at the cap. The
  higher the item level, the hotter the color.
- **Center: slot label**, localized (see Languages below).
- **Bottom-left: BOE tag**, shown only while that specific item is still
  unbound, or the equipment set name when the item belongs to a set.

**Bottom-right on any bag item: type tag**, localized:

- **Junk**: Poor (gray) quality items, plus Common (white) quality gear.
  Junk items get no other overlays: a gray junk tag means sell it.
  White quality non-gear (trade goods, reagents) is not junk.
- **Quest**: quest items.
- **Consumables**: food, flask and potion each have their own tag;
  every other consumable gets a generic use tag.

The tag sits slightly above the corner so it does not cover the stack
count number.

**Character frame**: item level on every equipment slot, same gradient.

## Languages

The slot labels and type tags ship in four languages: **English**
(default), **Chinese**, **French** and **Spanish**. Pick one in the
options panel: **Esc > Options > AddOns > DodoItemLevelOverlay**, or use
the slash command:

```
/dilo en
/dilo cn
/dilo fr
/dilo es
```

The choice is saved per account. Item levels, BOE and set names are
language independent.

Note for the Chinese option on non-Chinese clients: the labels use the
Chinese client font shipped with the game. If that font file is missing
from your installation the labels fall back to the default font and may
render as squares.

## Configuration

Everything else is constants in `Config.lua` (no options UI for them by
design):

- `GRADIENT_MIN_ILVL` / `GRADIENT_MAX_ILVL`: the item level window mapped
  onto the color ramp. Anything at or below MIN shows white, anything at
  or above MAX shows legendary orange. Tune these two numbers once per
  season.
- `HIDE_JUNK_QUALITY`: set to `false` to treat white gear as normal gear
  (gear overlays shown, no junk tag). Gray items are always tagged junk.
- Font sizes, anchor corners and colors for each overlay text.

Edit, save, then `/reload` in game.

## Install

Copy the `DodoItemLevelOverlay` folder into
`World of Warcraft/_retail_/Interface/AddOns/` and restart the client, or
`/reload` if it was already installed.

## Files

| File | Purpose |
| --- | --- |
| `Config.lua` | User-tweakable settings |
| `Locales.lua` | Translations (the only non-ASCII file) |
| `Gradient.lua` | Raider.IO style color ramp and item level mapping |
| `ItemInfo.lua` | Item data helpers (item level, bind state, quality, type) |
| `Overlay.lua` | FontString management on item buttons |
| `Equipment.lua` | Character frame equipment slots |
| `Bags.lua` | Blizzard bag frames |
| `Options.lua` | Settings panel and slash command |
| `Core.lua` | SavedVariables, events and refresh wiring |

## Credits

Color ramp inspired by the Mythic+ score colors of
[Raider.IO](https://raider.io/). This addon is not affiliated with
Raider.IO in any way.
