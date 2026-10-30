--[[
	Live tuning knobs. Every value here shows up as a slider in the debug
	panel (F1), so flight feel can be tuned while playing. When something
	feels right, copy the number back into the defaults below.
]]

local T = {}

T.specs = {
	{ key = "thrustScale",    label = "Thrust",                 min = 0.2, max = 3,    value = 1,    precision = 2 },
	{ key = "sideScale",      label = "Side/retro thrusters",   min = 0,   max = 3,    value = 1,    precision = 2 },
	{ key = "dragScale",      label = "Drag (sets top speed)",  min = 0,   max = 3,    value = 0.5,    precision = 2 },
	{ key = "linearDamping",  label = "Linear damping (drift)", min = 0,   max = 2,    value = 0.04, precision = 2 },
	{ key = "massScale",      label = "Mass",                   min = 0.25, max = 3,   value = 1,    precision = 2 },
	{ key = "turnScale",      label = "Turn torque",            min = 0.1, max = 3,    value = 1,    precision = 2 },
	{ key = "maxTurnRate",    label = "Max turn rate (rad/s)",  min = 1,   max = 15,   value = 6.5,  precision = 1 },
	{ key = "aimGain",        label = "Aim snappiness",         min = 1,   max = 30,   value = 9,    precision = 1 },
	{ key = "turnResponse",   label = "Turn response",          min = 1,   max = 60,   value = 18,   precision = 1 },
	{ key = "knockbackScale", label = "Hit knockback",          min = 0,   max = 4,    value = 1,    precision = 2 },
	{ key = "recoilScale",    label = "Recoil",                 min = 0,   max = 4,    value = 1,    precision = 2 },
	{ key = "ramSpeed",       label = "Ram: min impact speed",  min = 0,   max = 400,  value = 90,   precision = 0 },
	{ key = "ramDamageScale", label = "Ram damage",             min = 0,   max = 0.003, value = 0.0005, precision = 5 },
	{ key = "boostThrust",    label = "Afterburner thrust (x main)", min = 1, max = 6, value = 3,  precision = 2 },
	{ key = "boostDrain",     label = "Afterburner drain (capacity/s)", min = 0, max = 2, value = 0.15, precision = 2 },
	{ key = "boostRelight",   label = "Afterburner relights at (capacity)", min = 0, max = 1, value = 0.3, precision = 2 },
	{ key = "thrustRecharge", label = "Power recharge while thrusting", min = 0, max = 1, value = 0.35, precision = 2 },
	{ key = "currentScale",   label = "Planet current speed",   min = 0,   max = 3,    value = 1,    precision = 2 },
	{ key = "gunFalloff",     label = "Gun rounds: damage lost at max range", min = 0, max = 1, value = 0.6, precision = 2 },
	{ key = "artilleryFuse",  label = "Artillery proximity fuse (x splash)", min = 0, max = 1, value = 0.2, precision = 2 },
	{ key = "asteroidToughness", label = "Asteroid toughness (hp per r^2)", min = 0.005, max = 0.3, value = 0.05, precision = 3 },
	{ key = "asteroidImpact", label = "Asteroid impact damage", min = 0, max = 20, value = 4, precision = 1 },
	{ key = "huskToughness",  label = "Husk toughness (x ship armor)", min = 0.05, max = 2, value = 0.5, precision = 2 },
	{ key = "tractorBase",    label = "Tractor beam base range", min = 50, max = 800, value = 260, precision = 0 },
	{ key = "enemyDamage",    label = "Enemy damage",           min = 0,   max = 2,    value = 0.7,  precision = 2 },
	{ key = "camLead",        label = "Camera lead",            min = 0,   max = 0.6,  value = 0.3,  precision = 2 },
	{ key = "shake",          label = "Screenshake",            min = 0,   max = 2,    value = 1,    precision = 2 },
	{ key = "sellRate",       label = "Market: sell price (x list)", min = 0, max = 1, value = 0.5, precision = 2 },
	{ key = "timeScale",      label = "Game speed",             min = 0.1, max = 2,    value = 1,    precision = 2 },
}

for _, s in ipairs(T.specs) do T[s.key] = s.value end

function T.reset()
	for _, s in ipairs(T.specs) do T[s.key] = s.value end
end

-- Fixed conversion factors between data units and physics units.
T.FORCE_PER_KN = 100      -- 1 kN of engine thrust = this much force in pixel units
T.TORQUE_PER_TURN = 1000  -- 1 point of "turn" = this much torque

-- Share of a dead ship's fitted modules that survive in its husk.
T.moduleSalvage = 0.5

-- Station storage grid, in 1 m3 cells (every station has its own).
T.storageW, T.storageH = 16, 12

-- Looting and towing. A tap of the tractor key (shorter than tapTime
-- seconds) on a wreck or container opens it; holding it tows a container
-- on a towLength pixel line, and you can't fly faster than towSpeed.
T.tapTime = 0.25
T.towLength, T.towSpeed = 70, 220
T.towStiffness, T.towDamping = 15, 6
-- Loose loaded containers drifting in each field.
T.fieldContainers = 6

-- The ship you're given when you start out or lose yours.
T.starterHull = "halcyon_wisp"
-- Level enemies leave you alone until you come this close (or shoot them).
T.aggroRange = 2600
-- Mass drivers (src/transit.lua): the capture ring's radius, seconds to
-- line up and to fire, the speed you leave and arrive at, how long after
-- arriving before a driver will take you again, and the fare in credits
-- (a base plus a little per AU).
T.driverRadius = 260
T.driverAlign, T.driverFire = 1.2, 0.8
T.driverExitSpeed = 2600
T.driverCooldown = 6
T.driverFare, T.driverFarePerAU = 100, 60

-- Orbits: seconds of game clock for Earth's year (the other planets keep
-- their real years relative to it).
T.yearLength = 1800

-- The transit lane: length (base + per AU of distance), the radius of its
-- arc (at least; long lanes bend more gently), how far each side of the
-- median a lane runs, how soft the median is, the current's speed and
-- grip, how far around you things are kept, and how much there is.
-- laneDerelict: the chance, each time something would spawn, of a derelict.
T.laneBase, T.lanePerAU = 20000, 13000
T.laneArc = 60000
T.laneWidth, T.laneMedian = 2400, 400
T.laneFlow, T.laneSwirl = 1800, 0.6
T.laneReach = 12000
T.laneTraffic, T.laneRocks, T.laneDerelict = 5, 5, 0.12
-- The lane buff: thrust multiplier, with the afterburner, and drag
-- multiplier, for every ship inside the lane.
T.laneThrust, T.laneBoostThrust, T.laneDrag = 3, 6, 0.12

-- Gas giants: how far below the cloud tops you can go before the crush
-- starts, how much deeper it reaches full strength, its damage per
-- second there, and its drag.
T.crushStart = 2000
T.crushDepth, T.crushDamage, T.crushDrag = 8000, 60, 0.8

-- Hangar bays: cells across and down, and how many pixels of hull length
-- or width one cell stands for (a Wisp is 4 x 2, a Bastion 14 x 5).
T.hangarW, T.hangarH, T.hangarCell = 30, 14, 20

-- Markets (src/market.lua, data/markets.lua). Credits you start with; the
-- trade grid and a station's shelf, in cells; how long something you sold
-- stays for sale before it's sold on; and how long one more stack takes to
-- come in, by kind (seconds of game time).
T.startCredits = 5000
T.tradeW, T.tradeH = 10, 8
T.marketW, T.marketH = 12, 10
T.resaleTime = 600
T.restockAmmo, T.restockS, T.restockM, T.restockL = 180, 300, 600, 1200

-- Developer cheats, toggled from the debug panel.
T.dev = { god = false, infiniteAmmo = false, showHold = false }

return T
