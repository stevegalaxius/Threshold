# Mods

Each mod is a folder here with a `data/` folder inside:

```
mods/
  my_mod/
    data/
      guns.lua
```

Files in `data/` use the same format as the game's own `data/` folder:
`hull { }`, `module { }`, `ammo { }`, `salvage { }` and `enemy { }`. Reusing an
existing id replaces that definition. Mods load in alphabetical order, after
the base game.

Mods can also go in the game's save folder under `mods/`, so players don't
need to touch the game files.

The Shipyard (F2 in game) exports the hulls you draw to
`mods/shipyard/data/<id>.lua` in the save folder, in this same format. See
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
