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

-- The hulls themselves live one per file in data/ships/<id>.lua, the same
-- file the Shipyard (F2) exports to mods/shipyard/data/<id>.lua: to update a
-- ship, export it and copy the file over its namesake here; to add one, copy
-- a new export in. Subfolders of data/ships load too.
