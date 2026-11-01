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
local HullShape = require("src.hullshape")
local Stations = require("src.stations")
local Weapons = require("src.weapons")
local AI = require("src.ai")
local Camera = require("src.camera")
local events = require("src.events")
local Fields = require("src.fields")
local Hold = require("src.inventory.hold")
local Grid = require("src.inventory.grid")
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
	for _, e in ipairs(self.sleepers or {}) do
		if not e.removed then e.body:destroy(); e.removed = true end
	end
	self.sleepers, self.sleepTick = {}, T.sleepEvery   -- first step sorts them
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
	self:spawnMoonGates()
	self:spawnFieldEnemies()
	self:placePlayer(opts.player, opts.at)
	-- the new level's name replaces any still showing (the game builds
	-- Earth before loading the save, which flashed EARTH wherever you were)
	for i = #self.toasts, 1, -1 do
		if self.toasts[i].big then table.remove(self.toasts, i) end
	end
	if not opts.quiet then self:toast(self.field.name:upper(), 2, nil, true) end
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
-- The drone comes out of the least worn stack in the hold, and carries
-- its wear (the share of armour it had lost) back in when it docks.
function Game:launchDrone(owner, item, x, y, angle)
	local shot = item.shot
	local wear = 0
	if owner.hold then
		-- the count already went down (Weapons took the ammo); take that stack
		local bestG, bestS
		for _, g in ipairs(owner.hold.grids) do
			for _, s in ipairs(g.stacks) do
				if s.id == item.id and not s.inner and (not bestS or (s.wear or 0) < (bestS.wear or 0)) then bestG, bestS = g, s end
			end
		end
		if bestS then
			wear = bestS.wear or 0
			bestS.n = bestS.n - 1
			if bestS.n <= 0 then Grid.remove(bestG, bestS) end
		end
	end
	local d = Ship.new(self, {
		hull = shot.hull, cargo = shot.cargo, team = owner.team, x = x, y = y, angle = angle,
		color = owner.color, enemy = { id = item.id, ai = DRONE_AI },
	})
	-- drones never expire: they come home once there's nothing to fight
	d.drone, d.owner, d.itemId = true, owner, item.id
	d.armor = d.stats.armor * (1 - wear)
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

-- What a sleeping piece of debris has instead of a body: just enough for
-- drawing it (and for anything that asks where it is).
local Ghost = {}
Ghost.__index = Ghost
function Ghost:getPosition() return self.x, self.y end
function Ghost:setPosition(x, y) self.x, self.y = x, y end
function Ghost:getAngle() return self.a end
function Ghost:getLinearVelocity() return 0, 0 end
function Ghost:destroy() end

-- Sleeping debris. Around a planet, every loose rock, ice chunk and piece
-- of junk just circles with the current, so the ones far from the player
-- don't need simulating: they're taken out of the world (their bodies
-- switched off, out of self.entities) and kept as an orbit (radius, angle
-- at a time, turn rate), and put back, exactly where that orbit has
-- carried them, when the player comes near. Far from the player is past
-- T.sleepFar; they wake inside T.sleepNear. Checked every T.sleepEvery
-- steps.
function Game:sleeperPos(e)
	local o = e.sleep
	local w = self.well
	local a = o.a + o.rate * (self.time - o.t)
	return w.x + cos(a) * o.r, w.y + sin(a) * o.r, a
end

function Game:updateSleepers()
	local w = self.well
	if not w or self.lane then return end
	self.sleepTick = (self.sleepTick or 0) + 1
	if self.sleepTick <= T.sleepEvery then return end
	self.sleepTick = 0
	local p = self.player
	local px, py
	if p and not p.dead then px, py = p.body:getPosition() else px, py = self.camera.x, self.camera.y end
	local far2, near2 = T.sleepFar ^ 2, T.sleepNear ^ 2
	-- wake the ones the player is coming up on
	local sl, keep = self.sleepers, {}
	for _, e in ipairs(sl) do
		if not e.removed then
			local x, y, a = self:sleeperPos(e)
			if (x - px) ^ 2 + (y - py) ^ 2 < near2 then
				local o = e.sleep
				e.sleep = nil
				self:debrisBody(e, x, y, e.body.a, o.spin)
				local v = o.rate * o.r
				e.body:setLinearVelocity(-sin(a) * v, cos(a) * v)
				table.insert(self.entities, e)
			else
				keep[#keep + 1] = e
			end
		end
	end
	self.sleepers = keep
	-- and put the far ones to sleep
	local awake = {}
	for _, e in ipairs(self.entities) do
		local slept = false
		if e.kind == "asteroid" and not e.giant and not e.dead and not e.removed and not e.reentry then
			local b = e.body
			local x, y = b:getPosition()
			if (x - px) ^ 2 + (y - py) ^ 2 > far2 then
				local dx, dy = x - w.x, y - w.y
				local r2 = dx * dx + dy * dy
				local vx, vy = b:getLinearVelocity()
				e.sleep = { r = sqrt(r2), a = math.atan2(dy, dx), t = self.time, rate = (dx * vy - dy * vx) / max(r2, 1),
					spin = b:getAngularVelocity() }
				-- out of the physics world entirely (an inactive body still
				-- costs Box2D a little every step, and there are thousands)
				e.body = setmetatable({ x = x, y = y, a = b:getAngle() }, Ghost)
				b:destroy()
				keep[#keep + 1] = e
				slept = true
			end
		end
		if not slept then awake[#awake + 1] = e end
	end
	self.entities = awake
end

-- Debris kinds (see Fields.mixes): shade/colour, how tough per px^2, and
-- what they break into.
local DEBRIS = {
	rock = { fill = { 0.24, 0.24, 0.27 }, line = { 0.6, 0.62, 0.68 }, tough = 1, breaks = "rock" },
	ice = { fill = { 0.42, 0.55, 0.62 }, line = { 0.8, 0.92, 1 }, tough = 0.6, breaks = "ice" },
	junk = { fill = { 0.25, 0.27, 0.31 }, line = { 0.66, 0.71, 0.78 }, tough = 0.8, breaks = "junk" },
	sat = { fill = { 0.3, 0.31, 0.34 }, line = { 0.8, 0.83, 0.88 }, tough = 0.7 },   -- bursts, no pieces
}
Game.DEBRIS = DEBRIS

-- The convex hull of a flat list of points (x1, y1, x2, y2, ...), as the
-- same kind of list, counter-clockwise (monotone chain).
local function convexHull(v)
	local pts = {}
	for i = 1, #v, 2 do pts[#pts + 1] = { v[i], v[i + 1] } end
	table.sort(pts, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
	local function cross(o, a, b) return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1]) end
	local lower, upper = {}, {}
	for _, p in ipairs(pts) do
		while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], p) <= 0 do table.remove(lower) end
		lower[#lower + 1] = p
	end
	for i = #pts, 1, -1 do
		local p = pts[i]
		while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], p) <= 0 do table.remove(upper) end
		upper[#upper + 1] = p
	end
	local out = {}
	for i = 1, #lower - 1 do out[#out + 1] = lower[i][1]; out[#out + 1] = lower[i][2] end
	for i = 1, #upper - 1 do out[#out + 1] = upper[i][1]; out[#out + 1] = upper[i][2] end
	return out
end

-- A random kind from a mix of weights ({ rock = 5, ice = 2, ... }).
function Game:pickDebris(mix)
	mix = mix or (self.field and self.field.mix) or { rock = 1 }
	local total = 0
	for _, w in pairs(mix) do total = total + w end
	local r = random() * total
	for _, k in ipairs({ "rock", "ice", "junk", "sat" }) do
		local w = mix[k]
		if w then
			if r < w then return k end
			r = r - w
		end
	end
	return "rock"
end

-- A typical size for a piece of debris of this kind.
function Game:debrisSize(kind)
	if kind == "sat" then
		-- mostly small birds, now and then a big platform
		return random() < 0.15 and 60 + random() * 60 or 20 + random() * 35
	end
	if kind == "junk" then return 16 + random() ^ 2.5 * 130 end   -- scraps, and the odd wrecked hulk
	return 28 + random() ^ 2 * 100
end

-- A breakable piece of debris: rock, ice, junk or a satellite. They all
-- fly, collide and break the same way; only the look, the shape and how
-- tough they are differ.
function Game:spawnDebris(kind, x, y, radius)
	return self:spawnAsteroid(x, y, radius, kind)
end

function Game:spawnAsteroid(x, y, radius, kind)
	kind = kind or "rock"
	local D = DEBRIS[kind] or DEBRIS.rock
	local verts = {}
	if kind == "sat" then
		-- a boxy bus (the panels are drawn, not collided)
		local h = radius * 0.45
		verts = { -h, -h, h, -h, h, h, -h, h }
	elseif kind == "junk" then
		-- jagged, flat scraps
		local n = random(4, 6)
		for j = 0, n - 1 do
			local ang = j / n * pi * 2 + (random() - 0.5) * 0.5
			local rr = radius * (0.5 + 0.5 * random()) * (j % 2 == 0 and 1 or 0.7)
			table.insert(verts, cos(ang) * rr)
			table.insert(verts, sin(ang) * rr)
		end
	else
		for j = 0, 7 do
			local ang = j / 8 * pi * 2 + (random() - 0.5) * 0.35
			local rr = radius * ((kind == "ice" and 0.7 or 0.82) + (kind == "ice" and 0.3 or 0.18) * random())
			table.insert(verts, cos(ang) * rr)
			table.insert(verts, sin(ang) * rr)
		end
	end
	-- jagged outlines can come out concave: keep their convex hull, so
	-- every piece is a polygon (never a plain circle)
	if not love.math.isConvex(verts) then verts = convexHull(verts) end
	local e = { kind = "asteroid", debris = kind, id = self:nextId(), team = 0, radius = radius, verts = verts,
		shade = 0.55 + random() * 0.25, fill = D.fill, line = D.line, blink = random() * 10,
		hp = radius * radius * T.asteroidToughness * D.tough }
	self:debrisBody(e, x, y, random() * pi * 2, (random() - 0.5) * (kind == "sat" and 0.2 or 0.6))
	e.body:setLinearVelocity((random() - 0.5) * 20, (random() - 0.5) * 20)
	table.insert(self.entities, e)
	return e
end

-- The physics body for a piece of debris (made again when it wakes).
function Game:debrisBody(e, x, y, angle, spin)
	local kind, radius = e.debris, e.radius
	local body = love.physics.newBody(self.world, x, y, "dynamic")
	body:setAngle(angle or 0)
	local fixture = love.physics.newFixture(body, love.physics.newPolygonShape(e.verts), 1)
	fixture:setRestitution(kind == "ice" and 0.1 or 0.2)
	fixture:setFriction(kind == "ice" and 0.1 or 0.5)
	local m = 0.12 * radius * radius * (kind == "ice" and 0.6 or 1)
	body:setMassData(0, 0, m, m * radius * radius * 0.5)
	-- rocks around a planet keep their orbits, so no drag there
	body:setLinearDamping(self.field and self.field.rockDrag or 0.25)
	body:setAngularDamping(0.2)
	body:setAngularVelocity(spin or 0)
	fixture:setUserData(e)
	body:setUserData(e)
	e.body, e.fixture = body, fixture
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
--
-- rocky: an airless rock (small moons, Ceres) instead of a smooth world:
-- a lumpy cratered outline (src/fields.lua, Fields.rockShape) that it
-- also collides as, and no atmosphere.
function Game:spawnPlanet(x, y, radius, flow, swirl, rocky)
	local body = love.physics.newBody(self.world, x, y, "static")
	local e = { kind = "planet", invulnerable = true, id = self:nextId(), team = 0, radius = radius, body = body,
		hue = { 0.35 + random() * 0.2, 0.45 + random() * 0.2, 0.7 + random() * 0.2 } }
	local shape
	if rocky then
		e.rock = rocky
		shape = love.physics.newChainShape(true, rocky.outline)
	else
		shape = love.physics.newCircleShape(radius)
	end
	local f = love.physics.newFixture(body, shape)
	f:setFriction(0.6)
	f:setRestitution(0.1)
	f:setUserData(e)
	body:setUserData(e)
	table.insert(self.entities, e)
	-- atmo: how deep the atmosphere (the haze drawn round it) reaches
	self.well = { x = x, y = y, radius = radius, flow = flow, swirl = swirl, atmo = not rocky and 840 or nil, planet = e }
	return e
end

-- How fast the field's current runs at distance r from the planet.
function Game:currentSpeed(r)
	local w = self.well
	if not w then return 0 end
	return w.flow * sqrt(w.radius / max(r, w.radius)) * T.currentScale
end

-- The current's velocity at (x, y): along the tangent, clockwise on screen.
function Game:flowAt(x, y)
	local w = self.well
	if not w then return 0, 0 end
	local dx, dy = w.x - x, w.y - y
	local r = max(sqrt(dx * dx + dy * dy), 1)
	local f = self:currentSpeed(r)
	return dy / r * f, -dx / r * f
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
			self:spawnInfallingAsteroid(radius, o.debris)
		elseif o.kind == "husk" or o.kind == "container" then
			self:addEffect({ kind = "explosion", x = x, y = y, r = 120, life = 0.4, t = 0, dust = true })
			self:remove(o)
		end
	end
end

-- A rock arriving from the edge of the map: it comes in moving with the
-- current and is steered into a lane in the belt (e.orbitR, see
-- applyCurrent), where it settles into orbit.
function Game:spawnInfallingAsteroid(radius, kind)
	local w = self.well
	local Rm = self.arenaRadius - 400
	for _ = 1, 20 do
		local a = random() * pi * 2
		local x, y = w.x + cos(a) * Rm, w.y + sin(a) * Rm
		if self:isClear(x, y, radius + 80) then
			local e = self:spawnAsteroid(x, y, radius, kind)
			local f = self:currentSpeed(Rm)
			e.body:setLinearVelocity(-sin(a) * f - cos(a) * 250, cos(a) * f - sin(a) * 250)
			-- settles into the map's belt
			local band = self.field and self.field.belt or { w.radius + 1500, w.radius + 6000 }
			e.orbitR = band[1] + random() * (band[2] - band[1])
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
	-- the wheel's layout as parts (src/stations.lua); a station { } with
	-- the same id in data or mods replaces it
	local id = Stations.ringId(R, tube)
	if not data.stations[id] then
		local _, err = data.defineStation(Stations.ring(R, tube))
		if err then error(err, 0) end
	end
	return self:spawnStation(id, x, y, spin, simulated)
end

-- A station from its definition (data.stations): every colliding part
-- is solid, and the part tagged dock is the docking module.
function Game:spawnStation(id, x, y, spin, simulated)
	local def = data.stations[id]
	local body = love.physics.newBody(self.world, x, y, simulated and "dynamic" or "kinematic")
	body:setAngle(random() * pi * 2)
	body:setAngularVelocity(spin or 0.04)
	-- key: which station this is, for the universe (storage, hangar,
	-- respawn); the same field always builds its stations in the same order
	self.stationCount = (self.stationCount or 0) + 1
	local n = self.stationCount
	local names = self.field and self.field.stations
	local e = { kind = "station", invulnerable = true, id = self:nextId(), team = 0, body = body,
		def = def,
		key = ("%s/%d"):format(self.fieldId or "?", n),
		name = names and names[n] or ((self.field and self.field.name or "") .. " Station " .. n) }
	-- The dock (see Game:updateDocking): x1..x2 its extent out from the
	-- centre along +x, hw its half-width. Ships that fly into the capture
	-- zone in front of its door are pulled inside.
	e.docks = {}
	for _, d in ipairs(def.docks) do
		local copy = {}
		for k, v in pairs(d) do copy[k] = v end
		table.insert(e.docks, copy)
	end
	e.dock = e.docks[1]
	e.radius = def.radius
	-- the dock module is solid too; ships only get inside by being pulled in
	for _, part in ipairs(def.parts) do
		if part.collide ~= false then
			for _, t in ipairs(part.tris) do
				local a2 = math.abs((t[3] - t[1]) * (t[6] - t[2]) - (t[5] - t[1]) * (t[4] - t[2]))
				if a2 > 4 then
					local f = love.physics.newFixture(body, love.physics.newPolygonShape(t))
					f:setFriction(0.5)
					f:setRestitution(0.1)
					f:setUserData(e)
				end
			end
		end
	end
	self:armStation(e)
	local R = def.radius
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

-- Station turrets (def.turrets): each fires its weapon module like a
-- ship's turret, with endless ammo and power, at whatever
-- Game:stationHostile says. The station itself is the gun's owner, so it
-- carries the few fields Weapons.fire reads off a ship.
local STATION_MULT = { primaryFireRate = 1, primaryDamage = 1, missileDamage = 1, ramDamage = 1 }
local ENDLESS = { __index = function() return math.huge end }
local GRUDGE_TIME = 30        -- seconds a station stays angry at whoever shot it
local RETARGET = 0.4          -- seconds between each turret's target checks
local STATION_DRONE_REACH = 5000   -- how near a target a station's drone bays launch at
Game.STATION_DRONE_REACH = STATION_DRONE_REACH

function Game:armStation(e)
	local list = {}
	for _, t in ipairs(e.def.turrets or {}) do
		local m = data.modules[t.module]
		if m and m.weapon then
			-- missile, torpedo and drone launchers are fixed bays: they
			-- point one way (heading, or straight out from the centre);
			-- missiles curve round to the target, drones fly off to it
			local bay = m.family == "auxiliary"
			local out = (t.x == 0 and t.y == 0) and 0 or math.atan2(t.y, t.x)
			table.insert(list, { slot = { x = t.x, y = t.y }, module = m, w = m.weapon,
				group = bay and "auxiliary" or "primary",
				ammo = data.ammoFor(m), ammoOptions = data.ammoOptions(m),
				cooldown = random() * 0.5, think = random() * RETARGET,
				mount = bay and "bay" or "turret", turn = math.rad(t.turn or 90),
				aim = bay and (t.heading and math.rad(t.heading) or out) or random() * pi * 2 })
		end
	end
	if #list == 0 then return end
	e.weapons = list
	e.stats = { mult = STATION_MULT }
	e.cargo = setmetatable({}, ENDLESS)
	e.power = math.huge
	e.intent = Ship.emptyIntent()
	e.color = e.color or e.def.color        -- its drones' paint
	e.grudge = e.grudge or setmetatable({}, { __mode = "k" })
end

-- Would this station shoot at o? For now: hostile ships (team 2, and
-- their drones), and anyone who has shot the station lately. The
-- reputation and AI system will replace this.
function Game:stationHostile(st, o)
	if o.kind ~= "ship" or o.dead or o.removed or o.dockState then return false end
	local g = st.grudge and st.grudge[o]
	if g and self.time - g < GRUDGE_TIME then return true end
	return o.team == 2
end

function Game:updateStationGuns(dt)
	for _, st in ipairs(self.entities) do
		if st.kind == "station" and st.weapons and not st.removed then
			local sa = st.body:getAngle()
			for _, slot in ipairs(st.weapons) do
				slot.cooldown = max(0, slot.cooldown - dt)
				local wx, wy = Ship.hardpoint(st, slot.slot)
				-- (a drone's "range" is how far it flies on launch; a drone
				-- bay launches at anything inside STATION_DRONE_REACH)
				local range = slot.w.kind == "drone" and STATION_DRONE_REACH or Weapons.range(slot)
				-- now and then, the nearest hostile in reach
				slot.think = slot.think - dt
				local tg = slot.target
				if slot.think <= 0 or (tg and (tg.dead or tg.removed or tg.dockState)) then
					slot.think = RETARGET
					tg = nil
					local best = range * range
					for _, o in ipairs(self.entities) do
						if o.kind == "ship" and self:stationHostile(st, o) then
							local ox, oy = o.body:getPosition()
							local d = (ox - wx) ^ 2 + (oy - wy) ^ 2
							if d < best then tg, best = o, d end
						end
					end
					slot.target = tg
				end
				if tg then
					-- lead the target by the shot's flight time (lasers hit
					-- at once; missiles steer themselves)
					local tx, ty = tg.body:getPosition()
					local kind = slot.w.kind
					if kind ~= "laser" and kind ~= "missile" and slot.ammo then
						local speed = data.items[slot.ammo].shot.speed
						local vx, vy = tg.body:getLinearVelocity()
						local svx, svy = st.body:getLinearVelocityFromWorldPoint(wx, wy)
						local t = sqrt((tx - wx) ^ 2 + (ty - wy) ^ 2) / max(1, speed)
						tx, ty = tx + (vx - svx) * t, ty + (vy - svy) * t
					end
					local want = Ship.wrapAngle(math.atan2(ty - wy, tx - wx) - sa)
					local err = Ship.wrapAngle(want - slot.aim)
					local cone = 0.06
					if slot.mount == "bay" then
						-- fixed: missiles launch whichever way the target is
						-- (they steer); torpedoes only down the bay's line
						cone = (kind == "missile" or kind == "drone") and math.huge or 0.15
					else
						local step = slot.turn * dt
						slot.aim = Ship.wrapAngle(slot.aim + max(-step, min(step, err)))
					end
					if math.abs(err) < cone then
						st.intent.aimX, st.intent.aimY = tx, ty
						st.lock = tg
						Weapons.fire(self, st, slot, dt)
					end
				end
			end
		end
	end
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

-- A dock's frame: station-local coordinates with +x out of the door. A dock
-- with d.both (a cloud city's tunnel) opens both ways along x, and side -1
-- is the frame mirrored, for the far end.
-- A station can have several docks; each sits in its own frame, turned by
-- d.a and shifted d.xc along and d.yc across (all 0 for a dock along the
-- station's +x). A tunnel (d.both) is centred on its frame, so its far
-- end is the same frame mirrored (side -1).
-- d defaults to the station's first dock.
local function dockLocal(st, side, x, y, d)
	d = d or st.dock
	local lx, ly = st.body:getLocalPoint(x, y)
	local a = d.a or 0
	local c, s = cos(a), sin(a)
	local rx, ry = lx * c + ly * s - (d.xc or 0), -lx * s + ly * c - (d.yc or 0)
	return rx * side, ry * side
end
local function dockWorld(st, side, lx, ly, d)
	d = d or st.dock
	local a = d.a or 0
	local c, s = cos(a), sin(a)
	local rx, ry = lx * side + (d.xc or 0), ly * side + (d.yc or 0)
	return st.body:getWorldPoint(rx * c - ry * s, rx * s + ry * c)
end
local function dockVector(st, side, vx, vy, d)
	d = d or st.dock
	local a = d.a or 0
	local c, s = cos(a), sin(a)
	vx, vy = vx * side, vy * side
	return st.body:getWorldVector(vx * c - vy * s, vx * s + vy * c)
end
local function dockAngle(st, side, d)
	d = d or st.dock
	return st.body:getAngle() + (d.a or 0) + (side < 0 and pi or 0)
end
Game.dockWorld, Game.dockAngle, Game.dockLocal = dockWorld, dockAngle, dockLocal

-- Station-local position of a point, and whether it's in the tractor zone
-- (over the runway, in front of the door), and from which side.
function Game:inTractorZone(st, x, y)
	for _, d in ipairs(st.docks or { st.dock }) do
		local lx, ly = dockLocal(st, 1, x, y, d)
		local side = (d.both and lx < 0) and -1 or 1
		lx, ly = lx * side, ly * side
		if lx > d.x2 and lx < d.x2 + d.runway and math.abs(ly) < d.hw * 1.3 then
			return true, lx, ly, side, d
		end
	end
	return false
end

function Game:beginDocking(e, st, side, dock)
	e.dockState = { station = st, phase = "tractor", t = 0, side = side or 1, dock = dock or st.dock }
	-- the player keeps the stick while the beam works (like a mass
	-- driver's): it can be fought, overshot or slid out of
	if e ~= self.player then
		e.intent.thrust, e.intent.strafe, e.intent.boost = 0, 0, false
	end
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
					if st.kind == "station" and (not trader or (e.route and e.route[e.routeIndex or 1] == st)) then
						local inZone, _, _, side, dock = self:inTractorZone(st, x, y)
						if inZone then
							self:beginDocking(e, st, side, dock)
							break
						end
					end
				end
			end
		end
	end
end

local function wrapAngle(a) return (a + pi) % (2 * pi) - pi end

-- A free berth at the station that the ship fits on, or nil (no berths,
-- all taken, or all too small): then it goes inside.
function Game:freeBerth(st, e)
	local berths = st.def and st.def.berths
	if not berths or #berths == 0 then return nil end
	local taken = {}
	for _, o in ipairs(self.entities) do
		local ods = o ~= e and not o.dead and not o.removed and o.dockState
		if ods and ods.station == st and ods.berth then taken[ods.berth] = true end
	end
	for i, b in ipairs(berths) do
		if not taken[i] and (e.halfLength or 0) <= b.size then return i end
	end
	return nil
end

function Game:finishDocking(e, ds, st)
	ds.phase, ds.done, ds.t = "done", true, 0
	if e == self.player then
		self.state = "docked"
		self:playerDocked(st)
	else
		ds.stay = 30 + random() * 60
	end
	events.emit("dock", e, st)
end

-- One step of a docking ship: tractor it in, pull it inside (or over to a
-- berth), or wait.
function Game:updateDockedShip(e, dt)
	local ds = e.dockState
	local st, d = ds.station, ds.dock or ds.station.dock
	local b, sb = e.body, st.body
	local side = ds.side or 1
	ds.t = ds.t + dt

	if ds.phase == "tractor" then
		local x, y = b:getPosition()
		local lx, ly = dockLocal(st, side, x, y, d)
		local doorX = d.x2 + e.halfLength + 40
		-- grip grows over the first second and as the ship nears the door
		local near = 1 - max(0, min(1, (lx - doorX) / d.runway))
		local grip = min(1, ds.t / 1.0) * (0.35 + 0.65 * near)
		-- wanted velocity, in the station's frame: onto the centre line and
		-- in toward the door, slowing as it arrives
		local gap = lx - doorX
		local inward = -min(260, gap > 0 and max(50, gap * 0.6) or gap * 0.6)
		local across = -ly * 0.8
		local wx, wy = dockVector(st, side, inward, across, d)
		local svx, svy = sb:getLinearVelocityFromWorldPoint(x, y)
		local vx, vy = b:getLinearVelocity()
		local k = 2.2 * grip
		local m = b:getMass()
		local ax, ay = (svx + wx - vx) * k, (svy + wy - vy) * k
		if e == self.player then
			-- the player's beam has a limited grip, like a mass driver's
			local a = sqrt(ax * ax + ay * ay)
			local cap = T.driverGrip * (0.5 + 0.5 * grip)
			if a > cap then ax, ay = ax / a * cap, ay / a * cap end
			if lx > d.x2 + d.runway * 1.2 or math.abs(ly) > d.hw * 2 then
				e.dockState, e.dockCooldown = nil, 3
				self:toast("TRACTOR LOST", 1.4)
				return
			end
		end
		b:applyForce(ax * m, ay * m)
		-- nose toward the door
		local want = dockAngle(st, side, d) + pi
		local turn = wrapAngle(want - b:getAngle()) * 1.4 * grip + sb:getAngularVelocity()
		b:setAngularVelocity(b:getAngularVelocity() + (turn - b:getAngularVelocity()) * min(1, 3 * dt))
		local rvx, rvy = vx - svx, vy - svy
		if lx <= doorX + 30 and math.abs(ly) < d.hw * 0.4 and rvx * rvx + rvy * rvy < 250 ^ 2 then
			local berth = self:freeBerth(st, e)
			if berth then
				-- a free berth outside: glide over and park there, in view
				local bd = st.def.berths[berth]
				ds.phase, ds.t, ds.berth = "taxi", 0, berth
				ds.lx, ds.ly = sb:getLocalPoint(x, y)
				ds.la = b:getAngle() - sb:getAngle()
				ds.dur = max(1.5, min(8, sqrt((bd.x - ds.lx) ^ 2 + (bd.y - ds.ly) ^ 2) / 220))
			else
				ds.phase, ds.t = "pull", 0
				ds.lx, ds.ly, ds.la = lx, ly, b:getAngle() - dockAngle(st, side, d)
			end
			b:setActive(false)
		end
		return
	end

	if ds.phase == "taxi" then
		local bd = st.def.berths[ds.berth]
		local f = min(1, ds.t / ds.dur)
		f = f * f * (3 - 2 * f)
		local ba = math.rad(bd.heading)
		b:setPosition(sb:getWorldPoint(ds.lx + (bd.x - ds.lx) * f, ds.ly + (bd.y - ds.ly) * f))
		b:setAngle(sb:getAngle() + ds.la + wrapAngle(ba - ds.la) * f)
		b:setLinearVelocity(0, 0)
		b:setAngularVelocity(0)
		if f >= 1 then self:finishDocking(e, ds, st) end
		return
	end

	if ds.phase == "pull" then
		local f = min(1, ds.t / PULL_TIME)
		f = f * f * (3 - 2 * f)
		local tx = (d.x1 + d.x2) / 2
		local da = wrapAngle(pi - ds.la)
		b:setPosition(dockWorld(st, side, ds.lx + (tx - ds.lx) * f, ds.ly * (1 - f), d))
		b:setAngle(dockAngle(st, side, d) + ds.la + da * f)
		b:setLinearVelocity(0, 0)
		b:setAngularVelocity(0)
		if f >= 1 then self:finishDocking(e, ds, st) end
		return
	end

	-- docked: ride along, parked on a berth or inside
	if ds.berth then
		local bd = st.def.berths[ds.berth]
		b:setPosition(sb:getWorldPoint(bd.x, bd.y))
		b:setAngle(sb:getAngle() + math.rad(bd.heading))
	else
		b:setPosition(dockWorld(st, side, (d.x1 + d.x2) / 2, 0, d))
	end
	if ds.stay and ds.t >= ds.stay then self:undockShip(e) end
end

-- Launch a docked ship back out of the door.
function Game:undockShip(e)
	local ds = e.dockState
	if not ds or not ds.done then return end
	local st, d = ds.station, ds.dock or ds.station.dock
	local sb = st.body
	local side = ds.side or 1
	local wx, wy, wa, ox, oy, speed
	local bd = ds.berth and st.def.berths[ds.berth]
	if bd then
		-- off the berth, nose first, gently
		wx, wy = sb:getWorldPoint(bd.x, bd.y)
		wa = sb:getAngle() + math.rad(bd.heading)
		ox, oy, speed = cos(wa), sin(wa), 140
	else
		wx, wy = dockWorld(st, side, d.x2 + e.halfLength + 60, 0, d)
		ox, oy = dockVector(st, side, 1, 0, d)
		wa, speed = dockAngle(st, side, d), 260
	end
	local svx, svy = sb:getLinearVelocityFromWorldPoint(wx, wy)
	e.body:setPosition(wx, wy)
	e.body:setAngle(wa)
	e.body:setActive(true)
	e.body:setLinearVelocity(svx + ox * speed, svy + oy * speed)
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
		local kind = self:pickDebris()
		local radius = kind == "rock" and 28 + random() ^ 2 * 100 or self:debrisSize(kind)
		local a = random() * pi * 2
		local d = minD + random() * (self.arenaRadius - minD - 150)
		local x, y = cos(a) * d, sin(a) * d
		if self:isClear(x, y, radius + 60) then self:spawnAsteroid(x, y, radius, kind); placed = placed + 1 end
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
	if not p or p.dead or (p.dockState and p.dockState.phase ~= "tractor") or p.launch then return end
	local d = self:pilotedShip()
	if d ~= p then
		-- flying a drone: it gets the stick, your ship holds still
		for k, v in pairs(intent) do d.intent[k] = v end
		d.intent.targetDist = nil
		local x, y = p.body:getPosition()
		local a = p.body:getAngle()
		for k, v in pairs(intent) do p.intent[k] = v end
		p.intent.thrust, p.intent.strafe, p.intent.boost, p.intent.tractor = 0, 0, false, false
		p.intent.firePrimary, p.intent.fireSecondary, p.intent.fireAux = false, false, false
		p.intent.aimX, p.intent.aimY = x + cos(a) * 700, y + sin(a) * 700
		return
	end
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
				-- the player flies on under the beam until it's pulled inside
				if e == self.player and e.dockState.phase == "tractor" then Ship.fly(e, dt) end
				self:updateDockedShip(e, dt)
			else
				if e.cruise then self:cruise(e) elseif e.def and not e.piloted then AI.think(self, e, dt) end
				Ship.fly(e, dt)
				Weapons.update(self, e, dt)
			end
		end
	end

	self:updateStationGuns(dt)
	self:updateSleepers()
	self:applyBoundary()
	self:applyCurrent(dt)
	self:updateLane(dt)
	self:updateAtmosphere(dt)
	self:updateCrush(dt)
	self:updateDrivers(dt)
	self:updateCatch(dt)
	self:updateMoonGates(dt)
	self:updateOrbits(dt)
	self:updateCities(dt)
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
		-- the highway, or the warp trip and the catch (debug panel picks)
		if T.travelMode == "flight" then self:beginFlight(to) else self:launchTrip(to) end
	elseif self.pendingArrive then
		local back = self.pendingArrive == "back"
		self.pendingArrive = nil
		self:arrive(back)
	end
end

-- Soft arena edge: the further past it, the harder you're pushed back.
function Game:applyBoundary()
	local R = self.arenaRadius
	for _, e in ipairs(self.entities) do
		local b = e.body
		local x, y = b:getPosition()
		local d = sqrt(x * x + y * y)
		-- only what people built is turned back (rocks drift on out), and
		-- gently, like a nudge from traffic control
		if d > R and e.kind ~= "asteroid" and not e.fleeing and not e.catching and not e.launch then
			local over = d - R
			local f = min(over, 1500) * b:getMass() * 1.2
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
				self:damage(o, base * mult, other, "ram", c.x, c.y)
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
-- hx, hy: where it hit, when that's known (a wreck built in parts takes
-- it on the part that was hit).
function Game:damage(e, amount, source, cause, hx, hy)
	-- a station remembers who shot it (and its turrets answer)
	if e and e.grudge and source and source.kind == "ship" and amount > 0 then e.grudge[source] = self.time end
	-- Asteroids, husks and containers don't flinch: they soak damage until they break
	-- apart (in reap).
	if e and (e.invulnerable or e.dockState) then return end
	if e and e.kind == "husk" and e.pieces and not e.dead and amount > 0 and self:damagePiece(e, amount, hx, hy) then return end
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
				if not (owner and e.team == owner.team) then self:damage(e, damage * fall, owner, cause or "splash", x, y) end
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
	local breaks = (DEBRIS[e.debris or "rock"] or DEBRIS.rock).breaks
	local n = breaks and random(2, 4) or 0
	local spin = random() * pi * 2
	for k = 1, n do
		local r = e.radius * sqrt(1 / n) * (0.75 + random() * 0.25)
		if r >= 14 then
			local a = spin + k / n * pi * 2 + (random() - 0.5) * 0.6
			local rock = self:spawnAsteroid(x + cos(a) * e.radius * 0.45, y + sin(a) * e.radius * 0.45, r, breaks)
			local s = 40 + random() * 90
			rock.body:setLinearVelocity(vx + cos(a) * s, vy + sin(a) * s)
		end
	end
	self:spark(x, y, 8 + floor(e.radius / 4), e.line or { 0.65, 0.65, 0.7 })
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
		elseif e.recalled then
			-- a drone back in its bay: into the owner's hold, wear and all
			table.remove(self.entities, i)
			local x, y = e.body:getPosition()
			e.body:destroy()
			e.removed = true
			local o = e.owner
			if o and not o.dead and e.itemId then
				local wear = 1 - e.armor / e.stats.armor
				local s = { id = e.itemId, n = 1, wear = wear > 0.005 and wear or nil }
				if not o.hold then
					o.cargo[e.itemId] = (o.cargo[e.itemId] or 0) + 1
				elseif Hold.placeStack(o.hold, s) then
					o.cargo[e.itemId] = (o.cargo[e.itemId] or 0) + 1
					Ship.updateMass(o)
					if o.isPlayer then self:toast("Drone returned", 1.2) end
				else
					self:spawnPickup(x, y, e.itemId, 1)
					if o.isPlayer then self:toast("No room for the drone", 1.2) end
				end
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
	-- Remembered by slot, so a wreck in parts can put each one in the part
	-- its slot sits on (Game:breakablePieces).
	e.salvagedSlots = {}
	for i in ipairs(e.hull.slots) do
		local id = e.loadout[i]
		if id and data.items[id] and random() < T.moduleSalvage then
			loot[id] = (loot[id] or 0) + 1
			e.salvagedSlots[i] = id
		end
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
	if #hull.parts > 1 then
		self:breakablePieces(h, ship)
	else
		local n = math.ceil((s2 - s1) / r) + 1
		for k = 0, n - 1 do
			local cx = (n > 1) and (s1 + (s2 - s1) * k / (n - 1)) or s1
			local f = love.physics.newFixture(body, love.physics.newCircleShape(cx, 0, r), 1)
			f:setRestitution(0.2)
			f:setFriction(0.5)
			f:setUserData(h)
		end
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

-- A placed wreck or prop (data.wrecks): rolls its loot table, then becomes
-- a husk like a dead ship's, so it drifts, loots and breaks apart the same.
function Game:spawnWreck(id, x, y, a, vx, vy)
	local def = data.wrecks[id]
	if not def then return nil end
	local cargo = {}
	for _, l in ipairs(def.loot) do
		local item, lo, hi, chance = l[1], l[2] or 1, l[3] or l[2] or 1, l[4] or 1
		if data.items[item] and random() < chance then
			cargo[item] = (cargo[item] or 0) + random(lo, math.max(lo, hi))
		end
	end
	-- a stand-in for the ship a husk normally comes from
	local noseX, tailX = 0, 0
	for k = 1, #def.shape, 2 do noseX, tailX = max(noseX, def.shape[k]), min(tailX, def.shape[k]) end
	local r = def.radius
	local s1, s2 = tailX + r, noseX - r
	if s2 < s1 then s1, s2 = (s1 + s2) / 2, (s1 + s2) / 2 end
	local ghost = {
		hull = def, color = def.color or { 0.7, 0.72, 0.75 }, spine = { s1, s2 },
		noseX = noseX, tailX = tailX, halfLength = max(noseX, -tailX),
		stats = { armor = def.armor / T.huskToughness, hold = def.hold, mass = def.mass },
		cargo = cargo, loadout = {},
	}
	local h = self:spawnHusk(ghost, x, y, a or random() * pi * 2, (vx or 0) / 0.6, (vy or 0) / 0.6, (random() - 0.5) * 0.2)
	h.placed = def.kind
	return h
end

-- A wreck of a hull built in parts stays whole, but each part outside the
-- biggest (the core) can be shot off. Every part collides in its own
-- shape and holds a share of the loot, weighted by its size (the
-- wreck's hold has it all until then; containers go whole).
-- When a part's share of the wreck's toughness is used up it breaks away
-- as its own small wreck, taking what's left of its share with it.
local function partFixtures(body, part, h, ox, oy)
	local list = {}
	if part.collide == false then return list end
	for _, t in ipairs(part.tris) do
		local pts = { t[1] - ox, t[2] - oy, t[3] - ox, t[4] - oy, t[5] - ox, t[6] - oy }
		local tri = math.abs((pts[3] - pts[1]) * (pts[6] - pts[2]) - (pts[5] - pts[1]) * (pts[4] - pts[2]))
		if tri > 4 then
			local f = love.physics.newFixture(body, love.physics.newPolygonShape(pts), 1)
			f:setRestitution(0.2)
			f:setFriction(0.5)
			f:setUserData(h)
			table.insert(list, f)
		end
	end
	return list
end

function Game:breakablePieces(h, ship)
	local hull = ship.hull
	-- the core: a part tagged core, else the biggest one that collides.
	-- Loot goes to the parts tagged cargo, or to every part if none is.
	local total, core, tagged = 0, nil, nil
	for _, part in ipairs(hull.parts) do
		total = total + part.area
		if part.core then tagged = tagged or part end
		if part.collide ~= false and (not core or part.area > core.area) then core = part end
	end
	core = tagged or core
	local anyCargo = false
	for _, part in ipairs(hull.parts) do
		if part.cargo then anyCargo = true end
	end
	local function carries(part)
		return part.collide ~= false and (part.cargo or not anyCargo)
	end
	h.pieces, h.armorBase = {}, ship.stats.armor * T.huskToughness
	local lootTotal = 0
	for _, part in ipairs(hull.parts) do
		-- parts that never break off count as the core
		local fixed = part == core or part.breakable == false or part.collide == false
		local piece = { part = part, core = fixed, frac = part.area / total, share = {} }
		piece.hp = h.armorBase * piece.frac * (part.armor or 1)
		piece.fixtures = partFixtures(h.body, part, h, 0, 0)
		table.insert(h.pieces, piece)
		if carries(part) then lootTotal = lootTotal + part.area end
	end
	-- mass tag: a part's share of the wreck's weight, when it breaks away
	local massTotal = 0
	for _, pc in ipairs(h.pieces) do massTotal = massTotal + pc.part.area * (pc.part.mass or 1) end
	for _, pc in ipairs(h.pieces) do pc.massFrac = pc.part.area * (pc.part.mass or 1) / max(massTotal, 1) end
	-- fitted modules that survived go to the part their slot sits on (the
	-- topmost one under the hardpoint); unplaced slots stay with the core
	local reserved = {}
	for i, id in pairs(ship.salvagedSlots or {}) do
		local slot = hull.slots[i]
		local owner
		if slot and slot.x then
			for k = #h.pieces, 1, -1 do
				local pc = h.pieces[k]
				if pc.part.collide ~= false and HullShape.contains(pc.part, slot.x, slot.y or 0) then owner = pc break end
			end
		end
		reserved[id] = (reserved[id] or 0) + 1
		if owner and not owner.core then owner.share[id] = (owner.share[id] or 0) + 1 end
	end
	-- share the rest out: loose items unit by unit, containers whole
	if lootTotal > 0 then
		for id, n in pairs(Hold.totals(h.hold)) do
			for _ = 1, n - (reserved[id] or 0) do
				local r, pick = random() * lootTotal, nil
				for _, pc in ipairs(h.pieces) do
					if carries(pc.part) then
						pick = pc
						r = r - pc.part.area
						if r <= 0 then break end
					end
				end
				if pick and not pick.core then pick.share[id] = (pick.share[id] or 0) + 1 end
			end
		end
	end
end

-- Damage on a wreck in parts: the part nearest the hit (or any, if we
-- don't know where) takes it. Returns true if a breakable part took it;
-- hits on the core fall through to the wreck as a whole.
function Game:damagePiece(h, amount, hx, hy)
	local piece
	if hx then
		local lx, ly = h.body:getLocalPoint(hx, hy)
		local best = math.huge
		for _, pc in ipairs(h.pieces) do
			local d = pc.part.collide == false and math.huge or (lx - pc.part.cx) ^ 2 + (ly - pc.part.cy) ^ 2
			if d < best then best, piece = d, pc end
		end
	else
		piece = h.pieces[random(1, #h.pieces)]
	end
	if not piece or piece.core then return false end
	piece.hp = piece.hp - amount
	if piece.hp <= 0 then self:breakOff(h, piece) end
	return true
end

function Game:breakOff(h, piece)
	local part = piece.part
	for i, pc in ipairs(h.pieces) do if pc == piece then table.remove(h.pieces, i) break end end
	for _, f in ipairs(piece.fixtures) do f:destroy() end
	h.partsLeft = {}
	for _, pc in ipairs(h.pieces) do table.insert(h.partsLeft, pc.part) end
	-- what's left of its share leaves with it
	local taken, stacks = {}, {}
	for id, n in pairs(piece.share) do
		if data.items[id].kind == "container" then
			-- containers go whole, cargo and all
			for _, g in ipairs(h.hold.grids) do
				for k = #g.stacks, 1, -1 do
					local s = g.stacks[k]
					if n > 0 and s.id == id then
						Grid.remove(g, s)
						table.insert(stacks, { id = s.id, n = 1, inner = s.inner })
						n = n - 1
					end
				end
			end
		else
			local got = Hold.take(h.hold, id, n)
			if got > 0 then taken[id] = got end
		end
	end
	h.loot = Hold.totals(h.hold)
	local x, y = h.body:getWorldPoint(part.cx, part.cy)
	if part.explode then
		-- this part bursts instead of drifting off: its share scatters
		for id, n in pairs(taken) do self:spawnPickup(x, y, id, n) end
		for _, st in ipairs(stacks) do self:spawnPickup(x, y, st.id, st.n, st.inner) end
		self:spark(x, y, 28, { 1, 0.7, 0.35 })
		self:explode(x, y, part.reach * 1.2, 0, 0)
		return
	end
	local vx, vy = h.body:getLinearVelocityFromWorldPoint(x, y)
	local hx, hy = h.body:getPosition()
	local ox, oy = x - hx, y - hy
	local ol = max(sqrt(ox * ox + oy * oy), 1)
	local kick = 80 + random() * 120
	local body = love.physics.newBody(self.world, x, y, "dynamic")
	local bits = {
		kind = "husk", id = self:nextId(), team = 0, hull = h.hull, part = part, color = h.color,
		noseX = part.reach, tailX = -part.reach, halfLength = part.reach, radius = part.reach, body = body,
		hold = Hold.pack(taken, 4, 3, h.hull.name .. " wreckage", random, stacks), hp = h.armorBase * piece.frac * 0.5,
		flicker = random() * 10,
	}
	bits.loot = Hold.totals(bits.hold)
	partFixtures(body, part, bits, part.cx, part.cy)
	local m = max(1, h.body:getMass() * (piece.massFrac or piece.frac))
	body:setMassData(0, 0, m, m * part.reach * part.reach * 0.4)
	body:setAngle(h.body:getAngle())
	body:setLinearVelocity(vx + ox / ol * kick, vy + oy / ol * kick)
	body:setAngularVelocity(h.body:getAngularVelocity() + (random() - 0.5) * 2)
	body:setLinearDamping(0.15)
	body:setAngularDamping(0.1)
	body:setUserData(bits)
	table.insert(self.entities, bits)
	self:spark(x, y, 16, { 1, 0.6, 0.3 })
	self:explode(x, y, part.reach * 0.6, 0, 0)
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
	-- the launch and the lane's run-up take the zoom for a while
	local p = self.player
	if self.cineZoom and (not p or p.dead or not (p.launch or p.runup)) then
		-- whatever was running it is over (died, or a load): the zoom stays
		-- where it is, and it's yours again
		self.cineZoom, self.savedZoom = nil, nil
	end
	if self.cineZoom then
		self.camera.zoom = self.camera.zoom + (self.cineZoom - self.camera.zoom) * (1 - exp(-dt * 6))
	end
	if p and p.laneFade then
		p.laneFade = p.laneFade - dt / 1.5
		if p.laneFade <= 0 then p.laneFade = nil end
	end
	if self.flash then
		self.flash.t = self.flash.t + dt
		if self.flash.t >= self.flash.life then self.flash = nil end
	end
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

	p = self.player
	if p and not p.dead then
		self:updateComputers(dt)
		local x, y = self:pilotedShip().body:getPosition()
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
require("src.moons")(Game)
require("src.computers")(Game)
require("src.market")(Game)

return Game
