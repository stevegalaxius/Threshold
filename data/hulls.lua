--[[
	Hulls. A hull is a fixed, branded product: it sets the slot layout,
	base stats and two or three bonuses that multiply specific stats.

	Units used everywhere in data/:
	  mass   tonnes          thrust  kN (engines)
	  armor  hit points      turn    turning torque (bigger = snappier)
	  sideThrust  kN of maneuvering thrusters, used for strafing and reverse.
	              The main engine only pushes forward, so this is what lets a
	              ship move sideways while keeping its guns on target.
	  hold   cubic metres    drag    quadratic drag; top speed = sqrt(thrust*100 / drag)
	  radius collision radius in pixels
	  shape  outline drawn for the ship, as x,y pairs in pixels, nose pointing +x

	Slots: family is primary, secondary, engine, reactor, armor or utility;
	size is S, M or L, and a module only fits a slot of its own family and
	size. Slots with x,y are drawn on the hull (weapons fire from there).

	loadout lists the module id fitted to each slot, in slot order
	(false = empty). cargo is what's in the hold when you take the hull out.
]]

hull {
	id = "halcyon_wisp", name = "Wisp", maker = "Halcyon Arms", class = "light",
	mass = 50, armor = 80, turn = 500, sideThrust = 240, hold = 24, drag = 0.14, radius = 16,
	shape = { 20,0, 4,-7, -6,-14, -14,-12, -10,0, -14,12, -6,14, 4,7 },
	slots = {
		{ family = "primary",   size = "S", x = 6,   y = -9 },
		{ family = "primary",   size = "S", x = 6,   y = 9 },
		{ family = "secondary", size = "S", x = -2,  y = 0 },
		{ family = "engine",    size = "S", x = -13, y = 0 },
		{ family = "reactor",   size = "S" },
		{ family = "armor",     size = "S" },
		{ family = "utility",   size = "S" },
	},
	bonuses = { primaryFireRate = 1.15, hullMass = 0.85 },
	loadout = { "px2_autogun", "px2_autogun", "sparrow_rack", "flit_engine", "ember_reactor", "thin_plate", "hold_pod_s" },
	cargo = { rounds_s = 400, missile_s = 4 },
	price = 14000,
}

hull {
	id = "brute_anvil", name = "Anvil", maker = "Brute Industries", class = "medium",
	mass = 130, armor = 140, turn = 1500, sideThrust = 200, hold = 40, drag = 0.36, radius = 24,
	shape = { 26,-8, 26,8, 12,18, -16,20, -24,10, -24,-10, -16,-20, 12,-18 },
	slots = {
		{ family = "primary",   size = "M", x = 14,  y = -14 },
		{ family = "primary",   size = "M", x = 14,  y = 14 },
		{ family = "secondary", size = "S", x = 4,   y = 0 },
		{ family = "engine",    size = "M", x = -24, y = 0 },
		{ family = "reactor",   size = "M" },
		{ family = "armor",     size = "M" },
		{ family = "armor",     size = "M" },
		{ family = "utility",   size = "S" },
	},
	bonuses = { armor = 1.2, ramDamage = 1.25 },
	loadout = { "rk7_chaingun", "rk7_chaingun", "sparrow_rack", "mule_engine", "kiln_reactor", "slab_plate", "slab_plate", "tug_beam" },
	cargo = { rounds_m = 500, missile_s = 6 },
	price = 38000,
}

hull {
	id = "ferrous_bastion", name = "Bastion", maker = "Ferrous Collective", class = "heavy",
	mass = 300, armor = 260, turn = 4500, sideThrust = 220, hold = 80, drag = 1.0, radius = 34,
	shape = { 38,0, 24,-20, -6,-30, -30,-26, -36,0, -30,26, -6,30, 24,20 },
	slots = {
		{ family = "primary",   size = "L", x = 30,  y = 0 },
		{ family = "primary",   size = "M", x = 12,  y = -24 },
		{ family = "primary",   size = "M", x = 12,  y = 24 },
		{ family = "secondary", size = "M", x = -4,  y = 0 },
		{ family = "engine",    size = "L", x = -36, y = 0 },
		{ family = "reactor",   size = "M" },
		{ family = "armor",     size = "L" },
		{ family = "armor",     size = "L" },
		{ family = "utility",   size = "M" },
	},
	bonuses = { missileDamage = 1.15, hold = 1.3 },
	loadout = { "long_tom", "rk7_chaingun", "rk7_chaingun", "hornet_pod", "cinder_drive", "kiln_reactor", "bulwark_plate", "bulwark_plate", "hold_pod_m" },
	cargo = { shell_l = 30, rounds_m = 600, missile_m = 6 },
	price = 95000,
}

-- Enemy-only hulls.

-- Basic enemy: no maneuvering thrusters, so it flies in straight lines and
-- has to turn around after it overshoots.
hull {
	id = "scrap_drone", name = "Scrap Drone", maker = "Nova Syndicate", class = "drone", playable = false,
	mass = 30, armor = 10, turn = 160, sideThrust = 0, hold = 8, drag = 0.14, radius = 13,
	shape = { 15,0, -9,-11, -5,0, -9,11 },
	slots = {
		{ family = "primary", size = "S", x = 4,  y = 0 },
		{ family = "engine",  size = "S", x = -8, y = 0 },
		{ family = "reactor", size = "S" },
		{ family = "armor",   size = "S" },
	},
	loadout = { "px2_autogun", "flit_engine", "ember_reactor", "thin_plate" },
	cargo = { rounds_s = 150 },
}

-- Harasser: tiny, twitchy, strong side thrusters. Hard to hit on purpose.
hull {
	id = "nova_dart", name = "Dart", maker = "Nova Syndicate", class = "drone", playable = false,
	mass = 24, armor = 30, turn = 220, sideThrust = 320, hold = 6, drag = 0.12, radius = 11,
	shape = { 14,0, 2,-5, -8,-10, -5,0, -8,10, 2,5 },
	slots = {
		{ family = "primary", size = "S", x = 5,  y = 0 },
		{ family = "engine",  size = "S", x = -7, y = 0 },
		{ family = "reactor", size = "S" },
	},
	loadout = { "px2_autogun", "flit_engine", "ember_reactor" },
	cargo = { rounds_s = 200 },
}
