--[[
	Playing fields: what the arena is filled with. Each field has a name,
	where the player launches from, and a build function that places
	everything. Switch fields from the debug panel (F1) or with F2.

	  asteroids  open space with a scattering of breakable rocks
	  giant      one huge asteroid in the middle, far too big to damage,
	             that everyone fights around, plus some loose rocks
	  station    a space station in the middle: a hub, four docking arms
	             and an outer ring with gaps to fly through
]]

local Fields = {}

local cos, sin, pi, random = math.cos, math.sin, math.pi, love.math.random

Fields.list = { "asteroids", "giant", "station", "planet" }

Fields.asteroids = {
	name = "Asteroid field",
	spawn = { 0, 0 },
	radius = 10000,
	build = function(game)
		game:spawnAsteroids(220)
	end,
}

Fields.giant = {
	name = "Giant asteroid",
	spawn = { 0, 2600 },
	radius = 10000,
	build = function(game)
		game:spawnGiantAsteroid(0, 0, 1800)
		game:spawnAsteroids(110)
	end,
}

Fields.station = {
	name = "Space station",
	spawn = { 0, 2600 },
	radius = 9000,
	build = function(game)
		game:spawnWheelStation(0, 0, 1400, 160, 0.04)
		-- A thin scattering of rocks well outside.
		game:spawnAsteroids(70, 2200)
	end,
}

Fields.planet = {
	name = "Planet",
	spawn = { 0, 14200 },
	radius = 24000,
	rockDrag = 0,
	build = function(game)
		-- 15000 px across: too big to see whole even zoomed all the way out.
		local R = 7500
		game:spawnPlanet(0, 0, R, 580, 0.1)
		-- Two wheel stations out past the belt.
		-- The first rides a slow track around the planet at its altitude.
		game:setOrbit(game:spawnWheelStation(10500, -10700, 900, 120, 0.05), 0, 0, 90)
		-- The second is simulated: launched at the current's speed, then
		-- left to the current and whatever runs into it.
		local sx, sy = -12000, 9000
		local st = game:spawnWheelStation(sx, sy, 900, 120, -0.05, true)
		local d = math.sqrt(sx * sx + sy * sy)
		local v = game:currentSpeed(d)
		st.body:setLinearVelocity(-sy / d * v, sx / d * v)
		-- A belt of rocks already circling with the current.
		local placed = 0
		for _ = 1, 2000 do
			if placed >= 180 then break end
			local radius = 24 + random() ^ 2 * 80
			local a = random() * pi * 2
			local d = R + 1500 + random() * 4500
			local x, y = cos(a) * d, sin(a) * d
			if game:isClear(x, y, radius + 60) then
				local e = game:spawnAsteroid(x, y, radius)
				local v = game:currentSpeed(d)
				e.body:setLinearVelocity(-sin(a) * v, cos(a) * v)
				placed = placed + 1
			end
		end
		game:spawnAsteroids(80, R + 7500)
	end,
}

return Fields
