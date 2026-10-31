--[[
	The flight-toy arena: one Box2D world, a flat list of entities (ships
	and asteroids), and lists of projectiles, pickups and effects. Systems
	are just functions that loop over those lists each step.

	This is the "instance" layer from the design doc in miniature: the
	level you're in (a playing field from src/fields.lua), rebuilt fresh
	each time you arrive. What lasts between levels (station storage,
	hangars, where you respawn) is the universe, in src/world.lua, which
	also has travel and save/load.
]]

local data = require("src.data")
local T = require("src.tuning")
local Ship = require("src.ship")
local Weapons = require("src.weapons")
local AI = require("src.ai")
local Camera = require("src.camera")
local events = require("src.events")
local Fields = require("src.fields")
local Hold = require("src.inventory.hold")
local Shapes = require("src.inventory.shapes")

local Game = {}
Game.__index = Game

local sqrt, cos, sin, max, min, floor, pi, random, exp = math.sqrt, math.cos, math.sin, math.max, math.min, math.floor, math.pi, love.math.random, math.exp

function Game.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Game)
	love.physics.setMeter(64)
	self.world = love.physics.newWorld(0, 0, true)
	self.world:setCallbacks(nil, nil, nil, function(...) self:postSolve(...) end)

	self.idCounter = 0
	self.entities = {}
	self.projectiles = {}
	self.pickups = {}
	self.effects = {}
	self.toasts = {}
	self.contacts = {}
	self.time = 0
	self.arenaRadius = 4500
	self.camera = Camera.new()

	self.playerHull = opts.hull or "halcyon_wisp"
	self.playerColor = { 0.55, 0.9, 0.95 }
	self.kills = 0
	self.state = "playing"
	self.stats = { maxImpulse = 0, maxImpactSpeed = 0 }
	self:newUniverse()

	self:loadField(opts.field or Fields.start)
	return self
end

-- Clear the arena and build a level (a playing field, src/fields.lua) in
-- it: its contents, its mass drivers and its enemies. Then the player:
--   opts.player  a ship record to fly in (Ship.record), or a fresh one
--   opts.at      where: { station = key } docked there, { driver = fieldId }
--                coming out of the driver from that planet, { x, y, angle,
--                vx, vy }, or the field's spawn point
function Game:loadField(id, opts)
	opts = opts or {}
	for _, e in ipairs(self.entities) do
		if not e.removed then e.body:destroy(); e.removed = true end
	end
	self.entities, self.projectiles, self.pickups, self.effects, self.contacts = {}, {}, {}, {}, {}
	self.player, self.playerHusk, self.deathX, self.deathY = nil, nil, nil, nil
	self.fieldId = id
	self.field = assert(Fields[id], "unknown field " .. tostring(id))
	self.arenaRadius = self.field.radius or 10000
	self.well, self.lane, self.driverMenu = nil, nil, nil
	if not self.field.transit then self.trip = nil end
	self.stationCount = 0
	self.field.build(self)
	self:spawnDrivers()
	self:spawnFieldEnemies()
	self:placePlayer(opts.player, opts.at)
	self:toast(self.field.name:upper(), 2, nil, true)
end

-- F2: the next playing field.
function Game:nextField()
	local i = 1
	for j, id in ipairs(Fields.list) do if id == self.fieldId then i = j end end
	local p = self.player
	self:loadField(Fields.list[i % #Fields.list + 1], { player = p and not p.dead and Ship.record(p) or nil })
end

function Game:nextId()
	self.idCounter = self.idCounter + 1
	return self.idCounter
end

-- Spawning -------------------------------------------------------------------

-- A new player ship at the field's spawn point. hullId can instead be a
-- ship record (Ship.record) to bring back a parked or saved ship.
function Game:spawnPlayer(hullId, loadout, cargo)
	if self.player and not self.player.removed then self:remove(self.player) end
	local rec = type(hullId) == "table" and hullId or { hull = hullId, loadout = loadout, cargo = cargo }
	if not data.hulls[rec.hull or self.playerHull] then rec = { hull = T.starterHull } end
	self.playerHull = rec.hull or self.playerHull
	if rec.color then self.playerColor = rec.color end
	local sx, sy = self.field.spawn[1], self.field.spawn[2]
	local p = Ship.new(self, { hull = self.playerHull, loadout = rec.loadout, cargo = rec.cargo, hold = rec.hold, armor = rec.armor,
		team = 1, x = sx, y = sy, angle = -pi / 2, color = self.playerColor, grid = true })
	p.isPlayer = true
	table.insert(self.entities, p)
	self.player = p
	self.state = "playing"
	self.camera.x, self.camera.y = sx, sy
	return p
end

-- opts.idle: it minds its own business until the player comes close or
-- shoots it (enemies placed by a level); otherwise it comes straight for
-- the player.
function Game:spawnEnemy(id, x, y, opts)
	local def = assert(data.enemies[id], "unknown enemy " .. tostring(id))
	local angle = 0
	if self.player and not self.player.dead then
		local px, py = self.player.body:getPosition()
		angle = math.atan2(py - y, px - x)
	end
	local e = Ship.new(self, { hull = def.hull, loadout = def.loadout, cargo = def.cargo, team = def.team or 2, x = x, y = y, angle = angle, enemy = def })
	e.aggro = not (opts and opts.idle)
	table.insert(self.entities, e)
	return e
end

-- A drone from a drone bay: a small AI ship on the launcher's side, in the
-- launcher's paint, that fights until its life runs out or it's destroyed.
local DRONE_AI = { style = "orbit", range = 450, accuracy = 0.6, throttle = 0.9, burstOn = 1.2, burstOff = 0.8 }
function Game:launchDrone(owner, item, x, y, angle)
	local shot = item.shot
	local d = Ship.new(self, {
		hull = shot.hull, cargo = shot.cargo, team = owner.team, x = x, y = y, angle = angle,
		color = owner.color, enemy = { id = item.id, ai = DRONE_AI },
	})
	d.drone, d.owner, d.life = true, owner, shot.life
	-- A ship never collides with its own drones (or they with each other):
	-- Box2D skips contacts between fixtures sharing a negative group index.
	-- (Group indexes are 16-bit, so hand them out from a small counter.)
	if not owner.collisionGroup then
		self.groupCounter = (self.groupCounter or 0) % 30000 + 1
		owner.collisionGroup = -self.groupCounter
		for _, f in ipairs(owner.body:getFixtures()) do f:setGroupIndex(owner.collisionGroup) end
	end
	for _, f in ipairs(d.body:getFixtures()) do f:setGroupIndex(owner.collisionGroup) end
	local vx, vy = owner.body:getLinearVelocity()
	d.body:setLinearVelocity(vx + cos(angle) * shot.speed, vy + sin(angle) * shot.speed)
	table.insert(self.entities, d)
	return d
end

-- A point a given distance from the player, kept inside the arena.
function Game:spawnPoint(minD, maxD)
	local cx, cy = 0, 0
	if self.player and not self.player.dead then cx, cy = self.player.body:getPosition() end
	for _ = 1, 20 do
		local a = random() * pi * 2
		local d = minD + random() * (maxD - minD)
		local x, y = cx + cos(a) * d, cy + sin(a) * d
		if x * x + y * y < (self.arenaRadius - 200) ^ 2 and self:isClear(x, y, 150) then return x, y end
	end
	local a = random() * pi * 2
	return cos(a) * (self.arenaRadius - 300), sin(a) * (self.arenaRadius - 300)
end

function Game:spawnAsteroid(x, y, radius)
	local verts = {}
	for j = 0, 7 do
		local ang = j / 8 * pi * 2 + (random() - 0.5) * 0.35
		local rr = radius * (0.82 + 0.18 * random())
		table.insert(verts, cos(ang) * rr)
		table.insert(verts, sin(ang) * rr)
	end
	local body = love.physics.newBody(self.world, x, y, "dynamic")
	local shape
	if love.math.isConvex(verts) then shape = love.physics.newPolygonShape(verts)
	else shape = love.physics.newCircleShape(radius * 0.9); verts = nil end
	local fixture = love.physics.newFixture(body, shape, 1)
	fixture:setRestitution(0.2)
	fixture:setFriction(0.5)
	local m = 0.12 * radius * radius
	body:setMassData(0, 0, m, m * radius * radius * 0.5)
	-- rocks around a planet keep their orbits, so no drag there
	body:setLinearDamping(self.field and self.field.rockDrag or 0.25)
	body:setAngularDamping(0.2)
	body:setAngularVelocity((random() - 0.5) * 0.6)
	body:setLinearVelocity((random() - 0.5) * 20, (random() - 0.5) * 20)
	local e = { kind = "asteroid", id = self:nextId(), team = 0, radius = radius, verts = verts, body = body, fixture = fixture, shade = 0.55 + random() * 0.25,
		hp = radius * radius * T.asteroidToughness }
	fixture:setUserData(e)
	body:setUserData(e)
	table.insert(self.entities, e)
	return e
end

-- Is a circle at (x, y) clear of asteroids and structures (by margin)?
function Game:isClear(x, y, margin)
	for _, o in ipairs(self.entities) do
		local kind = o.kind
		if kind == "asteroid" or kind == "structure" or kind == "planet" or kind == "station" or kind == "ship" then
			local ox, oy = o.body:getPosition()
			ox, oy = ox + (o.cx or 0), oy + (o.cy or 0)
			local r = (kind == "ship") and o.halfLength or o.radius
			if (ox - x) ^ 2 + (oy - y) ^ 2 < (r + margin) ^ 2 then return false end
		end
	end
	return true
end

-- One enormous rock, far too big to damage: a static body built from a
-- fan of triangles around a lumpy outline.
function Game:spawnGiantAsteroid(x, y, radius)
	local n = 28
	local outline = {}
	for j = 0, n - 1 do
		local ang = j / n * pi * 2
		local rr = radius * (0.88 + 0.12 * random())
		table.insert(outline, cos(ang) * rr)
		table.insert(outline, sin(ang) * rr)
	end
	local body = love.physics.newBody(self.world, x, y, "static")
	local e = { kind = "asteroid", giant = true, invulnerable = true, id = self:nextId(), team = 0, radius = radius,
		outline = outline, tris = love.math.triangulate(outline), body = body, shade = 0.6, craters = {} }
	for _ = 1, 9 do
		local a, d = random() * pi * 2, random() * radius * 0.6
		table.insert(e.craters, { cos(a) * d, sin(a) * d, radius * (0.06 + random() * 0.1) })
	end
	for j = 0, n - 1 do
		local k = (j + 1) % n
		local f = love.physics.newFixture(body, love.physics.newPolygonShape(0, 0,
			outline[j * 2 + 1], outline[j * 2 + 2], outline[k * 2 + 1], outline[k * 2 + 2]))
		f:setFriction(0.6)
		f:setRestitution(0.15)
		f:setUserData(e)
	end
	body:setUserData(e)
	table.insert(self.entities, e)
	return e
end

-- A planet: a static, indestructible disc in a turning field. There's no
-- gravity: nothing is pulled in. The field is a current circling the
-- planet (clockwise on screen) at flow px/s at the surface, slowing with
-- distance (as 1/sqrt(r)). swirl is how hard it drags things toward the
-- current's speed (per second). Loose things (rocks, wrecks, loot) are also
-- held in their lane while they circle, so the belt doesn't fling outward.
function Game:spawnPlanet(x, y, radius, flow, swirl)
	local body = love.physics.newBody(self.world, x, y, "static")
	local e = { kind = "planet", invulnerable = true, id = self:nextId(), team = 0, radius = radius, body = body,
		hue = { 0.35 + random() * 0.2, 0.45 + random() * 0.2, 0.7 + random() * 0.2 } }
	local f = love.physics.newFixture(body, love.physics.newCircleShape(radius))
	f:setFriction(0.6)
	f:setRestitution(0.1)
	f:setUserData(e)
	body:setUserData(e)
	table.insert(self.entities, e)
	-- atmo: how deep the atmosphere (the haze drawn round it) reaches
	self.well = { x = x, y = y, radius = radius, flow = flow, swirl = swirl, atmo = 840, planet = e }
	return e
end

-- How fast the field's current runs at distance r from the planet.
function Game:currentSpeed(r)
	local w = self.well
	if not w then return 0 end
	return w.flow * sqrt(w.radius / max(r, w.radius)) * T.currentScale
end

-- Acceleration from the turning field on something at (x, y) moving at
-- (vx, vy): a drag along the tangent toward the current's speed, and, if
-- hold, just enough pull inward to keep whatever it's circling at on a
-- circle (zero for something not moving around the planet).
function Game:currentAt(x, y, vx, vy, hold)
	local w = self.well
	if not w then return 0, 0 end
	local dx, dy = w.x - x, w.y - y
	local r = max(sqrt(dx * dx + dy * dy), 1)
	local nx, ny = dx / r, dy / r
	local tx, ty = ny, -nx                     -- clockwise on screen
	local vt = vx * tx + vy * ty
	local s = (self:currentSpeed(r) - vt) * w.swirl
	local ax, ay = tx * s, ty * s
	if hold then
		local c = vt * vt / r
		ax, ay = ax + nx * c, ay + ny * c
	end
	return ax, ay
end

function Game:applyCurrent(dt)
	if not self.well then return end
	for _, e in ipairs(self.entities) do
		local b = e.body
		if not e.removed and b:getType() == "dynamic" then
			local x, y = b:getPosition()
			local vx, vy = b:getLinearVelocity()
			local ax, ay
			if e.kind == "ship" then
				-- Ships ride the current through their own drag (see
				-- Ship.fly), and are held on the curve as they go round.
				local dx, dy = self.well.x - x, self.well.y - y
				local r = max(sqrt(dx * dx + dy * dy), 1)
				local tx, ty = dy / r, -dx / r
				local f = self:currentSpeed(r)
				e.flowX, e.flowY = tx * f, ty * f
				local vt = vx * tx + vy * ty
				local c = max(0, vt) * max(0, vt) / r
				ax, ay = dx / r * c, dy / r * c
			else
				ax, ay = self:currentAt(x, y, vx, vy, true)
				-- Box2D's damping slows against the world; push back so it
				-- only slows wrecks and containers relative to the current
				-- (otherwise they'd sit still while everything else turns).
				local d = b:getLinearDamping()
				if d > 0 then
					local dx, dy = self.well.x - x, self.well.y - y
					local r = max(sqrt(dx * dx + dy * dy), 1)
					local f = self:currentSpeed(r)
					ax, ay = ax + dy / r * f * d, ay - dx / r * f * d
				end
				if e.orbitR then
					-- steer a newly arrived rock into its lane: a damped
					-- spring on its distance from the planet
					local dx, dy = self.well.x - x, self.well.y - y
					local r = max(sqrt(dx * dx + dy * dy), 1)
					local nx, ny = dx / r, dy / r
					local vr = -(vx * nx + vy * ny)          -- outward speed
					local s = (r - e.orbitR) * 0.004 + vr * 0.13
					ax, ay = ax + nx * s, ay + ny * s
				end
			end
			local m = b:getMass()
			b:applyForce(ax * m, ay * m)
		end
	end
	for _, p in ipairs(self.pickups) do
		local ax, ay = self:currentAt(p.x, p.y, p.vx, p.vy, true)
		p.vx, p.vy = p.vx + ax * dt, p.vy + ay * dt
	end
end

-- Re-entry. Inside the planet's atmosphere things are dragged against the
-- current, sink toward the surface, and heat up with speed: ships take
-- heat damage and glow (e.reentry, 0..1, plus the direction of travel for
-- the flame); rocks just glow. Deeper means thicker. Rocks that drifted
-- back out of a re-entry respawn as usual only if they hit the ground.
local REENTRY_DRAG, REENTRY_SINK, REENTRY_HEAT = 0.7, 70, 6

function Game:updateAtmosphere(dt)
	local w = self.well
	if not w or not w.atmo then return end
	for _, e in ipairs(self.entities) do
		local b = e.body
		e.reentry = nil
		if not e.removed and not e.dockState and b:getType() == "dynamic" and (e.kind == "ship" or e.kind == "asteroid" or e.kind == "husk" or e.kind == "container") then
			local x, y = b:getPosition()
			local dx, dy = w.x - x, w.y - y
			local r = sqrt(dx * dx + dy * dy)
			local depth = 1 - (r - w.radius) / w.atmo
			if depth > 0 and r > 1 then
				depth = min(1, depth)
				local nx, ny = dx / r, dy / r
				-- drag against the air, which moves with the current
				local f = self:currentSpeed(r)
				local vx, vy = b:getLinearVelocity()
				local rvx, rvy = vx - ny * f, vy + nx * f
				local m = b:getMass()
				local k = REENTRY_DRAG * depth
				b:applyForce((-rvx * k + nx * REENTRY_SINK * depth) * m, (-rvy * k + ny * REENTRY_SINK * depth) * m)
				local rs = sqrt(rvx * rvx + rvy * rvy)
				-- the glow builds as soon as you're in, and with speed
				local heat = min(1, depth * 1.6) * (0.45 + 0.55 * min(1, rs / 300))
				if heat > 0.05 then
					-- flame direction: the way it moves through the air, or
					-- straight down for something just sinking in it
					local fx, fy = rvx / max(rs, 1), rvy / max(rs, 1)
					if rs < 60 then fx, fy = nx, ny end
					e.reentry, e.reentryX, e.reentryY = heat, fx, fy
					if e.kind == "ship" then self:damage(e, REENTRY_HEAT * heat * (1 + rs / 300) * dt, nil, "heat") end
				end
			end
		end
	end
end

-- Hitting the planet itself: ships crash, wrecks burn up, and rocks
-- shatter and are replaced by a new one falling in from the edge of the
-- map onto an orbit.
function Game:planetImpacts()
	local w = self.well
	if not w or not w.planet or w.planet.removed then return end
	local hit = {}
	for _, c in ipairs(w.planet.body:getContacts()) do
		if c:isTouching() then
			local fa, fb = c:getFixtures()
			for _, f in ipairs({ fa, fb }) do
				local o = f:getUserData()
				if o and o ~= w.planet and not o.dead and not o.removed then hit[o] = true end
			end
		end
	end
	for o in pairs(hit) do
		local x, y = o.body:getPosition()
		if o.kind == "ship" and not o.dockState then
			self:damage(o, 1e9, nil, "crash")
			if o == self.player then self:toast("CRASHED", 2) end
		elseif o.kind == "asteroid" then
			local radius = o.radius
			self:addEffect({ kind = "explosion", x = x, y = y, r = radius * 1.4, life = 0.5, t = 0, dust = true })
			self:spark(x, y, 10, { 1, 0.6, 0.3 })
			self:remove(o)
			self:spawnInfallingAsteroid(radius)
		elseif o.kind == "husk" or o.kind == "container" then
			self:addEffect({ kind = "explosion", x = x, y = y, r = 120, life = 0.4, t = 0, dust = true })
			self:remove(o)
		end
	end
end

-- A rock arriving from the edge of the map: it comes in moving with the
-- current and is steered into a lane in the belt (e.orbitR, see
-- applyCurrent), where it settles into orbit.
function Game:spawnInfallingAsteroid(radius)
	local w = self.well
	local Rm = self.arenaRadius - 400
	for _ = 1, 20 do
		local a = random() * pi * 2
		local x, y = w.x + cos(a) * Rm, w.y + sin(a) * Rm
		if self:isClear(x, y, radius + 80) then
			local e = self:spawnAsteroid(x, y, radius)
			local f = self:currentSpeed(Rm)
			e.body:setLinearVelocity(-sin(a) * f - cos(a) * 250, cos(a) * f - sin(a) * 250)
			e.orbitR = w.radius + 1500 + random() * 4500
			return e
		end
	end
end

-- A wheel station (the classic 2001 shape): a round ring joined to a
-- central hub by spokes, turning slowly. R is the ring's centre line, tube
-- its thickness. The ring collides as many short pieces, but is drawn as a
-- smooth circle. Indestructible, and kinematic so it turns without being
-- pushed around, unless simulated: then it's a very heavy dynamic body that
-- gravity and collisions act on like anything else.
function Game:spawnWheelStation(x, y, R, tube, spin, simulated)
	local body = love.physics.newBody(self.world, x, y, simulated and "dynamic" or "kinematic")
	body:setAngle(random() * pi * 2)
	body:setAngularVelocity(spin or 0.04)
	local hub = R * 0.2
	-- key: which station this is, for the universe (storage, hangar,
	-- respawn); the same field always builds its stations in the same order
	self.stationCount = (self.stationCount or 0) + 1
	local n = self.stationCount
	local names = self.field and self.field.stations
	local e = { kind = "station", invulnerable = true, id = self:nextId(), team = 0, body = body,
		ringR = R, tube = tube, hub = hub, spokes = 4,
		key = ("%s/%d"):format(self.fieldId or "?", n),
		name = names and names[n] or ((self.field and self.field.name or "") .. " Station " .. n) }
	-- The dock: a square module on the outside of the ring (along the
	-- station's +x axis). x1..x2 is its extent out from the centre, hw its
	-- half-width. Ships that fly into the capture zone in front of its
	-- door are pulled inside (see Game:updateDocking).
	local D = max(300, tube * 2)
	local dock = { x1 = R + tube / 2 - tube * 0.3, x2 = R + tube / 2 + D, hw = D / 2, wall = 24,
		runway = 600, capture = 260 }
	e.dock = dock
	e.radius = dock.x2
	local function add(shape)
		local f = love.physics.newFixture(body, shape)
		f:setFriction(0.5)
		f:setRestitution(0.1)
		f:setUserData(e)
	end
	local ri, ro, n = R - tube / 2, R + tube / 2, 72
	for i = 0, n - 1 do
		local a1, a2 = i / n * pi * 2, (i + 1) / n * pi * 2
		add(love.physics.newPolygonShape(cos(a1) * ri, sin(a1) * ri, cos(a1) * ro, sin(a1) * ro,
			cos(a2) * ro, sin(a2) * ro, cos(a2) * ri, sin(a2) * ri))
	end
	add(love.physics.newCircleShape(hub))
	local sw = tube * 0.22
	for k = 0, e.spokes - 1 do
		local a = k / e.spokes * pi * 2
		local c, s = cos(a), sin(a)
		local px, py = -s * sw, c * sw
		add(love.physics.newPolygonShape(c * hub + px, s * hub + py, c * ri + px, s * ri + py,
			c * ri - px, s * ri - py, c * hub - px, s * hub - py))
	end
	-- the dock module is solid; ships only get inside by being pulled in
	add(love.physics.newPolygonShape(dock.x1, -dock.hw, dock.x2, -dock.hw, dock.x2, dock.hw, dock.x1, dock.hw))
	if simulated then
		-- hundreds of times a battleship's mass, and no drag
		local m = 300000
		body:setMassData(0, 0, m, m * R * R)
		body:setLinearDamping(0)
		body:setAngularDamping(0)
		body:setAngularVelocity(spin or 0.04)
	end
	body:setUserData(e)
	table.insert(self.entities, e)
	return e
end

-- Docking. A ship that flies into the tractor zone along a station's
-- runway lights is caught: its own controls cut out and the beam eases it
-- onto the runway's centre line, matches it to the station's motion,
-- turns its nose to the door and draws it in, gently at first and firmer
-- as it gets close ("tractor"). At the door it stops colliding and slides
-- inside over PULL_TIME ("pull"), and then it's docked ("done"). The
-- player gets the station screen (state "docked") until Game:undock();
-- traders stay a while (ds.stay seconds) and then launch on their own.
local PULL_TIME = 2.2

-- Station-local position of a point, and whether it's in the tractor zone
-- (over the runway, in front of the door).
function Game:inTractorZone(st, x, y)
	local d = st.dock
	if not d then return false end
	local lx, ly = st.body:getLocalPoint(x, y)
	return lx > d.x2 and lx < d.x2 + d.runway and math.abs(ly) < d.hw * 1.3, lx, ly
end

function Game:beginDocking(e, st)
	e.dockState = { station = st, phase = "tractor", t = 0 }
	e.intent.thrust, e.intent.strafe, e.intent.boost = 0, 0, false
	e.intent.firePrimary, e.intent.fireSecondary, e.intent.fireAux = false, false, false
	if e == self.player then self:toast("TRACTOR LOCK", 1.4) end
end

function Game:updateDocking(dt)
	for _, e in ipairs(self.entities) do
		if e.kind == "ship" and not e.dead and not e.dockState then
			e.dockCooldown = max(0, (e.dockCooldown or 0) - dt)
			local trader = e.def and e.def.ai.style == "trader"
			if (e == self.player or trader) and e.dockCooldown == 0 then
				local x, y = e.body:getPosition()
				for _, st in ipairs(self.entities) do
					-- traders only dock where their route says to
					if st.kind == "station" and (not trader or (e.route and e.route[e.routeIndex or 1] == st))
						and self:inTractorZone(st, x, y) then
						self:beginDocking(e, st)
						break
					end
				end
			end
		end
	end
end

local function wrapAngle(a) return (a + pi) % (2 * pi) - pi end

-- One step of a docking ship: tractor it in, pull it inside, or wait.
function Game:updateDockedShip(e, dt)
	local ds = e.dockState
	local st, d = ds.station, ds.station.dock
	local b, sb = e.body, st.body
	ds.t = ds.t + dt

	if ds.phase == "tractor" then
		local x, y = b:getPosition()
		local lx, ly = sb:getLocalPoint(x, y)
		local doorX = d.x2 + e.halfLength + 40
		-- grip grows over the first second and as the ship nears the door
		local near = 1 - max(0, min(1, (lx - doorX) / d.runway))
		local grip = min(1, ds.t / 1.0) * (0.35 + 0.65 * near)
		-- wanted velocity, in the station's frame: onto the centre line and
		-- in toward the door, slowing as it arrives
		local gap = lx - doorX
		local inward = -min(260, gap > 0 and max(50, gap * 0.6) or gap * 0.6)
		local across = -ly * 0.8
		local wx, wy = sb:getWorldVector(inward, across)
		local svx, svy = sb:getLinearVelocityFromWorldPoint(x, y)
		local vx, vy = b:getLinearVelocity()
		local k = 2.2 * grip
		local m = b:getMass()
		b:applyForce((svx + wx - vx) * k * m, (svy + wy - vy) * k * m)
		-- nose toward the door
		local want = sb:getAngle() + pi
		local turn = wrapAngle(want - b:getAngle()) * 1.4 * grip + sb:getAngularVelocity()
		b:setAngularVelocity(b:getAngularVelocity() + (turn - b:getAngularVelocity()) * min(1, 3 * dt))
		if lx <= doorX + 30 and math.abs(ly) < d.hw * 0.4 then
			ds.phase, ds.t = "pull", 0
			ds.lx, ds.ly, ds.la = lx, ly, b:getAngle() - sb:getAngle()
			b:setActive(false)
		end
		return
	end

	if ds.phase == "pull" then
		local f = min(1, ds.t / PULL_TIME)
		f = f * f * (3 - 2 * f)
		local tx = (d.x1 + d.x2) / 2
		local da = wrapAngle(pi - ds.la)
		b:setPosition(sb:getWorldPoint(ds.lx + (tx - ds.lx) * f, ds.ly * (1 - f)))
		b:setAngle(sb:getAngle() + ds.la + da * f)
		b:setLinearVelocity(0, 0)
		b:setAngularVelocity(0)
		if f >= 1 then
			ds.phase, ds.done, ds.t = "done", true, 0
			if e == self.player then
				self.state = "docked"
				self:playerDocked(st)
			else
				ds.stay = 30 + random() * 60
			end
			events.emit("dock", e, st)
		end
		return
	end

	-- docked: ride along inside
	b:setPosition(sb:getWorldPoint((d.x1 + d.x2) / 2, 0))
	if ds.stay and ds.t >= ds.stay then self:undockShip(e) end
end

-- Launch a docked ship back out of the door.
function Game:undockShip(e)
	local ds = e.dockState
	if not ds or not ds.done then return end
	local st, d = ds.station, ds.station.dock
	local sb = st.body
	local wx, wy = sb:getWorldPoint(d.x2 + e.halfLength + 60, 0)
	local ox, oy = sb:getWorldVector(1, 0)
	local svx, svy = sb:getLinearVelocityFromWorldPoint(wx, wy)
	e.body:setPosition(wx, wy)
	e.body:setAngle(sb:getAngle())
	e.body:setActive(true)
	e.body:setLinearVelocity(svx + ox * 260, svy + oy * 260)
	e.body:setAngularVelocity(sb:getAngularVelocity())
	e.dockState = nil
	e.dockCooldown = 4
	if e.route then e.routeIndex = (e.routeIndex or 1) % #e.route + 1 end
	events.emit("undock", e, st)
end

-- The player's launch button on the station screen.
function Game:undock()
	local p = self.player
	if not p or not p.dockState or not p.dockState.done then return end
	local missing = Ship.launchProblem(p)
	if missing then self:toast(("CAN'T LAUNCH: %s"):format(missing:upper()), 1.6) return end
	self:undockShip(p)
	self.state = "playing"
	self:toast("LAUNCHED", 1)
end

-- A navigation buoy: a marker that nothing collides with (it has no
-- fixtures), usually set on a track with setOrbit.
function Game:spawnBuoy(x, y)
	local body = love.physics.newBody(self.world, x, y, "kinematic")
	local e = { kind = "buoy", invulnerable = true, id = self:nextId(), team = 0, body = body, radius = 24, blink = random() }
	body:setUserData(e)
	table.insert(self.entities, e)
	return e
end

-- Put a kinematic body (a station) on a fixed circular track around
-- (cx, cy), moving at speed px/s (positive is clockwise on screen, the way
-- the planet's well turns). Not simulated: it just follows the track.
function Game:setOrbit(e, cx, cy, speed)
	local x, y = e.body:getPosition()
	local r = sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
	e.orbit = { cx = cx, cy = cy, r = r, angle = math.atan2(y - cy, x - cx), rate = speed / r }
end

function Game:updateOrbits(dt)
	for _, e in ipairs(self.entities) do
		local o = e.orbit
		if o and not e.removed then
			o.angle = o.angle + o.rate * dt
			local tx, ty = o.cx + cos(o.angle) * o.r, o.cy + sin(o.angle) * o.r
			local x, y = e.body:getPosition()
			-- velocity that lands it exactly on the track this step
			e.body:setLinearVelocity((tx - x) / dt, (ty - y) / dt)
		end
	end
end

-- A static, indestructible piece of station: one convex polygon (world
-- coordinates, up to 8 points). Each piece is its own entity, so the AI
-- steers around pieces rather than the whole station.
function Game:addStructure(verts, opts)
	local cx, cy = 0, 0
	local n = #verts / 2
	for i = 1, #verts, 2 do cx, cy = cx + verts[i] / n, cy + verts[i + 1] / n end
	local r = 0
	for i = 1, #verts, 2 do r = max(r, sqrt((verts[i] - cx) ^ 2 + (verts[i + 1] - cy) ^ 2)) end
	local body = love.physics.newBody(self.world, 0, 0, "static")
	local e = { kind = "structure", invulnerable = true, id = self:nextId(), team = 0, verts = verts,
		cx = cx, cy = cy, radius = r, role = opts and opts.role, body = body, blink = random() * 10 }
	local f = love.physics.newFixture(body, love.physics.newPolygonShape(verts))
	f:setFriction(0.5)
	f:setRestitution(0.1)
	f:setUserData(e)
	body:setUserData(e)
	table.insert(self.entities, e)
	return e
end

-- Scatter n breakable asteroids, no closer than minD to the centre.
function Game:spawnAsteroids(n, minD)
	minD = minD or 450
	local placed = 0
	for _ = 1, n * 10 do
		if placed >= n then break end
		local radius = 28 + random() ^ 2 * 100
		local a = random() * pi * 2
		local d = minD + random() * (self.arenaRadius - minD - 150)
		local x, y = cos(a) * d, sin(a) * d
		if self:isClear(x, y, radius + 60) then self:spawnAsteroid(x, y, radius); placed = placed + 1 end
	end
end

-- inner: what a loaded container carries (its hold).
function Game:spawnPickup(x, y, item, count, inner)
	if data.items[item].kind == "container" then          -- a stowed container floats out as itself
		for _ = 1, count do self:spawnContainer(x + (random() - 0.5) * 40, y + (random() - 0.5) * 40, item, false, inner) end
		return
	end
	local a = random() * pi * 2
	local s = 40 + random() * 120
	table.insert(self.pickups, {
		x = x, y = y, vx = cos(a) * s, vy = sin(a) * s,
		item = item, count = count, spin = random() * pi * 2,
	})
end

-- Push something out of the player's hold: it floats out behind the ship
-- as an ordinary pickup (the tractor beam can reel it back in).
function Game:eject(e, id, count, inner)
	local x, y = e.body:getPosition()
	local a = e.body:getAngle()
	local vx, vy = e.body:getLinearVelocity()
	local c, s = cos(a), sin(a)
	local back = e.tailX - 24
	local side = (random() - 0.5) * e.hull.radius
	if data.items[id].kind == "container" then
		local back2 = e.tailX - 40
		for _ = 1, count do
			local box = self:spawnContainer(x + c * back2 - s * side, y + s * back2 + c * side, id, false, inner)
			box.body:setLinearVelocity(vx - c * 60, vy - s * 60)
		end
		self:toast(("-%d %s"):format(count, data.items[id].name), 1.2, "pickup")
		events.emit("eject", e, id, count)
		return
	end
	table.insert(self.pickups, {
		x = x + c * back - s * side, y = y + s * back + c * side,
		vx = vx - c * 90 + (random() - 0.5) * 30, vy = vy - s * 90 + (random() - 0.5) * 30,
		item = id, count = count, spin = random() * pi * 2,
	})
	self:toast(("-%d %s"):format(count, data.items[id].name), 1.2, "pickup")
	events.emit("eject", e, id, count)
end

-- A cargo container floating in space: a box with a grid hold of its own.
-- loaded fills it from the item's fill table; inner is a hold it already
-- carries (one that was stowed or packed into a wreck). Like a husk it
-- soaks damage until it breaks, and then spills what it held.
function Game:spawnContainer(x, y, id, loaded, inner)
	id = id or "cargo_container"
	local item = data.items[id]
	local w, h = item.body[1], item.body[2]
	local body = love.physics.newBody(self.world, x, y, "dynamic")
	local hold = inner or Hold.new({ { key = "main", name = item.name, w = item.grid[1], h = item.grid[2] } })
	local e = {
		kind = "container", id = self:nextId(), team = 0, item = id, body = body, hold = hold,
		w = w, h = h, radius = sqrt(w * w + h * h) / 2, halfLength = w / 2, hp = item.hp,
	}
	if loaded then
		local counts = {}
		for _, f in ipairs(item.fill) do
			if random() < (f[4] or 1) then counts[f[1]] = (counts[f[1]] or 0) + random(f[2], f[3]) end
		end
		Hold.fill(hold, counts, { random = random })
	end
	e.loot = Hold.totals(hold)
	local f = love.physics.newFixture(body, love.physics.newRectangleShape(w, h), 1)
	f:setRestitution(0.2)
	f:setFriction(0.5)
	f:setUserData(e)
	body:setUserData(e)
	body:setAngle(random() * pi * 2)
	body:setAngularVelocity((random() - 0.5) * 0.5)
	body:setLinearDamping(0.1)
	body:setAngularDamping(0.2)
	self:containerMass(e)
	table.insert(self.entities, e)
	return e
end

-- A container weighs its own mass plus what's in it.
function Game:containerMass(e)
	local m = data.items[e.item].mass
	for id, n in pairs(e.loot) do m = m + data.items[id].mass * n end
	m = m * T.massScale
	e.body:setMassData(0, 0, m, m * (e.w * e.w + e.h * e.h) / 12)
	e.massDirty = nil
end

-- A few loaded containers drifting loose somewhere in the field.
function Game:spawnContainers(n, minD)
	minD = minD or 600
	for _ = 1, n * 10 do
		if n <= 0 then break end
		local a = random() * pi * 2
		local d = minD + random() * (self.arenaRadius - minD - 300)
		local x, y = cos(a) * d, sin(a) * d
		if self:isClear(x, y, 80) then self:spawnContainer(x, y, nil, true); n = n - 1 end
	end
end

-- Looting: while a wreck or container is open in the cargo screen
-- (game.looting, set by the cargo screen), the tractor beam tries to keep
-- it in reach. It matches your velocity and, past lootHoldAt of the beam's
-- range, closes back in; the pull has a limit (lootHoldAccel), so a heavy
-- burn can still leave it behind and close the window.
function Game:updateLootHold(dt)
	local p, e = self.player, self.looting
	if not e or e.removed or e.dead or not p or p.dead or p.dockState then return end
	local px, py = p.body:getPosition()
	local ex, ey = e.body:getPosition()
	local dx, dy = px - ex, py - ey
	local d = max(sqrt(dx * dx + dy * dy), 1)
	local edge = Ship.distanceTo(p, ex, ey) - e.radius
	local want = max(0, edge - Ship.tractorRange(p) * T.lootHoldAt) * 2
	local pvx, pvy = p.body:getLinearVelocity()
	local evx, evy = e.body:getLinearVelocity()
	local ax, ay = (pvx + dx / d * want - evx) * 4, (pvy + dy / d * want - evy) * 4
	local a = sqrt(ax * ax + ay * ay)
	if a > T.lootHoldAccel then ax, ay = ax / a * T.lootHoldAccel, ay / a * T.lootHoldAccel end
	local m = e.body:getMass()
	e.body:applyForce(ax * m, ay * m)
end

-- Towing: a line from the player's ship to the container it holds with
-- the tractor beam. Slack up to towLength from the hull; past that it
-- pulls both ways (so a full container drags on you), and the ship can't
-- go faster than towSpeed. A container your hold has room for is reeled
-- in and stowed instead, cargo and all.
function Game:updateTow(dt)
	for _, e in ipairs(self.entities) do
		if e.kind == "container" and e.massDirty then self:containerMass(e) end
	end
	local p = self.player
	local c = p and not p.dead and p.towTarget
	if not c then return end
	if c.removed or c.dead or p.dockState then p.towTarget = nil return end
	local px, py = p.body:getPosition()
	local cx, cy = c.body:getPosition()
	local dx, dy = px - cx, py - cy
	local d = max(sqrt(dx * dx + dy * dy), 1)
	local nx, ny = dx / d, dy / d
	local edge = Ship.distanceTo(p, cx, cy) - c.radius
	if edge > Ship.tractorRange(p) * 1.3 then
		p.towTarget = nil
		self:toast("TOW LOST", 1.2)
		return
	end
	local pvx, pvy = p.body:getLinearVelocity()
	local cvx, cvy = c.body:getLinearVelocity()
	if c.stow then
		-- reel it in like a pickup
		local want = min(300, d * 3)
		local blend = min(1, dt * 6)
		c.body:setLinearVelocity(cvx + (pvx + nx * want - cvx) * blend, cvy + (pvy + ny * want - cvy) * blend)
		if edge < 10 then
			if Ship.stowContainer(p, c) then
				self:toast("+1 " .. data.items[c.item].name, 1.4, "pickup")
				events.emit("pickup", p, c.item, 1)
				self:remove(c)
			end
			p.towTarget = nil
		end
		return
	end
	local slack = T.towLength
	if edge > slack then
		local closing = (pvx - cvx) * nx + (pvy - cvy) * ny   -- how fast the ship pulls away
		local mc, mp = c.body:getMass(), p.body:getMass()
		local mu = mc * mp / (mc + mp)
		local f = (T.towStiffness * (edge - slack) + T.towDamping * max(0, closing)) * mu
		c.body:applyForce(nx * f, ny * f)
		p.body:applyForce(-nx * f, -ny * f)
	end
	local sp = sqrt(pvx * pvx + pvy * pvy)
	if sp > T.towSpeed then
		local k = (sp - T.towSpeed) * p.body:getMass() * 30
		p.body:applyForce(-pvx / sp * k, -pvy / sp * k)
	end
end

-- Each station keeps its own storage: a big grid you can leave cargo in
-- while docked there. It lives in the universe, so it's still there when
-- you come back to the level (and in the save).
function Game:stationStorage(st)
	return self:stationRecord(st).storage
end

function Game:enemyCount()
	local n = 0
	for _, e in ipairs(self.entities) do
		if e.kind == "ship" and e.team == 2 and not e.dead and not e.fleeing then n = n + 1 end
	end
	return n
end

-- Simulation -----------------------------------------------------------------

function Game:setPlayerIntent(intent)
	local p = self.player
	if not p or p.dead or p.dockState or p.launch then return end
	for k, v in pairs(intent) do p.intent[k] = v end
end

function Game:step(dt)
	if self.flight then self:updateFlight(dt) return end
	self.time = self.time + dt
	if self.universe then self.universe.clock = self.universe.clock + dt end

	for _, e in ipairs(self.entities) do
		if e.kind == "ship" and not e.dead then
			if e.life then
				e.life = e.life - dt
				if e.life <= 0 then e.dead = true end
			end
			if e.dockState then
				self:updateDockedShip(e, dt)
			else
				if e.cruise then self:cruise(e) elseif e.def then AI.think(self, e, dt) end
				Ship.fly(e, dt)
				Weapons.update(self, e, dt)
			end
		end
	end

	self:applyBoundary()
	self:applyCurrent(dt)
	self:updateLane(dt)
	self:updateAtmosphere(dt)
	self:updateCrush(dt)
	self:updateDrivers(dt)
	self:updateCatch(dt)
	self:updateOrbits(dt)
	self:updateTow(dt)
	self:updateLootHold(dt)
	self.world:update(dt)
	self:planetImpacts()
	self:updateDocking(dt)
	self:resolveContacts()
	Weapons.updateProjectiles(self, dt)
	self:updatePickups(dt)
	self:reap()
	if self.pendingFlight then
		local to = self.pendingFlight
		self.pendingFlight = nil
		self:beginFlight(to)
	elseif self.pendingArrive then
		self.pendingArrive = nil
		self:arrive()
	end
end

-- Soft arena edge: the further past it, the harder you're pushed back.
function Game:applyBoundary()
	local R = self.arenaRadius
	for _, e in ipairs(self.entities) do
		local b = e.body
		local x, y = b:getPosition()
		local d = sqrt(x * x + y * y)
		if d > R and not e.fleeing and not e.catching then
			local over = d - R
			local f = over * b:getMass() * 6
			b:applyForce(-x / d * f, -y / d * f)
		end
	end
end

-- Box2D reports collision impulses after it resolves them; we sum them per
-- pair of entities and turn anything over the threshold into ram damage.
function Game:postSolve(fa, fb, contact, n1, t1, n2, t2)
	local a, b = fa:getUserData(), fb:getUserData()
	if not a or not b then return end
	local key = a.id < b.id and (a.id * 1000003 + b.id) or (b.id * 1000003 + a.id)
	local c = self.contacts[key]
	if not c then
		c = { a = a, b = b, imp = 0 }
		self.contacts[key] = c
		c.x, c.y = contact:getPositions()
	end
	c.imp = c.imp + (n1 or 0) + (n2 or 0)
end

function Game:resolveContacts()
	for key, c in pairs(self.contacts) do
		-- (skip anything removed this step, e.g. a rock that hit a planet)
		if c.a.removed or c.b.removed then
			self.contacts[key] = nil
		else
		-- Impulse / reduced mass is roughly the impact speed. Slow bumps and
		-- scrapes (below the hull's ramSpeed) do nothing; harder hits scale with impulse,
		-- so heavy ships hit harder.
		local ma, mb = c.a.body:getMass(), c.b.body:getMass()
		-- Against something immovable (a station, the giant asteroid) the
		-- reduced mass is just the moving body's own.
		local mu = (ma == 0 or mb == 0) and max(ma, mb) or ma * mb / (ma + mb)
		local impactSpeed = c.imp / max(mu, 1e-6)
		if impactSpeed > self.stats.maxImpactSpeed then self.stats.maxImpactSpeed = impactSpeed end
		if c.imp > self.stats.maxImpulse then self.stats.maxImpulse = c.imp end
		-- Each side has its own toughness: a hull's ramSpeed (light hulls
		-- crumple at a nudge, battleships shrug off bumps), T.ramSpeed for
		-- everything else, all scaled by the debug slider.
		local function threshold(o)
			return (o.kind == "ship" and o.hull.ramSpeed or T.ramSpeed) * T.ramSpeedScale
		end
		local ta, tb = threshold(c.a), threshold(c.b)
		if impactSpeed > min(ta, tb) and c.x then
			local function ramMult(o) return o.kind == "ship" and o.stats.mult.ramDamage or 1 end
			local function hit(o, other, thr)
				if impactSpeed <= thr then return 0 end
				local base = c.imp * T.ramDamageScale * (1 - thr / impactSpeed)
				local mult = (o.kind == "asteroid" or o.kind == "husk" or o.kind == "container") and T.asteroidImpact or ramMult(other)
				self:damage(o, base * mult, other, "ram")
				return base
			end
			local base = max(hit(c.a, c.b, ta), hit(c.b, c.a, tb))
			self:spark(c.x, c.y, min(14, 3 + floor(base / 4)), { 1, 0.9, 0.7 })
			if c.a == self.player or c.b == self.player then self:shake(min(0.5, base / 40)) end
			events.emit("ram", c.a, c.b, base)
		end
		self.contacts[key] = nil
		end
	end
end

-- Closest thing hit along a segment, ignoring one team.
function Game:raycast(x1, y1, x2, y2, ignoreTeam)
	if x1 == x2 and y1 == y2 then return nil end
	local best
	self.world:rayCast(x1, y1, x2, y2, function(fixture, x, y, xn, yn, fraction)
		local e = fixture:getUserData()
		if not e or e.dead or e.team == ignoreTeam then return -1 end
		best = { entity = e, x = x, y = y, nx = xn, ny = yn, fraction = fraction }
		return fraction
	end)
	return best
end

-- cause: gun, artillery, laser, missile, splash or ram (passed on to listeners)
function Game:damage(e, amount, source, cause)
	-- Asteroids, husks and containers don't flinch: they soak damage until they break
	-- apart (in reap).
	if e and (e.invulnerable or e.dockState) then return end
	if e and (e.kind == "asteroid" or e.kind == "husk" or e.kind == "container") and not e.dead and amount > 0 then
		e.hp = e.hp - amount
		if e.hp <= 0 then e.dead = true end
		return
	end
	if not e or e.kind ~= "ship" or e.dead or amount <= 0 then return end
	if source and source.def then amount = amount * T.enemyDamage end   -- difficulty knob
	e.flash = 0.08
	if e.isPlayer and T.dev.god then return end
	e.armor = e.armor - amount
	e.lastHitBy = source
	-- a neutral that gets shot remembers who did it, and shoots back
	if e.team == 3 and source and source.kind == "ship" and source.team ~= 3 then e.aggressor = source end
	e.lastHitTime = self.time
	if e.isPlayer then self:shake(min(0.35, amount / 50)) end
	events.emit("hit", e, amount, source, cause)
	if e.armor <= 0 then
		e.armor = 0
		e.dead = true
	end
end

-- Splash damage and a radial shove. Ships don't take splash from their own side.
function Game:explode(x, y, radius, damage, knockback, owner, direct, cause)
	radius = radius or 40
	local seen = {}
	self.world:queryBoundingBox(x - radius - 40, y - radius - 40, x + radius + 40, y + radius + 40, function(fixture)
		local e = fixture:getUserData()
		if e and not seen[e] and not e.dead then
			seen[e] = true
			local ex, ey = e.body:getPosition()
			local dx, dy = ex - x, ey - y
			local d = sqrt(dx * dx + dy * dy)
			local edge = (e.kind == "ship") and Ship.distanceTo(e, x, y) or (d - e.radius)
			local fall = 1 - max(0, min(1, edge / radius))
			if e == direct then fall = 1 end
			if fall > 0 then
				if not (owner and e.team == owner.team) then self:damage(e, damage * fall, owner, cause or "splash") end
				if d > 1 and e.kind == "ship" then
					local k = knockback * fall
					e.body:applyLinearImpulse(dx / d * k, dy / d * k)
				end
			end
		end
		return true
	end)
	self:addEffect({ kind = "explosion", x = x, y = y, r = radius, life = 0.45, t = 0 })
	self:spark(x, y, 10 + floor(radius / 8), { 1, 0.7, 0.35 })
	if self.player and not self.player.dead then
		local px, py = self.player.body:getPosition()
		local d = sqrt((px - x) ^ 2 + (py - y) ^ 2)
		self:shake(max(0, 0.35 - d / 2500) * radius / 60)
	end
end

-- Pickups float where they were dropped until someone takes them; nothing
-- is collected by flying over it. Holding the tractor beam key with the
-- cursor on a pickup within tractor range locks onto it and reels it in;
-- it goes into the hold when it reaches the hull.
--
-- With the cursor on a husk or a container in range instead, a tap of the
-- key opens it (game.openLoot, which the cargo screen picks up), and
-- holding it on a container tows it (updateTow).
function Game:updatePickups(dt)
	local p = self.player
	local alive = p and not p.dead and not p.dockState
	local list = self.pickups
	self.hoverPickup, self.hoverLoot = nil, nil

	if alive then
		local range = Ship.tractorRange(p)
		local it = p.intent
		-- What's under the cursor (a little slack, wider when zoomed out).
		local grab = 28 / self.camera.zoom
		local best, bestD = nil, grab * grab
		for _, k in ipairs(list) do
			local d = (k.x - it.aimX) ^ 2 + (k.y - it.aimY) ^ 2
			if d < bestD and Ship.distanceTo(p, k.x, k.y) < range then best, bestD = k, d end
		end
		self.hoverPickup = best
		if not best then
			local lootD = math.huge
			for _, e in ipairs(self.entities) do
				if (e.kind == "husk" or e.kind == "container") and not e.dead then
					local ex, ey = e.body:getPosition()
					local d = sqrt((ex - it.aimX) ^ 2 + (ey - it.aimY) ^ 2)
					if d < e.radius + grab and d < lootD and Ship.distanceTo(p, ex, ey) - e.radius < range then
						self.hoverLoot, lootD = e, d
					end
				end
			end
		end
		if not it.tractor then
			p.tractorTarget = nil
		elseif not p.tractorTarget and not p.towTarget then
			p.tractorTarget = best
		end

		-- Tap to open, hold to tow.
		local pressed, released = it.tractor and not p.tractorHeld, p.tractorHeld and not it.tractor
		p.tractorHeld = it.tractor
		if pressed then p.tractorPress = { t = self.time, loot = (not best) and self.hoverLoot or nil } end
		local press = p.tractorPress
		local e = press and press.loot
		if e and (e.removed or e.dead) then
			p.tractorPress, e = nil, nil
		end
		if e then
			local held = self.time - press.t
			if it.tractor and held >= T.tapTime and e.kind == "container" and p.towTarget ~= e then
				p.towTarget = e
				e.stow = Ship.canFit(p, e.item, 1) >= 1
				if not e.stow then self:toast("TOO BIG FOR YOUR HOLD: TOWING", 1.4) end
			elseif released and (held < T.tapTime or e.kind == "husk") then
				self.openLoot = e
			end
		end
		if released then p.tractorPress, p.towTarget = nil, nil end
	end

	local target = alive and p.tractorTarget
	local i = 1
	while i <= #list do
		local k = list[i]
		k.spin = k.spin + dt * 1.5
		-- slow down relative to the current (around a planet they drift
		-- with it like everything else)
		local damp = exp(-dt * 1.5)
		local fx, fy = 0, 0
		if self.well then
			local dx, dy = self.well.x - k.x, self.well.y - k.y
			local r = max(sqrt(dx * dx + dy * dy), 1)
			local f = self:currentSpeed(r)
			fx, fy = dy / r * f, -dx / r * f
		end
		k.vx, k.vy = fx + (k.vx - fx) * damp, fy + (k.vy - fy) * damp
		local remove = false
		if k == target then
			local px, py = p.body:getPosition()
			local pvx, pvy = p.body:getLinearVelocity()
			local dx, dy = px - k.x, py - k.y
			local d = max(sqrt(dx * dx + dy * dy), 1)
			-- Reel in: steer toward the ship, matching its velocity.
			local want = min(600, d * 4)
			local tvx, tvy = pvx + dx / d * want, pvy + dy / d * want
			local blend = min(1, dt * 8)
			k.vx, k.vy = k.vx + (tvx - k.vx) * blend, k.vy + (tvy - k.vy) * blend
			local edge = Ship.distanceTo(p, k.x, k.y)
			if edge < 12 then
				local item = data.items[k.item]
				local got = Ship.addCargo(p, k.item, k.count)
				if got > 0 then
					k.count = k.count - got
					self:toast(("+%d %s"):format(got, item.name), 1.4, "pickup")
					events.emit("pickup", p, k.item, got)
				end
				if k.count <= 0 then
					remove = true
				else
					self:toast("HOLD FULL", 1.2)
					k.vx, k.vy = -dx / d * 160 + pvx, -dy / d * 160 + pvy
				end
				p.tractorTarget = nil
			elseif edge > Ship.tractorRange(p) * 1.3 then
				p.tractorTarget = nil
			end
		end
		k.x, k.y = k.x + k.vx * dt, k.y + k.vy * dt
		if remove then
			list[i] = list[#list]; list[#list] = nil
		else
			i = i + 1
		end
	end
end

-- An asteroid that took too much damage splits into two to four smaller
-- rocks flying apart; pieces too small to matter just crumble to dust.
function Game:breakAsteroid(e)
	local x, y = e.body:getPosition()
	local vx, vy = e.body:getLinearVelocity()
	local n = random(2, 4)
	local spin = random() * pi * 2
	for k = 1, n do
		local r = e.radius * sqrt(1 / n) * (0.75 + random() * 0.25)
		if r >= 14 then
			local a = spin + k / n * pi * 2 + (random() - 0.5) * 0.6
			local rock = self:spawnAsteroid(x + cos(a) * e.radius * 0.45, y + sin(a) * e.radius * 0.45, r)
			local s = 40 + random() * 90
			rock.body:setLinearVelocity(vx + cos(a) * s, vy + sin(a) * s)
		end
	end
	self:spark(x, y, 8 + floor(e.radius / 4), { 0.65, 0.65, 0.7 })
	self:addEffect({ kind = "explosion", x = x, y = y, r = e.radius * 0.8, life = 0.3, t = 0, dust = true })
end

-- Remove the dead. Ships explode and (unless they're drones) leave a husk
-- holding everything they carried; a destroyed husk bursts into pickups.
-- Broken asteroids split apart.
function Game:reap()
	local i = 1
	while i <= #self.entities do
		local e = self.entities[i]
		if e.dead and e.kind == "asteroid" then
			table.remove(self.entities, i)
			self:breakAsteroid(e)          -- reads the body, so before destroying it
			e.body:destroy()
			e.removed = true
		elseif e.fleeing and not e.dead and e.body:getX() ^ 2 + e.body:getY() ^ 2 > (self.arenaRadius + 600) ^ 2 then
			-- A fleeing enemy that made it well past the edge is gone for good.
			table.remove(self.entities, i)
			e.body:destroy()
			e.removed = true
			self:toast(((e.def.name or "ENEMY") .. " escaped"):upper(), 1.5)
		elseif e.dead and (e.kind == "husk" or e.kind == "container") then
			table.remove(self.entities, i)
			local x, y = e.body:getPosition()
			e.body:destroy()
			e.removed = true
			self:explode(x, y, e.halfLength, 0, 0)
			self:spark(x, y, 16, { 0.8, 0.7, 0.6 })
			-- one pickup per stack, so a burst husk scatters what it held
			for _, g in ipairs(e.hold.grids) do
				for _, st in ipairs(g.stacks) do self:spawnPickup(x, y, st.id, st.n, st.inner) end
			end
		elseif e.dead then
			local x, y = e.body:getPosition()
			local a = e.body:getAngle()
			local vx, vy = e.body:getLinearVelocity()
			local w = e.body:getAngularVelocity()
			self:explode(x, y, e.halfLength * 1.6, 0, 3000)
			self:spark(x, y, 24, { 1, 0.6, 0.3 })
			if e.def and not e.drone then self.kills = self.kills + 1 end
			events.emit("kill", e, e.lastHitBy)
			if e.isPlayer then
				self.state = "dead"
				self.deathTime = self.time
				self.deathX, self.deathY = x, y
				self:shake(1)
				events.emit("death", e)
			end
			e.body:destroy()
			e.removed = true
			table.remove(self.entities, i)
			if not e.drone then
				local husk = self:spawnHusk(e, x, y, a, vx, vy, w)
				if e.isPlayer then self.playerHusk = husk end
			end
		else
			i = i + 1
		end
	end
end

-- What a dead ship leaves behind: its whole hold (nothing is lost), the
-- modules that survived, and the salvage its enemy definition rolls.
local function lootOf(e)
	local loot = {}
	for id, count in pairs(e.cargo) do
		local item = data.items[id]
		-- Loose ammo is boxed up: crates are cargo to sell or use back at a
		-- station, not something the guns can draw from mid-fight.
		local into = (item and item.kind == "ammo") and item.crate or id
		if count > 0 then loot[into] = (loot[into] or 0) + count end
	end
	-- Fitted modules: each one has a T.moduleSalvage chance of surviving.
	for i in ipairs(e.hull.slots) do
		local id = e.loadout[i]
		if id and data.items[id] and random() < T.moduleSalvage then loot[id] = (loot[id] or 0) + 1 end
	end
	local s = e.def and e.def.salvage or { 0, 0 }
	for _ = 1, random(s[1], s[2]) do
		local id = random() < 0.2 and "salvage_kit" or "scrap"
		loot[id] = (loot[id] or 0) + 1
	end
	return loot
end

-- A ship that carries its cargo in containers (enemy containers =
-- { item, min, max }, like a Hauler) packs its loot into them: at least
-- min, more as needed up to max, and anything left over stays loose.
local function intoContainers(ship, loot)
	local cs = ship.def and ship.def.containers
	if not cs then return loot, {} end
	local item = data.items[cs[1]]
	local stacks = {}
	for k = 1, cs[3] do
		if k > cs[2] and not next(loot) then break end
		local inner = Hold.new({ { key = "main", name = item.name, w = item.grid[1], h = item.grid[2] } })
		loot = Hold.fill(inner, loot)
		table.insert(stacks, { id = cs[1], n = 1, inner = next(Hold.totals(inner)) and inner or nil })
	end
	return loot, stacks
end

-- A husk's hold: one grid the size of the ship's main hold, loosely packed
-- (it's wreckage), growing if it has to so nothing is lost.
local function huskHold(ship)
	local gw, gh
	if ship.hold then
		gw, gh = ship.hold.grids[1].w, ship.hold.grids[1].h
	else
		gw, gh = Shapes.gridFor(ship.stats.hold)
	end
	local loose, stacks = intoContainers(ship, lootOf(ship))
	return Hold.pack(loose, gw, gh, ship.hull.name .. " husk", random, stacks)
end

-- A burnt-out wreck in the dead ship's shape. It drifts and tumbles, holds
-- the ship's loot in a grid hold (to be opened with the tractor beam once
-- the loot window exists), and can be shot apart, which spills the loot as
-- pickups.
function Game:spawnHusk(ship, x, y, a, vx, vy, w)
	local hull = ship.hull
	local body = love.physics.newBody(self.world, x, y, "dynamic")
	local hold = huskHold(ship)
	local h = {
		kind = "husk", id = self:nextId(), team = 0, hull = hull, color = ship.color,
		spine = ship.spine, noseX = ship.noseX, tailX = ship.tailX, halfLength = ship.halfLength,
		radius = ship.halfLength, body = body, hold = hold, loot = Hold.totals(hold),
		hp = ship.stats.armor * T.huskToughness, flicker = random() * 10,
	}
	local s1, s2, r = ship.spine[1], ship.spine[2], hull.radius
	local n = math.ceil((s2 - s1) / r) + 1
	for k = 0, n - 1 do
		local cx = (n > 1) and (s1 + (s2 - s1) * k / (n - 1)) or s1
		local f = love.physics.newFixture(body, love.physics.newCircleShape(cx, 0, r), 1)
		f:setRestitution(0.2)
		f:setFriction(0.5)
		f:setUserData(h)
	end
	local m = ship.stats.mass * T.massScale * 0.7
	body:setMassData(0, 0, m, m * r * r * 0.5)
	body:setAngle(a)
	body:setLinearVelocity(vx * 0.6, vy * 0.6)
	body:setAngularVelocity(w * 0.5 + (random() - 0.5) * 0.8)
	body:setLinearDamping(0.15)
	body:setAngularDamping(0.1)
	body:setUserData(h)
	table.insert(self.entities, h)
	return h
end

function Game:remove(e)
	for i, o in ipairs(self.entities) do
		if o == e then table.remove(self.entities, i); break end
	end
	if not e.removed then e.body:destroy() end
	e.removed = true
end

function Game:clearEnemies()
	for i = #self.entities, 1, -1 do
		local e = self.entities[i]
		if e.kind == "ship" and e.team == 2 then self:remove(e) end
	end
	self.projectiles = {}
end

-- Visual effects (don't affect the simulation) -------------------------------

function Game:addEffect(fx)
	table.insert(self.effects, fx)
end

function Game:spark(x, y, n, color)
	for _ = 1, n do
		local a = random() * pi * 2
		local s = 60 + random() * 260
		self:addEffect({ kind = "spark", x = x, y = y, vx = cos(a) * s, vy = sin(a) * s, life = 0.2 + random() * 0.35, t = 0, color = color })
	end
end

function Game:muzzle(x, y, angle, size)
	self:addEffect({ kind = "muzzle", x = x, y = y, a = angle, size = size, life = 0.06, t = 0 })
end

function Game:shake(amount)
	self.camera:shake(amount)
end

-- Q: switch the player's auxiliary launcher to the next size it can fire.
function Game:cycleAux()
	local p = self.player
	if not p or p.dead then return end
	local id = Weapons.cycleAmmo(p, "auxiliary")
	if id then self:toast("AUX: " .. data.items[id].name:upper(), 1.2) end
end

-- big: a headline (arriving in a level)
function Game:toast(text, duration, style, big)
	for _, t in ipairs(self.toasts) do
		if t.text == text then t.t = 0; t.life = duration or 1.5; return end
	end
	table.insert(self.toasts, { text = text, t = 0, life = duration or 1.5, style = style, big = big })
	if #self.toasts > 5 then table.remove(self.toasts, 1) end
end

-- Per-frame update for things that aren't simulation: effects, camera, toasts.
function Game:frame(dt, aimX, aimY)
	local i = 1
	while i <= #self.effects do
		local fx = self.effects[i]
		fx.t = fx.t + dt
		if fx.vx then
			fx.x, fx.y = fx.x + fx.vx * dt, fx.y + fx.vy * dt
			local damp = exp(-dt * 3)
			fx.vx, fx.vy = fx.vx * damp, fx.vy * damp
		end
		if fx.t >= fx.life then
			self.effects[i] = self.effects[#self.effects]; self.effects[#self.effects] = nil
		else
			i = i + 1
		end
	end
	for j = #self.toasts, 1, -1 do
		local t = self.toasts[j]
		t.t = t.t + dt
		if t.t >= t.life then table.remove(self.toasts, j) end
	end

	local p = self.player
	if p and not p.dead then
		local x, y = p.body:getPosition()
		if p.catching then
			-- coming in hot: look down the line at the rings ahead
			local vx, vy = p.body:getLinearVelocity()
			x, y = x + vx * 0.25, y + vy * 0.25
			self.camera:follow(x, y, x, y, dt)
		else
			self.camera:follow(x, y, aimX or x, aimY or y, dt)
		end
	elseif self.playerHusk and not self.playerHusk.removed then
		-- Death screen: watch your own wreck drift.
		local hx, hy = self.playerHusk.body:getPosition()
		self.camera:follow(hx, hy, hx, hy, dt)
	elseif self.deathX then
		self.camera:follow(self.deathX, self.deathY, self.deathX, self.deathY, dt)
	end
end

require("src.world")(Game)
require("src.transit")(Game)
require("src.market")(Game)

return Game
