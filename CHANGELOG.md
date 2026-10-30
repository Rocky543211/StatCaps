# Changelog

All notable changes to StatCaps are documented here.

## [1.0 Beta] - 2026-10-30

First public release.

### Stat caps
- Main window showing every tracked rating against the cap for your level, with signed Over / Under values and coloured cap bars.
- Calculations via Giseldah's CalcStat library; tier selection is saved.

### Build advice and scoring
- Per-class build selection with cap-aware priorities and a "next relevant stat" list.
- Configurable scoring weights (class EV and role values), Finesse targets and resistance reference.

### Item comparison
- Compare a candidate against worn gear (A/B for paired slots) with upgrade/downgrade scoring.
- Built-in item database: fixed items, item-level scaling gear (recalculates when you type the tooltip item level), skirmish gear and weapon DPS.
- Search by English name, item ID or pasted item link; variant picker for ambiguous items.
- Socketed items use base stats; essences go on the item or under Set/Essence bonuses.
- Legendary items are searchable placeholders without compared stats.

### Full loadout planner
- Character-screen layout with all 19 slots, planned vs. current gear, slot-filtered search and set-piece search.
- Manual Set/Essence bonus totals, unequip planning and restriction checks (class, level, unique, two-handed).

### Characters and virtues
- Automatic per-character snapshots of stats, gear, build and virtues for cross-character planning.
- Virtue planner with cap-aware recommendations and swap advice.

### Interface
- Race designs and class accents, each automatic or chosen independently; draggable SC launcher icon.
- English, German and French localization.
- Diagnostics report (`/statcaps debug`).
