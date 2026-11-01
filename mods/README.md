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
