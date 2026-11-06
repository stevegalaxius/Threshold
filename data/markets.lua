--[[
	Market profiles: station placements select a catalogue by its explicit ID.
	Profiles can be reused without coupling shops to station names or regions.
	Every station buys anything.

	market { id = <profile id>, station = <display label>, sells = { entries } }. A mod can replace a
	station's whole list by using the same profile ID.

	Several shops instead of one list: shops = { { name = "...",
	description = "...", sells = { entries } }, ... }. Each shop has its own
	shelf and restock; the Market tab lists them as buttons.

	Each entry: { item id, max [, restock seconds] }.
	  max      how much the station keeps on its shelf, in stacks (a stack
	           of ammo is its full stack, a module is one)
	  restock  seconds of game time for one more stack to come in while
	           it's under max. Left out, it comes from the item: ammo
	           T.restockAmmo, small modules T.restockS, and so on.

	ships = { hull ids } (optional): the station's shipyard. Each sells new,
	with its stock fit, at the hull's price; there's no stock to run out.

	Prices are the items' own (data/items.lua, data/modules.lua). Anything
	you sell a station sits on its shelf as resale for T.resaleTime
	seconds, then it's sold on.
]]

market { id = "market:venus_1", station = "Hub Station", ships = { "halcyon_wisp", "ferrous_runner" }, sells = {   -- general store
	{ "rounds_s", 6 }, { "rounds_m", 4 }, { "gun_s_base", 2 }, { "flit_engine", 1 },
	{ "ember_reactor", 1 }, { "hold_pod_s", 1 }, { "cargo_container", 2 },
} }
market { id = "market:mars_1", station = "Station Alpha", ships = { "brute_anvil" }, sells = {   -- artillery
	{ "shell_s", 6 }, { "shell_m", 4 }, { "artillery_s_base", 2 }, { "artillery_m_base", 1 },
	{ "torp_s", 3 }, { "missile_s_base", 1 }, { "mule_engine", 1 },
} }
market { id = "market:mars_3", station = "Heaven-Ladder", sells = {   -- Mandate bulk freight
	{ "martian_ore", 8 }, { "salvage_kit", 3 }, { "scrap", 6 },
	{ "bore_drill", 2 }, { "rockbiter", 1 }, { "deep_core_drill", 1 }, { "iron_ore", 4 }, { "water_ice", 4 },
} }
market { id = "market:mars_2", station = "Station Beta", sells = {   -- missiles and drones
	{ "missile_s", 4 }, { "missile_m", 3 }, { "missile_s_base", 2 }, { "missile_m_base", 1 },
	{ "drone_s", 2 }, { "drone_m", 1 }, { "wasp_bay", 1 }, { "hive_bay", 1 }, { "tug_beam", 1 }, { "flare_pod", 1 }, { "flare", 6 }, { "scanner", 1 },
} }
market { id = "market:earth_1", station = "Orbital One", shops = {   -- heavy weapons
	{ name = "Kinetic armory", description = "Autocannons, the Long Tom and heavy shells.", sells = {
		{ "gun_m_base", 2 }, { "gun_l_base", 1 }, { "artillery_l_base", 1 }, { "shell_l", 4 },
	} },
	{ name = "Beam works", description = "Lasers and beam weapons. No ammo needed, just power.", sells = {
		{ "glint_laser", 2 }, { "lumen_lance", 1 }, { "sunder_beam", 1 },
		{ "thread_beam", 2 }, { "searing_ray", 1 }, { "furnace_beam", 1 },
	} },
} }
market { id = "market:earth_2", station = "Orbital Two", ships = { "ferrous_bastion", "ferrous_freighter", "ferrous_mule" }, sells = {   -- capital gear
	{ "missile_l", 2 }, { "missile_l_base", 1 }, { "torp_m", 2 }, { "missile_m_base", 1 },
	{ "torp_l", 1 }, { "drone_l", 1 }, { "carrier_deck", 1 },
	{ "cinder_drive", 1 }, { "kiln_reactor", 1 }, { "hold_pod_s", 1 }, { "forge_reactor", 1 }, { "nav_computer", 2 }, { "fire_computer", 1 }, { "guidance_computer", 1 }, { "drone_uplink", 1 },
} }

-- Moon stations. Each sells its own few things.
market { id = "market:luna_1", station = "Tranquility Dock", sells = {   -- miners' supply
	{ "rounds_s", 6 }, { "shell_s", 4 }, { "hold_pod_s", 2 }, { "tug_beam", 1 },
} }
market { id = "market:luna_2", station = "Shackleton Station", sells = {   -- polar depot
	{ "cargo_container", 3 }, { "nav_computer", 1 },
} }
market { id = "market:europa_1", station = "Conamara Station", sells = {   -- ice haulers
	{ "hold_pod_s", 1 }, { "mule_engine", 1 }, { "rounds_m", 4 },
} }
market { id = "market:europa_2", station = "Pwyll Station", sells = {
	{ "glint_laser", 1 }, { "missile_s", 4 }, { "missile_s_base", 1 },
} }
market { id = "market:ganymede_1", station = "Galileo Regio", sells = {   -- Jovian Accord yard
	{ "gun_m_base", 1 }, { "shell_m", 4 }, { "artillery_m_base", 1 },
} }
market { id = "market:ganymede_2", station = "Uruk Station", sells = {
	{ "drone_s", 2 }, { "wasp_bay", 1 }, { "ember_reactor", 1 },
} }
market { id = "market:titan_1", station = "Kraken Station", sells = {   -- Caliphate refinery
	{ "kiln_reactor", 1 }, { "torp_s", 3 }, { "missile_s_base", 1 },
} }
market { id = "market:titan_2", station = "Huygens Station", sells = {
	{ "missile_m", 3 }, { "missile_m_base", 1 }, { "fire_computer", 1 },
} }
market { id = "market:triton_1", station = "Cipango Station", sells = {   -- frontier outpost
	{ "rounds_s", 4 }, { "artillery_s_base", 1 }, { "flit_engine", 1 },
} }
market { id = "market:triton_2", station = "Voyager Station", sells = {
	{ "lumen_lance", 1 }, { "guidance_computer", 1 }, { "drone_m", 1 },
} }

-- Expanded destinations: modest working catalogues using existing equipment.
market { id = "market:io_1", station = "Pele Works", sells = {
	{ "kiln_reactor", 1 }, { "shell_m", 4 }, { "artillery_m_base", 1 },
} }
market { id = "market:io_2", station = "Loki Laboratory", sells = {
	{ "glint_laser", 1 }, { "ember_reactor", 1 }, { "nav_computer", 1 },
} }
market { id = "market:callisto_1", station = "Valhalla Port", sells = {
	{ "hold_pod_s", 1 }, { "cargo_container", 3 }, { "rounds_m", 4 },
} }
market { id = "market:callisto_2", station = "Asgard Station", sells = {
	{ "drone_s", 2 }, { "wasp_bay", 1 }, { "tug_beam", 1 },
} }
market { id = "market:enceladus_1", station = "Tiger Stripe Laboratory", sells = {
	{ "guidance_computer", 1 }, { "glint_laser", 1 }, { "ember_reactor", 1 },
} }
market { id = "market:enceladus_2", station = "South Pole Port", sells = {
	{ "hold_pod_s", 2 }, { "cargo_container", 3 }, { "flit_engine", 1 },
} }
market { id = "market:pluto_1", station = "Milliways Freeport", sells = {
	{ "rounds_s", 4 }, { "artillery_s_base", 1 }, { "nav_computer", 1 },
} }
market { id = "market:pluto_2", station = "Sputnik Port", sells = {
	{ "missile_s", 4 }, { "missile_s_base", 1 },
} }

market { id = "market:titania_1", station = "Gertrude Port", sells = {
	{ "cargo_container", 3 }, { "hold_pod_s", 2 }, { "rounds_s", 4 },
} }
market { id = "market:titania_2", station = "Messina Research Station", sells = {
	{ "nav_computer", 1 }, { "glint_laser", 1 }, { "guidance_computer", 1 },
} }
