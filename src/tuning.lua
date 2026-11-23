--[[
	Live tuning knobs. Every value here shows up as a slider in the debug
	panel (F1), so flight feel can be tuned while playing. When something
	feels right, copy the number back into the defaults below.
]]

local T = {}

T.specs = {
	{ key = "thrustScale",    label = "Thrust",                 min = 0.2, max = 3,    value = 1,    precision = 2 },
	{ key = "sideScale",      label = "Maneuvering thrusters",   min = 0,   max = 3,    value = 1.5,    precision = 2 },
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
	{ key = "turnResponse",   label = "Turn controller gain",   min = 1,   max = 60,   value = 18,   precision = 1 },
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
-- Rock chips and rare ore (src/rock_chips.lua).
T.chipHp = 4              -- one more hit pops it
T.chipPerRadius = 10      -- a rock sheds one chip per this many px of radius
T.chipMax = 12            -- ...but never more than this many
T.chipLife = 180          -- seconds before a chip nobody collects fades
T.drillOreMult = 2        -- ore from a chip a drill broke, against 1 when shot
T.rareChance = { rock = 0.06, ice = 0.08 }   -- chance a big rock has a gold core, big ice a crystal
T.rareMinRadius = { rock = 55, ice = 30 }    -- only pieces this big carry one (ring ice runs small)
T.rareCovetRange = 6000   -- miners go after loose rare ore this close
-- NPCs detouring for rare ore (src/prospect.lua)
T.prospectRange = 2500    -- how close it has to pass to notice
T.prospectThink = 1.5     -- seconds between looks
T.prospectStandoff = 320  -- a gun's distance from the rock it cuts
T.prospectEager = { miner = 1, pirate = 1, trader = 0.35, patrol = 0, other = 0.35 }
T.prospectOffline = 0.06  -- offline: chance per leg into a belt, for a keen ship
T.rareCore = 0.4          -- the core's size, as a share of the rock's radius
T.rareChipShare = 0.3     -- a chip this much core is rare ore
T.chunkRadius = 14        -- a cut-off piece this big is a rock that chips on
T.cutMin, T.cutMax = 0.15, 0.55   -- how deep one cut goes, as a share of radius
T.wreckShotRecovery = 0.5 -- each cargo unit survives shooting a wreck; drilling preserves all

-- Station storage grid, in 1 m3 cells (every station has its own).
-- default station storage; a station sets its own with storage = { w, h }
T.storageW, T.storageH = 16, 18

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
-- Site ships with nothing to fight drift round their post (src/ai.lua AI.siteIdle)
T.siteWander, T.siteWanderSpeed, T.siteWanderPause = 900, 160, 9
-- What an idle site ship sees (src/ai.lua pickTarget): out to
-- T.siteSightRange inside a cone of +-T.siteSightCone radians off its
-- nose, and T.siteNearSense all round.
T.siteSightRange, T.siteSightCone, T.siteNearSense = 4200, 0.8, 1200
T.siteGroupSize = 3            -- wildcats per group: one aggroing brings the group
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
-- how fast the Heaven-Ladder's ring and elevators turn about Mars, in radians a second. They run
-- against the planet's current (which turns clockwise on screen).
T.elevatorSpin = 0.006
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
T.pickupInstant = 50 -- px from the hull: within this, E takes an item aboard at once
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
-- Legs between stops on one orbit follow it (src/alife.lua followOrbit):
-- a carrot this many radians ahead while the ship is within this fraction
-- of the stop's orbital radius. .2 rad keeps the chord's sag under 0.5%
-- of the radius (400 at Saturn's track, inside the Cassini division).
T.alifeArcStep,T.alifeArcBand=.2,.06
-- a ship woken from the abstract sim starts at no more than this x its cruise
T.alifeWakeSpeed=1
T.alifeGateExit = 2000  -- online ships fly beyond the existing moon gate before transfer
T.alifeSpread = 1500  -- persistent cross-track variation, fading at destinations
T.alifeLocalTick, T.alifeRemoteTick, T.alifeStay = 0.5, 2, 60
T.alifeSweepBudget = 0.00075 -- wall seconds before deferring the rest of an offline batch
T.alifeSweepStep = 1 / 120 -- offline record visits are spread over the tick in steps this long (see Game:updateALife)
T.securityThink, T.securityRange = 0.5, 6000
T.aiSteerEvery, T.aiClearance = 0.2, 12
-- A turn-helm hull slides with no side thrust: past this much speed
-- error across its route it turns its engines onto the error (px/s), and
-- goes back to facing the route once the error is under the release.
T.aiSlideCorrect, T.aiSlideRelease = 80, 30
T.npcDecisionInterval,T.npcControlInterval,T.npcCombatInterval=1,.2,.1
T.npcCruiseInterval=1
T.npcCrowdLook,T.npcCrowdMargin=2,800  -- replan at the combat rate when something solid is within 2 cruise replans of travel (+800px)
T.npcStationClearance=250  -- px beyond a station hull (plus the ship's half length) that traffic routes around
T.npcDockCone,T.npcDockMarker=.35,700  -- dock approach: lined-up cone width per px out; marker distance beyond the hull
T.aiBoostCruise, T.aiBoostStopMargin = 3, 1800
T.aiStationSlowRange, T.aiStationSpeed = 5000, 450  -- dock approach: no burner inside this range, easing down to this speed by half of it
T.patrolInspect, T.pirateLinger = 10, 60
T.patrolDockEvery,T.patrolDockStay,T.patrolStandOff=3,45,450
-- Squads and battlegroups (src/squads.lua)
T.squadTick = 2              -- s between squad upkeep passes
T.policeWage = 1200          -- credits an hour each police ship is paid by its faction
T.squadSweepHold = 20        -- s a squad holds at each stop of its beat
T.squadRespondCount = 2      -- squads sent when a flagship calls
T.squadRespondTime = 180     -- s a called squad stays on the call
T.squadRespondHold = 30      -- s it holds at the call point before checking again
T.squadRegroupArmor = 0.4    -- leader armour share below which the squad goes home
T.squadRegroupStay = 120     -- s a regrouping squad waits at home for recruits
T.squadRegroupTries = 3      -- waits before it goes back out under strength
T.squadHitMemory = 8         -- s a hit on a live ship counts as 'under attack'
T.flagshipRebuild = 1800     -- s before a lost flagship is replaced
T.couriersPerSystem = 1      -- faction couriers per owned planet with a service fleet
T.squadOddsPenalty = 0.15    -- raider's odds lost per ally of its prey in the area
T.npcRepairThreshold,T.npcRepairPerSecond=.7,4
T.stationOpeningCredits=60000 -- what a station's account opens with (src/accounts.lua)
T.factionOpeningCredits=2000000 -- and a faction's
T.factionFlowHours=6 -- half-life of a faction's rolling surplus/deficit (src/accounts.lua A.flow)
T.stationFloor,T.factionFloor=20000,500000 -- accounts pay down to these; past them the faction, then its home economy, pays (src/accounts.lua)
T.factionTax=.35 -- share of a station's takings paid to its faction (stations piled up money while their factions ran down at .25)
T.residentFoodPay=1.5 -- residents pay this multiple of the station's food price for what they eat (src/food.lua)
-- Crew fatigue and shore leave (src/crew_fatigue.lua). Fatigue runs 0..1.
T.fatigueRate=.035          -- fatigue a minute underway (about 20 min from rested to the soft limit)
T.fatigueTransit=1.5        -- times that on an interplanetary crossing
T.fatigueFight=.05          -- added per fight
T.fatigueDamage=.1          -- added per whole hull's worth of armor lost
T.fatigueSoft=.7            -- a captain of middling ambition books shore leave here
T.fatigueAmbitionSpread=.3  -- ambition 0..1 moves that by -/+ half this
T.fatigueHard=.95           -- past this, no new jobs until it has rested
T.restSecondsPerFatigue=260 -- seconds of shore leave a whole unit of fatigue takes (at an ordinary station)
T.restMinStay,T.restMaxStay=60,600
T.restBaseRate=60           -- credits a minute at an ordinary station, for a hull of 4 hangar cells or fewer (bigger hulls pay by the square root of their size)
T.restCrowding=.5           -- price rises this much as resting crews fill the station's places
T.restResidentialPrice,T.restResidentialSpeed=.6,1.5
T.restDepotPrice,T.restDepotSpeed=1.3,.7 -- faction-run depots (hubs, customs houses)
T.restDarkPrice=1.8
T.restHomePrice,T.restHomeSpeed=.5,1.2 -- at the ship's own home station
T.restHomeLoyalty=.5        -- how much a timid captain favours resting at home over a nearer station
T.restTimeValue=.6          -- credits a second of travel to a rest stop is worth, at middling ambition
T.restReserve=200           -- credits a crew keeps back rather than spend on shore leave
T.restHomeXp=1              -- rank experience for a full rest at home (src/npc_rank.lua)
T.fatigueHomeward=.8        -- from this share of its rest threshold a crew favours jobs ending in its home system
T.fatigueAwayPenalty=.5     -- how much a job ending away from home loses, at full fatigue (src/transport.lua)
T.restFoodPerCrew=.5        -- food crates a game hour each resting crew eats (src/station_needs.lua)
T.restWaterPerCrew=.3       -- water tanks a game hour each resting crew drinks
T.resaleMargin=.1 -- a station prices goods it bought in at least this much over their landed cost (src/markets.lua)
T.hubMarkup=.3 -- a logistics hub sells on what it imports at this markup (src/transport.lua)
T.npcStartingCredits=2000 -- what an arriving NPC has left after buying its ship
T.npcSavings=8000 -- over this an NPC refits or trades up its ship more readily (src/npc_refit.lua)
T.npcSupplyRetry=30 -- seconds before rechecking a dockside stock or price shortage
T.npcSupplyReserve=200 -- credits an NPC keeps back when buying ammo and flares
T.npcAmmoThreshold,T.npcAmmoSeconds=.2,10 -- seek supplies below 20%; fallback reserve = 10s of fire
T.pirateLootUnits,T.pirateLootTime,T.pirateLootRange=5,25,3000
T.pirateRetreatHealth,T.pirateRest=.35,30
-- Fencing (piracy.lua): share of its home station's bid a pirate gets for stolen goods
T.pirateFenceRate=.6
-- Raid targeting (piracy.lua P.wants): odds bonus for prey carrying what the raider's home station is short of
T.raidShortageBias=.25
-- Pirate berths (security.lua S.berths): a dark base with a shipyard keeps as
-- many raiders as its fuel stock covers, fuelReserves full reserves each, up to max
T.pirateBerths={max=10,fuelReserves=2}
-- One NPC cruise speed; hulls vary it by at most npcCruiseSpread either way.
T.npcCruise,T.npcCruiseSpread=650,.15
T.npcCruiseReferenceHull='ferrous_mule' -- the hull that cruises at exactly T.npcCruise (stock fit)
T.directLinkAngle=math.pi*.8 -- NPCs fly straight (round the planet) between nodes up to this far apart (at 2/3 pi,
-- two stations just past it with nothing between went the long way round);
-- kept well short of half the planet, where 'which way round' flips frame to frame
T.ramAggroShare=.15 -- a ram this share of max armour (or more) makes the victim hostile
T.npcIdleHomeDelay=60 -- seconds without work before returning to the assigned home station
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
-- Ship losses: the chance a robbed civilian is destroyed anyway, and the
-- chance any other side that breaks off a fight doesn't get away. Lost
-- ships are replaced from the shipyards, which is what keeps ships,
-- modules and ammo selling.
T.pirateScuttleChance, T.offlineBreakKill = 0.5, 0.5
T.alifeWreckLifetime = 1800
-- The fixed fleet (src/arbiter.lua): haulers and miners across the whole
-- system. With ~46 police, the pirate bases' launches and a few couriers,
-- about 300 ships fly.
T.fleet = { hauler = 190, miner = 55 }
T.population = {
 -- pirates have no per-region target: dark bases launch them (T.pirateBerths)
 pirate={minDelay=180,maxDelay=300},
 hauler={minDelay=180,maxDelay=300},
 patrol={minDelay=180,maxDelay=300},
 courier={minDelay=240,maxDelay=420},
 miner={minDelay=180,maxDelay=300},
 hunter={minDelay=300,maxDelay=600},
}
-- Wildcat sites (src/sites.lua Sites.tick, src/wildcats.lua)
-- Sized to the population: wildcat crews plus bounty hunters make up about
-- T.siteShare of the living NPCs. Short of that, a site opens every
-- T.siteSpawnEvery; a world (or save) with none gets its share at once.
T.siteShare = 0.15
T.siteSpawnEvery = 120        -- s between new sites while crews are short of their share
T.sitesPerPlanet, T.sitesMax = 3, 16
T.wildcatSortieEvery = 900    -- s between a posted wildcat's raids (give or take 40%)
T.wildcatSortieTime = 900     -- s a wildcat raids before heading home empty-handed
T.wildcatIdleHome = 120      -- s a wildcat out raiding waits with no raid to take before heading home
T.wildcatSortieHealth = 0.8   -- share of armour a wildcat wants before it goes out
T.wildcatPatchRate = 0.5      -- share of full armour patched per hour at the site
T.hoardFenceAt = 30           -- units of stolen goods on a site's hoard that send one wildcat to fence it
-- Bounties: robberies and kills by a site's wildcats before its system's
-- paying station posts a bounty; each wildcat is then worth this much to
-- whoever lands the last hit (plus a little per point of its hull's armour)
T.bountyLosses = 3
T.bountyPerHead, T.bountyPerArmor = 600, 1
T.bountySlots = 3             -- hunters the board sends at one site at once
T.huntersPerSystem = 3        -- bounty hunters per owned system with a trade station
T.hunterReadyHealth = 0.8     -- share of armour a hunter wants before it takes a bounty
T.hunterBreakKill = 0.3       -- chance a hunter that breaks inside a site doesn't get out
T.hunterAssaultTime = 1800    -- s a hunter stays inside a site before it gives up and pulls out
T.npcWarpDuration = 1.5
T.npcDriverArrivalTime = 20   -- s after leaving a driver lane that an NPC waking up comes in along the rail
T.npcArrivalBeyondEdge = 1500 -- px past the map edge where an NPC off a driver lane comes in, on its origin planet's bearing
T.npcArrivalWidth = 4000     -- px across (and half that deep) the band driver arrivals spread over, by id
T.sleepFar, T.sleepNear, T.sleepEvery = 7000, 6000, 12
T.sleepViewMargin = 1000   -- px past the screen's edge that debris is kept awake (zoomed out)
-- Cloud-city launches: how long the city's beam carries a departing NPC up
-- out of the cloud-top pull at most (Game:cloudClimbing), in seconds.
T.cloudClimbTime = 60
-- and how near a cloud city its inbound traffic is held up the same way (px)
T.cloudHoldRange = 4000

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

T.tradeW, T.tradeH = 12, 10
-- original widths, taller for bigger modules: tall grids scroll
T.marketW, T.marketH = 14, 24
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
T.minersPerArea,T.miningChunkDamping=3,1.1
-- a miner fills its hold before heading home, unless the drill has had no
-- rock for it this long (src/mining.lua)
T.minerIdleReturn=120
T.miningOrbitDamping=1.1
T.miningScan=.5

-- Bounded saved observations; quiet physical fights end after this interval.
T.historyLimit,T.historyQuietTime=256,5

-- Inventory-fuel prototype. One unit provides this much electrical energy.
T.reactorFuelItem,T.reactorFuelEnergy='deuterium_canister',1750
T.idleDrain=0.5  -- share of modules' standing powerDraw a ship actually pulls
T.turnDrain=0.25 -- share of the main-drive load that turning alone costs
T.orderMinLoad=10   -- the smallest part of a goods order a hauler will take
T.orderLotHours=4   -- a buyer orders at least this many hours of its own use at once
T.orderMinFreight=800 -- and an order pays a hauler at least this over an AU (E.minOrder)
T.orderMaxVolume=200 -- cubic metres in one ordinary (not hub-to-hub) order: a median hauler's hold
T.agendaMaxJobs=4     -- most jobs one NPC holds at once (src/npc_agenda.lua)
T.agendaHoldPerJob=80 -- m3 of hold per extra job it may hold
T.freightMinRun=12    -- m3 of freight at a pickup, bound for one area, before haulers fly it
T.unmetShortageAge=300 -- s a buyer stays short before its makers count it as unmet, spare stock elsewhere or not (src/economy.lua)
T.freightMaxWait=600  -- seconds an order waits for a fuller load before any hauler takes it
T.freightCreditsPerM3=10 -- base payment per cubic metre delivered
-- scarcity premium (src/transport.lua): the share of the source-to-target
-- price gap the destination adds to freight pay, growing by 1x per
-- freightUrgencyHours its shortage goes unserved (to freightUrgencyMax),
-- and never more than freightPremiumCap times the base pay
T.freightGapShare=.5
T.freightUrgencyHours=2
T.freightUrgencyMax=2
T.freightPremiumCap=2
-- NPC job scoring (src/transport.lua): reward (credits/s) is capped at
-- freightScoreCap/100, varied per trader by +-freightScoreJitter, and cut
-- by freightRiskPerAU per AU of interplanetary route for timid traders
T.freightScoreCap=20000
-- urgency*10000 + shortage age*100 tops out here (about ten minutes of
-- shortage), so pay stays in the race; see the transport score
T.freightNeedCap=60000
-- The freight board's shared shortlist (src/tasks.lua): rebuilt this often,
-- holding this many orders per system for haulers there and showing this
-- many of each other system's best to everyone else
T.freightCacheSeconds=5
T.freightCacheLocal=16
T.freightCacheRemote=3
T.freightScoreJitter=.1
T.freightRiskPerAU=.05
-- market goods trade at the station's live price +- this share
T.marketSpread=.05
-- station prices (src/markets.lua): never under priceFloor; up to
-- priceCrisisMax once a shortage has gone priceCrisisHours unserved;
-- makers sell makerDiscount under their stock-based price
-- The price rule: a good's list price is (inputs + the recipe's work) x
-- T.priceMargin (src/economy_model.lua flags a recipe whose inputs alone
-- outprice it). A station's price never falls under cost plus 10%
-- (priceFloor = 1.10 / priceMargin of list), and climbs to about three
-- times cost (priceCrisisMax) once a shortage goes unserved.
T.priceMargin=1.35
T.priceFloor=1.10/1.35
T.priceCrisisHours=2
T.priceCrisisMax=2.2
T.makerDiscount=.1
-- merchant houses (src/merchants.lua): how often they trade; a house
-- under merchantBankrupt of its capital that has sold nothing for
-- merchantStale seconds turns insolvent, sells at anything over
-- merchantFireSale x list, and recovers at merchantRecover of capital
T.merchantTick=300
T.merchantBankrupt=.1
T.merchantStale=6*3600
T.merchantFireSale=1
T.merchantRecover=.3
-- the markup a house wants over what it paid before it will sell
T.merchantMargin=.15
-- the most of one good a house buffers at its hub warehouse
T.merchantBuffer=3000
-- the most unclaimed freight jobs one house keeps posted at once
T.merchantOpenMax=12
-- a house stops buffering surplus below this share of its capital
T.merchantReserve=.5
-- a globalPrice plant (crack_ice) speeds up while the universal price of
-- its good is this far over list, and slows while it's this far under
T.globalPriceBand=.1
-- adaptive plants (fuel, canisters...) speed up while all trade stations
-- together hold less than this many times their combined target
T.adaptiveCushion=1.5
-- guided munitions: offline a rack fires one load of its tubes every
-- offlineSalvoRounds combat rounds; NPCs carry npcMissileSalvos tube loads
T.offlineSalvoRounds=3
T.npcMissileSalvos=6
-- freight pay also covers the cargo's worth: this share of its value
-- (live market price, else list) per unit carried
T.freightValueShare=.05
T.freightCreditsPerM3AU=6 -- additional credits per cubic metre per route AU
T.freightHandling=200 -- once per shipment; partial orders earn a proportional share
T.freightListingSeconds=30 -- public listing before NPC reservation
T.trunkLot=250     -- cubic metres per hub-to-hub trunk order: a full load for a trunk freighter
T.trunkMinHold=250 -- hold a ship needs to take trunk runs
T.trunkMinOrders=4 -- a trunk run waits for this many ordinary order lots (E.minOrder)
T.playerFirstLookSeconds=180 -- orders placed at the station you're docked at wait this long for you before NPCs may take them
T.satJobPlayerFirst=600     -- s a satellite launch/refuel job is offered to the player before haulers may take it
-- Station jobs (src/quests.lua): player work the shared freight board
-- can't express (rescues, satellite and site jobs, ore contracts).
T.questSlots=3           -- open station jobs per station
T.questMaxActive=3       -- station jobs the player can hold at once
T.questOfferLife=1800    -- an unaccepted job is withdrawn after this
T.questDeadline=3600     -- time to finish once accepted
T.questMaxVolume=60      -- m3 asked for in one ore contract
T.questTick=60
T.questKindMax=2         -- open offers of one kind per station
T.questCooldown={rescue=120,ore_delivery=300} -- per station, after posting that kind
T.questWeights={rescue=2,sat_launch=2,sat_refuel=2,ore_delivery=1} -- default order when the arbiter can choose; a location's questWeights overrides
T.questStanding=2        -- giver faction standing for a finished job
T.questFailStanding=1    -- and lost for a failed or abandoned one
T.rescueMinAge=60        -- stranded this long before a station posts the rescue
T.rescueBase=300         -- flat rescue pay, plus the fuel's worth below
T.rescueFuelMultiple=3
T.rescueRange=2500       -- px: you count as the rescuer if you were this close
T.rescueCredit=120       -- s: ...this recently when it stopped being stranded
T.rescueDeadline=1800
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
T.salvagerCollectTime=180   -- salvage jobs fill the hold (src/scavenge.lua)
T.salvagerRange,T.salvagerStay=6000,30
T.wreckBountyBase=80       -- CR a system's trade station pays for each ship wreck cleared (src/wreck_bounty.lua)
T.wreckBountyPerSteel=4    -- plus this per steel plate in the hull
T.oreQuestPremium=1.3       -- ore contracts (src/ore_quests.lua) pay this multiple of the station's price
T.oreQuestMin=5            -- and are only posted for at least this many units short
T.oreQuestReserve=40       -- ore a drill home always wants on hand, even one that ships it all on
T.minerOrePay=.6           -- share of the station's ore price an NPC miner is paid on delivery (src/mining.lua)

-- Playable area: every planet map's open space (edge, belts, rings,
-- station track) is multiplied by mapScale; loose debris, belts and rings
-- are thinned by mapDensity (1/mapScale^2 keeps rock counts unchanged;
-- lower thins further). Pre-alpha test values.
T.mapScale = 1.5
-- rad/s: stations outside a planet's well tumble whole, core and all, at
-- one of these rates (src/fields.lua place.drift); a turn every 3-5 minutes
T.freeStationDrift = { 0.022, 0.03, 0.018 }
T.darkCrossingAU = 8      -- extra AU the economy counts on a supply run between the white and dark networks
T.darkCrossingMarkup = 0.5 -- the same, as a price markup, for priced commodities
T.fenceStock = 300 -- m3 of each dark surplus good a fence keeps in its back room to sell on
-- Dark runners (src/dark_runners.lua): white haulers who sign on with
-- Milliways while dark freight goes unclaimed, and quit when it dries up.
T.darkRunnerHome = 'station:pluto_1'
T.darkRecruitWait = 300   -- s dark orders sit unclaimed before haulers sign on
T.darkRecruitEvery = 120  -- s between rounds of recruiting
T.darkRecruitBatch = 4    -- at most this many sign on in a round
T.darkOrdersPerRunner = 4 -- one more runner for every this many orders waiting
T.darkRetireIdle = 7200   -- s without dark work before a runner goes straight
T.darkRunnerMax = 40
T.mapDensity = 0.3

-- Idle NPCs that may look for a new job in one simulation tick (src/alife.lua).
T.taskChoosePerTick = 4

-- Residential stations and passenger contracts (src/passengers.lua).
-- Demand is a rule, not a population: a station's open passenger
-- contracts (accepted ones still waiting for pickup included) are capped
-- at population / passengerResidentsPerContract, between 1 and
-- passengerMaxOutstanding. Each station posts at most one contract per
-- passengerInterval, staggered by station.
T.passengerInterval=300
T.passengerResidentsPerContract=1000
T.passengerMaxOutstanding=6
T.passengerExpiry=1800      -- an unaccepted contract is withdrawn after this
T.passengerMaxParty=8       -- largest party (one climate cell a passenger)
T.passengerReturnShare=.4   -- share of workplace trips that run back home
-- Fare: per passenger, base + perAU x route AU, then a comfort premium
-- (up to passengerComfortMax at comfort 1) and a speed incentive (up to
-- passengerSpeedMax for the fastest cruise, scaled by the share of the
-- journey the ship's own speed actually shortens: driver legs take the same
-- time for everyone). Both lock when the contract is accepted.
T.passengerFareBase=60
T.passengerFarePerAU=40
T.passengerComfortMax=.4
T.passengerSpeedMax=.25
T.passengerPodComfort=.3    -- a Climate Pod with no comfort of its own
T.passengerHoldComfort=.6   -- a hull's climate compartment with none of its own
return T
