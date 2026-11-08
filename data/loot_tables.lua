--[[
	Loot tables (src/loot_tables.lua). Containers and crates name one
	(lootTable = id); spawn sets (data/spawn_sets.lua) can pick another per
	placement. Entries: { item = id, min, max, weight } or
	{ table = id, weight }, optionally areas = { area = true } to only count
	there.
]]

local INNER = { mercury = true, venus = true, earth = true, luna = true, station = true }
local MARS = { mars = true, phobos = true, deimos = true }
local BELT = { belt = true, ceres_quarry = true, quarry = true, ring = true }
local GIANTS = { jupiter = true, io = true, europa = true, ganymede = true, callisto = true,
	saturn = true, enceladus = true, titan = true, titania = true, uranus = true, triton = true, pluto = true }

-- What a hauler in this part of space would have been carrying: the goods
-- the local economy actually moves.
loot_table {
	id = "hauler_goods", rolls = { 1, 2 },
	entries = {
		{ item = "hydrogen_canister", min = 8, max = 24, weight = 3, areas = INNER },
		{ item = "empty_canister", min = 10, max = 30, weight = 2, areas = INNER },
		{ item = "iron_ore", min = 12, max = 40, weight = 3, areas = MARS },
		{ item = "empty_canister", min = 10, max = 30, weight = 3, areas = MARS },
		{ item = "water_ice", min = 12, max = 40, weight = 3, areas = BELT },
		{ item = "iron_ore", min = 12, max = 40, weight = 2, areas = BELT },
		{ item = "hydrogen_canister", min = 8, max = 24, weight = 3, areas = GIANTS },
		{ item = "deuterium_canister", min = 4, max = 16, weight = 2, areas = GIANTS },
		{ item = "empty_canister", min = 10, max = 30, weight = 1 },
	},
}

-- A little ammunition, as a hauler would carry for its own guns.
loot_table {
	id = "ship_stores", rolls = { 0, 1 },
	entries = {
		{ item = "rounds_s", min = 20, max = 100, weight = 3 },
		{ item = "rounds_m", min = 20, max = 60, weight = 2 },
		{ item = "missile_s", min = 2, max = 8, weight = 1 },
		{ item = "flare", min = 4, max = 10, weight = 1 },
	},
}

-- A cargo container gone astray: its goods, maybe some stores.
loot_table {
	id = "lost_cargo",
	guaranteed = { { table = "hauler_goods" } },
	rolls = { 1, 1 },
	entries = { { table = "ship_stores", weight = 1 } },
}
