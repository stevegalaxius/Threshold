--[[
	Hulls. A hull is a fixed, branded product: it sets the slot layout,
	base stats and optional bonuses that multiply specific stats
	(bonuses = { armor = 1.2, ... }; see src/stats.lua). No hull uses
	bonuses while the base ship classes are being worked out.

	Units used everywhere in data/:
	  mass   tonnes          thrust  kN (engines)
	  armor  hit points      turn    turning torque (bigger = snappier)
	  retroThrust kN of built-in reverse thrusters (the main engine only
	              pushes forward)
	  sideThrust  kN of built-in side thrusters. Playable hulls have none:
	              strafing comes from a module in their thruster slot.
	  spoolTime   seconds for the main engine to reach full thrust; a slight
	              ramp-up makes heavy hulls feel heavy (default 0, instant)
	  helm   how A/D steer it: "strafe" (default) fires the side thrusters,
	         "turn" rotates the hull instead and the mouse only aims the
	         guns. Battleships use "turn": no thruster slot, no strafing.
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

	armor is part of the hull itself, not a module.

	Slots: family is primary, secondary, engine, reactor, utility or
	thruster; size is S, M or L, and a module only fits a slot of its own
	family and size. Utility and thruster slots are size "any": shared
	slots every class has alike. Slots with x,y are drawn on the hull
	(weapons fire from there).

	loadout lists the module id fitted to each slot, in slot order
	(false = empty). cargo is what's in the hold when you take the hull out.
]]

hull {
	id = "halcyon_wisp", name = "Wisp", maker = "Halcyon Arms", class = "light", mount = "fixed",
	mass = 58, armor = 120, turn = 500, retroThrust = 340, hold = 24, drag = 0.14, radius = 16,
	shape = { 40,0, 8,-7, -12,-14, -28,-12, -20,0, -28,12, -12,14, 8,7 },
	slots = {
		{ family = "primary",   size = "S", x = 12,   y = -9 },
		{ family = "primary",   size = "S", x = 12,   y = 9 },
		{ family = "secondary", size = "S", x = -4,  y = 0 },
		{ family = "engine",    size = "S", x = -26, y = 0 },
		{ family = "reactor",   size = "S" },
		{ family = "utility",   size = "any" },
		{ family = "thruster",  size = "any" },
	},
	loadout = { "px2_autogun", "px2_autogun", "sparrow_rack", "flit_engine", "ember_reactor", "hold_pod_s", "aux_thrusters" },
	cargo = { rounds_s = 400, missile_s = 4 },
	price = 14000,
}

hull {
	id = "brute_anvil", name = "Anvil", maker = "Brute Industries", class = "medium", mount = "gimbal",
	mass = 240, armor = 380, turn = 3500, turnSpeed = 200, retroThrust = 600, spoolTime = 0.2, hold = 50, drag = 0.5, radius = 34,
	shape = { 74,-11, 74,11, 34,26, -46,28, -68,14, -68,-14, -46,-28, 34,-26 },
	slots = {
		{ family = "primary",   size = "M", x = 40,  y = -20 },
		{ family = "primary",   size = "M", x = 40,  y = 20 },
		{ family = "secondary", size = "M", x = 12,  y = 0 },
		{ family = "engine",    size = "M", x = -68, y = 0 },
		{ family = "reactor",   size = "M" },
		{ family = "utility",   size = "any" },
		{ family = "thruster",  size = "any" },
	},
	loadout = { "rk7_chaingun", "rk7_chaingun", "hornet_pod", "mule_engine", "kiln_reactor", "tug_beam", "aux_thrusters_m" },
	cargo = { rounds_m = 500, missile_m = 4, missile_s = 6 },
	price = 38000,
}

-- Battleship: huge, slow to turn, and every gun is on a turret, so it can
-- fight in every direction at once while the hull lumbers along. No
-- thruster slot: it can't strafe, and A/D turn the hull instead.
hull {
	id = "ferrous_bastion", name = "Bastion", maker = "Ferrous Collective", class = "heavy", mount = "turret", turretTurn = 150, helm = "turn",
	mass = 735, armor = 1070, turn = 3200, turnSpeed = 50, retroThrust = 1100, spoolTime = 0.45, hold = 120, drag = 1.6, radius = 62,
	shape = { 144,0, 108,-26, 32,-46, -68,-50, -124,-36, -136,0, -124,36, -68,50, 32,46, 108,26 },
	slots = {
		{ family = "primary",   size = "L", x = 80,  y = 0 },
		{ family = "primary",   size = "L", x = -60, y = 0 },
		{ family = "primary",   size = "M", x = 28,  y = -32 },
		{ family = "primary",   size = "M", x = 28,  y = 32 },
		{ family = "primary",   size = "M", x = -52, y = -36 },
		{ family = "primary",   size = "M", x = -52, y = 36 },
		{ family = "secondary", size = "L", x = 12,  y = 0 },
		{ family = "engine",    size = "L", x = -132, y = 0 },
		{ family = "reactor",   size = "M" },
		{ family = "utility",   size = "any" },
	},
	loadout = { "long_tom", "long_tom", "rk7_chaingun", "rk7_chaingun", "rk7_chaingun", "rk7_chaingun", "trident_bay",
		"cinder_drive", "kiln_reactor", "hold_pod_m" },
	cargo = { shell_l = 60, rounds_m = 1000, missile_l = 6, missile_m = 6 },
	price = 95000,
}

-- Enemy-only hulls.

-- Basic enemy: no side thrusters and only weak retro thrusters, so it flies
-- in straight lines and swings wide when it overshoots.
hull {
	id = "scrap_drone", name = "Scrap Drone", maker = "Nova Syndicate", class = "drone", playable = false, mount = "fixed",
	mass = 38, armor = 50, turn = 160, sideThrust = 0, retroThrust = 150, hold = 8, drag = 0.14, radius = 13,
	shape = { 30,0, -18,-11, -10,0, -18,11 },
	slots = {
		{ family = "primary", size = "S", x = 8,  y = 0 },
		{ family = "engine",  size = "S", x = -16, y = 0 },
		{ family = "reactor", size = "S" },
	},
	loadout = { "px2_autogun", "flit_engine", "ember_reactor" },
	cargo = { rounds_s = 150 },
}

-- Harasser: tiny, twitchy, strong side thrusters. Hard to hit on purpose.
hull {
	id = "nova_dart", name = "Dart", maker = "Nova Syndicate", class = "drone", playable = false, mount = "fixed",
	mass = 24, armor = 30, turn = 220, sideThrust = 320, retroThrust = 320, hold = 6, drag = 0.12, radius = 11,
	shape = { 28,0, 4,-5, -16,-10, -10,0, -16,10, 4,5 },
	slots = {
		{ family = "primary", size = "S", x = 10,  y = 0 },
		{ family = "engine",  size = "S", x = -14, y = 0 },
		{ family = "reactor", size = "S" },
	},
	loadout = { "px2_autogun", "flit_engine", "ember_reactor" },
	cargo = { rounds_s = 200 },
}
