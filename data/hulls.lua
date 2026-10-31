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
	         guns. Battleships use "turn": they never strafe, and the side
	         jets in their thruster slot add turning torque instead.
	  turnSpeed  optional cap on spin speed in degrees/second, so a heavy hull
	             comes about slowly even with a big engine
	  hold   cubic metres    drag    quadratic drag; top speed = sqrt(thrust*100 / drag)
	  radius collision radius in pixels
	  ramSpeed  impact speed (px/s) below which a bump does it no harm;
	            low is fragile, high shrugs off collisions
	  shape  outline drawn for the ship, as x,y pairs in pixels, nose pointing +x
	  parts  instead of shape: a list of polygons, { shape = {...}, shade = 0.6,
	         tint = { r, g, b } }, drawn in order and coloured apart from the
	         hull (shade multiplies its colour, tint is added). The wreck stays
	         whole; shoot a part off and it drifts away with its share of the loot. See
	         the Hauler, and src/hullshape.lua.
	  mount  how the hull carries its weapons, which sets how each class feels:
	         fixed   guns point straight down the nose; you aim with the ship
	         gimbal  guns swing a few degrees toward the cursor (default)
	         turret  guns rotate all the way around, turretTurn degrees/second
	         A slot can override it with its own mount.

	armor is part of the hull itself, not a module.

	Slots: family is primary, secondary, auxiliary, engine, reactor,
	utility or thruster; size is S, M or L. Primary and secondary slots
	take weapons (guns, artillery, lasers) and are the two fire groups: left
	and right mouse button. The auxiliary slot takes a launcher (missiles,
	torpedoes, drones) on the middle mouse button. Everything else takes a
	module of its own family. Sizes must match. Utility and thruster slots are size "any": shared
	slots every class has alike. Slots with x,y are drawn on the hull
	(weapons fire from there).

	loadout lists the module id fitted to each slot, in slot order
	(false = empty). cargo is what's in the hold when you take the hull out.
]]

hull {
	id = "halcyon_wisp", name = "Wisp", maker = "Halcyon Arms", class = "light", mount = "fixed",
	mass = 58, armor = 120, turn = 500, retroThrust = 340, hold = 24, drag = 0.14, radius = 16,
	mass = 58, armor = 120, turn = 500, retroThrust = 340, hold = 24, drag = 0.14, radius = 16, ramSpeed = 100,
	shape = { 40,0, 8,-7, -12,-14, -28,-12, -20,0, -28,12, -12,14, 8,7 },
	slots = {
		{ family = "primary",   size = "S", x = 12,   y = -9 },
		{ family = "primary",   size = "S", x = 12,   y = 9 },
		{ family = "auxiliary", size = "S", x = -4,  y = 0 },
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
	mass = 240, armor = 380, turn = 3500, turnSpeed = 200, retroThrust = 600, spoolTime = 0.2, hold = 50, drag = 0.5, radius = 34, ramSpeed = 170,
	shape = { 74,-11, 74,11, 34,26, -46,28, -68,14, -68,-14, -46,-28, 34,-26 },
	slots = {
		{ family = "primary",   size = "M", x = 40,  y = -20 },
		{ family = "primary",   size = "M", x = 40,  y = 20 },
		{ family = "secondary", size = "M", x = 60,  y = 0 },
		{ family = "auxiliary", size = "M", x = 12,  y = 0 },
		{ family = "engine",    size = "M", x = -68, y = 0 },
		{ family = "reactor",   size = "M" },
		{ family = "utility",   size = "any" },
		{ family = "thruster",  size = "any" },
	},
	loadout = { "rk7_autocannon", "rk7_autocannon", "thumper_m", "hornet_pod", "mule_engine", "kiln_reactor", "tug_beam", "aux_thrusters_m" },
	cargo = { rounds_m = 500, shell_m = 20, missile_m = 4, missile_s = 6 },
	price = 38000,
}

-- Battleship: huge, slow to turn, and every gun is on a turret, so it can
-- fight in every direction at once while the hull lumbers along. It can't
-- strafe: A/D turn the hull, and side jets help it turn.
hull {
	id = "ferrous_bastion", name = "Bastion", maker = "Concord Military", class = "heavy", mount = "turret", turretTurn = 150, helm = "turn",
	mass = 735, armor = 1070, turn = 3200, turnSpeed = 50, retroThrust = 1100, spoolTime = 0.45, hold = 120, drag = 1.6, radius = 62, ramSpeed = 250,
	shape = { 144,0, 108,-26, 32,-46, -68,-50, -124,-36, -136,0, -124,36, -68,50, 32,46, 108,26 },
	slots = {
		{ family = "secondary", size = "L", x = 80,  y = 0 },
		{ family = "secondary", size = "L", x = -60, y = 0 },
		{ family = "primary",   size = "M", x = 28,  y = -32 },
		{ family = "primary",   size = "M", x = 28,  y = 32 },
		{ family = "primary",   size = "M", x = -52, y = -36 },
		{ family = "primary",   size = "M", x = -52, y = 36 },
		{ family = "auxiliary", size = "L", x = 12,  y = 0 },
		{ family = "engine",    size = "L", x = -132, y = 0 },
		{ family = "reactor",   size = "M" },
		{ family = "utility",   size = "any" },
		{ family = "thruster",  size = "any" },
	},
	loadout = { "long_tom", "long_tom", "rk7_autocannon", "rk7_autocannon", "rk7_autocannon", "rk7_autocannon", "trident_bay",
		"cinder_drive", "kiln_reactor", "hold_pod_m", "aux_thrusters_m" },
	cargo = { shell_l = 60, rounds_m = 1000, missile_l = 6, missile_m = 6 },
	price = 95000,
}

-- Freighter: battleship-sized but boxy, nearly all cargo bay. Two medium
-- turrets to see off pirates, a big engine and low drag so it's quick in a
-- straight line, but it comes about very slowly. Flown by neutral traders.
hull {
	id = "ferrous_freighter", name = "Hauler", maker = "Ferrous Collective", class = "heavy", mount = "turret", turretTurn = 120, helm = "turn",
	mass = 900, armor = 900, turn = 3600, turnSpeed = 40, retroThrust = 800, spoolTime = 0.6, hold = 400, drag = 1.1, radius = 62,
	mass = 900, armor = 900, turn = 3600, turnSpeed = 40, retroThrust = 800, spoolTime = 0.6, hold = 400, drag = 1.1, radius = 62, ramSpeed = 200,
	-- built in parts: they're tinted apart, and break off separately when
	-- it dies (src/hullshape.lua)
	parts = {
		{ shape = { 100,-48, 100,48, -96,48, -96,-48 } },                                   -- cargo spine
		{ shape = { 92,-60, 92,-36, -88,-36, -88,-60 }, tint = { 0.12, 0.06, -0.12 } },    -- port container rack
		{ shape = { 92,36, 92,60, -88,60, -88,36 }, tint = { 0.12, 0.06, -0.12 } },        -- starboard container rack
		{ shape = { 138,-30, 128,-44, 100,-44, 100,44, 128,44, 138,30 }, shade = 1.15 },   -- bridge
		{ shape = { -96,-44, -96,44, -128,52, -140,40, -140,-40, -128,-52 }, shade = 0.6 }, -- engine block
	},
	slots = {
		{ family = "primary",   size = "M", x = 70,  y = 0 },
		{ family = "primary",   size = "M", x = -70, y = 0 },
		{ family = "engine",    size = "L", x = -136, y = 0 },
		{ family = "reactor",   size = "M" },
		{ family = "utility",   size = "any" },
		{ family = "utility",   size = "any" },
		{ family = "thruster",  size = "any" },
	},
	loadout = { "rk7_autocannon", "rk7_autocannon", "cinder_drive", "kiln_reactor", "hold_pod_m", "hold_pod_m", "aux_thrusters_m" },
	cargo = { rounds_m = 600 },
	price = 70000,
}
-- Light freighter: a courier's ship. Quick in a straight line and nimble
-- enough to dodge, but fragile and with only a token gun. One small turret
-- so it can swat a lone pirate while running; the hold is the point.
hull {
	id = "ferrous_runner", name = "Runner", maker = "Ferrous Collective", class = "light", mount = "turret", turretTurn = 180,
	mass = 120, armor = 160, turn = 900, turnSpeed = 160, retroThrust = 400, spoolTime = 0.15, hold = 90, drag = 0.22, radius = 24,
	mass = 120, armor = 160, turn = 900, turnSpeed = 160, retroThrust = 400, spoolTime = 0.15, hold = 90, drag = 0.22, radius = 24, ramSpeed = 110,
	shape = { 58,-8, 52,-20, -34,-22, -46,-14, -46,14, -34,22, 52,20, 58,8 },
	slots = {
		{ family = "primary",   size = "S", x = 30,  y = 0 },
		{ family = "engine",    size = "S", x = -44, y = 0 },
		{ family = "reactor",   size = "S" },
		{ family = "utility",   size = "any" },
		{ family = "thruster",  size = "any" },
	},
	loadout = { "px2_autogun", "flit_engine", "ember_reactor", "hold_pod_s", "aux_thrusters" },
	cargo = { rounds_s = 300 },
	price = 22000,
}

-- Medium freighter: the workhorse between the Runner and the Hauler. Two
-- small turrets and a launcher for defence, a decent hold and a medium
-- engine. Slow to turn but steady.
hull {
	id = "ferrous_mule", name = "Packhorse", maker = "Ferrous Collective", class = "medium", mount = "turret", turretTurn = 140,
	mass = 420, armor = 520, turn = 2400, turnSpeed = 90, retroThrust = 650, spoolTime = 0.35, hold = 200, drag = 0.6, radius = 44,
	mass = 420, armor = 520, turn = 2400, turnSpeed = 90, retroThrust = 650, spoolTime = 0.35, hold = 200, drag = 0.6, radius = 44, ramSpeed = 180,
	shape = { 96,-24, 88,-40, -78,-42, -92,-30, -92,30, -78,42, 88,40, 96,24 },
	slots = {
		{ family = "primary",   size = "M", x = 44,  y = -18 },
		{ family = "primary",   size = "M", x = 44,  y = 18 },
		{ family = "auxiliary", size = "M", x = 0,   y = 0 },
		{ family = "engine",    size = "M", x = -90, y = 0 },
		{ family = "reactor",   size = "M" },
		{ family = "utility",   size = "any" },
		{ family = "utility",   size = "any" },
		{ family = "thruster",  size = "any" },
	},
	loadout = { "rk7_autocannon", "rk7_autocannon", "hornet_pod", "mule_engine", "kiln_reactor", "hold_pod_m", "hold_pod_s", "aux_thrusters_m" },
	cargo = { rounds_m = 400, missile_m = 4 },
	price = 48000,
}


-- Enemy-only hulls.

-- Basic enemy: no side thrusters and only weak retro thrusters, so it flies
-- in straight lines and swings wide when it overshoots.
hull {
	id = "scrap_drone", name = "Scrap Drone", maker = "Nova Syndicate", class = "drone", playable = false, mount = "fixed",
	mass = 38, armor = 50, turn = 160, sideThrust = 0, retroThrust = 150, hold = 8, drag = 0.14, radius = 13,
	mass = 38, armor = 50, turn = 160, sideThrust = 0, retroThrust = 150, hold = 8, drag = 0.14, radius = 13, ramSpeed = 100,
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
	mass = 24, armor = 30, turn = 220, sideThrust = 320, retroThrust = 320, hold = 6, drag = 0.12, radius = 11, ramSpeed = 90,
	shape = { 28,0, 4,-5, -16,-10, -10,0, -16,10, 4,5 },
	slots = {
		{ family = "primary", size = "S", x = 10,  y = 0 },
		{ family = "engine",  size = "S", x = -14, y = 0 },
		{ family = "reactor", size = "S" },
	},
	loadout = { "px2_autogun", "flit_engine", "ember_reactor" },
	cargo = { rounds_s = 200 },
}

-- Drones: launched from drone bays, fight on the launcher's side for a while.

hull {
	id = "wasp_drone", name = "Wasp", maker = "Nova Syndicate", class = "drone", playable = false, mount = "fixed",
	mass = 14, armor = 30, turn = 160, sideThrust = 260, retroThrust = 260, hold = 4, drag = 0.12, radius = 8,
	mass = 14, armor = 30, turn = 160, sideThrust = 260, retroThrust = 260, hold = 4, drag = 0.12, radius = 8, ramSpeed = 80,
	shape = { 22,0, 2,-4, -12,-8, -8,0, -12,8, 2,4 },
	slots = {
		{ family = "primary", size = "S", x = 8,  y = 0 },
		{ family = "engine",  size = "S", x = -10, y = 0 },
		{ family = "reactor", size = "S" },
	},
	loadout = { "px2_autogun", "flit_engine", "ember_reactor" },
	cargo = {},
}

hull {
	id = "hive_drone", name = "Hive", maker = "Nova Syndicate", class = "drone", playable = false, mount = "gimbal",
	mass = 40, armor = 80, turn = 900, sideThrust = 450, retroThrust = 450, hold = 10, drag = 0.25, radius = 14,
	mass = 40, armor = 80, turn = 900, sideThrust = 450, retroThrust = 450, hold = 10, drag = 0.25, radius = 14, ramSpeed = 100,
	shape = { 34,0, 6,-9, -20,-14, -14,0, -20,14, 6,9 },
	slots = {
		{ family = "primary", size = "M", x = 12, y = 0 },
		{ family = "engine",  size = "M", x = -16, y = 0 },
		{ family = "reactor", size = "M" },
	},
	loadout = { "rk7_autocannon", "mule_engine", "kiln_reactor" },
	cargo = {},
}

hull {
	id = "warden_drone", name = "Warden", maker = "Nova Syndicate", class = "drone", playable = false, mount = "turret", turretTurn = 200,
	mass = 90, armor = 180, turn = 2200, sideThrust = 700, retroThrust = 700, hold = 20, drag = 0.4, radius = 20,
	mass = 90, armor = 180, turn = 2200, sideThrust = 700, retroThrust = 700, hold = 20, drag = 0.4, radius = 20, ramSpeed = 150,
	shape = { 48,0, 20,-16, -26,-20, -36,0, -26,20, 20,16 },
	slots = {
		{ family = "primary", size = "M", x = 14, y = -8 },
		{ family = "primary", size = "M", x = 14, y = 8 },
		{ family = "engine",  size = "M", x = -34, y = 0 },
		{ family = "reactor", size = "M" },
	},
	loadout = { "rk7_autocannon", "rk7_autocannon", "mule_engine", "kiln_reactor" },
	cargo = {},
}
