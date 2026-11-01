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

wreck {
	id = "derelict_tug", name = "Derelict tug",
	armor = 260, hold = 16, mass = 140,
	loot = {
		{ "scrap", 3, 8, 1 },
		{ "salvage_kit", 1, 2, 0.4 },
	},
	parts = {
		{ name = "cabin", shape = { 46,-14, 46,14, 20,22, -30,22, -40,10, -40,-10, -30,-22, 20,-22 }, core = true },
		{ name = "cargo pod", shape = { 10,-38, 10,-22, -34,-22, -34,-38 }, cargo = true, mirror = true, shade = 0.8 },
		{ name = "engine", shape = { -40,-12, -40,12, -58,16, -58,-16 }, shade = 0.6 },
		{ name = "mast", shape = { 30,-3, 70,-1, 70,1, 30,3 }, collide = false, layer = "detail" },
	},
}

prop {
	id = "hull_plate", name = "Hull plate",
	armor = 60, mass = 20,
	parts = {
		{ name = "plate", shape = { 24,-10, 30,6, 6,14, -22,10, -28,-4, -8,-12 } },
		{ name = "rib", shape = { 18,-8, 22,4, -16,8, -20,-2 }, shade = 0.7, layer = "detail", collide = false },
	},
}
