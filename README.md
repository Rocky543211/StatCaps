# StatCaps

**Beta 1.0** · A Lord of the Rings Online plugin that shows, at a glance, how close each of your ratings is to the stat limit for your level, and helps you compare gear against those limits.

English, German and French interface (follows the LOTRO client language).

## Features

- **Stat caps at a glance** – mitigations, masteries, critical rating, finesse, resistance, block/parry/evade, healing and more. Each row shows your rating, the cap for your level and a signed **Over / Under** value with a coloured bar.
- **Build advice** – choose your class build to see which uncapped stat matters next, with cap-aware priorities.
- **Item comparison** – compare a candidate item against what you are wearing. Bonuses autofill from a built-in item database (about 80,000 items, including item-level scaling gear, skirmish gear and weapon DPS). Searches offer armour-type, quality, and target class/minimum-level filters.
- **Companion catalogues** – choose essences, preview consumable stat bonuses, search translated German/French item names, and view known acquisition sources.
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
- When a dropped or equipped item has several variants, enter its **Tooltip item level (not character level)** in the variant picker and click **Recalculate variants** (or **Find** in the loadout picker) before selecting. Blank uses database/base levels, which can differ from the actual instance. For example, the Reinforced Shield of the Wayfarer can have tooltip item level 17 despite database base level 51. Check every bonus; percentages, procs and other unsupported effects still need separate consideration.
- Normal item comparison fetches reviewed current-item bonuses/variants directly from the selected character's loadout planner state, even when that window is hidden, or from its saved plan when the planner has not been opened. No loadout comparison is needed. Reuse requires the recorded equipment identity and scaling level to match. This also applies to direct drops into A/B and survives reopening/saving the loadout; an already-open item comparison checks for newly reviewed variants when you Analyze. Database default item levels are not treated as actual tooltip levels. Planned replacements are never used as the equipped baseline, and ambiguous same-name equipment still needs an explicit slot/variant choice. This is reuse of your review, not automatic instance detection: check same-name replacements and changed tooltip item levels. Selecting missing variants continues item analysis automatically.
- Virtue search uses the same attribute, derived-rating and cap-aware scoring as the displayed comparison. Equally scored sets prefer keeping your currently equipped virtues rather than asking for a pointless swap. After a recommendation, **Apply to planner only** fills the planner slots with it in one click (virtues you already have stay in their slot) and saves them as equipped. It does **not** change your in-game virtues, because LOTRO plugins cannot equip virtues; equip the same virtues in LOTRO yourself, then recalculate after the live stats settle; percentages and temporary buffs can make the base-conversion estimate differ from the game.
- **Clear planned gear** in the loadout planner returns all planned slots to **Keep equipped**, including planned unequips and weapon/off-hand changes. It saves the cleared equipment plan while preserving reviewed current items, virtues and current/planned set/essence totals. Check those extra totals separately before comparing. **Reset plan** remains the full reset.
- Set, essence and consumable totals can be reviewed under **Set/Essence bonuses**. The essence and consumable pickers fill editor fields; **Apply** saves them to the plan.
- Legendary items are listed as placeholders; their stats are not compared.
- Item search accepts English names and translations for your German or French client. Translated names are displayed when available; English names remain the database identity. Exact translated name/category checks also support dropped equipment. Ambiguous variants still require your choice.
- Pasted names such as `[Sharpened Silver Longsword]` work in item and loadout searches; surrounding chat brackets are ignored.
- Item comparison accepts different weapon types, such as a spear and sword, when they fit a common equipment slot. Automatic matching includes compatible main-hand and off-hand weapons for dual-wielding characters, but excludes shields from weapon comparisons (and weapons from shield comparisons). Weapon DPS remains separate from stat scoring; class proficiency, two-handed/off-hand conflicts and weapon-specific effects still need checking in the full loadout or game.
- Search filters are optional and initially disabled. Click the Armour and Quality buttons to cycle their choices. Target class + level checks explicit class and minimum-level requirements, not every weapon proficiency, trait, or unique-item restriction.

## Essences, consumables and item sources

### Experimental best gear preview

The experimental preview is included in this release and retains its **Best gear (Test)** label. Open the full loadout planner, select the character/build, and click **Best gear (Test)**. First review the current equipment's full bonuses, Current set/essence totals and equipped virtues; confirm that they match the captured snapshot. Unknown current item bonuses must be entered in the ordinary editor before the search can safely replace them.

The first generation loads equipment rules, item/set data and translated names on the UI thread before starting the cancellable search. It may briefly pause while these catalogues initialize.

The preview searches supported numeric gear bonuses, tries equipment-set families and individual swaps, and alternates those with exhaustive selection of legal active virtues at the **maximum rank for the character level**, even if those virtues are untrained. It is a bounded heuristic gear search, **not a proven global best-in-slot result**. Existing race/class/trait stats, ongoing buffs and passive virtue ranks remain in the baseline; passive virtues, new sockets, procs, legendary effects, durations and buff stacking are not optimized. Current extras are subtracted and proposed numeric sets are calculated automatically, so keep ongoing consumable buffs out of Current extras for this particular search.

**Equip minimum and item level are separate.** An item-level 300 item with minimum level 1 is eligible at level 1. Fixed items use their database stats. Rewards with an explicit character-to-item-level generation curve use that curve at the target character level, capped at the reward's maximum generation level; the preview shows the possible random-bonus range and uses the base roll by default. For example, Wayfarer rewards opened at character level 20 have item levels 16–18, not database level 51. At later levels, generation curves can produce item levels in the hundreds; there is no character-level-based item-level cutoff. Other scaling items still use database/base item levels unless overridden. Enter the actual tooltip item level beside an alternative to override its calculated stats, including a random bonus roll. An override changes stats, never the character's level or the item's minimum equip level. Missing minimums and conditional requirements (traits, race, reputation, rank or effects) are excluded from new choices by default; an explicit checkbox includes them as unverified candidates. Already worn items with confirmed full bonuses can remain candidates despite unknown requirements, but cannot bypass known character-level, class or armour restrictions.

Select a slot to review alternatives and numeric bonuses, view **Item sources**, or **Exclude + retry**. Exclusions normally cover every same-name variant; turn that option off to exclude only the exact ID. **Use + recalculate** pins an alternative while searching the other slots and virtues again. **Set bonuses / effects** shows the proposed totals, thresholds and unscored warnings; select a slot again to return to its alternatives. Clear exclusions/pins/levels to start fresh. Items with no known quest, vendor, barter, loot, container, crafting or other source in the bundled LOTRO Companion data are skipped by default, because they are usually removed or unreleased items (for example the **Zealous and Devoted** set). Tick **Include items with no known source** if you still want them; the status line shows how many were skipped. Availability is not automatically verified, even when a known source is listed.

Weapons and class items are kept by default. Optional same-type search preserves the equipped weapon/shield family and avoids a known weapon-DPS loss; it still cannot model every proficiency, skill effect or weapon interaction. Legendary items stay unchanged. The preview does **not** equip anything, overwrite the ordinary plan, alter saved virtue ranks, or save its exclusions. Copy choices manually into the normal planner if you want to evaluate socket bonuses or other effects. Closing the window cancels an active search.

**Essences:** click **Add essence** in item comparison or a loadout item/bonus editor. Search by name or ID, optionally enter the essence's own tooltip item level, and choose a quantity. Review supported bonuses and the **Not compared** warnings before confirming and adding. Check the socket type/count yourself. Add socketed bonuses to the item **or** the shared extras, never both. Changing an equipment item's level recalculates its base bonuses and replaces manual essence additions; add those again afterward.

**Consumables:** open the loadout planner's **Current set/essence bonuses** or **Planned set/essence bonuses**, then **Add consumable**. Supported scaling consumables use the selected **character level**, not equipment item level. Buffs contribute only their supported flat stats; regeneration, percentages, skills, procs and other unsupported effects are shown as omitted. Entries without supported bonuses cannot be added.

The comparison subtracts **Current** extras from the captured character stats and adds **Planned** extras. Current consumable totals must therefore include **only buffs already present in that snapshot**; Planned contains the intended replacement buffs. Put an unchanged buff on both sides or neither. These are editable totals, not an automatic active-buff reader or buff timer: verify stacking, conflicts, duration and duplicate additions yourself, especially when reopening a saved editor. Adding a bonus does not apply a buff in game. Saved plans must be reviewed again after changing level or buffs.

**Sources:** click **Item sources** beside an exact item search result or in its loadout editor. The catalogue records known crafting, barter, vendor, quest, container, enemy and instance sources for about 63,000 items. It shows up to three examples per category and the known count. This is not exhaustive, does not include all costs or prerequisites, and does not guarantee current availability. Source descriptions remain in English.

The supplemental data is loaded only when needed; only the active client's translated-name catalogue is loaded. Repeated names are stored once to keep the files smaller. Both language files remain in the download so the same installation works with either client. No generator or test tools are required or included.

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
