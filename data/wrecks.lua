--[[
	Wrecks and props: derelicts and debris placed in the world rather than
	left by a dying ship (src/data.lua, api.wreck; src/game.lua,
	Game:spawnWreck). They drift, can be looted with the tractor beam and
	break apart part by part like a ship's wreck. Spawn them from the F1
	panel, or draw your own in the Shipyard (F2).

	  parts  as for hulls (src/hullshape.lua)
	  armor  toughness           hold  m3 for the loot      mass  tonnes
	  loot   { { item, min, max, chance }, ... } rolled when it spawns
]]

-- Wrecks, containers and props live one per file in data/wrecks/<id>.lua,
-- named like the Shipyard's exports (mods/shipyard/data/<id>.lua). Weapons
-- are in data/modules/, stations in data/stations/, hulls in data/ships/.
