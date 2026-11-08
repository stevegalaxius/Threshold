--[[
	Playing fields, which are the game's levels: what the arena is filled
	with. Each field has a name, where the player launches from, and a build
	function that places everything. Optional:
	  enemies   { { enemy id, count }, ... } placed around the level; they
	            leave you alone until you come close (T.aggroRange)
	Station identities, names and placements are authored in src/world_layout.lua.
	Every planet map has a mass driver. Fly into it, pick a planet on its
	orrery, and it fires you into a transit lane (the "lane" field) toward
	that planet; you
	come out the far end at the other planet's driver, still moving fast.
	F1 debug travel and the map teleport controls select named destinations
	for testing.

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

Fields.list = { "mercury", "venus", "earth", "luna", "mars", "phobos", "deimos", "belt", "ring", "quarry", "ceres_quarry", "jupiter", "io", "europa", "ganymede", "callisto",
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
	-- not a moon: Ring Station's mining field, a short hop out from the hub
	-- (the phase fixes which side of the hub's map the way out is on)
	quarry = { parent = "ring", period = 1, phase = 0.9, gap = 16000, color = { 0.7, 0.62, 0.5 } },
	-- and Ceres's: Ceres itself is drilled for ice, rock comes from here
	ceres_quarry = { parent = "belt", period = 1, phase = 2.4, gap = 14000, color = { 0.66, 0.6, 0.52 } },
}

-- The moons of a planet, in a fixed order.
function Fields.moonsOf(planet)
	local out = {}
	for id, m in pairs(Fields.moons) do if m.parent == planet then table.insert(out, id) end end
	table.sort(out)
	return out
end

-- The moons that share a planet with this one (its sisters), in a fixed order.
function Fields.siblingMoons(id)
	local m = Fields.moons[id]
	local out = {}
	if not m then return out end
	for _, other in ipairs(Fields.moonsOf(m.parent)) do
		if other ~= id then table.insert(out, other) end
	end
	return out
end

-- The highway between two sister moons: the bearing (radians) it leaves
-- moon a on, and its length in px. Each moon is put at its gap along its
-- authored phase round the planet, the same fixed frame the planet's
-- corridors use, so the corridor stays put while the moons orbit.
function Fields.moonLink(a, b)
	local ma, mb = Fields.moons[a], Fields.moons[b]
	local ax, ay = cos(ma.phase) * ma.gap, sin(ma.phase) * ma.gap
	local bx, by = cos(mb.phase) * mb.gap, sin(mb.phase) * mb.gap
	local dx, dy = bx - ax, by - ay
	return math.atan2(dy, dx), math.max(12000, math.sqrt(dx * dx + dy * dy))
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
	instance = true,
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
 miningAsteroids={{x=0,y=0,radius=1800}},
	instance = true,
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
	instance = true,
	name = "Space station",
	spawn = { 0, 2600 },
	radius = 9000,
	enemies = { { "swarmer", 2 } },
	build = function(game)
		for _,id in ipairs(Fields.station.stationIds) do require("src.locations").spawnStation(game,id) end
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
--   landable           enable soft terrain contacts for mining worlds only
--   city               a cloud city's name: a station floating in a gas
--                      giant's cloud tops, above the crush (station 1)
--   enemies            { { enemy id, count }, ... }
--   gas                a gas giant (see Game:spawnGasGiant)
--   extra(game, R)     more to build once the planet is in
local function planetField(o)
	local name, R = o.name, o.R
	-- T.mapScale stretches every planet map's open space; T.mapDensity
	-- thins its debris so a bigger map doesn't carry (scale^2) more rocks.
	local depth = (o.depth or 35000) * T.mapScale
	local dens = T.mapDensity
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
			table.insert(bands, { R + depth * rb[1], R + depth * rb[2], (rb.density or 0) * dens, { ice = 1 },
				size = function() return random() < big and 60 + random() * 60 or 10 + random() ^ 3 * 60 end })
		end
	elseif o.belts then
		-- several belts, each { inner, outer (fractions of depth), density
		-- per million px^2, mix }
		for _, b in ipairs(o.belts) do
			table.insert(bands, { R + depth * b[1], R + depth * b[2], b[3] * dens, b[4] or { rock = 1 } })
		end
	else
		bands[1] = { beltIn, beltOut, (o.belt or 0) * dens, o.beltMix or { rock = 1 } }
	end
	local scattered = floor((o.density or 0) * dens * area(looseIn, edge))
	-- the planet's colour, the same every visit (so it can be drawn ahead
	-- of you on the highway before you arrive)
	local rng = love.math.newRandomGenerator(#name * 7919 + R)
	local hue = { 0.35 + rng:random() * 0.2, 0.45 + rng:random() * 0.2, 0.7 + rng:random() * 0.2 }
	if o.hue then hue = o.hue end
	local field
	field = {
		name = name,
		stationTrack = sd, surfaceMine = o.surfaceMine, city = o.city, cityScale = o.cityScale, traderPopulation = o.traders or 5,
		planetR = R, gas = o.gas, hue = hue, rocky = o.rocky, landable = o.landable, lumpy = o.lumpy, maria = o.maria, parent = o.parent,
		mix = o.mix or MIX.inner,
		rings = o.gas and bands or nil,
		enemies = o.enemies,
		spawn = { 0, sd - 800 },
		belt = { beltIn, beltOut },
		radius = edge,
		rockDrag = 0,
		build = function(game)
			local planet = o.gas and game:spawnGasGiant(0, 0, R, 290, 0.1, hue)
				or game:spawnPlanet(0, 0, R, 290, 0.1, o.rocky and Fields.rockShape(name, R, o.lumpy, o.maria), o.landable)
			if not o.gas then planet.hue = hue end
			if o.gas then planet.rings = bands end
			-- The catalogue drives both physical construction and remote navigation.
            local Locations=require('src.locations')
            for _,id in ipairs(field.stationIds) do Locations.spawnStation(game,id) end
            for _,id in ipairs(field.buoyIds) do
                local buoy=game:spawnBuoy(0,0,id);local m=Locations.get(id).motion
                game:setOrbit(buoy,m.cx or 0,m.cy or 0,Locations.rate(m)*m.radius)
            end
            if o.extra then o.extra(game,R) end

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
-- planet: a turning wheel station in a wide clear space kept by traffic
-- control, with only loose rock drifting in from the field. The mining is
-- next door in the Quarry (Fields.quarry), reached the way a moon is.
Fields.ring = {
	name = "Ring Station",
	spawn = { 0, 3800 * T.mapScale },
	radius = 26000 * T.mapScale,
	mix = MIX.belt,
	enemies = { { "swarmer", 2 }, { "interceptor", 1 } },
	build = function(game)
		for _,id in ipairs(Fields.ring.stationIds) do require("src.locations").spawnStation(game,id) end
		-- a thin scattering of rock from well outside the hub to the edge
		local S = T.mapScale
		local area = pi * ((26000 * S) ^ 2 - (9000 * S) ^ 2) / 1e6
		game:spawnAsteroids(floor(area * 0.035 * T.mapDensity), 9000 * S)
		game:spawnContainers(T.fieldContainers, 6000)
	end,
}

-- A quarry: a station's mining field, its own map off the edge of its
-- parent's (Fields.moons). Thick belt rock, a few huge rocks the drill
-- crews work, and an ore depot they haul back to.
local function quarryField(id, name)
	local f
	f = {
		miningAsteroids = {},
		name = name,
		spawn = { 0, 3000 * T.mapScale },
		radius = 22000 * T.mapScale,
		mix = MIX.belt,
		enemies = { { "swarmer", 3 }, { "interceptor", 2 }, { "gunner", 2 } },
		build = function(game)
			for _,sid in ipairs(f.stationIds) do require("src.locations").spawnStation(game,sid) end
			for _,s in ipairs(f.miningAsteroids) do game:spawnGiantAsteroid(s.x,s.y,s.radius) end
			-- thick rock from the depot's clear zone out to the edge
			local S = T.mapScale
			local area = pi * ((22000 * S) ^ 2 - (4500 * S) ^ 2) / 1e6
			game:spawnAsteroids(floor(area * 0.18 * T.mapDensity), 4500 * S)
			game:spawnContainers(T.fieldContainers, 4500)
		end,
	}
	for k = 0, 3 do
		local a, d = k / 4 * pi * 2 + 0.4, (8000 + (k % 2) * 4500) * T.mapScale
		f.miningAsteroids[#f.miningAsteroids + 1] = { x = cos(a) * d, y = sin(a) * d, radius = 900 + (k % 3) * 400 }
	end
	Fields[id] = f
end
quarryField("quarry", "Ring Quarry")
quarryField("ceres_quarry", "Ceres Quarry")

-- Authored industrial sites, shared by the catalogue and the simulation.
function Fields.miningSources(area)
 local f=Fields[area];local sources={}
 if f.landable then sources[1]={x=0,y=0,radius=f.planetR,planet=true,ore=f.drillOre} end
 for _,source in ipairs(f.miningAsteroids or {}) do sources[#sources+1]=source end
 return sources
end

-- Each planet's map. Planet sizes are as set; how roomy a map is comes
-- from depth, and its character from density, mix and belt.
Fields.mercury = planetField({ name = "Mercury", R = 5700, depth = 15000, rocky = true, lumpy = 0,
	density = 0.07, mix = { junk = 3, sat = 2, rock = 5 }, belt = 1.1,
	enemies = { { "gunner", 2 }, { "swarmer", 2 } } })
Fields.venus = planetField({ name = "Venus", R = 14300, depth = 18000,
	density = 0.1, mix = MIX.inner, belt = 1.1,
	enemies = { { "gunner", 2 }, { "swarmer", 3 } } })
Fields.earth = planetField({ name = "Earth", R = 15000, depth = 18000,
	density = 0.1, mix = MIX.inner, belt = 1.1,
	enemies = { { "brawler", 2 }, { "sniper", 2 }, { "gunner", 2 } } })
Fields.mars = planetField({ name = "Mars", R = 7500, depth = 17000, hue = { 0.85, 0.38, 0.24 },   -- rust red
	density = 0.005, mix = { junk = 7, sat = 5, rock = 1 },
	belt = 0.025, beltMix = { junk = 7, sat = 5, rock = 1 }, traders = 9,
	enemies = { { "gunner", 2 }, { "interceptor", 2 } },
	extra = function(game, R) if game.field.ladderId then game:spawnHeavenLadder(0, 0, R + 1100) end end })
-- The asteroid belt: Ceres in the middle and rock everywhere.
-- Close in, Ceres's own ice and rock; out past the station track, the belt
-- proper, all rock, thickening toward the edge of the map.
Fields.belt = planetField({ name = "Ceres", R = 2500, depth = 20000, rocky = true, landable = true, lumpy = 0.15,
	density = 0.12, mix = { rock = 1 },
	belts = { { 0.06, 0.4, 0.9, { ice = 1, rock = 1 } }, { 0.7, 0.97, 0.5, { rock = 1 } } },
	enemies = { { "swarmer", 3 }, { "interceptor", 2 }, { "brawler", 1 } } })
-- Ceres's surface drill brings up ice; its rock is mined in the Ceres Quarry.
Fields.belt.drillOre = "ice"
Fields.jupiter = planetField({ name = "Jupiter", R = 45000, depth = 22000, gas = true,
	hue = { 0.85, 0.65, 0.45 },
	-- ring stretched out to the edge (x2.43 from the surface); stations
	-- orbit inside it
	density = 0.08, mix = MIX.giant, track = 0.4, rings = { { 0.485, 0.97, density = 1.5 } },
	city = true, cityScale = 2,
	enemies = { { "brawler", 3 }, { "sniper", 2 }, { "interceptor", 3 } } })
Fields.saturn = planetField({ name = "Saturn", R = 45000, depth = 34000, gas = true,
	hue = { 0.9, 0.8, 0.55 },
	density = 0.08, mix = { ice = 6, rock = 4 }, track = 0.71,   -- in the Cassini division
	-- C ring (faint), B ring (dense, the odd big chunk), the Cassini
	-- division, then the A ring (medium)
	-- (stretched x1.617 from the surface so the A ring meets the edge)
	rings = { { 0.243, 0.404, density = 0.5 }, { 0.404, 0.679, density = 3, big = 0.03 }, { 0.744, 0.97, density = 1.5 } },
	enemies = { { "gunner", 3 }, { "sniper", 2 }, { "swarmer", 3 } } })
Fields.uranus = planetField({ name = "Uranus", R = 30000, depth = 20000, gas = true,
	hue = { 0.55, 0.85, 0.9 },
	-- ring stretched out to the edge (x2.43); stations orbit inside it
	density = 0.09, mix = MIX.ice, track = 0.45, rings = { { 0.606, 0.97, density = 2 } },
	city = true,
	enemies = { { "interceptor", 3 }, { "sniper", 2 } } })
Fields.neptune = planetField({ name = "Neptune", R = 30000, depth = 20000, gas = true,
	hue = { 0.35, 0.5, 0.95 },
	density = 0.09, mix = { ice = 9, rock = 1 }, -- four dense rings, well out from the planet, in pairs: a wider ring
	-- then a thin one just outside it, twice
	-- (stretched x1.183 so the outer pair meets the edge; stations in the
	-- wide gap between the pairs)
	track = 0.7,
	rings = { { 0.399, 0.461, density = 6 }, { 0.564, 0.590, density = 6 }, { 0.822, 0.885, density = 6 }, { 0.951, 0.97, density = 6 } },
	enemies = { { "brawler", 3 }, { "interceptor", 3 }, { "sniper", 2 } } })

-- The moons' maps (see Fields.moons). Airless bodies retain their rocky
-- silhouettes; infrastructure can be added separately without replacing them.
Fields.luna = planetField({ name = "Luna", R = 4000, depth = 15000, rocky = true, lumpy = 0, maria = 6, parent = "earth",
	hue = { 0.62, 0.62, 0.6 }, density = 0.08, mix = { rock = 6, junk = 3, sat = 1 }, belt = 0.6,
	enemies = { { "gunner", 2 }, { "swarmer", 2 } } })
Fields.phobos = planetField({ name = "Phobos", surfaceMine = true, R = 1400, depth = 9000, rocky = true, landable = true, parent = "mars",
	hue = { 0.5, 0.42, 0.38 }, density = 0.04, mix = { rock = 1 }, belt = 0.45, beltIn = 0.15, beltOut = 0.4 })
Fields.deimos = planetField({ name = "Deimos", surfaceMine = true, R = 800, depth = 9000, rocky = true, landable = true, parent = "mars",
	hue = { 0.55, 0.48, 0.42 }, density = 0.035, mix = { rock = 1 }, belt = 0.3, beltIn = 0.15, beltOut = 0.4 })
Fields.io = planetField({ name = "Io", R = 4500, depth = 14000, parent = "jupiter", rocky = true, lumpy = 0,
	hue = { 0.85, 0.65, 0.25 }, density = 0.035, mix = { rock = 7, junk = 3 }, belt = 0.15,
	enemies = { { "gunner", 2 }, { "interceptor", 1 } } })
Fields.callisto = planetField({ name = "Callisto", R = 6000, depth = 16000, parent = "jupiter", rocky = true, lumpy = 0,
	hue = { 0.48, 0.45, 0.42 }, density = 0.08, mix = { rock = 6, ice = 3, junk = 1 }, belt = 0.4,
	enemies = { { "swarmer", 2 }, { "gunner", 2 } } })
Fields.enceladus = planetField({ name = "Enceladus", R = 2600, depth = 13000, parent = "saturn", rocky = true, lumpy = 0,
	hue = { 0.72, 0.85, 0.9 }, density = 0.09, mix = { ice = 9, junk = 1 },
	belt = 0.7, beltMix = { ice = 1 },
	enemies = { { "interceptor", 2 } } })
Fields.pluto = planetField({ name = "Pluto", R = 3000, depth = 16000, rocky = true, lumpy = 0,
	hue = { 0.65, 0.52, 0.45 }, density = 0.06, mix = { ice = 8, rock = 2 },
	belt = 0.35, beltMix = { ice = 1 },
	enemies = { { "sniper", 1 }, { "interceptor", 2 } } })
Fields.europa = planetField({ name = "Europa", R = 3800, depth = 15000, parent = "jupiter", rocky = true, lumpy = 0,
	hue = { 0.85, 0.8, 0.7 }, density = 0.08, mix = { ice = 8, rock = 2 }, belt = 0.8,
	enemies = { { "interceptor", 2 }, { "sniper", 1 } } })
Fields.ganymede = planetField({ name = "Ganymede", R = 6000, depth = 17000, parent = "jupiter", rocky = true, lumpy = 0,
	hue = { 0.6, 0.58, 0.55 }, density = 0.08, mix = { ice = 5, rock = 5 }, belt = 0.8,
	enemies = { { "brawler", 2 }, { "gunner", 2 } } })
Fields.titan = planetField({ name = "Titan", R = 6000, depth = 17000, parent = "saturn",
	hue = { 0.9, 0.62, 0.3 }, density = 0.07, mix = { ice = 6, rock = 4 }, belt = 0.7,
	enemies = { { "gunner", 2 }, { "sniper", 2 } } })
Fields.titania = planetField({ name = "Titania", R = 2000, depth = 14000, parent = "uranus", rocky = true, lumpy = 0,
	hue = { 0.62, 0.64, 0.67 }, density = 0.07, mix = { ice = 6, rock = 3, junk = 1 },
	belt = 0.45, beltMix = { ice = 7, rock = 3 },
	enemies = { { "interceptor", 2 }, { "gunner", 1 } } })
Fields.triton = planetField({ name = "Triton", R = 3200, depth = 15000, parent = "neptune", rocky = true, lumpy = 0,
	hue = { 0.75, 0.8, 0.85 }, density = 0.09, mix = { ice = 9, rock = 1 }, belt = 0.8,
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
local WorldLayout=require('src.world_layout')
function Fields.configureLocations(area)
	local F = Fields[area]
	F.locations, F.stationIds, F.buoyIds = {}, {}, {}
 F.ladderId,F.ladderIds=nil,nil
	local function add(id, name, kind, motion, spin, destination)
		local full = kind=="station" and id or area .. "/" .. id
		F.locations[#F.locations + 1] = { id = full, area = area, name = name, kind = kind,
			motion = motion, spin = spin, destination = destination }
		return full
	end
    F.navigation=WorldLayout.navigation[area] or {}
    local entries={}
    for _,entry in ipairs(WorldLayout.stations[area] or {}) do if entry.enabled~=false then entries[#entries+1]=entry end end
    local orbitCount=0
    for _,entry in ipairs(entries) do if not entry.adapter and (not entry.motion or entry.motion.type=='orbit') then orbitCount=orbitCount+1 end end
    F.stations={}
    local orbitIndex=0
    for i,entry in ipairs(entries) do
        local id=assert(entry.id,'station needs a stable id')
        local motion,spin=entry.motion,entry.spin
        if entry.position then
            local p=entry.position
            if F.stationTrack and not p.fixed then
                local radius=math.sqrt(p.x*p.x+p.y*p.y)
                assert(radius>0,'orbiting station must be outside the planet centre')
                motion={type='orbit',radius=radius,phase=math.atan2(p.y,p.x),surface=F.planetR}
            else motion={type='fixed',x=p.x,y=p.y} end
        end
        local wheel=entry.wheel or {900,120}
        local layout=entry.layout or require('src.stations').ringId(wheel[1],wheel[2])
        if entry.adapter=='surface_mine' then
            local outline=Fields.rockShape(F.name,F.planetR,F.lumpy,F.maria).outline
            local x,y=0,math.huge
            for j=1,#outline,2 do if outline[j+1]<y then x,y=outline[j],outline[j+1] end end
            motion=motion or {type='fixed',x=x,y=y-100};spin=spin or 0
        elseif entry.adapter=='cloud' then
            local tunnel=require('src.stations').CITY_TUNNEL
            local top,bottom=F.planetR-60-tunnel,F.planetR-F.planetR/13+tunnel+100
            motion=motion or {type='cloud',a=-pi/2+.35,r=(top+bottom)/2,
                up=math.max(0,(top-bottom)/2*.85),across=T.cityDriftAcross,
                upPeriod=T.cityDriftUp,acrossPeriod=T.cityDriftAcrossPeriod,phase=area=='jupiter' and .7 or 2.1}
            layout=entry.layout or 'city_'..(F.cityScale or 1)
        elseif F.stationTrack and (not motion or motion.type=='orbit') then
            orbitIndex=orbitIndex+1
            motion=motion or {type='orbit',radius=entry.radius or F.stationTrack,surface=F.planetR,
                phase=entry.phase or -.8+(orbitIndex-1)*pi*2/math.max(1,orbitCount)}
            spin=spin or (orbitIndex==1 and .05 or -.05)
        else
            motion=motion or {type='fixed',x=0,y=0};spin=spin or .04
        end
        F.stations[i]=entry.name or id
        F.stationIds[i]=add(id,F.stations[i],'station',motion,spin)
        local place=F.locations[#F.locations]
        place.layout,place.wheel,place.adapter=layout,wheel,entry.adapter
        place.marketId=entry.marketId or WorldLayout.defaults.marketId
        -- what this station offers and makes belong to the place, not its design
        place.services,place.industry=entry.services,entry.industry
        place.primary,place.uses=entry.primary,{trade=true,mining=true,patrol=true}
        for purpose,enabled in pairs(entry.uses or {}) do place.uses[purpose]=enabled end
    end
    local function home(purpose)
        local candidates={}
        for _,place in ipairs(F.locations) do
            if place.uses[purpose] then candidates[#candidates+1]=place end
        end
        table.sort(candidates,function(a,b)
            if not not a.primary~=not not b.primary then return not not a.primary end
            return a.id<b.id
        end)
        return candidates[1] and candidates[1].id
    end
    F.tradeHome,F.miningHome=home('trade'),home('mining')
    local population=F.navigation.population or {}
    F.alifeTraders=F.tradeHome and not F.surfaceMine and (population.trader~=nil and population.trader or F.traderPopulation) or nil

	-- The Heaven-Ladder (Mars): one station with four elevator anchors as its
	-- access points, each a location (and a travel-graph node) of its own.
	-- The first is the station's identity; the others say accessOf it, so
	-- routes to the Ladder end at whichever anchor is nearest, and all four
	-- share its storage, hangar and market (see Game:spawnHeavenLadder).
	if area == "mars" and F.planetR and WorldLayout.specials.heavenLadder.enabled~=false then
		local LR = F.planetR + 1100
		F.ladderIds = {}
		for k = 0, 3 do
			local a = (k * 2 + 1) / 8 * pi * 2
			local lid = add(WorldLayout.specials.heavenLadder.access[k+1],
				k == 0 and "Heaven-Ladder" or ("Heaven-Ladder anchor " .. (k + 1)), "station",
				{ type = "fixed", x = cos(a) * LR, y = sin(a) * LR }, 0)
			local place = F.locations[#F.locations]
			place.heading,place.layout,place.uses = a,"ladder_anchor",{patrol=true}
            place.marketId=WorldLayout.specials.heavenLadder.marketId
			if k > 0 then place.accessOf = F.ladderIds[1] end
			F.ladderIds[k + 1] = lid
		end
		F.ladderId = F.ladderIds[1]
	end
	if F.stationTrack then
        local specs=F.navigation.buoys
        local count=type(specs)=="table" and #specs or assert(specs,"rotating region needs a buoy definition: "..area)
        assert(count>=2,"rotating regions need at least two navigation buoys")
        for i=1,count do
            local spec=type(specs)=='table' and specs[i] or {}
            F.buoyIds[i]=add(spec.id or ('trade_buoy_'..string.char(96+i)),spec.name or ('Trade buoy '..i),'buoy',
                {type='orbit',radius=spec.radius or F.stationTrack,surface=F.planetR,
                 phase=spec.phase or -.8+pi/2+(i-1)*pi*2/count},spec.spin or 0)
            local place=F.locations[#F.locations]
            place.prop=spec.prop
            if place.prop==nil then place.prop=F.navigation.buoyProp end
            if place.prop==nil then place.prop=WorldLayout.defaults.buoyProp end
            place.scale,place.heading=spec.scale or 1,spec.heading or 0
		end
	end
	if Fields.orbits[area] then
		local d = F.radius - T.driverBarrel - 100
		F.driverId = add("mass_driver", "Mass driver", "driver", { type = "orbit", radius = d + T.driverBarrel / 2,
			surface = F.planetR, flowRadius = d, speedScale = T.driverOrbitScale, phase = -pi / 2 + 0.6 })
	end
	do -- moon gates (also the Quarry's, off Ring Station, which has no planet)
		local function gate(to, moon, back)
			local m = Fields.moons[moon]
			add("to_" .. to, "Departure to " .. Fields[to].name, "moon_gate",
				{ type = "orbit", radius = F.radius, phase = m.phase + (back and pi or 0), rate = 0 }, nil, to)
		end
		for _, moon in ipairs(Fields.moonsOf(area)) do gate(moon, moon, false) end
		if Fields.moons[area] then gate(Fields.moons[area].parent, area, true) end
		-- Sister corridors sit on their true bearing, nudged along the edge
		-- so no two exits' arcs overlap (the planet's stays where it is).
		local moon = Fields.moons[area]
		if moon then
			local sep = T.departArc / F.radius * 1.25
			local function d(a, b) return (b - a + pi) % (2 * pi) - pi end
			local fixed, ways = moon.phase + pi, {}
			for _, sister in ipairs(Fields.siblingMoons(area)) do
				ways[#ways + 1] = { id = sister, a = (Fields.moonLink(area, sister)) }
			end
			for _ = 1, 40 do
				for i, w in ipairs(ways) do
					local k = d(fixed, w.a)
					if math.abs(k) < sep then w.a = fixed + (k >= 0 and sep or -sep) end
					for j = i + 1, #ways do
						local o = ways[j]
						local e = d(w.a, o.a)
						if math.abs(e) < sep then
							local push = (sep - math.abs(e)) / 2 * (e >= 0 and 1 or -1)
							w.a, o.a = w.a - push, o.a + push
						end
					end
				end
			end
			for _, w in ipairs(ways) do
				add("to_" .. w.id, "Departure to " .. Fields[w.id].name, "moon_gate",
					{ type = "orbit", radius = F.radius, phase = w.a, rate = 0 }, nil, w.id)
			end
		end
	end
 F.drillIds={}
 for i,source in ipairs(Fields.miningSources(area)) do
  F.drillIds[i]=add('drill/'..i,'Drill site '..i,'mining_site',
   {type='mining',x=source.x,y=source.y,radius=source.radius,planet=source.planet,home=source.home or F.miningHome})
 end
 F.holdingId=nil
 if #F.stationIds==0 and #F.buoyIds==0 then
  F.holdingId=add('holding','Holding position','waypoint',{type='fixed',x=F.spawn and F.spawn[1] or 0,y=F.spawn and F.spawn[2] or 0})
 end
 -- Population defaults depend on available navigation, not an exact buoy count.
 F.alifeSecurity=Fields.orbits[area] and F.tradeHome and #F.buoyIds>=2 and {patrol=population.patrol or 2,pirate=population.pirate or 1} or nil
 WorldLayout.connect(F)

end

for _,area in ipairs(Fields.list) do Fields.configureLocations(area) end

return Fields
