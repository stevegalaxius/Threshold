return function()
	local Game = require("src.game")
	local Ship = require("src.ship")
	local game = Game.new({ preview = true })
	game.autosaveOff = true
	game.world:destroy()
	game.world = love.physics.newWorld()
	game.entities, game.player, game.well = {}, nil, nil
	local station = game:spawnStation("shipyard_1", 0, 0, 0, false, "station:earth_3")
	station.body:setAngularVelocity(0)
	station.body:setLinearVelocity(0, 0)
	local dock = station.dock
	local dt = 1/120
	local function shipAt(lx, ly, player, heading)
		local x, y = game.dockWorld(station, 1, lx, ly, dock)
		local e = Ship.new(game, { hull = "intaki_wisp", x = x, y = y, angle = heading, team = 3 })
		e.isPlayer = player
		if player then game.player = e else e.route = {station} end
		game.entities[#game.entities + 1] = e
		return e
	end
	local outward = game.dockAngle(station, 1, dock)
	local function step(e, thrust)
		game.time = game.time + dt
		if e.dockState then
			if e == game.player and e.dockState.phase == "tractor" then
				local x, y = e.body:getPosition()
				e.intent.thrust, e.intent.boost = thrust or 0, thrust ~= nil
				e.intent.aimX, e.intent.aimY = x + math.cos(outward)*500, y + math.sin(outward)*500
				Ship.fly(e, dt)
			end
			game:updateDockedShip(e, dt)
		end
		game.world:update(dt)
	end

	local player = shipAt(dock.x2 + dock.runway*1.5, 0, true, outward)
	game:updateDocking(dt)
	assert(player.dockState and player.dockState.phase == "tractor", "player missed the enlarged runway")
	for _ = 1, 6*120 do
		step(player, 1)
		if not player.dockState then break end
	end
	assert(not player.dockState and player.dockCooldown > 0 and player.body:isActive(),
		"player could not escape the beam under thrust")
	game:remove(player)
	game.player = nil

	local npc = shipAt(dock.x2 + dock.runway*1.4, dock.hw*2.1, false, outward+math.pi)
	local px, py = game.dockWorld(station, 1, dock.x2 + dock.runway*1.4, dock.hw, dock)
	local wall = love.physics.newBody(game.world, px, py, "static")
	love.physics.newFixture(wall, love.physics.newCircleShape(35))
	game:updateDocking(dt)
	assert(not npc.dockState, "wide capture locked through a solid obstacle")
	wall:destroy()
	game:updateDocking(dt)
	assert(npc.dockState and npc.dockState.phase == "tractor" and npc.body:isActive(),
		"NPC missed the shared wide capture envelope")
	for _ = 1, 18*120 do
		step(npc)
		assert(npc.dockState, "unobstructed NPC escaped the tractor")
		if npc.dockState.done then break end
	end
	assert(npc.dockState.done and npc.bay, "NPC did not reach the hangar")

	player = shipAt(dock.x2 + dock.runway*2, 0, true, outward)
	local berth = assert(game:freeBerth(station, player))
	local pose = assert(game:berthPose(station, berth, player.hull.id))
	local a = math.rad(pose.heading)
	player.body:setPosition(station.body:getWorldPoint(pose.x + math.cos(a)*440, pose.y + math.sin(a)*440))
	player.body:setAngle(station.body:getAngle()+a)
	game:updateDocking(dt)
	assert(player.dockState and player.dockState.berth == berth and player.dockState.phase == "tractor"
		and player.body:isActive(), "exterior capture did not use the live beam")
	for _ = 1, 15*120 do
		step(player)
		if player.dockState and player.dockState.done then break end
	end
	assert(player.dockState and player.dockState.done and player.dockState.berth == berth,
		"player did not reach the exterior berth")
	-- A replan inside the station's broad hull circle should keep an
	-- already lined-up ship on the exterior approach.
	game:remove(player)
	game.player = nil
	local inbound = shipAt(dock.x2 + dock.runway*2, 0, false, outward)
	inbound.body:setPosition(station.body:getWorldPoint(pose.x+math.cos(a)*400, pose.y+math.sin(a)*400))
	inbound.dockApproach = { stop = station, dock = dock, berth = berth, refresh = -1 }
	local planned = require("src.dock_approach").plan(game, inbound, station, dock)
	assert(planned.berth == berth and #planned.pts == 2, "berth replan sent a lined-up ship back outside")
	game.world:destroy()
	print("ok  tractor: wide capture, powered escape, NPC hangar and player berth")
end
