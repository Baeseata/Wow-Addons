# DodoInspect

Lightweight item overlays for the default Blizzard bags and character
frame, plus a target info line. No minimap button, no dependencies.
One glance tells you what is an upgrade, what is bind-on-equip, what
an item is for, what is vendor trash, and who you are looking at.

## Features

**Bags** (combined or separated Blizzard bags), on every equippable item
that is worth wearing:

- **Top-left: item level**, colored with a Raider.IO style gradient.
  The lower half of the window runs the Raider.IO Mythic+ score ramp
  (white through green, blue, purple, pink); the entire upper half is
  warm, going legendary orange at the midpoint and rising through
  amber and gold into hot red at the cap. Good gear is unmistakably
  orange territory, and near-cap item levels still get clearly
  distinct steps instead of saturating into one color.
- **Center: slot label**, localized (see Languages below).
- **Bottom-left: BOE tag**, shown only while that specific item is still
  unbound, or the equipment set name when the item belongs to a set.

**Top-left on everything that is not wearable gear: type tag**,
localized and color coded:

- **Junk** (gray): Poor quality items, plus Common (white) quality gear.
  Junk items get no other overlays: a bare gray tag means sell it.
  White quality non-gear (trade goods, reagents) is not junk.
- **Quest** (gold): quest items.
- **Consumables**: food (orange), flask (teal) and potion (red) each
  have their own tag and color; every other consumable gets a generic
  tag in light blue.

An item shows either an item level or a type tag in that corner, never
both, so the text stays short and clear of the stack count number.

**Character frame**: item level on every equipment slot, same gradient.

**Gear summary side panel**, docked to the right of the character frame.
One row per equipment slot:

- Localized slot abbreviation (same words as the bag labels).
- A fixed four-column secondary stat grid: versatility (blue), haste
  (yellow), mastery (green), critical strike (red). A column lights up
  when the item has that stat, so stat combos line up vertically across
  the whole gear list. The dominant stat (strictly higher than the
  other one) is underlined; equal values mean no underline.
- Item level (gradient colored) and the item name in your client
  language, quality colored. Mouse over the name for the full item
  tooltip, and over a gem icon for the gem tooltip.
- Tertiary stats: compact color-coded tags between the name and the
  enchant tag when the item has speed (cyan), leech (pink) or
  avoidance (lavender), localized like the other labels. Items
  without tertiary stats leave the column empty.
- The empty off-hand row is hidden. Enchant tags and gems sit in
  fixed columns so they align vertically across rows; the item name
  column has a fixed width and long names clip (the tooltip always
  carries the full name).
- Enchant state: a green tag when the item is enchanted (Death Knight
  runeforges count), a red tag when an enchantable slot is missing its
  enchant. Slots that take no enchant this season show nothing. Mouse
  over a green tag to see the enchant line from the item tooltip.
- Sockets: exactly as many icons as the item actually has sockets, gem
  icons for filled ones and a bright empty socket icon for unfilled
  ones, flowing right after the name and the enchant tag.

The enchantable slot list is season data (Midnight 12.0: enchants on
helm, shoulder, chest, legs via spellthread/armor kit, boots, rings and
weapons). It lives in `Config.lua` and is easy to update when a new
season changes the rules.

**Target info**, above the default target frame whenever you target a
player: item level (same gradient), race, class and spec (class
colored) and hero talent (gold). Compact locales fit on one line; long
ones (German, French, Russian) wrap between words onto up to three
lines, never inside a name. The line renders in layers, showing each
piece as soon as the game provides it:

- **Friendly players within inspect range** (about 28 yards) get the
  full line: race and class appear instantly, item level, spec and
  hero talent follow a moment later through the inspect data.
- **Hostile players cannot be inspected**; that is a Blizzard API
  rule, not an addon choice. They show race and class everywhere, and
  inside battlegrounds and arenas the spec too (read from the
  scoreboard and the arena opponent data, which cover both factions).
  Item levels and hero talents of hostile players are not available
  to any addon.

All words on the line (race, class, spec, hero talent) come from the
game's own localization, so they always match your client language.

## Options

All options live under **Esc > Options > AddOns > DodoInspect**:

- **Language** for the slot labels and type tags (see Languages below).
- **Equipment slot item levels**: the numbers on the character frame
  equipment slots.
- **Bag overlays**: item levels, slot labels, BOE and type tags on the
  Blizzard bags.
- **Gear summary side panel**: the gear list next to the character
  frame.
- **Target info**: the player summary line above the target frame.

The feature toggles render independently, so any combination works:
keep only the side panel, only the bags, or anything in between.
Settings are saved per account and apply immediately.

## Compatibility

DodoInspect only draws its own text on top of the default Blizzard
frames. It never modifies or blocks other addons, so running it next
to another item level addon breaks nothing; you would simply see two
copies of the same information stacked on the slots. If your UI
already shows item levels somewhere (ElvUI, SimpleItemLevel, a bag
addon with its own numbers, and so on), use the three toggles above to
switch off the overlapping part and keep the rest.

Bag replacement addons (Bagnon, BetterBags, AdiBags, ...) hide the
default Blizzard bags entirely, so the bag overlays have nowhere to
draw and silently do nothing. The character frame overlays and the
side panel keep working alongside them.

The target info line anchors above the default target frame. If a UI
overhaul addon removes that frame, the line falls back to the top
center of the screen.

## Languages

The slot labels and type tags ship in four languages: **English**
(default), **Chinese**, **French** and **Spanish**. Tags are kept to
five characters or fewer so they fit a bag icon (JUNK / NUL / MALO,
QST / QTE / MIS, FOOD / BOUF / COMI, and so on); French and Spanish
labels are deliberately accent-free so they render in any client font.
Chinese labels render a couple of points larger than the Latin ones
(CJK glyphs are denser), still sized to fit the icons.
Pick a language in the options panel:
**Esc > Options > AddOns > DodoInspect**, or use the slash
command:

```
/dins en
/dins cn
/dins fr
/dins es
```

The choice is saved per account. Item levels, BOE and set names are
language independent. The target info line is not affected by this
option at all: race, class, spec and hero talent names come from the
game client itself, in whatever language the client runs.

Note for the Chinese option on non-Chinese clients: the labels use the
Chinese client font shipped with the game. If that font file is missing
from your installation the labels fall back to the default font and may
render as squares.

## Configuration

Beyond the options panel, everything else is constants in `Config.lua`
(no options UI for them by design):

- `GRADIENT_MIN_ILVL` / `GRADIENT_MAX_ILVL`: the item level window mapped
  onto the color ramp. Anything at or below MIN shows white, anything at
  or above MAX shows hot red; the whole upper half of the window is the
  warm orange-to-red stretch. Tune these two numbers once per season:
  MAX a touch above the current best-in-slot ceiling, MIN so that the
  window midpoint sits where "good gear" begins.
- `HIDE_JUNK_QUALITY`: set to `false` to treat white gear as normal gear
  (gear overlays shown, no junk tag). Gray items are always tagged junk.
- Font sizes, anchor corners and colors for each overlay text.

Edit, save, then `/reload` in game.

## Install

Copy the `DodoInspect` folder into
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
| `TargetInfo.lua` | Player summary line above the target frame |
| `Options.lua` | Settings panel (language, feature toggles) and slash command |
| `Core.lua` | SavedVariables, events and refresh wiring |

## Credits

Color ramp inspired by the Mythic+ score colors of
[Raider.IO](https://raider.io/). This addon is not affiliated with
Raider.IO in any way.
