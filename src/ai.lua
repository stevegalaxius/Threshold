--[[
	Enemy AI. It doesn't move ships directly: it fills in the same intent
	table the player's controls fill (thrust, strafe, aim point, fire), and
	the ship code turns that into forces like it does for you.

	The AI works out which way it wants to go in the world, then converts
	that into nose-relative thrust. Ships with strong side thrusters can
	strafe while keeping their guns on you; ships without them have to turn
	toward where they're going (turn and burn) and can't shoot while they do.

	Styles (set per enemy in data/enemies.lua):
	  rush   close in; with ram = true it keeps pushing into you
	  orbit  circle the target at its preferred range
	  kite   hold long range and back off when you get close
]]

local Ship = require("src.ship")
local T = require("src.tuning")
local data = require("src.data")

local AI = {}

local sqrt, cos, sin, max, min, random = math.sqrt, math.cos, math.sin, math.max, math.min, love.math.random

local function norm(x, y)
	local l = sqrt(x * x + y * y)
	if l < 1e-6 then return 0, 0, 0 end
	return x / l, y / l, l
end

-- Look ahead for collisions: for every ship and asteroid nearby (except the
-- target, which the braking below handles), find where it will be at the
-- moment of closest approach over the next couple of seconds. If that's
-- too close, push away from that point, harder the sooner and closer it
-- is. Returns the push and how urgent the worst one is (0..1).
local HORIZON = 1.6
local function avoidCollisions(game, e, target, x, y, vx, vy)
	local px, py, worst = 0, 0, 0
	local speed = sqrt(vx * vx + vy * vy)
	for _, o in ipairs(game.entities) do
		if o ~= e and o ~= target and not o.dead then
			local ox, oy = o.body:getPosition()
			ox, oy = ox + (o.cx or 0), oy + (o.cy or 0)   -- structures sit at 0,0
			local orad = (o.kind == "ship") and o.halfLength or o.radius
			local clear = e.halfLength + orad + 50
			local rx, ry = ox - x, oy - y
			local reach = clear + (speed + 400) * HORIZON
			if rx * rx + ry * ry < reach * reach then
				local ovx, ovy = o.body:getLinearVelocity()
				local dvx, dvy = ovx - vx, ovy - vy
				local dv2 = dvx * dvx + dvy * dvy
				local t = (dv2 > 1e-6) and max(0, -(rx * dvx + ry * dvy) / dv2) or 0
				if t < HORIZON then
					local cx, cy = rx + dvx * t, ry + dvy * t
					local miss = sqrt(cx * cx + cy * cy)
					if miss < clear then
						local urgency = (1 - miss / clear) * 0.5 + (1 - t / HORIZON) * 0.5
						local nx, ny, l = norm(-cx, -cy)
						if l == 0 then nx, ny = norm(-ry, rx) end
						px, py = px + nx * urgency * 3, py + ny * urgency * 3
						worst = max(worst, urgency)
					end
				end
			end
		end
	end
	return px, py, worst
end

-- Who an AI ship fights: enemies go for the player; drones go for the
-- nearest ship on another team.
local function pickTarget(game, e, x, y)
	if not e.drone then return game.player end
	local best, bestD = nil, 3000 * 3000
	for _, o in ipairs(game.entities) do
		if o.kind == "ship" and not o.dead and o.team ~= e.team then
			local ox, oy = o.body:getPosition()
			local d = (ox - x) ^ 2 + (oy - y) ^ 2
			if d < bestD then best, bestD = o, d end
		end
	end
	return best
end

function AI.think(game, e, dt)
	local it = e.intent
	local ai = e.def.ai
	it.firePrimary, it.fireSecondary, it.fireAux, it.boost = false, false, false, false
	it.thrust, it.strafe = 0, 0

	local x, y = e.body:getPosition()
	local target = pickTarget(game, e, x, y)
	if not target or target.dead then
		it.targetDist = nil
		local a = e.body:getAngle()
		it.aimX, it.aimY = x + cos(a) * 100, y + sin(a) * 100
		-- A drone with nothing to fight stays near whoever launched it.
		local o = e.owner
		if o and not o.dead then
			local ox, oy = o.body:getPosition()
			local mx, my, d = norm(ox - x, oy - y)
			if d > 350 then
				it.aimX, it.aimY = ox, oy
				it.thrust, it.strafe = Ship.toLocal(e, mx * 0.8, my * 0.8)
			end
		end
		return
	end

	local vx, vy = e.body:getLinearVelocity()

	-- Bail out: an enemy down to 10% armor gives up and runs for the edge
	-- of the arena, afterburner lit, and leaves (Game:reap lets it go once
	-- it's well outside). It doesn't fire while running.
	if not e.drone and (e.fleeing or e.armor <= e.stats.armor * 0.1) then
		if not e.fleeing then
			e.fleeing = true
			game:toast(((e.def.name or "ENEMY") .. " is running"):upper(), 1.5)
		end
		local tx, ty = target.body:getPosition()
		local ox, oy, od = norm(x, y)
		if od == 0 then ox, oy = 1, 0 end
		local ax, ay = norm(x - tx, y - ty)
		local mx, my = ox * 0.7 + ax * 0.5, oy * 0.7 + ay * 0.5
		local avx, avy = avoidCollisions(game, e, nil, x, y, vx, vy)
		local nmx, nmy = norm(mx + avx, my + avy)
		it.aimX, it.aimY = x + nmx * 400, y + nmy * 400
		it.thrust, it.strafe = Ship.toLocal(e, nmx, nmy)
		it.boost = true
		it.targetDist = nil
		return
	end

	local tx, ty = target.body:getPosition()
	local tvx, tvy = target.body:getLinearVelocity()
	local ux, uy, dist = norm(tx - x, ty - y)

	-- Lead the target using the first weapon's shot speed. Shots inherit the
	-- shooter's velocity, so lead with relative velocity. Low accuracy
	-- under-leads and wobbles more.
	local slot = e.weapons[1]
	local shotSpeed = (slot and slot.ammo and data.items[slot.ammo].shot.speed) or 3000
	local lead = dist / shotSpeed * ai.accuracy
	e.jitterTimer = (e.jitterTimer or 0) - dt
	if e.jitterTimer <= 0 then
		e.jitterTimer = 0.4 + random() * 0.6
		local spread = (1 - ai.accuracy) * 120
		e.jitterX, e.jitterY = (random() * 2 - 1) * spread, (random() * 2 - 1) * spread
	end
	local aimX = tx + (tvx - vx) * lead + (e.jitterX or 0)
	local aimY = ty + (tvy - vy) * lead + (e.jitterY or 0)
	it.targetDist = dist

	-- Self-preservation: a badly damaged ship backs off to well past its
	-- preferred range and fights from there.
	local hurt = e.armor < e.stats.armor * 0.35
	local style = hurt and "kite" or ai.style

	-- Where it wants to go, in world space.
	local r = hurt and ai.range * 1.8 or ai.range
	local mx, my = 0, 0
	e.orbitDir = e.orbitDir or ((random() < 0.5) and -1 or 1)
	if style == "rush" then
		if ai.ram or dist > r then
			mx, my = ux, uy
		else
			mx, my = -uy * e.orbitDir * 0.8, ux * e.orbitDir * 0.8
			if dist < r * 0.6 then mx, my = mx - ux * 0.8, my - uy * 0.8 end
		end
	elseif style == "orbit" then
		local err = max(-1, min(1, (dist - r) / 200))
		mx, my = -uy * e.orbitDir * 0.85 + ux * err, ux * e.orbitDir * 0.85 + uy * err
	elseif style == "kite" then
		local err = max(-1, min(1, (dist - r) / 300))
		mx, my = -uy * e.orbitDir * 0.35 + ux * err, ux * e.orbitDir * 0.35 + uy * err
	end

	-- Don't fly into the target: if it's closing faster than it can stop
	-- before reaching its preferred range, brake by pushing away. Only
	-- ships with ram = true are allowed to plough on in.
	if not ai.ram then
		local closing = (vx - tvx) * ux + (vy - tvy) * uy
		if closing > 0 then
			local s = e.stats
			local brakeForce = max(s.retroThrust, s.sideThrust, s.thrust * 0.5) * T.FORCE_PER_KN * T.thrustScale
			local stopDist = closing * closing / (2 * max(brakeForce / e.body:getMass(), 1))
			if stopDist > dist - r * 0.8 then mx, my = mx - ux * 1.5, my - uy * 1.5 end
		end
	end

	-- Jink: after being hit, or while the target is pointing right at it,
	-- throw in sideways dodges that flip direction every half second or so.
	local ta = target.body:getAngle()
	local aimedAt = (cos(ta) * -ux + sin(ta) * -uy) > 0.97 and dist < 1500
	local recentlyHit = e.lastHitTime and game.time - e.lastHitTime < 1.5
	e.jinkTimer = (e.jinkTimer or 0) - dt
	if e.jinkTimer <= 0 then
		e.jinkTimer = 0.35 + random() * 0.5
		e.jinkDir = (random() < 0.5) and -1 or 1
	end
	if aimedAt or recentlyHit then
		local j = hurt and 1.0 or 0.6
		mx, my = mx - uy * e.jinkDir * j, my + ux * e.jinkDir * j
	end

	-- Steer clear of asteroids and other ships it's about to hit.
	local avx, avy, danger = avoidCollisions(game, e, target, x, y, vx, vy)
	mx, my = mx + avx, my + avy

	-- Keep some distance from other AI ships so they don't clump.
	for _, o in ipairs(game.entities) do
		if o ~= e and o.kind == "ship" and o.team == e.team and not o.dead then
			local ox, oy = o.body:getPosition()
			local sx, sy, d = norm(x - ox, y - oy)
			local keep = (e.halfLength + o.halfLength) * 1.6
			if d > 0 and d < keep then
				local push = (keep - d) / keep
				mx, my = mx + sx * push * 1.5, my + sy * push * 1.5
			end
		end
	end

	if random() < dt * 0.15 then e.orbitDir = -e.orbitDir end

	local nmx, nmy, ml = norm(mx, my)
	ml = min(1, ml)

	-- Turn and burn: a ship with weak side thrusters that needs to get
	-- somewhere other than "toward the target" points its nose that way.
	local weak = e.stats.sideThrust < e.stats.thrust * 0.35
	local relocating = dist > r * 1.5 or dist < r * 0.55
	local along = nmx * ux + nmy * uy
	local burning = weak and ml > 0.2 and (relocating or danger > 0.4) and along < 0.6
	if burning then
		it.aimX, it.aimY = x + nmx * 300, y + nmy * 300
	else
		it.aimX, it.aimY = aimX, aimY
	end

	-- Avoiding a crash or running hurt: full throttle.
	local th = ((danger > 0.3 or hurt) and 1 or ai.throttle) * ml
	it.thrust, it.strafe = Ship.toLocal(e, nmx * th, nmy * th)
	if burning and style == "kite" and dist < r * 0.5 then it.boost = true end

	-- Fire in bursts, only when not turning away and roughly facing the
	-- target (turrets don't need to face it).
	local burstOn, burstOff = ai.burstOn or 1.0, ai.burstOff or 1.4
	e.burstClock = ((e.burstClock or random() * (burstOn + burstOff)) + dt) % (burstOn + burstOff)
	local a = e.body:getAngle()
	local fx, fy = cos(a), sin(a)
	local ax, ay = norm(aimX - x, aimY - y)
	local facing = e.hull.mount == "turret" or (fx * ax + fy * ay) > 0.95
	it.firePrimary = not burning and e.burstClock < burstOn and facing
	it.fireSecondary = it.firePrimary
end

return AI
