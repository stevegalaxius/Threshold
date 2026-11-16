# shipgen

Generates ships in bulk for the Shipyard to finish off. Standalone: Python 3.8+ and Pillow, nothing from the game runs.

On Windows, double-click `tools\shipgen\shipgen.bat` (or run it from a terminal with the same options
as below). It finds Python, installs Pillow the first time and writes into your save folder.

```
python tools/shipgen/shipgen.py                         # 8 of every role into the workspace
python tools/shipgen/shipgen.py --role hauler -n 24     # 24 haulers
python tools/shipgen/shipgen.py --role fighter --seeds 6,9  # rebuild just those two
```

Roles: fighter, gunship, hauler, heavy, yacht, carrier. Each ship is a new design, stats included
(`design.py`):

- **Brief:** a role plus a brief (balanced, armoured, racer, long-haul, brawler, skirmisher) that
  trades one thing for another, e.g. armoured: +45% armour, heavier, slower to turn.
- **Slots:** engine, weapon, bay and utility counts come from the role and brief before the hull is
  drawn, so the geometry is built around them (twin nacelles for two engines, sponsons for guns).
  Sizes follow the finished hull's weight (S/M/L), with the main guns forward and smaller ones behind.
- **Stats:** mass from hull area, armour from mass, hold from cargo-rack area, drag from mass and
  bluntness, thrusters, turn rate and response and spool time from length, price from mass, armour and
  fit. Each one is bent by the brief.
- **Loadout:** engines sized so thrust/weight lands in the role's band, a reactor to match, weapons of
  the brief's type (sometimes a second type on the small mounts), and role-fitting utilities
  (nav computer, hold pods, flares, drone uplink...).
- **Balance check:** acceleration, top speed, turn rate, strafe, armour per tonne, price per tonne and
  power have to land within the range (±20%) that existing ships of half to double its weight already
  cover. A new design can be unusual, but it can't be broken.

A ship is kitbashed from blocks: a stepped or tapered spine, a nose, engines matching the slot count,
and side attachments (wings, fins, pods, booms, sponsons, cargo racks, radiators, carrier decks), plus
a cockpit or bridge, panels, stripes, antennae and lights. About half come out mirrored (using
`mirror = true` parts, so they edit as pairs); the rest are lopsided on purpose and recentred so their
centre of area sits on the axis.

Every candidate goes through `validate.py` and is dropped if it fails any check (outline, slivers,
connected, hidden parts, size for its role, fill, balance, slots on hull, clear exhaust, lights,
berths on deck, near-duplicates of existing ships or earlier keepers, stats). Keepers are written as
`gen_<role>_<seed>.lua` in Shipyard format and drawn on `sheet_<role>.png`, all at one scale with seed,
brief and mass under each.

Runs never overwrite anything. Each run writes to its own `batch_<date>_<time>/` folder inside the
shipgen folder (`--batch name` to name it). Before generating, it scans the whole Shipyard folder for
generated ids, wherever you've moved or edited them, and carries on after the highest seed per role, so
every new ship gets a new id. Ships already on disk also count for the near-duplicate check. A seed
always makes the same ship; `--seeds 4,9` builds exactly those, skipping any that already exist.

## Workspace and game content

In a mod's data folder only namesake folders load into the game: `ships/`, `stations/`, `wrecks/`,
`satellites/`, `icons/`, `weapons/`, `modules/` (and `items/`, `enemies/`, `markets/`, `sites/`, `spawn_sets/`,
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
