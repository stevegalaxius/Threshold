--[[
	Weapons and projectiles.

	  gun        fast fire, short range, no splash. Uses ammo.
	  artillery  slow fire, long range, big damage and splash. Shells burst
	             on contact, when they pass near an enemy (proximity fuse),
	             or at the end of their range. Uses ammo.
	  laser      pulse laser: a brief, instant-hit flash about once a second.
	             No ammo; each pulse takes a chunk of power.
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

-- Where each weapon points, as an angle off the nose (slot.aim). How it
-- follows the aim point depends on how the hull mounts its weapons:
--   fixed   bolted to the nose: always fires straight ahead (small hulls)
--   gimbal  swings toward the aim point, but only within the weapon's
--           gimbal angle of the nose (medium hulls)
--   turret  rotates all the way around at the hull's turretTurn speed, so
--           it can fire in any direction while the hull points elsewhere
--           (heavy hulls)
local function aimSlot(e, slot, dt)
	if slot.mount == "fixed" then slot.aim = 0; return end
	local wx, wy = Ship.hardpoint(e, slot.slot)
	local want = Ship.wrapAngle(atan2(e.intent.aimY - wy, e.intent.aimX - wx) - e.body:getAngle())
	if slot.mount == "turret" then
		local step = rad(e.hull.turretTurn or 180) * dt
		slot.aim = Ship.wrapAngle(slot.aim + max(-step, min(step, Ship.wrapAngle(want - slot.aim))))
	else
		local g = rad(slot.w.gimbal or 8)
		slot.aim = max(-g, min(g, want))
	end
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
	local angle = e.body:getAngle() + slot.aim
	local dx, dy = cos(angle), sin(angle)

	if w.kind == "laser" then
		-- One pulse: hits instantly along the beam, then the beam lingers
		-- on screen for w.pulse seconds.
		if slot.cooldown > 0 then return end
		if e.power < w.powerPerShot then slot.starved = true; return end
		slot.starved = false
		e.power = e.power - w.powerPerShot
		slot.cooldown = 1 / w.fireRate
		local ex, ey = wx + dx * w.range, wy + dy * w.range
		local hit = game:raycast(wx, wy, ex, ey, e.team)
		if hit then
			ex, ey = hit.x, hit.y
			game:damage(hit.entity, w.damage * mult.primaryDamage, e, "laser")
			local k = (w.knockback or 0) * T.knockbackScale
			hit.entity.body:applyLinearImpulse(dx * k, dy * k, hit.x, hit.y)
			game:spark(hit.x, hit.y, 8, { 0.7, 1, 1 })
		end
		slot.beam = { wx, wy, ex, ey, game.time, w.pulse or 0.12 }
		game:muzzle(wx, wy, angle, 1.0)
		events.emit("fire", e, slot)
		return
	end

	-- Everything else fires one round per shot.
	if slot.cooldown > 0 then return end
	local rate = w.fireRate * (slot.group == "primary" and mult.primaryFireRate or 1)
	-- Out of the selected ammo: fall back to another size this weapon can fire.
	if (e.cargo[slot.ammo] or 0) <= 0 and not (T.dev.infiniteAmmo and e.isPlayer) then
		for _, id in ipairs(slot.ammoOptions) do
			if (e.cargo[id] or 0) > 0 then slot.ammo = id; break end
		end
	end
	if not takeAmmo(e, slot.ammo) then
		slot.empty = true
		slot.cooldown = 0.3
		if e.isPlayer then game:toast("OUT OF " .. data.items[slot.ammo].name:upper(), 1.2) end
		return
	end
	slot.empty = false
	slot.cooldown = 1 / rate

	-- The round sets the damage and flight; the weapon only how it's fired.
	local ws = data.items[slot.ammo].shot
	local spread = rad(w.spread or 0)
	angle = angle + (random() * 2 - 1) * spread
	dx, dy = cos(angle), sin(angle)
	local svx, svy = e.body:getLinearVelocity()

	local p = {
		kind = w.kind, team = e.team, owner = e,
		x = wx, y = wy, px = wx, py = wy,
		vx = svx + dx * ws.speed, vy = svy + dy * ws.speed,
		damage = ws.damage, splash = ws.splash, knockback = (ws.knockback or 0),
		size = data.items[slot.ammo].size,
	}

	if w.kind == "gun" then
		p.life = ws.range / ws.speed
		p.damage = ws.damage * mult.primaryDamage
	elseif w.kind == "artillery" then
		p.life = ws.range / ws.speed
		p.damage = ws.damage * mult.primaryDamage
		p.burst = true
		p.fuse = (ws.splash or 40) * 0.5
	elseif w.kind == "missile" then
		p.vx, p.vy = svx + dx * ws.speed * 0.4, svy + dy * ws.speed * 0.4
		p.maxSpeed, p.accel, p.turnRate = ws.speed, ws.accel, ws.turnRate
		p.life = ws.range / ws.speed * 1.3
		p.damage = ws.damage * mult.missileDamage
		p.target = nearestTargetTo(game, e.intent.aimX, e.intent.aimY, e.team, 600)
			or nearestTargetTo(game, wx + dx * 900, wy + dy * 900, e.team, 1000)
		p.burst = true
		p.fuse = (ws.splash or 40) * 0.5
	end

	table.insert(game.projectiles, p)

	local r = (w.recoil or 0) * T.recoilScale
	if r > 0 then e.body:applyLinearImpulse(-dx * r, -dy * r, wx, wy) end
	if w.kind == "artillery" then game:muzzle(wx, wy, angle, 1.6) else game:muzzle(wx, wy, angle, 0.6) end
	if e.isPlayer and w.kind == "artillery" then game:shake(0.18) end
	events.emit("fire", e, slot)
end

-- How far a weapon reaches with what it's loaded with.
function Weapons.range(slot)
	if slot.ammo then return data.items[slot.ammo].shot.range end
	return slot.w.range or 0
end

-- Switch every weapon in a group to the next ammo size it can fire.
-- Returns the newly selected ammo id (of the first launcher that changed).
function Weapons.cycleAmmo(e, group)
	local picked
	for _, slot in ipairs(e.weapons) do
		if slot.group == group and #slot.ammoOptions > 1 then
			local i = 1
			for j, id in ipairs(slot.ammoOptions) do if id == slot.ammo then i = j end end
			slot.ammo = slot.ammoOptions[i % #slot.ammoOptions + 1]
			picked = picked or slot.ammo
		end
	end
	return picked
end

function Weapons.update(game, e, dt)
	local it = e.intent
	for _, slot in ipairs(e.weapons) do
		slot.cooldown = max(0, slot.cooldown - dt)
		aimSlot(e, slot, dt)
		local wants = (slot.group == "primary" and it.firePrimary) or (slot.group == "secondary" and it.fireSecondary)
		-- AI only fires a weapon when the target is roughly in its range.
		if wants and it.targetDist and it.targetDist > Weapons.range(slot) * 1.05 then wants = false end
		if wants then fire(game, e, slot, dt) end
	end
	if e.massDirty then Ship.updateMass(e) end
end

-- Projectiles ---------------------------------------------------------------

-- Proximity fuse: the first enemy ship within fuse range of the shell.
local function fuseTarget(game, p)
	for _, o in ipairs(game.entities) do
		if o.kind == "ship" and not o.dead and o.team ~= p.team then
			if Ship.distanceTo(o, p.x, p.y) < p.fuse then return o end
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
