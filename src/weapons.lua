--[[
	Weapons and projectiles.

	  gun        fast fire, short range, no splash. Uses ammo.
	  artillery  slow fire, long range, big damage and splash. Shells burst
	             on contact, when they pass near an enemy (proximity fuse),
	             or at the end of their range. Uses ammo.
	  laser      continuous beam, no ammo, drains power while firing.
	  missile    secondary weapon, guided, splash. Expensive ammo.

	Every shot of a gun, artillery piece or missile launcher takes one round
	out of the hold, and the ship gets lighter as it does.

	Projectiles aren't physics bodies: each step they ray-cast from where
	they were to where they are, which is cheap and never tunnels through
	thin targets.
]]

local data = require("src.data")
local Ship = require("src.ship")
local T = require("src.tuning")
local events = require("src.events")

local Weapons = {}

local sqrt, cos, sin, atan2, rad, max, min, random = math.sqrt, math.cos, math.sin, math.atan2, math.rad, math.max, math.min, love.math.random

local function takeAmmo(e, id)
	if T.dev.infiniteAmmo and e.isPlayer then return true end
	local n = e.cargo[id] or 0
	if n <= 0 then return false end
	e.cargo[id] = n - 1
	e.massDirty = true
	return true
end

-- Fire direction: toward the aim point if it's within the weapon's gimbal
-- angle of the nose, otherwise as close to it as the gimbal allows.
local function fireAngle(e, wx, wy, w)
	local nose = e.body:getAngle()
	local want = atan2(e.intent.aimY - wy, e.intent.aimX - wx)
	local g = rad(w.gimbal or 8)
	local off = Ship.wrapAngle(want - nose)
	off = max(-g, min(g, off))
	return nose + off
end

local function nearestTargetTo(game, x, y, team, maxDist)
	local best, bestD = nil, maxDist * maxDist
	for _, o in ipairs(game.entities) do
		if o.kind == "ship" and not o.dead and o.team ~= team then
			local ox, oy = o.body:getPosition()
			local d = (ox - x) ^ 2 + (oy - y) ^ 2
			if d < bestD then best, bestD = o, d end
		end
	end
	return best
end

local function fire(game, e, slot, dt)
	local w = slot.w
	local mult = e.stats.mult
	local wx, wy = Ship.hardpoint(e, slot.slot)
	local angle = fireAngle(e, wx, wy, w)
	local dx, dy = cos(angle), sin(angle)

	if w.kind == "laser" then
		local cost = w.powerPerSec * dt
		if e.power < cost then slot.beam = nil; slot.starved = true; return end
		slot.starved = false
		e.power = e.power - cost
		local ex, ey = wx + dx * w.range, wy + dy * w.range
		local hit = game:raycast(wx, wy, ex, ey, e.team)
		if hit then
			ex, ey = hit.x, hit.y
			game:damage(hit.entity, w.damage * mult.primaryDamage * dt, e, "laser")
			local k = (w.knockback or 0) * T.knockbackScale * dt
			hit.entity.body:applyLinearImpulse(dx * k, dy * k, hit.x, hit.y)
			if random() < dt * 30 then game:spark(hit.x, hit.y, 1, { 0.6, 1, 1 }) end
		end
		slot.beam = { wx, wy, ex, ey, game.time }
		return
	end

	-- Everything else fires one round per shot.
	if slot.cooldown > 0 then return end
	local rate = w.fireRate * (slot.group == "primary" and mult.primaryFireRate or 1)
	if not takeAmmo(e, slot.ammo) then
		slot.empty = true
		slot.cooldown = 0.3
		if e.isPlayer then game:toast("OUT OF " .. data.items[slot.ammo].name:upper(), 1.2) end
		return
	end
	slot.empty = false
	slot.cooldown = 1 / rate

	local spread = rad(w.spread or 0)
	angle = angle + (random() * 2 - 1) * spread
	dx, dy = cos(angle), sin(angle)
	local svx, svy = e.body:getLinearVelocity()

	local p = {
		kind = w.kind, team = e.team, owner = e,
		x = wx, y = wy, px = wx, py = wy,
		vx = svx + dx * w.speed, vy = svy + dy * w.speed,
		damage = w.damage, splash = w.splash, knockback = (w.knockback or 0),
		size = slot.module.size,
	}

	if w.kind == "gun" then
		p.life = w.range / w.speed
		p.damage = w.damage * mult.primaryDamage
	elseif w.kind == "artillery" then
		p.life = w.range / w.speed
		p.damage = w.damage * mult.primaryDamage
		p.burst = true
		p.fuse = (w.splash or 40) * 0.5
	elseif w.kind == "missile" then
		p.vx, p.vy = svx + dx * w.speed * 0.4, svy + dy * w.speed * 0.4
		p.maxSpeed, p.accel, p.turnRate = w.speed, w.accel, w.turnRate
		p.life = w.range / w.speed * 1.3
		p.damage = w.damage * mult.missileDamage
		p.target = nearestTargetTo(game, e.intent.aimX, e.intent.aimY, e.team, 600)
			or nearestTargetTo(game, wx + dx * 900, wy + dy * 900, e.team, 1000)
		p.burst = true
		p.fuse = (w.splash or 40) * 0.5
	end

	table.insert(game.projectiles, p)

	local r = (w.recoil or 0) * T.recoilScale
	if r > 0 then e.body:applyLinearImpulse(-dx * r, -dy * r, wx, wy) end
	if w.kind == "artillery" then game:muzzle(wx, wy, angle, 1.6) else game:muzzle(wx, wy, angle, 0.6) end
	if e.isPlayer and w.kind == "artillery" then game:shake(0.18) end
	events.emit("fire", e, slot)
end

function Weapons.update(game, e, dt)
	local it = e.intent
	for _, slot in ipairs(e.weapons) do
		slot.cooldown = max(0, slot.cooldown - dt)
		local wants = (slot.group == "primary" and it.firePrimary) or (slot.group == "secondary" and it.fireSecondary)
		-- AI only fires a weapon when the target is roughly in its range.
		if wants and it.targetDist and it.targetDist > (slot.w.range or 0) * 1.05 then wants = false end
		if wants then
			fire(game, e, slot, dt)
		elseif slot.w.kind == "laser" then
			slot.beam = nil
		end
	end
	if e.massDirty then Ship.updateMass(e) end
end

-- Projectiles ---------------------------------------------------------------

-- Proximity fuse: the first enemy ship within fuse range of the shell.
local function fuseTarget(game, p)
	for _, o in ipairs(game.entities) do
		if o.kind == "ship" and not o.dead and o.team ~= p.team then
			local ox, oy = o.body:getPosition()
			local r = o.hull.radius + p.fuse
			if (ox - p.x) ^ 2 + (oy - p.y) ^ 2 < r * r then return o end
		end
	end
end

local function steerMissile(p, dt)
	local t = p.target
	if t and t.dead then p.target, t = nil, nil end
	local speed = sqrt(p.vx * p.vx + p.vy * p.vy)
	local heading = atan2(p.vy, p.vx)
	if t then
		local tx, ty = t.body:getPosition()
		local want = atan2(ty - p.y, tx - p.x)
		local diff = Ship.wrapAngle(want - heading)
		local turn = p.turnRate * dt
		heading = heading + max(-turn, min(turn, diff))
	end
	speed = min(p.maxSpeed, speed + p.accel * dt)
	p.vx, p.vy = cos(heading) * speed, sin(heading) * speed
	p.trailTimer = (p.trailTimer or 0) - dt
end

function Weapons.updateProjectiles(game, dt)
	local list = game.projectiles
	local i = 1
	while i <= #list do
		local p = list[i]
		if p.kind == "missile" then steerMissile(p, dt) end
		p.px, p.py = p.x, p.y
		local nx, ny = p.x + p.vx * dt, p.y + p.vy * dt
		local hit = game:raycast(p.x, p.y, nx, ny, p.team)
		local done = false

		if hit then
			p.x, p.y = hit.x, hit.y
			local sp = sqrt(p.vx * p.vx + p.vy * p.vy)
			local k = p.knockback * T.knockbackScale
			if p.burst then
				game:explode(p.x, p.y, p.splash, p.damage, k, p.owner, hit.entity, p.kind)
			else
				game:damage(hit.entity, p.damage, p.owner, p.kind)
				hit.entity.body:applyLinearImpulse(p.vx / sp * k, p.vy / sp * k, hit.x, hit.y)
				game:spark(hit.x, hit.y, 4, { 1, 0.85, 0.5 })
			end
			done = true
		else
			p.x, p.y = nx, ny
			p.life = p.life - dt
			if p.life <= 0 then
				if p.burst then game:explode(p.x, p.y, p.splash, p.damage, p.knockback * T.knockbackScale, p.owner, nil, p.kind) end
				done = true
			elseif p.fuse then
				local near = fuseTarget(game, p)
				if near then
					game:explode(p.x, p.y, p.splash, p.damage, p.knockback * T.knockbackScale, p.owner, near, p.kind)
					done = true
				end
			end
		end

		if done then
			list[i] = list[#list]
			list[#list] = nil
		else
			i = i + 1
		end
	end
end

return Weapons
