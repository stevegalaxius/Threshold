--[[
	Modules: fixed catalog items, never randomly rolled. Each has a family
	and size (it only fits a matching slot), a mass, and an optional
	powerDraw that is taken out of the reactor's output all the time.

	Stat fields by family:
	  engine   thrust (kN), turn
	  thruster sideThrust (kN) for maneuvering thrusters: the only way a ship
	           can strafe. Thruster slots are size "any", shared by every
	           hull that has one, and battleships have none.
	  reactor  powerOut (per second), powerCap (stored power)
	  computer universal (size "any"), one per hull. computer = "nav",
	           "ordnance" or "radar" (radarRange px); see src/computers.lua.
	  utility  hold (cubic metres), tractorRange (pixels). Utility modules are
	           size "any" and fit any hull's utility slot.
	  weapon   (guns, artillery, lasers) fits a hull's primary or secondary
	           slot; which one decides the mouse button that fires it.
	  auxiliary (missile, torpedo and drone launchers) fits the auxiliary
	           slot and fires on the middle mouse button.

	Weapon fields:
	  kind        gun, artillery or laser (weapon family); missile, torpedo
	              or drone (auxiliary family). Each fires ammo of its own
	              kind: guns and artillery in their exact caliber, auxiliary
	              launchers their size or smaller. The ammo sets damage,
	              speed, range, splash and knockback (data/items.lua). Lasers are pulse lasers
	              with no ammo: they carry damage (per pulse), range,
	              knockback, pulse (seconds the flash shows) and
	              powerPerShot themselves.
	  fireRate    shots per second           spread    random spread in degrees
	  caliber     ammo size a gun fires, if not its own (twin mounts)
	  barrels     barrels that take turns firing; barrelGap = spacing
	  gimbal      degrees it can aim off the nose
	  recoil      push back on the shooter
]]

-- Weapons: guns (fast, short range, no splash) --------------------------------

module {
	id = "px2_autogun", name = "PX-2 Autogun", maker = "Halcyon Arms", family = "weapon", size = "S",
	mass = 4, powerDraw = 1, price = 2200,
	weapon = { kind = "gun", fireRate = 150 / 60, spread = 2, gimbal = 10, recoil = 40 },
}

module {
	id = "rk7_autocannon", name = "RK-7 Autocannon", maker = "Brute Industries", family = "weapon", size = "M",
	mass = 10, powerDraw = 2, price = 6500,
	weapon = { kind = "gun", fireRate = 150 / 60, spread = 2.5, gimbal = 10, recoil = 70 },
}

-- Two RK-7 actions on one large mount, firing the same heavy rounds. The
-- barrels alternate, so it's two autocannons' worth of fire from one slot.
module {
	id = "rk14_twin", name = "RK-14 Twin Autocannon", maker = "Brute Industries", family = "weapon", size = "L",
	mass = 24, powerDraw = 4, price = 15000,
	weapon = { kind = "gun", caliber = "M", barrels = 2, barrelGap = 10, fireRate = 300 / 60, spread = 2.5, gimbal = 10, recoil = 70 },
}

-- Weapons: artillery (slow, long range, high damage, splash) -----------------
-- Shells fly their full range and burst on contact, near an enemy, or at the end of their range.

module {
	id = "pip_mortar", name = "Pip Mortar", maker = "Ferrous Collective", family = "weapon", size = "S",
	mass = 6, powerDraw = 1, price = 3400,
	weapon = { kind = "artillery", fireRate = 1.2, spread = 1, gimbal = 6, recoil = 1500 },
}

module {
	id = "thumper_m", name = "Thumper", maker = "Brute Industries", family = "weapon", size = "M",
	mass = 16, powerDraw = 2, price = 9000,
	weapon = { kind = "artillery", fireRate = 0.8, spread = 1, gimbal = 6, recoil = 4000 },
}

module {
	id = "long_tom", name = "Long Tom", maker = "Ferrous Collective", family = "weapon", size = "L",
	mass = 34, powerDraw = 3, price = 24000,
	weapon = { kind = "artillery", fireRate = 0.5, spread = 0.5, gimbal = 5, recoil = 12000 },
}

-- Weapons: pulse lasers (no ammo, a chunk of power per pulse) -----------------

module {
	id = "glint_laser", name = "Glint Laser", maker = "Halcyon Arms", family = "weapon", size = "S",
	mass = 5, price = 5200,
	weapon = { kind = "laser", fireRate = 1.6, damage = 30, powerPerShot = 20, pulse = 0.12, range = 1400, gimbal = 12, knockback = 1500 },
}

module {
	id = "lumen_lance", name = "Lumen Lance", maker = "Nova Syndicate", family = "weapon", size = "M",
	mass = 12, price = 14000,
	weapon = { kind = "laser", fireRate = 1.4, damage = 65, powerPerShot = 45, pulse = 0.14, range = 1700, gimbal = 12, knockback = 3000 },
}

module {
	id = "sunder_beam", name = "Sunder Beam", maker = "Nova Syndicate", family = "weapon", size = "L",
	mass = 30, price = 38000,
	weapon = { kind = "laser", fireRate = 1.0, damage = 160, powerPerShot = 90, pulse = 0.2, range = 2100, gimbal = 10, knockback = 8000 },
}

-- Auxiliary launchers -------------------------------------------------------------
-- Missiles (guided), torpedoes (unguided, huge damage) and drone bays (launch
-- an armed drone that fights for you for a while). Each fires its own kind
-- in its size or smaller; Q switches the size.

module {
	id = "sparrow_rack", name = "Sparrow Rack", maker = "Halcyon Arms", family = "auxiliary", size = "S",
	mass = 3, price = 4000,
	weapon = { kind = "missile", fireRate = 1.5, recoil = 300 },
}

module {
	id = "hornet_pod", name = "Hornet Pod", maker = "Nova Syndicate", family = "auxiliary", size = "M",
	mass = 8, price = 11000,
	weapon = { kind = "missile", fireRate = 1.0, recoil = 800 },
}

module {
	id = "trident_bay", name = "Trident Bay", maker = "Ferrous Collective", family = "auxiliary", size = "L",
	mass = 18, price = 26000,
	weapon = { kind = "missile", fireRate = 0.7, recoil = 1600 },
}

module {
	id = "maul_tube", name = "Maul Tube", maker = "Brute Industries", family = "auxiliary", size = "S",
	mass = 5, price = 5000,
	weapon = { kind = "torpedo", fireRate = 0.5, recoil = 600 },
}

module {
	id = "breaker_tube", name = "Breaker Tube", maker = "Brute Industries", family = "auxiliary", size = "M",
	mass = 12, price = 14000,
	weapon = { kind = "torpedo", fireRate = 0.35, recoil = 1500 },
}

module {
	id = "leviathan_tube", name = "Leviathan Tube", maker = "Ferrous Collective", family = "auxiliary", size = "L",
	mass = 26, price = 32000,
	weapon = { kind = "torpedo", fireRate = 0.25, recoil = 4000 },
}

module {
	id = "wasp_bay", name = "Wasp Bay", maker = "Nova Syndicate", family = "auxiliary", size = "S",
	mass = 6, price = 7000,
	weapon = { kind = "drone", fireRate = 0.4, recoil = 100 },
}

module {
	id = "hive_bay", name = "Hive Bay", maker = "Nova Syndicate", family = "auxiliary", size = "M",
	mass = 14, price = 18000,
	weapon = { kind = "drone", fireRate = 0.3, recoil = 200 },
}

module {
	id = "carrier_deck", name = "Carrier Deck", maker = "Nova Syndicate", family = "auxiliary", size = "L",
	mass = 30, price = 40000,
	weapon = { kind = "drone", fireRate = 0.2, recoil = 400 },
}

-- Engines -----------------------------------------------------------------------

module { id = "flit_engine",  name = "Flit Engine",  maker = "Halcyon Arms",       family = "engine", size = "S", mass = 6,  powerDraw = 2, thrust = 420,  turn = 250, price = 3000 }
module { id = "mule_engine",  name = "Mule Engine",  maker = "Brute Industries",   family = "engine", size = "M", mass = 16, powerDraw = 4, thrust = 900,  turn = 800, price = 9000 }
module { id = "cinder_drive", name = "Cinder Drive", maker = "Nova Syndicate",     family = "engine", size = "L", mass = 40, powerDraw = 8, thrust = 2000, turn = 2500, price = 26000 }

-- Reactors ----------------------------------------------------------------------

module { id = "ember_reactor", name = "Ember Reactor", maker = "Halcyon Arms",       family = "reactor", size = "S", mass = 5,  powerOut = 20, powerCap = 60,  price = 2500 }
module { id = "kiln_reactor",  name = "Kiln Reactor",  maker = "Ferrous Collective", family = "reactor", size = "M", mass = 14, powerOut = 40, powerCap = 140, price = 8000 }
module { id = "forge_reactor", name = "Forge Reactor", maker = "Concord Military",   family = "reactor", size = "L", mass = 32, powerOut = 75, powerCap = 280, price = 21000 }


-- Utility -----------------------------------------------------------------------

module { id = "hold_pod_s", name = "Cargo Pod",     maker = "Ferrous Collective", family = "utility", size = "any", mass = 2, hold = 12, price = 1200 }
module { id = "tug_beam",   name = "Tug Beam",      maker = "Halcyon Arms",       family = "utility", size = "any", mass = 3, powerDraw = 2, tractorRange = 220, price = 3500 }
module { id = "hold_pod_m", name = "Cargo Pod XL",  maker = "Ferrous Collective", family = "utility", size = "any", mass = 5, hold = 30, price = 4000 }

-- Maneuvering thrusters (shared "any" slot) ----------------------------------------

-- One set of side jets for every hull: it scales to the thruster slot it's
-- fitted in (S as listed, M and L stronger, heavier and hungrier).
module { id = "aux_thrusters",   name = "Side Jets",    maker = "Halcyon Arms", family = "thruster", size = "any", mass = 4,  powerDraw = 2, sideThrust = 410, price = 3800,
	bySlot = { S = 1, M = 1.9, L = 3.5, any = 1 } }

-- Computers: one universal slot on every playable hull (src/computers.lua).
module { id = "nav_computer",  name = "Nav Computer",      maker = "Halcyon Arms",       family = "computer", size = "any", mass = 1, powerDraw = 1, computer = "nav",      price = 2500 }
module { id = "fire_computer", name = "Ordnance Computer", maker = "Concord Military",   family = "computer", size = "any", mass = 1, powerDraw = 2, computer = "ordnance", price = 6000 }
module { id = "radar_suite",   name = "Radar Suite",       maker = "Nova Syndicate",     family = "computer", size = "any", mass = 3, powerDraw = 3, computer = "radar", radarRange = 4000, price = 9000 }
