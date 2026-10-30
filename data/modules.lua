--[[
	Modules: fixed catalog items, never randomly rolled. Each has a family
	and size (it only fits a matching slot), a mass, and an optional
	powerDraw that is taken out of the reactor's output all the time.

	Stat fields by family:
	  engine   thrust (kN), turn, burnPower (power/second at full throttle;
	           retro thrusters burn 40% of it at full reverse)
	  thruster sideThrust (kN) and jetPower (power/second at full strafe) for
	           maneuvering thrusters: the only way a ship
	           can strafe. Thruster slots are size "any", shared by every
	           hull that has one, and battleships have none.
	  reactor  powerOut (per second), powerCap (stored power)
	  utility  hold (cubic metres), tractorRange (pixels). Utility modules are
	           size "any" and fit any hull's utility slot.
	  primary / secondary: a weapon table

	Weapon fields:
	  kind        gun, artillery, laser or missile. Guns, artillery and
	              missiles fire ammo of their own kind in their own size or
	              smaller, and the ammo sets damage, speed, range, splash
	              and knockback (data/items.lua). Lasers use no ammo: they
	              carry damage (per second), range and knockback themselves
	              and drain powerPerSec.
	  fireRate    shots per second           spread    random spread in degrees
	  gimbal      degrees it can aim off the nose
	  recoil      push back on the shooter
]]

-- Primary: guns (fast, short range, no splash) ------------------------------

module {
	id = "px2_autogun", name = "PX-2 Autogun", maker = "Halcyon Arms", family = "primary", size = "S",
	mass = 4, powerDraw = 1, price = 2200,
	weapon = { kind = "gun", fireRate = 150 / 60, spread = 2, gimbal = 10, recoil = 40 },
}

module {
	id = "rk7_chaingun", name = "RK-7 Chaingun", maker = "Brute Industries", family = "primary", size = "M",
	mass = 10, powerDraw = 2, price = 6500,
	weapon = { kind = "gun", fireRate = 150 / 60, spread = 2.5, gimbal = 10, recoil = 70 },
}

-- Primary: artillery (slow, long range, high damage, splash) -----------------
-- Shells fly their full range and burst on contact, near an enemy, or at the end of their range.

module {
	id = "pip_mortar", name = "Pip Mortar", maker = "Ferrous Collective", family = "primary", size = "S",
	mass = 6, powerDraw = 1, price = 3400,
	weapon = { kind = "artillery", fireRate = 1.2, spread = 1, gimbal = 6, recoil = 1500 },
}

module {
	id = "thumper_m", name = "Thumper", maker = "Brute Industries", family = "primary", size = "M",
	mass = 16, powerDraw = 2, price = 9000,
	weapon = { kind = "artillery", fireRate = 0.8, spread = 1, gimbal = 6, recoil = 4000 },
}

module {
	id = "long_tom", name = "Long Tom", maker = "Ferrous Collective", family = "primary", size = "L",
	mass = 34, powerDraw = 3, price = 24000,
	weapon = { kind = "artillery", fireRate = 0.5, spread = 0.5, gimbal = 5, recoil = 12000 },
}

-- Primary: lasers (no ammo, heavy power draw) ---------------------------------

module {
	id = "glint_laser", name = "Glint Laser", maker = "Halcyon Arms", family = "primary", size = "S",
	mass = 5, price = 5200,
	weapon = { kind = "laser", damage = 26, powerPerSec = 22, range = 750, gimbal = 12, knockback = 60 },
}

module {
	id = "lumen_lance", name = "Lumen Lance", maker = "Nova Syndicate", family = "primary", size = "M",
	mass = 12, price = 14000,
	weapon = { kind = "laser", damage = 55, powerPerSec = 48, range = 900, gimbal = 12, knockback = 120 },
}

-- Secondary: missile launchers ---------------------------------------------------
-- Q switches which missile size the launchers fire.

module {
	id = "sparrow_rack", name = "Sparrow Rack", maker = "Halcyon Arms", family = "secondary", size = "S",
	mass = 3, price = 4000,
	weapon = { kind = "missile", fireRate = 1.5, recoil = 300 },
}

module {
	id = "hornet_pod", name = "Hornet Pod", maker = "Nova Syndicate", family = "secondary", size = "M",
	mass = 8, price = 11000,
	weapon = { kind = "missile", fireRate = 1.0, recoil = 800 },
}

module {
	id = "trident_bay", name = "Trident Bay", maker = "Ferrous Collective", family = "secondary", size = "L",
	mass = 18, price = 26000,
	weapon = { kind = "missile", fireRate = 0.7, recoil = 1600 },
}

-- Engines -----------------------------------------------------------------------

module { id = "flit_engine",  name = "Flit Engine",  maker = "Halcyon Arms",       family = "engine", size = "S", mass = 6,  powerDraw = 2, thrust = 420,  turn = 250,  burnPower = 18,  price = 3000 }
module { id = "mule_engine",  name = "Mule Engine",  maker = "Brute Industries",   family = "engine", size = "M", mass = 16, powerDraw = 4, thrust = 900,  turn = 800,  burnPower = 34,  price = 9000 }
module { id = "cinder_drive", name = "Cinder Drive", maker = "Nova Syndicate",     family = "engine", size = "L", mass = 40, powerDraw = 8, thrust = 2000, turn = 2500, burnPower = 24, price = 26000 }

-- Reactors ----------------------------------------------------------------------

module { id = "ember_reactor", name = "Ember Reactor", maker = "Halcyon Arms",       family = "reactor", size = "S", mass = 5,  powerOut = 20, powerCap = 60,  price = 2500 }
module { id = "kiln_reactor",  name = "Kiln Reactor",  maker = "Ferrous Collective", family = "reactor", size = "M", mass = 14, powerOut = 40, powerCap = 140, price = 8000 }


-- Utility -----------------------------------------------------------------------

module { id = "hold_pod_s", name = "Cargo Pod",     maker = "Ferrous Collective", family = "utility", size = "any", mass = 2, hold = 12, price = 1200 }
module { id = "tug_beam",   name = "Tug Beam",      maker = "Halcyon Arms",       family = "utility", size = "any", mass = 3, powerDraw = 2, tractorRange = 220, price = 3500 }
module { id = "hold_pod_m", name = "Cargo Pod XL",  maker = "Ferrous Collective", family = "utility", size = "any", mass = 5, hold = 30, price = 4000 }

-- Maneuvering thrusters (shared "any" slot) ----------------------------------------

module { id = "aux_thrusters",   name = "Side Jets",    maker = "Halcyon Arms", family = "thruster", size = "any", mass = 4,  powerDraw = 2, sideThrust = 340, jetPower = 8,  price = 3800 }
module { id = "aux_thrusters_m", name = "Side Jets XL", maker = "Halcyon Arms", family = "thruster", size = "any", mass = 10, powerDraw = 4, sideThrust = 650, jetPower = 14, price = 9500 }
