return function()
	local Game = require("src.game")
	local Ship = require("src.ship")
	local Queue = require("src.queue")
	local game = Game.new({ preview = true })
	game.autosaveOff = true
	local shipRecord = Ship.record(game.player)
	game.world:destroy()
	game.world = love.physics.newWorld()
	game.entities, game.player, game.alifeOnline = {}, nil, {}
	local station = game:spawnStation("shipyard_1", 0, 0, 0, false, "station:earth_3")
	station.body:setAngularVelocity(0)
	local dock = station.dock
	local function makeShip()
		return Ship.new(game, { hull = "intaki_wisp", x = 0, y = 0, angle = 0 })
	end

	local old = makeShip()
	old.body:setPosition(game.dockWorld(station, 1, dock.x2 + dock.runway, 0, dock))
	old.body:setActive(false)
	old.dockState = { phase = "npcBerth", station = station, dock = dock, t = 408 }
	game.entities[#game.entities + 1] = old
	local x, y = old.body:getPosition()
	assert(Queue.dockBusy(game, station, dock))
	game:updateDockedShip(old, 1/120)
	local nx, ny = old.body:getPosition()
	assert(not old.dockState and old.body:isActive() and x == nx and y == ny,
		"obsolete docking state did not release the ship at its saved pose")
	assert(not Queue.dockBusy(game, station, dock))
	game:remove(old)

	local launch = makeShip()
	game.entities[#game.entities + 1] = launch
	assert(game:dockInstantly(launch, station))
	local origin = dock.x2 + launch.halfLength + 60
	local wx, wy = game.dockWorld(station, 1, origin + dock.runway*.85, 5, dock)
	local wreck = game:spawnHusk(launch, wx, wy, game.dockAngle(station, 1, dock), 0, 0, 0)
	wreck.body:setLinearVelocity(station.body:getLinearVelocityFromWorldPoint(wx, wy))
	local hold = wreck.hold
	assert(game:launchBlocker(launch) == wreck, "launch clearance missed a wreck down the runway")
	game:clearRunway(launch, wreck)
	for _ = 1, 25*120 do
		game.time = game.time + 1/120
		game:updateDebrisClear(1/120)
		game.world:update(1/120)
		if not wreck.debrisClear then break end
	end
	assert(not wreck.debrisClear and not game:launchBlocker(launch) and wreck.hold == hold,
		"tow did not clear the runway with the same wreck and hold")

	local occupant = makeShip()
	occupant.body:setPosition(game.dockWorld(station, 1, dock.x2 + dock.runway*.6, 0, dock))
	game.entities[#game.entities + 1] = occupant
	game:beginDocking(occupant, station, 1, dock)
	local clock = game.universe.clock
	local function arrival(id)
		local record = {
			id = id, state = "travel", area = "earth", home = "earth",
			route = {"station:earth_1", station.locationId}, index = 2,
			depart = clock - 20, arrive = clock, speed = 600, ship = shipRecord,
			action = { kind = "dock", target = { provider = "location", id = station.locationId } },
		}
		game.universe.npcs[id] = record
		return require("src.alife").wake(game, record)
	end
	local a, b = arrival("npc/90000"), arrival("npc/90001")
	local ax, ay = a.body:getPosition()
	local bx, by = b.body:getPosition()
	assert(not a.dockState and not b.dockState and Queue.dockBusy(game, station, dock),
		"offline arrivals took an occupied runway")
	assert(not game:inTractorZone(station, ax, ay) and not game:inTractorZone(station, bx, by)
		and (ax-bx)^2 + (ay-by)^2 > (a.halfLength + b.halfLength)^2,
		"offline arrivals materialized in the runway or on top of one another")
	local record = {
		id = "npc/90002", state = "travel", area = "earth", home = "earth",
		route = {station.locationId, "station:earth_1"}, index = 2,
		depart = clock, arrive = clock + 20, speed = 600, ship = shipRecord,
		action = { kind = "dock", target = { provider = "location", id = station.locationId } },
	}
	game.universe.npcs[record.id] = record
	local departing = require("src.alife").wake(game, record)
	assert(departing.dockState and departing.dockState.resumeDeparture == 2,
		"offline departure launched into the occupied runway")
	game:remove(occupant)
	game:updateDockedShip(departing, 1/120)
	assert(not departing.dockState and departing.routeIndex == 2 and record.state == "travel",
		"queued departure lost its original leg")
	-- The first ship retains priority while the following ship can fly
	-- toward a nearby slot outside the beam, even without offline bookings.
	local Approach = require("src.dock_approach")
	station.body:setLinearVelocity(0, 0)
	local stageX, stageY = assert(Approach.stagingPoint(game, b, station, 1, dock, 1, 1))
	assert(not game:inTractorZone(station, stageX, stageY), "staging spot is inside the tractor zone")
	a.body:setPosition(game.dockWorld(station, 1, dock.x2 + dock.runway, 0, dock))
	b.body:setPosition(stageX, stageY)
	departing.dockExit = nil
	game:remove(departing)
	game.universe.clock = clock + 1
	local waiting, place, busy = Queue.holding(game, b, station)
	assert(not Queue.holding(game, a, station) and waiting and place == 2 and not busy,
		"staging changed the live arrival order")
	require("src.ai").trade(game, b, 1/120)
	local aim = b.navAim
	assert((aim.sx-stageX)^2+(aim.sy-stageY)^2 < 1, "next arrival did not steer toward staging")

	-- A passing ship on an unrelated route can cross the final leg.
	a.body:setPosition(stageX + 200, stageY + 400)
	a.body:setLinearVelocity(0, -400)
	assert(Queue.crossing(game, b, station, stageX + 600, stageY, 200), "missed crossing traffic")
	a.body:setLinearVelocity(0, 400)
	assert(not Queue.crossing(game, b, station, stageX + 600, stageY, 200), "held for traffic moving away")
	-- A queued station stop can still be on another map and have no
	-- local physics body when the route controller runs.
	local remote = makeShip()
	remote.alifeId = "npc/90003"
	local remoteRecord = {
		id = remote.alifeId, state = "travel", area = "earth",
		route = {station.locationId, "station:mars_1"}, index = 2,
		queue = {key = "station:mars_1", kind = "dock", at = clock, ready = clock + 20},
	}
	game.universe.npcs[remote.alifeId] = remoteRecord
	remote.def = { ai = { style = "civilian", throttle = 1 } }
	local ALife = require("src.alife")
	ALife.bindRoute(game, remote, remoteRecord)
	local remoteStop = remote.route[remote.routeIndex]
	assert(remoteStop.kind == "station" and not remoteStop.body.getFixtures and Queue.holding(game, remote, remoteStop),
		"remote station test must exercise queue spacing without a physics body")
	require("src.ai").trade(game, remote, 1/120)
	assert(remote.navAim and remote.navAim.stop == remoteStop.locationId, "remote station route lost its queue target")
	game.world:destroy()
	print("ok  dock traffic: legacy save release, full departure lane and separate arrivals")
end
