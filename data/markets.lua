--[[
	Market profiles: station placements select a catalogue by its explicit ID.
	Profiles can be reused without coupling shops to station names or regions.
	Every station buys anything.

	market { id = <profile id>, station = <display label>, sells = { entries } }. A mod can replace a
	station's whole list by using the same profile ID.

	Several shops instead of one list: shops = { { name = "...",
	description = "...", sells = { entries } }, ... }. Each shop has its own
	stockpile and restock; the Market tab lists them as buttons. NPC haulers
	and miners use the first shop that lists an item (src/stockpile.lua).

	Each entry: { item id, max [, restock seconds] }.
	  max      how much the station keeps on its shelf, in stacks (a stack
	           of ammo is its full stack, a module is one)
	  restock  seconds of game time for one more stack to come in while
	           it's under max. Left out, it comes from the item: ammo
	           T.restockAmmo, small modules T.restockS, and so on.

	dealer = { ... } (optional): the station's ship dealership, a lot of
	specific ships in limited number, each with its own trim, paint and
	price, refilled over time (or built from hull frames, for a
	manufacturer). src/dealers.lua has the fields.

	Prices are the items' own (data/items.lua, data/modules.lua). Anything
	you sell a station sits on its shelf as resale for T.resaleTime
	seconds, then it's sold on.
]]

market { id = "market:venus_1", station = "Hub Station", dealer = { name = "Hub Station Motors", hulls = { "ferrous_runner", "ferrous_mule", "mack_mustang", "mack_burro", "intaki_wisp", "brute_runt" }, lots = 6, restock = 8 }, sells = {   -- general store
	{ "rounds_s", 6 }, { "airburst_s", 4 }, { "rounds_m", 4 }, { "airburst_m", 3 }, { "gun_s_base", 2 }, { "flit_engine", 1 },
	{ "ember_reactor", 1 }, { "hold_pod_s", 1 }, { "cargo_container", 2 },
} }
market { id = "market:mercury_2", station = "Haephestus Logistics", sells = {   -- logistics equipment store
	{ "rounds_m", 4 }, { "shell_m", 3 }, { "artillery_s_base", 1 }, { "cinder_drive", 1 }, { "forge_reactor", 1 }, { "hold_pod_s", 1 },
} }
market { id = "market:mars_1", station = "Station Alpha", dealer = { name = "Intaki Zhuhai Atelier", hulls = { "intaki_wisp", "intaki_praetor", "intaki_archangel" }, lots = 3, assembly = "intaki_assembly", markup = 1.2, trims = { "stock" } }, sells = {   -- artillery
	{ "shell_s", 6 }, { "shell_m", 4 }, { "artillery_s_base", 2 }, { "artillery_m_base", 1 },
	{ "torp_s", 3 }, { "missile_s_base", 1 }, { "mule_engine", 1 },
} }
market { id = "market:mars_3", station = "Heaven-Ladder", sells = {   -- Mandate bulk freight
	{ "martian_ore", 8 }, { "salvage_kit", 3 },
	{ "drill_s_base", 2 }, { "drill_m_base", 1 }, { "drill_l_base", 1 }, { "iron_ore", 4 }, { "water_ice", 4 },
} }
market { id = "market:mars_2", station = "Station Beta", sells = {   -- missiles and drones
	{ "missile_s", 4 }, { "missile_m", 3 }, { "missile_s_base", 2 }, { "missile_m_base", 1 },
	{ "drone_s", 2 }, { "drone_m", 1 }, { "drone_s_base", 1 }, { "drone_m_base", 1 }, { "tug_beam", 1 }, { "flare_pod", 1 }, { "flare", 6 }, { "scanner", 1 },
} }
market { id = "market:earth_1", station = "Orbital One", shops = {   -- heavy weapons
	{ name = "Kinetic armory", description = "Guns, artillery, solid and airburst rounds, explosive and scatter shells.", sells = {
		{ "gun_m_base", 2 }, { "gun_l_base", 1 }, { "artillery_l_base", 1 }, { "shell_l", 4 },
		{ "rounds_s", 6 }, { "rounds_m", 4 }, { "airburst_s", 4 }, { "airburst_m", 3 },
		{ "shot_s", 4 }, { "shot_m", 4 }, { "shot_l", 3 },
	} },
	{ name = "Beam works", description = "Lasers and beam weapons. No ammo needed, just power.", sells = {
		{ "pulse_s_base", 2 }, { "pulse_m_base", 1 }, { "pulse_l_base", 1 },
		{ "beam_s_base", 2 }, { "beam_m_base", 1 }, { "beam_l_base", 1 },
	} },
} }
market { id = "market:earth_2", station = "Orbital Two", sells = {   -- capital gear
	{ "missile_l", 2 }, { "missile_l_base", 1 }, { "torp_m", 2 }, { "missile_m_base", 1 },
	{ "torp_l", 1 }, { "drone_l", 1 }, { "drone_l_base", 1 },
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
	{ "pulse_s_base", 1 }, { "missile_s", 4 }, { "missile_s_base", 1 },
} }
market { id = "market:ganymede_1", station = "Galileo Regio", sells = {   -- Jovian Accord yard
	{ "gun_m_base", 1 }, { "shell_m", 4 }, { "artillery_m_base", 1 },
} }
market { id = "market:ganymede_2", station = "Uruk Station", sells = {
	{ "drone_s", 2 }, { "drone_s_base", 1 }, { "ember_reactor", 1 },
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
	{ "pulse_m_base", 1 }, { "guidance_computer", 1 }, { "drone_m", 1 },
} }

-- Expanded destinations: modest working catalogues using existing equipment.
market { id = "market:io_1", station = "Pele Works", sells = {
	{ "kiln_reactor", 1 }, { "shell_m", 4 }, { "artillery_m_base", 1 },
} }
market { id = "market:io_2", station = "Loki Laboratory", sells = {
	{ "pulse_s_base", 1 }, { "ember_reactor", 1 }, { "nav_computer", 1 },
} }
market { id = "market:callisto_1", station = "Valhalla Port", sells = {
	{ "hold_pod_s", 1 }, { "cargo_container", 3 }, { "rounds_m", 4 },
} }
market { id = "market:callisto_2", station = "Asgard Station", sells = {
	{ "drone_s", 2 }, { "drone_s_base", 1 }, { "tug_beam", 1 },
} }
market { id = "market:enceladus_1", station = "Tiger Stripe Laboratory", sells = {
	{ "guidance_computer", 1 }, { "pulse_s_base", 1 }, { "ember_reactor", 1 },
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
	{ "nav_computer", 1 }, { "pulse_s_base", 1 }, { "guidance_computer", 1 },
} }

-- Ring Station and its Quarry.
market { id = "market:ring_1", station = "Ring Station", dealer = { name = "Ring Station Used Hulls", hulls = { "mack_mustang", "mack_burro", "mack_longhorn", "ferrous_runner", "ferrous_mule" }, lots = 5, restock = 12, markup = 0.85, trims = { "stripped" } }, sells = {   -- belt crossroads
	{ "iron_ore", 4 },
	{ "rounds_s", 6 }, { "rounds_m", 4 }, { "shell_s", 3 }, { "gun_s_base", 2 },
	{ "hold_pod_s", 2 }, { "cargo_container", 3 }, { "nav_computer", 1 },
} }
market { id = "market:quarry_1", station = "Quarry Ore Depot", sells = {   -- drill crews' supply
	{ "iron_ore", 4 },
	{ "rounds_s", 4 }, { "tug_beam", 1 }, { "hold_pod_s", 2 }, { "mule_engine", 1 },
} }
market { id = "market:ceres_quarry_1", station = "Ceres Quarry Depot", sells = {   -- drill crews' supply
	{ "iron_ore", 4 }, { "rounds_s", 4 }, { "shell_s", 3 }, { "hold_pod_s", 2 }, { "tug_beam", 1 },
} }
market { id = "market:belt_1", station = "Ceres Dock", sells = {   -- deuterium works
	{ "deuterium_canister", 6 }, { "empty_canister", 2 }, { "water_ice", 2 },
	{ "rounds_s", 4 }, { "drill_s_base", 1 },
} }
market { id = "market:belt_2", station = "MACK Industrial Works", dealer = { name = "MACK Industrial Works", hulls = { "mack_mustang", "mack_burro", "mack_longhorn" }, lots = 5, assembly = "mack_assembly", markup = 0.95 }, sells = {   -- belt freight forwarder
	{ "iron_ore", 4 }, { "cargo_container", 4 }, { "hold_pod_s", 2 }, { "mule_engine", 1 },
} }

market { id = "market:mercury_3", station = "Brute Industries Shipyard", dealer = { name = "Brute Industries Works", hulls = { "brute_runt", "brute_anvil", "brute_nautilus" }, lots = 4, assembly = "brute_assembly", markup = 0.95 }, sells = {
 { "cargo_container", 2 }, { "nav_computer", 1 },
} }

market { id = "market:earth_3", station = "Ferrous Collective Shipyard", dealer = { name = "Ferrous Collective Works", hulls = { "ferrous_runner", "ferrous_mule", "ferrous_bison" }, lots = 5, assembly = "ferrous_assembly" }, sells = {
 { "cargo_container", 2 }, { "nav_computer", 1 },
} }
