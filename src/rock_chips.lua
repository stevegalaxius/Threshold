--[[
	Rock chips: how loose rock and ice come apart under fire.

	A rock or ice asteroid no longer splits into smaller rocks. Each time a
	weapon takes another slice of its health it sheds a chip, a tiny rock
	thrown off from where it was hit, and shrinks to match. Whatever is left
	when its health runs out crumbles into a last chip or two. A chip is the
	smallest unit of rock: shoot it once more and it pops into one unit of
	ore (two if a drill or mining laser broke it), ore that a pickup tractor
	can then collect.

	Rare ore: now and then a big rock carries a vein (drawn on its face) or
	a big ice chunk holds a crystal (drawn inside it, through the ice). Once
	enough of the rock is cut away to reach it, every chip that comes off is
	a rare chip, tinted in the ore's colour, and pops into the rare ore.

	Rocks that NPC mining sites own (e.miningId) keep the old drill-only
	rule: their crews and the site's books depend on it (src/mining.lua).
]]
local T = require('src.tuning')
local Ore = require('src.ore')
local C = {}
local random, sqrt, cos, sin, max, min, floor, pi = love.math.random, math.sqrt, math.cos, math.sin, math.max, math.min, math.floor, math.pi

-- Damage that isn't a weapon (bumps, heat, exhaust wash) wears a rock down
-- without chipping it, so a crowded belt doesn't fill up with chips.
local NOT_WEAPON = { ram = true, crash = true, crushed = true, heat = true, exhaust = true }

function C.weapon(cause) return cause ~= nil and not NOT_WEAPON[cause] end

-- Which kinds of debris chip, and what they give.
function C.chips(e)
	return e.kind == 'asteroid' and not e.giant and not e.miningId and not e.chip
		and Ore.items[e.debris or 'rock'] ~= nil
end

-- On spawn: roll for a vein (rock) or a crystal (ice) in a big enough piece.
function C.seed(e)
	if not C.chips(e) then return end
	local rare = Ore.rare[e.debris or 'rock']
	if not rare or e.radius < T.rareMinRadius or random() >= T.rareChance then return end
	e.rare = rare
	-- the vein's path across the face, and the crystal's shape, as offsets
	-- in units of the radius (so they shrink with the rock)
	local a = random() * pi * 2
	local pts = {}
	for k = 0, 5 do
		local t = k / 5 - 0.5
		pts[#pts + 1] = cos(a) * t * 1.1 + (random() - 0.5) * 0.18
		pts[#pts + 1] = sin(a) * t * 1.1 + (random() - 0.5) * 0.18
	end
	local fx, fy, flecks = cos(a + pi / 2), sin(a + pi / 2), {}
	for _ = 1, 4 do
		local t, s = (random() - 0.5) * 0.9, (random() - 0.5) * 0.45
		flecks[#flecks + 1] = { cos(a) * t + fx * s, sin(a) * t + fy * s }
	end
	local crystal = {}
	local n = 6
	for j = 0, n - 1 do
		local ang = j / n * pi * 2 + (random() - 0.5) * 0.5
		local rr = 0.22 + random() * 0.12
		crystal[#crystal + 1] = 0.12 + cos(ang) * rr
		crystal[#crystal + 1] = -0.06 + sin(ang) * rr
	end
	e.rareArt = { vein = pts, flecks = flecks, crystal = crystal }
	e.rareAt = T.rareExposeAt
end

-- Is the rare ore reached yet (so chips coming off now are rare)?
function C.exposed(e)
	return e.rare and e.hp <= e.maxHp * e.rareAt
end

-- Called from Game:damage before the health comes off.
function C.hit(game, e, cause, source, hx, hy)
	if not e.maxHp then e.maxHp = e.hp end
	e.lastCause, e.lastWeapon = cause, C.weapon(cause)
	if hx then e.hitX, e.hitY = hx, hy end
	if cause == 'drill' then e.drillHit = true end
end

-- How much health one chip takes off this rock: bigger rocks shed more chips.
local function slice(e)
	local n = max(2, min(T.chipMax, floor(e.radius0 / T.chipPerRadius)))
	return e.maxHp / n
end

-- A chip thrown off e from where it was last hit.
local function throw(game, e, x, y, vx, vy, rare, drilled)
	local hx, hy = e.hitX or x, e.hitY or y
	local a = math.atan2(hy - y, hx - x)
	if hx == x and hy == y then a = random() * pi * 2 end
	a = a + (random() - 0.5) * 1.2
	local d = e.radius + T.chipRadius * 1.2
	local item = rare and e.rare or Ore.items[e.debris or 'rock']
	local chip = game:spawnAsteroid(x + cos(a) * d, y + sin(a) * d, T.chipRadius * (0.85 + random() * 0.3), e.debris)
	chip.chip, chip.rare, chip.drilled = item, rare and e.rare or nil, drilled
	chip.hp, chip.maxHp = T.chipHp, T.chipHp
	chip.expires = game.time + T.chipLife
	local s = 50 + random() * 70
	chip.body:setLinearVelocity(vx + cos(a) * s, vy + sin(a) * s)
	return chip
end

-- Shrink a rock to radius r: scale its outline and rebuild its fixture.
local function shrink(game, e, r)
	local k = r / e.radius
	if k >= 0.999 then return end
	local verts = {}
	for i, v in ipairs(e.verts) do verts[i] = v * k end
	local body = e.body
	local x, y = body:getPosition()
	local a, spin = body:getAngle(), body:getAngularVelocity()
	local vx, vy = body:getLinearVelocity()
	body:destroy()
	e.verts, e.radius = verts, r
	game:debrisBody(e, x, y, a, spin)
	e.body:setLinearVelocity(vx, vy)
end

-- From Game:reap, for a living rock: shed the chips its damage has earned.
function C.update(game, e)
	if not e.maxHp or e.hp >= e.maxHp or not C.chips(e) then return end
	e.radius0 = e.radius0 or e.radius
	e.chipped = e.chipped or 0
	local due = floor((e.maxHp - e.hp) / slice(e))
	if due <= e.chipped then return end
	if not e.lastWeapon then e.chipped = due; return end      -- worn down, not chipped
	local x, y = e.body:getPosition()
	local vx, vy = e.body:getLinearVelocity()
	for _ = e.chipped + 1, due do
		throw(game, e, x, y, vx, vy, C.exposed(e), e.lastCause == 'drill')
	end
	e.chipped = due
	-- what's left, by area, but never below a small rock
	shrink(game, e, max(T.chipRadius * 1.6, e.radius0 * sqrt(max(e.hp, 0) / e.maxHp)))
end

-- From Game:breakAsteroid. Returns true when it handled the break.
function C.breakRock(game, e, x, y, vx, vy)
	if e.chip then
		if e.lastWeapon or e.lastCause == nil then
			local n = (e.drilled or e.drillHit) and T.drillOreMult or 1
			game:spawnPickup(x, y, e.chip, n)
		end
		return true
	end
	if not C.chips(e) then return false end
	-- crumble: a last chip or two, if a weapon finished it
	if e.lastWeapon then
		local n = e.radius >= T.chipRadius * 3 and 2 or 1
		for _ = 1, n do throw(game, e, x, y, vx, vy, C.exposed(e) or e.rare ~= nil, e.lastCause == 'drill') end
	end
	return true
end

-- Chips nobody comes back for fade away.
function C.expired(game, e)
	return e.chip and e.expires and game.time > e.expires
end

return C
