--[[
	Live tuning knobs. Every value here shows up as a slider in the debug
	panel (F1), so flight feel can be tuned while playing. When something
	feels right, copy the number back into the defaults below.
]]

local T = {}

T.specs = {
	{ key = "thrustScale",    label = "Thrust",                 min = 0.2, max = 3,    value = 1,    precision = 2 },
	{ key = "sideScale",      label = "Side/retro thrusters",   min = 0,   max = 3,    value = 1.5,    precision = 2 },
	{ key = "dragScale",      label = "Drag (sets top speed)",  min = 0,   max = 3,    value = 0.03,   precision = 2 },
	{ key = "navLookahead",   label = "Nav fallback: lookahead (s)", min = 1, max = 8, value = 2, precision = 1 },
	{ key = "guidanceCone",   label = "Guidance fallback: cone (deg)", min = 5, max = 90, value = 25, precision = 0 },
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
	{ key = "recoilScale",    label = "Recoil",                 min = 0,   max = 4,    value = 3,    precision = 2 },
	{ key = "ramDamage",      label = "Ram damage (x mass x speed change^2)", min = 0, max = 0.00003, value = 0.0000028, precision = 7 },
	{ key = "ramGrace",       label = "Ram: free speed change (px/s)", min = 0, max = 300, value = 60, precision = 0 },
	{ key = "boostThrust",    label = "Afterburner thrust (x main)", min = 1, max = 6, value = 3,  precision = 2 },
	{ key = "boostDrain",     label = "Afterburner drain (capacity/s)", min = 0, max = 2, value = 0.15, precision = 2 },
	{ key = "boostRelight",   label = "Afterburner capacitor reserve (capacity)", min = 0, max = 1, value = 0.3, precision = 2 },
	{ key = "boostReserve",   label = "Afterburner on reserve (share of its extra thrust)", min = 0, max = 1, value = 0.75, precision = 2 },
	{ key = "thrustRecharge", label = "Power recharge while thrusting", min = 0, max = 1, value = 0.35, precision = 2 },
	{ key = "surfacePull", label = "Surface inward pull (px/s2)", min = 0, max = 100, value = 35, precision = 0 },
	{ key = "surfacePullRange", label = "Surface pull reach (px)", min = 200, max = 5000, value = 2200, precision = 0 },
	{ key = "gasPullScale", label = "Cloud-top pull multiplier", min = 0, max = 8, value = 4, precision = 2 },
	{ key = "currentScale",   label = "Planet current speed",   min = 0,   max = 3,    value = 1,    precision = 2 },
	{ key = "gunFalloff",     label = "Gun rounds: damage lost at max range", min = 0, max = 1, value = 0.6, precision = 2 },
	{ key = "artilleryFuse",  label = "Artillery proximity fuse (x splash)", min = 0, max = 1, value = 0.2, precision = 2 },
	{ key = "asteroidToughness", label = "Asteroid toughness (hp per r^2)", min = 0.005, max = 0.3, value = 0.05, precision = 3 },
	{ key = "asteroidImpact", label = "Asteroid impact damage", min = 0, max = 20, value = 8, precision = 1 },
	{ key = "huskToughness",  label = "Husk toughness (x ship armor)", min = 0.05, max = 2, value = 0.5, precision = 2 },
	{ key = "tractorBase",    label = "Tractor beam base range", min = 50, max = 800, value = 260, precision = 0 },
	{ key = "lootHoldAt",     label = "Looting: beam holds it within (x range)", min = 0.2, max = 1.2, value = 0.6, precision = 2 },
	{ key = "lootHoldAccel",  label = "Looting: beam pull on something your own mass (px/s^2)", min = 0, max = 4000, value = 1200, precision = 0 },
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
T.moduleSalvage = 0.75
T.wreckShotRecovery = 0.5 -- each cargo unit survives shooting a wreck; drilling preserves all

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
T.starterHull = "intaki_wisp"
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
T.driverZone, T.driverZoneWidth = 600, 110
T.driverBarrel = 1000                -- the barrel's length
T.driverReel = 450
-- The tractor beam that catches ships (src/beam.lua): the most it can slow
-- the player (px/s^2) at a station's runway or a driver's breech. NPCs are
-- held without a cap.
T.beamGrip = 360
T.driverAlign, T.driverFire = 1.2, 0.25
-- how fast a driver's barrel swings round to its firing bearing (rad/s),
-- and its speed round the planet as a share of the current there
T.driverSlew, T.driverOrbitScale = 0.6, 1
T.driverExitSpeed = 16000
-- How a driver sends you: "lane" (the highway) or "flight" (the warp
-- trip and the catch at the other end). Switchable in the debug panel.
T.travelMode = "lane"
T.laneEntrySpeed = 2600
-- After the barrel: T.driverCoast seconds climbing to driverCoastSpeed with
-- the camera pulling out to cineZoom; then into the lane on a run-up of
-- laneRunup px short of its mouth, braking to laneEntrySpeed.
T.driverCoast, T.driverCoastSpeed, T.cineZoom, T.laneRunup = 0.7, 24000, 0.15, 20000
-- share of the driver's speed you still have as you enter the lane
T.laneKeep = 0.4
-- a cut that can't be avoided (fired at something solid, a map that
-- couldn't be built ahead) hidden in the lane's glow: seconds for it to
-- wash over, and to clear once the new level is in (Game:coverThen)
T.laneCoverIn, T.laneCoverOut = 0.18, 0.55
-- the map at a lane's far end is built ahead of you, a slice per frame
-- (seconds of each frame it may take), starting this far from the end
-- (px, on top of what's in view); the map you left goes once you're this
-- far past its edge (px, on top of what's in view)
T.laneStageBudget = 0.004
T.laneStageAhead = 60000
T.laneDropBehind = 8000
-- fastest you come out of a lane into a site's pocket (at its spawn point)
T.siteArriveSpeed = 600
-- loose rock carrying on past a map's edge (Game:spawnOuterBelt): how far
-- out (px; past what's in view at the widest zoom, so a lane leaving the
-- map takes over out of sight) and how thick (rocks per 100M px^2)
T.mapOuter = 16000
-- share of a map's radius, in from its edge, over which the current eases
-- off to nothing (so it's still at the edge and beyond)
T.edgeCurrentFade = 0.3
T.mapOuterDensity = 14
-- seconds over which lane drag comes back after you enter, so the kick
-- carries you a good way down the road
T.laneCarryTime = 20
-- the seconds a driver's extra kick takes to settle back to the lane's
-- speed (laneFlow: the lane carries you, and its traffic, src/transit.lua)
T.laneKickTime = 6
T.driverCooldown = 6
T.driverFare, T.driverFarePerAU = 100, 60
T.siteLaneLength = 40000   -- off a driver out to a site (and home again)
T.gateLaneLength = 20000   -- between a site's pockets
-- acceleration gates (src/sites.lua): small single-target mass drivers
T.gateBarrel, T.gateHalfWidth, T.gateRadius = 520, 46, 300
-- an acceleration gate's shot: out of the barrel at gateExitSpeed, climbing
-- to gateCoastSpeed (a driver's are driverExitSpeed and driverCoastSpeed)
T.gateExitSpeed, T.gateCoastSpeed = 5000, 6500
T.gateZone, T.gateZoneWidth = 900, 170
T.siteFare = 200   -- a site that names no fare of its own (data/sites.lua)

-- Orbits: seconds of game clock for Earth's year (the other planets keep
-- their real years relative to it).
T.pickupDrag = 1.5 -- shared by live pickups and unloaded orbital catch-up
T.yearLength = 7200

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
T.crushDepth, T.crushDamage, T.crushDrag = 8000, 260, 1

-- Cloud cities drift round their spot: this far across (px, each way),
-- and over these periods (s) across and up and down (the up and down
-- range is the layer between the cloud tops and the crush).
T.cityDriftAcross, T.cityDriftAcrossPeriod, T.cityDriftUp = 2500, 330, 260

-- Sleeping debris (Game:updateSleepers): rocks further than sleepFar
-- from the player stop being simulated and just follow their orbit, and
-- wake inside sleepNear; checked every sleepEvery steps.
-- A-Life prototype, separate from the debris sleep band.
T.alifeNear, T.alifeFar = 18000, 22000
T.alifeMoonEvery = 3  -- one in this many traders takes an eligible moon round trip
T.alifeGateExit = 2000  -- online ships fly beyond the existing moon gate before transfer
T.alifeSpread = 1500  -- persistent cross-track variation, fading at destinations
T.alifeLocalTick, T.alifeRemoteTick, T.alifeStay = 0.5, 2, 60
T.securityThink, T.securityRange = 0.5, 6000
T.aiSteerEvery, T.aiClearance = 0.2, 12
T.npcDecisionInterval,T.npcControlInterval,T.npcCombatInterval=1,.2,.1
T.npcCruiseInterval=1
T.aiBoostCruise, T.aiBoostStopMargin = 1.6, 1800
T.patrolInspect, T.pirateLinger = 10, 60
T.patrolDockEvery,T.patrolDockStay,T.patrolStandOff=3,45,450
T.npcRepairThreshold,T.npcRepairPerSecond=.7,4
T.npcAmmoThreshold,T.npcAmmoSeconds=.2,30 -- seek supplies below 20%; fallback reserve = 30s of fire
T.pirateLootUnits,T.pirateLootTime,T.pirateLootRange=5,25,3000
T.pirateRetreatHealth,T.pirateRest=.35,30
-- One NPC cruise speed; hulls vary it by at most npcCruiseSpread either way.
T.npcCruise,T.npcCruiseReference,T.npcCruiseSpread=650,700,.15
T.directLinkAngle=math.pi*2/3 -- NPCs fly straight (round the planet) between ordinary nodes up to this far apart;
-- kept well short of half the planet, where 'which way round' flips frame to frame
T.ramAggroShare=.15 -- a ram this share of max armour (or more) makes the victim hostile
T.npcIdleRoam=60 -- seconds with no work before an NPC roams to another node of its job
T.offlineCombatTick, T.offlineCombatHit, T.offlineCombatRounds = 4, 0.15, 12
T.offlineCombatSegment, T.offlineRetreat = 0.12, 90
-- Offline combat rule (encounters.lua): pirates attack only at these odds or
-- better; faster prey escapes with chance (speed ratio - 1) x gain, capped;
-- armour fraction where each kind of ship breaks off.
T.offlineEngageOdds, T.offlineEngageWindow = 0.6, 60
T.offlineEscapeGain, T.offlineEscapeMax = 1.5, 0.8
-- Robbery (robbery.lua): share of trade goods a pirate demands, seconds to
-- comply, seconds a complying ship is spared afterwards.
T.robberyShare, T.robberyWindow, T.robberySpare = 0.5, 15, 120
-- Distress (distress.lua): how far a stranded ship's call reaches online,
-- seconds between calls, seconds a helper has to deliver, and the share of
-- its normal fuel reserve a stranded ship asks for.
T.distressRange, T.distressRetry, T.distressWindow, T.distressShare = 20000, 30, 120, 0.5
T.distressMinSpare = 3   -- units of fuel a helper must be able to spare
T.offlineStationAccuracy = 0.5   -- turret hit chance offline
T.offlineCivilianBreak, T.offlinePirateBreak, T.offlinePatrolBreak = 0.6, 0.4, 0.3
T.alifeWreckLifetime = 1800
T.population = {
 pirate={minDelay=180,maxDelay=300,target=2},
 trader={minDelay=180,maxDelay=300},
 patrol={minDelay=180,maxDelay=300},
 miner={minDelay=180,maxDelay=300},
 salvager={minDelay=180,maxDelay=300},
}
T.npcWarpDuration = 1.5
T.npcDriverArrivalTime = 20   -- s after leaving a driver lane that an NPC waking up comes in along the rail
T.sleepFar, T.sleepNear, T.sleepEvery = 7000, 6000, 12

-- Berth ship capacity is independent of the authored pad/editor marker size.
T.berthShipScale = 3

-- Hangar bays: cells across and down, and how many pixels of hull length
-- or width one cell stands for (a Wisp is 4 x 2, a Bastion 14 x 5).
T.hangarW, T.hangarH, T.hangarCell = 12, 10, 20
T.repairRate = 6          -- credits per armor point at a station repair bay (station def repairRate overrides)

-- Markets (src/market.lua, data/markets.lua). Credits you start with; the
-- trade grid and a station's shelf, in cells; how long something you sold
-- stays for sale before it's sold on; and how long one more stack takes to
-- come in, by kind (seconds of game time).
T.startCredits = 5000

-- How far the camera zooms out (mouse wheel), as a scale.
T.minZoom = 0.17 / 1.5   -- pulled out with T.mapScale

T.tradeW, T.tradeH = 12, 6
T.marketW, T.marketH = 14, 12
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
	{ key = "flightClockPerAU", label = "Game clock per AU (s)",         min = 0,    max = 1200,  value = 0,     precision = 0 },
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
	{ key = "laneHazardDepth", label = "Moon rock belt minimum depth (px)", min = 8000, max = 60000, value = 24000, precision = 0 },
	{ key = "laneOffroad",     label = "Rocks off-road (per 10k px)",   min = 0,    max = 60,    value = 12,    precision = 0 },
	{ key = "laneDerelicts",   label = "Derelicts (per 100k px)",       min = 0,    max = 10,    value = 1,     precision = 1 },
	{ key = "laneFlow",        label = "Lane speed (px/s)",             min = 300,  max = 12000, value = 6000,  precision = 0 },
	{ key = "laneThrust",      label = "Lane buff: thrust x",           min = 1,    max = 6,     value = 3,     precision = 2 },
	{ key = "laneDrag",        label = "Lane buff: drag x",             min = 0.05, max = 1,     value = 0.25,  precision = 2 },
	{ key = "laneRamp",        label = "Off-road falloff (px)",         min = 0,    max = 8000,  value = 3000,  precision = 0 },
	{ key = "lanePerAU",       label = "Lane length per AU (px)",       min = 2000, max = 100000, value = 50000, precision = 0 },
}
for _, s in ipairs(T.laneSpecs) do T[s.key] = s.value end

function T.resetLane()
	for _, s in ipairs(T.laneSpecs) do T[s.key] = s.value end
end


-- Moons (src/moons.lua): the way out toward a moon is departArc px of the
-- map's edge. Crossing it outward hands off immediately without taking
-- control or zooming the camera. The lane mouth starts rampLead ahead.
T.departArc = 9000
T.rampLead = 1500
-- Past a map's edge (Game:applyBoundary): outward speed bleeds away at up
-- to edgeBrake per second, reaching full strength edgeSoft px out, and a
-- drift of edgeDrift px/s^2 carries you slowly back in.
T.edgeBrake, T.edgeSoft, T.edgeDrift = 1.5, 3000, 40


-- Surface drills emit bounded batches; both online and offline mining share them.
T.drillIntervalMin,T.drillIntervalMax,T.drillCap=2.5,8,18
T.drillStockCap=600 -- a drill stops while its station holds this much of its ore
T.drillRockMin,T.drillRockMax=28,100
-- A drill fires each chunk straight out along its rail, inside a narrow
-- cone (drillSpread, radians either side), and it brakes to a stop in the
-- spoil field drillThrowMin..Max px past the muzzle (speed = distance x
-- damping). Miners wait off to one side of that field (mineWorkSide) and
-- go in once a chunk has settled, so nothing is ever fired at them.
T.drillThrowMin,T.drillThrowMax,T.drillSpread=450,1150,.12
T.miningSettleTime=3
T.mineWorkAltitude=1500
T.mineWorkSide=1100
T.minersPerArea,T.minerLoad,T.miningChunkDamping=2,12,1.1
T.miningOrbitDamping=1.1
T.miningScan,T.miningOfflineEvery=.5,12

-- Bounded saved observations; quiet physical fights end after this interval.
T.historyLimit,T.historyQuietTime=256,5

-- Inventory-fuel prototype. One unit provides this much electrical energy.
T.reactorFuelItem,T.reactorFuelEnergy='deuterium_canister',2500
T.idleDrain=0.5  -- share of modules' standing powerDraw a ship actually pulls
T.turnDrain=0.25 -- share of the main-drive load that turning alone costs
T.fuelEmergency=2
T.orderMinLoad=10   -- the smallest part of a goods order a hauler will take
T.freightCreditsPerUnit=2 -- base payment per delivered unit
T.freightCreditsPerAU=1 -- additional credits per AU per delivered unit
T.reactorFuelStart,T.reactorFuelReserveSeconds=8,600
T.laserReserve=.5 -- laser damage and opacity below the capacitor reserve floor
-- Average throttle of an NPC flying a leg (live flights on Mars, Earth,
-- Saturn and the Belt measured .25-.34): what offline travel is billed at.
T.npcTravelThrottle=.3
-- How far (px) an NPC's own offset from a shared track or holding point can be
T.npcSpread=220
-- Queues at mass drivers and docks (src/queue.lua): how long one ship has the
-- beam (s), and where the line holds: the first spot this far back from the
-- chokepoint along the way in (px), each after it this much further.
T.queueService={driver=10,dock=14}
T.queueStart,T.queueGap=2200,600
T.npcFuelLow=.5 -- NPCs head to refuel below half their reactor reserve
-- ...or sooner, when what's left wouldn't cover the rest of the leg plus the
-- trip to the nearest fuel stop (times the margin, plus slack seconds).
-- Checked every npcFuelRangeCheck seconds of game time.
T.npcFuelRangeMargin,T.npcFuelRangeSlack,T.npcFuelRangeCheck=1.5,60,15
-- Seconds before a ship still short of fuel after a supply stop tries another.
T.npcFuelStopRetry=600
-- Extra gap between an undocking ship and traffic at its launch point.
T.launchClearance=60
-- Physics categories: loose pickups collide with world geometry, not ships.
T.collideShip,T.collidePickup,T.pickupRadius=2,3,6
-- Seconds a dead/escaped NPC record lingers (unreferenced) before removal.
T.alifeGoneLinger=300

T.wreckSteelPerTonne = 1 / 40   -- steel plates a drilled wreck yields, per tonne of hull
T.salvagerPopulation,T.salvagerCollectTime=1,180   -- salvagers fill their hold (src/scavenge.lua)
T.salvagerRange,T.salvagerStay=6000,30

-- Playable area: every planet map's open space (edge, belts, rings,
-- station track) is multiplied by mapScale; loose debris, belts and rings
-- are thinned by mapDensity (1/mapScale^2 keeps rock counts unchanged;
-- lower thins further). Pre-alpha test values.
T.mapScale = 1.5
T.mapDensity = 0.3

-- Idle NPCs that may look for a new job in one simulation tick (src/alife.lua).
T.taskChoosePerTick = 4
return T

