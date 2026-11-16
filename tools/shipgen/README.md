# shipgen

Generates ships in bulk for the Shipyard to finish off. Standalone: Python 3.8+ and Pillow, nothing from the game runs.

```
python tools/shipgen/shipgen.py                         # 8 of every role into the workspace
python tools/shipgen/shipgen.py --role hauler -n 24     # 24 haulers
python tools/shipgen/shipgen.py --role fighter --seeds 6,9  # rebuild just those two
```

Roles: fighter, gunship, hauler, heavy, yacht, carrier. Each ship borrows the stats, slot list, loadout,
compartments and berths of an existing hull of its role near its size (scaled to its area), so it flies
like something already balanced. Only the shape and slot positions are new.

A ship is kitbashed from blocks: a stepped or tapered spine, a nose, engines matching the slot count,
and side attachments (wings, fins, pods, booms, sponsons, cargo racks, radiators, carrier decks), plus
a cockpit or bridge, panels, stripes, antennae and lights. About half come out mirrored (using
`mirror = true` parts, so they edit as pairs); the rest are lopsided on purpose and recentred so their
centre of area sits on the axis.

Every candidate goes through `validate.py` and is dropped if it fails any check (outline, slivers,
connected, hidden parts, size vs. its class, fill, balance, slots on hull, clear exhaust, lights,
berths on deck, near-duplicates of existing ships or earlier keepers). Keepers are written as
`gen_<role>_<seed>.lua` in Shipyard format and drawn on `sheet_<role>.png`, all at one scale with seed
and template under each. A seed always makes the same ship.

## Workspace and game content

In a mod's data folder only namesake folders load into the game: `ships/`, `stations/`, `wrecks/`,
`satellites/`, `icons/`, `modules/` (and `items/`, `enemies/`, `markets/`, `sites/`, `spawn_sets/`,
`loot_tables/`). Everything else, the top level and any other folder, is workspace (`data.NAMESAKE` and
`data.inGame` in `src/data.lua`).

shipgen writes to the save folder's `mods/shipyard/data/shipgen/` (falls back to `shipgen_out/`), so its
ships are workspace:

- the Shipyard (F2) lists and opens them like any design, and says whether the folder you're in is
  workspace or in the game;
- the debug menu (F1) lists them last as `[workspace]`, to fly or park in a hangar;
- the simulation never uses them. A workspace design never replaces a game one with the same id (it's
  skipped with a warning), and a dealer, factory lineup or enemy that names a workspace hull fails to
  load. Non-design definitions in workspace files (modules, items, enemies, markets...) are left out.

To promote a keeper, save it into `ships/` from the Shipyard (or move the file there).

Check a batch loads without starting the game (needs LuaJIT, run from the repo root):
`luajit tools/shipgen/loadcheck.lua "<save folder>"`
