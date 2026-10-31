--[[
	Getting between planets, and the planets that need more than a disc.

	  drivers   a small mass driver at the edge of each planet map. Fly
	            into its capture ring and it holds you at the breech and
	            opens its targeting window (src/ui/orrery.lua): the planets
	            where they are now, with the distance and fare to each.
	            Pick one and pay, and it lines you up on its rail and fires
	            you off; back out and it lets you go.
	  flight    once fired, you're a projectile: the trip is a short view of
	            the orrery with your dot arcing to the target (src/ui/
	            transitview.lua) while the game clock runs on, then you
	            arrive far out from the destination's driver, still fast.
	  catch     the destination's driver catches you: a line of braking
	            rings leads in to it, each one bleeding off part of your
	            speed. Reach the driver slow enough and it holds you; too
	            fast and you shoot past into the planet map on your own.
	  lane      the old transit lane, kept as a race track for later (the
	            "lane" field, from the debug panel): one long
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

-- One driver per planet map, at the edge of the map and pointing
-- outward. A marker only: nothing collides with it.
function Game:spawnDrivers()
	if not Fields.orbits[self.fieldId] then return end
	-- right at the edge of the map, barrel pointing out of it
	local a = -pi / 2 + 0.6
	local d = self.arenaRadius - T.driverBarrel - 100
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
		radius = T.driverRadius, name = "Mass driver", angle = a }
	body:setUserData(g)
	table.insert(self.entities, g)
	self:spawnCatchRings()
end

-- A point in a driver's frame: lx along the barrel (the breech at 0, the
-- approach behind it negative), ly across it.
local function driverLocal(g, x, y)
	local gx, gy = g.body:getPosition()
	local dx, dy = cos(g.angle), sin(g.angle)
	local rx, ry = x - gx, y - gy
	return rx * dx + ry * dy, -rx * dy + ry * dx
end

function Game:findDriver()
	for _, g in ipairs(self.entities) do
		if g.kind == "driver" then return g end
	end
end

-- Pay the fare to planet `to` and start the launch (from the driver's
-- targeting window, src/ui/orrery.lua).
function Game:fireDriver(to)
	local menu, p = self.driverMenu, self.player
	if not menu or not p or p.dead then return false end
	local fare = self:driverFare(to)
	if self.universe.credits < fare then
		self:toast(("PASSAGE TO %s IS %d CR"):format(Fields[to].name:upper(), fare), 2)
		return false
	end
	self.universe.credits = self.universe.credits - fare
	self.driverMenu = nil
	p.launch = { driver = menu.driver, to = to, t = 0 }
	self:toast(("FIRING FOR %s  -%d CR"):format(Fields[to].name:upper(), fare), 1.6)
	return true
end

-- Back out of the targeting window: you drift free of the ring.
function Game:closeDriverMenu()
	local p = self.player
	self.driverMenu = nil
	if p then p.driverCooldown = T.driverCooldown end
end

-- Catch the player in the driver's ring and hold them at the breech while
-- the targeting window is up; then run the launch: line up on the rail
-- and fire outward. p.launch = { driver, to, t } while it runs.
function Game:updateDrivers(dt)
	local p = self.player
	if not p or p.dead or p.dockState then self.driverMenu = nil return end
	local L = p.launch
	local menu = self.driverMenu
	if L or menu then
		local g = (L or menu).driver
		local gx, gy = g.body:getPosition()
		local x, y = p.body:getPosition()
		local dx, dy = cos(g.angle), sin(g.angle)
		p.intent.thrust, p.intent.strafe, p.intent.boost = 0, 0, false
		p.intent.firePrimary, p.intent.fireSecondary, p.intent.fireAux = false, false, false
		local a = p.body:getAngle()
		local diff = (g.angle - a + pi) % (2 * pi) - pi
		p.body:setAngle(a + diff * min(1, dt * 4))
		p.body:setAngularVelocity(0)
		if menu or L.t < T.driverAlign then
			if L then L.t = L.t + dt end
			-- held in the breech
			p.body:setLinearVelocity((gx - x) * 3, (gy - y) * 3)
		else
			L.t = L.t + dt
			-- down the barrel, harder and harder, engine lit
			local u = min(1, (L.t - T.driverAlign) / T.driverFire)
			local s = T.driverExitSpeed * u * u
			p.body:setLinearVelocity(dx * s, dy * s)
			p.intent.thrust, p.intent.boost = 1, true
			self:shake(0.08 * u)
			if L.t >= T.driverAlign + T.driverFire then self.pendingFlight = L.to end
		end
		return
	end
	if p.driverTractor then return self:updateDriverTractor(p, dt) end
	p.driverCooldown = max(0, (p.driverCooldown or 0) - dt)
	if p.driverCooldown > 0 then return end
	local g = self:findDriver()
	if not g then return end
	local lx, ly = driverLocal(g, p.body:getPosition())
	if lx < 0 and lx > -T.driverZone and math.abs(ly) < T.driverZoneWidth then
		p.driverTractor = { driver = g, t = 0 }
		self:toast("TRACTOR LOCK", 1.4)
	end
end

-- The approach, like a station's runway: fly into the zone behind the
-- breech and the beam takes over, easing you onto the centre line, nose
-- along the barrel, and drawing you in, gently at first and firmer near
-- the breech. Its grip has a limit (driverGrip, px/s^2), so come in too
-- fast and you sail straight through the breech and out the far side.
function Game:updateDriverTractor(p, dt)
	local tr = p.driverTractor
	local g = tr.driver
	tr.t = tr.t + dt
	local x, y = p.body:getPosition()
	local lx, ly = driverLocal(g, x, y)
	local dx, dy = cos(g.angle), sin(g.angle)
	local nx, ny = -dy, dx
	p.intent.thrust, p.intent.strafe, p.intent.boost = 0, 0, false
	p.intent.firePrimary, p.intent.fireSecondary, p.intent.fireAux = false, false, false
	if lx > 150 or math.abs(ly) > T.driverZoneWidth * 1.5 or lx < -T.driverZone * 1.2 then
		-- overshot the breech, or slid out of the beam
		p.driverTractor = nil
		p.driverCooldown = 3
		self:toast(lx > 150 and "OVERSHOT THE BREECH: TOO FAST" or "TRACTOR LOST", 1.8)
		return
	end
	local vx, vy = p.body:getLinearVelocity()
	if lx > -120 and math.abs(ly) < 120 and vx * vx + vy * vy < 250 ^ 2 then
		p.driverTractor = nil
		self.driverMenu = { driver = g }
		self:toast("DRIVER LOCK", 1.2)
		return
	end
	local near = 1 - max(0, min(1, -lx / T.driverZone))
	local grip = min(1, tr.t / 1.0) * (0.35 + 0.65 * near)
	local gap = -lx
	local inward = min(T.driverReel, max(60, gap * 0.6))
	local wx, wy = dx * inward - nx * ly * 0.8, dy * inward - ny * ly * 0.8
	local ax, ay = (wx - vx) * 2.2 * grip, (wy - vy) * 2.2 * grip
	local a = math.sqrt(ax * ax + ay * ay)
	local cap = T.driverGrip * (0.5 + 0.5 * grip)
	if a > cap then ax, ay = ax / a * cap, ay / a * cap end
	local m = p.body:getMass()
	p.body:applyForce(ax * m, ay * m)
	-- nose down the barrel
	local turn = ((g.angle - p.body:getAngle() + pi) % (2 * pi) - pi) * 1.4 * grip
	local w = p.body:getAngularVelocity()
	p.body:setAngularVelocity(w + (turn - w) * min(1, 3 * dt))
end

-- In flight to planet `to`: the trip is the transit view, game.flight =
-- { from, to, au, t, dur }, while the world waits. Game:step runs it.
function Game:beginFlight(to)
	local p = self.player
	if not p or p.dead then return end
	local from = self.fieldId
	local au = Fields.distance(from, to, self.universe.clock)
	p.launch = nil
	self.flight = { from = from, to = to, au = au, t = 0, dur = T.flightBase + T.flightPerAU * au,
		ship = Ship.record(p) }
	events.emit("travel", from, to)
end

function Game:updateFlight(dt)
	local f = self.flight
	f.t = f.t + dt
	if f.t < f.dur then return end
	self.flight, self.lastFlight = nil, f
	self.universe.clock = self.universe.clock + T.flightClockPerAU * f.au
	self:loadField(f.to, { player = f.ship, at = { catch = true } })
end

-- Arriving: far out along the driver's rail, beyond the last ring, coming
-- in fast and roughly lined up, with a little error to correct.
function Game:placeForCatch(p)
	local g = self:findDriver()
	if not g then return false end
	local gx, gy = g.body:getPosition()
	local ox, oy = cos(g.angle), sin(g.angle)
	local d = math.floor(T.catchRings + 0.5) * T.catchSpacing + T.catchApproach
	local off = (random() * 2 - 1) * T.catchOffset
	local x, y = gx + ox * d - oy * off, gy + oy * d + ox * off
	local err = (random() * 2 - 1) * 0.04
	local ia = g.angle + pi + err
	p.body:setPosition(x, y)
	self.camera.x, self.camera.y = x, y
	p.body:setAngle(ia)
	p.body:setLinearVelocity(cos(ia) * T.catchSpeed, sin(ia) * T.catchSpeed)
	p.catching, p.coasting = true, true
	p.driverCooldown = 0
	for _, e in ipairs(self.entities) do if e.kind == "catchring" then e.passed = nil end end
	self.camera.x, self.camera.y = x, y
	self:toast(("INBOUND  %s CATCHER"):format(self.field.name:upper()), 2.5)
	return true
end

-- The braking rings out along the driver's rail, nearest first.
function Game:spawnCatchRings()
	local g = self:findDriver()
	if not g then return end
	local gx, gy = g.body:getPosition()
	local ox, oy = cos(g.angle), sin(g.angle)
	for k = 1, math.floor(T.catchRings + 0.5) do
		local d = k * T.catchSpacing
		local body = love.physics.newBody(self.world, gx + ox * d, gy + oy * d, "static")
		local e = { kind = "catchring", invulnerable = true, id = self:nextId(), team = 0, body = body,
			radius = T.catchRingRadius, index = k, angle = g.angle }
		body:setUserData(e)
		table.insert(self.entities, e)
	end
end

-- The next ring you'll come to on the way in (the furthest out not yet
-- passed), or nil.
function Game:nextCatchRing()
	local best
	for _, e in ipairs(self.entities) do
		if e.kind == "catchring" and not e.passed and (not best or e.index > best.index) then best = e end
	end
	return best
end

-- Through a ring: it bleeds off speed. Into the driver: caught if slow
-- enough, else you're through and on your own.
function Game:updateCatch(dt)
	local p = self.player
	if not p or p.dead then return end
	if p.coasting then
		-- a projectile: no drag (Ship.fly) until you're down to catching
		-- speed, but the planet's current still pushes you off your line
		local vx, vy = p.body:getLinearVelocity()
		if not p.catching and vx * vx + vy * vy < T.catchBaySpeed ^ 2 then p.coasting = nil end
		local m = p.body:getMass()
		p.body:applyForce((p.flowX or 0) * T.catchDrift * m, (p.flowY or 0) * T.catchDrift * m)
	end
	if not p.catching then return end
	local x, y = p.body:getPosition()
	for _, e in ipairs(self.entities) do
		if e.kind == "catchring" and not e.passed then
			local ex, ey = e.body:getPosition()
			if (x - ex) ^ 2 + (y - ey) ^ 2 < e.radius ^ 2 then
				e.passed = true
				local vx, vy = p.body:getLinearVelocity()
				local k = 1 - T.catchBrake
				p.body:setLinearVelocity(vx * k, vy * k)
				self:spark(x, y, 14, { 0.6, 0.95, 1 })
				self:shake(6)
				self:toast(("BRAKE %d  %d px/s"):format(e.index, sqrt(vx * vx + vy * vy) * k), 1.2)
			end
		end
	end
	local g = self:findDriver()
	if not g then p.catching = nil return end
	local gx, gy = g.body:getPosition()
	local vx, vy = p.body:getLinearVelocity()
	local speed = sqrt(vx * vx + vy * vy)
	local d2 = (x - gx) ^ 2 + (y - gy) ^ 2
	if d2 < (g.radius + 300) ^ 2 then
		p.catching = nil
		if speed <= T.catchBaySpeed then
			-- caught: matched to the current, like any ship idling here
			p.coasting = nil
			p.body:setLinearVelocity(p.flowX or 0, p.flowY or 0)
			p.driverCooldown = T.driverCooldown
			self:toast("CAUGHT", 2, "pickup", true)
		else
			p.driverCooldown = T.driverCooldown
			self:toast(("MISSED THE CATCH  %d px/s"):format(speed), 2.5)
			self:shake(10)
		end
	else
		-- went wide: once you're inside the driver, you're on your own
		local ox, oy = cos(g.angle), sin(g.angle)
		if (x - gx) * ox + (y - gy) * oy < -1500 then
			p.catching = nil
			self:toast("MISSED THE CATCH", 2.5)
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
	local Rc = max(T.laneArc, self.trip.length * 0.9)
	local s0, n0 = -self.trip.length / 2 + 600, -T.laneWidth / 2
	local phi = s0 / Rc
	local x, y = sin(phi) * (Rc - n0), Rc - cos(phi) * (Rc - n0)
	self:loadField("lane", { player = Ship.record(p),
		at = { x = x, y = y, angle = phi, vx = cos(phi) * T.laneEntrySpeed, vy = sin(phi) * T.laneEntrySpeed } })
	self:toast(("%s TO %s  %.2f AU"):format(Fields[from].name:upper(), Fields[to].name:upper(), au), 3)
	events.emit("travel", from, to)
end

-- Out of the far end of the lane at the other planet's driver, moving fast.
function Game:arrive()
	local p, trip = self.player, self.trip
	if not p or p.dead or not trip then return end
	-- keep your heading and velocity relative to the lane: along it
	-- becomes in from the driver
	local x, y = p.body:getPosition()
	local _, _, phi = self:toLane(x, y)
	local vx, vy = p.body:getLinearVelocity()
	local tx, ty = cos(phi), sin(phi)
	local exit = { along = vx * tx + vy * ty, across = -vx * ty + vy * tx, turn = p.body:getAngle() - phi }
	self.trip = nil
	self:loadField(trip.to, { player = Ship.record(p), at = { driver = trip.from, exit = exit } })
end

-- Out of this planet's driver heading inward, at the driver's exit speed,
-- or as you left the lane (exit = { along, across, turn }).
function Game:placeAtDriver(p, exit)
	local g = self:findDriver()
	if not g then return false end
	local gx, gy = g.body:getPosition()
	local ix, iy = -cos(g.angle), -sin(g.angle)
	local a = math.atan2(iy, ix)
	local along, across, turn = T.laneEntrySpeed, 0, 0
	if exit then along, across, turn = exit.along, exit.across, exit.turn end
	p.body:setPosition(gx + ix * (T.driverRadius + 300), gy + iy * (T.driverRadius + 300))
	p.body:setAngle(a + turn)
	p.body:setLinearVelocity(ix * along - iy * across, iy * along + ix * across)
	p.driverCooldown = T.driverCooldown
	self.camera.x, self.camera.y = p.body:getPosition()
	return true
end

-- The transit lane -----------------------------------------------------------

-- The lane is a slight arc: a circle of radius lane.R round (0, lane.R),
-- passing through the origin heading +x and bending down the screen. In
-- lane coordinates s is the distance along it and n the offset from its
-- median (negative: the outbound side). Holding a straight line drifts
-- you across it.
function Game:toLane(x, y)
	local R = self.lane.R
	local dx, dy = x, y - R
	local phi = math.atan2(dx, -dy)
	return phi * R, R - sqrt(dx * dx + dy * dy), phi
end

function Game:fromLane(s, n)
	local R = self.lane.R
	local phi = s / R
	return sin(phi) * (R - n), R - cos(phi) * (R - n)
end

-- The lane's current at offset n: outbound below the median, oncoming
-- above it, easing through zero across the median.
function Game:laneFlow(n)
	return T.laneFlow * max(-1, min(1, -n / T.laneMedian)) * self:laneStrength(n)
end

-- How much of the lane there is at offset n: full inside it, fading out
-- over T.laneRamp past its edge (the buff and the current alike).
function Game:laneStrength(n)
	local out = abs(n) - T.laneWidth
	if out <= 0 then return 1 end
	if T.laneRamp <= 0 then return 0 end
	return max(0, 1 - out / T.laneRamp)
end

function Game:buildLane()
	if not self.trip then
		-- reached from the debug panel: a lane from Earth to Mars
		local au = Fields.distance("earth", "mars", self.universe.clock)
		self.trip = { from = "earth", to = "mars", au = au, length = T.laneBase + T.lanePerAU * au }
	end
	self.lane = { half = self.trip.length / 2, R = max(T.laneArc, self.trip.length * 0.9), spawnT = 0 }
	self.arenaRadius = 1e7
end

-- What turns up in the lane, with weights. cruise: rides the current.
local LANE_TRAFFIC = {
	{ "freighter", 2 },
	{ "packhorse_trader", 2 },
	{ "runner_trader", 2 },
	{ "gunner", 2, neutral = true },       -- couriers and private craft
	{ "brawler", 1, neutral = true },
	{ "interceptor", 1, neutral = true },
	{ "gunner", 0.4, raider = true },      -- raiders working the lane
}

local function pick(list)
	local total = 0
	for _, t in ipairs(list) do total = total + t[2] end
	local r = random() * total
	for _, t in ipairs(list) do
		r = r - t[2]
		if r <= 0 then return t end
	end
	return list[1]
end

-- The current, the walls, the lane buff, and what turns up: kept going
-- around the player, cleared away once it falls far behind or ahead.
function Game:updateLane(dt)
	local lane, p = self.lane, self.player
	if not lane then return end
	local W = T.laneWidth
	for _, e in ipairs(self.entities) do
		local b = e.body
		if not e.removed and b:getType() == "dynamic" then
			local x, y = b:getPosition()
			local vx, vy = b:getLinearVelocity()
			local s, n, phi = self:toLane(x, y)
			local tx, ty = cos(phi), sin(phi)
			local f = self:laneFlow(n)
			local m = b:getMass()
			if e.kind == "ship" then
				-- in the lane: the buff (thrust up, drag down); traffic also
				-- rides the current and is held on the curve
				local k = self:laneStrength(n)
				e.laneBuff = k > 0 and k or nil
				if e.lane then
					local v = f * (e.cruiseSpeed or 1)
					e.flowX, e.flowY = tx * v, ty * v
					local c = (vx * tx + vy * ty) ^ 2 / lane.R
					b:applyForce(sin(phi) * -c * m, cos(phi) * c * m)
					-- now and then a traveller drifts across into the other side
					if e.cruise and not e.veer and random() < T.laneVeer * dt then
						e.veer = { t = 3 + random() * 3, dir = n > 0 and -1 or 1 }
					end
					if e.veer then
						e.veer.t = e.veer.t - dt
						local push = e.veer.dir * 260 * m
						b:applyForce(-sin(phi) * push, cos(phi) * push)
						if e.veer.t <= 0 then e.veer = nil end
					end
				end
			elseif e.lane ~= "offroad" then
				-- carried along the lane; anything drifting across keeps drifting
				local va = vx * tx + vy * ty
				local c = va * va / lane.R
				local a = (f - va) * T.laneSwirl
				b:applyForce((tx * a - sin(phi) * c) * m, (ty * a + cos(phi) * c) * m)
			end
			-- soft walls well outside the lane, and the near end
			local over = abs(n) - (W + T.laneRamp + 2500)
			if over > 0 then
				local k = (n > 0 and 1 or -1) * over * m * 4
				b:applyForce(sin(phi) * k, -cos(phi) * k)
			end
			if s < -lane.half then b:applyForce(tx * (-lane.half - s) * m * 6, ty * (-lane.half - s) * m * 6) end
		end
	end
	if not p or p.dead then return end
	local ps = self:toLane(p.body:getPosition())
	if ps > lane.half - 400 and not p.launch then self.pendingArrive = true end
	-- off-road rocks, scattered either side all along: a field to fill
	-- once, then topped up at the edge of reach as you go
	if not lane.filled then
		lane.filled = true
		for _ = 1, T.laneOffroad * 2 do self:spawnOffroadRock(ps + (random() * 2 - 1) * T.laneReach, ps) end
	end
	local traffic, rocks, offroad, gone = 0, 0, 0, {}
	for _, e in ipairs(self.entities) do
		if not e.removed and e ~= p and e.body:getType() == "dynamic" then
			local s = self:toLane(e.body:getPosition())
			if abs(s - ps) > T.laneReach * 1.2 then
				table.insert(gone, e)
			elseif e.lane == "traffic" then traffic = traffic + 1
			elseif e.lane == "rock" then rocks = rocks + 1
			elseif e.lane == "offroad" then offroad = offroad + 1 end
		end
	end
	for _, e in ipairs(gone) do self:remove(e) end
	if offroad < T.laneOffroad * 2 then
		self:spawnOffroadRock(ps + (random() < 0.7 and 1 or -1) * T.laneReach * (0.8 + random() * 0.2), ps)
	end
	-- new arrivals, well out of sight ahead or behind
	lane.spawnT = lane.spawnT - dt
	if lane.spawnT > 0 then return end
	lane.spawnT = T.laneSpawnEvery
	local side = random() < 0.5 and -1 or 1
	local n = side * (0.15 + random() * 0.75) * W
	-- oncoming traffic shows up ahead; outbound mostly from behind
	local ahead = side > 0 or random() < 0.4
	local s = ps + (ahead and 1 or -1) * T.laneReach * (0.75 + random() * 0.25)
	if s < -lane.half + 500 or s > lane.half - 500 then return end
	local x, y = self:fromLane(s, n)
	if not self:isClear(x, y, 400) then return end
	local _, _, phi = self:toLane(x, y)
	local f = self:laneFlow(n)
	local vx, vy = cos(phi) * f, sin(phi) * f
	if traffic < T.laneTraffic then
		local t = pick(LANE_TRAFFIC)
		local e = self:spawnEnemy(t[1], x, y)
		e.lane = "traffic"
		e.cruiseSpeed = T.laneSpeedMin + random() * (T.laneSpeedMax - T.laneSpeedMin)
		e.body:setAngle(f > 0 and phi or phi + pi)
		e.body:setLinearVelocity(vx * e.cruiseSpeed, vy * e.cruiseSpeed)
		if t.raider then
			e.aggro = false     -- they find you when you come close
		else
			e.cruise = true
			if t.neutral then e.team = 3 end
		end
	elseif rocks < T.laneRocks and random() < 0.6 then
		-- a rock, or now and then a little cluster of them
		for k = 1, random() < 0.25 and 3 or 1 do
			local rx, ry = self:fromLane(s + (k - 1) * 260, n + (random() - 0.5) * 400)
			if self:isClear(rx, ry, 150) then
				local e = self:spawnAsteroid(rx, ry, 25 + random() ^ 2 * (k == 1 and 140 or 50))
				e.lane = "rock"
				-- some of it is debris drifting across the lanes
				local across = random() < 0.35 and (n > 0 and -1 or 1) * (120 + random() * 200) or 0
				e.body:setLinearVelocity(vx - sin(phi) * across, vy + cos(phi) * across)
			end
		end
	elseif random() < T.laneDerelict then
		-- a derelict: a hauler that didn't make it, hold and all, or a
		-- lost container
		if random() < 0.6 then
			local e = self:spawnEnemy("freighter", x, y)
			e.body:setLinearVelocity(vx, vy)
			self:damage(e, 1e9, nil, "derelict")
		else
			local e = self:spawnContainer(x, y, "cargo_container", true)
			if e then e.body:setLinearVelocity(vx, vy) end
		end
	end
end

-- A rock off the road at distance s along the lane, either side, out of
-- sight of the player at ps. Off-road rocks just sit there.
function Game:spawnOffroadRock(s, ps)
	local lane = self.lane
	if s < -lane.half or s > lane.half or abs(s - ps) < 2500 then return end
	local side = random() < 0.5 and -1 or 1
	local n = side * (T.laneWidth + 200 + random() * (T.laneRamp + 2000))
	local x, y = self:fromLane(s, n)
	if not self:isClear(x, y, 200) then return end
	local e = self:spawnAsteroid(x, y, 30 + random() ^ 2 * 160)
	e.lane = "offroad"
	e.body:setLinearVelocity(0, 0)
	return e
end

-- Traffic just rides the current, nose along the lane.
function Game:cruise(e)
	local x, y = e.body:getPosition()
	local _, n, phi = self:toLane(x, y)
	local d = self:laneFlow(n) >= 0 and 1000 or -1000
	local it = e.intent
	it.thrust, it.strafe = 0, 0
	it.aimX, it.aimY = x + cos(phi) * d, y + sin(phi) * d
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
			local depth = (w.radius - T.crushStart - r) / T.crushDepth
			if r < w.radius then
				-- thickening air all the way down, crushing past crushStart
				local thick = min(1, (w.radius - r) / (T.crushStart + T.crushDepth))
				local vx, vy = b:getLinearVelocity()
				local m = b:getMass()
				b:applyForce(-vx * T.crushDrag * 0.3 * thick * m, -vy * T.crushDrag * 0.3 * thick * m)
			end
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
