--[[
	Live tuning knobs. Every value here shows up as a slider in the debug
	panel (F1), so flight feel can be tuned while playing. When something
	feels right, copy the number back into the defaults below.
]]

local T = {}

T.specs = {
	{ key = "thrustScale",    label = "Thrust",                 min = 0.2, max = 3,    value = 1,    precision = 2 },
	{ key = "sideScale",      label = "Side/retro thrusters",   min = 0,   max = 3,    value = 1,    precision = 2 },
	{ key = "dragScale",      label = "Drag (sets top speed)",  min = 0,   max = 3,    value = 0.08,   precision = 2 },
	{ key = "navLookahead",   label = "Nav: collision warning (s ahead)", min = 1, max = 8, value = 3, precision = 1 },
	{ key = "guidanceCone",   label = "Guidance: lock cone (deg)", min = 5, max = 90, value = 25, precision = 0 },
	{ key = "droneRecall",    label = "Drone: idle secs before docking", min = 2, max = 30, value = 10, precision = 0 },
	{ key = "aiCruise",       label = "AI: fighting speed (px/s)", min = 100, max = 2500, value = 750, precision = 0 },
	{ key = "traderCruise",   label = "AI: trader cruise (px/s)", min = 100, max = 2500, value = 600, precision = 0 },
	{ key = "aiResponse",     label = "AI: speed error for full thrust", min = 20, max = 800, value = 200, precision = 0 },
	{ key = "linearDamping",  label = "Linear damping (drift)", min = 0,   max = 2,    value = 0.04, precision = 2 },
	{ key = "massScale",      label = "Mass",                   min = 0.25, max = 3,   value = 1,    precision = 2 },
	{ key = "turnScale",      label = "Turn torque",            min = 0.1, max = 3,    value = 1,    precision = 2 },
	{ key = "maxTurnRate",    label = "Max turn rate (rad/s)",  min = 1,   max = 15,   value = 6.5,  precision = 1 },
	{ key = "aimGain",        label = "Aim snappiness",         min = 1,   max = 30,   value = 9,    precision = 1 },
	{ key = "turnResponse",   label = "Turn response",          min = 1,   max = 60,   value = 18,   precision = 1 },
	{ key = "knockbackScale", label = "Hit knockback",          min = 0,   max = 4,    value = 1,    precision = 2 },
	{ key = "recoilScale",    label = "Recoil",                 min = 0,   max = 4,    value = 1,    precision = 2 },
	{ key = "ramSpeed",       label = "Ram: min impact speed (non-ships)", min = 0, max = 400, value = 90, precision = 0 },
	{ key = "ramSpeedScale",  label = "Ram: min impact speed (x each hull's)", min = 0, max = 3, value = 1, precision = 2 },
	{ key = "ramDamageScale", label = "Ram damage",             min = 0,   max = 0.003, value = 0.0005, precision = 5 },
	{ key = "boostThrust",    label = "Afterburner thrust (x main)", min = 1, max = 6, value = 3,  precision = 2 },
	{ key = "boostDrain",     label = "Afterburner drain (capacity/s)", min = 0, max = 2, value = 0.15, precision = 2 },
	{ key = "boostRelight",   label = "Afterburner relights at (capacity)", min = 0, max = 1, value = 0.3, precision = 2 },
	{ key = "boostReserve",   label = "Afterburner on reserve (share of its extra thrust)", min = 0, max = 1, value = 0.75, precision = 2 },
	{ key = "thrustRecharge", label = "Power recharge while thrusting", min = 0, max = 1, value = 0.35, precision = 2 },
	{ key = "currentScale",   label = "Planet current speed",   min = 0,   max = 3,    value = 1,    precision = 2 },
	{ key = "gunFalloff",     label = "Gun rounds: damage lost at max range", min = 0, max = 1, value = 0.6, precision = 2 },
	{ key = "artilleryFuse",  label = "Artillery proximity fuse (x splash)", min = 0, max = 1, value = 0.2, precision = 2 },
	{ key = "asteroidToughness", label = "Asteroid toughness (hp per r^2)", min = 0.005, max = 0.3, value = 0.05, precision = 3 },
	{ key = "asteroidImpact", label = "Asteroid impact damage", min = 0, max = 20, value = 4, precision = 1 },
	{ key = "huskToughness",  label = "Husk toughness (x ship armor)", min = 0.05, max = 2, value = 0.5, precision = 2 },
	{ key = "tractorBase",    label = "Tractor beam base range", min = 50, max = 800, value = 260, precision = 0 },
	{ key = "lootHoldAt",     label = "Looting: beam holds it within (x range)", min = 0.2, max = 1.2, value = 0.6, precision = 2 },
	{ key = "lootHoldAccel",  label = "Looting: beam pull (px/s^2)", min = 0, max = 4000, value = 1200, precision = 0 },
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
-- The approach behind the breech where its tractor takes you (length and
-- half-width), how fast it reels you in, and the most it can slow you
-- (px/s^2): come in faster than it can stop and you overshoot.
T.driverZone, T.driverZoneWidth = 1500, 250
T.driverBarrel = 1000                -- the barrel's length
T.driverReel = 450
T.driverGrip = 320
T.driverAlign, T.driverFire = 1.2, 1.4
-- how fast a driver's barrel swings round to its firing bearing (rad/s),
-- and its speed round the planet as a share of the current there
T.driverSlew, T.driverOrbitScale = 0.6, 1
T.driverExitSpeed = 4500
-- How a driver sends you: "lane" (the highway) or "flight" (the warp
-- trip and the catch at the other end). Switchable in the debug panel.
T.travelMode = "lane"
T.laneEntrySpeed = 2600
-- After the barrel: T.driverCoast seconds climbing to driverCoastSpeed with
-- the camera pulling out to cineZoom; then into the lane on a run-up of
-- laneRunup px short of its mouth, braking to laneEntrySpeed.
T.driverCoast, T.driverCoastSpeed, T.cineZoom, T.laneRunup = 2.5, 9000, 0.15, 20000
-- share of the driver's speed you still have as you enter the lane
T.laneKeep = 0.8
-- seconds over which lane drag comes back after you enter, so the kick
-- carries you a good way down the road
T.laneCarryTime = 20
T.driverCooldown = 6
T.driverFare, T.driverFarePerAU = 100, 60

-- Orbits: seconds of game clock for Earth's year (the other planets keep
-- their real years relative to it).
T.yearLength = 1800

-- The transit lane: length (base + per AU of distance), the radius of its
-- arc (at least; long lanes bend more gently), how far each side of the
-- median a lane runs and how soft the median is. The rest (buff, how
-- much is on the road) are live sliders in the debug panel: T.laneSpecs
-- below.
T.laneBase = 20000
T.laneArc = 60000
T.laneWidth, T.laneMedian = 2400, 400
-- Past laneFarAU, each extra AU of a trip adds only laneFarScale of an
-- AU of lane, so Neptune is a long haul but not minutes of road.
T.laneFarAU, T.laneFarScale = 5, 0.25

-- Gas giants: how far below the cloud tops you can go before the crush
-- starts, how much deeper it reaches full strength, its damage per
-- second there, and its drag.
T.crushStart = 2000
T.crushDepth, T.crushDamage, T.crushDrag = 8000, 60, 0.8

-- Cloud cities drift round their spot: this far across (px, each way),
-- and over these periods (s) across and up and down (the up and down
-- range is the layer between the cloud tops and the crush).
T.cityDriftAcross, T.cityDriftAcrossPeriod, T.cityDriftUp = 2500, 330, 260

-- Sleeping debris (Game:updateSleepers): rocks further than sleepFar
-- from the player stop being simulated and just follow their orbit, and
-- wake inside sleepNear; checked every sleepEvery steps.
T.sleepFar, T.sleepNear, T.sleepEvery = 7000, 6000, 12

-- Hangar bays: cells across and down, and how many pixels of hull length
-- or width one cell stands for (a Wisp is 4 x 2, a Bastion 14 x 5).
T.hangarW, T.hangarH, T.hangarCell = 30, 14, 20

-- Markets (src/market.lua, data/markets.lua). Credits you start with; the
-- trade grid and a station's shelf, in cells; how long something you sold
-- stays for sale before it's sold on; and how long one more stack takes to
-- come in, by kind (seconds of game time).
T.startCredits = 5000

-- How far the camera zooms out (mouse wheel), as a scale.
T.minZoom = 0.17

T.tradeW, T.tradeH = 10, 8
T.marketW, T.marketH = 12, 10
T.resaleTime = 600
T.restockAmmo, T.restockS, T.restockM, T.restockL = 180, 300, 600, 1200

-- Developer cheats, toggled from the debug panel.
T.dev = { god = false, infiniteAmmo = false, showHold = false }

-- Flight and the catch (src/transit.lua), sliders in the debug panel's
-- Flight and catch section. flight*: seconds the trip view lasts (base
-- plus per AU) and game-clock seconds that pass per AU. catch*: how many
-- braking rings, how far apart and how big, the share of speed each one
-- takes, the fastest the driver will catch you at, how fast you arrive,
-- how far beyond the last ring you start, and how far off the line.
T.flightSpecs = {
	{ key = "flightBase",      label = "Trip view: seconds",             min = 0,    max = 15,    value = 3,     precision = 1 },
	{ key = "flightPerAU",     label = "Trip view: seconds per AU",      min = 0,    max = 5,     value = 1,     precision = 1 },
	{ key = "flightClockPerAU", label = "Game clock per AU (s)",         min = 0,    max = 1200,  value = 120,   precision = 0 },
	{ key = "catchSpeed",      label = "Arrival speed (px/s)",           min = 500,  max = 6000,  value = 2500,  precision = 0 },
	{ key = "catchRings",      label = "Braking rings",                  min = 1,    max = 8,     value = 2,     precision = 0 },
	{ key = "catchSpacing",    label = "Ring spacing (px)",              min = 800,  max = 6000,  value = 2500,  precision = 0 },
	{ key = "catchRingRadius", label = "Ring radius (px)",               min = 100,  max = 1000,  value = 550,   precision = 0 },
	{ key = "catchBrake",      label = "Speed taken per ring",           min = 0,    max = 0.9,   value = 0.5,  precision = 2 },
	{ key = "catchBaySpeed",   label = "Fastest catch (px/s)",           min = 100,  max = 2000,  value = 900,   precision = 0 },
	{ key = "catchApproach",   label = "Start beyond last ring (px)",    min = 1000, max = 20000, value = 8000,  precision = 0 },
	{ key = "catchOffset",     label = "Start off the line (px)",        min = 0,    max = 4000,  value = 600,  precision = 0 },
	{ key = "catchDrift",      label = "Planet current push while inbound", min = 0, max = 2,     value = 0.12,  precision = 2 },
}
for _, s in ipairs(T.flightSpecs) do T[s.key] = s.value end

function T.resetFlight()
	for _, s in ipairs(T.flightSpecs) do T[s.key] = s.value end
end

-- Transit lane knobs, shown as sliders in the debug panel's Transit lane
-- section. laneRamp: how far past the lane's edge the buff and the
-- current fade out. Rocks and derelicts are laid out when you enter.
T.laneSpecs = {
	{ key = "laneRocks",       label = "Rocks on the road (per 10k px)", min = 0,  max = 15,    value = 1,     precision = 0 },
	{ key = "laneOffroad",     label = "Rocks off-road (per 10k px)",   min = 0,    max = 60,    value = 12,    precision = 0 },
	{ key = "laneDerelicts",   label = "Derelicts (per 100k px)",       min = 0,    max = 10,    value = 1,     precision = 1 },
	{ key = "laneFlow",        label = "Traffic speed (px/s)",          min = 300,  max = 4000,  value = 1800,  precision = 0 },
	{ key = "laneThrust",      label = "Lane buff: thrust x",           min = 1,    max = 6,     value = 3,     precision = 2 },
	{ key = "laneDrag",        label = "Lane buff: drag x",             min = 0.05, max = 1,     value = 0.25,  precision = 2 },
	{ key = "laneRamp",        label = "Off-road falloff (px)",         min = 0,    max = 8000,  value = 3000,  precision = 0 },
	{ key = "lanePerAU",       label = "Lane length per AU (px)",       min = 2000, max = 100000, value = 50000, precision = 0 },
}
for _, s in ipairs(T.laneSpecs) do T[s.key] = s.value end

function T.resetLane()
	for _, s in ipairs(T.laneSpecs) do T[s.key] = s.value end
end

return T
