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
	  weapon   (cannons, lasers, drills) fits a hull's hardpoint slot.
	  bay      (missile racks and drone bays) fits a bay slot.
	           Either fires on whichever trigger its slot is set to, and
	           loads whichever ammo is picked for that slot.

	Weapon fields:
	  kind        cannon, pulse, beam or drill (weapon family); missile or drone
	              (bay family). A cannon is anything that fires rounds, shells
	              or shot: chambers says which. Hardpoint weapons load ammo
	              in their exact caliber, bay launchers their size or smaller. The ammo sets damage,
	              speed, range, splash and knockback (data/items.lua).
	              Lasers take no ammo. A pulse fires a flash per shot:
	              damage, range, powerPerShot, pulse (seconds it shows). A
	              beam burns while held: damage and powerPerSecond per second.
	  beams       lasers: lines fired at once, each doing full damage
	              (a shotgun laser); beamSpread = fan width in degrees.
	  color       lasers: beam color { r, g, b } (0..1); beamWidth scales
	              how thick it's drawn.
	  capacity    missile racks: tube space, in S rounds (an M round takes 2,
	              an L round 4). It salvos what's armed at fireRate, then
	              re-arms one round at a time from the hold, each taking its
	              ammo's shot.armTime seconds.
	  control     drone bays: how many drones it flies at once, counted by
	              size (S drone 1, M 2, L 4). S bay 1, M bay 2, L bay 4.
	  chambers    the ammo families it can load, first = default: "gun"
	              (rounds), "artillery" (shells), "shotgun" (shot), like
	              { "shotgun", "gun" }. Unset: cannons rounds, missile racks
	              missiles and torpedoes. It fires at its own fireRate
	              whatever is loaded; the ammo changes the hit, not the cadence.
	              (Old kinds gun, artillery and shotgun load as a cannon
	              chambering that ammo; torpedo as a missile rack.)
	  fireRate    shots per second           spread    random spread in degrees
	  caliber     ammo size a gun fires, if not its own (twin mounts)
	  barrels     barrels that take turns firing; barrelGap = spacing
	  gimbal      degrees it can aim off the nose
	  recoilPct   cannons: push back on the shooter, as a
	              percentage of the round's knockback
	  recoil      launchers: push back on the shooter (a fixed impulse)
]]

-- Weapons: guns (fast, short range, no splash) --------------------------------



-- Two RK-7 actions on one large mount, firing the same heavy rounds. The
-- barrels alternate, so it's two autocannons' worth of fire from one slot.

-- Weapons: artillery (slow, long range, high damage, splash) -----------------
-- Shells fly their full range and burst on contact, near an enemy, or at the end of their range.




-- Weapons: pulse lasers (no ammo, a chunk of power per pulse) -----------------




-- Mining drills: hold the trigger and the drill extends out of the nose,
-- up to the ship's own length, and grinds whatever its tip touches. No
-- ammo and little power. damage is per second; rockDamage multiplies it
-- against asteroids, and drilled rock drops ore when it breaks.
module {
	id = "drill_s_base", name = "Drill S", maker = "Ferrous Collective", family = "weapon", size = "S",
	mass = 6, price = 3500,
	weapon = { kind = "drill", damage = 12, rockDamage = 12, powerPerSecond = 4, extendTime = 0.35 },
}

module {
	id = "drill_m_base", name = "Drill M", maker = "Ferrous Collective", family = "weapon", size = "M",
	mass = 14, price = 9000,
	weapon = { kind = "drill", damage = 25, rockDamage = 14, powerPerSecond = 8, extendTime = 0.45 },
}

module {
	id = "drill_l_base", name = "Drill L", maker = "Brute Industries", family = "weapon", size = "L",
	mass = 34, price = 24000,
	weapon = { kind = "drill", damage = 50, rockDamage = 16, powerPerSecond = 15, extendTime = 0.6 },
}

-- Beam lasers: a continuous beam while the trigger is held. damage and
-- powerPerSecond are per second; easier to keep on target than a pulse
-- laser, so a little less damage for the power.
module {
	id = "beam_s_base", name = "Beam Laser S", maker = "Halcyon Arms", family = "weapon", size = "S",
	mass = 6, price = 6000,
	weapon = { kind = "beam", damage = 40, powerPerSecond = 30, range = 3000, gimbal = 12 },
}

module {
	id = "beam_m_base", name = "Beam Laser M", maker = "Nova Syndicate", family = "weapon", size = "M",
	mass = 14, price = 16000,
	weapon = { kind = "beam", damage = 85, powerPerSecond = 60, range = 3600, gimbal = 12 },
}

module {
	id = "beam_l_base", name = "Beam Laser L", maker = "Halcyon Arms", family = "weapon", size = "L",
	mass = 32, price = 42000,
	weapon = { kind = "beam", damage = 150, powerPerSecond = 100, range = 4400, gimbal = 10 },
}

-- Bay launchers -------------------------------------------------------------------
-- Missile racks (fire missiles, or torpedoes: very fast, steer slowly, huge damage) and drone bays (launch
-- an armed drone that fights for you for a while). Each fires its own kind
-- in its size or smaller, picked per slot.




module {
	id = "drone_s_base", name = "Drone Bay S", maker = "Nova Syndicate", family = "bay", size = "S",
	mass = 6, price = 7000,
	weapon = { kind = "drone", fireRate = 0.4, recoil = 100, control = 1 },
}

module {
	id = "drone_m_base", name = "Drone Bay M", maker = "Nova Syndicate", family = "bay", size = "M",
	mass = 14, price = 18000,
	weapon = { kind = "drone", fireRate = 0.3, recoil = 200, control = 2 },
}

module {
	id = "drone_l_base", name = "Drone Bay L", maker = "Nova Syndicate", family = "bay", size = "L",
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
