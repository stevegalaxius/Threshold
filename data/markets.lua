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

-- Unspecified stations get ordinary supplies, never another station's dealer.
local generalStore = {
	{ "rounds_s", 6 }, { "airburst_s", 4 }, { "rounds_m", 4 }, { "airburst_m", 3 }, { "gun_s_base", 2 }, { "flit_engine", 1 },
	{ "ember_reactor", 1 }, { "hold_pod_s", 1 }, { "climate_pod_s", 1 }, { "cargo_container", 2 },
}
market { id = "market:general", station = "General store", sells = generalStore }
market { id = "market:jupiter_1", station = "Olympus", sells = generalStore }
market { id = "market:jupiter_2", station = "Kyrakos Naval Yard",
	dealer = { name = "Kyrakos Naval Yard", hulls = { "jove_picket", "jove_vigil" },
		lots = 8, assembly = "jove_assembly", service = "jove", civilianExchange = "station:jupiter_1" }, sells = {} }
-- Residential services do not grant ship sales; passenger refits stay available.
market { id = "market:venus_1", station = "Hub Station", sells = {
	{ "climate_pod_s", 1 }, { "nav_computer", 1 },
} }
market { id = "market:luna_3", station = "Tranquility Commons", sells = {
	{ "climate_pod_s", 1 }, { "nav_computer", 1 },
} }
market { id = "market:mars_5", station = "Hakka Tulou Habitat", sells = {
	{ "climate_pod_s", 1 }, { "nav_computer", 1 },
} }
market { id = "market:mercury_5", station = "Daybreak Commons", sells = {
	{ "climate_pod_s", 1 }, { "nav_computer", 1 },
} }
market { id = "market:saturn_2", station = "Shiloh", sells = {
	{ "climate_pod_s", 1 }, { "nav_computer", 1 },
} }
market { id = "market:mercury_2", station = "Haephestus Logistics", sells = {   -- logistics equipment store
	{ "rounds_m", 4 }, { "shell_m", 3 }, { "artillery_s_base", 1 }, { "cinder_drive", 1 }, { "forge_reactor", 1 }, { "hold_pod_s", 1 }, { "climate_pod_s", 1 },
} }
-- Logistics hubs: trunk-freight terminals, one per hubbed planet system.
market { id = "market:belt_3", station = "Ceres Logistics", sells = {
	{ "rounds_m", 4 }, { "shell_m", 3 }, { "hold_pod_s", 1 }, { "cargo_container", 2 }, { "satellite_package", 4 },
} }
market { id = "market:jupiter_3", station = "Jovian Logistics", sells = {
	{ "rounds_m", 4 }, { "airburst_m", 3 }, { "hold_pod_s", 1 }, { "cargo_container", 2 }, { "satellite_package", 4 },
} }
market { id = "market:uranus_3", station = "Uranian Logistics", sells = {
	{ "rounds_m", 4 }, { "airburst_m", 3 }, { "hold_pod_s", 1 }, { "cargo_container", 2 }, { "satellite_package", 4 },
} }
market { id = "market:mars_4", station = "Zhuhai Logistics", sells = {
	{ "shell_m", 4 }, { "missile_s", 2 }, { "hold_pod_s", 1 }, { "cargo_container", 2 }, { "satellite_package", 4 },
} }
market { id = "market:triton_3", station = "Triton Logistics", sells = {
	{ "rounds_m", 4 }, { "shell_m", 3 }, { "hold_pod_s", 1 }, { "cargo_container", 2 }, { "satellite_package", 4 },
} }
market { id = "market:venus_2", station = "Cloudline Station", sells = {
	{ "hold_pod_s", 1 }, { "cargo_container", 2 },
} }
market { id = "market:venus_4", station = "Venus Logistics", sells = {
	{ "rounds_s", 4 }, { "shell_s", 3 }, { "hold_pod_s", 1 }, { "cargo_container", 2 }, { "satellite_package", 4 },
} }
-- Specialized shelves take their stock from production and freight.
market { id = "market:saturn_1", station = "Zebulun's Bounty", sells = {
	{ "food_crate", 0 }, { "fertilizer", 0 },
} }
market { id = "market:saturn_3", station = "Saturn Logistics", sells = {
	{ "rounds_m", 4 }, { "shell_m", 3 }, { "hold_pod_s", 1 }, { "cargo_container", 2 }, { "satellite_package", 4 },
} }
-- Moon customs: each moon's exports leave, and its imports arrive, here.
market { id = "market:io_3", station = "Io Customs", sells = {
	{ "rounds_m", 2 }, { "hold_pod_s", 1 }, { "cargo_container", 2 },
} }
market { id = "market:europa_3", station = "Europa Customs", sells = {
	{ "rounds_m", 2 }, { "hold_pod_s", 1 }, { "cargo_container", 2 },
} }
market { id = "market:ganymede_3", station = "Ganymede Customs", sells = {
	{ "rounds_m", 2 }, { "hold_pod_s", 1 }, { "cargo_container", 2 },
} }
market { id = "market:callisto_3", station = "Callisto Customs", sells = {
	{ "rounds_m", 2 }, { "hold_pod_s", 1 }, { "cargo_container", 2 },
} }
market { id = "market:mars_1", station = "Red Furnace Shipyard", dealer = { name = "Red Furnace Shipyard", hulls = { "redfu_crane", "redfu_pelican", "redfu_gila" }, lots = 6, assembly = "redfu_assembly", markup = 0.90, trims = { "stripped", "stock" } }, sells = {
	{ "mule_engine", 1 },
} }
market { id = "market:mars_3", station = "Heaven-Ladder", sells = {
	{ "gun_s_base", 0 }, { "gun_m_base", 0 }, { "gun_l_base", 0 },
	{ "artillery_s_base", 0 }, { "artillery_m_base", 0 }, { "artillery_l_base", 0 },
	{ "iron_ore", 4 }, { "water_ice", 4 },
} }
market { id = "market:mars_2", station = "Zhongke Intelligent Manufacturing", dealer = { name = "Zhongke Intaki Atelier", hulls = { "intaki_wisp", "intaki_praetor", "intaki_archangel" }, lots = 5, assembly = "intaki_assembly", markup = 1.2, trims = { "stock" } }, sells = {   -- missiles and drones
	{ "missile_s", 4 }, { "missile_m", 3 }, { "missile_s_base", 2 }, { "missile_m_base", 1 },
	{ "drone_s", 2 }, { "drone_m", 1 }, { "drone_s_base", 1 }, { "drone_m_base", 1 }, { "tug_beam", 1 }, { "flare_pod", 1 }, { "flare", 6 }, { "scanner", 1 },
} }
market { id = "market:mars_mine", station = "Mars mining supplies", sells = {
	{ "drill_s_base", 2 }, { "drill_m_base", 1 }, { "drill_l_base", 1 },
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
market { id = "market:earth_2", station = "Elysium", sells = {   -- passenger fittings and capital gear
	{ "climate_pod_s", 1 },
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
market { id = "market:luna_4", station = "Kepler Avionics Works", sells = {
	{ "guidance_computer", 1 }, { "drone_uplink", 1 },
} }
market { id = "market:ganymede_5", station = "Ganymede Outfitting Works", sells = {
	{ "hold_pod_s", 1 }, { "climate_pod_s", 1 },
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
market { id = "market:titan_3", station = "Gilgal Arsenal", sells = {   -- Diwan missile works
	{ "missile_s_base", 1 }, { "missile_m_base", 1 }, { "guidance_computer", 1 },
} }
market { id = "market:mercury_4", station = "Ashgrove Drone Foundry", sells = {   -- Estates drone works
	{ "drone_s_base", 1 }, { "drone_m_base", 1 },
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
market { id = "market:pluto_1", station = "Milliways Freeport", sells = {   -- the cartel's counting house
	{ "fentanyl", 4 }, { "amphetamines", 4 }, { "cannabinoid_moss", 2 }, { "rounds_s", 4 }, { "artillery_s_base", 1 }, { "nav_computer", 1 },
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

-- Providence and its Quarry.
market { id = "market:ring_1", station = "Providence", dealer = { name = "Providence Ship Sales", hulls = { "mack_mustang", "mack_burro", "mack_longhorn", "ferrous_mule" }, lots = 5, restock = 12, markup = 0.85, trims = { "stripped" } }, sells = {   -- belt crossroads
	{ "iron_ore", 4 },
	{ "rounds_s", 6 }, { "rounds_m", 4 }, { "shell_s", 3 }, { "gun_s_base", 2 },
	{ "hold_pod_s", 2 }, { "cargo_container", 3 }, { "nav_computer", 1 },
} }
market { id = "market:ring_2", station = "Lumen Fabrication", sells = {   -- electronics fab
	{ "electronics", 4 }, { "silicon", 2 }, { "industrial_acids", 2 }, { "nav_computer", 1 },
} }
market { id = "market:quarry_1", station = "Quarry Ore Depot", sells = {   -- drill crews' supply
	{ "iron_ore", 4 },
	{ "rounds_s", 4 }, { "tug_beam", 1 }, { "hold_pod_s", 2 }, { "mule_engine", 1 },
} }
-- dark stations (src/dark.lua)
market { id = "market:shoals_1", station = "Slag Harbor", sells = {   -- pirate ore depot
	{ "iron_ore", 4 }, { "steel_plate", 3 }, { "empty_canister", 2 }, { "rounds_s", 4 }, { "drill_s_base", 1 },
} }
market { id = "market:shoals_2", station = "Cinder Works", sells = {   -- cartel lab and munitions
	{ "fentanyl", 6 }, { "amphetamines", 6 }, { "rounds_s", 6 }, { "shell_s", 4 }, { "steel_plate", 2 },
} }
market { id = "market:shoals_3", station = "Shoals Freeport", sells = {
	{ "rounds_s", 4 }, { "shell_s", 2 }, { "artillery_s_base", 1 }, { "hold_pod_s", 1 },
} }
market { id = "market:antichthon_1", station = "Antichthon Gardens", sells = {   -- moss beds and farm
	{ "cannabinoid_moss", 4 }, { "food_crate", 6 }, { "fertilizer", 2 }, { "water", 2 },
} }
market { id = "market:cordelia_1", station = "Cordelia Freeport", sells = {
	{ "rounds_s", 4 }, { "missile_s", 2 }, { "deuterium_canister", 4 }, { "nav_computer", 1 },
} }
market { id = "market:ceres_quarry_1", station = "Ceres Quarry Depot", sells = {   -- drill crews' supply
	{ "iron_ore", 4 }, { "rounds_s", 4 }, { "shell_s", 3 }, { "hold_pod_s", 2 }, { "tug_beam", 1 },
} }
market { id = "market:belt_1", station = "Ceres Dock", sells = {   -- deuterium works
	{ "deuterium_canister", 6 }, { "empty_canister", 2 }, { "water_ice", 2 },
	{ "rounds_s", 4 }, { "drill_s_base", 1 },
} }
market { id = "market:belt_2", station = "MACK Industrial Works", dealer = { name = "MACK Industrial Works", hulls = { "mack_mustang", "mack_burro", "mack_longhorn" }, lots = 7, assembly = "mack_assembly", markup = 0.95 }, sells = {   -- belt freight forwarder
	{ "iron_ore", 4 }, { "cargo_container", 4 }, { "hold_pod_s", 2 }, { "mule_engine", 1 },
} }

market { id = "market:venus_3", station = "Angelmaschinenwerft Atelier", dealer = { name = "Angelmaschinenwerft Atelier", hulls = { "amw_sprint", "amw_sprint_fat", "amw_wayfarer", "amw_wayfarer_fat" }, lots = 5, assembly = "amw_assembly", markup = 1.25, trims = { "stock" } }, sells = {
 { "nav_computer", 1 }, { "flare_pod", 1 },
} }
market { id = "market:mercury_3", station = "Brute Industries Shipyard", dealer = { name = "Brute Industries Works", hulls = { "brute_anvil", "brute_nautilus" }, lots = 6, assembly = "brute_assembly", markup = 0.95 }, sells = {
 { "cargo_container", 2 }, { "nav_computer", 1 },
} }

-- Military yards: service = the faction whose police and couriers draw
-- their ships from this lot. Nobody else can buy from it.
market { id = "market:earth_5", station = "Estates Naval Yards", dealer = { name = "Estates Naval Yards", hulls = { "estates_whisper", "estates_rapier", "estates_bastion" }, lots = 8, assembly = "estates_assembly", service = "estates" }, sells = {
 { "cargo_container", 2 }, { "nav_computer", 1 },
} }
market { id = "market:saturn_4", station = "Diwan Military Yards", dealer = { name = "Diwan Military Yards", hulls = { "diwan_cherubim", "diwan_seraph" }, lots = 8, assembly = "diwan_assembly", service = "diwan" }, sells = {
 { "cargo_container", 2 }, { "nav_computer", 1 },
} }

market { id = "market:earth_3", station = "Ferrous Collective Shipyard", dealer = { name = "Ferrous Collective Works", hulls = { "ferrous_pony", "ferrous_mule", "ferrous_bison", "ferrous_bison_carrier" }, lots = 7, assembly = "ferrous_assembly" }, sells = {
 { "cargo_container", 2 }, { "nav_computer", 1 },
} }

-- Satellites (src/satellites.lua): small fixed vending lists, no extra
-- shops (bare). The hub sells fuel and supplies; fuel and vendor are retired
-- kinds, kept so old saves still open.
market { id = "sat:fuel", station = "Fuel buoy", bare = true, shops = { { name = "Fuel", description = "", sells = { { "deuterium_canister", 6 } } } } }
market { id = "sat:vendor", station = "Vending satellite", bare = true, shops = { { name = "Vending", description = "", sells = {
	{ "rounds_s", 4 }, { "rounds_m", 3 }, { "shell_s", 2 }, { "patch_kit", 3 }, { "deuterium_canister", 3 },
} } } }
market { id = "sat:hub", station = "Trade hub", bare = true, shops = { { name = "Hub stores", description = "Fuel and ammunition for ships passing through.", sells = {
	{ "deuterium_canister", 8 }, { "rounds_s", 4 }, { "rounds_m", 3 }, { "shell_s", 2 }, { "patch_kit", 3 },
} } } }
market { id = "sat:passive", station = "Satellite", bare = true, sells = {} }
