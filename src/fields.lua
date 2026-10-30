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

local T = require("src.tuning")

local Fields = {}

local cos, sin, pi, random = math.cos, math.sin, math.pi, love.math.random

Fields.list = { "asteroids", "giant", "station", "planet", "bigplanet" }

Fields.asteroids = {
	name = "Asteroid field",
	spawn = { 0, 0 },
	radius = 10000,
	build = function(game)
		game:spawnAsteroids(220)
		game:spawnContainers(T.fieldContainers)
	end,
}

Fields.giant = {
	name = "Giant asteroid",
	spawn = { 0, 2600 },
	radius = 10000,
	build = function(game)
		game:spawnGiantAsteroid(0, 0, 1800)
		game:spawnAsteroids(110)
		game:spawnContainers(T.fieldContainers, 2200)
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
		game:spawnContainers(T.fieldContainers, 2200)
	end,
}

-- A planet field. R is the planet's radius; the belt, station track and
-- arena edge keep the same distances from its surface whatever its size.
local function planetField(name, R, rocks, scattered)
	return {
		name = name,
		spawn = { 0, R + 6700 },
		radius = R + 16500,
		rockDrag = 0,
		build = function(game)
			game:spawnPlanet(0, 0, R, 580, 0.1)
			-- Two wheel stations out past the belt.
			-- Both ride a track around the planet at opposite ends, moving at
			-- the current's speed at that altitude (what a free station drifts at).
			local sd = R + 7500
			local sa = -0.8
			local speed = game:currentSpeed(sd)
			local stA = game:spawnWheelStation(cos(sa) * sd, sin(sa) * sd, 900, 120, 0.05)
			local stB = game:spawnWheelStation(-cos(sa) * sd, -sin(sa) * sd, 900, 120, -0.05)
			game:setOrbit(stA, 0, 0, speed)
			game:setOrbit(stB, 0, 0, speed)
			-- Buoys on the same track at the two Lagrange-style points halfway
			-- between the stations, a quarter turn from each.
			local b1 = game:spawnBuoy(cos(sa + pi / 2) * sd, sin(sa + pi / 2) * sd)
			local b2 = game:spawnBuoy(cos(sa - pi / 2) * sd, sin(sa - pi / 2) * sd)
			game:setOrbit(b1, 0, 0, speed)
			game:setOrbit(b2, 0, 0, speed)
			-- Neutral freighters hauling the loop: station, buoy, station, buoy.
			local route = { stA, b1, stB, b2 }
			-- They start on the track between stops, heading for the next one.
			for k = 1, 3 do
				local a = sa + pi / 4 + (k - 1) * pi / 2
				local f = game:spawnEnemy("freighter", cos(a) * sd, sin(a) * sd)
				f.route = route
				f.routeIndex = k % #route + 1
				f.body:setAngle(a + pi / 2)
				f.body:setLinearVelocity(-sin(a) * speed, cos(a) * speed)
			end
			-- A belt of rocks already circling with the current.
			local placed = 0
			for _ = 1, rocks * 12 do
				if placed >= rocks then break end
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
			game:spawnAsteroids(scattered, R + 7500)
			game:spawnContainers(T.fieldContainers, R + 7500)
		end,
	}
end

-- 15000 px across: too big to see whole even zoomed all the way out.
Fields.planet = planetField("Planet", 7500, 180, 80)
-- Twice the size: 30000 px across.
Fields.bigplanet = planetField("Giant planet", 15000, 320, 140)

return Fields
