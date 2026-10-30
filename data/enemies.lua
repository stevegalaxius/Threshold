--[[
	Enemies are ships built from the same hulls and modules as the player,
	plus an AI. They carry real ammo too, and drop part of what's left.

	ai.style     rush (close in, brawl or ram), orbit (circle at range),
	             kite (hold range, back off when approached)
	ai.range     preferred distance in pixels
	ai.accuracy  0..1, how well it leads its shots
	ai.throttle  0..1, how hard it uses its engines
	ai.ram       true = keeps pushing into you instead of stopping at range
	ai.burstOn, ai.burstOff  seconds of firing, then of pause (default 1.2, 0.9)
	salvage      { min, max } salvage crates dropped
	ammoDrop     share of its remaining ammo that drops (0..1)
]]

enemy {
	id = "swarmer", name = "Scrap Drone", hull = "scrap_drone",
	cargo = { rounds_s = 150 },
	ai = { style = "rush", range = 350, accuracy = 0.35, throttle = 0.6, burstOn = 0.8, burstOff = 1.8 },
	salvage = { 1, 2 }, ammoDrop = 0.5,
}

enemy {
	id = "gunner", name = "Raider Wisp", hull = "halcyon_wisp",
	loadout = { "px2_autogun", "px2_autogun", false, "flit_engine", "ember_reactor", "thin_plate", false, "aux_thrusters" },
	cargo = { rounds_s = 300 },
	ai = { style = "orbit", range = 600, accuracy = 0.55, throttle = 0.75 },
	salvage = { 2, 3 }, ammoDrop = 0.4,
}

enemy {
	id = "brawler", name = "Raider Anvil", hull = "brute_anvil",
	loadout = { "rk7_chaingun", "rk7_chaingun", false, "mule_engine", "kiln_reactor", "slab_plate", "slab_plate", false, "aux_thrusters_m" },
	cargo = { rounds_m = 300 },
	ai = { style = "rush", range = 500, accuracy = 0.55, throttle = 0.85 },
	salvage = { 3, 5 }, ammoDrop = 0.4,
}

enemy {
	id = "sniper", name = "Raider Mortar", hull = "brute_anvil",
	loadout = { "thumper_m", "rk7_chaingun", false, "mule_engine", "kiln_reactor", "slab_plate", false, false, "aux_thrusters_m" },
	cargo = { shell_m = 24, rounds_m = 150 },
	ai = { style = "kite", range = 1500, accuracy = 0.6, throttle = 0.7, burstOn = 2, burstOff = 2 },
	salvage = { 3, 5 }, ammoDrop = 0.5,
}

-- Harasser: the fast, hard-to-hit one. Shows up from wave 3.
enemy {
	id = "interceptor", name = "Dart", hull = "nova_dart",
	cargo = { rounds_s = 200 },
	ai = { style = "orbit", range = 450, accuracy = 0.6, throttle = 1.0, burstOn = 0.8, burstOff = 1.2 },
	salvage = { 1, 3 }, ammoDrop = 0.5,
}
