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
local data = require("src.data")
local Stations = require("src.stations")

local sqrt, cos, sin, pi, max, min, abs, random, floor = math.sqrt, math.cos, math.sin, math.pi, math.max, math.min, math.abs, love.math.random, math.floor

return function(Game)

-- Mass drivers ----------------------------------------------------------------

-- Passage to another planet: a base fare plus a little per AU.
function Game:driverFare(to)
	local au = Fields.distance(self.fieldId, to, self.universe.clock)
	return math.floor((T.driverFare + T.driverFarePerAU * au) / 10 + 0.5) * 10
end

-- One driver per planet map, at the edge of the map, riding a slow track
-- round the planet like the stations do (where it is on the track follows
-- the universe clock, so it's the same after a save). Its barrel points
-- outward until you buy a passage; then it swings round to the bearing of
-- the planet you're going to (Fields.orbitPos), so the lane leaves the
-- way the trip really goes. A marker only: nothing collides with it.
function Game:spawnDrivers()
	if not Fields.orbits[self.fieldId] then return end
	local d = self.arenaRadius - T.driverBarrel - 100
	local speed = self:currentSpeed(d) * T.driverOrbitScale
	local a = -pi / 2 + 0.6 + (self.universe and self.universe.clock or 0) * speed / d
	local x, y = cos(a) * (d + T.driverBarrel / 2), sin(a) * (d + T.driverBarrel / 2)
	for k = #self.entities, 1, -1 do
		local o = self.entities[k]
		if o.kind == "asteroid" then
			local ox, oy = o.body:getPosition()
			if (ox - x) ^ 2 + (oy - y) ^ 2 < (o.radius + T.driverRadius + 1200) ^ 2 then self:remove(o) end
		end
	end
	local body = love.physics.newBody(self.world, x, y, "kinematic")
	local g = { kind = "driver", invulnerable = true, id = self:nextId(), team = 0, body = body,
		radius = T.driverRadius, name = "Mass driver", angle = a }
	body:setUserData(g)
	table.insert(self.entities, g)
	self:setOrbit(g, 0, 0, speed)
	-- the braking rings are only for the warp-and-catch way of travelling
	if T.travelMode == "flight" then self:spawnCatchRings() end
end

-- The breech: where you're held. The body sits at the gun's middle, the
-- axis it turns on, half a barrel up from the breech.
local function breech(g)
	local gx, gy = g.body:getPosition()
	local h = T.driverBarrel / 2
	return gx - cos(g.angle) * h, gy - sin(g.angle) * h
end
function Game:driverBreech(g) return breech(g) end

-- A point in a driver's frame: lx along the barrel (the breech at 0, the
-- approach behind it negative), ly across it.
local function driverLocal(g, x, y)
	local gx, gy = breech(g)
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
-- How far along the ray from (x, y) heading (dx, dy) to the first
-- planet, station or structure it would hit (math.huge if none).
function Game:solidAhead(x, y, dx, dy)
	local best = math.huge
	for _, e in ipairs(self.entities) do
		if (e.kind == "planet" and not e.gas) or e.kind == "station" or e.kind == "structure" or (e.kind == "asteroid" and e.giant) then
			local ex, ey = e.body:getPosition()
			local r = e.radius or 500
			local rx, ry = ex - x, ey - y
			local along = rx * dx + ry * dy
			if along > 0 then
				local off2 = rx * rx + ry * ry - along * along
				if off2 < r * r then best = min(best, along - sqrt(r * r - off2)) end
			end
		end
	end
	return best
end

-- Which way the barrel should point: at the destination while a launch
-- is on, otherwise straight out from the planet.
local function barrelTarget(game, g, p)
	local L = p and p.launch
	if L and L.driver == g then
		local clock = game.universe and game.universe.clock or 0
		local ax, ay = Fields.orbitPos(game.fieldId, clock)
		local bx, by = Fields.orbitPos(L.to, clock)
		return math.atan2(by - ay, bx - ax)
	end
	if g.orbit then return g.orbit.angle end
	return g.angle
end

-- Swing every driver's barrel toward where it should point, at
-- T.driverSlew rad/s. Returns how far the player's launch driver still has
-- to turn.
function Game:aimDrivers(dt)
	local p = self.player
	for _, g in ipairs(self.entities) do
		if g.kind == "driver" then
			local want = barrelTarget(self, g, p)
			local diff = (want - g.angle + pi) % (2 * pi) - pi
			local step = T.driverSlew * dt
			g.angle = g.angle + max(-step, min(step, diff))
			g.aimLeft = math.abs(diff) - math.min(math.abs(diff), step)
		end
	end
end

function Game:updateDrivers(dt)
	self:aimDrivers(dt)
	local p = self.player
	if not p or p.dead or p.dockState then self.driverMenu = nil return end
	local L = p.launch
	local menu = self.driverMenu
	if L or menu then
		local g = (L or menu).driver
		local gx, gy = breech(g)
		local x, y = p.body:getPosition()
		local dx, dy = cos(g.angle), sin(g.angle)
		p.intent.thrust, p.intent.strafe, p.intent.boost = 0, 0, false
		p.intent.firePrimary, p.intent.fireSecondary, p.intent.fireAux = false, false, false
		local a = p.body:getAngle()
		local diff = (g.angle - a + pi) % (2 * pi) - pi
		p.body:setAngle(a + diff * min(1, dt * 4))
		p.body:setAngularVelocity(0)
		if menu or L.t < T.driverAlign or (g.aimLeft or 0) > 0.002 then
			-- the clock waits for the barrel to come round
			if L and (g.aimLeft or 0) <= 0.002 then L.t = L.t + dt end
			-- held in the breech, riding along as the gun travels and turns
			local gvx, gvy = g.body:getLinearVelocity()
			if L and (x - gx) ^ 2 + (y - gy) ^ 2 < 300 ^ 2 then
				p.body:setPosition(gx, gy)
				p.body:setLinearVelocity(gvx, gvy)
			else
				p.body:setLinearVelocity(gvx + (gx - x) * 3, gvy + (gy - y) * 3)
			end
		else
			L.t = L.t + dt
			if not self.savedZoom then self.savedZoom = self.camera.zoom end
			-- once it fires, the ship passes through whatever's in the way
			-- (the bearing can point back across the map)
			if not L.ghost then
				L.ghost = true
				for _, f in ipairs(p.body:getFixtures()) do f:setSensor(true) end
			end
			local ft = L.t - T.driverAlign
			local s
			if ft < T.driverFire then
				-- down the barrel, harder and harder, engine lit
				local u = ft / T.driverFire
				s = T.driverExitSpeed * u * u
				self:shake(0.08 * u)
			else
				-- out of the muzzle and still climbing, the camera pulling
				-- wide so everything falls away behind you
				local u = min(1, (ft - T.driverFire) / T.driverCoast)
				s = T.driverExitSpeed + (T.driverCoastSpeed - T.driverExitSpeed) * u
				-- (only ever out: if you're already wider, it leaves you be)
				local wide = math.min(self.savedZoom, T.cineZoom)
				self.cineZoom = self.savedZoom + (wide - self.savedZoom) * (1 - (1 - u) ^ 2)
				-- the bearing can point back across the map: cut to the lane
				-- early rather than fly into the planet (or a station)
				if u >= 1 or self:solidAhead(x, y, dx, dy) < s * 0.8 + 2000 then
					self.pendingFlight = L.to
					self.flash = { t = 0, life = 0.5 }
				end
			end
			p.body:setLinearVelocity(dx * s, dy * s)
			p.intent.thrust, p.intent.boost = 1, true
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
	-- velocity relative to the driver, which rides its track round the planet
	local vx, vy = p.body:getLinearVelocity()
	local gvx, gvy = g.body:getLinearVelocity()
	vx, vy = vx - gvx, vy - gvy
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
	if not self:nextCatchRing() then self:spawnCatchRings() end
	local gx, gy = breech(g)
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
	local gx, gy = breech(g)
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
	local gx, gy = breech(g)
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
-- moon: a short hop between a planet and its moon (src/moons.lua), left
-- off the edge of the map: { bearing, length } instead of the orbits'.
function Game:launchTrip(to, moon)
	local p = self.player
	if not p or p.dead then return end
	local from = self.fieldId
	local au, bearing, half
	if moon then
		au, bearing, half = 0, moon.bearing, moon.length / 2
	else
		au = Fields.distance(from, to, self.universe.clock)
		-- the lane leaves along the bearing the driver fired you on
		local clock = self.universe.clock
		local ax, ay = Fields.orbitPos(from, clock)
		local bx, by = Fields.orbitPos(to, clock)
		bearing = math.atan2(by - ay, bx - ax)
		half = Fields.laneLength(au) / 2
	end
	local _, rot = Game.laneShape(half * 2, bearing)
	self.trip = { from = from, to = to, au = au, length = half * 2, rot = rot, moon = moon ~= nil }
	-- No run-up and no cut. The planet you left is drawn behind the lane's
	-- mouth (trip.origin, src/render.lua), and you carry on from exactly
	-- where you were relative to it, at the same speed and heading, a
	-- little short of the mouth. Off a driver you keep its kick for a
	-- while (laneCarry); off a map's edge, your own speed.
	local p0 = self.player
	local vx, vy = p0.body:getLinearVelocity()
	local speed = max(T.laneEntrySpeed, sqrt(vx * vx + vy * vy))
	local ox, oy, angle = p0.body:getX(), p0.body:getY(), p0.body:getAngle()
	local spin = p0.body:getAngularVelocity()
	self:loadField("lane", { player = Ship.record(p), quiet = true })
	local mx, my = self:fromLane(-half, -T.laneWidth / 4)
	local px, py = mx - cos(bearing) * T.rampLead, my - sin(bearing) * T.rampLead
	local cx, cy = px - ox, py - oy
	self.trip.origin = { x = cx, y = cy }
	p = self.player
	p.body:setPosition(px, py)
	p.body:setAngle(angle)
	p.body:setAngularVelocity(spin)
	p.body:setLinearVelocity(vx, vy)
	if not moon then p.laneCarry = { speed = sqrt(vx * vx + vy * vy), t = 0 } end
	self.camera.x, self.camera.y = px, py
	events.emit("travel", from, to)
end

-- Out of the far end of the lane at the other planet's driver, moving fast.
-- back: you turned round, so you come out of your own planet's driver.
function Game:arrive(back)
	local p, trip = self.player, self.trip
	if not p or p.dead or not trip then return end
	local to, from = trip.to, trip.from
	if back then to, from = from, to end
	local exit = self:laneExit(back)
	self.trip = nil
	self:loadField(to, { player = Ship.record(p), at = { driver = from, exit = exit } })
end

-- How you come out of the lane: pointing and moving exactly as you were on
-- screen, and where you were relative to the planet drawn ahead at the end
-- of the lane (Game:laneDestination). Saving mid-trip uses it too.
function Game:laneExit(back)
	local p = self.player
	local vx, vy = p.body:getLinearVelocity()
	local exit = { angle = p.body:getAngle(), vx = vx, vy = vy, moon = self.trip and self.trip.moon }
	local px, py = p.body:getPosition()
	if not back then
		local cx, cy = self:laneDestination()
		exit.ox, exit.oy = px - cx, py - cy
	elseif self.trip and self.trip.origin then
		-- back off a moon trip: where you are relative to the planet drawn
		-- behind the mouth
		exit.ox, exit.oy = px - self.trip.origin.x, py - self.trip.origin.y
		exit.free = true   -- put back exactly there, even past the map's edge
	end
	return exit
end

-- Out of this planet's driver heading inward, at the driver's exit speed,
-- or, off the highway (exit = { angle, vx, vy }), in from the map's edge
-- on course for the planet.
function Game:placeAtDriver(p, exit)
	local g = self:findDriver()
	-- off the highway needs no driver (moons have none)
	if not g and not exit then return false end
	if exit then
		-- off the highway: not at the driver, but in from the edge of the
		-- map on whichever side lines your course up on the planet, so
		-- you arrive flying the way you were, straight at it
		local d = self.arenaRadius - 1500
		local x, y = exit.ox, exit.oy
		if not x then
			local sp = sqrt(exit.vx ^ 2 + exit.vy ^ 2)
			local dx, dy = exit.vx / max(sp, 1), exit.vy / max(sp, 1)
			if sp < 50 then dx, dy = cos(exit.angle), sin(exit.angle) end
			x, y = -dx * d, -dy * d
		end
		local r = sqrt(x * x + y * y)
		local lim = self.arenaRadius - 200
		if r > lim and not exit.free then x, y = x / r * lim, y / r * lim end
		p.body:setPosition(x, y)
		p.body:setAngle(exit.angle)
		p.body:setLinearVelocity(exit.vx, exit.vy)
		local sp = sqrt(exit.vx ^ 2 + exit.vy ^ 2)
		local fx, fy = cos(exit.angle), sin(exit.angle)
		if sp > 50 then fx, fy = exit.vx / sp, exit.vy / sp end
		-- a station can't be swept, so slide the run sideways off one
		for _ = 1, 4 do
			local hit
			for _, e in ipairs(self.entities) do
				if e.kind == "station" then
					local sx, sy = e.body:getPosition()
					local dx, dy = sx - x, sy - y
					local along, across = dx * fx + dy * fy, dx * fy - dy * fx
					local need = (e.radius or 1000) + 900
					if along > 0 and along < 14000 and math.abs(across) < need then
						hit = (across >= 0 and -1 or 1) * (need - math.abs(across) + 200)
						break
					end
				end
			end
			if not hit then break end
			x, y = x + fy * hit, y - fx * hit
		end
		p.body:setPosition(x, y)
		-- the lane's glow and streaks fade off you instead of blinking out
		if not exit.moon then p.laneFade = 1 end
	else
		local gx, gy = breech(g)
		local ix, iy = -cos(g.angle), -sin(g.angle)
		local a = math.atan2(iy, ix)
		p.body:setPosition(gx + ix * (T.driverRadius + 300), gy + iy * (T.driverRadius + 300))
		p.body:setAngle(a)
		p.body:setLinearVelocity(ix * T.laneEntrySpeed, iy * T.laneEntrySpeed)
	end
	p.driverCooldown = T.driverCooldown
	self.camera.x, self.camera.y = p.body:getPosition()
	return true
end

-- The transit lane -----------------------------------------------------------

-- The lane is a slight S: two arcs of radius lane.R meeting at the
-- origin, heading +x there. The near half (s < 0) is a circle round
-- (0, R) and the far half (s > 0) one round (0, -R), so it bends one way
-- and then back, and leaves heading the same way it came in. In lane
-- coordinates s is the distance along it and n the offset from its median
-- (negative: the outbound side). Holding a straight line drifts you
-- across it.
--
-- The whole thing is then turned by lane.rot so both ends lie along the
-- real bearing between the planets (the way the driver fired you, and
-- the way you come in at the other end). toLane's phi is the world
-- direction of the lane at that point.
function Game:toLane(x, y)
	local R, r = self.lane.R, self.lane.rot or 0
	local c, s = cos(-r), sin(-r)
	x, y = x * c - y * s, x * s + y * c
	if x < 0 then
		local dx, dy = x, y - R
		local phi = math.atan2(dx, -dy)
		return phi * R, R - sqrt(dx * dx + dy * dy), phi + r
	end
	local dx, dy = x, y + R
	local psi = math.atan2(dx, dy)
	return psi * R, sqrt(dx * dx + dy * dy) - R, -psi + r
end

-- Where the destination planet's centre sits, in the lane's coordinates:
-- straight on past the end of the lane by as far as you'll arrive from
-- it. It's drawn there as you come in, and you arrive where you were
-- relative to it, so the swap doesn't show.
function Game:laneDestination()
	local lane, F = self.lane, Fields[self.trip.to]
	local ex, ey = self:fromLane(lane.half, 0)
	local phi = self:laneHeading(lane.half)
	local d = F.radius - 1500
	return ex + cos(phi) * d, ey + sin(phi) * d, F
end

-- A lane's point at (s, n) for a lane of arc radius R turned by r, in its
-- own coordinates (Game:fromLane for the lane you're on; src/moons.lua
-- uses it to draw a moon's highway out past a planet map's edge).
local function laneXY(R, r, s, n)
	local phi = s / R
	local x, y
	if s < 0 then
		x, y = sin(phi) * (R - n), R - cos(phi) * (R - n)
	else
		x, y = sin(phi) * (R + n), -R + cos(phi) * (R + n)
	end
	local c, si = cos(r), sin(r)
	return x * c - y * si, x * si + y * c
end
Game.laneXY = laneXY

function Game:fromLane(s, n)
	return laneXY(self.lane.R, self.lane.rot or 0, s, n)
end

-- The arc radius and turn of a lane `length` long leaving along bearing.
function Game.laneShape(length, bearing)
	local Rc = max(T.laneArc, length * 0.9)
	return Rc, bearing + length / 2 / Rc
end

-- The lane's world direction at distance s along it.
function Game:laneHeading(s)
	return -math.abs(s) / self.lane.R + (self.lane.rot or 0)
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
		self.trip = { from = "earth", to = "mars", au = au, length = Fields.laneLength(au) }
	end
	self.lane = { half = self.trip.length / 2, R = max(T.laneArc, self.trip.length * 0.9), rot = self.trip.rot or 0 }
	self.arenaRadius = 1e7
	self:populateLane()
end

-- Everything on the road, laid out once when you enter and left alone
-- until you leave: no pop-in, nothing invented as you go. A fresh layout
-- every trip (the planets have moved since the last one). Rocks on the road (some drifting across it), rocks off-road,
-- and now and then a derelict hauler or a lost container. The first and
-- last few thousand px stay clear for the drivers.
function Game:populateLane()
	local lane, trip = self.lane, self.trip
	local rng = love.math.newRandomGenerator(random(1, 2147483646))
	local W = T.laneWidth
	local s1, s2 = -lane.half + 3000, lane.half - 3000
	local span = max(0, s2 - s1)
	-- what's on the road: the mix where you're headed
	local dest = Fields[trip.to]
	local mix = dest and dest.mix
	local function at(s, n, r)
		local x, y = self:fromLane(s, n)
		if self:isClear(x, y, r) then return x, y end
	end
	-- on the road
	for _ = 1, floor(span / 10000 * T.laneRocks) do
		local s, n = s1 + rng:random() * span, (rng:random() * 2 - 1) * W * 0.9
		local cluster = rng:random() < 0.25 and 3 or 1
		local across = rng:random() < 0.35 and (n > 0 and -1 or 1) * (120 + rng:random() * 200) or 0
		for k = 1, cluster do
			local r = 25 + rng:random() ^ 2 * (k == 1 and 140 or 50)
			local x, y = at(s + (k - 1) * 260, n + (rng:random() - 0.5) * 400, r + 60)
			if x then
				local e = self:spawnAsteroid(x, y, r, self:pickDebris(mix))
				e.lane = "rock"
				local _, _, phi = self:toLane(x, y)
				e.body:setLinearVelocity(-sin(phi) * across, cos(phi) * across)
			end
		end
	end
	-- off the road, either side
	for _ = 1, floor(span / 10000 * T.laneOffroad) do
		local side = rng:random() < 0.5 and -1 or 1
		local s, n = s1 + rng:random() * span, side * (W + 200 + rng:random() * (T.laneRamp + 2000))
		local r = 30 + rng:random() ^ 2 * 160
		local x, y = at(s, n, r + 40)
		if x then
			local e = self:spawnAsteroid(x, y, r, self:pickDebris(mix))
			e.lane = "offroad"
			e.body:setLinearVelocity(0, 0)
		end
	end
	-- derelicts
	for _ = 1, floor(span / 100000 * T.laneDerelicts + rng:random()) do
		local x, y = at(s1 + rng:random() * span, (rng:random() * 2 - 1) * W * 0.8, 400)
		if x then
			if rng:random() < 0.6 then
				local e = self:spawnEnemy("freighter", x, y)
				self:damage(e, 1e9, nil, "derelict")
			else
				local e = self:spawnContainer(x, y, "cargo_container", true)
				if e then e.body:setLinearVelocity(0, 0) end
			end
		end
	end
end

function Game:updateLane(dt)
	local lane, p = self.lane, self.player
	if not lane then return end
	local W = T.laneWidth
	for _, e in ipairs(self.entities) do
		local b = e.body
		if not e.removed and b:getType() == "dynamic" then
			local x, y = b:getPosition()
			local s, n, phi = self:toLane(x, y)
			local tx, ty = cos(phi), sin(phi)
			local m = b:getMass()
			if e.kind == "ship" then
				-- in the lane: the buff (thrust up, drag down)
				local k = self:laneStrength(n)
				-- (not on a moon trip: just your own ship in open space)
				e.laneBuff = k > 0 and not (self.trip and self.trip.moon) and k or nil
			end
			-- soft walls well outside the lane, and the near end (not on
			-- a moon trip: that's open space, flown like anywhere else)
			local over = abs(n) - (W + T.laneRamp + 2500)
			if over > 0 and not (self.trip and self.trip.moon) then
				local k = (n > 0 and 1 or -1) * over * m * 4
				b:applyForce(sin(phi) * k, -cos(phi) * k)
			end
			if s < -lane.half and e ~= p then b:applyForce(tx * (-lane.half - s) * m * 6, ty * (-lane.half - s) * m * 6) end
		end
	end
	if not p or p.dead then return end
	local ps, pn, ph = self:toLane(p.body:getPosition())
	local R = p.runup
	if R then
		-- the run-up: held on the line into the mouth, braking from the
		-- driver's speed to the lane's, the camera wide so you see it coming
		local tx, ty = cos(R.h), sin(R.h)
		local x, y = p.body:getPosition()
		local u = max(0, min(1, ((x - R.x) * tx + (y - R.y) * ty) / T.laneRunup))
		-- easing off only a little: you hit the lane still carrying most of
		-- the driver's kick
		local keep = max(T.laneEntrySpeed, R.speed * T.laneKeep)
		local sp = R.speed + (keep - R.speed) * u * u
		local it = p.intent
		it.thrust, it.strafe, it.boost = 0, 0, false
		it.firePrimary, it.fireSecondary, it.fireAux = false, false, false
		p.body:setLinearVelocity(tx * sp, ty * sp)
		p.body:setAngle(R.h)
		p.body:setAngularVelocity(0)
		-- the zoom stays wide; once you're in the lane it's yours again,
		-- left where it is
		if u >= 1 then
			p.runup = nil
			p.laneCarry = { speed = sp, t = 0 }
			self.cineZoom, self.savedZoom = nil, nil
		end
		return
	end
	-- fresh onto the highway, the driver's kick bleeds off slowly: your
	-- speed can't drop below a floor that eases down from the entry speed
	-- over T.laneCarryTime (steer all you like, it only keeps the pace)
	local C = p.laneCarry
	if C then
		C.t = C.t + dt
		local u = C.t / T.laneCarryTime
		local floor = C.speed * (1 - u * u)
		local vx, vy = p.body:getLinearVelocity()
		local sp = sqrt(vx * vx + vy * vy)
		if sp > 1 and sp < floor then p.body:setLinearVelocity(vx / sp * floor, vy / sp * floor) end
		if u >= 1 or p.intent.thrust < 0 then p.laneCarry = nil end
	end
	if ps > -lane.half then p.laneEntered = true end
	if ps > lane.half - 400 and not p.launch then self.pendingArrive = true end
	-- turned round and flew back out the near end: home again (off a
	-- map's edge you start short of the mouth, so only once you're in)
	if ps < -lane.half - 200 and (p.laneEntered or not self.trip.origin) then self.pendingArrive = "back" end
end

-- Traffic flies its own side of the lane at its own speed, nose along
-- the lane: thrusting (and side-jetting) to match the velocity it wants.
function Game:cruise(e)
	local x, y = e.body:getPosition()
	local _, n, phi = self:toLane(x, y)
	local dir = self:laneFlow(n) >= 0 and 1 or -1
	local tx, ty = cos(phi) * dir, sin(phi) * dir
	local want = T.laneFlow * (e.cruiseSpeed or 1)
	local vx, vy = e.body:getLinearVelocity()
	local ex, ey = tx * want - vx, ty * want - vy
	local it = e.intent
	it.aimX, it.aimY = x + tx * 1000, y + ty * 1000
	local th, st = Ship.toLocal(e, ex / 200, ey / 200)
	it.thrust, it.strafe = max(-1, min(1, th)), max(-1, min(1, st))
end

-- Gas giants -----------------------------------------------------------------

-- A gas giant: the same turning field as a planet, but nothing solid at
-- the middle. Inside its radius the crush builds with depth.
function Game:spawnGasGiant(x, y, radius, flow, swirl, hue)
	local body = love.physics.newBody(self.world, x, y, "static")
	local e = { kind = "planet", gas = true, invulnerable = true, id = self:nextId(), team = 0, radius = radius, body = body,
		hue = hue or { 0.85, 0.65, 0.45 } }
	body:setUserData(e)
	table.insert(self.entities, e)
	-- the crush starts at the first band drawn inside the cloud tops
	-- (the bands step in by 1/13 of the radius; see drawPlanet)
	self.well = { x = x, y = y, radius = radius, flow = flow, swirl = swirl, gas = true, planet = e, crushStart = radius / 13 }
	return e
end

-- Cloud cities -----------------------------------------------------------------

local function wrapAngle(a) return (a + pi) % (2 * pi) - pi end

-- Where a cloud city's drift has it now, and the angle round the planet.
function Game:cityTarget(e)
	local w, d, t = self.well, e.drift, self.time
	local rr = d.r + d.up * sin(t / d.upPeriod * pi * 2 + d.phase)
	local aa = d.a + d.across * sin(t / d.acrossPeriod * pi * 2 + d.phase * 0.7) / d.r
	return w.x + cos(aa) * rr, w.y + sin(aa) * rr, aa
end

-- Move each cloud city along its drift: a slow loop round its spot, set as
-- a velocity so ships docking with it ride along.
function Game:updateCities(dt)
	local w = self.well
	if not w then return end
	for _, e in ipairs(self.entities) do
		local d = e.drift
		if d and not e.removed then
			local tx, ty, aa = self:cityTarget(e)
			local x, y = e.body:getPosition()
			e.body:setLinearVelocity((tx - x) / dt, (ty - y) / dt)
			e.body:setAngularVelocity(wrapAngle(aa + pi / 2 - e.body:getAngle()) / dt)
		end
	end
end

-- A cloud city: a fixed platform hanging in a gas giant's cloud tops, at
-- angle a round the planet, with its docking tunnel just under the tops.
-- It doesn't turn or drift. You dock by flying into either end of the
-- tunnel (dock.both); the clamp is in the middle. k: size (1 or 2).
function Game:spawnCloudCity(a, k)
	k = k or 1
	local w = self.well
	local TH = Stations.CITY_TUNNEL
	-- It floats in the layer between the cloud tops and the crush, drifting
	-- slowly round a fixed spot: across (along the clouds) and up and down,
	-- never above the tops or into the crush. See Game:updateCities.
	local top, bottom = w.radius - 60 - TH, w.radius - w.crushStart + TH + 100
	local mid = (top + bottom) / 2
	local r = mid
	local body = love.physics.newBody(self.world, w.x + cos(a) * r, w.y + sin(a) * r, "kinematic")
	body:setAngle(a + pi / 2)                -- local -y points out to space
	self.stationCount = (self.stationCount or 0) + 1
	local n = self.stationCount
	local names = self.field and self.field.stations
	-- the layout (src/stations.lua): a station { } with this id in the
	-- data or the mods folder (say, from the Shipyard) replaces it
	local id = Stations.cityId(k)
	if not data.stations[id] then
		local _, err = data.defineStation(Stations.city(k))
		if err then error(err) end
	end
	local def = data.stations[id]
	local e = { kind = "station", city = true, invulnerable = true, id = self:nextId(), team = 0, body = body,
		def = def, key = ("%s/%d"):format(self.fieldId or "?", n),
		name = names and names[n] or "Cloud city", radius = 1680 * k,
		cloudY = def.haze or (-TH - 60),
		drift = { a = a, r = mid, up = max(0, (top - bottom) / 2 * 0.85), across = T.cityDriftAcross,
			upPeriod = T.cityDriftUp, acrossPeriod = T.cityDriftAcrossPeriod, phase = random() * pi * 2 } }
	e.docks = {}
	for _, d in ipairs(def.docks) do
		local c = {}
		for kk, v in pairs(d) do c[kk] = v end
		table.insert(e.docks, c)
	end
	e.dock = e.docks[1]
	self:armStation(e)
	local sx, sy, sa = self:cityTarget(e)
	body:setPosition(sx, sy)
	body:setAngle(sa + pi / 2)
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
	body:setUserData(e)
	table.insert(self.entities, e)
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
			local cs = w.crushStart or T.crushStart
			local depth = (w.radius - cs - r) / T.crushDepth
			if r < w.radius then
				-- thickening air all the way down, crushing past crushStart
				local thick = min(1, (w.radius - r) / (cs + T.crushDepth))
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
