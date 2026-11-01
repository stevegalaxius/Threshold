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

	  mercury, venus, earth, mars, belt (Ceres)
	                       planet maps (Mars has the Heaven-Ladder)
	  jupiter, saturn, uranus, neptune
	                       gas giants with rings (Jupiter's Olympus and
	                       Uranus's Herschel float in the cloud tops)
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

local cos, sin, pi, floor, random = math.cos, math.sin, math.pi, math.floor, love.math.random

Fields.list = { "mercury", "venus", "earth", "mars", "belt", "jupiter", "saturn", "uranus", "neptune",
	"asteroids", "giant", "station" }
Fields.start = "earth"

-- Orbits: distance from the Sun in AU, year length in Earth years, where
-- it starts, and its dot colour on the orrery and the trip view.
Fields.orbits = {
	mercury = { au = 0.39, year = 0.24, phase = 5.2, color = { 0.75, 0.7, 0.65 } },
	venus = { au = 0.72, year = 0.615, phase = 2.1, color = { 0.95, 0.85, 0.55 } },
	earth = { au = 1.0, year = 1.0, phase = 0, color = { 0.45, 0.75, 1 } },
	mars = { au = 1.52, year = 1.88, phase = 4.0, color = { 1, 0.5, 0.35 } },
	belt = { au = 2.77, year = 4.6, phase = 3.0, color = { 0.65, 0.6, 0.55 } },
	jupiter = { au = 5.2, year = 11.86, phase = 1.2, color = { 0.9, 0.7, 0.5 } },
	saturn = { au = 9.54, year = 29.46, phase = 0.5, color = { 0.95, 0.85, 0.6 } },
	uranus = { au = 19.2, year = 84.0, phase = 2.8, color = { 0.6, 0.9, 0.95 } },
	neptune = { au = 30.07, year = 164.8, phase = 4.6, color = { 0.4, 0.55, 1 } },
}

-- Where an orbit of au goes on a map of the system, as a fraction of its
-- radius: squashed (power 0.4) so Mercury and Neptune both fit.
function Fields.mapScale(au)
	local maxAU = 0
	for _, o in pairs(Fields.orbits) do maxAU = math.max(maxAU, o.au) end
	return (au / maxAU) ^ 0.4
end

-- How long a lane is for a trip of au: full length per AU out to
-- T.laneFarAU, then each AU past that counts for only T.laneFarScale of
-- one, so the outer planets are a longer trip but not minutes of road.
function Fields.laneLength(au)
	local eff = au
	if au > T.laneFarAU then eff = T.laneFarAU + (au - T.laneFarAU) * T.laneFarScale end
	return T.laneBase + T.lanePerAU * eff
end

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

-- Debris: what you hit in space. Each planet map has a mix (weights for
-- the kinds below), so the inner worlds are mostly junk and satellites and
-- the outer reaches mostly rock and ice. See Game:spawnDebris.
--   rock   plain asteroids        ice   ice asteroids (pale, brittle)
--   junk   dead hardware          sat   working satellites (blinking)
local MIX = {
	inner = { junk = 4, sat = 2, rock = 4 },
	mars = { junk = 3, sat = 2, rock = 5 },
	belt = { rock = 9, ice = 1 },
	giant = { rock = 5, ice = 4, junk = 1 },
	ice = { ice = 8, rock = 2 },
}
Fields.mixes = MIX

-- A planet field, from a table of settings (all distances in px):
--   name, R            name and planet radius
--   depth              open space past the surface: the arena edge is at
--                      R + depth. This, not R, is how roomy the map is.
--   density            loose debris per million px^2 of open space past
--                      the station track
--   mix                debris weights (see MIX above)
--   belt               belt (or, round a gas giant, ring) density per
--                      million px^2; beltIn/beltOut: its band above the
--                      surface, as fractions of depth (default 0.25..0.38)
--   track              the station track, as a fraction of depth (0.55)
--   beltMix            the belt's own mix (default rock)
--   rings              a gas giant's rings, instead of a belt: bands
--                      { inner, outer (fractions of depth), density =,
--                      big = chance of a large chunk }, all small ice
--   stations           names for its orbital stations (none if nil)
--   city               a cloud city's name: a station floating in a gas
--                      giant's cloud tops, above the crush (station 1)
--   enemies            { { enemy id, count }, ... }
--   gas                a gas giant (see Game:spawnGasGiant)
--   extra(game, R)     more to build once the planet is in
local function planetField(o)
	local name, R = o.name, o.R
	local depth = o.depth or 35000
	local edge = R + depth
	-- Everything is laid out as fractions of the open space (depth), so a
	-- roomier map spreads its belt and stations out instead of leaving
	-- the extra room empty at the edge.
	local beltIn, beltOut = R + depth * (o.beltIn or 0.25), R + depth * (o.beltOut or 0.38)
	local sd = R + depth * (o.track or 0.55)  -- the station track
	local looseIn = sd + 2000                 -- loose debris starts past the station track
	local area = function(r1, r2) return pi * (r2 * r2 - r1 * r1) / 1e6 end
	-- The belt, or a gas giant's rings: bands of { inner, outer, how many
	-- per million px^2, mix, size(game) for each piece }. Rings are all ice
	-- and mostly small chunks; o.rings lists them as fractions of depth,
	-- with big: the chance of an occasional large chunk.
	local bands = {}
	if o.gas then
		for _, rb in ipairs(o.rings or {}) do
			local big = rb.big or 0
			table.insert(bands, { R + depth * rb[1], R + depth * rb[2], rb.density, { ice = 1 },
				size = function() return random() < big and 60 + random() * 60 or 10 + random() ^ 3 * 60 end })
		end
	else
		bands[1] = { beltIn, beltOut, o.belt or 0, o.beltMix or { rock = 1 } }
	end
	local scattered = floor((o.density or 0) * area(looseIn, edge))
	-- the planet's colour, the same every visit (so it can be drawn ahead
	-- of you on the highway before you arrive)
	local rng = love.math.newRandomGenerator(#name * 7919 + R)
	local hue = { 0.35 + rng:random() * 0.2, 0.45 + rng:random() * 0.2, 0.7 + rng:random() * 0.2 }
	if o.hue then hue = o.hue end
	local stations = o.stations
	if o.city then
		stations = { o.city }
		for _, n in ipairs(o.stations or {}) do table.insert(stations, n) end
	end
	return {
		name = name,
		planetR = R, gas = o.gas, hue = hue,
		mix = o.mix or MIX.inner,
		rings = o.gas and bands or nil,
		stations = stations,
		enemies = o.enemies,
		spawn = { 0, sd - 800 },
		belt = { beltIn, beltOut },
		radius = edge,
		rockDrag = 0,
		build = function(game)
			local planet = o.gas and game:spawnGasGiant(0, 0, R, 290, 0.1, hue) or game:spawnPlanet(0, 0, R, 290, 0.1)
			if not o.gas then planet.hue = hue end
			if o.gas then planet.rings = bands end
			if o.city then game:spawnCloudCity(-pi / 2 + 0.35, o.cityScale) end
			if o.extra then o.extra(game, R) end
			if o.stations then
				-- Two wheel stations out past the belt.
				-- Both ride a track around the planet at opposite ends, moving at
				-- the current's speed at that altitude (what a free station drifts at).
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
				-- One of each size: a Hauler, a Packhorse and a Runner.
				local kinds = { "freighter", "packhorse_trader", "runner_trader" }
				for k = 1, 3 do
					local a = sa + pi / 4 + (k - 1) * pi / 2
					local f = game:spawnEnemy(kinds[k], cos(a) * sd, sin(a) * sd)
					f.route = route
					f.routeIndex = k % #route + 1
					f.body:setAngle(a + pi / 2)
					f.body:setLinearVelocity(-sin(a) * speed, cos(a) * speed)
				end
			end
			-- The belt (or rings), already circling with the current.
			for _, band in ipairs(bands) do
				local b1, b2 = band[1], band[2]
				local n = floor(band[3] * area(b1, b2))
				local placed = 0
				for _ = 1, n * 12 do
					if placed >= n then break end
					local kind = game:pickDebris(band[4])
					local radius = band.size and band.size() or game:debrisSize(kind)
					local a = random() * pi * 2
					local d = b1 + random() * (b2 - b1)
					local x, y = cos(a) * d, sin(a) * d
					-- ring ice is packed too densely to check every placement
					-- against every other piece; they're tiny, so let them be
					if band.size or game:isClear(x, y, radius + 40) then
						local e = game:spawnDebris(kind, x, y, radius)
						local v = game:currentSpeed(d)
						e.body:setLinearVelocity(-sin(a) * v, cos(a) * v)
						placed = placed + 1
					end
				end
			end
			game:spawnAsteroids(scattered, looseIn)
			game:spawnContainers(T.fieldContainers, sd)
		end,
	}
end

-- Each planet's map. Planet sizes are as set; how roomy a map is comes
-- from depth, and its character from density, mix and belt.
Fields.mercury = planetField({ name = "Mercury", R = 5700, depth = 15000,
	density = 0.07, mix = { junk = 3, sat = 2, rock = 5 }, belt = 1.1,
	stations = { "Terminator Station", "Dawnline Station" },
	enemies = { { "gunner", 2 }, { "swarmer", 2 } } })
Fields.venus = planetField({ name = "Venus", R = 14300, depth = 18000,
	density = 0.1, mix = MIX.inner, belt = 1.1,
	stations = { "Hub Station", "Cloudline Station" },
	enemies = { { "gunner", 2 }, { "swarmer", 3 } } })
Fields.earth = planetField({ name = "Earth", R = 15000, depth = 18000,
	density = 0.1, mix = MIX.inner, belt = 1.1,
	stations = { "Orbital One", "Orbital Two" },
	enemies = { { "brawler", 2 }, { "sniper", 2 }, { "gunner", 2 } } })
Fields.mars = planetField({ name = "Mars", R = 7500, depth = 17000,
	density = 0.05, mix = MIX.mars, belt = 1.1,
	stations = { "Station Alpha", "Station Beta" },
	enemies = { { "gunner", 2 }, { "interceptor", 2 } },
	extra = function(game, R) game:spawnHeavenLadder(0, 0, R + 1100) end })
-- The asteroid belt: Ceres in the middle and rock everywhere.
Fields.belt = planetField({ name = "Ceres", R = 2500, depth = 20000,
	density = 0.3, mix = MIX.belt, belt = 2.5, beltIn = 0.1, beltOut = 0.35,
	stations = { "Ceres Dock", "Piazzi Station" },
	enemies = { { "swarmer", 3 }, { "interceptor", 2 }, { "brawler", 1 } } })
Fields.jupiter = planetField({ name = "Jupiter", R = 45000, depth = 22000, gas = true,
	hue = { 0.85, 0.65, 0.45 },
	density = 0.08, mix = MIX.giant, rings = { { 0.2, 0.4, density = 1.5 } },
	city = "Olympus", cityScale = 2,
	enemies = { { "brawler", 3 }, { "sniper", 2 }, { "interceptor", 3 } } })
Fields.saturn = planetField({ name = "Saturn", R = 45000, depth = 34000, gas = true,
	hue = { 0.9, 0.8, 0.55 },
	density = 0.08, mix = { ice = 6, rock = 4 }, track = 0.75,
	-- C ring (faint), B ring (dense, the odd big chunk), the Cassini
	-- division, then the A ring (medium)
	rings = { { 0.15, 0.25, density = 0.5 }, { 0.25, 0.42, density = 3, big = 0.03 }, { 0.46, 0.6, density = 1.5 } },
	stations = { "Cassini Gate", "Enceladus Station" },
	enemies = { { "gunner", 3 }, { "sniper", 2 }, { "swarmer", 3 } } })
Fields.uranus = planetField({ name = "Uranus", R = 30000, depth = 20000, gas = true,
	hue = { 0.55, 0.85, 0.9 },
	density = 0.09, mix = MIX.ice, rings = { { 0.25, 0.4, density = 2 } },
	city = "Herschel",
	enemies = { { "interceptor", 3 }, { "sniper", 2 } } })
Fields.neptune = planetField({ name = "Neptune", R = 30000, depth = 20000, gas = true,
	hue = { 0.35, 0.5, 0.95 },
	density = 0.09, mix = { ice = 9, rock = 1 }, rings = { { 0.25, 0.38, density = 1.5 } },
	enemies = { { "brawler", 3 }, { "interceptor", 3 }, { "sniper", 2 } } })

-- The transit lane: built from game.trip (see Game:launchTrip).
Fields.lane = {
	name = "Transit lane",
	spawn = { 0, 0 },
	radius = 1e6,
	transit = true,
	build = function(game) game:buildLane() end,
}

return Fields
