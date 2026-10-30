--[[
	The flight-toy arena: one Box2D world, a flat list of entities (ships
	and asteroids), and lists of projectiles, pickups and effects. Systems
	are just functions that loop over those lists each step.

	This is the "instance" layer from the design doc in miniature: a
	generated space you fight in. Docking, stations and saving come later.
]]

local data = require("src.data")
local T = require("src.tuning")
local Ship = require("src.ship")
local Weapons = require("src.weapons")
local AI = require("src.ai")
local Camera = require("src.camera")
local events = require("src.events")
local Fields = require("src.fields")

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
	self.wave = 0
	self.waveTimer = 2.5
	self.wavesOn = opts.waves ~= false
	self.kills = 0
	self.state = "playing"
	self.stats = { maxImpulse = 0, maxImpactSpeed = 0 }

	self:loadField(opts.field or "asteroids")
	return self
end

-- Clear the arena and build a playing field (src/fields.lua) in it, then
-- launch the player.
function Game:loadField(id)
	for _, e in ipairs(self.entities) do
		if not e.removed then e.body:destroy(); e.removed = true end
	end
	self.entities, self.projectiles, self.pickups, self.effects, self.contacts = {}, {}, {}, {}, {}
	self.player, self.playerHusk, self.deathX, self.deathY = nil, nil, nil, nil
	self.wave, self.waveTimer, self.kills = 0, 2.5, 0
	self.fieldId = id
	self.field = assert(Fields[id], "unknown field " .. tostring(id))
	self.arenaRadius = self.field.radius or 10000
	self.well = nil
	self.field.build(self)
	self:spawnPlayer()
	self:toast(self.field.name:upper(), 2)
end

-- F2: the next playing field.
function Game:nextField()
	local i = 1
	for j, id in ipairs(Fields.list) do if id == self.fieldId then i = j end end
	self:loadField(Fields.list[i % #Fields.list + 1])
end

function Game:nextId()
	self.idCounter = self.idCounter + 1
	return self.idCounter
end

-- Spawning -------------------------------------------------------------------

function Game:spawnPlayer(hullId, loadout, cargo)
	if self.player and not self.player.removed then self:remove(self.player) end
	self.playerHull = hullId or self.playerHull
	local sx, sy = self.field.spawn[1], self.field.spawn[2]
	local p = Ship.new(self, { hull = self.playerHull, loadout = loadout, cargo = cargo, team = 1, x = sx, y = sy, angle = -pi / 2, color = self.playerColor })
	p.isPlayer = true
	table.insert(self.entities, p)
	self.player = p
	self.state = "playing"
	self.camera.x, self.camera.y = sx, sy
	return p
end

function Game:spawnEnemy(id, x, y)
	local def = assert(data.enemies[id], "unknown enemy " .. tostring(id))
	local angle = 0
	if self.player and not self.player.dead then
		local px, py = self.player.body:getPosition()
		angle = math.atan2(py - y, px - x)
	end
	local e = Ship.new(self, { hull = def.hull, loadout = def.loadout, cargo = def.cargo, team = 2, x = x, y = y, angle = angle, enemy = def })
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
		if o.kind == "asteroid" or o.kind == "structure" or o.kind == "planet" then
			local ox, oy = o.body:getPosition()
			ox, oy = ox + (o.cx or 0), oy + (o.cy or 0)
			if (ox - x) ^ 2 + (oy - y) ^ 2 < (o.radius + margin) ^ 2 then return false end
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

-- A planet: a static, indestructible disc at the centre of a gravity well.
-- g is the pull at the surface in px/s^2 (falling off with 1/r^2). The
-- well turns: swirl is how hard it drags things toward circling at orbital
-- speed (per second), so loose rocks settle into orbit and ships feel a
-- current around the planet.
function Game:spawnPlanet(x, y, radius, g, swirl)
	local body = love.physics.newBody(self.world, x, y, "static")
	local e = { kind = "planet", invulnerable = true, id = self:nextId(), team = 0, radius = radius, body = body,
		hue = { 0.35 + random() * 0.2, 0.45 + random() * 0.2, 0.7 + random() * 0.2 } }
	local f = love.physics.newFixture(body, love.physics.newCircleShape(radius))
	f:setFriction(0.6)
	f:setRestitution(0.1)
	f:setUserData(e)
	body:setUserData(e)
	table.insert(self.entities, e)
	self.well = { x = x, y = y, radius = radius, gm = g * radius * radius, swirl = swirl }
	return e
end

-- Acceleration from the gravity well on something at (x, y) moving at
-- (vx, vy): the pull toward the centre, plus (if withSwirl) the drag of
-- the turning well toward orbital speed.
function Game:gravityAt(x, y, vx, vy, withSwirl)
	local w = self.well
	if not w then return 0, 0 end
	local dx, dy = w.x - x, w.y - y
	local r = max(sqrt(dx * dx + dy * dy), w.radius)
	local g = T.gravityScale
	local nx, ny = dx / r, dy / r
	local a = w.gm / (r * r) * g
	local ax, ay = nx * a, ny * a
	if withSwirl then
		-- tangent pointing the way the well turns (clockwise on screen)
		local tx, ty = ny, -nx
		local orbit = sqrt(w.gm * g / r)
		local s = (orbit - (vx * tx + vy * ty)) * w.swirl
		ax, ay = ax + tx * s, ay + ty * s
	end
	return ax, ay
end

function Game:applyGravity(dt)
	if not self.well then return end
	for _, e in ipairs(self.entities) do
		local b = e.body
		if not e.removed and b:getType() == "dynamic" then
			local x, y = b:getPosition()
			local vx, vy = b:getLinearVelocity()
			local ax, ay = self:gravityAt(x, y, vx, vy, true)
			local m = b:getMass()
			b:applyForce(ax * m, ay * m)
		end
	end
	for _, p in ipairs(self.projectiles) do
		local ax, ay = self:gravityAt(p.x, p.y)
		p.vx, p.vy = p.vx + ax * dt, p.vy + ay * dt
	end
	for _, p in ipairs(self.pickups) do
		local ax, ay = self:gravityAt(p.x, p.y, p.vx, p.vy, true)
		p.vx, p.vy = p.vx + ax * dt, p.vy + ay * dt
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

function Game:spawnPickup(x, y, item, count)
	local a = random() * pi * 2
	local s = 40 + random() * 120
	table.insert(self.pickups, {
		x = x, y = y, vx = cos(a) * s, vy = sin(a) * s,
		item = item, count = count, spin = random() * pi * 2,
	})
end

function Game:enemyCount()
	local n = 0
	for _, e in ipairs(self.entities) do
		if e.kind == "ship" and e.team == 2 and not e.dead and not e.fleeing then n = n + 1 end
	end
	return n
end

-- Waves: when the arena is clear, the next, bigger wave arrives.
local WAVE_POOL = {
	{ id = "swarmer",     from = 1, weight = 3 },
	{ id = "gunner",      from = 2, weight = 2 },
	{ id = "interceptor", from = 3, weight = 1.2 },
	{ id = "brawler",     from = 4, weight = 1.2 },
	{ id = "sniper",      from = 5, weight = 1 },
}

function Game:spawnWave(n)
	local pool, total = {}, 0
	for _, entry in ipairs(WAVE_POOL) do
		if n >= entry.from and data.enemies[entry.id] then
			table.insert(pool, entry); total = total + entry.weight
		end
	end
	local count = min(1 + n, 9)
	for _ = 1, count do
		local roll = random() * total
		local pick = pool[1]
		for _, entry in ipairs(pool) do
			roll = roll - entry.weight
			if roll <= 0 then pick = entry; break end
		end
		local x, y = self:spawnPoint(1500, 2000)
		self:spawnEnemy(pick.id, x, y)
	end
	self:toast("WAVE " .. n, 2)
end

function Game:updateWaves(dt)
	if not self.wavesOn or self.state ~= "playing" then return end
	if self:enemyCount() == 0 then
		self.waveTimer = self.waveTimer - dt
		if self.waveTimer <= 0 then
			self.wave = self.wave + 1
			self:spawnWave(self.wave)
			self.waveTimer = 4
		end
	end
end

-- Simulation -----------------------------------------------------------------

function Game:setPlayerIntent(intent)
	local p = self.player
	if not p or p.dead then return end
	for k, v in pairs(intent) do p.intent[k] = v end
end

function Game:step(dt)
	self.time = self.time + dt

	for _, e in ipairs(self.entities) do
		if e.kind == "ship" and not e.dead then
			if e.life then
				e.life = e.life - dt
				if e.life <= 0 then e.dead = true end
			end
			if e.def then AI.think(self, e, dt) end
			Ship.fly(e, dt)
			Weapons.update(self, e, dt)
		end
	end

	self:applyBoundary()
	self:applyGravity(dt)
	self.world:update(dt)
	self:resolveContacts()
	Weapons.updateProjectiles(self, dt)
	self:updatePickups(dt)
	self:reap()
	self:updateWaves(dt)
end

-- Soft arena edge: the further past it, the harder you're pushed back.
function Game:applyBoundary()
	local R = self.arenaRadius
	for _, e in ipairs(self.entities) do
		local b = e.body
		local x, y = b:getPosition()
		local d = sqrt(x * x + y * y)
		if d > R and not e.fleeing then
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
		-- Impulse / reduced mass is roughly the impact speed. Slow bumps and
		-- scrapes (below ramSpeed) do nothing; harder hits scale with impulse,
		-- so heavy ships hit harder.
		local ma, mb = c.a.body:getMass(), c.b.body:getMass()
		-- Against something immovable (a station, the giant asteroid) the
		-- reduced mass is just the moving body's own.
		local mu = (ma == 0 or mb == 0) and max(ma, mb) or ma * mb / (ma + mb)
		local impactSpeed = c.imp / max(mu, 1e-6)
		if impactSpeed > self.stats.maxImpactSpeed then self.stats.maxImpactSpeed = impactSpeed end
		if c.imp > self.stats.maxImpulse then self.stats.maxImpulse = c.imp end
		if impactSpeed > T.ramSpeed and c.x then
			local base = c.imp * T.ramDamageScale * (1 - T.ramSpeed / impactSpeed)
			local function ramMult(o) return o.kind == "ship" and o.stats.mult.ramDamage or 1 end
			local function hit(o, other)
				local mult = (o.kind == "asteroid" or o.kind == "husk") and T.asteroidImpact or ramMult(other)
				self:damage(o, base * mult, other, "ram")
			end
			hit(c.a, c.b)
			hit(c.b, c.a)
			self:spark(c.x, c.y, min(14, 3 + floor(base / 4)), { 1, 0.9, 0.7 })
			if c.a == self.player or c.b == self.player then self:shake(min(0.5, base / 40)) end
			events.emit("ram", c.a, c.b, base)
		end
		self.contacts[key] = nil
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
	-- Asteroids and husks don't flinch: they soak damage until they break
	-- apart (in reap).
	if e and e.invulnerable then return end
	if e and (e.kind == "asteroid" or e.kind == "husk") and not e.dead and amount > 0 then
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
function Game:updatePickups(dt)
	local p = self.player
	local alive = p and not p.dead
	local list = self.pickups
	self.hoverPickup = nil

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
		if not it.tractor then
			p.tractorTarget = nil
		elseif not p.tractorTarget then
			p.tractorTarget = best
		end
	end

	local target = alive and p.tractorTarget
	local i = 1
	while i <= #list do
		local k = list[i]
		k.spin = k.spin + dt * 1.5
		local damp = exp(-dt * 1.5)
		k.vx, k.vy = k.vx * damp, k.vy * damp
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
		elseif e.dead and e.kind == "husk" then
			table.remove(self.entities, i)
			local x, y = e.body:getPosition()
			e.body:destroy()
			e.removed = true
			self:explode(x, y, e.halfLength, 0, 0)
			self:spark(x, y, 16, { 0.8, 0.7, 0.6 })
			for id, count in pairs(e.loot) do
				if count > 0 then self:spawnPickup(x, y, id, count) end
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

-- What a dead ship leaves behind: its whole hold (nothing is lost) plus
-- the salvage its enemy definition rolls.
local function lootOf(e)
	local loot = {}
	for id, count in pairs(e.cargo) do
		local item = data.items[id]
		-- Loose ammo is boxed up: crates are cargo to sell or use back at a
		-- station, not something the guns can draw from mid-fight.
		local into = (item and item.kind == "ammo") and item.crate or id
		if count > 0 then loot[into] = (loot[into] or 0) + count end
	end
	local s = e.def and e.def.salvage or { 0, 0 }
	for _ = 1, random(s[1], s[2]) do
		local id = random() < 0.2 and "salvage_kit" or "scrap"
		loot[id] = (loot[id] or 0) + 1
	end
	return loot
end

-- A burnt-out wreck in the dead ship's shape. It drifts and tumbles, holds
-- the ship's loot (for the inventory system to open later), and can be
-- shot apart, which spills the loot as pickups.
function Game:spawnHusk(ship, x, y, a, vx, vy, w)
	local hull = ship.hull
	local body = love.physics.newBody(self.world, x, y, "dynamic")
	local h = {
		kind = "husk", id = self:nextId(), team = 0, hull = hull, color = ship.color,
		spine = ship.spine, noseX = ship.noseX, tailX = ship.tailX, halfLength = ship.halfLength,
		radius = ship.halfLength, body = body, loot = lootOf(ship),
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

function Game:toast(text, duration, style)
	for _, t in ipairs(self.toasts) do
		if t.text == text then t.t = 0; t.life = duration or 1.5; return end
	end
	table.insert(self.toasts, { text = text, t = 0, life = duration or 1.5, style = style })
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
		self.camera:follow(x, y, aimX or x, aimY or y, dt)
	elseif self.playerHusk and not self.playerHusk.removed then
		-- Death screen: watch your own wreck drift.
		local hx, hy = self.playerHusk.body:getPosition()
		self.camera:follow(hx, hy, hx, hy, dt)
	elseif self.deathX then
		self.camera:follow(self.deathX, self.deathY, self.deathX, self.deathY, dt)
	end
end

return Game
