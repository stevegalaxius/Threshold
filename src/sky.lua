-- The look of space behind each map.
--
-- Every planet has a "look": a handful of numbers and colours in Sky.looks
-- below. A moon uses its planet's look, a lane keeps the look of the place
-- it left, and a place with no entry gets one worked out from its own
-- colour and its distance from the Sun (further out: colder, darker, more
-- stars). Changing place fades from one look to the next.
--
-- A look is drawn as layers that slide past at different speeds (depth 0 is
-- fixed to the screen, 1 moves with the world):
--   haze   big soft clouds in the look's two colours, almost fixed
--   stars  five layers from many faint far ones to a few nearer ones,
--          gathered into a wavy band (the look's own Milky Way)
-- Each layer is a tile built once into a mesh, so a frame is a few dozen
-- draws whatever the look.
--
-- To give a place its own look, add an entry to Sky.looks. Every field is
-- optional:
--   space  {r,g,b}  the colour of empty space
--   hazeA, hazeB    the two cloud colours
--   haze   0..1     how strong the clouds are
--   stars  number   how many stars (1 is ordinary)
--   warm   -1..1    star colour, from cold blue to warm amber
--   band   0..1     how much the stars gather into the band
local Fields = require("src.fields")
local lg = love.graphics
local floor, max, min, sin, cos, pi, exp = math.floor, math.max, math.min, math.sin, math.cos, math.pi, math.exp
local Sky = {}

Sky.looks = {
	mercury = { space = { 0.05, 0.035, 0.025 }, hazeA = { 1.0, 0.75, 0.4 }, hazeB = { 0.9, 0.45, 0.2 }, haze = 0.9, stars = 0.45, warm = 0.8, band = 0.2 },
	venus = { space = { 0.05, 0.045, 0.025 }, hazeA = { 0.95, 0.8, 0.4 }, hazeB = { 0.8, 0.55, 0.25 }, haze = 0.8, stars = 0.6, warm = 0.6, band = 0.3 },
	earth = { space = { 0.02, 0.035, 0.065 }, hazeA = { 0.25, 0.5, 0.9 }, hazeB = { 0.3, 0.75, 0.7 }, haze = 0.45, stars = 1.0, warm = 0, band = 0.6 },
	mars = { space = { 0.05, 0.028, 0.025 }, hazeA = { 0.85, 0.38, 0.24 }, hazeB = { 0.6, 0.3, 0.4 }, haze = 0.6, stars = 0.9, warm = 0.5, band = 0.5 },
	belt = { space = { 0.03, 0.03, 0.035 }, hazeA = { 0.55, 0.5, 0.45 }, hazeB = { 0.35, 0.4, 0.5 }, haze = 0.3, stars = 1.2, warm = 0.1, band = 0.8 },
	jupiter = { space = { 0.04, 0.03, 0.03 }, hazeA = { 0.85, 0.6, 0.35 }, hazeB = { 0.7, 0.35, 0.3 }, haze = 0.7, stars = 1.0, warm = 0.3, band = 0.6 },
	saturn = { space = { 0.04, 0.036, 0.028 }, hazeA = { 0.9, 0.8, 0.5 }, hazeB = { 0.6, 0.55, 0.7 }, haze = 0.55, stars = 1.1, warm = 0.2, band = 0.7 },
	uranus = { space = { 0.015, 0.04, 0.05 }, hazeA = { 0.4, 0.85, 0.85 }, hazeB = { 0.3, 0.55, 0.9 }, haze = 0.6, stars = 1.3, warm = -0.4, band = 0.8 },
	neptune = { space = { 0.012, 0.02, 0.06 }, hazeA = { 0.25, 0.4, 0.95 }, hazeB = { 0.5, 0.3, 0.85 }, haze = 0.7, stars = 1.4, warm = -0.7, band = 0.9 },
	pluto = { space = { 0.012, 0.012, 0.025 }, hazeA = { 0.5, 0.4, 0.7 }, hazeB = { 0.3, 0.35, 0.55 }, haze = 0.25, stars = 1.8, warm = -0.3, band = 1.0 },
}

-- Which look a map uses: its own, or its planet's, or (a lane) none of its own.
local function lookId(area)
	local f = Fields[area]
	if not f or f.transit then return nil end
	if Sky.looks[area] then return area end
	local moon = Fields.moons and Fields.moons[area]
	if moon and moon.parent then return moon.parent end
	return area
end

-- A look for a place without one: its own colour, and its distance out.
local function derived(area)
	local f = Fields[area] or {}
	local o = Fields.orbits and Fields.orbits[area] or {}
	local hue = f.hue or o.color or { 0.5, 0.6, 0.8 }
	local far = min(1, (o.au or 3) / 30)            -- 0 by the Sun, 1 at the edge
	local dim = 0.05 - 0.02 * far
	return {
		space = { hue[1] * dim, hue[2] * dim, hue[3] * dim + 0.015 },
		hazeA = hue, hazeB = { hue[3], hue[1], hue[2] },
		haze = 0.6 - 0.3 * far, stars = 0.7 + far, warm = 0.5 - far, band = 0.4 + 0.5 * far,
	}
end

-- Everything here stays well behind the play field: depths are small (a
-- layer near depth 1 moves and zooms almost like the world, and reads as
-- things floating over it), stars are never bigger than two pixels and never
-- as bright as debris.
local STARS = {   -- far to near: depth, tile size, point size, how many, brightness
	{ depth = 0.01, tile = 2048, size = 1, n = 2600, alpha = 0.4, band = 1.0 },
	{ depth = 0.025, tile = 2048, size = 1, n = 900, alpha = 0.6, band = 0.7 },
	{ depth = 0.05, tile = 2048, size = 1, n = 260, alpha = 0.8, band = 0.3 },
	{ depth = 0.09, tile = 2048, size = 2, n = 60, alpha = 0.55, band = 0 },
	{ depth = 0.14, tile = 2048, size = 2, n = 14, alpha = 0.75, band = 0 },
}
local HAZE = { depth = 0.006, tile = 2048, reach = 900 }

local function seedOf(id)
	local h = 7
	for i = 1, #id do h = (h * 31 + id:byte(i)) % 1000003 end
	return h
end

local function build(id)
	local spec = Sky.looks[id] or derived(id)
	local base = derived(id)
	for k, v in pairs(base) do if spec[k] == nil then spec[k] = v end end
	local rng = love.math.newRandomGenerator(seedOf(id))
	local look = { space = spec.space, stars = {} }
	-- the band: a wave across the far tiles (it wraps, so the tile repeats cleanly)
	local phase, sway, width = rng:random() * pi * 2, 0.08 + rng:random() * 0.1, 0.07 + rng:random() * 0.05
	local function inBand(x, y, tile)
		local centre = 0.5 + sway * sin(x / tile * pi * 2 + phase)
		local d = (y / tile - centre) / width
		return exp(-d * d)
	end
	for li, L in ipairs(STARS) do
		local v = {}
		local count = floor(L.n * spec.stars)
		local gather = spec.band * L.band
		local tries = 0
		while #v < count and tries < count * 40 do
			tries = tries + 1
			local x, y = rng:random() * L.tile, rng:random() * L.tile
			local near = inBand(x, y, L.tile)
			if rng:random() < (1 - gather) * 0.5 + gather * near then
				-- most stars faint, a few bright; mostly white, some coloured
				local b = L.alpha * (0.35 + 0.65 * rng:random() ^ 2.2)
				local t = max(-1, min(1, spec.warm + (rng:random() - 0.5) * 1.6))
				local r, g, bl = 0.82 + 0.18 * max(0, t), 0.88 + 0.06 * (1 - math.abs(t)), 0.82 + 0.18 * max(0, -t)
				v[#v + 1] = { x, y, 0, 0, r, g, bl, b }
			end
		end
		look.stars[li] = { depth = L.depth, tile = L.tile, size = L.size, mesh = #v > 0 and lg.newMesh(v, "points", "static") or nil }
	end
	-- haze: soft clouds, more of them along the band
	do
		local v = {}
		local function cloud(x, y, rx, ry, c, a)
			local n = 20
			for i = 0, n - 1 do
				local a1, a2 = i / n * pi * 2, (i + 1) / n * pi * 2
				local c1, s1, c2, s2 = cos(a1), sin(a1), cos(a2), sin(a2)
				local mid = a * 0.42
				-- centre to half way, then half way to the rim (a soft falloff)
				v[#v + 1] = { x, y, 0, 0, c[1], c[2], c[3], a }
				v[#v + 1] = { x + c1 * rx * 0.5, y + s1 * ry * 0.5, 0, 0, c[1], c[2], c[3], mid }
				v[#v + 1] = { x + c2 * rx * 0.5, y + s2 * ry * 0.5, 0, 0, c[1], c[2], c[3], mid }
				v[#v + 1] = { x + c1 * rx * 0.5, y + s1 * ry * 0.5, 0, 0, c[1], c[2], c[3], mid }
				v[#v + 1] = { x + c1 * rx, y + s1 * ry, 0, 0, c[1], c[2], c[3], 0 }
				v[#v + 1] = { x + c2 * rx, y + s2 * ry, 0, 0, c[1], c[2], c[3], 0 }
				v[#v + 1] = { x + c1 * rx * 0.5, y + s1 * ry * 0.5, 0, 0, c[1], c[2], c[3], mid }
				v[#v + 1] = { x + c2 * rx, y + s2 * ry, 0, 0, c[1], c[2], c[3], 0 }
				v[#v + 1] = { x + c2 * rx * 0.5, y + s2 * ry * 0.5, 0, 0, c[1], c[2], c[3], mid }
			end
		end
		local T = HAZE.tile
		for i = 1, 12 do
			local x = rng:random() * T
			local along = i <= 8
			local y = along and (0.5 + sway * sin(x / T * pi * 2 + phase) + (rng:random() - 0.5) * width * 2) * T or rng:random() * T
			local r = 350 + rng:random() * (HAZE.reach - 350)
			local c = rng:random() < 0.6 and spec.hazeA or spec.hazeB
			cloud(x, y, r, r * (0.5 + rng:random() * 0.5), c, spec.haze * (0.1 + rng:random() * 0.12))
		end
		look.haze = lg.newMesh(v, "triangles", "static")
	end
	return look
end

local built = {}
local function lookOf(id)
	local look = built[id]
	if not look then look = build(id); built[id] = look end
	return look
end
-- (after editing Sky.looks while the game runs)
function Sky.rebuild() built = {} end

local function tiles(mesh, cam, depth, tile, margin, w, h, size)
	local hw, hh = w / 2, h / 2
	local scale = cam.zoom ^ depth
	local cx, cy = (cam.x + (cam.backgroundX or 0)) * depth, (cam.y + (cam.backgroundY or 0)) * depth
	local tx1, tx2 = floor((cx - hw / scale - margin) / tile), floor((cx + hw / scale + margin) / tile)
	local ty1, ty2 = floor((cy - hh / scale - margin) / tile), floor((cy + hh / scale + margin) / tile)
	local nudge = size and size / 2 - 0.5 or 0
	for tx = tx1, tx2 do
		for ty = ty1, ty2 do
			lg.draw(mesh, hw + (tx * tile - cx) * scale + nudge, hh + (ty * tile - cy) * scale + nudge, 0, scale, scale)
		end
	end
end

local function drawLook(look, cam, alpha, w, h)
	lg.setColor(1, 1, 1, alpha)
	lg.setBlendMode("add")
	tiles(look.haze, cam, HAZE.depth, HAZE.tile, HAZE.reach, w, h)
	lg.setBlendMode("alpha")
	for _, layer in ipairs(look.stars) do
		if layer.mesh then
			local size = max(1, layer.size * cam.zoom ^ layer.depth)
			lg.setPointSize(size)
			tiles(layer.mesh, cam, layer.depth, layer.tile, 0, w, h, size)
		end
	end
end

-- Between planets: plain deep space, none of either planet's colour.
Sky.looks.void = { space = { 0.012, 0.014, 0.022 }, hazeA = { 0.4, 0.45, 0.6 }, hazeB = { 0.3, 0.3, 0.45 }, haze = 0.12, stars = 1.2, warm = 0, band = 0.7 }

local function mix(a, b, t, cam)
	local w, h = lg.getDimensions()
	local o, s = a.space, b.space
	lg.clear(o[1] + (s[1] - o[1]) * t, o[2] + (s[2] - o[2]) * t, o[3] + (s[3] - o[3]) * t)
	if t < 1 then drawLook(a, cam, 1 - t, w, h) end
	if t > 0 then drawLook(b, cam, t, w, h) end
	lg.setColor(1, 1, 1)
end

local now, before, changed = nil, nil, 0
Sky.fade = 2.5   -- seconds from one look to the next (debug teleports, loads)
-- area: the map you're in. toward and arrived (0..1): on a lane, where it
-- leads and how far you've slowed toward it. The planet you left is gone
-- the moment the lane takes you; the next one comes up as you slow down,
-- and it's fully there when you arrive, so arriving changes nothing.
function Sky.draw(cam, area, toward, arrived)
	local time = love.timer.getTime()
	local dest = toward and lookId(toward)
	if dest then
		now, before = dest, nil
		mix(lookOf("void"), lookOf(dest), max(0, min(1, arrived or 0)), cam)
		return
	end
	local id = lookId(area) or now or "earth"
	if id ~= now then
		before, changed = now, time
		now = id
	end
	local t = before and min(1, (time - changed) / Sky.fade) or 1
	if t >= 1 then before = nil end
	if before then mix(lookOf(before), lookOf(now), t, cam)
	else mix(lookOf(now), lookOf(now), 1, cam) end
end

return Sky
