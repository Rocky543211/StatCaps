# StatCaps

**Beta 1.0** · A Lord of the Rings Online plugin that shows, at a glance, how close each of your ratings is to the stat limit for your level, and helps you compare gear against those limits.

English, German and French interface (follows the LOTRO client language).

## Features

- **Stat caps at a glance** – mitigations, masteries, critical rating, finesse, resistance, block/parry/evade, healing and more. Each row shows your rating, the cap for your level and a signed **Over / Under** value with a coloured bar.
- **Build advice** – choose your class build to see which uncapped stat matters next, with cap-aware priorities.
- **Item comparison** – compare a candidate item against what you are wearing. Bonuses autofill from a built-in item database (about 80,000 items, including item-level scaling gear, skirmish gear and weapon DPS). Searches offer armour-type, quality, and target class/minimum-level filters.
- **Full loadout planner** – a character-screen layout with all 19 slots. Drop or search replacements, keep the rest as current gear, add set/essence bonuses and compare the whole loadout.
- **Cross-character planning** – each character's stats, gear, build and virtues are saved automatically, so you can plan for an alt while logged in on your crafter.
- **Virtue planner** – cap-aware virtue recommendations and swap advice.
- **Themes** – race designs and class accents, each automatic or chosen freely. Toggle with the draggable **SC** icon.

## Requirements

- [CalcStat by Giseldah](https://giseldah.github.io/) installed at `Plugins/Giseldah/CalcStat`.

## Installation

1. Download `StatCaps-1.0-beta.zip` from the [Releases](../../releases) page.
2. Extract it into your LOTRO `Plugins` folder, so you have `Plugins/StatCaps/StatCaps.plugin`.
   - Windows: `Documents\The Lord of the Rings Online\Plugins`
3. In game:

```
/plugins load StatCaps
```

## Commands

| Command | Action |
| --- | --- |
| `/statcaps` | Show or hide the main window (or click the **SC** icon) |
| `/statcaps loadout` | Open the full loadout planner |
| `/statcaps item` | Open item comparison |
| `/statcaps settings` | Appearance, scoring, diagnostics and command help |
| `/statcaps debug` | Print a diagnostics report to chat |
| `/statcaps virtuelog` | Toggle virtue-rank notification logging |
| `/plugins unload StatCaps` | Unload the plugin |

## Notes and limitations

- The LOTRO API does not expose full item tooltips. Database values are **suggestions**: check the tooltip, item level and essences before comparing.
- For scaling items, type the **item level shown in the tooltip** (not your character level) and the bonuses recalculate.
- Set and essence bonuses are entered manually under **Set/Essence bonuses**.
- Legendary items are listed as placeholders; their stats are not compared.
- Item search uses English item names.
- Search filters are optional and initially disabled. Click the Armour and Quality buttons to cycle their choices. Target class + level checks explicit class and minimum-level requirements, not every weapon proficiency, trait, or unique-item restriction.

## Import virtue ranks from LOTRO Companion

The optional `ImportVirtues.html` helper opens locally in a browser on Windows or Linux. It has no downloads, uploads, or network connections and does not write plugin data.

1. In LOTRO Companion, import your character with **Current Gear** selected.
2. Open `ImportVirtues.html` from the StatCaps folder in your browser. Select the XML file for that imported character configuration in Companion's character data folder. Do not select `summary.xml`, `deedsStatus.xml`, or the separate `virtues.xml` status file: those do not contain the complete configuration ranks.
3. Copy the resulting text. In StatCaps, open **Virtues → All virtue ranks → Import from Companion**, paste it, and click **Review imported ranks**.
4. Check the displayed source character and all ranks, then click **Save all virtue ranks**. Nothing is saved just by pasting or reviewing.

All 21 ranks must be present, including zero for untrained virtues. The helper rejects incomplete or invalid data rather than inventing ranks. Equipped virtues remain unchanged. Old or simulated Companion configurations can differ from your live character; verify the import. If your browser blocks automatic clipboard access, select the output and copy it manually.

Changes: [CHANGELOG.md](CHANGELOG.md)

## Credits

- Stat calculations use [CalcStat](https://giseldah.github.io/) by Giseldah.
- Item, set and progression data is generated from [LOTRO Companion](https://github.com/LotroCompanion) public data.

The Lord of the Rings Online is a trademark of its respective owners. This is an unofficial fan plugin.
