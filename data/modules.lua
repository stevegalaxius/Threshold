--[[
	Modules: fixed catalog items, never randomly rolled. Each has a family
	and size (it only fits a matching slot), a mass, and an optional
	powerDraw that is taken out of the reactor's output all the time.

	Stat fields by family:
	  engine   thrust (kN), turn, exhaust (visual settings; see Engines below)
	  reactor  powerOut (per second), powerCap (stored power)
	  computer universal (size "any"), one per hull. computer = "nav",
	           "ordnance", "guidance" (radarRange px) or "drone" (uplinkRange
	           px); see src/computers.lua.
	  utility  hold (cubic metres), tractorRange (pixels), tractorPower (tractor strength added to the basic beam's 1: looting pull and top towing speed). Several stack. Utility modules are
	           size "any" and fit any hull's utility slot.
	  weapon   (guns, artillery, lasers) fits a hull's hardpoint slot.
	  bay      (missile, torpedo and drone launchers) fits a bay slot.
	           Either fires on whichever trigger its slot is set to.

	Weapon fields:
	  kind        gun, artillery, laser or drill (weapon family); missile, torpedo
	              or drone (bay family). Each fires ammo of its own
	              kind: guns and artillery in their exact caliber, bay
	              launchers their size or smaller. The ammo sets damage,
	              speed, range, splash and knockback (data/items.lua). Lasers are pulse lasers
	              with no ammo: they carry damage (per pulse), range,
	              pulse (seconds the flash shows) and
	              powerPerShot themselves.
	              beam = true makes it a beam laser instead: it burns while
	              the trigger is held, with damage and powerPerSecond per second.
	  control     drone bays: how many drones it flies at once, counted by
	              size (S drone 1, M 2, L 4). S bay 1, M bay 2, L bay 4.
	  fireRate    shots per second           spread    random spread in degrees
	  caliber     ammo size a gun fires, if not its own (twin mounts)
	  barrels     barrels that take turns firing; barrelGap = spacing
	  gimbal      degrees it can aim off the nose
	  recoilPct   guns and artillery: push back on the shooter, as a
	              percentage of the round's knockback
	  recoil      launchers: push back on the shooter (a fixed impulse)
]]

-- Weapons: guns (fast, short range, no splash) --------------------------------

module {
	id = "gun_S_base", name = "PX-2 Autogun",
	family = "weapon",
	maker = "Halcyon Arms",
	mass = 4,
	powerDraw = 1,
	price = 2200,
	size = "S",
	weapon = { fireRate = 5, gimbal = 10, kind = "gun", recoilPct = 16, spread = 0.8 },
	art = {
		muzzles = {
			{ 12, 0 },
		},
		parts = {
			{ name = "part 2", shape = { 3, -1, 12, -1, 12, 1, 3, 1 }, barrel = true },
			{ name = "part 1", shape = { -5.5, -1.5, 8, -1.5, 8, 1.5, -5.5, 1.5 } },
		},
	},
}

module {
	id = "gun_M_base", name = "RK-7 Autocannon",
	family = "weapon",
	maker = "Brute Industries",
	mass = 10,
	powerDraw = 2,
	price = 6500,
	size = "M",
	weapon = { fireRate = 4, gimbal = 10, kind = "gun", recoilPct = 50.5, spread = 1 },
	art = {
		muzzles = {
			{ 22, 0 },
		},
		parts = {
			{ name = "part 1", shape = { -2.5, -1.5, 22, -1.5, 22, 1.5, -2.5, 1.5 }, barrel = true },
			{ name = "part 2", shape = { -9.5, -2.5, 16, -2.5, 16, 2.5, -9.5, 2.5 }, paint = "primary" },
		},
	},
}

-- Two RK-7 actions on one large mount, firing the same heavy rounds. The
-- barrels alternate, so it's two autocannons' worth of fire from one slot.
module {
	id = "gun_L_base", name = "RK-14 Twin Autocannon",
	family = "weapon",
	maker = "Brute Industries",
	mass = 24,
	powerDraw = 4,
	price = 15000,
	size = "L",
	weapon = {
		barrelGap = 10,
		barrels = 2,
		caliber = "M",
		fireRate = 8,
		gimbal = 10,
		kind = "gun",
		recoilPct = 17.5,
		spread = 1,
	},
	art = {
		muzzles = {
			{ 22.5, -4.5 },
			{ 22.5, 4.5 },
		},
		parts = {
			{ name = "part 2", shape = { 0.5, -6, 22.5, -6, 22.5, -3, 0.5, -3 }, mirror = true },
			{ name = "part 1", shape = { -11, -7, 16, -7, 16, -2, -11, -2 }, mirror = true },
		},
	},
}

-- Weapons: artillery (slow, long range, high damage, splash) -----------------
-- Shells fly their full range and burst on contact, near an enemy, or at the end of their range.

module {
	id = "artillery_S_base", name = "Pip Mortar",
	family = "weapon",
	maker = "Ferrous Collective",
	mass = 6,
	powerDraw = 1,
	price = 3400,
	size = "S",
	weapon = { fireRate = 1.2, gimbal = 6, kind = "artillery", recoilPct = 100, spread = 1 },
	art = {
		muzzles = {
			{ 19, 0 },
		},
		parts = {
			{ name = "part 2", shape = { 4, -0.5, 19, -0.5, 19, 0.5, 4, 0.5 } },
			{ name = "part 1", shape = { -8, -1.5, 6, -1.5, 6, 1.5, -8, 1.5 } },
		},
	},
}

module {
	id = "artillery_M_base", name = "Thumper",
	family = "weapon",
	maker = "Brute Industries",
	mass = 16,
	powerDraw = 2,
	price = 9000,
	size = "M",
	weapon = { fireRate = 0.8, gimbal = 6, kind = "artillery", recoilPct = 100, spread = 1 },
	art = {
		muzzles = {
			{ 28, 0 },
		},
		parts = {
			{ name = "part 2", shape = { 0, -1, 28, -1, 28, 1, 0, 1 } },
			{ name = "part 1", shape = { -16, -2, 8, -2, 8, 2, -16, 2 } },
		},
	},
}

module {
	id = "artillery_L_base", name = "Long Tom",
	family = "weapon",
	maker = "Ferrous Collective",
	mass = 34,
	powerDraw = 3,
	price = 24000,
	size = "L",
	weapon = { fireRate = 0.5, gimbal = 5, kind = "artillery", recoilPct = 100, spread = 0.5 },
	art = {
		muzzles = {
			{ 52, 0 },
		},
		parts = {
			{ name = "part 2", shape = { 0, -1.5, 52, -1.5, 52, 1.5, 0, 1.5 }, barrel = true },
			{ name = "part 1", shape = { -28, -4, 12, -4, 12, 4, -28, 4 } },
		},
	},
}

-- Weapons: pulse lasers (no ammo, a chunk of power per pulse) -----------------

module {
	id = "glint_laser", name = "Glint Laser", maker = "Halcyon Arms", family = "weapon", size = "S",
	mass = 5, price = 5200,
	weapon = { kind = "laser", fireRate = 1.6, damage = 30, powerPerShot = 20, pulse = 0.12, range = 3500, gimbal = 12 },
}

module {
	id = "lumen_lance", name = "Lumen Lance", maker = "Nova Syndicate", family = "weapon", size = "M",
	mass = 12, price = 14000,
	weapon = { kind = "laser", fireRate = 1.4, damage = 65, powerPerShot = 45, pulse = 0.14, range = 4200, gimbal = 12 },
}

module {
	id = "sunder_beam", name = "Sunder Beam", maker = "Nova Syndicate", family = "weapon", size = "L",
	mass = 30, price = 38000,
	weapon = { kind = "laser", fireRate = 1.0, damage = 160, powerPerShot = 90, pulse = 0.2, range = 5200, gimbal = 10 },
}

-- Mining drills: hold the trigger and the drill extends out of the nose,
-- up to the ship's own length, and grinds whatever its tip touches. No
-- ammo and little power. damage is per second; rockDamage multiplies it
-- against asteroids, and drilled rock drops ore when it breaks.
module {
	id = "bore_drill", name = "Bore Drill", maker = "Ferrous Collective", family = "weapon", size = "S",
	mass = 6, price = 3500,
	weapon = { kind = "drill", damage = 12, rockDamage = 12, powerPerSecond = 4, extendTime = 0.35 },
}

module {
	id = "rockbiter", name = "Rockbiter", maker = "Ferrous Collective", family = "weapon", size = "M",
	mass = 14, price = 9000,
	weapon = { kind = "drill", damage = 25, rockDamage = 14, powerPerSecond = 8, extendTime = 0.45 },
}

module {
	id = "deep_core_drill", name = "Deep Core Drill", maker = "Brute Industries", family = "weapon", size = "L",
	mass = 34, price = 24000,
	weapon = { kind = "drill", damage = 50, rockDamage = 16, powerPerSecond = 15, extendTime = 0.6 },
}

-- Beam lasers: a continuous beam while the trigger is held. damage and
-- powerPerSecond are per second; easier to keep on target than a pulse
-- laser, so a little less damage for the power.
module {
	id = "thread_beam", name = "Thread Beam", maker = "Halcyon Arms", family = "weapon", size = "S",
	mass = 6, price = 6000,
	weapon = { kind = "laser", beam = true, damage = 40, powerPerSecond = 30, range = 3000, gimbal = 12 },
}

module {
	id = "searing_ray", name = "Searing Ray", maker = "Nova Syndicate", family = "weapon", size = "M",
	mass = 14, price = 16000,
	weapon = { kind = "laser", beam = true, damage = 85, powerPerSecond = 60, range = 3600, gimbal = 12 },
}

module {
	id = "furnace_beam", name = "Furnace Beam", maker = "Halcyon Arms", family = "weapon", size = "L",
	mass = 32, price = 42000,
	weapon = { kind = "laser", beam = true, damage = 150, powerPerSecond = 100, range = 4400, gimbal = 10 },
}

-- Bay launchers -------------------------------------------------------------------
-- Missiles (fire and forget), torpedoes (very fast, steer slowly, huge damage) and drone bays (launch
-- an armed drone that fights for you for a while). Each fires its own kind
-- in its size or smaller; Q switches the size.

module {
	id = "missile_S_base", name = "Sparrow Rack",
	family = "bay",
	maker = "Halcyon Arms",
	mass = 3,
	price = 4000,
	size = "S",
	weapon = { fireRate = 3, kind = "missile", recoil = 300 },
	art = {
		parts = {
			{ name = "part 1", shape = { -4, 4, -4, -4, 6, -4, 8, -3, 8, 3, 6, 4 }, paint = "primary" },
			{ name = "part 2", shape = { 5, -1, 8, -1, 8, 1, 5, 1 } },
		},
	},
}

module {
	id = "missile_M_base", name = "Hornet Pod",
	family = "bay",
	maker = "Nova Syndicate",
	mass = 8,
	price = 11000,
	size = "M",
	weapon = { fireRate = 2.5, kind = "missile", recoil = 800 },
	art = {
		parts = {
			{ name = "part 1", shape = { -6, 6, -6, -6, 8, -6, 12, -3, 12, 3, 8, 6 }, paint = "primary" },
			{ name = "part 2", shape = { 5, -2, 12, -2, 12, 2, 5, 2 }, barrel = true },
		},
	},
}

module {
	id = "missile_L_base", name = "Trident Bay",
	family = "bay",
	maker = "Ferrous Collective",
	mass = 18,
	price = 26000,
	size = "L",
	weapon = { fireRate = 1.5, kind = "missile", recoil = 1600 },
	art = {
		parts = {
			{ name = "part 1", shape = { -9, -9, -9, 9, 10, 9, 16, 4, 16, -4, 10, -9 }, paint = "primary" },
			{ name = "part 2", shape = { 5, -4, 16, -4, 16, 4, 5, 4 }, barrel = true },
		},
	},
}

module {
	id = "maul_tube", name = "Maul Tube", maker = "Brute Industries", family = "bay", size = "S",
	mass = 5, price = 5000,
	weapon = { kind = "torpedo", fireRate = 0.5, recoil = 600 },
}

module {
	id = "breaker_tube", name = "Breaker Tube", maker = "Brute Industries", family = "bay", size = "M",
	mass = 12, price = 14000,
	weapon = { kind = "torpedo", fireRate = 0.35, recoil = 1500 },
}

module {
	id = "leviathan_tube", name = "Leviathan Tube", maker = "Ferrous Collective", family = "bay", size = "L",
	mass = 26, price = 32000,
	weapon = { kind = "torpedo", fireRate = 0.25, recoil = 4000 },
}

module {
	id = "wasp_bay", name = "Wasp Bay", maker = "Nova Syndicate", family = "bay", size = "S",
	mass = 6, price = 7000,
	weapon = { kind = "drone", fireRate = 0.4, recoil = 100, control = 1 },
}

module {
	id = "hive_bay", name = "Hive Bay", maker = "Nova Syndicate", family = "bay", size = "M",
	mass = 14, price = 18000,
	weapon = { kind = "drone", fireRate = 0.3, recoil = 200, control = 2 },
}

module {
	id = "carrier_deck", name = "Carrier Deck", maker = "Nova Syndicate", family = "bay", size = "L",
	mass = 30, price = 40000,
	weapon = { kind = "drone", fireRate = 0.2, recoil = 400, control = 4 },
}

-- Engines -----------------------------------------------------------------------

-- Exhaust dimensions are in ship-local pixels; colors are RGB in 0..1.
-- width: nozzle half-width; length: full-throttle plume length.
-- afterburnScale multiplies length while boosting; flicker is fractional jitter.
-- damage is exhaust damage per second at full throttle (zero disables it).
module { id = "flit_engine", name = "Flit Engine", maker = "Halcyon Arms", family = "engine", size = "S",
 mass = 6, powerDraw = 2, thrust = 420, turn = 250, price = 3000,
 exhaust = { width = 5, length = 30, color = {1,.6,.25}, coreColor = {1,.92,.65},
  glowColor = {1,.35,.08}, afterburnScale = 2.2, flicker = .15, damage = 30 } }
module { id = "mule_engine", name = "Mule Engine", maker = "Brute Industries", family = "engine", size = "M",
 mass = 16, powerDraw = 4, thrust = 900, turn = 800, price = 9000,
 exhaust = { width = 10, length = 45, color = {1,.55,.18}, coreColor = {1,.9,.6},
  glowColor = {1,.3,.06}, afterburnScale = 2.2, flicker = .12, damage = 50 } }
module { id = "cinder_drive", name = "Cinder Drive", maker = "Nova Syndicate", family = "engine", size = "L",
 mass = 40, powerDraw = 8, thrust = 2000, turn = 2500, price = 26000,
 exhaust = { width = 20, length = 60, color = {1,.45,.12}, coreColor = {1,.85,.5},
  glowColor = {1,.22,.04}, afterburnScale = 2.5, flicker = .18, damage = 80 } }

-- Reactors ----------------------------------------------------------------------

module { id = "ember_reactor", name = "Ember Reactor", maker = "Halcyon Arms",       family = "reactor", size = "S", mass = 5,  powerOut = 20, powerCap = 60,  price = 2500 }
module { id = "kiln_reactor",  name = "Kiln Reactor",  maker = "Ferrous Collective", family = "reactor", size = "M", mass = 14, powerOut = 40, powerCap = 140, price = 8000 }
module { id = "forge_reactor", name = "Forge Reactor", maker = "Estates Military",   family = "reactor", size = "L", mass = 32, powerOut = 75, powerCap = 280, price = 21000 }


-- Utility -----------------------------------------------------------------------

module { id = "hold_pod_s", name = "Cargo Pod",     maker = "Ferrous Collective", family = "utility", size = "any", mass = 2, hold = 16, price = 1200 }
module { id = "flare_pod",  name = "Flare Pod",     maker = "Estates Military",   family = "utility", size = "any", mass = 2, powerDraw = 1, flares = true, price = 3000 }
module { id = "tug_beam",   name = "Tug Beam",      maker = "Halcyon Arms",       family = "utility", size = "any", mass = 3, powerDraw = 2, tractorRange = 220, tractorPower = 1, price = 3500 }

-- Computers (src/computers.lua). Ranges are world pixels:
-- nav: radarRange, lookahead (seconds of collision prediction).
-- ordnance: radarRange, predictionTime (maximum projectile flight time for a lead solution).
-- guidance: radarRange, lockCone (half-angle in degrees; retention uses 1.5x).
-- scanner: radarRange (how far it reads what's inside wrecks and containers).
-- drone: uplinkRange, controlLimit (largest drone control cost for direct piloting:
-- S=1, M=2, L=4; does not replace the launching bay's capacity).
module { id = "nav_computer",  name = "Nav Computer",      maker = "Halcyon Arms",       family = "computer", size = "any", mass = 1, powerDraw = 1, computer = "nav", radarRange = 12000, lookahead = 2, price = 2500 }
module { id = "fire_computer", name = "Ordnance Computer", maker = "Estates Military",   family = "computer", size = "any", mass = 1, powerDraw = 2, computer = "ordnance", radarRange = 6000, predictionTime = 4, price = 6000 }
module { id = "guidance_computer", name = "Missile Guidance", maker = "Estates Military", family = "computer", size = "any", mass = 2, powerDraw = 2, computer = "guidance", radarRange = 4000, lockCone = 25, price = 7000 }
module { id = "scanner",       name = "Deep Scanner",      maker = "Halcyon Arms",       family = "computer", size = "any", mass = 1, powerDraw = 2, computer = "scanner", radarRange = 3000, price = 4500 }
module { id = "drone_uplink",  name = "Drone Uplink",      maker = "Nova Syndicate",     family = "computer", size = "any", mass = 3, powerDraw = 3, computer = "drone", uplinkRange = 4000, controlLimit = 4, price = 9000 }
