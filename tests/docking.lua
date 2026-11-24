return function()
	local Game = require("src.game")
	local Ship = require("src.ship")
	local AI = require("src.ai")
	local T = require("src.tuning")
	local game = Game.new({ preview = true })
	game.world:destroy()
	game.world = love.physics.newWorld()
	game.entities, game.player, game.well, game.alifeOnline = {}, nil, nil, {}
	local peak = 0
	game.world:setCallbacks(function(...)
		game:beginContact(...)
		for _, hit in pairs(game.contacts) do
			if hit.a.kind == "station" and hit.b.kind == "ship"
				or hit.b.kind == "station" and hit.a.kind == "ship" then
				peak = math.max(peak, hit.v)
			end
		end
	end, nil, function(...) game:preSolveContact(...) end)

	local station = game:spawnStation("shipyard_1", 0, 0, .03, false, "station:earth_3")
	station.body:setAngle(0)
	station.body:setAngularVelocity(.03)
	station.body:setLinearVelocity(130, 95)
	local dock = station.dock
	local function spawn(hull, lx, ly, inward)
		local x, y = game.dockWorld(station, 1, lx, ly, dock)
		local nose = game.dockAngle(station, 1, dock) + math.pi
		local ship = Ship.new(game, { hull = hull, x = x, y = y, angle = nose, team = 3 })
		ship.def = { ai = { style = "civilian", throttle = 1 } }
		ship.route = { station }
		local vx, vy = station.body:getLinearVelocityFromWorldPoint(x, y)
		ship.body:setLinearVelocity(vx + math.cos(nose)*inward, vy + math.sin(nose)*inward)
		table.insert(game.entities, ship)
		return ship
	end

	local arrival = spawn("intaki_wisp", 3600, 190, 300)
	local waiting = spawn("intaki_wisp", 4600, -80, 300)
	local wx, wy = game.dockWorld(station, 1, dock.x2 + 320, 5, dock)
	local wreck = game:spawnHusk(arrival, wx, wy, station.body:getAngle(), 0, 0, 0)
	wreck.body:setLinearVelocity(station.body:getLinearVelocityFromWorldPoint(wx, wy))
	local hold = wreck.hold
	assert(game:launchBlocker({dockState={station=station,dock=dock},halfLength=arrival.halfLength}) == wreck,
		"departure scan missed a wreck ahead of the launch point")
	local ships = { arrival, waiting }
	local sawBeam, sawQueue, cleared = false, false, false
	local dt = 1/120
	local function simulate(seconds)
		for i = 1, seconds * 120 do
			game.time = game.time + dt
			game.universe.clock = game.universe.clock + dt
			local before = {}
			for _, ship in ipairs(ships) do
				local x, y = ship.body:getPosition()
				before[ship] = {x, y}
				local ds = ship.dockState
				if ds then
					if not ds.done then game:updateDockedShip(ship, dt) end
				else
					if i%8 == 1 then
						ship.dockRequest, ship.dockTarget = nil, nil
						AI.trade(game, ship, dt*8)
					end
					Ship.fly(ship, dt)
				end
			end
			game:updateWreckClear(dt)
			game:updateDocking(dt)
			game.world:update(dt)
			game:resolveContacts()
			for _, ship in ipairs(ships) do
				assert(not ship.dead, "docking ship died")
				local ds = ship.dockState
				local x, y = ship.body:getPosition()
				assert((x-before[ship][1])^2 + (y-before[ship][2])^2 < 30^2, "ship jumped during docking")
				if ds and ds.phase == "tractor" then
					assert(ship.body:isActive(), "tractor disabled the ship's physics")
					sawBeam = true
				end
			end
			if arrival.dockState and not arrival.dockState.done and not waiting.dockState then sawQueue = true end
			if wreck.wreckClear then cleared = true end
			local done = true
			for _, ship in ipairs(ships) do done = done and ship.dockState and ship.dockState.done end
			if done then return end
		end
		error("docking did not complete")
	end
	simulate(70)
	assert(sawBeam and sawQueue, "arrival and queue did not exercise tractor clearance")
	assert(cleared and not wreck.wreckClear and wreck.hold == hold and not wreck.dead,
		"wreck did not clear with its cargo intact")

	local hauler = spawn("ferrous_bison", 4400, 1600, 680)
	ships = { hauler }
	simulate(100)
	assert(hauler.dockState.berth, "long hauler did not use an exterior berth")
	assert(peak <= T.ramGrace, ("dock impacts reached %.1f px/s"):format(peak))
	local player = spawn("intaki_wisp", dock.x2 + dock.runway, dock.hw * 1.5, 0)
	game.player = player
	game:updateDocking(dt)
	assert(player.dockState and player.dockState.phase == "tractor", "player missed the wider beam")
	player.body:setPosition(game.dockWorld(station, 1, dock.x2 + dock.runway * 1.5, 0, dock))
	game:updateDockedShip(player, dt)
	assert(not player.dockState and player.body:isActive(), "player could not leave the beam")

	game.world:destroy()
	print("ok  docking: continuous tractor, queued arrival, long hauler and runway wreck")

	-- An actual A-Life record waking at the end of its offline leg used to
	-- start with a legacy tractor state and immediately back out of the dock.
	local live = Game.new({ preview = true })
	live.autosaveOff = true
	local ferrous = live:locationEntity("station:earth_3")
	live.player.body:setPosition(live.dockWorld(ferrous, 1, 5150, 2300, ferrous.dock))
	live.player.body:setLinearVelocity(ferrous.body:getLinearVelocity())
	local clock = live.universe.clock
	local record = {
		id = "npc/90000", state = "travel", area = "earth", home = "earth",
		route = { "station:earth_1", ferrous.locationId }, index = 2,
		depart = clock - 20, arrive = clock, speed = 600,
		ship = Ship.record(live.player),
		action = { kind = "dock", fromJob = true, lastClock = clock,
			target = { provider = "location", id = ferrous.locationId } },
	}
	live.universe.npcs[record.id] = record
	local incoming = require("src.alife").wake(live, record)
	local x, y = incoming.body:getPosition()
	local sx, sy = ferrous.body:getPosition()
	local clearRadius = AI.hullRadius(ferrous) + incoming.halfLength
	assert(not incoming.dockState and (x - sx)^2 + (y - sy)^2 > clearRadius^2,
		"offline arrival woke inside the runway without clearance")
	for _ = 1, 22*120 do
		live:step(dt)
		assert(not incoming.dead and not incoming.removed, "woken arrival was lost")
		local ds = incoming.dockState
		assert(not ds or ds.guided ~= "abort", "woken arrival aborted its first approach")
		if ds and ds.done then break end
	end
	assert(incoming.dockState and incoming.dockState.done and record.state == "docked",
		"woken arrival did not finish docking through the live NPC controller")
	live.world:destroy()
	print("ok  docking: offline Ferrous arrival wakes outside and docks in the live simulation")
end
