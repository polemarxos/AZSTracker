# AZS Tracker

Minimap helpers and a live rarity odds panel for **[Azeroth Survivors](https://wow.aethus.pl)**

Never miss a Battleground Cache or guardian lair, and see what your luck actually buys you on card rolls.

## Features

### Odds panel
Your chance of a **Rare**, **Epic**, or **Legendary** card for:

| Card type | Extra bonus |
|-----------|-------------|
| Spells    | —           |
| Rings     | —           |
| Trinkets  | —           |
| Amulets   | +0.5 on top |

Odds are derived from your **luck** stat plus a **level bonus** (+1% per level, 30% at most). Amulets get their extra bonus on top.

- Updates live during the run
- Drag anywhere — position is saved
- Only appears during a run (when luck is available)


### Minimap button
- Clover icon on the minimap rim
- **Click** — show or hide the odds panel
- **Drag** — move the button around the minimap

### Minimap markers
- **Battleground Caches** — chest icons for every cache on the field
- **Guardian lairs** — skull icons while a guardian is asleep or awake (empty lairs stay hidden)
- Lair icons draw **above** chests when they overlap
- The game’s stock red lair flag is hidden while markers are on (restored when you hide markers)

Works with round and square minimaps.

## Install

1. Download the latest release zip
2. Extract so the path is:
   ```
   benilla-config/AddOns/AZSTracker/
   ```
3. Restart the game (or re-enter the world) and enable the addon

Browser build: **Options → AddOns → install a `.zip` of the addon folder**.

## Commands

| Command        | What it does                                      |
|----------------|---------------------------------------------------|
| `/azst show`   | Enable minimap markers                            |
| `/azst hide`   | Hide minimap markers (restores the game’s lair flag) |
| `/azst odds`   | Toggle the odds panel                             |
| `/azst debug`  | Print phase, luck, chest/lair counts              |

## Requirements

- Azeroth Survivors (WoW 1.12.1 / Interface `11200`)
- Addon API globals (`AZS_RUN`, `AZS_CHESTS`, `AZS_LAIRS`, `AZS_STATS`, etc.)
