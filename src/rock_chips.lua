--[[
	Rock chips: how loose rock and ice come apart under fire.

	A rock or ice asteroid doesn't split into smaller rocks any more. Each
	slice of weapon damage cuts a facet off the side that was hit: a flat
	cut, a random depth, so what flies off is anything from a sliver to a
	chunk. A piece big enough is a rock of its own and chips on in turn; a
	small one is a chip, the smallest unit, which pops into ore when shot
	(plain iron or ice only to a drill, two units; rare ore to any
	weapon, one shot or two drilled). Whatever's left when the rock's
	health runs out is cut in two a last time.

	Rare ore: now and then a big rock holds a gold core, or big ice a
	crystal. Ice is clear, so its crystal shows from the start; a rock shows
	only a vein running in toward its core, until a cut reaches it. From
	then on the core is a gold face in the rock, and every cut through it
	throws off gold. Cut away the stone round it and what's left is the
	motherlode. A piece that is mostly core is rare ore; a chunk with a bit
	of core in it carries that bit with it.

	Shapes are body-local polygons; cutting keeps them convex (one cut of a
	convex polygon is convex), so they stay valid physics shapes.

	Rocks that NPC mining sites own (e.miningId) keep the old drill-only
	rule: their crews and the site's books depend on it (src/mining.lua).
]]
local T = require('src.tuning')
local Ore = require('src.ore')
local C = {}
local random, sqrt, cos, sin, max, min, floor, pi, abs = love.math.random, math.sqrt, math.cos, math.sin, math.max, math.min, math.floor, math.pi, math.abs

-- Damage that isn't a weapon (bumps, heat, exhaust wash) wears a rock down
-- without chipping it, so a crowded belt doesn't fill up with chips.
local NOT_WEAPON = { ram = true, crash = true, crushed = true, heat = true, exhaust = true }

function C.weapon(cause) return cause ~= nil and not NOT_WEAPON[cause] end

-- Which kinds of debris chip, and what they give.
function C.chips(e)
	return e.kind == 'asteroid' and not e.giant and not e.miningId and not e.chip
		and Ore.items[e.debris or 'rock'] ~= nil
end

---------------------------------------------------------------- polygons

local function area(p)
	local s = 0
	for i = 1, #p, 2 do
		local j = i + 2 > #p and 1 or i + 2
		s = s + p[i] * p[j + 1] - p[j] * p[i + 1]
	end
	return abs(s) / 2
end

local function centroid(p)
	local cx, cy, a = 0, 0, 0
	for i = 1, #p, 2 do
		local j = i + 2 > #p and 1 or i + 2
		local f = p[i] * p[j + 1] - p[j] * p[i + 1]
		cx, cy, a = cx + (p[i] + p[j]) * f, cy + (p[i + 1] + p[j + 1]) * f, a + f
	end
	if abs(a) < 1e-9 then return p[1], p[2] end
	return cx / (3 * a), cy / (3 * a)
end

-- The part of p with (x, y) . (ux, uy) <= c (sign = 1), or >= c (sign = -1).
local function clip(p, ux, uy, c, sign)
	local out = {}
	local n = #p
	for i = 1, n, 2 do
		local j = i + 2 > n and 1 or i + 2
		local ax, ay, bx, by = p[i], p[i + 1], p[j], p[j + 1]
		local da, db = (ax * ux + ay * uy - c) * sign, (bx * ux + by * uy - c) * sign
		if da <= 0 then out[#out + 1] = ax; out[#out + 1] = ay end
		if (da < 0) ~= (db < 0) and da ~= db then
			local t = da / (da - db)
			out[#out + 1] = ax + (bx - ax) * t; out[#out + 1] = ay + (by - ay) * t
		end
	end
	return #out >= 6 and out or nil
end

-- Physics polygons take at most 8 corners: drop the flattest ones.
local function cap(p)
	while #p > 16 do
		local best, bi = math.huge, 1
		local n = #p
		for i = 1, n, 2 do
			local h = i - 2 < 1 and n - 1 or i - 2
			local j = i + 2 > n and 1 or i + 2
			local a = abs((p[i] - p[h]) * (p[j + 1] - p[h + 1]) - (p[j] - p[h]) * (p[i + 1] - p[h + 1]))
			if a < best then best, bi = a, i end
		end
		table.remove(p, bi); table.remove(p, bi)
	end
	return p
end

local function shift(p, dx, dy)
	if not p then return nil end
	local q = {}
	for i = 1, #p, 2 do q[i], q[i + 1] = p[i] - dx, p[i + 1] - dy end
	return q
end

local function reach(p)
	local r = 0
	for i = 1, #p, 2 do r = max(r, p[i] * p[i] + p[i + 1] * p[i + 1]) end
	return sqrt(r)
end

local function inside(p, x, y)
	local sgn
	for i = 1, #p, 2 do
		local j = i + 2 > #p and 1 or i + 2
		local s = (p[j] - p[i]) * (y - p[i + 1]) - (p[j + 1] - p[i + 1]) * (x - p[i])
		if sgn == nil then sgn = s >= 0 elseif (s >= 0) ~= sgn and abs(s) > 1e-6 then return false end
	end
	return true
end
C.inside = inside

---------------------------------------------------------------- rare ore

-- Put a core of rare ore in e (rock: a hidden gold core with veins running
-- in to it; ice: a crystal seen through it).
function C.giveCore(e, rare)
	local R = e.radius
	local ox, oy = (random() - 0.5) * R * 0.3, (random() - 0.5) * R * 0.3
	local core = {}
	local n = 7
	for j = 0, n - 1 do
		local ang = j / n * pi * 2 + (random() - 0.5) * 0.5
		local rr = R * T.rareCore * (0.75 + random() * 0.4)
		core[#core + 1] = ox + cos(ang) * rr
		core[#core + 1] = oy + sin(ang) * rr
	end
	if not love.math.isConvex(core) then core = { ox + R * 0.3, oy, ox, oy + R * 0.3, ox - R * 0.3, oy, ox, oy - R * 0.3 } end
	e.rare, e.core, e.veins = rare, core, nil
	if e.debris ~= 'ice' then
		e.veins = {}
		local a0 = random() * pi * 2
		for k = 1, 3 do
			local a = a0 + k * pi * 2 / 3 + (random() - 0.5) * 0.8
			local line = { ox, oy }
			local steps = 4
			for s = 1, steps do
				local d = R * (T.rareCore * 0.6 + (0.85 - T.rareCore * 0.6) * s / steps)
				a = a + (random() - 0.5) * 0.5
				line[#line + 1] = ox + cos(a) * d
				line[#line + 1] = oy + sin(a) * d
			end
			e.veins[k] = line
		end
	end
end

-- On spawn: roll for a gold core (rock) or a crystal (ice) in a big piece.
function C.seed(e)
	if not C.chips(e) then return end
	local rare = Ore.rare[e.debris or 'rock']
	local kind = e.debris or 'rock'
	if not rare or e.radius < T.rareMinRadius[kind] or random() >= T.rareChance[kind] then return end
	C.giveCore(e, rare)
end

-- Has a cut reached the core (so it shows, and pieces off it are rare)?
function C.exposed(e)
	return e.core and (e.debris == 'ice' or e.opened)
end

---------------------------------------------------------------- damage

-- Called from Game:damage before the health comes off.
function C.hit(game, e, cause, source, hx, hy)
	if not e.maxHp then e.maxHp = e.hp end
	e.lastCause, e.lastWeapon = cause, C.weapon(cause)
	if hx then e.hitX, e.hitY = hx, hy end
	if cause == 'drill' then e.drillHit = true end
end

local function toughness(e, r)
	local D = require('src.game').DEBRIS[e.debris or 'rock'] or { tough = 1 }
	return r * r * T.asteroidToughness * D.tough
end

-- A piece cut off e: shape p in e's frame, with its share of the core.
-- Small pieces are chips (the loot unit); bigger ones are rocks that chip on.
local function spawnPiece(game, e, p, core, drilled, kick)
	local a = area(p)
	if a < 4 then return end
	local cx, cy = centroid(p)
	local body = e.body
	local ang = body:getAngle()
	local ca, sa = cos(ang), sin(ang)
	local bx, by = body:getPosition()
	local wx, wy = bx + cx * ca - cy * sa, by + cx * sa + cy * ca
	local vx, vy = body:getLinearVelocity()
	local shape = cap(shift(p, cx, cy))
	local r = sqrt(a / pi)
	local share = core and area(core) / a or 0
	local big = r >= T.chunkRadius
	local ok, piece = pcall(game.spawnAsteroid, game, wx, wy, max(r, 4), e.debris, shape)
	if not ok then
		ok, piece = pcall(game.spawnAsteroid, game, wx, wy, max(r, 4), e.debris)
		if not ok then return end
	end
	piece.body:setAngle(ang)
	piece.shade = e.shade
	if big then
		piece.radius = reach(shape)
		piece.hp = toughness(piece, r)
		if core and share > 0.02 then piece.rare, piece.core, piece.opened = e.rare, cap(shift(core, cx, cy)), true end
	else
		local rare = core and share >= T.rareChipShare
		piece.chip = rare and e.rare or Ore.items[e.debris or 'rock']
		piece.rare = rare and e.rare or nil
		piece.hp = T.chipHp
		piece.expires = game.time + T.chipLife
	end
	piece.maxHp, piece.drilled = piece.hp, drilled
	-- thrown off along the cut's outward side
	local ux, uy = kick[1], kick[2]
	local wux, wuy = ux * ca - uy * sa, ux * sa + uy * ca
	local s = (big and 25 or 50) + random() * 60
	local sp = (random() - 0.5) * 0.6
	piece.body:setLinearVelocity(vx + (wux * cos(sp) - wuy * sin(sp)) * s, vy + (wux * sin(sp) + wuy * cos(sp)) * s)
	piece.body:setAngularVelocity((random() - 0.5) * (big and 1 or 4))
	return piece
end

-- Give e a new outline (in its own frame), recentred, and rebuild its body.
local function reshape(game, e, p, core)
	local cx, cy = centroid(p)
	p, core = cap(shift(p, cx, cy)), core and cap(shift(core, cx, cy))
	local body = e.body
	local x, y = body:getPosition()
	local a, spin = body:getAngle(), body:getAngularVelocity()
	local vx, vy = body:getLinearVelocity()
	local old = { e.verts, e.radius }
	e.verts, e.radius = p, reach(p)
	local ok = pcall(function()
		local nb = love.physics.newPolygonShape(p)   -- throws on a bad polygon
		nb:release()
	end)
	if not ok then e.verts, e.radius = old[1], old[2]; return false end
	body:destroy()
	e.core = core
	if e.veins then
		for k, line in ipairs(e.veins) do e.veins[k] = shift(line, cx, cy) end
	end
	game:debrisBody(e, x + cx * cos(a) - cy * sin(a), y + cx * sin(a) + cy * cos(a), a, spin)
	e.body:setLinearVelocity(vx, vy)
	return true
end

-- One cut into e from the side facing (lx, ly), its own frame.
-- Returns false when nothing's left worth keeping.
local function cut(game, e, lx, ly, depth, drilled)
	local d = sqrt(lx * lx + ly * ly)
	local ux, uy
	if d < 1e-3 then local a = random() * pi * 2; ux, uy = cos(a), sin(a) else ux, uy = lx / d, ly / d end
	-- a little off square, so the facets don't all line up
	local tw = (random() - 0.5) * 0.7
	ux, uy = ux * cos(tw) - uy * sin(tw), ux * sin(tw) + uy * cos(tw)
	local hmax = -math.huge
	for i = 1, #e.verts, 2 do hmax = max(hmax, e.verts[i] * ux + e.verts[i + 1] * uy) end
	local c = hmax - depth
	local keep, off = clip(e.verts, ux, uy, c, 1), clip(e.verts, ux, uy, c, -1)
	if not off then return true end
	local core, coreOff = e.core, nil
	if core then
		coreOff = clip(core, ux, uy, c, -1)
		core = clip(core, ux, uy, c, 1)
		if coreOff then e.opened = true end
	end
	spawnPiece(game, e, off, coreOff, drilled, { ux, uy })
	if not keep or sqrt(area(keep) / pi) < T.chunkRadius then
		-- too little left: it goes as a last piece
		if keep then spawnPiece(game, e, keep, core, drilled, { -ux, -uy }) end
		return false
	end
	if not reshape(game, e, keep, core) then return false end
	if e.core == nil and e.rare then e.rare = nil end
	return true
end

-- How much health one cut takes off this rock: bigger rocks take more cuts.
local function slice(e)
	local n = max(2, min(T.chipMax, floor(e.radius0 / T.chipPerRadius)))
	return e.maxHp / n
end

local function localHit(e)
	local x, y = e.body:getPosition()
	local hx, hy = (e.hitX or x) - x, (e.hitY or y) - y
	local a = -e.body:getAngle()
	return hx * cos(a) - hy * sin(a), hx * sin(a) + hy * cos(a)
end

-- From Game:reap, for a living rock: make the cuts its damage has earned.
function C.update(game, e)
	if not e.maxHp or e.hp >= e.maxHp or not C.chips(e) then return end
	e.radius0 = e.radius0 or e.radius
	e.chipped = e.chipped or 0
	local due = floor((e.maxHp - e.hp) / slice(e))
	if due <= e.chipped then return end
	if not e.lastWeapon then e.chipped = due; return end      -- worn down, not chipped
	local drilled = e.lastCause == 'drill'
	for _ = e.chipped + 1, due do
		local lx, ly = localHit(e)
		local depth = e.radius * (T.cutMin + random() * (T.cutMax - T.cutMin))
		if not cut(game, e, lx, ly, depth, drilled) then
			e.spent, e.dead = true, true          -- reap clears it away
			return
		end
	end
	e.chipped = due
end

-- From Game:breakAsteroid. Returns true when it handled the break.
function C.breakRock(game, e, x, y, vx, vy)
	if e.chip then
		-- only a drill recovers plain iron or ice; guns get just the rare ore
		local drilled = e.drilled or e.drillHit
		if (e.lastWeapon or e.lastCause == nil) and (drilled or e.rare) then
			game:spawnPickup(x, y, e.chip, drilled and T.drillOreMult or 1)
		end
		return true
	end
	if not C.chips(e) then return false end
	if e.spent then return true end
	-- the last of it: cut through the middle, if a weapon finished it
	if e.lastWeapon and e.verts then
		local lx, ly = localHit(e)
		local d = sqrt(lx * lx + ly * ly)
		if d < 1e-3 then lx, ly, d = 1, 0, 1 end
		local ux, uy = -ly / d, lx / d
		local drilled = e.lastCause == 'drill'
		for sign = 1, -1, -2 do
			local half = clip(e.verts, ux, uy, 0, sign)
			local core = e.core and clip(e.core, ux, uy, 0, sign)
			if core then e.opened = true end
			if half then
				local p = spawnPiece(game, e, half, core, drilled, { ux * -sign, uy * -sign })
				-- halves of a small rock are chips anyway; halves of a bigger
				-- one are chunks with health of their own
				if p and not p.chip then p.chipped = 0 end
			end
		end
	end
	return true
end

-- Chips nobody comes back for fade away.
function C.expired(game, e)
	return e.chip and e.expires and game.time > e.expires
end

return C
