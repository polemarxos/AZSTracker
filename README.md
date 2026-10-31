<p align="center">
  <img src="docs/images/banner.png" alt="AZS Tracker" width="100%">
</p>

<h1 align="center">AZS Tracker</h1>

<p align="center">
  <b>Minimap markers, damage meters, boss timers and live run panels for <a href="https://wow.aethus.pl">Azeroth Survivors</a></b><br>
  World of Warcraft 1.12.1 addon · Interface <code>11200</code> · by Polemarxos
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#features">Features</a> ·
  <a href="#resizing-panels">Resizing</a> ·
  <a href="#options">Options</a> ·
  <a href="#slash-commands">Commands</a> ·
  <a href="#skill-icons">Skill icons</a> ·
  <a href="#faq--troubleshooting">FAQ</a>
</p>

> The images in this README are illustrations of the addon's panels, not in-game screenshots.

---

## Contents

- [Install](#install)
- [Features](#features)
  - [Square minimap](#square-minimap)
  - [Minimap markers: caches & guardian lairs](#minimap-markers-caches--guardian-lairs)
  - [Compass button](#compass-button)
  - [Highest Damage meter](#highest-damage-meter)
  - [DPS meter](#dps-meter)
  - [Party DPS meter](#party-dps-meter)
  - [Bosses panel & mission timer](#bosses-panel--mission-timer)
  - [Enemy HP bars](#enemy-hp-bars)
  - [Run tally](#run-tally)
  - [Odds panel](#odds-panel)
  - [Attributes](#attributes)
  - [Gear panel](#gear-panel)
  - [Compact chat](#compact-chat)
- [Resizing panels](#resizing-panels)
- [Options](#options)
- [Slash commands](#slash-commands)
- [Skill icons](#skill-icons)
- [FAQ / troubleshooting](#faq--troubleshooting)
- [Changelog](#changelog)

---

## Install

1. Download the latest release zip.
2. Extract the **`AZSTracker`** folder into `benilla-config/AddOns/`.
3. Check the layout:
   ```
   benilla-config/AddOns/AZSTracker/
   ├── AZSTracker.toc
   ├── AZSTrackerIcons.lua
   ├── AZSTracker.lua
   └── Textures/
   ```
4. Enable **AZS Tracker** in the AddOns list on the character screen if needed.
5. Enter the world and start an Azeroth Survivors run. Click the compass button on the minimap or type `/azst` to configure.

**Updating:** delete the old `AZSTracker` folder and extract the new one. Don't copy new files over an old version. Your settings, panel positions and sizes are kept, because they live in `SavedVariables`.

---

## Features

### Square minimap

<img width="369" height="384" alt="εικόνα" src="https://github.com/user-attachments/assets/c1d1a782-a18b-4057-978f-abc764386fb4" />


- Shows the **full map as a square**, using a bundled square mask, with no round crop.
- **Locked fully zoomed out**, so the view never zooms in or out. The +/− zoom buttons are hidden and the mouse wheel does nothing.
- **Anchored inside the top-right corner of the screen** so no part of the square is cut off.
- Framed **gold rim** with a dark outer shadow and inner line.
- **Zone name strip** across the top, coloured by zone type (sanctuary, friendly, hostile, contested).
- The tracking, mail, battleground and meeting-stone buttons are tucked into the square's corners.
- Buffs are moved to the left of the map so they don't overlap it.
- **Size adjustable** from 140 to 400 px (default 210 px) in the options.
- Turning **Square minimap** off restores the original round minimap, its position and buttons.

### Minimap markers: caches & guardian lairs

- **Battleground Cache** (chest) and **Guardian Lair** (skull) markers from the live AZS data.
- Lair states at a glance:
  - **Sleeping**: normal icon
  - **Fighting**: tinted red
  - **Empty / respawning**: greyed out, with an optional **respawn countdown** (`!` when due)
- Markers follow the player's live position and adapt to minimap size, zoom and shape.
- Lairs draw above chests. A chest is raised above a lair only when their icons overlap.
- Marker size is adjustable (**Minimap icon size**).
- While the markers are on, the game's own lair flag is hidden. Hiding the markers brings it back.

### Compass button

- Sits on the minimap rim. **Left-click** opens or closes the options window, which works before a run too.
- **Drag** it around the map edge to reposition it. Its position is saved.

### Highest Damage meter

<img width="463" height="296" alt="εικόνα" src="https://github.com/user-attachments/assets/18ba0884-c340-4fe6-94aa-e6830551e3e0" />


The **biggest single hit or tick per skill**. It never decreases during a run.

- Reads the combat log and groups by **skill name** (never by target).
- Includes **summons, pets and totems**:
  - Hits from your pet and guardians (such as totems) always count.
  - Other creatures count only if they are your pet, a totem, a known summon (Imp, Voidwalker, Infernal, Water Elemental, Treant, Lightwell …) or a name listed by the game's own meter.
  - Hostile mobs and party members' pets are ignored.
  - Summon spells appear as `Skill (Summon)`, e.g. `Attack (Searing Totem)`.
- Includes **talent / proc skills**:
  - Lines such as `Mob suffers 33 damage from <YourName>'s Deep Wounds` are counted.
  - Skills the combat log never reports use a biggest-hit value from the game's meter when it has one.
  - Otherwise the value is **estimated** from the damage the game adds in a 0.1 s window (per hit when the game counts hits). These values are shown with a **`~`** prefix.
- Proc rows are tinted blue. Bars scale against the top hit, which is shown in the header.

### DPS meter

- **Total damage per skill**, which only goes up, like the game's own meter. Read from the game's meter data.
- Header shows total damage and current DPS.

### Party DPS meter

- Damage per group member: **you, party or raid members, and pets** (each pet is merged into its owner).
- **Class-coloured** bars showing total damage, with **DPS in brackets** based on each member's own active combat time (gaps of more than 3.5 s don't count).
- Header shows the group's combined DPS.
- Click **reset** in the header or type `/azst partyreset` to start a new count. It also resets automatically when a new zone/run loads.
- Works solo (you + your pet).

### Bosses panel & mission timer

<img width="1083" height="362" alt="εικόνα" src="https://github.com/user-attachments/assets/5e56b481-d7c1-4160-aeee-4c37a4b48380" />


- **Mission timer** at the top: elapsed run time from the game's run clock (`m:ss`, or `h:mm:ss` after an hour). Shows `--:--` outside a run.
- **Bosses that are up** come first, with HP % and an **ENRAGE** flag, coloured red.
- **Upcoming bosses** follow, with a countdown, coloured gold.

### Enemy HP bars

- Compact dark-red HP bars for **bosses and guardian-lair guardians**. Enraged ones are brighter red.
- Replaces the game's own boss HP display while enabled.

### Run tally

- Three icons: **gold**, **chest cost** and **kills** for the current run.
- Replaces the game's own tally while enabled.

### Odds panel

<img width="459" height="263" alt="εικόνα" src="https://github.com/user-attachments/assets/9b9bae6e-938a-4865-9017-1c182407d9c3" />


- Your **Luck** and the bonus from your level.
- Current chance of **Rare / Epic / Legendary** for spells, rings, trinkets and amulets (amulets get their extra bonus).

### Attributes

- Live run attributes: Max Health, Damage, Cooldown, Crit Chance, Crit Multiplier, Damage Reduction, Regen/sec, Area, Extra Targets, Echo, Speed, Pickup Range, XP Gain, Luck, Gold Find, Heal on Kill, Leech, Thorns, Lives.

### Gear panel

<img width="351" height="214" alt="εικόνα" src="https://github.com/user-attachments/assets/6b6953a3-d0ee-4e23-a5c3-4497e4a9b776" />


- Icons for all 17 equipped slots. **Hover** an icon for the full item tooltip.
- The grid **always fits inside the panel**: it picks the column count and icon size that best fill the space you give it (6×3 at the default size, one long row when wide and short, and so on).

### Compact chat

- A small chat panel showing say, yell, party, raid, guild, whisper, system, channel, emote and loot messages, colour-coded by type.
- Hides the default chat frames while enabled.
- Shows more lines when you make the panel taller.

---

## Resizing panels

<img width="100" height="57" alt="εικόνα" src="https://github.com/user-attachments/assets/6dc29f5b-f8bd-4f76-8cea-762e266ec28c" />


Every panel has a small **dotted grip** in its bottom-right corner:

| Action | Result |
|---|---|
| **Drag** | Change **width and height freely** (no fixed aspect ratio). |
| **Shift + drag** | **Scale** the whole panel (text and icons grow too). |
| **Mouse wheel** over the grip | Scale in **5 % steps**. |
| **Right-click** the grip | **Reset** that panel's size and scale. |

- List panels (Highest Damage, DPS, Party DPS, Bosses, Enemy HP, Chat) **show more rows** when taller.
- Bars, columns, the Odds table, the tally and the gear grid **stretch to the new width**.
- In the options: **Scale all panels** (−/+) and **Reset sizes**.
- **Drag** a panel anywhere else to move it.
- Positions, sizes and scales are **saved per panel**.

---

## Options

<img width="82" height="64" alt="εικόνα" src="https://github.com/user-attachments/assets/065bc4b7-837a-4d97-b4e4-76c434f4003b" />

Open with the **compass button** or `/azst`. The window is available before a run; the live panels appear during a run.

| Option | What it does | Default |
|---|---|---|
| Minimap chests & lairs | Cache and guardian-lair markers | On |
| Odds panel | Rare / Epic / Legendary chances | On |
| Highest Damage Meter | Biggest hit per skill | On |
| DPS Meter | Total damage per skill + DPS | On |
| Party DPS Meter | Damage / DPS for you, your group and pets | On |
| Attributes | Live run attributes | Off |
| Boss timers | Bosses panel with mission timer | On |
| Enemy HP bars | Boss / guardian HP bars (hides the game's) | On |
| Run tally icons | Gold, chest cost, kills (hides the game's) | On |
| Gear panel | Equipped item icons | On |
| Compact chat | Small chat panel (hides default chat) | On |
| Lair spawn countdown on minimap | Respawn timer on empty lairs | On |
| Square minimap | Full square map, locked zoom, gold rim | On |
| Minimap icon size | `−` / `+` marker size | 10–16 px |
| Panel opacity | `−` / `+` panel background opacity | 50 % |
| Scale all panels | `−` / `+` scales every panel by 5 % | 100 % |
| Reset sizes | Every panel back to default size and scale | — |
| Square minimap size | `−` / `+` square map size (140–400 px) | 210 px |

**OK** applies and closes the window. **Cancel** restores the settings from when it was opened.

<br clear="right">

---

## Slash commands

| Command | Action |
|---|---|
| `/azst` · `/azst options` · `/azst config` · `/azst opt` | Open / close the options window |
| `/azst show` | Enable minimap chest and lair markers |
| `/azst hide` | Hide minimap chest and lair markers |
| `/azst partyreset` | Reset the Party DPS meter |
| `/azst icons` | List each meter skill, its icon and where the icon came from |
| `/azst debug` | Print run/marker diagnostics (phase, luck, chest count, lair count) |

---

## Skill icons

Icons for the Highest Damage and DPS rows are resolved in this order:

1. **The icon the game supplies** for that skill: `AZS_SPELLS` / meter-line icon fields, or a spell ID resolved through `SpellInfo` / `GetSpellInfo` when the client has them.
2. **Built-in Azeroth Survivors icon list** (`AZSTrackerIcons.lua`, about 640 entries taken from the game's own data): every class ability, all talents, perks, rings/trinkets, amulets and companion pets. It matches both display names (`Multi-Shot`) and internal keys (`multi_shot`).
3. **Any other `AZS_*` table** the game exposes (talents, summons, items …). Every entry with a name and an icon is learned automatically.
4. **Exact name** in your spellbook (including pet spells), talents, then action bars. A `Summon X` spell also provides the icon for `X`.
5. **Whole-word partial match** (game data, built-in list, spellbook, talents). The longest match wins.
6. **Keyword map** for common abilities, summons/pets/totems and damage schools, also matched on whole words.

Names like `Imp's Firebolt` are also tried as `Firebolt` and `Imp`, and `Summoned Treant` as `Treant`. Anything still unknown, and any name containing `?`, shows a **question mark** instead of a wrong icon.

> Missing an icon? Type `/azst icons` during a run. Lines marked `[none]` are skills with no match. Open an issue with those names.

---

## FAQ / troubleshooting

**Panels don't show up.**
Most panels appear only **during a run** and only when enabled in the options. The options window itself works anytime.

**Minimap markers are missing.**
They need valid player coordinates from the game. Check that **Minimap chests & lairs** is on (`/azst show`) and use `/azst debug` to see the phase and the chest/lair counts.

**A damage row shows `~` before the number.**
That skill never appears in the combat log, so its biggest hit is **estimated** from the game's meter (see [Highest Damage meter](#highest-damage-meter)). Area attacks that hit many targets at once can read high.

**Party DPS shows less damage than the game's meter.**
Party DPS is built from the **English combat log**. Damage the client doesn't report there, or a non-English client, isn't counted.

**I want the round minimap back.**
Untick **Square minimap** in the options. The original map, its position and buttons are restored.

**A panel is too big or too small, or off-screen.**
Right-click its corner grip to reset it, or press **Reset sizes** in the options. Panels are clamped to the screen.

---

## Notes

- Reads Azeroth Survivors' exposed `AZS_*` data and the WoW 1.12.1 client API. It **does not change game mechanics**.
- The meters depend on combat-log message formats (English client).
- Written for Lua 5.0 (WoW 1.12) limits.

---

## Changelog

| Version | Changes |
|---|---|
| **1.8** | Highest Damage includes summons, pets, totems and talent/proc skills (`~` estimates when the log has no data). |
| **1.7** | Built-in Azeroth Survivors icon list (~640 abilities, talents, perks, jewelry, pets). |
| **1.6** | New **Party DPS** meter. |
| **1.5** | Gear grid always fits inside its panel. |
| **1.4** | Square map locked fully zoomed out; icons from summons and talents; `/azst icons`. |
| **1.3** | Free width/height resizing, Shift-drag/wheel scaling, Scale all panels; DPS icon fixes; full square minimap. |
| **1.2** | Resizable panels; **mission timer** on the Bosses panel. |
| **1.1** | Minimap markers, odds, damage meter, attributes, boss timers. |

---

<p align="center"><sub>AZS Tracker is a fan-made addon for Azeroth Survivors. World of Warcraft is a trademark of Blizzard Entertainment.</sub></p>
