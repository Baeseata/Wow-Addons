# DodoItemLevelOverlay

Lightweight item level overlays for the default Blizzard bags and character
frame. No SavedVariables, no options UI, no dependencies. One glance tells
you what is an upgrade, what is bind-on-equip, and what is vendor trash.

## Features

**Bags** (combined or separated Blizzard bags), on every equippable item:

- **Top-left: item level**, colored with a Raider.IO style gradient. Item
  levels are mapped onto the same color ramp Raider.IO uses for Mythic+
  scores: white at the bottom of the window, blending smoothly through
  green, blue, purple and pink up to legendary orange at the cap. The
  higher the item level, the hotter the color.
- **Bottom-left: BOE tag**, shown only while that specific item is still
  unbound, or the equipment set name when the item belongs to a set.
- **Top-right: slot label** (HD, SH, CH, GL, BT, LG, FT, RG, TR, MH, OH...).

**Character frame**: item level on every equipment slot, same gradient.

**Junk filter**: equippable items of Poor (gray) or Common (white) quality
get no overlays at all. A bare icon means the item is worthless for gearing
and safe to vendor.

## Configuration

There is no options panel by design. All knobs are constants in
`Config.lua`:

- `GRADIENT_MIN_ILVL` / `GRADIENT_MAX_ILVL`: the item level window mapped
  onto the color ramp. Anything at or below MIN shows white, anything at or
  above MAX shows legendary orange. Tune these two numbers once per season.
- `HIDE_JUNK_QUALITY`: set to `false` to show overlays on gray/white gear.
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
| `Gradient.lua` | Raider.IO style color ramp and item level mapping |
| `ItemInfo.lua` | Item data helpers (item level, bind state, quality, slot) |
| `Overlay.lua` | FontString management on item buttons |
| `Equipment.lua` | Character frame equipment slots |
| `Bags.lua` | Blizzard bag frames |
| `Core.lua` | Events and refresh wiring |

## Credits

Color ramp inspired by the Mythic+ score colors of
[Raider.IO](https://raider.io/). This addon is not affiliated with
Raider.IO in any way.
