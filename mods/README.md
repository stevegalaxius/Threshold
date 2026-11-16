# Mods

Each mod is a folder here with a `data/` folder inside. Only files in a
namesake folder load into the game:

```
mods/
  my_mod/
    data/
      modules/guns.lua      game content
      ships/raider.lua      game content
      drafts/raider_v2.lua  workspace
      notes.lua             workspace
```

The namesake folders are `ships/`, `stations/`, `wrecks/`, `satellites/`,
`icons/`, `modules/`, `items/`, `enemies/`, `markets/`, `sites/`,
`spawn_sets/` and `loot_tables/` (`data.NAMESAKE` in `src/data.lua`).
Everything else is **workspace**. Designs there (hulls, stations, wrecks,
containers, props, satellites and icons) load so the Shipyard can open them
and the F1 debug menu can fly or park them. They never reach the
simulation:

- They never replace a game definition with the same id.
- A dealer, factory lineup or enemy that names a workspace hull won't load.
- Anything else in a workspace file (modules, items, enemies, markets and so
  on) is left out.

Files in `data/` use the same format as the game's own `data/` folder:
`hull { }`, `module { }`, `ammo { }`, `salvage { }` and `enemy { }`. Reusing an
existing id replaces that definition. Mods load in alphabetical order, after
the base game.

Mods can also go in the game's save folder under `mods/`, so players don't
need to touch the game files.

The Shipyard (F2 in game) exports the hulls you draw to
`mods/shipyard/data/<folder>/<id>.lua` in the save folder, in this same
format. It saves into workspace unless you're browsing a namesake folder,
and its Files panel says which one you're in. See
`src/editor/init.lua` for its controls.

Its Weapons tab edits weapon modules the same way: stats, plus optional
art drawn from polygons, saved as a `module { }` with an `art` table:

```lua
art = {
	muzzles = { { 14, -2 }, { 14, 2 } },   -- where shots leave, taking turns
	parts = {
		{ name = "base", shape = { -4, -4, 4, -4, 4, 4, -4, 4 } },
		{ name = "barrel", shape = { 0, -1, 14, -1, 14, 1, 0, 1 }, barrel = true },  -- recoils
	},
},
```

Coordinates are in mount space: 0,0 is the slot and +x the line of fire.
Weapons without `art` keep the plain barrels. "Test fire" fits the weapon
to every matching slot on your ship and puts you in flight.
