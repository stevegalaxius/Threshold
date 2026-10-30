--[[
	Ships: the player and every enemy use this same code. A ship is a Box2D
	body plus its hull, fitted modules, hold contents and current state.

	Each step something fills in ship.intent (the player's input, or the AI),
	and Ship.fly turns that intent into forces. Nothing ever moves a ship by
	setting its position or velocity directly: it all goes through thrust,
	torque and impulses, so mass matters for everyone.
]]

local data = require("src.data")
local stats = require("src.stats")
local T = require("src.tuning")

local Ship = {}

local sqrt, atan2, cos, sin, abs, max, min, pi, rad = math.sqrt, math.atan2, math.cos, math.sin, math.abs, math.max, math.min, math.pi, math.rad

local function copy(t)
	local out = {}
	for k, v in pairs(t or {}) do out[k] = v end
	return out
end

local function wrapAngle(a)
	return (a + pi) % (2 * pi) - pi
end
Ship.wrapAngle = wrapAngle

function Ship.emptyIntent()
	-- thrust: -1..1 along the nose (forward is the main engine, back is retro thrusters)
	-- strafe: -1..1 to the ship's right (maneuvering thrusters, or turning
	--         right on a hull with helm = "turn")
	return { thrust = 0, strafe = 0, aimX = 0, aimY = 0, firePrimary = false, fireSecondary = false, boost = false }
end

--[[ Ship.new(game, opts)
	opts.hull     hull id
	opts.loadout  module ids by slot (defaults to the hull's loadout)
	opts.cargo    hold contents { itemId = count } (defaults to the hull's cargo)
	opts.x, opts.y, opts.angle, opts.team, opts.enemy (enemy definition, for AI ships)
]]
function Ship.new(game, opts)
	local hull = assert(data.hulls[opts.hull], "unknown hull " .. tostring(opts.hull))
	local e = {
		kind = "ship", id = game:nextId(), team = opts.team or 2,
		hull = hull, def = opts.enemy,
		loadout = copy(opts.loadout or hull.loadout),
		cargo = copy(opts.cargo or hull.cargo),
		intent = Ship.emptyIntent(),
		flash = 0, spool = 0, mainBurn = 0, retroBurn = 0, sideBurn = 0, boostCooldown = 0,
	}

	local body = love.physics.newBody(game.world, opts.x or 0, opts.y or 0, "dynamic")
	local fixture = love.physics.newFixture(body, love.physics.newCircleShape(hull.radius), 1)
	fixture:setRestitution(0.35)
	fixture:setFriction(0.3)
	fixture:setUserData(e)
	body:setUserData(e)
	body:setAngle(opts.angle or 0)
	body:setAngularDamping(0)
	e.body, e.fixture = body, fixture

	Ship.refit(e)
	e.armor = e.stats.armor
	e.power = e.stats.powerCap
	return e
end

-- Rebuild stats and weapon list after the hull's modules change.
function Ship.refit(e)
	local hull = e.hull
	for i, slot in ipairs(hull.slots) do
		local m = e.loadout[i] and data.modules[e.loadout[i]]
		if not m or m.family ~= slot.family or m.size ~= slot.size then e.loadout[i] = false end
	end

	e.stats = stats.compute(hull, e.loadout)
	e.weapons = {}
	for i, slot in ipairs(hull.slots) do
		local m = e.loadout[i] and data.modules[e.loadout[i]]
		if m and m.weapon then
			table.insert(e.weapons, {
				slot = slot, module = m, w = m.weapon,
				group = (slot.family == "secondary") and "secondary" or "primary",
				ammo = data.ammoFor(m), cooldown = 0,
				mount = slot.mount or hull.mount or "gimbal", aim = 0,
			})
		end
	end

	if e.armor then e.armor = min(e.armor, e.stats.armor) end
	if e.power then e.power = min(e.power, e.stats.powerCap) end
	Ship.updateMass(e)
end

-- Body mass = dry mass + whatever's in the hold. Called whenever the hold changes.
function Ship.updateMass(e)
	local volume, cargoMass = stats.cargo(e.cargo)
	e.holdUsed = volume
	e.cargoMass = cargoMass
	local m = (e.stats.mass + cargoMass) * T.massScale
	local r = e.hull.radius
	e.body:setMassData(0, 0, m, m * r * r * 0.5)
	e.massDirty = false
end

function Ship.holdFree(e)
	return e.stats.hold - e.holdUsed
end

-- How many of an item fit in the hold right now.
function Ship.canFit(e, itemId)
	local item = data.items[itemId]
	if not item then return 0 end
	return math.floor(Ship.holdFree(e) / item.volume + 1e-6)
end

-- Add items to the hold; returns how many actually fit.
function Ship.addCargo(e, itemId, count)
	local n = min(count, Ship.canFit(e, itemId))
	if n > 0 then
		e.cargo[itemId] = (e.cargo[itemId] or 0) + n
		Ship.updateMass(e)
	end
	return n
end

-- World position of a slot's hardpoint.
function Ship.hardpoint(e, slot)
	local x, y = e.body:getPosition()
	local a = e.body:getAngle()
	local sx, sy = slot.x or 0, slot.y or 0
	return x + sx * cos(a) - sy * sin(a), y + sx * sin(a) + sy * cos(a)
end

-- Turn intent into forces. Runs once per physics step, before the world updates.
function Ship.fly(e, dt)
	local b, s, it = e.body, e.stats, e.intent

	-- Power: reactor output minus passive draw refills the capacitor.
	e.power = min(s.powerCap, e.power + s.powerNet * dt)
	if e.power < 0 then e.power = 0 end

	-- Thrust is relative to the nose. The main engine only pushes forward,
	-- and spools up over the hull's spoolTime (winding down twice as fast),
	-- which makes heavy hulls feel heavy. Reverse comes from built-in retro
	-- thrusters (retroThrust), sideways only from maneuvering thrusters
	-- (sideThrust). On a hull with helm = "turn", A/D turn the hull instead.
	local fwd = max(-1, min(1, it.thrust or 0))
	local side = max(-1, min(1, it.strafe or 0))
	local steer = 0
	if e.hull.helm == "turn" then steer, side = side, 0 end
	local main = max(0, fwd)
	local spoolTime = e.hull.spoolTime or 0
	if spoolTime > 0 then
		local step = dt / spoolTime
		e.spool = e.spool + max(-2 * step, min(step, main - e.spool))
	else
		e.spool = main
	end
	local a = b:getAngle()
	local fx, fy = cos(a), sin(a)
	local rx, ry = -fy, fx                         -- the ship's right-hand side
	local retro = s.retroThrust * T.sideScale
	local aux = s.sideThrust * T.sideScale
	local scale = T.FORCE_PER_KN * T.thrustScale
	local f = (e.spool * s.thrust + min(0, fwd) * retro) * scale
	local l = side * aux * scale
	if f ~= 0 or l ~= 0 then b:applyForce(fx * f + rx * l, fy * f + ry * l) end
	e.mainBurn = e.spool
	e.retroBurn = retro > 0 and max(0, -fwd) or 0
	e.sideBurn = aux > 0 and side or 0

	-- Quadratic drag gives a natural top speed (no hard cap):
	-- top speed = sqrt(thrust / drag).
	local vx, vy = b:getLinearVelocity()
	local speed = sqrt(vx * vx + vy * vy)
	local k = e.hull.drag * T.dragScale
	b:applyForce(-k * speed * vx, -k * speed * vy)
	b:setLinearDamping(T.linearDamping)

	-- Afterburner: an instant forward kick from the main engine, paid for with stored power.
	e.boostCooldown = max(0, e.boostCooldown - dt)
	if it.boost and e.boostCooldown == 0 and e.power >= T.boostCost then
		local m = b:getMass()
		b:applyLinearImpulse(fx * m * T.boostSpeed, fy * m * T.boostSpeed)
		e.power = e.power - T.boostCost
		e.boostCooldown = 1.0
		e.boostFlash = 0.25
	end

	-- Turning: a controller that tries to point the nose at the aim point,
	-- limited by the torque the hull and engine can produce. Heavy ships
	-- (more rotational inertia) turn slower with the same thrusters. The
	-- spin is capped by the hull's turnSpeed, and the controller starts
	-- braking early enough that the torque it has can stop the spin right
	-- on target, so heavy hulls ease in instead of overshooting.
	-- With helm = "turn", A/D set the spin directly and the hull holds its
	-- heading when they're released.
	local inertia = b:getInertia()
	local maxTorque = s.turn * T.TORQUE_PER_TURN * T.turnScale
	local cap = min(T.maxTurnRate, e.hull.turnSpeed and rad(e.hull.turnSpeed) or T.maxTurnRate)
	local targetW
	if e.hull.helm == "turn" then
		targetW = steer * cap
	else
		local x, y = b:getPosition()
		local diff = wrapAngle(atan2(it.aimY - y, it.aimX - x) - a)
		local brake = sqrt(2 * 0.8 * maxTorque / inertia * abs(diff))
		targetW = min(cap, abs(diff) * T.aimGain, brake) * (diff < 0 and -1 or 1)
	end
	local w = b:getAngularVelocity()
	local torque = (targetW - w) * inertia * T.turnResponse
	b:applyTorque(max(-maxTorque, min(maxTorque, torque)))

	e.flash = max(0, e.flash - dt)
	if e.boostFlash then e.boostFlash = max(0, e.boostFlash - dt) end
end

-- Convert a world-space direction someone wants to move in into this ship's
-- thrust (along the nose) and strafe (to its right). Used by the AI.
function Ship.toLocal(e, mx, my)
	local a = e.body:getAngle()
	local fx, fy = cos(a), sin(a)
	return mx * fx + my * fy, mx * -fy + my * fx
end

-- Rough performance numbers for the debug readout.
function Ship.performance(e)
	local m = e.body:getMass()
	local thrust = e.stats.thrust * T.FORCE_PER_KN * T.thrustScale
	local k = e.hull.drag * T.dragScale
	return {
		mass = m,
		accel = thrust / m,
		topSpeed = sqrt(thrust / k),
		sideAccel = e.stats.sideThrust * T.FORCE_PER_KN * T.thrustScale * T.sideScale / m,
		turnAccel = e.stats.turn * T.TORQUE_PER_TURN * T.turnScale / e.body:getInertia(),
		turnSpeed = math.deg(min(T.maxTurnRate, e.hull.turnSpeed and rad(e.hull.turnSpeed) or T.maxTurnRate)),
	}
end

return Ship
