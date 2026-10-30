# AZS Tracker

Minimap helpers and live information panels for **[Azeroth Survivors](https://wow.aethus.pl)**

## Features

### Minimap button

A compass button sits around the minimap:

- **Left-click** to open or close the options window. This works outside a run too.
- **Drag** the button around the minimap to reposition it. Its position is saved.

### Minimap markers

- Shows **Battleground Cache** (chest) markers and **Guardian Lair** markers using the live AZS data.
- Lair markers distinguish sleeping, fighting, and empty/respawning lairs. Sleeping lairs use the normal icon, fighting lairs are tinted red, and empty lairs are greyed out.
- When enabled, empty lairs show the remaining respawn time; a `!` indicates that the lair is due. The timer text can be switched off separately.
- Markers are positioned relative to the player's live map coordinates and adapt to minimap zoom and shape.
- Lair icons normally draw above chest icons. A chest is raised above a lair **only when their visible icons overlap**, so unrelated nearby markers keep their normal layering.
- The addon's minimap markers temporarily hide the game's own lair flag while markers are active; hiding the addon's markers restores the game's flag.

### Live panels

Panels are shown only while a run is active and when their option is enabled. They can be dragged to reposition them; panel positions are saved.

- **Odds panel** — displays the current chances for Rare, Epic, Legendary, spells, rings, trinkets, and amulets, using the run's luck/level bonuses.
- **Damage meter** — lists the player's strongest recorded individual hit/tick per skill. It reads combat-log messages and uses the skill name for grouping, rather than grouping by the target. Rows are seeded from the current AZS spell list where possible.
- **Attributes** — displays the character's live run attributes.
- **Boss timers** — shows currently alive bosses first, followed by upcoming boss countdowns.

Panels use a movable, adjustable-opacity skin. Their locations and the relevant display settings are saved between sessions.

## Skill icon lookup

For damage-meter rows, skill icons are resolved in this order:

1. Player spellbook (including spell tabs and pet spellbook entries where the client exposes them).
2. Action bars.
3. Spell IDs/names supplied by `AZS_SPELLS`.
4. Case-insensitive exact and partial name matching across those sources.
5. Built-in keyword matching for common class abilities, damage schools, melee, bleeds, poison, pets, summons, procs, and jewelry-related terms.
6. Talent icons, as a final real-icon source.


Unknown entries whose names contain `?` keep the question-mark icon.

## Options

Open the options window with the compass button or `/azst`. Available controls:

| Option | What it does | Default |
|---|---|---|
| Minimap chests & lairs | Shows/hides both marker types | On |
| Odds panel | Shows the drop-odds panel | On |
| Damage meter | Shows the biggest-hit-per-skill panel | Off |
| Attributes | Shows the live attributes panel | Off |
| Boss timers | Shows alive and upcoming bosses | On |
| Lair spawn countdown on minimap | Shows/hides countdown text on empty lairs | On |
| Square minimap | Applies the square minimap styling and gold rim | On |
| Minimap icon size | `−` / `+` adjusts marker size | Default |
| Panel opacity | Adjusts panel transparency | 50% |

The options window is available before a run. The live panels themselves appear only during a run. Settings, panel positions, and the compass-button position are saved.

## Slash commands

| Command | Action |
|---|---|
| `/azst` or `/azst options` | Open/close the options window |
| `/azst show` | Enable minimap chest and lair markers |
| `/azst hide` | Hide minimap chest and lair markers |
| `/azst debug` | Print basic run/marker diagnostics (phase, luck, chest count, lair count) |

`/azst config` and `/azst opt` also open the options window.

## Install

1. Extract the `AZSTracker` folder into `benilla-config/AddOns/`.
2. Make sure the folder layout is `benilla-config/AddOns/AZSTracker/AZSTracker.toc`.
3. Enable the addon in the AddOns list if needed. The TOC targets interface version `11200` (WoW 1.12.1).
4. Enter the world and start an Azeroth Survivors run. Use the compass button or `/azst` to configure it.

To update, replace the existing `AZSTracker` folder with the new one. Do not merge old files over the new version.

## Notes

- The addon reads Azeroth Survivors' exposed `AZS_*` data and the WoW 1.12.1 client APIs; it does not change game mechanics.
- Minimap markers require valid player and world coordinates from the game. If the game does not provide coordinates, markers cannot be placed reliably.
- The damage meter depends on combat-log message formats and may not capture damage that the client does not report in those messages.
