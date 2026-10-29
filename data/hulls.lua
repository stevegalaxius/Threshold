--[[
	Hulls. A hull is a fixed, branded product: it sets the slot layout,
	base stats and two or three bonuses that multiply specific stats.

	Units used everywhere in data/:
	  mass   tonnes          thrust  kN (engines)
	  armor  hit points      turn    turning torque (bigger = snappier)
	  sideThrust  kN of maneuvering thrusters, used for strafing and reverse.
	              The main engine only pushes forward, so this is what lets a
	              ship move sideways while keeping its guns on target.
	  turnSpeed  optional cap on spin speed in degrees/second, so a heavy hull
	             comes about slowly even with a big engine
	  hold   cubic metres    drag    quadratic drag; top speed = sqrt(thrust*100 / drag)
	  radius collision radius in pixels
	  shape  outline drawn for the ship, as x,y pairs in pixels, nose pointing +x
	  mount  how the hull carries its weapons, which sets how each class feels:
	         fixed   guns point straight down the nose; you aim with the ship
	         gimbal  guns swing a few degrees toward the cursor (default)
	         turret  guns rotate all the way around, turretTurn degrees/second
	         A slot can override it with its own mount.

	Slots: family is primary, secondary, engine, reactor, armor or utility;
	size is S, M or L, and a module only fits a slot of its own family and
	size. Slots with x,y are drawn on the hull (weapons fire from there).

	loadout lists the module id fitted to each slot, in slot order
	(false = empty). cargo is what's in the hold when you take the hull out.
]]

hull {
	id = "halcyon_wisp", name = "Wisp", maker = "Halcyon Arms", class = "light", mount = "fixed",
	mass = 50, armor = 80, turn = 500, sideThrust = 340, hold = 24, drag = 0.14, radius = 16,
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
	id = "brute_anvil", name = "Anvil", maker = "Brute Industries", class = "medium", mount = "gimbal",
	mass = 200, armor = 200, turn = 3500, turnSpeed = 200, sideThrust = 600, hold = 50, drag = 0.5, radius = 34,
	shape = { 37,-11, 37,11, 17,26, -23,28, -34,14, -34,-14, -23,-28, 17,-26 },
	slots = {
		{ family = "primary",   size = "M", x = 20,  y = -20 },
		{ family = "primary",   size = "M", x = 20,  y = 20 },
		{ family = "secondary", size = "S", x = 6,   y = 0 },
		{ family = "engine",    size = "M", x = -34, y = 0 },
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

-- Battleship: huge, slow to turn, and every gun is on a turret, so it can
-- fight in every direction at once while the hull lumbers along.
hull {
	id = "ferrous_bastion", name = "Bastion", maker = "Ferrous Collective", class = "heavy", mount = "turret", turretTurn = 150,
	mass = 600, armor = 500, turn = 3200, turnSpeed = 50, sideThrust = 1100, hold = 120, drag = 1.6, radius = 62,
	shape = { 72,0, 54,-26, 16,-46, -34,-50, -62,-36, -68,0, -62,36, -34,50, 16,46, 54,26 },
	slots = {
		{ family = "primary",   size = "L", x = 40,  y = 0 },
		{ family = "primary",   size = "L", x = -30, y = 0 },
		{ family = "primary",   size = "M", x = 14,  y = -32 },
		{ family = "primary",   size = "M", x = 14,  y = 32 },
		{ family = "primary",   size = "M", x = -26, y = -36 },
		{ family = "primary",   size = "M", x = -26, y = 36 },
		{ family = "secondary", size = "M", x = 6,   y = 0 },
		{ family = "engine",    size = "L", x = -66, y = 0 },
		{ family = "reactor",   size = "M" },
		{ family = "armor",     size = "L" },
		{ family = "armor",     size = "L" },
		{ family = "armor",     size = "L" },
		{ family = "utility",   size = "M" },
	},
	bonuses = { missileDamage = 1.15, hold = 1.3 },
	loadout = { "long_tom", "long_tom", "rk7_chaingun", "rk7_chaingun", "rk7_chaingun", "rk7_chaingun", "hornet_pod",
		"cinder_drive", "kiln_reactor", "bulwark_plate", "bulwark_plate", "bulwark_plate", "hold_pod_m" },
	cargo = { shell_l = 60, rounds_m = 1000, missile_m = 8 },
	price = 95000,
}

-- Enemy-only hulls.

-- Basic enemy: no maneuvering thrusters, so it flies in straight lines and
-- has to turn around after it overshoots.
hull {
	id = "scrap_drone", name = "Scrap Drone", maker = "Nova Syndicate", class = "drone", playable = false, mount = "fixed",
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
	id = "nova_dart", name = "Dart", maker = "Nova Syndicate", class = "drone", playable = false, mount = "fixed",
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
