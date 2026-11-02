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

Fields.list = { "mercury", "venus", "earth", "luna", "mars", "phobos", "deimos", "belt", "ring", "jupiter", "io", "europa", "ganymede", "callisto",
	"saturn", "enceladus", "titan", "uranus", "titania", "neptune", "triton", "pluto", "asteroids", "giant", "station" }
Fields.start = "earth"

-- Orbits: distance from the Sun in AU, year length in Earth years, where
-- it starts, and its dot colour on the orrery and the trip view.
Fields.orbits = {
	mercury = { au = 0.39, year = 0.24, phase = 5.2, color = { 0.75, 0.7, 0.65 } },
	venus = { au = 0.72, year = 0.615, phase = 2.1, color = { 0.95, 0.85, 0.55 } },
	earth = { au = 1.0, year = 1.0, phase = 0, color = { 0.45, 0.75, 1 } },
	mars = { au = 1.52, year = 1.88, phase = 4.0, color = { 1, 0.5, 0.35 } },
	belt = { au = 2.77, year = 4.6, phase = 3.0, color = { 0.65, 0.6, 0.55 } },
	ring = { au = 2.77, year = 4.6, phase = 3.0 + math.pi, color = { 0.8, 0.75, 0.6 } },   -- across the Sun from Ceres
	jupiter = { au = 5.2, year = 11.86, phase = 1.2, color = { 0.9, 0.7, 0.5 } },
	saturn = { au = 9.54, year = 29.46, phase = 0.5, color = { 0.95, 0.85, 0.6 } },
	uranus = { au = 19.2, year = 84.0, phase = 2.8, color = { 0.6, 0.9, 0.95 } },
	neptune = { au = 30.07, year = 164.8, phase = 4.6, color = { 0.4, 0.55, 1 } },
	pluto = { au = 39.48, year = 248, phase = 3.8, color = { 0.75, 0.65, 0.6 } },
}

-- Moons: each is its own small map, reached by flying off the edge of
-- its planet's map toward it, onto a short highway (src/moons.lua), not
-- by mass driver. A moon has no orbit round the Sun of its own: for
-- anything at AU scale it sits on its planet.
--   parent   the planet it circles
--   period   its month, in Earth years (the same game clock as the planets)
--   phase    where it starts round the planet
--   gap      how long the highway from planet to moon is, in px
-- A new moon is one line here plus its map (planetField, below, with
-- parent = its planet).
Fields.moons = {
	luna = { parent = "earth", period = 0.075, phase = 1.0, gap = 30000, color = { 0.8, 0.8, 0.78 } },
	phobos = { parent = "mars", period = 0.02, phase = 2.5, gap = 14000, color = { 0.65, 0.55, 0.5 } },
	deimos = { parent = "mars", period = 0.04, phase = 5.0, gap = 20000, color = { 0.7, 0.6, 0.5 } },
	io = { parent = "jupiter", period = 0.025, phase = 1.8, gap = 22000, color = { 0.95, 0.8, 0.35 } },
	callisto = { parent = "jupiter", period = 0.2, phase = 5.2, gap = 54000, color = { 0.6, 0.57, 0.52 } },
	enceladus = { parent = "saturn", period = 0.03, phase = 1.6, gap = 24000, color = { 0.7, 0.88, 0.95 } },
	europa = { parent = "jupiter", period = 0.05, phase = 0.3, gap = 30000, color = { 0.9, 0.85, 0.75 } },
	ganymede = { parent = "jupiter", period = 0.1, phase = 3.6, gap = 42000, color = { 0.7, 0.68, 0.62 } },
	titan = { parent = "saturn", period = 0.15, phase = 4.4, gap = 40000, color = { 0.95, 0.7, 0.35 } },
	titania = { parent = "uranus", period = 0.09, phase = 2.0, gap = 30000, color = { 0.7, 0.72, 0.75 } },
	triton = { parent = "neptune", period = 0.1, phase = 5.5, gap = 32000, color = { 0.8, 0.85, 0.9 } },
}

-- The moons of a planet, in a fixed order.
function Fields.moonsOf(planet)
	local out = {}
	for id, m in pairs(Fields.moons) do if m.parent == planet then table.insert(out, id) end end
	table.sort(out)
	return out
end

-- Which way a moon lies from its planet at this clock (radians).
function Fields.moonAngle(id, clock)
	local m = Fields.moons[id]
	return m.phase + clock / (T.yearLength * m.period) * pi * 2
end

-- An airless rock's outline, the same every visit, with craters (drawn,
-- not collided). Points are local to its centre. lumpy: 0 is a round
-- world (Luna), 1 a potato (Phobos). maria: dark lava plains, as on Luna.
function Fields.rockShape(name, R, lumpy, maria)
	lumpy = lumpy or 1
	local rng = love.math.newRandomGenerator(#name * 104729 + floor(R))
	local n = 96
	-- a few broad lumps plus a little roughness
	local waves = {}
	for k = 1, 4 do waves[k] = { f = k + 1, a = rng:random() * 0.07 / k * 2 * lumpy, p = rng:random() * pi * 2 } end
	local outline = {}
	for i = 0, n - 1 do
		local a = i / n * pi * 2
		local r = 1 + (rng:random() - 0.5) * 0.015 * math.max(lumpy, 0.2)
		for _, w in ipairs(waves) do r = r + w.a * sin(w.f * a + w.p) end
		outline[#outline + 1] = cos(a) * R * r
		outline[#outline + 1] = sin(a) * R * r
	end
	local craters = {}
	for _ = 1, 14 do
		local a, d = rng:random() * pi * 2, math.sqrt(rng:random()) * R * 0.8
		craters[#craters + 1] = { cos(a) * d, sin(a) * d, R * (0.04 + rng:random() * 0.12) }
	end
	local plains = {}
	for _ = 1, maria or 0 do
		local a, d = rng:random() * pi * 2, math.sqrt(rng:random()) * R * 0.55
		plains[#plains + 1] = { cos(a) * d, sin(a) * d, R * (0.15 + rng:random() * 0.2) }
	end
	return { outline = outline, craters = craters, maria = plains }
end

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
		game:spawnWheelStation(0, 0, 1400, 160, 0.04, false, "station/hub_station")
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
	local field
	field = {
		name = name,
		stationTrack = sd, city = o.city, alifeTraders = o.stations and (o.traders or 3),
		planetR = R, gas = o.gas, hue = hue, rocky = o.rocky, lumpy = o.lumpy, maria = o.maria, parent = o.parent,
		mix = o.mix or MIX.inner,
		rings = o.gas and bands or nil,
		stations = stations,
		enemies = o.enemies,
		spawn = { 0, sd - 800 },
		belt = { beltIn, beltOut },
		radius = edge,
		rockDrag = 0,
		build = function(game)
			local planet = o.gas and game:spawnGasGiant(0, 0, R, 290, 0.1, hue)
				or game:spawnPlanet(0, 0, R, 290, 0.1, o.rocky and Fields.rockShape(name, R, o.lumpy, o.maria))
			if not o.gas then planet.hue = hue end
			if o.gas then planet.rings = bands end
			if o.city then game:spawnCloudCity(-pi / 2 + 0.35, o.cityScale, field.stationIds[1]) end
			if o.extra then o.extra(game, R) end
			if o.stations then
				-- Two wheel stations out past the belt.
				-- Both ride a track around the planet at opposite ends, moving at
				-- the current's speed at that altitude (what a free station drifts at).
				local sa = -0.8
				local speed = game:currentSpeed(sd)
				local stA = game:spawnWheelStation(cos(sa) * sd, sin(sa) * sd, 900, 120, 0.05, false, field.stationIds[o.city and 2 or 1])
				local stB = game:spawnWheelStation(-cos(sa) * sd, -sin(sa) * sd, 900, 120, -0.05, false, field.stationIds[o.city and 3 or 2])
				game:setOrbit(stA, 0, 0, speed)
				game:setOrbit(stB, 0, 0, speed)
				sa = math.atan2(stA.body:getY(), stA.body:getX())
				-- Buoys on the same track at the two Lagrange-style points halfway
				-- between the stations, a quarter turn from each.
				local b1 = game:spawnBuoy(cos(sa + pi / 2) * sd, sin(sa + pi / 2) * sd, field.buoyIds[1])
				local b2 = game:spawnBuoy(cos(sa - pi / 2) * sd, sin(sa - pi / 2) * sd, field.buoyIds[2])
				game:setOrbit(b1, 0, 0, speed)
				game:setOrbit(b2, 0, 0, speed)
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
					if (band.size or game:isClear(x, y, radius + 40)) and game:areaObjectClear(x, y, radius + 40) then
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
	return field
end

-- Ring Station: the belt's other stop, across the Sun from Ceres. No
-- planet: a giant wheel station in the middle of thick rock, with a clear
-- space round it kept by traffic control.
Fields.ring = {
	name = "Ring Station",
	spawn = { 0, 5200 },
	radius = 26000,
	mix = MIX.belt,
	stations = { "Ring Station" },
	enemies = { { "swarmer", 3 }, { "interceptor", 2 }, { "gunner", 2 } },
	build = function(game)
		game:spawnWheelStation(0, 0, 3000, 300, 0.02, false, "ring/ring_station")
		-- a few huge rocks, too big to break, out in the field
		for k = 0, 3 do
			local a = k / 4 * pi * 2 + 0.4
			local d = 11000 + (k % 2) * 5000
			game:spawnGiantAsteroid(cos(a) * d, sin(a) * d, 900 + (k % 3) * 400)
		end
		-- thick rock from the clear zone out to the edge
		local area = pi * (26000 ^ 2 - 6500 ^ 2) / 1e6
		game:spawnAsteroids(floor(area * 0.18), 6500)
		game:spawnContainers(T.fieldContainers, 4500)
	end,
}

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
	density = 0.005, mix = { junk = 7, sat = 5, rock = 1 },
	belt = 0.025, beltMix = { junk = 7, sat = 5, rock = 1 }, traders = 9,
	stations = { "Station Alpha", "Station Beta" },
	enemies = { { "gunner", 2 }, { "interceptor", 2 } },
	extra = function(game, R) game:spawnHeavenLadder(0, 0, R + 1100) end })
-- The asteroid belt: Ceres in the middle and rock everywhere.
Fields.belt = planetField({ name = "Ceres", R = 2500, depth = 20000, rocky = true, lumpy = 0.15,
	density = 0.15, mix = MIX.belt, belt = 2.5, beltIn = 0.1, beltOut = 0.35,
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
	density = 0.09, mix = { ice = 9, rock = 1 }, -- four dense rings, well out from the planet, in pairs: a wider ring
	-- then a thin one just outside it, twice
	rings = { { 0.337, 0.390, density = 6 }, { 0.477, 0.499, density = 6 }, { 0.695, 0.748, density = 6 }, { 0.804, 0.820, density = 6 } },
	enemies = { { "brawler", 3 }, { "interceptor", 3 }, { "sniper", 2 } } })

-- The moons' maps (see Fields.moons). Airless bodies retain their rocky
-- silhouettes; infrastructure can be added separately without replacing them.
Fields.luna = planetField({ name = "Luna", R = 4000, depth = 15000, rocky = true, lumpy = 0, maria = 6, parent = "earth",
	hue = { 0.62, 0.62, 0.6 }, density = 0.08, mix = { rock = 6, junk = 3, sat = 1 }, belt = 0.6,
	stations = { "Tranquility Dock", "Shackleton Station" },
	enemies = { { "gunner", 2 }, { "swarmer", 2 } } })
Fields.phobos = planetField({ name = "Phobos", R = 1400, depth = 9000, rocky = true, parent = "mars",
	hue = { 0.5, 0.42, 0.38 }, density = 0.12, mix = { rock = 1 }, belt = 1.5, beltIn = 0.15, beltOut = 0.4 })
Fields.deimos = planetField({ name = "Deimos", R = 800, depth = 9000, rocky = true, parent = "mars",
	hue = { 0.55, 0.48, 0.42 }, density = 0.1, mix = { rock = 1 }, belt = 1.0, beltIn = 0.15, beltOut = 0.4 })
Fields.io = planetField({ name = "Io", R = 4500, depth = 14000, parent = "jupiter",
	hue = { 0.85, 0.65, 0.25 }, density = 0.035, mix = { rock = 7, junk = 3 }, belt = 0.15,
	stations = { "Pele Works", "Loki Laboratory" },
	enemies = { { "gunner", 2 }, { "interceptor", 1 } } })
Fields.callisto = planetField({ name = "Callisto", R = 6000, depth = 16000, parent = "jupiter", rocky = true, lumpy = 0.1,
	hue = { 0.48, 0.45, 0.42 }, density = 0.08, mix = { rock = 6, ice = 3, junk = 1 }, belt = 0.4,
	stations = { "Valhalla Port", "Asgard Station" },
	enemies = { { "swarmer", 2 }, { "gunner", 2 } } })
Fields.enceladus = planetField({ name = "Enceladus", R = 2600, depth = 13000, parent = "saturn",
	hue = { 0.72, 0.85, 0.9 }, density = 0.09, mix = { ice = 9, junk = 1 },
	belt = 0.7, beltMix = { ice = 1 },
	stations = { "Tiger Stripe Laboratory", "South Pole Port" },
	enemies = { { "interceptor", 2 } } })
Fields.pluto = planetField({ name = "Pluto", R = 3000, depth = 16000,
	hue = { 0.65, 0.52, 0.45 }, density = 0.06, mix = { ice = 8, rock = 2 },
	belt = 0.35, beltMix = { ice = 1 },
	stations = { "Tombaugh Station", "Sputnik Port" },
	enemies = { { "sniper", 1 }, { "interceptor", 2 } } })
Fields.europa = planetField({ name = "Europa", R = 3800, depth = 15000, parent = "jupiter",
	hue = { 0.85, 0.8, 0.7 }, density = 0.08, mix = { ice = 8, rock = 2 }, belt = 0.8,
	stations = { "Conamara Station", "Pwyll Station" },
	enemies = { { "interceptor", 2 }, { "sniper", 1 } } })
Fields.ganymede = planetField({ name = "Ganymede", R = 6000, depth = 17000, parent = "jupiter",
	hue = { 0.6, 0.58, 0.55 }, density = 0.08, mix = { ice = 5, rock = 5 }, belt = 0.8,
	stations = { "Galileo Regio", "Uruk Station" },
	enemies = { { "brawler", 2 }, { "gunner", 2 } } })
Fields.titan = planetField({ name = "Titan", R = 6000, depth = 17000, parent = "saturn",
	hue = { 0.9, 0.62, 0.3 }, density = 0.07, mix = { ice = 6, rock = 4 }, belt = 0.7,
	stations = { "Kraken Station", "Huygens Station" },
	enemies = { { "gunner", 2 }, { "sniper", 2 } } })
Fields.titania = planetField({ name = "Titania", R = 2000, depth = 14000, parent = "uranus", rocky = true, lumpy = 0.08,
	hue = { 0.62, 0.64, 0.67 }, density = 0.07, mix = { ice = 6, rock = 3, junk = 1 },
	belt = 0.45, beltMix = { ice = 7, rock = 3 },
	stations = { "Gertrude Port", "Messina Research Station" },
	enemies = { { "interceptor", 2 }, { "gunner", 1 } } })
Fields.triton = planetField({ name = "Triton", R = 3200, depth = 15000, parent = "neptune",
	hue = { 0.75, 0.8, 0.85 }, density = 0.09, mix = { ice = 9, rock = 1 }, belt = 0.8,
	stations = { "Cipango Station", "Voyager Station" },
	enemies = { { "interceptor", 3 }, { "sniper", 1 } } })

-- The transit lane: built from game.trip (see Game:launchTrip).
Fields.lane = {
	name = "In transit",
	spawn = { 0, 0 },
	radius = 1e6,
	transit = true,
	build = function(game) game:buildLane() end,
}

-- Stable authored station IDs. Display names may change without changing
-- these references. Factory calls pass these IDs explicitly to each body.
local stationIds = {
	mercury = { "terminator_station", "dawnline_station" },
	venus = { "hub_station", "cloudline_station" }, earth = { "orbital_one", "orbital_two" },
	mars = { "station_alpha", "station_beta" }, belt = { "ceres_dock", "piazzi_station" },
	jupiter = { "olympus" }, saturn = { "cassini_gate", "enceladus_station" },
	uranus = { "herschel" }, luna = { "tranquility_dock", "shackleton_station" },
	io = { "pele_works", "loki_laboratory" }, europa = { "conamara_station", "pwyll_station" },
	ganymede = { "galileo_regio", "uruk_station" }, callisto = { "valhalla_port", "asgard_station" },
	enceladus = { "tiger_stripe_laboratory", "south_pole_port" }, titan = { "kraken_station", "huygens_station" },
	titania = { "gertrude_port", "messina_research_station" }, triton = { "cipango_station", "voyager_station" },
	pluto = { "tombaugh_station", "sputnik_port" }, ring = { "ring_station" }, station = { "hub_station" },
}
for _, area in ipairs(Fields.list) do
	local F = Fields[area]
	F.locations, F.stationIds, F.buoyIds = {}, {}, {}
	local function add(id, name, kind, motion, spin, destination)
		local full = area .. "/" .. id
		F.locations[#F.locations + 1] = { id = full, area = area, name = name, kind = kind,
			motion = motion, spin = spin, destination = destination }
		return full
	end
	for i, id in ipairs(stationIds[area] or {}) do
		local motion, spin
		if F.city and i == 1 then
			local tunnel = require("src.stations").CITY_TUNNEL
			local top, bottom = F.planetR - 60 - tunnel, F.planetR - F.planetR / 13 + tunnel + 100
			motion = { type = "cloud", a = -pi / 2 + 0.35, r = (top + bottom) / 2,
				up = math.max(0, (top - bottom) / 2 * 0.85), across = T.cityDriftAcross,
				upPeriod = T.cityDriftUp, acrossPeriod = T.cityDriftAcrossPeriod, phase = area == "jupiter" and 0.7 or 2.1 }
		elseif F.stationTrack then
			local n = i - (F.city and 1 or 0)
			motion = { type = "orbit", radius = F.stationTrack, surface = F.planetR, phase = -0.8 + (n - 1) * pi }
			spin = n == 1 and 0.05 or -0.05
		else
			motion, spin = { type = "fixed", x = 0, y = 0 }, area == "ring" and 0.02 or 0.04
		end
		F.stationIds[i] = add(id, F.stations[i], "station", motion, spin)
	end
	if F.stationTrack and #F.stationIds > (F.city and 1 or 0) then
		for i, phase in ipairs({ -0.8 + pi / 2, -0.8 - pi / 2 }) do
			F.buoyIds[i] = add(i == 1 and "trade_buoy_a" or "trade_buoy_b", "Trade buoy " .. i, "buoy",
				{ type = "orbit", radius = F.stationTrack, surface = F.planetR, phase = phase })
		end
	end
	if Fields.orbits[area] then
		local d = F.radius - T.driverBarrel - 100
		F.driverId = add("mass_driver", "Mass driver", "driver", { type = "orbit", radius = d + T.driverBarrel / 2,
			surface = F.planetR, flowRadius = d, speedScale = T.driverOrbitScale, phase = -pi / 2 + 0.6 })
	end
	if F.planetR then
		local function gate(to, moon, back)
			local m = Fields.moons[moon]
			add("to_" .. to, "Departure to " .. Fields[to].name, "moon_gate",
				{ type = "orbit", radius = F.radius, phase = m.phase + (back and pi or 0), period = m.period }, nil, to)
		end
		for _, moon in ipairs(Fields.moonsOf(area)) do gate(moon, moon, false) end
		if Fields.moons[area] then gate(Fields.moons[area].parent, area, true) end
	end
 -- These links describe existing journeys, not generated navigation geometry.
 F.travelLinks = {}
 local function link(a,b)
  if a and b and a~=b then F.travelLinks[#F.travelLinks+1]={a,b} end
 end
 if #F.buoyIds == 2 then
  local a,b=F.stationIds[F.city and 2 or 1],F.stationIds[F.city and 3 or 2]
  F.traderRoute={a,F.buoyIds[1],b,F.buoyIds[2]}
  for i,id in ipairs(F.traderRoute) do link(id,F.traderRoute[i%#F.traderRoute+1]) end
  if F.city then link(F.stationIds[1],a) end
 else
  for i=2,#F.stationIds do link(F.stationIds[i-1],F.stationIds[i]) end
 end
 link(F.driverId,F.stationIds[1])
 for _,place in ipairs(F.locations) do
  if place.kind=='moon_gate' then link(place.id,F.driverId or F.stationIds[1]) end
 end

end

return Fields
