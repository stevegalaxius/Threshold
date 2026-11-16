# shipgen

Generates ships in bulk for the Shipyard to finish off. Standalone: Python 3.8+ and Pillow, nothing from the game runs.

```
python tools/shipgen/shipgen.py                         # 8 of every role into shipgen_out/
python tools/shipgen/shipgen.py --role hauler -n 24     # 24 haulers
python tools/shipgen/shipgen.py --role fighter --seeds 6,9 --out "%APPDATA%/LOVE/spacegame_proto/mods/shipyard/data"
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

Copy the ones you like into the save folder's `mods/shipyard/data/` to fly them or open them in F2.
