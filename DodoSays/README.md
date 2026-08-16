# DodoSays

A memory-game helper for **Azta'rec**, the Delve Nemesis in Venomfall Deeps
(Midnight Season 2). Works on both `?` and `??`.

Azta'rec splits the room into quarters three times a fight. First he preaches
and shows you which quarter is safe, one wave at a time. Then he echoes the
whole run back with no telegraph at all — same order, no warning.

DodoSays does not try to read the room. It cannot: the client stopped handing
out player positions in there. **You** tap the safe quarter while he preaches,
and it calls them back to you while he echoes.

## Using it

1. Before the pull, drop raid markers on the floor: **cross** toward the boss,
   then **square**, **triangle**, **circle** going clockwise. Any rotation works
   as long as the ground matches the board.
2. While he preaches, tap the quarter that stayed safe — click the board, or
   bind keys under *Key Bindings → DodoSays*.
3. While he echoes, watch the middle of the screen. Each wave shows the marker
   to stand in, the one coming after it at 60% size, and a bar that empties as
   the wave lands.

The board only accepts taps while he is preaching. Outside that it stays on
screen but greys out.

## Commands

| | |
|---|---|
| `/ds` | list every command |
| `/ds panel` | settings (or click the minimap button) |
| `/ds sim 5` | rehearse a five-wave round with no boss needed |
| `/ds go` | lock the rehearsal and play it back at the real cadence |
| `/ds show` / `hide` | the board |
| `/ds where` | what map the client thinks you are on |

`/ds sim` drives exactly the same code a real pull does — only the source of
the events differs. If it works in the rehearsal it works in the fight.

## Notes

Everything is timed off events the client still hands out. Spell ids, spell
names and cast timestamps all come back secret in this encounter, so nothing
here depends on reading them; the wave lengths are measured live and corrected
every round.

The addon stays completely asleep outside this one encounter.
