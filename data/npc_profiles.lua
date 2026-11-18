--[[
	How persistent NPCs fly and fight, one profile per job (src/npc_profile.lua).
	These replace the old enemy presets ("archetypes") the A-Life NPCs used
	to borrow. Speed comes from the ship itself (NPC.cruise) and ammo from
	its weapons (src/supplies.lua), so a profile only carries:

	ai        the same fields as an enemy's ai (data/enemies.lua). Style
	          civilian: flies its route, docks where it says, only shoots
	          back at whoever attacked it, and keeps its distance.
	team      2 = hostile, 3 = neutral
	hull, loadout  the ship a record starts with when nothing was bought for
	          it (world seeding); a bought ship replaces it
	livery, salvage  as for enemies
]]

npc_profile {
	id = "hauler", team = 3, name = "Hauler", hull = "ferrous_mule",
	ai = { style = "civilian", range = 1200, accuracy = 0.55, throttle = 0.9, horizon = 3.5, burstOn = 1.2, burstOff = 0.9 },
	salvage = { 2, 5 },
}

npc_profile {
	id = "miner", team = 3, name = "Miner", hull = "ferrous_mule",
	loadout = { "drill_m_base", "drill_m_base", false, "mule_engine", "kiln_reactor", "tug_beam", false, false },
	ai = { style = "civilian", range = 2500, accuracy = 0.7, throttle = 0.9 },
	salvage = { 1, 2 },
}

npc_profile {
	id = "police", team = 3, name = "Police", hull = "intaki_wisp",
	livery = { primary = { 0.4, 0.75, 1 } },
	loadout = { "gun_s_base", "gun_s_base", "flit_engine", "ember_reactor", false, false },
	ai = { style = "orbit", range = 900, accuracy = 0.65, throttle = 0.85 },
	salvage = { 2, 3 },
}

npc_profile {
	id = "raider", team = 2, name = "Raider", hull = "intaki_wisp",
	livery = { primary = { 1, 0.4, 0.25 } },
	loadout = { "gun_s_base", "gun_s_base", "flit_engine", "ember_reactor", false, false },
	ai = { style = "orbit", range = 700, accuracy = 0.55, throttle = 0.8 },
	salvage = { 2, 4 },
}
