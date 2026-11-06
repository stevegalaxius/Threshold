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
	  sideThrust  kN of built-in maneuvering thrust (strafe or turn assistance).
	  spoolTime   seconds for the main engine to reach full thrust; a slight
	              ramp-up makes heavy hulls feel heavy (default 0, instant)
	  helm   how A/D steer it: "strafe" (default) fires the side thrusters,
	         "turn" rotates the hull instead and the mouse only aims the
	         guns. Battleships use "turn": they never strafe, and the side
	         built-in jets add turning torque instead.
	  turnSpeed  optional cap on spin speed in degrees/second, so a heavy hull
	             comes about slowly even with a big engine
	  hold   cubic metres    drag    quadratic drag; top speed = sqrt(thrust*100 / drag)
	  radius optional: half the hull's width (worked out from the shape if left
	         out). Ships collide in their drawn shape; radius sets the spine,
	         distances to the hull and thruster size
	  toughness optional (default 1): crash damage is divided by it. Size is
	            already felt (a light ship's speed changes most in a crash);
	            this makes one hull sturdier (2 = half damage) or flimsier.
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

	Slots: family is hardpoint, bay, engine, reactor, utility or computer;
	size is S, M or L. Hardpoints take turret-style weapons (guns,
	artillery, lasers); bays take launchers (missiles, torpedoes, drones).
	Either kind can be in the primary, secondary or tertiary fire group
	(mouse: left, right, middle; pad: right trigger, left trigger, right
	bumper): the player sets that per slot in the loadout screen. trigger
	sets the slot's default; without one, hardpoints are primary and bays
	tertiary. Everything else takes a module of its own family. Sizes must match. Utility and computer slots are size "any": shared
	slots every class has alike. Slots with x,y are drawn on the hull
	(weapons fire from there).

	loadout lists the module id fitted to each slot, in slot order
	(false = empty). cargo is what's in the hold when you take the hull out.
]]



-- Battleship: huge, slow to turn, and every gun is on a turret, so it can
-- fight in every direction at once while the hull lumbers along. It can't
-- strafe: A/D turn the hull, and side jets help it turn.

-- Freighter: battleship-sized but boxy, nearly all cargo bay. Two medium
-- turrets to see off pirates, a big engine and low drag so it's quick in a
-- straight line, but it comes about very slowly. Flown by neutral traders.
-- Light freighter: a courier's ship. Quick in a straight line and nimble
-- enough to dodge, but fragile and with only a token gun. One small turret
-- so it can swat a lone pirate while running; the hold is the point.

-- Medium freighter: the workhorse between the Runner and the Hauler. Two
-- small turrets and a launcher for defence, a decent hold and a medium
-- engine. Slow to turn but steady.


-- Enemy-only hulls.

-- Basic enemy: no side thrusters and only weak retro thrusters, so it flies
-- in straight lines and swings wide when it overshoots.
hull {
	id = "scrap_drone", name = "Scrap Drone", maker = "Nova Syndicate", class = "drone", playable = false, mount = "fixed",
	mass = 38, armor = 50, turn = 160, sideThrust = 0, retroThrust = 150, hold = 8, drag = 0.14, radius = 13,
	mass = 38, armor = 50, turn = 160, sideThrust = 0, retroThrust = 150, hold = 8, drag = 0.14, radius = 13,
	shape = { 30,0, -18,-11, -10,0, -18,11 },
	slots = {
		{ family = "hardpoint", size = "S", x = 8,  y = 0 },
		{ family = "engine",  size = "S", x = -16, y = 0 },
		{ family = "reactor", size = "S" },
	},
	loadout = { "gun_s_base", "flit_engine", "ember_reactor" },
}

-- Harasser: tiny, twitchy, strong side thrusters. Hard to hit on purpose.
hull {
	id = "nova_dart", name = "Dart", maker = "Nova Syndicate", class = "drone", playable = false, mount = "fixed",
	mass = 24, armor = 30, turn = 220, sideThrust = 320, retroThrust = 320, hold = 6, drag = 0.12, radius = 11,
	mass = 24, armor = 30, turn = 220, sideThrust = 320, retroThrust = 320, hold = 6, drag = 0.12, radius = 11,
	shape = { 28,0, 4,-5, -16,-10, -10,0, -16,10, 4,5 },
	slots = {
		{ family = "hardpoint", size = "S", x = 10,  y = 0 },
		{ family = "engine",  size = "S", x = -14, y = 0 },
		{ family = "reactor", size = "S" },
	},
	loadout = { "gun_s_base", "flit_engine", "ember_reactor" },
}

-- Drones: launched from drone bays, fight on the launcher's side for a while.

hull {
	id = "wasp_drone", name = "Wasp", maker = "Nova Syndicate", class = "drone", playable = false, mount = "fixed",
	mass = 14, armor = 30, turn = 160, sideThrust = 260, retroThrust = 260, hold = 4, drag = 0.12, radius = 8,
	mass = 14, armor = 30, turn = 160, sideThrust = 260, retroThrust = 260, hold = 4, drag = 0.12, radius = 8,
	shape = { 22,0, 2,-4, -12,-8, -8,0, -12,8, 2,4 },
	slots = {
		{ family = "hardpoint", size = "S", x = 8,  y = 0 },
		{ family = "engine",  size = "S", x = -10, y = 0 },
		{ family = "reactor", size = "S" },
	},
	loadout = { "pulse_s_base", "flit_engine", "ember_reactor" },
}

hull {
	id = "hive_drone", name = "Hive", maker = "Nova Syndicate", class = "drone", playable = false, mount = "gimbal",
	mass = 40, armor = 80, turn = 900, sideThrust = 450, retroThrust = 450, hold = 10, drag = 0.25, radius = 14,
	mass = 40, armor = 80, turn = 900, sideThrust = 450, retroThrust = 450, hold = 10, drag = 0.25, radius = 14,
	shape = { 34,0, 6,-9, -20,-14, -14,0, -20,14, 6,9 },
	slots = {
		{ family = "hardpoint", size = "M", x = 12, y = 0 },
		{ family = "engine",  size = "M", x = -16, y = 0 },
		{ family = "reactor", size = "M" },
	},
	loadout = { "pulse_m_base", "mule_engine", "kiln_reactor" },
}

hull {
	id = "warden_drone", name = "Warden", maker = "Nova Syndicate", class = "drone", playable = false, mount = "turret", turretTurn = 200,
	mass = 90, armor = 180, turn = 2200, sideThrust = 700, retroThrust = 700, hold = 20, drag = 0.4, radius = 20,
	mass = 90, armor = 180, turn = 2200, sideThrust = 700, retroThrust = 700, hold = 20, drag = 0.4, radius = 20,
	shape = { 48,0, 20,-16, -26,-20, -36,0, -26,20, 20,16 },
	slots = {
		{ family = "hardpoint", size = "M", x = 14, y = -8 },
		{ family = "hardpoint", size = "M", x = 14, y = 8 },
		{ family = "engine",  size = "M", x = -34, y = 0 },
		{ family = "reactor", size = "L" },
	},
	loadout = { "pulse_m_base", "pulse_m_base", "mule_engine", "forge_reactor" },
}
