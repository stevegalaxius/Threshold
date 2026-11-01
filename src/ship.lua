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
local Hold = require("src.inventory.hold")
local Shapes = require("src.inventory.shapes")

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
	return { thrust = 0, strafe = 0, aimX = 0, aimY = 0, firePrimary = false, fireSecondary = false, fireAux = false, boost = false, tractor = false }
end

--[[ Ship.new(game, opts)
	opts.hull     hull id
	opts.loadout  module ids by slot (defaults to the hull's loadout)
	opts.cargo    hold contents { itemId = count } (defaults to the hull's cargo)
	opts.x, opts.y, opts.angle, opts.team, opts.enemy (enemy definition, for AI ships)
	opts.color    paint { r, g, b } (defaults to the enemy definition's color)
	opts.grid     true for a grid hold (the player): items take shapes on a
	              grid of 1 m3 cells. Other ships just count volume.
	opts.hold     an existing grid hold to carry (a ship coming out of a
	              hangar or a save keeps its hold exactly as it was)
	opts.armor    armor to start with (defaults to full)
]]
function Ship.new(game, opts)
	local hull = assert(data.hulls[opts.hull], "unknown hull " .. tostring(opts.hull))
	local e = {
		kind = "ship", id = game:nextId(), team = opts.team or 2,
		hull = hull, def = opts.enemy,
		loadout = copy(opts.loadout or hull.loadout),
		cargo = copy(opts.cargo or hull.cargo),
		gridHold = opts.grid or opts.hold ~= nil,
		hold = opts.hold,
		intent = Ship.emptyIntent(),
		flash = 0, spool = 0, mainBurn = 0, retroBurn = 0, sideBurn = 0, afterburn = false,
		color = opts.color or (opts.enemy and opts.enemy.color) or { 0.95, 0.5, 0.32 },
	}

	-- The spine: the line through the hull's middle, tail to nose, inset by
	-- its radius (half its width). Distances to the hull are measured to it.
	local r = hull.radius
	local noseX, tailX = 0, 0
	for i = 1, #hull.shape, 2 do
		noseX, tailX = max(noseX, hull.shape[i]), min(tailX, hull.shape[i])
	end
	local s1, s2 = tailX + r, noseX - r
	if s2 < s1 then s1, s2 = (s1 + s2) / 2, (s1 + s2) / 2 end
	e.spine = { s1, s2 }
	e.noseX, e.tailX = noseX, tailX
	e.halfLength = max(noseX, -tailX)

	local body = love.physics.newBody(game.world, opts.x or 0, opts.y or 0, "dynamic")
	-- the body collides in the hull's drawn shape: every triangle of every
	-- part (parts tagged collide = false are drawn only). Mass is set from
	-- the stats in Ship.updateMass, so the fixtures' density doesn't matter.
	local made = 0
	for _, part in ipairs(hull.parts) do
		if part.collide ~= false then
			for _, t in ipairs(part.tris) do
				local a2 = math.abs((t[3] - t[1]) * (t[6] - t[2]) - (t[5] - t[1]) * (t[4] - t[2]))
				if a2 > 4 then   -- Box2D refuses slivers
					local fixture = love.physics.newFixture(body, love.physics.newPolygonShape(t), 1)
					fixture:setRestitution(0.35)
					fixture:setFriction(0.3)
					fixture:setUserData(e)
					made = made + 1
				end
			end
		end
	end
	if made == 0 then
		-- a hull too small or thin for polygons: a circle of its radius
		local fixture = love.physics.newFixture(body, love.physics.newCircleShape(0, 0, r), 1)
		fixture:setRestitution(0.35)
		fixture:setFriction(0.3)
		fixture:setUserData(e)
	end
	body:setUserData(e)
	body:setAngle(opts.angle or 0)
	body:setAngularDamping(0)
	e.body = body

	if e.hold then e.cargo = Hold.totals(e.hold) end
	Ship.refit(e)
	e.armor = min(opts.armor or e.stats.armor, e.stats.armor)
	e.power = e.stats.powerCap
	return e
end

-- Everything that makes this ship this ship, to park it in a hangar or
-- carry it to another level: hull, modules, hold (the hold itself, not a
-- copy), armor and paint. Game:spawnPlayer turns one back into a ship.
function Ship.record(e)
	return {
		hull = e.hull.id, loadout = copy(e.loadout), hold = e.hold, cargo = not e.hold and copy(e.cargo) or nil,
		armor = e.armor, color = e.color and copy(e.color) or nil,
	}
end

-- Rebuild stats and weapon list after the hull's modules change.
function Ship.refit(e)
	local hull = e.hull
	for i, slot in ipairs(hull.slots) do
		local m = e.loadout[i] and data.modules[e.loadout[i]]
		if not m or not data.fits(slot, m) then e.loadout[i] = false end
	end

	e.stats = stats.compute(hull, e.loadout)
	e.weapons = {}
	for i, slot in ipairs(hull.slots) do
		local m = e.loadout[i] and data.modules[e.loadout[i]]
		if m and m.weapon then
			table.insert(e.weapons, {
				slot = slot, module = m, w = m.weapon,
				group = slot.family,              -- primary, secondary or auxiliary
				ammo = data.ammoFor(m), ammoOptions = data.ammoOptions(m), cooldown = 0,
				mount = slot.mount or hull.mount or "gimbal", aim = 0,
			})
		end
	end
	-- Stagger: identical weapons in the same fire group take turns instead of
	-- firing in unison (see Weapons.update).
	local count, seen = {}, {}
	for _, w in ipairs(e.weapons) do
		local key = w.group .. ":" .. w.module.id
		count[key] = (count[key] or 0) + 1
	end
	for _, w in ipairs(e.weapons) do
		local key = w.group .. ":" .. w.module.id
		seen[key] = (seen[key] or 0) + 1
		w.stagger = (seen[key] - 1) / count[key]
	end

	if e.armor then e.armor = min(e.armor, e.stats.armor) end
	if e.power then e.power = min(e.power, e.stats.powerCap) end
	if e.gridHold then Ship.layoutHold(e) end
	Ship.updateMass(e)
end

-- The grids a ship's hold is made of: the hull's main hold (hull.holdGrid
-- = { w, h }, or a shape picked from its size), then one grid per fitted
-- module with hold space (Cargo Pods), in slot order.
function Ship.holdLayout(e)
	local layout, pods = {}, 0
	for i in ipairs(e.hull.slots) do
		local m = e.loadout[i] and data.modules[e.loadout[i]]
		if m and (m.hold or 0) > 0 then
			pods = pods + m.hold
			local w, h = Shapes.gridFor(m.hold)
			table.insert(layout, { key = "slot" .. i, name = m.name, w = w, h = h })
		end
	end
	local g = e.hull.holdGrid
	local w, h
	if g then w, h = g[1], g[2] else w, h = Shapes.gridFor(e.stats.hold - pods) end
	table.insert(layout, 1, { key = "hull", name = "Main hold", w = w, h = h })
	return layout
end

-- Build the grid hold, or rebuild it after a refit. Grids that didn't
-- change keep their layout; anything that no longer fits is set aside in
-- e.holdOverflow (only the debug panel can cause that for now; the station
-- screen will send it to storage).
function Ship.layoutHold(e)
	local left
	if e.hold then
		e.hold, left = Hold.relayout(e.hold, Ship.holdLayout(e))
	else
		e.hold = Hold.new(Ship.holdLayout(e))
		left = Hold.fill(e.hold, e.cargo)
	end
	e.holdOverflow = e.holdOverflow or {}
	for id, n in pairs(left) do e.holdOverflow[id] = (e.holdOverflow[id] or 0) + n end
	e.cargo = Hold.totals(e.hold)
end

-- Body mass = dry mass + whatever's in the hold. Called whenever the hold changes.
-- A grid hold first catches up with any change made to e.cargo (weapons
-- firing, the debug panel), and then counts cells instead of volume.
function Ship.updateMass(e)
	if e.hold then Hold.sync(e.hold, e.cargo) end
	local volume, cargoMass = stats.cargo(e.cargo)
	e.holdUsed = volume
	if e.hold then
		e.holdUsed, e.holdCap = Hold.cells(e.hold)
		cargoMass = cargoMass + Hold.innerMass(e.hold, data.items)   -- what loaded containers carry
	end
	e.cargoMass = cargoMass
	local m = (e.stats.mass + cargoMass) * T.massScale
	local r = e.hull.radius
	e.body:setMassData(0, 0, m, m * r * r * 0.5)
	e.massDirty = false
end

-- Why this ship can't leave a station, or nil if it can: it needs a
-- reactor, and an engine or maneuvering thrusters to move with.
function Ship.launchProblem(e)
	local has = {}
	for i in ipairs(e.hull.slots) do
		local m = e.loadout[i] and data.modules[e.loadout[i]]
		if m then has[m.family] = true end
	end
	if not has.reactor then return "no reactor" end
	if not has.engine and not has.thruster then return "no engine or thrusters" end
	return nil
end

-- Hold size in cubic metres (for a grid hold, its cells).
function Ship.holdCapacity(e)
	return e.holdCap or e.stats.hold
end

function Ship.holdFree(e)
	return Ship.holdCapacity(e) - e.holdUsed
end

-- How many of an item fit in the hold right now (up to `upTo`).
function Ship.canFit(e, itemId, upTo)
	local item = data.items[itemId]
	if not item then return 0 end
	if e.hold then return Hold.room(e.hold, itemId, upTo or 100000) end
	local n = math.floor(Ship.holdFree(e) / item.volume + 1e-6)
	return upTo and min(n, upTo) or n
end

-- Add items to the hold; returns how many actually fit. In a grid hold
-- they top up partial stacks, then go in the first space that fits.
function Ship.addCargo(e, itemId, count)
	if not data.items[itemId] or count <= 0 then return 0 end
	local n
	if e.hold then
		Hold.sync(e.hold, e.cargo)
		n = Hold.add(e.hold, itemId, count)
		e.cargo[itemId] = Hold.count(e.hold, itemId)
	else
		n = Ship.canFit(e, itemId, count)
		e.cargo[itemId] = (e.cargo[itemId] or 0) + n
	end
	if n > 0 then Ship.updateMass(e) end
	return n
end

-- Scoop a floating container into the hold, cargo and all. Returns true
-- if there was room.
function Ship.stowContainer(e, box)
	if not e.hold then return false end
	Hold.sync(e.hold, e.cargo)
	local s = { id = box.item, n = 1, inner = next(box.loot) and box.hold or nil }
	if not Hold.placeStack(e.hold, s) then return false end
	e.cargo = Hold.totals(e.hold)
	Ship.updateMass(e)
	return true
end

-- Distance from a world point to the ship's hull edge (0 or less = inside).
-- Measured to the hull's spine, so it's right along a long ship's length.
function Ship.distanceTo(e, px, py)
	local x, y = e.body:getPosition()
	local a = e.body:getAngle()
	local dx, dy = px - x, py - y
	local lx, ly = dx * cos(a) + dy * sin(a), -dx * sin(a) + dy * cos(a)
	local sx = max(e.spine[1], min(e.spine[2], lx))
	return sqrt((lx - sx) ^ 2 + ly * ly) - e.hull.radius
end

-- How far the tractor beam reaches from the hull: every ship has a basic
-- one, and a tractor module (tractorRange) extends it.
function Ship.tractorRange(e)
	return T.tractorBase + (e.stats.tractorRange or 0)
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

	-- Power: reactor output minus passive draw refills the capacitor, but
	-- only at thrustRecharge of that rate while any thruster is firing.
	local moving = (it.thrust or 0) ~= 0 or (it.strafe or 0) ~= 0 or it.boost
	local net = s.powerNet
	if net > 0 and moving then net = net * T.thrustRecharge end
	e.power = min(s.powerCap, e.power + net * dt)
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

	-- Afterburner: full main engine plus extra thrust, draining power fast.
	-- Once the capacitor runs dry it drops to reserve: boostReserve of its
	-- thrust with no drain, until power is back above boostRelight of
	-- capacity. (The empty check comes after the drain below: the reactor
	-- tops power up first every step, so it's never 0 up here.)
	if e.burnerLocked and e.power > s.powerCap * T.boostRelight then e.burnerLocked = false end
	local burner = it.boost and s.thrust > 0
		-- the lane's buff replaces it, except on heavies, which need the
		-- extra push to get anywhere on the road
		and (not e.laneBuff or e.hull.class == "heavy")
	if burner then fwd = 1 end
	e.afterburn = burner
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
	-- Maneuvering thrusters push forward too, but only matter when they
	-- out-push the main engine (no engine fitted, or a very weak one).
	local boost = burner and (e.burnerLocked and 1 + (T.boostThrust - 1) * T.boostReserve or T.boostThrust) or 1
	local engine = e.spool * s.thrust * boost
	local jets = max(0, fwd) * aux
	-- in a transit lane (e.laneBuff, src/transit.lua) every thruster hits
	-- far harder (the afterburner gets no extra on top)
	local buff = e.laneBuff and 1 + (T.laneThrust - 1) * e.laneBuff or 1
	local f = (max(engine, jets) + min(0, fwd) * retro) * scale * buff
	local l = side * aux * scale * buff
	if burner and not e.burnerLocked then
		e.power = max(0, e.power - s.powerCap * T.boostDrain * dt)
		if e.power <= 0 then e.burnerLocked = true end
	end
	if f ~= 0 or l ~= 0 then b:applyForce(fx * f + rx * l, fy * f + ry * l) end
	e.mainBurn = s.thrust > 0 and e.spool or 0
	e.foreBurn = jets > engine and max(0, fwd) or 0
	e.retroBurn = retro > 0 and max(0, -fwd) or 0
	e.sideBurn = aux > 0 and side or 0
	e.turnBurn = (aux > 0 and e.hull.helm == "turn") and steer or 0

	-- Quadratic drag gives a natural top speed (no hard cap):
	-- top speed = sqrt(thrust / drag). Drag is measured against the space
	-- the ship is in, so inside a planet's turning field (flowX/flowY, set
	-- by Game:applyCurrent) an idle ship drifts along with the current.
	local vx, vy = b:getLinearVelocity()
	vx, vy = vx - (e.flowX or 0), vy - (e.flowY or 0)
	local speed = sqrt(vx * vx + vy * vy)
	local k = e.hull.drag * T.dragScale * (e.laneBuff and 1 + (T.laneDrag - 1) * e.laneBuff or 1)
	if e.coasting then k = 0 end                   -- just fired from a mass driver
	b:applyForce(-k * speed * vx, -k * speed * vy)
	b:setLinearDamping(T.linearDamping)
	-- Box2D's damping slows against the world; push back so it, too, only
	-- slows the ship relative to the current.
	if e.flowX then
		local m = b:getMass() * T.linearDamping
		b:applyForce(e.flowX * m, e.flowY * m)
	end

	-- Turning: a controller that tries to point the nose at the aim point,
	-- limited by the torque the hull and engine can produce. Heavy ships
	-- (more rotational inertia) turn slower with the same thrusters. The
	-- spin is capped by the hull's turnSpeed, and the controller starts
	-- braking early enough that the torque it has can stop the spin right
	-- on target, so heavy hulls ease in instead of overshooting.
	-- With helm = "turn", A/D set the spin directly and the hull holds its
	-- heading when they're released.
	-- On a turn-helm hull the side jets can't strafe, so they help it turn:
	-- their thrust at the hull's edge adds torque and lifts the spin cap.
	local inertia = b:getInertia()
	local maxTorque = s.turn * T.TORQUE_PER_TURN * T.turnScale
	local cap = min(T.maxTurnRate, e.hull.turnSpeed and rad(e.hull.turnSpeed) or T.maxTurnRate)
	if e.hull.helm == "turn" and aux > 0 then
		local jet = aux * scale * e.hull.radius
		cap = cap * (1 + min(0.5, 0.5 * jet / max(maxTorque, 1)))
		maxTorque = maxTorque + jet
	end
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
	local thrust = max(e.stats.thrust, e.stats.sideThrust * T.sideScale) * T.FORCE_PER_KN * T.thrustScale
	local k = e.hull.drag * T.dragScale
	local aux = e.stats.sideThrust * T.FORCE_PER_KN * T.thrustScale * T.sideScale
	local torque = e.stats.turn * T.TORQUE_PER_TURN * T.turnScale
	local cap = min(T.maxTurnRate, e.hull.turnSpeed and rad(e.hull.turnSpeed) or T.maxTurnRate)
	local turnHelm = e.hull.helm == "turn"
	if turnHelm and aux > 0 then                 -- same as in Ship.fly
		local jet = aux * e.hull.radius
		cap = cap * (1 + min(0.5, 0.5 * jet / max(torque, 1)))
		torque = torque + jet
	end
	return {
		mass = m,
		accel = thrust / m,
		topSpeed = sqrt(thrust / k),
		sideAccel = turnHelm and 0 or aux / m,
		turnAccel = torque / e.body:getInertia(),
		turnSpeed = math.deg(cap),
	}
end

return Ship
