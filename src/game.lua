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

	self:spawnAsteroids(60)
	self:spawnPlayer()
	return self
end

function Game:nextId()
	self.idCounter = self.idCounter + 1
	return self.idCounter
end

-- Spawning -------------------------------------------------------------------

function Game:spawnPlayer(hullId, loadout, cargo)
	if self.player and not self.player.removed then self:remove(self.player) end
	self.playerHull = hullId or self.playerHull
	local p = Ship.new(self, { hull = self.playerHull, loadout = loadout, cargo = cargo, team = 1, x = 0, y = 0, angle = -pi / 2, color = self.playerColor })
	p.isPlayer = true
	table.insert(self.entities, p)
	self.player = p
	self.state = "playing"
	self.camera.x, self.camera.y = 0, 0
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

-- A point a given distance from the player, kept inside the arena.
function Game:spawnPoint(minD, maxD)
	local cx, cy = 0, 0
	if self.player and not self.player.dead then cx, cy = self.player.body:getPosition() end
	for _ = 1, 20 do
		local a = random() * pi * 2
		local d = minD + random() * (maxD - minD)
		local x, y = cx + cos(a) * d, cy + sin(a) * d
		if x * x + y * y < (self.arenaRadius - 200) ^ 2 then return x, y end
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
	body:setLinearDamping(0.25)
	body:setAngularDamping(0.2)
	body:setAngularVelocity((random() - 0.5) * 0.6)
	body:setLinearVelocity((random() - 0.5) * 20, (random() - 0.5) * 20)
	local e = { kind = "asteroid", id = self:nextId(), team = 0, radius = radius, verts = verts, body = body, fixture = fixture, shade = 0.55 + random() * 0.25 }
	fixture:setUserData(e)
	body:setUserData(e)
	table.insert(self.entities, e)
	return e
end

function Game:spawnAsteroids(n)
	local placed = 0
	for _ = 1, n * 10 do
		if placed >= n then break end
		local radius = 28 + random() ^ 2 * 100
		local a = random() * pi * 2
		local d = 450 + random() * (self.arenaRadius - 600)
		local x, y = cos(a) * d, sin(a) * d
		local clear = true
		for _, o in ipairs(self.entities) do
			if o.kind == "asteroid" then
				local ox, oy = o.body:getPosition()
				if (ox - x) ^ 2 + (oy - y) ^ 2 < (o.radius + radius + 60) ^ 2 then clear = false; break end
			end
		end
		if clear then self:spawnAsteroid(x, y, radius); placed = placed + 1 end
	end
end

function Game:spawnPickup(x, y, item, count)
	local a = random() * pi * 2
	local s = 40 + random() * 120
	table.insert(self.pickups, {
		x = x, y = y, vx = cos(a) * s, vy = sin(a) * s,
		item = item, count = count, life = 60, spin = random() * pi * 2, rejectUntil = 0,
	})
end

function Game:enemyCount()
	local n = 0
	for _, e in ipairs(self.entities) do
		if e.kind == "ship" and e.team == 2 and not e.dead then n = n + 1 end
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
			if e.def then AI.think(self, e, dt) end
			Ship.fly(e, dt)
			Weapons.update(self, e, dt)
		end
	end

	self:applyBoundary()
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
		if d > R then
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
		local mu = ma * mb / (ma + mb)
		local impactSpeed = c.imp / max(mu, 1e-6)
		if impactSpeed > self.stats.maxImpactSpeed then self.stats.maxImpactSpeed = impactSpeed end
		if c.imp > self.stats.maxImpulse then self.stats.maxImpulse = c.imp end
		if impactSpeed > T.ramSpeed and c.x then
			local base = c.imp * T.ramDamageScale * (1 - T.ramSpeed / impactSpeed)
			local function ramMult(o) return o.kind == "ship" and o.stats.mult.ramDamage or 1 end
			if c.a.kind == "ship" then self:damage(c.a, base * ramMult(c.b), c.b, "ram") end
			if c.b.kind == "ship" then self:damage(c.b, base * ramMult(c.a), c.a, "ram") end
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
	if not e or e.kind ~= "ship" or e.dead or amount <= 0 then return end
	if source and source.def then amount = amount * T.enemyDamage end   -- difficulty knob
	e.flash = 0.08
	if e.isPlayer and T.dev.god then return end
	e.armor = e.armor - amount
	e.lastHitBy = source
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
				if d > 1 then
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

function Game:updatePickups(dt)
	local p = self.player
	local alive = p and not p.dead
	local px, py, pull
	if alive then
		px, py = p.body:getPosition()
		pull = 80 + (p.stats.tractorRange or 0)
	end
	local list = self.pickups
	local i = 1
	while i <= #list do
		local k = list[i]
		k.life = k.life - dt
		k.spin = k.spin + dt * 1.5
		local damp = exp(-dt * 1.5)
		k.vx, k.vy = k.vx * damp, k.vy * damp
		local remove = k.life <= 0
		if alive and not remove and self.time >= k.rejectUntil then
			local dx, dy = px - k.x, py - k.y
			local d = sqrt(dx * dx + dy * dy)
			if d < pull and d > 0 then
				local a = 700 + (p.stats.tractorRange or 0) * 3
				k.vx, k.vy = k.vx + dx / d * a * dt, k.vy + dy / d * a * dt
			end
			if Ship.distanceTo(p, k.x, k.y) < 10 then
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
					k.rejectUntil = self.time + 2.5
					k.vx, k.vy = -dx / d * 160, -dy / d * 160
				end
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

-- Remove dead ships: explode, drop what they carried, count the kill.
function Game:reap()
	local i = 1
	while i <= #self.entities do
		local e = self.entities[i]
		if e.dead then
			local x, y = e.body:getPosition()
			self:explode(x, y, e.halfLength * 1.6, 0, 3000)
			self:spark(x, y, 24, { 1, 0.6, 0.3 })
			if e.def then
				self.kills = self.kills + 1
				self:dropLoot(e, x, y)
			end
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
		else
			i = i + 1
		end
	end
end

function Game:dropLoot(e, x, y)
	local def = e.def
	for id, count in pairs(e.cargo) do
		local item = data.items[id]
		if item and item.kind == "ammo" and count > 0 then
			local n = floor(count * (def.ammoDrop or 0.3) * (0.6 + random() * 0.4))
			if n > 0 then self:spawnPickup(x, y, id, n) end
		end
	end
	local s = def.salvage or { 0, 0 }
	for _ = 1, random(s[1], s[2]) do
		self:spawnPickup(x, y, random() < 0.2 and "salvage_kit" or "scrap", 1)
	end
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
	elseif self.deathX then
		self.camera:follow(self.deathX, self.deathY, self.deathX, self.deathY, dt)
	end
end

return Game
