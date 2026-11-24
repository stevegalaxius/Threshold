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
end
