--[[
	Weapons and projectiles.

	  cannon     fires whatever ammo it chambers:
	               rounds    fast, short range, no splash.
	               shells    long range, big damage and splash. Shells burst
	                         on contact, when they pass near an enemy (proximity
	                         fuse), or at the end of their range.
	               shot      a spray of pellets (shot.pellets, fanned over
	                         shot.pelletSpread degrees), each hitting like a round.
	  laser      no ammo. A pulse laser fires a brief, instant-hit flash per
	             shot (damage and powerPerShot per pulse); a beam laser
	             (beam = true) burns while held, damage and powerPerSecond
	             per second. Either can fire several lines at once (beams, fanned
	             over beamSpread degrees) in their own color.
	  missile    bay rack: missiles (guided, splash) or torpedoes (very fast,
	             steer slowly, enormous damage and splash).

	A weapon loads any ammo family it chambers (data.chambers). The weapon sets how it fires (fire rate,
	spread, recoil); the ammo sets the hit and how the shot flies, by its
	family.
	  drone      bay: launches an armed drone that fights for a while.

	Every shot of a cannon or missile rack takes one round
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

-- How much of a drone bay's control budget a drone of each size uses.
local DRONE_CONTROL = { S = 1, M = 2, L = 4 }

local sqrt, cos, sin, atan2, rad, max, min, random = math.sqrt, math.cos, math.sin, math.atan2, math.rad, math.max, math.min, love.math.random

-- How much of a missile rack's tubes one round of each size fills.
local TUBE_UNITS = { S = 1, M = 2, L = 4 }
Weapons.TUBE_UNITS = TUBE_UNITS

-- How many rounds of its loaded ammo a rack's tubes hold (weapon.capacity
-- in S-size units: an M round takes 2, an L round 4).
function Weapons.tubes(slot)
	local item = slot.ammo and data.items[slot.ammo]
	if not (slot.w.capacity and item) then return nil end
	return math.floor(slot.w.capacity / TUBE_UNITS[item.size])
end

-- Missile racks fire only what's armed in their tubes, and re-arm one round
-- at a time from the hold, each taking its ammo's shot.armTime seconds.
-- Armed rounds stay counted in the hold until they're fired. A fresh rack
-- starts armed; switching ammo empties the tubes.
function Weapons.arm(e, slot, dt)
	local n = Weapons.tubes(slot)
	if not n then return end
	local inf = T.dev.infiniteAmmo and e.isPlayer
	local held = inf and math.huge or (e.cargo[slot.ammo] or 0)
	if slot.armedId == nil then
		slot.armedId, slot.armed, slot.arming = slot.ammo, math.min(n, held), 0
	elseif slot.armedId ~= slot.ammo then
		slot.armedId, slot.armed, slot.arming = slot.ammo, 0, 0
	end
	slot.armed = math.min(slot.armed, n, held)
	if slot.armed < n and held > slot.armed then
		slot.arming = slot.arming + dt
		local t = data.items[slot.ammo].shot.armTime or 1
		if slot.arming >= t then slot.armed, slot.arming = slot.armed + 1, 0 end
	else
		slot.arming = 0
	end
end

-- Pulse and beam lasers; their default color when the weapon sets none.
local LASER_COLOR = { 0.55, 0.95, 1 }
Weapons.LASER_COLOR = LASER_COLOR
function Weapons.isLaser(w) return w.kind == "laser" end

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

-- How far a drill reaches fully out: its own length, else twice the
-- ship's half length (as long as the ship).
function Weapons.drillLength(e, w)
	return w.length or e.halfLength * 2
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

	if w.kind == "drill" then
		-- Mining drill: extends out of its mount (which aims like any gun's) while held, up to
		-- the ship's own length past the hardpoint, and grinds whatever the
		-- tip touches. No ammo, a little power per second. Rock it breaks
		-- drops ore (Game:breakAsteroid).
		local need = (w.powerPerSecond or 0) * dt
		if e.power < need then slot.starved = true; return end
		slot.starved = false
		e.power = e.power - need
		local ddx, ddy = dx, dy
		slot.extend = min(1, (slot.extend or 0) + dt / (w.extendTime or 0.4))
		local reach = Weapons.drillLength(e, w) * slot.extend
		local ex, ey = wx + ddx * reach, wy + ddy * reach
		local hit = game:raycast(wx, wy, ex, ey, e.team)
		slot.drillHit = nil
		if hit then
			local t = hit.entity
			local rock = t.kind == "asteroid"
			if rock then t.drilled = true end
			game:damage(t, w.damage * dt * (rock and (w.rockDamage or 1) or 1), e, "drill", hit.x, hit.y)
			slot.drillHit = { hit.x, hit.y }
			-- a steady spray of sparks and grit while it bites
			slot.sparkT = (slot.sparkT or 0) - dt
			if slot.sparkT <= 0 then
				slot.sparkT = 0.04
				game:spark(hit.x, hit.y, 3, { 1, 0.8, 0.4 })
				if rock and love.math.random() < 0.4 then game:spark(hit.x, hit.y, 2, t.line or { 0.6, 0.6, 0.65 }) end
			end
		end
		return
	end

	-- Lasers: hit instantly along each of w.beams lines (fanned over
	-- w.beamSpread degrees; a shotgun laser has several), each doing the
	-- full damage. A pulse fires once per shot and lingers w.pulse seconds;
	-- a beam burns while the trigger is held, per second.
	if Weapons.isLaser(w) then
		local beam = w.beam
		if not beam and slot.cooldown > 0 then return end
		local need = beam and w.powerPerSecond * dt or w.powerPerShot
		if e.power < need then slot.starved = true; return end
		slot.starved = false
		e.power = e.power - need
		local damage = w.damage * (beam and dt or 1) * mult.primaryDamage
		local n, fan = w.beams or 1, rad(w.beamSpread or 0)
		local c = w.color or LASER_COLOR
		local spark = { 0.7 + 0.3 * c[1], 0.7 + 0.3 * c[2], 0.7 + 0.3 * c[3] }
		local lines = {}
		for i = 1, n do
			local a = angle + (n > 1 and fan * ((i - 1) / (n - 1) - 0.5) or 0)
			local bx, by = cos(a), sin(a)
			local ex, ey = wx + bx * w.range, wy + by * w.range
			local hit = game:raycast(wx, wy, ex, ey, e.team)
			if hit then
				ex, ey = hit.x, hit.y
				game:damage(hit.entity, damage, e, "laser", hit.x, hit.y)
				if not beam then game:spark(hit.x, hit.y, 8, spark)
				elseif love.math.random() < dt * 20 then game:spark(hit.x, hit.y, 3, spark) end
			end
			lines[i] = { wx, wy, ex, ey }
		end
		slot.beams = { lines = lines, t = game.time, life = beam and 0.08 or (w.pulse or 0.12), color = c, width = w.beamWidth }
		if beam then
			if not slot.firing then events.emit("fire", e, slot) end
		else
			slot.cooldown = 1 / w.fireRate
			game:muzzle(wx, wy, angle, 1.0)
			events.emit("fire", e, slot)
		end
		return
	end

	-- Everything else fires one round per shot.
	if slot.cooldown > 0 then return end
	-- A drone bay controls only so many drones at once: its `control`
	-- budget, which each drone in the air uses its size's worth of.
	if w.kind == "drone" then
		local used = 0
		for _, d in ipairs(game.entities) do
			if d.drone and d.owner == e and d.bay == slot.slot and not d.dead then used = used + d.control end
		end
		local cost = DRONE_CONTROL[data.items[slot.ammo].size]
		if used + cost > (w.control or 1) then
			slot.cooldown = 0.3
			if e.isPlayer and not slot.fullWarned then game:toast("DRONE BAY AT CAPACITY", 1.2) end
			slot.fullWarned = true
			return
		end
		slot.fullWarned = false
	end
	-- Out of the picked ammo: fall back to another this weapon takes, and
	-- back to the pick as soon as there's some in the hold again.
	local pick = slot.pick or slot.ammo
	slot.pick = pick
	if not (T.dev.infiniteAmmo and e.isPlayer) then
		if (e.cargo[pick] or 0) > 0 then
			slot.ammo = pick
		elseif (e.cargo[slot.ammo] or 0) <= 0 then
			for _, id in ipairs(slot.ammoOptions) do
				if (e.cargo[id] or 0) > 0 then slot.ammo = id; break end
			end
		end
	end
	local rate = w.fireRate * (not slot.bay and mult.primaryFireRate or 1)
	-- a missile rack waits on its tubes (with ammo left, it's re-arming)
	if w.capacity and ((e.cargo[slot.ammo] or 0) > 0 or (T.dev.infiniteAmmo and e.isPlayer)) then
		Weapons.arm(e, slot, 0)
		if slot.armed < 1 then slot.cooldown = 0.05; return end
	end
	if not takeAmmo(e, slot.ammo) then
		slot.empty = true
		slot.cooldown = 0.3
		if e.isPlayer then game:toast("OUT OF " .. data.items[slot.ammo].name:upper(), 1.2) end
		return
	end
	slot.empty = false
	if w.capacity then slot.armed = slot.armed - 1 end
	slot.cooldown = 1 / rate

	-- The round sets the damage and flight; the weapon only how it's fired.
	local ws = data.items[slot.ammo].shot
	local kind = data.items[slot.ammo].family
	local spread = rad(w.spread or 0)
	local mountAngle = angle
	angle = angle + (random() * 2 - 1) * spread
	dx, dy = cos(angle), sin(angle)
	-- Multi-barrel mounts take turns, each barrel offset across the line of
	-- fire; weapon art with muzzle points fires from those instead.
	local mx, my = require("src.weapon_visual").muzzle(slot.module, slot)
	if mx then
		local ca, sa = cos(mountAngle), sin(mountAngle)
		wx, wy = wx + ca * mx - sa * my, wy + sa * mx + ca * my
	elseif (w.barrels or 1) > 1 then
		slot.barrel = (slot.barrel or 0) % w.barrels + 1
		local off = (slot.barrel - (w.barrels + 1) / 2) * (w.barrelGap or 8)
		wx, wy = wx - dy * off, wy + dx * off
	end
	local svx, svy = e.body:getLinearVelocity()

	-- Drone bays launch a ship, not a projectile.
	if kind == "drone" then
		local d = game:launchDrone(e, data.items[slot.ammo], wx, wy, angle)
		d.bay, d.control = slot.slot, DRONE_CONTROL[data.items[slot.ammo].size]
		game:muzzle(wx, wy, angle, 1.2)
		events.emit("fire", e, slot)
		return
	end

	local p = {
		kind = kind, team = e.team, owner = e,
		x = wx, y = wy, px = wx, py = wy,
		vx = svx + dx * ws.speed, vy = svy + dy * ws.speed,
		damage = ws.damage, splash = ws.splash, knockback = (ws.knockback or 0),
		size = data.items[slot.ammo].size,
		cause = ws.vaporize and "atomic" or nil,   -- atomic warheads leave no wreck
		born = game.time,                           -- (launch glow)
		ox = wx, oy = wy,                           -- where it left the barrel (trails stop there)
	}

	if kind == "gun" or kind == "shotgun" then
		p.kind = "gun"                             -- pellets fly and hit like rounds
		p.life = ws.range / ws.speed
		p.maxLife = p.life
		p.damage = ws.damage * mult.primaryDamage
	elseif kind == "artillery" then
		p.life = ws.range / ws.speed
		p.damage = ws.damage * mult.primaryDamage
		p.burst = true
		p.fuse = ws.fuse or (ws.splash or 40) * T.artilleryFuse
	elseif kind == "missile" then
		-- Fire and forget: picks a target on launch and chases it. With a
		-- guidance computer it takes the computer's lock and finds a new
		-- target if its own dies.
		p.guided = game:computer(e, "guidance") ~= nil
		p.vx, p.vy = svx + dx * ws.speed * 0.4, svy + dy * ws.speed * 0.4
		p.maxSpeed, p.accel, p.turnRate = ws.speed, ws.accel, ws.turnRate
		p.life = ws.range / ws.speed * 1.3
		p.damage = ws.damage * mult.missileDamage
		p.target = (p.guided and e.lock and not e.lock.dead and e.lock) or nearestTargetTo(game, e.intent.aimX, e.intent.aimY, e.team, 600)
			or nearestTargetTo(game, wx + dx * 900, wy + dy * 900, e.team, 1000)
		p.burst = true
		p.fuse = (ws.splash or 40) * 0.5
	elseif kind == "torpedo" then
		-- Very fast, and steers only a little: aim it, then it corrects
		-- slowly toward the target nearest your aim (or the guidance lock).
		p.guided = game:computer(e, "guidance") ~= nil
		p.maxSpeed, p.accel = ws.speed, 0
		p.turnRate = ws.turnRate or 0
		p.life = ws.range / ws.speed
		p.target = (p.guided and e.lock and not e.lock.dead and e.lock) or nearestTargetTo(game, e.intent.aimX, e.intent.aimY, e.team, 500)
		p.burst = true
	end

	table.insert(game.projectiles, p)
	-- A shotgun shell is several pellets, fanned across pelletSpread.
	if kind == "shotgun" then
		local fan = rad(ws.pelletSpread or 8)
		for _ = 2, ws.pellets or 1 do
			local a = angle + (random() * 2 - 1) * fan
			local q = {}
			for k, v in pairs(p) do q[k] = v end
			q.vx, q.vy = svx + cos(a) * ws.speed, svy + sin(a) * ws.speed
			table.insert(game.projectiles, q)
		end
	end

	-- Guns and artillery kick back by a share of the round's knockback;
	-- launchers (and older data) by a fixed impulse.
	local r = (w.recoilPct and (ws.knockback or 0) * w.recoilPct / 100 or (w.recoil or 0) * (ws.recoil or 1)) * T.recoilScale
	if r > 0 then e.body:applyLinearImpulse(-dx * r, -dy * r, wx, wy) end
	if kind == "artillery" or kind == "torpedo" then game:muzzle(wx, wy, angle, 1.6) else game:muzzle(wx, wy, angle, 0.6) end
	if e.isPlayer and (kind == "artillery" or kind == "shotgun") then game:shake(0.18) end
	events.emit("fire", e, slot)
end

Weapons.fire = fire

-- How far a weapon reaches with what it's loaded with.
function Weapons.range(slot)
	if slot.ammo then return data.items[slot.ammo].shot.range end
	return slot.w.range or 0
end

function Weapons.update(game, e, dt)
	local it = e.intent
	for _, slot in ipairs(e.weapons) do
		slot.cooldown = max(0, slot.cooldown - dt)
		Weapons.arm(e, slot, dt)
		aimSlot(e, slot, dt)
		-- a drill retracts when the trigger is let go
		if slot.w.kind == "drill" and not ((slot.group == "primary" and it.firePrimary) or (slot.group == "secondary" and it.fireSecondary)
			or (slot.group == "tertiary" and it.fireTertiary)) then
			slot.extend = max(0, (slot.extend or 0) - dt / (slot.w.extendTime or 0.4))
			slot.drillHit = nil
		end
		local wants = (slot.group == "primary" and it.firePrimary) or (slot.group == "secondary" and it.fireSecondary)
			or (slot.group == "tertiary" and it.fireTertiary)
		-- AI only fires a weapon when the target is roughly in its range.
		if wants and it.targetDist and it.targetDist > Weapons.range(slot) * 1.05 then wants = false end
		-- When the trigger goes down, delay each identical weapon by its
		-- share of the fire interval so they ripple instead of volleying.
		if wants and not slot.firing and slot.cooldown == 0 and slot.w.fireRate then
			slot.cooldown = (slot.stagger or 0) / slot.w.fireRate
		end
		slot.firing = wants
		if wants then fire(game, e, slot, dt) end
	end
	if e.massDirty then Ship.updateMass(e) end
end

-- Projectiles ---------------------------------------------------------------

-- Proximity fuse: the first enemy ship within fuse range of the shell.
local function fuseTarget(game, p)
	-- a guided missile only bursts early beside its own target
	local t = p.kind == "missile" and p.target
	if t and t.kind == "decoy" then
		-- a decoyed missile bursts on the flare (next step)
		if not t.dead and (t.x - p.x) ^ 2 + (t.y - p.y) ^ 2 < p.fuse * p.fuse then p.life = 0 end
		return nil
	end
	if t then
		if not t.dead and Ship.distanceTo(t, p.x, p.y) < p.fuse then return t end
		return nil
	end
	for _, o in ipairs(game.entities) do
		if o.kind == "ship" and not o.dead and o.team ~= p.team then
			if Ship.distanceTo(o, p.x, p.y) < p.fuse then return o end
		end
	end
end

-- Missiles fly through the planet's current like ships do: their own speed
-- and heading are relative to it, and the current carries them along.
-- Missiles steer round ships that aren't their target: any ship ahead
-- within a short look-ahead, whose hull (plus a margin) the missile's line
-- would pass through, pushes the wanted heading away from it, harder the
-- closer it is. (The ship that fired it is left alone for a moment, so
-- the missile can clear its own launcher.)
local AVOID_MARGIN = 60
local function avoidance(game, p, t, hx, hy, speed)
	local look = speed * 0.6 + 200
	local ax, ay = 0, 0
	for _, o in ipairs(game.entities) do
		if o.kind == "ship" and o ~= t and not o.dead and not o.dockState and (o ~= p.owner or (p.age or 0) > 0.6) then
			local ox, oy = o.body:getPosition()
			local dx, dy = ox - p.x, oy - p.y
			local ahead = dx * hx + dy * hy
			if ahead > 0 and ahead < look then
				local side = dx * -hy + dy * hx            -- + means it's to the left
				local clear = (o.halfLength or 20) + AVOID_MARGIN
				if math.abs(side) < clear then
					local k = (1 - ahead / look) * (1 - math.abs(side) / clear)
					local s = side >= 0 and -1 or 1          -- swerve the other way
					ax, ay = ax + -hy * s * k * 2, ay + hx * s * k * 2
				end
			end
		end
	end
	return ax, ay
end

local function steerMissile(game, p, dt)
	local t = p.target
	if t and t.dead then p.target, t = nil, nil end
	-- a guided missile whose target died picks the nearest other one
	if not t and p.guided and p.kind == "missile" and not p.decoyed then
		p.retarget = (p.retarget or 0) - dt
		if p.retarget <= 0 then
			p.retarget = 0.25
			t = nearestTargetTo(game, p.x, p.y, p.team, 3000)
			p.target = t
		end
	end
	p.age = (p.age or 0) + dt
	local fx, fy = game:flowAt(p.x, p.y)
	local rvx, rvy = p.vx - fx, p.vy - fy
	local speed = sqrt(rvx * rvx + rvy * rvy)
	local heading = atan2(rvy, rvx)
	if t then
		local tx, ty = t.body:getPosition()
		local wx, wy = tx - p.x, ty - p.y
		local wl = sqrt(wx * wx + wy * wy)
		if wl > 0 then wx, wy = wx / wl, wy / wl end
		local ax, ay = avoidance(game, p, t, cos(heading), sin(heading), speed)
		local want = atan2(wy + ay, wx + ax)
		local diff = Ship.wrapAngle(want - heading)
		local turn = p.turnRate * dt
		heading = heading + max(-turn, min(turn, diff))
	end
	speed = min(p.maxSpeed, speed + p.accel * dt)
	p.vx, p.vy = cos(heading) * speed + fx, sin(heading) * speed + fy
	p.trailTimer = (p.trailTimer or 0) - dt
end

-- Countermeasures: a ship with a flare pod (a module with flares = true)
-- and flares in its hold fires them by itself when a missile chasing it
-- comes within FLARE_RANGE. Each missile after it then has FLARE_CHANCE
-- of going for the flare instead, and it won't come back.
local FLARE_RANGE, FLARE_CHANCE, FLARE_COOLDOWN, FLARE_LIFE = 900, 0.75, 1.2, 2.0

local function hasFlarePod(e)
	if e.flarePod == nil or e.flarePodFor ~= e.loadout then
		e.flarePod, e.flarePodFor = false, e.loadout
		for _, id in pairs(e.loadout or {}) do
			local m = id and data.modules[id]
			if m and m.flares then e.flarePod = true end
		end
	end
	return e.flarePod
end

local function updateFlares(game, dt)
	game.decoys = game.decoys or {}
	for i = #game.decoys, 1, -1 do
		local d = game.decoys[i]
		d.life = d.life - dt
		d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
		d.vx, d.vy = d.vx * (1 - dt), d.vy * (1 - dt)
		if d.life <= 0 then d.dead = true; table.remove(game.decoys, i) end
	end
	for _, p in ipairs(game.projectiles) do
		local t = p.target
		if p.kind == "missile" and t and t.kind == "ship" and not t.dead and not p.decoyed and hasFlarePod(t) then
			local tx, ty = t.body:getPosition()
			if (tx - p.x) ^ 2 + (ty - p.y) ^ 2 < FLARE_RANGE * FLARE_RANGE then
				if (t.flareCooldown or 0) <= game.time and (t.cargo.flare or 0) > 0 then
					t.flareCooldown = game.time + FLARE_COOLDOWN
					takeAmmo(t, "flare")
					local vx, vy = t.body:getLinearVelocity()
					for k = 1, 3 do
						local a = love.math.random() * math.pi * 2
						local d = { kind = "decoy", x = tx, y = ty, vx = vx * 0.5 + cos(a) * 250, vy = vy * 0.5 + sin(a) * 250, life = FLARE_LIFE }
						d.body = { getPosition = function() return d.x, d.y end }
						table.insert(game.decoys, d)
						t.lastFlares = d
					end
					if t.isPlayer then game:toast("FLARES", 0.8) end
				end
				-- missiles near a fresh flare may go for it
				local d = t.lastFlares
				if d and not d.dead and p.flareRoll ~= d then
					p.flareRoll = d
					if love.math.random() < FLARE_CHANCE then p.target, p.decoyed = d, true end
				end
			end
		end
	end
end

function Weapons.updateProjectiles(game, dt)
	updateFlares(game, dt)
	local list = game.projectiles
	local i = 1
	while i <= #list do
		local p = list[i]
		if p.kind == "missile" or (p.kind == "torpedo" and p.turnRate and p.turnRate > 0) then steerMissile(game, p, dt) end
		p.px, p.py = p.x, p.y
		local nx, ny = p.x + p.vx * dt, p.y + p.vy * dt
		local hit = game:raycast(p.x, p.y, nx, ny, p.team)
		local done = false

		if hit then
			p.x, p.y = hit.x, hit.y
			local sp = sqrt(p.vx * p.vx + p.vy * p.vy)
			local k = p.knockback * T.knockbackScale
			if p.burst then
				game:explode(p.x, p.y, p.splash, p.damage, k, p.owner, hit.entity, p.cause or p.kind)
			else
				local dmg = p.damage
				-- gun rounds lose punch the further they've flown
				if p.maxLife then dmg = dmg * (1 - T.gunFalloff * (1 - p.life / p.maxLife)) end
				game:damage(hit.entity, dmg, p.owner, p.kind, hit.x, hit.y)
				if hit.entity.kind == "ship" and not hit.entity.driverProtected then hit.entity.body:applyLinearImpulse(p.vx / sp * k, p.vy / sp * k, hit.x, hit.y) end
				game:spark(hit.x, hit.y, 4, { 1, 0.85, 0.5 })
			end
			done = true
		else
			p.x, p.y = nx, ny
			p.life = p.life - dt
			if p.life <= 0 then
				if p.burst then game:explode(p.x, p.y, p.splash, p.damage, p.knockback * T.knockbackScale, p.owner, nil, p.cause or p.kind) end
				done = true
			elseif p.fuse then
				local near = fuseTarget(game, p)
				if near then
					game:explode(p.x, p.y, p.splash, p.damage, p.knockback * T.knockbackScale, p.owner, near, p.cause or p.kind)
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
