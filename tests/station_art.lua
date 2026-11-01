-- Focused integration check and visual captures: love . --stationtest
return function(game)
	local Render = require("src.render")
	local Export = require("src.editor.export")
	local Hold = require("src.inventory.hold")
	local checks = 0
	local function check(ok, message) assert(ok, message); checks = checks + 1 end
	local function find(id)
		for _, e in ipairs(game.entities) do
			if e.kind == "station" and e.def.id == id then return e end
		end
	end
	local function capture(name, x, y, zoom)
		game.camera.x, game.camera.y, game.camera.zoom = x, y, zoom
		game.camera.backgroundX, game.camera.backgroundY = 0, 0
		local canvas = love.graphics.newCanvas(1280, 720)
		love.graphics.setCanvas(canvas)
		Render.world(game)
		love.graphics.setColor(0.8, 0.9, 1)
		love.graphics.print(name, 20, 20)
		love.graphics.setCanvas()
		canvas:newImageData():encode("png", name .. ".png")
	end
	game.autosaveOff = true
	game:loadField("mars")
	local st = find("heaven_ladder")
	check(st and #st.docks == 2, "Heaven-Ladder needs two docks on one station")
	check(st.key == "mars/3", "existing station save keys shifted")
	check(game:findStation("mars/1").name == "Station Alpha", "Station Alpha changed identity")
	check(game:findStation("mars/2").name == "Station Beta", "Station Beta changed identity")
	check(st.body:getAngularVelocity() == 0 and not st.orbit, "elevator terminals must remain stationary")
	check(st.ring.body:getAngularVelocity() * game.well.swirl < 0, "ring must counter-rotate")
	check(st.ring.ringWidth >= 250, "ring is not substantially thicker")
	check(#st.elevatorTracks == 2, "Mars should have two elevator tethers")
	check(Hold.placeStack(game:stationRecord(st).storage, { id = "scrap", n = 1 }), "could not seed station storage")
	local shared = game:stationRecord(st)
	for i = 1, 2 do
		local d = st.docks[i]
		game:dockInstantly(game.player, st, d)
		check(game:stationRecord(game.player.dockState.station) == shared, "terminals do not share storage")
		check(game:stationMarket(st) == game:stationMarket(game.player.dockState.station), "terminals do not share a market")
		game:playerDocked(st)
		local state = game:saveState()
		check(state.player.at.dock == i and state.home.dock == i, "save lost dock identity")
		game:loadState(state)
		st = find("heaven_ladder")
		shared = game:stationRecord(st)
		check(Hold.totals(shared.storage).scrap == 1, "shared storage did not survive reload")
		check(game.player.dockState.dock == st.docks[i], "reload used the other terminal")
		game:undock()
		local d2 = st.docks[i]
		local px, py = game.player.body:getPosition()
		local lx, ly = game.dockLocal(st, 1, px, py, d2)
		check(lx > d2.x2 and math.abs(ly) < 1, "undock exited from the wrong terminal")
	end
	-- Changing ships and respawning at the western terminal must not move
	-- the player across the planet to the default eastern dock.
	game:dockInstantly(game.player, st, st.docks[2])
	game:playerDocked(st)
	check(game:addToHangar(st, "halcyon_wisp") ~= nil, "could not add shared hangar ship")
	check(game:flyFromHangar(1), "could not switch ships in the shared hangar")
	check(game.player.dockState.dock == st.docks[2], "hangar ship swap changed terminals")
	game.state = "dead"
	game:respawn()
	check(game.player.dockState.dock == st.docks[2], "respawn changed terminals")
	game:undock()
	-- Its editable stationary layout still round-trips through the Shipyard.
	local layout = Export.stationDef(Export.fromStation(st.def.id))
	local docks = 0
	for _, part in ipairs(layout.parts) do if part.dock then docks = docks + 1 end end
	check(docks == 2, "editor export lost an elevator dock")
	-- Simulate an actual tractor approach to each terminal with the normal
	-- docking/gravity code. Beam assistance is tested rather than teleporting.
	game:clearEnemies()
	for i = 1, 2 do
		local p, d = game.player, st.docks[i]
		p.dockState, p.dockCooldown = nil, 0
		p.body:setActive(true)
		local x, y = game.dockWorld(st, 1, d.x2 + p.halfLength + 180, 0, d)
		p.body:setPosition(x, y)
		p.body:setAngle(game.dockAngle(st, 1, d) + math.pi)
		p.body:setLinearVelocity(0, 0)
		p.intent.thrust, p.intent.strafe, p.intent.boost = 0, 0, false
		game:updateDocking(1 / 120)
		check(p.dockState and p.dockState.dock == d, "tractor selected wrong terminal")
		for _ = 1, 1200 do
			game:step(1 / 120)
			if p.dead or (p.dockState and p.dockState.done) then break end
		end
		check(not p.dead and p.dockState and p.dockState.done, "could not dock at terminal " .. i)
		game:undock()
	end
	for _, d in ipairs(st.docks) do
		local x, y = game.dockWorld(st, 1, d.x2 + 200, 0, d)
		local trader = game:spawnEnemy("runner_trader", x, y)
		trader.route, trader.routeIndex = { st }, 1
		game:updateDocking(1 / 120)
		check(trader.dockState and trader.dockState.dock == d, "incoming trader could not use an elevator terminal")
	end
	local angle = st.ring.body:getAngle()
	local spin = st.ring.body:getAngularVelocity()
	for _ = 1, 120 do game:step(1 / 120) end
	check(math.abs(st.ring.body:getAngle() - angle - spin) < 0.001, "belt collision body is not rotating with the art")
	check(math.abs(st.body:getAngle()) < 0.001, "fixed dock rotated with the belt")
	capture("mars-ring-overview", 0, 0, 0.027)
	local d = st.docks[1]
	local x, y = game.dockWorld(st, 1, d.x2 - 100, 0, d)
	capture("mars-elevator-terminal", x - 400, y, 0.35)
	game:loadField("mercury")
	st = find("mercury_elevator")
	check(st and #st.docks == 1, "Mercury needs one elevator dock")
	check(st.key == "mercury/3", "Mercury station save keys shifted")
	check(#st.elevatorTracks == 1 and not st.ring, "Mercury should have a standalone elevator")
	check(st.body:getAngularVelocity() == 0, "Mercury elevator must stay anchored")
	check(st.def.id ~= layout.id and st.def.parts[1].shape[2] ~= layout.parts[1].shape[2], "Mercury reused Mars's art")
	local ringCount = 0
	for _, e in ipairs(game.entities) do if e.panels then ringCount = ringCount + 1 end end
	check(ringCount == 0, "Mercury acquired an orbital ring")
	game:dockInstantly(game.player, st)
	local state = game:saveState()
	game:loadState(state)
	check(game.player.dockState.station.def.id == "mercury_elevator", "Mercury elevator save/load failed")
	capture("mercury-elevator-overview", 0, -700, 0.05)
	st = find("mercury_elevator")
	local x2, y2 = game.dockWorld(st, 1, st.dock.x2 - 100, 0)
	capture("mercury-elevator-terminal", x2, y2 + 250, 0.35)
	print(("station art: %d checks passed; four screenshots saved to %s"):format(checks, love.filesystem.getSaveDirectory()))
end
