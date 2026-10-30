--[[
	Playing fields, which are the game's levels: what the arena is filled
	with. Each field has a name, where the player launches from, and a build
	function that places everything. Optional:
	  enemies   { { enemy id, count }, ... } placed around the level; they
	            leave you alone until you come close (T.aggroRange)
	  stations  names for its stations, in the order build makes them
	Every planet map has a mass driver. Fly into it, pick a planet on its
	orrery, and it fires you into a transit lane (the "lane" field) toward
	that planet; you
	come out the far end at the other planet's driver, still moving fast.
	F2 (or the debug panel) still jumps straight to the next field for
	testing.

	Planets also circle the Sun (Fields.orbits): each one's year keeps its
	real length relative to Earth's, all sped up to T.yearLength seconds of
	game clock for Earth. That only sets the distance between two planets,
	which sets how long the transit lane between them is.

	  earth, venus, mars   planet maps (Mars has the Heaven-Ladder)
	  jupiter              a gas giant: no surface, a crushing gradient
	  lane                 the transit lane between two planets
	The old levels below stay as instance maps for missions later; for now
	they're reached from the debug panel.

	  asteroids  open space with a scattering of breakable rocks
	  giant      one huge asteroid in the middle, far too big to damage,
	             that everyone fights around, plus some loose rocks
	  station    a space station in the middle: a hub, four docking arms
	             and an outer ring with gaps to fly through
]]

local T = require("src.tuning")

local Fields = {}

local cos, sin, pi, random = math.cos, math.sin, math.pi, love.math.random

Fields.list = { "earth", "venus", "mars", "jupiter", "asteroids", "giant", "station" }
Fields.start = "earth"

-- Orbits: distance from the Sun in AU and year length in Earth years.
Fields.orbits = {
	venus = { au = 0.72, year = 0.615, phase = 2.1 },
	earth = { au = 1.0, year = 1.0, phase = 0 },
	mars = { au = 1.52, year = 1.88, phase = 4.0 },
	jupiter = { au = 5.2, year = 11.86, phase = 1.2 },
}

-- Where a planet is around the Sun at this clock, in AU.
function Fields.orbitPos(id, clock)
	local o = Fields.orbits[id]
	local a = o.phase + clock / (T.yearLength * o.year) * pi * 2
	return cos(a) * o.au, sin(a) * o.au
end

-- How far apart two planets are right now, in AU.
function Fields.distance(a, b, clock)
	local ax, ay = Fields.orbitPos(a, clock)
	local bx, by = Fields.orbitPos(b, clock)
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

Fields.asteroids = {
	name = "Asteroid field",
	spawn = { 0, 0 },
	radius = 10000,
	enemies = { { "swarmer", 4 }, { "gunner", 2 }, { "interceptor", 2 } },
	build = function(game)
		game:spawnAsteroids(220)
		game:spawnContainers(T.fieldContainers)
	end,
}

Fields.giant = {
	name = "Giant asteroid",
	spawn = { 0, 2600 },
	radius = 10000,
	enemies = { { "gunner", 3 }, { "brawler", 2 }, { "sniper", 1 } },
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
	stations = { "Hub Station" },
	enemies = { { "swarmer", 2 } },
	build = function(game)
		game:spawnWheelStation(0, 0, 1400, 160, 0.04)
		-- A thin scattering of rocks well outside.
		game:spawnAsteroids(70, 2200)
		game:spawnContainers(T.fieldContainers, 2200)
	end,
}

-- A planet field. R is the planet's radius; the belt, station track and
-- arena edge keep the same distances from its surface whatever its size.
-- o.gas: a gas giant (no surface, see Game:spawnGasGiant); o.extra(game, R):
-- more to build once the planet is in; o.edge: arena edge past the surface.
local function planetField(name, R, rocks, scattered, stations, enemies, o)
	o = o or {}
	return {
		name = name,
		stations = stations,
		enemies = enemies,
		spawn = { 0, R + 6700 },
		radius = R + (o.edge or 16500),
		rockDrag = 0,
		build = function(game)
			if o.gas then game:spawnGasGiant(0, 0, R, 290, 0.1) else game:spawnPlanet(0, 0, R, 290, 0.1) end
			if o.extra then o.extra(game, R) end
			if stations then
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

-- Sizes keep roughly the real ratios to Earth (Mars 0.53, Venus 0.95).
Fields.earth = planetField("Earth", 15000, 320, 140, { "Orbital One", "Orbital Two" },
	{ { "brawler", 2 }, { "sniper", 2 }, { "gunner", 2 } })
Fields.venus = planetField("Venus", 14300, 300, 120, { "Hub Station", "Cloudline Station" },
	{ { "gunner", 2 }, { "swarmer", 3 } })
Fields.mars = planetField("Mars", 7500, 180, 80, { "Station Alpha", "Station Beta" },
	{ { "gunner", 2 }, { "interceptor", 2 } },
	{ extra = function(game, R) game:spawnHeavenLadder(0, 0, R + 1100) end })
-- Barebones, to try the scale: a gas giant much bigger than Earth with no
-- stations yet, meant to be big enough to get lost in.
Fields.jupiter = planetField("Jupiter", 45000, 600, 260, nil,
	{ { "brawler", 3 }, { "sniper", 2 }, { "interceptor", 3 } },
	{ gas = true, edge = 30000 })

-- The transit lane: built from game.trip (see Game:launchTrip).
Fields.lane = {
	name = "Transit lane",
	spawn = { 0, 0 },
	radius = 1e6,
	transit = true,
	build = function(game) game:buildLane() end,
}

return Fields
