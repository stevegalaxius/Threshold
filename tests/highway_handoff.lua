-- Regression checks for scene identity and screen-space continuity at both ends.
return function(game)
	local Fields = require("src.fields")
	local Render = require("src.render")
	local checks = 0
	local function check(ok, message) assert(ok, message); checks = checks + 1 end
	local function near(a, b) return math.abs(a - b) < 0.001 end
	local function screen(camera, body)
		return camera:toScreen(body:getPosition())
	end

	local function capture(name)
		local w, h = love.graphics.getDimensions()
		local canvas = love.graphics.newCanvas(w, h)
		love.graphics.setCanvas(canvas)
		Render.world(game)
		love.graphics.setCanvas()
		canvas:newImageData():encode("png", name .. ".png")
	end

	game:loadField("earth")
	game.autosaveOff = true
	local originalWorld, originalEntities = game.world, game.entities
	local station
	for _, e in ipairs(game.entities) do if e.kind == "station" then station = e break end end
	game:spawnPickup(800, 900, "scrap", 1)
	local pickup = game.pickups[#game.pickups]
	game.player.body:setPosition(game.arenaRadius - 100, 0)
	game.player.body:setLinearVelocity(800, 0)
	game.camera.x, game.camera.y = game.player.body:getX() + 120, 80
	game:spawnAsteroid(game.player.body:getX() - 500, 400, 140, "rock")
	capture("turnaround-before")
	local sx, sy = screen(game.camera, station.body)
	local bx = game.camera.x + (game.camera.backgroundX or 0)
	game:launchTrip("luna", { bearing = 0, length = Fields.moons.luna.gap })
	local origin = game.trip.originScene
	check(origin.world == originalWorld and origin.entities == originalEntities, "departure map was rebuilt")
	check(not station.body:isDestroyed(), "departure station was destroyed")
	capture("turnaround-highway")
	Render.world(game)
	local tx, ty = screen(origin.camera, station.body)
	check(near(sx, tx) and near(sy, ty), "departure scene jumped on screen")
	check(near(bx, game.camera.x + (game.camera.backgroundX or 0)), "departure starfield jumped")
	game.player.body:setLinearVelocity(-800, 0)
	game.player.body:setAngularVelocity(0.25)
	game:updateLane(1 / 120)
	check(game.pendingArrive == "back", "cannot turn back before reaching highway mouth")
	game.pendingArrive = nil
	game:arrive(true)
	check(game.world == originalWorld and game.entities == originalEntities, "turnaround regenerated departure map")
	check(game.pickups[#game.pickups] == pickup, "turnaround discarded original salvage")
	local rx, ry = screen(game.camera, station.body)
	check(near(rx, sx) and near(ry, sy), "turnaround moved the camera relative to the station")
	check(near(game.player.body:getAngularVelocity(), 0.25), "turnaround reset ship spin")
	check(near(bx, game.camera.x + (game.camera.backgroundX or 0)), "turnaround starfield jumped")
	capture("turnaround-after")

	-- Arrival uses the exact preview bodies, with no fresh random placement
	-- or avoidance teleport. Cover a moon, a mining station and a planet.
	for _, target in ipairs({ "luna", "phobos", "pluto" }) do
		game:loadField(target == "phobos" and "mars" or "earth")
		if target == "pluto" then game:launchTrip(target)
		else game:launchTrip(target, { bearing = 0, length = Fields.moons[target].gap }) end
		local x, y = game:fromLane(game.lane.half - 450, -200)
		game.player.body:setPosition(x, y)
		game.player.runup, game.player.laneCarry = nil, nil
		game.player.body:setLinearVelocity(700, 40)
		game.player.body:setAngularVelocity(-0.3)
		game.camera.x, game.camera.y = x + 80, y + 60
		game:updateLane(1 / 120)
		local preview = game.arrivalPreview
		check(preview ~= nil, "arrival scene not prepared before exit")
		-- Local-space labels must stay on their map edge as the camera pans.
		local function boundarySample()
			local printf,line=love.graphics.printf,love.graphics.line
			local label,circleLines=nil,0
			game.camera.ox,game.camera.oy=0,0
			love.graphics.printf=function(text,...)
				if text==Fields[target].name:upper().." / LOCAL SPACE" then
					local sx,sy=love.graphics.transformPoint(0,0)
					local wx,wy=game.camera:toWorld(sx,sy);label={wx,wy}
				end
				return printf(text,...)
			end
			love.graphics.line=function(...)
				local v={...}
				if #v==4 and type(v[1])=="number" then
					local onCircle=true
					for j=1,4,2 do
						local sx,sy=love.graphics.transformPoint(v[j],v[j+1])
						local wx,wy=game.camera:toWorld(sx,sy)
						if math.abs(math.sqrt((wx-preview.x)^2+(wy-preview.y)^2)-Fields[target].radius)>.1 then onCircle=false end
					end
					if onCircle then circleLines=circleLines+1 end
				end
				return line(...)
			end
			local ok,err=pcall(function() Render.world(game) end)
			love.graphics.printf,love.graphics.line=printf,line
			assert(ok,err)
			return label,circleLines
		end
		local label,circleLines=boundarySample()
		check(label and circleLines>=180,"highway preview did not draw the actual circular local boundary")
		local cx,cy=game.camera.x,game.camera.y
		game.camera.x,game.camera.y=cx+600,cy+900
		local moved=boundarySample()
		check(moved and near(label[1],moved[1]) and near(label[2],moved[2]),"local-space label slid along boundary while camera panned")
		game.camera.x,game.camera.y=cx,cy
		local world, entities = preview.game.world, preview.game.entities
		local departureWorld = game.trip.originScene and game.trip.originScene.world
		local marker = entities[1]
		Render.world(game)
		local beforeX, beforeY = screen(preview.game.camera, marker.body)
		local playerX, playerY = screen(game.camera, game.player.body)
		local stars = game.camera.x + (game.camera.backgroundX or 0)
		if target == "luna" then capture("moon-exit-boundary") end
		game:arrive(false)
		check(game.world == world and game.entities == entities, "arrival rebuilt the preview world")
		local afterX, afterY = screen(game.camera, marker.body)
		check(near(beforeX, afterX) and near(beforeY, afterY), "arrival scenery jumped on screen")
		local ax, ay = screen(game.camera, game.player.body)
		check(near(playerX, ax) and near(playerY, ay), "arrival teleported player relative to camera")
		local vx, vy = game.player.body:getLinearVelocity()
		check(near(vx, 700) and near(vy, 40), "arrival changed velocity")
		check(near(game.player.body:getAngularVelocity(), -0.3), "arrival changed ship spin")
		check(near(stars, game.camera.x + (game.camera.backgroundX or 0)), "arrival starfield jumped")
		if departureWorld then check(departureWorld:isDestroyed(), "unused origin world leaked after onward travel") end
		Render.world(game)
	end
	-- Leaving through a debug jump also releases retained worlds.
	game:loadField("earth")
	game:launchTrip("luna", { bearing = 0, length = Fields.moons.luna.gap })
	local discarded = game.trip.originScene.world
	game:loadField("mars")
	check(discarded:isDestroyed(), "debug field change leaked departure scene")
	print(("highway handoff: %d checks passed"):format(checks))
end
