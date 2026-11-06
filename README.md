# MyQuestPlates

A lightweight, high-performance World of Warcraft addon tailored for **WoW: Forever** (1.60+), **Classic Era**, and modern clients. It places clear quest objective icons (slay, loot, talk) and progress counts directly onto default Blizzard nameplates—just like Questie, but lightweight and built specifically for default nameplates.

---

## Features

- ⚔️ **Slay / Kill Objectives**: Displays a sword icon above or beside mobs you need to kill.
- 🎒 **Loot / Pickup Objectives**: Displays a loot pouch/bag icon on mobs that drop items you need to collect.
- 💬 **Talk / Interact Objectives**: Displays a chat bubble or cogwheel on quest NPCs and interactable targets.
- 🔢 **Progress Counts**: Shows real-time progress text (e.g. `3/8`, `0/1`) directly with the icon.
- 🔄 **Questie Synergy**: If Questie is installed, MyQuestPlates directly hooks Questie's objective database and icon sets.
- 🛡️ **Native Fallback**: If Questie is absent or disabled, MyQuestPlates functions 100% standalone using Blizzard's tooltip scanner and Quest Log leaderboards.
- 🎯 **Target Frame Indicator**: Optional quest indicator on your target unit frame.
- ⚡ **Zero-Garbage Pooling**: Uses frame pooling so nameplate spawning never triggers garbage collection hitches or FPS drops.
- 🎛️ **In-Game Settings**: Full configuration panel to adjust anchor position (Left, Right, Above), scale, X/Y offsets, font sizes, and filters.

---

## Slash Commands

- `/mqp` or `/myquestplates`: Opens the configuration panel.
- `/mqp test`: Toggles preview test icons on all visible nameplates (great for adjusting offsets in real-time).
- `/mqp debug`: Dumps active quests by Quest ID, objective requirements, and live target unit diagnostics.
- `/mqp reset`: Resets all settings to default values.
- `/mqp help`: Displays available commands.

---

## Installation

Ensure the folder is located at:
`World of Warcraft\_classic_beta_\Interface\AddOns\MyQuestPlates\`
