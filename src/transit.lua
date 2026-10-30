--[[
	Getting between planets, and the planets that need more than a disc.

	  drivers   a small mass driver at the edge of a planet map for each
	            route out of it (Fields.links). Fly into its capture ring
	            and, if you can pay the fare, it locks on like a station
	            dock, lines you up on its rail and fires you off. Short of
	            credits, it tells you so and lets you go.
	  lane      the transit lane (the "lane" field): one long straight
	            corridor with a current running both ways, outbound below
	            the median and oncoming above it, like a highway. Nothing
	            stops you drifting into the oncoming side. Haulers cruise
	            both ways, rocks drift through now and then, and once in a
	            while a derelict. Its length comes from how far apart the
	            two planets are right now (Fields.distance). Reach the far
	            end and you come out of the other planet's driver, still
	            going fast.
	  gas giant a planet with no surface: you can fly into it, and the
	            deeper you go the harder it crushes your hull.
	  ladder    the Heaven-Ladder: an orbital ring round Mars with gaps to
	            fly through, held up by space elevators down to the surface.

	Added to Game by src/game.lua: require("src.transit")(Game).
]]

local T = require("src.tuning")
local Ship = require("src.ship")
local Fields = require("src.fields")
local events = require("src.events")

local sqrt, cos, sin, pi, max, min, abs, random = math.sqrt, math.cos, math.sin, math.pi, math.max, math.min, math.abs, love.math.random

return function(Game)

-- Mass drivers ----------------------------------------------------------------

-- Passage to another planet: a base fare plus a little per AU.
function Game:driverFare(to)
	local au = Fields.distance(self.fieldId, to, self.universe.clock)
	return math.floor((T.driverFare + T.driverFarePerAU * au) / 10 + 0.5) * 10
end

-- A driver for each route out of this planet, spaced around the edge and
-- pointing outward. Markers only: nothing collides with them.
function Game:spawnDrivers()
	local links = Fields.linksOf(self.fieldId)
	for i, to in ipairs(links) do
		local a = -pi / 2 + (i - 1) / #links * pi * 2 + 0.6
		local d = self.arenaRadius - 2400
		local x, y = cos(a) * d, sin(a) * d
		for k = #self.entities, 1, -1 do
			local o = self.entities[k]
			if o.kind == "asteroid" then
				local ox, oy = o.body:getPosition()
				if (ox - x) ^ 2 + (oy - y) ^ 2 < (o.radius + T.driverRadius + 1200) ^ 2 then self:remove(o) end
			end
		end
		local body = love.physics.newBody(self.world, x, y, "static")
		local g = { kind = "driver", invulnerable = true, id = self:nextId(), team = 0, body = body,
			radius = T.driverRadius, to = to, name = Fields[to].name, angle = a }
		body:setUserData(g)
		table.insert(self.entities, g)
	end
end

function Game:findDriver(to)
	for _, g in ipairs(self.entities) do
		if g.kind == "driver" and g.to == to then return g end
	end
end

-- Catch the player in a driver's ring, then run the launch: line up on
-- the rail, then fire outward. p.launch = { driver, t } while it runs.
function Game:updateDrivers(dt)
	local p = self.player
	if not p or p.dead or p.dockState then return end
	local L = p.launch
	if L then
		L.t = L.t + dt
		local g = L.driver
		local gx, gy = g.body:getPosition()
		local x, y = p.body:getPosition()
		local dx, dy = cos(g.angle), sin(g.angle)
		p.intent.thrust, p.intent.strafe, p.intent.boost = 0, 0, false
		p.intent.firePrimary, p.intent.fireSecondary, p.intent.fireAux = false, false, false
		local a = p.body:getAngle()
		local diff = (g.angle - a + pi) % (2 * pi) - pi
		p.body:setAngle(a + diff * min(1, dt * 4))
		p.body:setAngularVelocity(0)
		if L.t < T.driverAlign then
			-- reel in to the breech at the rail's inner end
			local bx, by = gx - dx * 500, gy - dy * 500
			p.body:setLinearVelocity((bx - x) * 3, (by - y) * 3)
		else
			local s = T.driverExitSpeed * min(1, (L.t - T.driverAlign) / T.driverFire)
			p.body:setLinearVelocity(dx * s, dy * s)
			if L.t >= T.driverAlign + T.driverFire then self.pendingTrip = g.to end
		end
		return
	end
	p.driverCooldown = max(0, (p.driverCooldown or 0) - dt)
	if p.driverCooldown > 0 then return end
	local x, y = p.body:getPosition()
	for _, g in ipairs(self.entities) do
		if g.kind == "driver" then
			local gx, gy = g.body:getPosition()
			if (x - gx) ^ 2 + (y - gy) ^ 2 < g.radius ^ 2 then
				local fare = self:driverFare(g.to)
				if self.universe.credits < fare then
					self:toast(("PASSAGE TO %s IS %d CR"):format(g.name:upper(), fare), 2)
					p.driverCooldown = 3
				else
					self.universe.credits = self.universe.credits - fare
					p.launch = { driver = g, t = 0 }
					self:toast(("DRIVER LOCK  -%d CR"):format(fare), 1.6)
				end
				return
			end
		end
	end
end

-- Into the transit lane toward planet `to`, in the ship you're flying.
function Game:launchTrip(to)
	local p = self.player
	if not p or p.dead then return end
	local from = self.fieldId
	local au = Fields.distance(from, to, self.universe.clock)
	self.trip = { from = from, to = to, au = au, length = T.laneBase + T.lanePerAU * au }
	local half = self.trip.length / 2
	self:loadField("lane", { player = Ship.record(p),
		at = { x = -half + 600, y = -T.laneWidth / 2, angle = 0, vx = T.driverExitSpeed, vy = 0 } })
	self:toast(("%s TO %s  %.2f AU"):format(Fields[from].name:upper(), Fields[to].name:upper(), au), 3)
	events.emit("travel", from, to)
end

-- Out of the far end of the lane at the other planet's driver, moving fast.
function Game:arrive()
	local p, trip = self.player, self.trip
	if not p or p.dead or not trip then return end
	self.trip = nil
	self:loadField(trip.to, { player = Ship.record(p), at = { driver = trip.from } })
end

-- Out of driver `from` heading inward at the driver's exit speed.
function Game:placeAtDriver(p, from)
	local g = self:findDriver(from)
	if not g then return false end
	local gx, gy = g.body:getPosition()
	local ix, iy = -cos(g.angle), -sin(g.angle)
	p.body:setPosition(gx + ix * (T.driverRadius + 300), gy + iy * (T.driverRadius + 300))
	p.body:setAngle(math.atan2(iy, ix))
	p.body:setLinearVelocity(ix * T.driverExitSpeed, iy * T.driverExitSpeed)
	p.driverCooldown = T.driverCooldown
	self.camera.x, self.camera.y = p.body:getPosition()
	return true
end

-- The transit lane -----------------------------------------------------------

-- The lane's current at height y: outbound (+x) below the median,
-- oncoming above it, easing through zero across the median.
function Game:laneFlow(y)
	return T.laneFlow * max(-1, min(1, -y / T.laneMedian))
end

function Game:buildLane()
	if not self.trip then
		-- reached from the debug panel: a lane from Earth to Mars
		local au = Fields.distance("earth", "mars", self.universe.clock)
		self.trip = { from = "earth", to = "mars", au = au, length = T.laneBase + T.lanePerAU * au }
	end
	self.lane = { half = self.trip.length / 2, spawnT = 0 }
	self.arenaRadius = self.lane.half
end

-- Keep traffic, rocks and the odd derelict going around the player, and
-- clear away what's fallen far behind or ahead.
function Game:updateLane(dt)
	local lane, p = self.lane, self.player
	if not lane then return end
	local half, W = lane.half, T.laneWidth
	-- the current, and the corridor's walls
	for _, e in ipairs(self.entities) do
		local b = e.body
		if not e.removed and b:getType() == "dynamic" then
			local x, y = b:getPosition()
			local vx, vy = b:getLinearVelocity()
			local f = self:laneFlow(y)
			local m = b:getMass()
			if e.kind == "ship" then
				e.flowX, e.flowY = f, 0
			else
				b:applyForce((f - vx) * T.laneSwirl * m, -vy * T.laneSwirl * m)
			end
			local over = abs(y) - W
			if over > 0 then b:applyForce(0, -(y > 0 and 1 or -1) * over * m * 6) end
			if x < -half then b:applyForce((-half - x) * m * 6, 0) end
		end
	end
	if not p or p.dead then return end
	local px = p.body:getPosition()
	if px > half - 400 and not p.launch then self.pendingArrive = true end
	-- recycle what's out of reach
	local traffic, rocks, gone = 0, 0, {}
	for _, e in ipairs(self.entities) do
		if not e.removed and e ~= p and e.body:getType() == "dynamic" then
			local x = e.body:getPosition()
			if abs(x - px) > T.laneReach * 1.3 then
				table.insert(gone, e)
			elseif e.lane == "traffic" then traffic = traffic + 1
			elseif e.lane == "rock" then rocks = rocks + 1 end
		end
	end
	for _, e in ipairs(gone) do self:remove(e) end
	-- new arrivals, off screen ahead or behind
	lane.spawnT = lane.spawnT - dt
	if lane.spawnT > 0 then return end
	lane.spawnT = 0.25
	local side = random() < 0.5 and -1 or 1
	local y = side * (0.15 + random() * 0.75) * W
	local x = px + (random() < 0.6 and 1 or -1) * (T.laneReach * (0.35 + random() * 0.6))
	if x < -half + 500 or x > half - 500 or not self:isClear(x, y, 300) then return end
	local f = self:laneFlow(y)
	if traffic < T.laneTraffic then
		local e = self:spawnEnemy("freighter", x, y)
		e.cruise, e.lane = true, "traffic"
		e.body:setAngle(f > 0 and 0 or pi)
		e.body:setLinearVelocity(f, 0)
	elseif rocks < T.laneRocks and random() < 0.5 then
		local e = self:spawnAsteroid(x, y, 30 + random() ^ 2 * 90)
		e.lane = "rock"
		e.body:setLinearVelocity(f, 0)
	elseif random() < T.laneDerelict then
		-- a derelict: a hauler that didn't make it, hold and all
		local e = self:spawnEnemy("freighter", x, y)
		e.body:setLinearVelocity(f, 0)
		self:damage(e, 1e9, nil, "derelict")
	end
end

-- Traffic just rides the current, nose along the lane.
function Game:cruise(e)
	local x, y = e.body:getPosition()
	local f = self:laneFlow(y)
	local it = e.intent
	it.thrust, it.strafe = 0, 0
	it.aimX, it.aimY = x + (f >= 0 and 1000 or -1000), y
end

-- Gas giants -----------------------------------------------------------------

-- A gas giant: the same turning field as a planet, but nothing solid at
-- the middle. Inside its radius the crush builds with depth.
function Game:spawnGasGiant(x, y, radius, flow, swirl)
	local body = love.physics.newBody(self.world, x, y, "static")
	local e = { kind = "planet", gas = true, invulnerable = true, id = self:nextId(), team = 0, radius = radius, body = body,
		hue = { 0.85, 0.65, 0.45 } }
	body:setUserData(e)
	table.insert(self.entities, e)
	self.well = { x = x, y = y, radius = radius, flow = flow, swirl = swirl, gas = true, planet = e }
	return e
end

function Game:updateCrush(dt)
	local w = self.well
	if not w or not w.gas then return end
	for _, e in ipairs(self.entities) do
		local b = e.body
		if not e.removed and not e.dead and b:getType() == "dynamic" then
			local x, y = b:getPosition()
			local r = sqrt((x - w.x) ^ 2 + (y - w.y) ^ 2)
			local depth = (w.radius - r) / T.crushDepth
			if depth > 0 then
				depth = min(1, depth)
				local vx, vy = b:getLinearVelocity()
				local m = b:getMass()
				b:applyForce(-vx * T.crushDrag * depth * m, -vy * T.crushDrag * depth * m)
				if e.kind == "ship" then
					self:damage(e, T.crushDamage * depth * depth * dt, nil, "crushed")
					if e == self.player and (self.crushWarn or 0) < self.time then
						self.crushWarn = self.time + 3
						self:toast(depth > 0.5 and "HULL BUCKLING" or "PRESSURE RISING", 1.4)
					end
				elseif depth > 0.6 then
					self:remove(e)
				end
			end
		end
	end
end

-- The Heaven-Ladder ----------------------------------------------------------

-- An orbital ring of radius R round (cx, cy), cut by gaps to fly through,
-- with four space elevators running from it down to the surface.
function Game:spawnHeavenLadder(cx, cy, R)
	local w = self.well
	local surface = w and w.radius or R - 1000
	local thick, gaps, gapW = 50, 8, 700
	local gapA = gapW / R
	for i = 0, gaps - 1 do
		local a1 = (i + 0.5) / gaps * pi * 2 + gapA / 2
		local a2 = (i + 1.5) / gaps * pi * 2 - gapA / 2
		local n = math.ceil((a2 - a1) * R / 400)
		for k = 0, n - 1 do
			local b1, b2 = a1 + (a2 - a1) * k / n, a1 + (a2 - a1) * (k + 1) / n
			self:addStructure({
				cx + cos(b1) * (R - thick), cy + sin(b1) * (R - thick),
				cx + cos(b2) * (R - thick), cy + sin(b2) * (R - thick),
				cx + cos(b2) * (R + thick), cy + sin(b2) * (R + thick),
				cx + cos(b1) * (R + thick), cy + sin(b1) * (R + thick),
			}, { role = "ladder" })
		end
	end
	-- the elevators, at the middle of every other arc
	for i = 0, 3 do
		local a = (i * 2 + 1) / gaps * pi * 2
		local ux, uy, nx, ny = cos(a), sin(a), -sin(a), cos(a)
		local tw = 24
		self:addStructure({
			cx + ux * surface + nx * tw, cy + uy * surface + ny * tw,
			cx + ux * (R - thick) + nx * tw, cy + uy * (R - thick) + ny * tw,
			cx + ux * (R - thick) - nx * tw, cy + uy * (R - thick) - ny * tw,
			cx + ux * surface - nx * tw, cy + uy * surface - ny * tw,
		}, { role = "tether" })
		local hw = 140
		self:addStructure({
			cx + ux * (R - 120) + nx * hw, cy + uy * (R - 120) + ny * hw,
			cx + ux * (R + 120) + nx * hw, cy + uy * (R + 120) + ny * hw,
			cx + ux * (R + 120) - nx * hw, cy + uy * (R + 120) - ny * hw,
			cx + ux * (R - 120) - nx * hw, cy + uy * (R - 120) - ny * hw,
		}, { role = "hub" })
	end
end

end
