--[[
	Station markets: what each station sells, by station name (the names in
	src/fields.lua). Every station sells its own things; none repeats
	another's. Every station buys anything.

	market { station = <name>, sells = { entries } }. A mod can replace a
	station's whole list by naming the same station.

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

market { station = "Hub Station", ships = { "halcyon_wisp", "ferrous_runner" }, sells = {   -- general store
	{ "rounds_s", 6 }, { "rounds_m", 4 }, { "px2_autogun", 2 }, { "flit_engine", 1 },
	{ "ember_reactor", 1 }, { "hold_pod_s", 1 }, { "aux_thrusters", 1 }, { "cargo_container", 2 },
} }
market { station = "Station Alpha", ships = { "brute_anvil" }, sells = {   -- artillery
	{ "shell_s", 6 }, { "shell_m", 4 }, { "pip_mortar", 2 }, { "thumper_m", 1 },
	{ "torp_s", 3 }, { "maul_tube", 1 }, { "mule_engine", 1 },
} }
market { station = "Station Beta", sells = {   -- missiles and drones
	{ "missile_s", 4 }, { "missile_m", 3 }, { "sparrow_rack", 2 }, { "hornet_pod", 1 },
	{ "drone_s", 2 }, { "drone_m", 1 }, { "wasp_bay", 1 }, { "hive_bay", 1 }, { "tug_beam", 1 },
} }
market { station = "Orbital One", sells = {   -- heavy weapons
	{ "rk7_autocannon", 2 }, { "rk14_twin", 1 }, { "long_tom", 1 }, { "shell_l", 4 },
	{ "glint_laser", 2 }, { "lumen_lance", 1 }, { "sunder_beam", 1 },
} }
market { station = "Orbital Two", ships = { "ferrous_bastion", "ferrous_freighter", "ferrous_mule" }, sells = {   -- capital gear
	{ "missile_l", 2 }, { "trident_bay", 1 }, { "torp_m", 2 }, { "breaker_tube", 1 },
	{ "torp_l", 1 }, { "leviathan_tube", 1 }, { "drone_l", 1 }, { "carrier_deck", 1 },
	{ "cinder_drive", 1 }, { "kiln_reactor", 1 }, { "hold_pod_m", 1 }, { "forge_reactor", 1 }, { "nav_computer", 2 }, { "fire_computer", 1 }, { "guidance_computer", 1 }, { "drone_uplink", 1 },
} }

-- Moon stations. Each sells its own few things.
market { station = "Tranquility Dock", sells = {   -- miners' supply
	{ "rounds_s", 6 }, { "shell_s", 4 }, { "hold_pod_s", 2 }, { "tug_beam", 1 },
} }
market { station = "Shackleton Station", sells = {   -- polar depot
	{ "cargo_container", 3 }, { "aux_thrusters", 1 }, { "nav_computer", 1 },
} }
market { station = "Conamara Station", sells = {   -- ice haulers
	{ "hold_pod_m", 1 }, { "mule_engine", 1 }, { "rounds_m", 4 },
} }
market { station = "Pwyll Station", sells = {
	{ "glint_laser", 1 }, { "missile_s", 4 }, { "sparrow_rack", 1 },
} }
market { station = "Galileo Regio", sells = {   -- Jovian Accord yard
	{ "rk7_autocannon", 1 }, { "shell_m", 4 }, { "thumper_m", 1 },
} }
market { station = "Uruk Station", sells = {
	{ "drone_s", 2 }, { "wasp_bay", 1 }, { "ember_reactor", 1 },
} }
market { station = "Kraken Station", sells = {   -- Caliphate refinery
	{ "kiln_reactor", 1 }, { "torp_s", 3 }, { "maul_tube", 1 },
} }
market { station = "Huygens Station", sells = {
	{ "missile_m", 3 }, { "hornet_pod", 1 }, { "fire_computer", 1 },
} }
market { station = "Cipango Station", sells = {   -- frontier outpost
	{ "rounds_s", 4 }, { "pip_mortar", 1 }, { "flit_engine", 1 },
} }
market { station = "Voyager Station", sells = {
	{ "lumen_lance", 1 }, { "guidance_computer", 1 }, { "drone_m", 1 },
} }

-- Expanded destinations: modest working catalogues using existing equipment.
market { station = "Phobos Strip Mine", ships = { "ferrous_freighter" }, sells = {
	{ "tug_beam", 2 }, { "cargo_container", 4 }, { "hold_pod_m", 2 }, { "rounds_m", 4 },
} }
market { station = "Deimos Strip Mine", ships = { "ferrous_runner" }, sells = {
	{ "hold_pod_s", 2 }, { "aux_thrusters", 2 }, { "mule_engine", 1 }, { "cargo_container", 4 },
} }
market { station = "Pele Works", sells = {
	{ "kiln_reactor", 1 }, { "shell_m", 4 }, { "thumper_m", 1 },
} }
market { station = "Loki Laboratory", sells = {
	{ "glint_laser", 1 }, { "ember_reactor", 1 }, { "nav_computer", 1 },
} }
market { station = "Valhalla Port", sells = {
	{ "hold_pod_m", 1 }, { "cargo_container", 3 }, { "rounds_m", 4 },
} }
market { station = "Asgard Station", sells = {
	{ "drone_s", 2 }, { "wasp_bay", 1 }, { "tug_beam", 1 },
} }
market { station = "Tiger Stripe Laboratory", sells = {
	{ "guidance_computer", 1 }, { "glint_laser", 1 }, { "ember_reactor", 1 },
} }
market { station = "South Pole Port", sells = {
	{ "hold_pod_s", 2 }, { "cargo_container", 3 }, { "flit_engine", 1 },
} }
market { station = "Tombaugh Station", sells = {
	{ "rounds_s", 4 }, { "pip_mortar", 1 }, { "nav_computer", 1 },
} }
market { station = "Sputnik Port", sells = {
	{ "missile_s", 4 }, { "sparrow_rack", 1 }, { "aux_thrusters", 1 },
} }
