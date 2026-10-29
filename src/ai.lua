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

local AI = {}

local sqrt, cos, sin, max, min, random = math.sqrt, math.cos, math.sin, math.max, math.min, love.math.random

local function norm(x, y)
	local l = sqrt(x * x + y * y)
	if l < 1e-6 then return 0, 0, 0 end
	return x / l, y / l, l
end

function AI.think(game, e, dt)
	local it = e.intent
	local ai = e.def.ai
	it.firePrimary, it.fireSecondary, it.boost = false, false, false
	it.thrust, it.strafe = 0, 0

	local x, y = e.body:getPosition()
	local target = game.player
	if not target or target.dead then
		it.targetDist = nil
		local a = e.body:getAngle()
		it.aimX, it.aimY = x + cos(a) * 100, y + sin(a) * 100
		return
	end

	local vx, vy = e.body:getLinearVelocity()
	local tx, ty = target.body:getPosition()
	local tvx, tvy = target.body:getLinearVelocity()
	local ux, uy, dist = norm(tx - x, ty - y)

	-- Lead the target using the first weapon's shot speed. Shots inherit the
	-- shooter's velocity, so lead with relative velocity. Low accuracy
	-- under-leads and wobbles more.
	local w = e.weapons[1] and e.weapons[1].w
	local shotSpeed = (w and w.speed) or 3000
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

	-- Where it wants to go, in world space.
	local r = ai.range
	local mx, my = 0, 0
	e.orbitDir = e.orbitDir or ((random() < 0.5) and -1 or 1)
	if ai.style == "rush" then
		if ai.ram or dist > r then
			mx, my = ux, uy
		else
			mx, my = -uy * e.orbitDir * 0.8, ux * e.orbitDir * 0.8
			if dist < r * 0.6 then mx, my = mx - ux * 0.8, my - uy * 0.8 end
		end
	elseif ai.style == "orbit" then
		local err = max(-1, min(1, (dist - r) / 200))
		mx, my = -uy * e.orbitDir * 0.85 + ux * err, ux * e.orbitDir * 0.85 + uy * err
	elseif ai.style == "kite" then
		local err = max(-1, min(1, (dist - r) / 300))
		mx, my = -uy * e.orbitDir * 0.35 + ux * err, ux * e.orbitDir * 0.35 + uy * err
	end

	-- Keep some distance from other AI ships so they don't clump.
	for _, o in ipairs(game.entities) do
		if o ~= e and o.kind == "ship" and o.team == e.team and not o.dead then
			local ox, oy = o.body:getPosition()
			local sx, sy, d = norm(x - ox, y - oy)
			local keep = (e.hull.radius + o.hull.radius) * 2.5
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
	local burning = weak and ml > 0.2 and relocating and along < 0.6
	if burning then
		it.aimX, it.aimY = x + nmx * 300, y + nmy * 300
	else
		it.aimX, it.aimY = aimX, aimY
	end

	local th = ai.throttle * ml
	it.thrust, it.strafe = Ship.toLocal(e, nmx * th, nmy * th)
	if burning and ai.style == "kite" and dist < r * 0.5 then it.boost = true end

	-- Fire in bursts, only when not turning away and roughly facing the
	-- target (turrets don't need to face it).
	local burstOn, burstOff = ai.burstOn or 1.0, ai.burstOff or 1.4
	e.burstClock = ((e.burstClock or random() * (burstOn + burstOff)) + dt) % (burstOn + burstOff)
	local a = e.body:getAngle()
	local fx, fy = cos(a), sin(a)
	local ax, ay = norm(aimX - x, aimY - y)
	local facing = e.hull.mount == "turret" or (fx * ax + fy * ay) > 0.95
	it.firePrimary = not burning and e.burstClock < burstOn and facing
end

return AI
