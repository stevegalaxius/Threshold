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
local softBoundary=require("src.soft_boundary")
local Ship = require("src.ship")
local AI = require("src.ai")
local Fields = require("src.fields")
local Locations = require("src.locations")
local events = require("src.events")
local data = require("src.data")
local Stations = require("src.stations")

local sqrt, cos, sin, pi, max, min, abs, random, floor = math.sqrt, math.cos, math.sin, math.pi, math.max, math.min, math.abs, love.math.random, math.floor
local laneXYFor   -- (defined with laneXY below)

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
	local x, y, a = Locations.position(self.field.driverId, self.universe.clock)
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
	self:bindLocation(g, self.field.driverId)
	self:setOrbit(g, 0, 0, speed)
	-- the braking rings are only for the warp-and-catch way of travelling
	if T.travelMode == "flight" then self:spawnCatchRings() end
end

-- The breech: where you're held. The body sits at the gun's middle, the
-- axis it turns on, half a barrel up from the breech.
local function breech(g)
	local gx, gy = g.body:getPosition()
	local h = (g.barrel or T.driverBarrel) / 2
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
		if g.kind == "driver" and not g.gate then return g end
	end
end

-- A driver's approach zone: a planet's driver, or a site's smaller
-- acceleration gate (src/sites.lua), which has its own.
local function zone(g) return g.zone or T.driverZone, g.zoneWidth or T.driverZoneWidth end

-- Pay the fare to planet `to` and start the launch (from the driver's
-- targeting window, src/ui/orrery.lua).
function Game:fireDriver(to)
	local menu, p = self.driverMenu, self.player
	if not menu or not p or p.dead then return false end
	if menu.driver.driverShip and menu.driver.driverShip~=p then return false end
	local fare = self:driverFare(to)
	if self.universe.credits < fare then
		self:toast(("PASSAGE TO %s IS %d CR"):format(Fields[to].name:upper(), fare), 2)
		return false
	end
	self.universe.credits = self.universe.credits - fare
	self.driverMenu = nil
	p.launch = { driver = menu.driver, to = to, t = 0 }
	p.driverProtected=true;menu.driver.driverShip=p
	self:toast(("FIRING FOR %s  -%d CR"):format(Fields[to].name:upper(), fare), 1.6)
	return true
end

-- Pay the fare to a site (src/sites.lua) and start the launch: the same
-- run down the barrel, then straight into the site's first pocket.
function Game:fireDriverToSite(instId)
	local Sites = require("src.sites")
	local menu, p = self.driverMenu, self.player
	local inst = Sites.list(self.universe)[instId]
	if not menu or not p or p.dead or not inst then return false end
	if menu.driver.driverShip and menu.driver.driverShip~=p then return false end
	local fare = Sites.fare(inst)
	if self.universe.credits < fare then
		self:toast(("PASSAGE TO %s IS %d CR"):format(Sites.name(inst):upper(), fare), 2)
		return false
	end
	self.universe.credits = self.universe.credits - fare
	self.driverMenu = nil
	p.launch = { driver = menu.driver, to = instId, site = true, t = 0 }
	p.driverProtected=true;menu.driver.driverShip=p
	self:toast(("FIRING FOR %s  -%d CR"):format(Sites.name(inst):upper(), fare), 1.6)
	return true
end

-- Back out of the targeting window: you drift free of the ring.
function Game:closeDriverMenu()
	local p = self.player
	self.driverMenu = nil
	if p then
	 p.driverCooldown=T.driverCooldown;p.driverProtected=nil
	 local g=self:findDriver();if g and g.driverShip==p then g.driverShip=nil end
	end
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
	if g.gate then return g.angle end
	if L and L.driver == g then
		local clock = game.universe and game.universe.clock or 0
		local ax, ay = Fields.orbitPos(game.fieldId, clock)
		local bx, by
		if L.site then
			local Sites = require("src.sites")
			local inst = Sites.list(game.universe)[L.to]
			if not inst then return g.angle end
			bx, by = Sites.position(inst, clock)
		else
			bx, by = Fields.orbitPos(L.to, clock)
		end
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
			if g.driverShip and (g.driverShip.dead or g.driverShip.removed) then g.driverShip=nil end
			local want = barrelTarget(self, g, g.driverShip or p)
			local diff = (want - g.angle + pi) % (2 * pi) - pi
			local step = T.driverSlew * dt
			g.angle = g.angle + max(-step, min(step, diff))
			g.aimLeft = math.abs(diff) - math.min(math.abs(diff), step)
		end
	end
end

function Game:requestDriver(p,g,to)
 if g.driverShip and g.driverShip~=p then return false end
 if p.driverCooldown and p.driverCooldown>0 then return false end
 local lx,ly=driverLocal(g,p.body:getPosition())
 local zl,zw=zone(g)
 if lx>=150 or lx<=-zl or math.abs(ly)>=zw then return false end
 g.driverShip=p;p.driverProtected=true
 p.driverTractor={driver=g,to=to,t=0}
 return true
end

function Game:updateDriverLaunch(p,dt)
	local L = p.launch
	local menu = p==self.player and self.driverMenu
	if L or menu then
		local g = (L or menu).driver
		local gx, gy = breech(g)
		local x, y = p.body:getPosition()
		local dx, dy = cos(g.angle), sin(g.angle)
		p.intent.thrust, p.intent.strafe, p.intent.boost = 0, 0, false
		p.intent.firePrimary, p.intent.fireSecondary, p.intent.fireTertiary = false, false, false
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
			-- once it fires, the ship passes through whatever's in the way
			-- (the bearing can point back across the map)
			if not L.ghost then
				L.ghost = true
				p.coasting=true
				for _, f in ipairs(p.body:getFixtures()) do f:setSensor(true) end
			end
			local ft = L.t - T.driverAlign
			local s
			if ft < T.driverFire then
				-- down the barrel, harder and harder, engine lit
				local u = ft / T.driverFire
				s = T.driverExitSpeed * u * u
				if p==self.player then self:shake(0.08 * u) end
			else
				-- out of the muzzle and still climbing, the camera pulling
				-- wide so everything falls away behind you
				local u = min(1, (ft - T.driverFire) / T.driverCoast)
				s = T.driverExitSpeed + (T.driverCoastSpeed - T.driverExitSpeed) * u
				-- the kick out of the muzzle
				if p==self.player and not L.kicked then
					L.kicked = true
					self:shake(0.6)
					self:spark(x, y, 30, { 0.7, 0.95, 1 })
				end
				-- the bearing can point back across the map: cut to the lane
				-- early rather than fly into the planet (or a station). A
				-- driver shot is a cut into the lane, hidden in the flash
				-- off the driver (the map isn't kept behind you: you're
				-- often over the planet when it fires).
				if u >= 1 or self:solidAhead(x, y, dx, dy) < s * 0.8 + 2000 then
					if p==self.player then
					 self.driverCut = true
					 -- a full white-out off the driver hides the cut
					 self.flash = { t = 0, life = 0.7, peak = 1 }
					 if L.gate then self.pendingGate = L.driver.gate elseif L.site then self.pendingSite = { id = L.to, bearing = L.driver.angle } else self.pendingFlight = L.to end
					else
					 p.launch=nil;p.alifeDepart=true
					 if g.driverShip==p then g.driverShip=nil end
					end
				end
			end
			p.body:setLinearVelocity(dx * s, dy * s)
			p.intent.thrust, p.intent.boost = 1, true
			p.mainBurn=1
		end
		return
	end
end

function Game:updateDrivers(dt)
	self:aimDrivers(dt)
	for _,e in ipairs(self.entities) do
	 if e.kind=="ship" and not e.dead and not e.removed then
	  if e~=self.player then e.driverCooldown=max(0,(e.driverCooldown or 0)-dt) end
	  if e.launch or e==self.player and self.driverMenu then self:updateDriverLaunch(e,dt)
	  elseif e.driverTractor then self:updateDriverTractor(e,dt) end
	 end
	end
	local p=self.player
	if not p or p.dead or p.dockState then self.driverMenu=nil;return end
	if p.launch or p.driverTractor or self.driverMenu then return end
	p.driverCooldown = max(0, (p.driverCooldown or 0) - dt)
	if p.driverCooldown > 0 then return end
	for _, g in ipairs(self.entities) do
		if g.kind == "driver" and not (g.driverShip and g.driverShip ~= p) then
			local lx, ly = driverLocal(g, p.body:getPosition())
			local zl, zw = zone(g)
			if lx < 0 and lx > -zl and math.abs(ly) < zw then
				if g.gate and not self:gateOpen(g) then
					if not g.warned then g.warned = true; self:toast("GATE LOCKED: " .. select(2, self:gateOpen(g)), 2) end
				else
					self:requestDriver(p,g)
					self:toast("TRACTOR LOCK", 1.4)
					return
				end
			elseif g.gate then g.warned = nil end
		end
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
	p.intent.firePrimary, p.intent.fireSecondary, p.intent.fireTertiary = false, false, false
	local zl, zw = zone(g)
	if lx > 150 or math.abs(ly) > zw * 1.5 or lx < -zl * 1.2 then
		-- overshot the breech, or slid out of the beam
		p.driverTractor = nil
		p.driverProtected=nil;if g.driverShip==p then g.driverShip=nil end
		p.driverCooldown = 3
		if p.isPlayer then self:toast(lx > 150 and "OVERSHOT THE BREECH: TOO FAST" or "TRACTOR LOST", 1.8) end
		return
	end
	-- velocity relative to the driver, which rides its track round the planet
	local vx, vy = p.body:getLinearVelocity()
	local gvx, gvy = g.body:getLinearVelocity()
	vx, vy = vx - gvx, vy - gvy
	if lx > -120 and math.abs(ly) < 120 and vx * vx + vy * vy < 250 ^ 2 then
		p.driverTractor = nil
		if p==self.player and g.gate then
		 -- an acceleration gate has one target: no window, it just fires
		 p.launch={driver=g,to=g.gate.to,gate=true,t=0};p.driverProtected=true
		 self:toast("GATE LOCK", 1.2)
		elseif p==self.player then
		 self.driverMenu = { driver = g };self:toast("DRIVER LOCK", 1.2)
		else p.launch={driver=g,to=tr.to,t=0} end
		return
	end
	local near = 1 - max(0, min(1, -lx / zl))
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
	self:captureALife(true)
	require("src.mining").unload(self)
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

-- The lane for a trip from here to `to` (see Game:launchTrip).
function Game:tripShape(to, moon, lane)
	local from = self.fieldId
	local au, bearing, half
	if moon then
		au, bearing, half = 0, moon.bearing, moon.length / 2
	elseif lane then
		au, bearing, half = lane.au or 0, lane.bearing, lane.length / 2
	else
		au = Fields.distance(from, to, self.universe.clock)
		-- the lane leaves along the bearing the driver fired you on
		local clock = self.universe.clock
		local ax, ay = Fields.orbitPos(from, clock)
		local bx, by = Fields.orbitPos(to, clock)
		bearing = math.atan2(by - ay, bx - ax)
		half = Fields.laneLength(au) / 2
	end
	local _, rot = Game.laneShape(half * 2, bearing, moon ~= nil)
	return { from = from, to = to, au = au, length = half * 2, rot = rot, moon = moon ~= nil, bearing = bearing }
end

-- Where you come into a lane from the map's edge, in the lane's own
-- coordinates: just short of the mouth off a moon exit, at the start of
-- the run-in out of a driver. (A lane's coordinates only need its trip.)
local function laneEntry(trip)
	local probe = { lane = { R = Game.laneShape(trip.length, trip.bearing, trip.moon), rot = trip.rot, half = trip.length / 2 } }
	local half = trip.length / 2
	if trip.moon then
		local mx, my = laneXYFor(probe.lane, -half, -T.laneWidth / 4)
		return mx - cos(trip.bearing) * T.rampLead, my - sin(trip.bearing) * T.rampLead
	end
	local mx, my = laneXYFor(probe.lane, -half, -T.laneWidth / 2)
	local h = -half / probe.lane.R + trip.rot
	return mx - cos(h) * T.laneRunup, my - sin(h) * T.laneRunup, h
end

-- Build the lane ahead of you while you're still on the map, so it's
-- already there (rocks and all, drawn beside the map) when you cross into
-- it. (ex, ey): where on this map you'll cross, which fixes where the lane
-- sits relative to it.
function Game:stageLane(to, moon, lane, ex, ey)
	local st = self.laneStage
	if st and st.to == to then return st end
	self:dropLaneStage()
	local trip = self:tripShape(to, moon, lane)
	local lx, ly = laneEntry(trip)
	trip.origin = { x = lx - ex, y = ly - ey }
	st = { to = to, trip = trip, stage = self:stageField("lane", trip) }
	self.laneStage = st
	return st
end

function Game:dropLaneStage(forget)
	local st = self.laneStage
	self.laneStage = nil
	if st and st.scene then st.scene:releaseScene(forget) end
end

-- Each frame: build on the staged lane.
function Game:updateLaneStage()
	local st = self.laneStage
	if not st or st.scene or st.failed then return end
	if Game.advanceStage(st.stage, T.laneStageBudget) then
		if st.stage.failed then st.failed = true return end
		st.scene = st.stage.scene
		st.scene.time = self.time
	end
end

function Game:finishLaneStage()
	local st = self.laneStage
	if not st or st.failed then return false end
	if not st.scene then
		while not Game.advanceStage(st.stage, 1) do end
		if st.stage.failed then st.failed = true return false end
		st.scene = st.stage.scene
		st.scene.time = self.time
	end
	return true
end

-- Into the lane that was built ahead of you: like any handoff, only your
-- ship and the camera move over, and the map you're leaving stays behind
-- the mouth.
function Game:enterStagedLane(st)
	local trip, scene = st.trip, st.scene
	local p = self.player
	local from, to = trip.from, trip.to
	local o = trip.origin
	local x, y = p.body:getPosition()
	local vx, vy = p.body:getLinearVelocity()
	local at = { x = x + o.x, y = y + o.y, angle = p.body:getAngle(), vx = vx, vy = vy }
	local spin = p.body:getAngularVelocity()
	local carry = self:carryFlight(p)
	local record = Ship.record(p)
	local camX, camY = self.camera.x, self.camera.y
	local effects = self.effects
	local origin = self:retainField()
	self.trip = trip
	trip.originScene = origin
	self:loadField("lane", { player = record, at = at, prepared = scene, retain = true, quiet = true, deferALife = true })
	p = self.player
	p.body:setAngularVelocity(spin)
	self:restoreFlight(p, carry, o.x, o.y)
	self.inputTranslation = { x = o.x, y = o.y }
	self.camera.x, self.camera.y = camX + o.x, camY + o.y
	self.camera.backgroundX = (origin.camera.backgroundX or 0) - o.x
	self.camera.backgroundY = (origin.camera.backgroundY or 0) - o.y
	for _, fx in ipairs(effects or {}) do
		if fx.x then fx.x, fx.y = fx.x + o.x, fx.y + o.y; table.insert(self.effects, fx) end
	end
	if not trip.moon then
		local _, _, h = laneEntry(trip)
		local speed = max(T.laneEntrySpeed, sqrt(vx * vx + vy * vy))
		p.runup = { speed = speed, x = at.x, y = at.y, h = h }
	end
	self:updateALife(true)
	if trip.moon then
		events.emit("travel", from, to)
	else
		self:toast(("%s TO %s  %.2f AU"):format(Fields[from].name:upper(), Fields[to].name:upper(), trip.au), 3)
		events.emit("travel", from, to)
	end
end

-- Into the transit lane toward planet `to`, in the ship you're flying.
-- moon: a short hop between a planet and its moon (src/moons.lua), left
-- off the edge of the map: { bearing, length } instead of the orbits'.
-- lane: { bearing, length } for a trip that isn't between two orbits (a
-- site off a driver or a gate, src/sites.lua): fired down a lane all the
-- same, just of a set length on the bearing it left on.
function Game:launchTrip(to, moon, lane)
	local p = self.player
	if not p or p.dead then return end
	local from = self.fieldId
	-- already in a lane (a second ask in the same step): nothing to do
	if self.lane or not Fields[from] then return end
	-- the lane behind you from the last trip, if it's still in view
	if self.trail then self.trail.scene:releaseScene(); self.trail = nil end
	-- the lane built ahead of you for this trip (Game:stageLane), if any
	local staged = self.laneStage
	if staged and staged.to == to and not self.launchBlocked and not self.driverCut and self:finishLaneStage() then
		self.laneStage = nil
		return self:enterStagedLane(staged)
	end
	self:dropLaneStage()
	self.trip = self:tripShape(to, moon, lane)
	local au, half, bearing = self.trip.au, self.trip.length / 2, self.trip.bearing
	local p0 = self.player
	local vx, vy = p0.body:getLinearVelocity()
	local label = lane and ("%s TO %s"):format(Fields[from].name:upper(), Fields[to].name:upper())
		or not moon and ("%s TO %s  %.2f AU"):format(Fields[from].name:upper(), Fields[to].name:upper(), au)
	-- Fired out of a driver with something solid dead ahead (the barrel
	-- pointed back across the map) you'd fly through the planet you left:
	-- that one still cuts, behind the glow (Game:coverThen).
	local blocked = self.launchBlocked or self.driverCut
	self.launchBlocked, self.driverCut = nil, nil
	if blocked and not moon then
		local speed = max(T.laneEntrySpeed, sqrt(vx * vx + vy * vy))
		self:loadField("lane", { player = Ship.record(p) })
		local mx, my = self:fromLane(-half, -T.laneWidth / 2)
		local h = self:laneHeading(-half)
		local x, y = mx - cos(h) * T.laneRunup, my - sin(h) * T.laneRunup
		p = self.player
		p.body:setPosition(x, y)
		p.body:setAngle(h)
		p.body:setLinearVelocity(cos(h) * speed, sin(h) * speed)
		p.runup = { speed = speed, x = x, y = y, h = h }
		self.camera.x, self.camera.y = x, y
		self:toast(label, 3)
		if not lane then events.emit("travel", from, to) end
		return
	end
	-- Otherwise there's no cut at all. The map you're leaving stays alive
	-- as a side scene (trip.originScene), placed in the lane's coordinates
	-- so that you carry on from exactly where you were relative to it, at
	-- the same speed, heading, spin and controls, and it's let go once it's
	-- well out of view (Game:stepSides).
	--   off a map's edge toward a moon (src/moons.lua): you come in just
	--     short of the lane's mouth, flying freely
	--   out of a driver: at the start of the run-up into the mouth, which
	--     carries you in along the lane's heading
	local p0 = self.player
	local ox, oy, angle = p0.body:getX(), p0.body:getY(), p0.body:getAngle()
	local spin = p0.body:getAngularVelocity()
	local record = Ship.record(p)
	local camX, camY = self.camera.x, self.camera.y
	local control={}
	for k,v in pairs(p0.intent) do control[k]=v end
	local weaponState={}
	for i,w in ipairs(p0.weapons) do
	 weaponState[i]={aim=w.aim,cooldown=w.cooldown,ammo=w.ammo,firing=w.firing,barrel=w.barrel}
	end
	local flight={}
	for _,k in ipairs({"power","spool","mainBurn","retroBurn","sideBurn","turnBurn","foreBurn","afterburn","burnerLocked"}) do flight[k]=p0[k] end
	local effects = self.effects
	-- (where the map you're leaving sits is known before the lane is laid
	-- out, so its rocks keep out of that map)
	local px, py, h = laneEntry(self.trip)
	local dx, dy = px - ox, py - oy
	self.trip.origin = { x = dx, y = dy }
	local origin = self:retainField()
	self.trip.originScene = origin
	self:loadField("lane", { player = record, quiet = true, retain = true, deferALife = true })
	p = self.player
	p.body:setPosition(px, py)
	p.body:setAngle(angle)
	p.body:setAngularVelocity(spin)
	p.body:setLinearVelocity(vx, vy)
	for k,v in pairs(flight) do p[k]=v end
	for i,w in ipairs(weaponState) do for k,v in pairs(w) do p.weapons[i][k]=v end end
	for k,v in pairs(control) do p.intent[k]=v end
	if p.intent.aimX then p.intent.aimX=p.intent.aimX+dx end
	if p.intent.aimY then p.intent.aimY=p.intent.aimY+dy end
	self.inputTranslation={x=dx,y=dy}
	self.camera.x, self.camera.y = camX + dx, camY + dy
	self.camera.backgroundX = (origin.camera.backgroundX or 0) - dx
	self.camera.backgroundY = (origin.camera.backgroundY or 0) - dy
	-- the sparks and exhaust in flight carry on too
	for _, fx in ipairs(effects or {}) do
		if fx.x then fx.x, fx.y = fx.x + dx, fx.y + dy; table.insert(self.effects, fx) end
	end
	if not moon then
		local speed = max(T.laneEntrySpeed, sqrt(vx * vx + vy * vy))
		p.runup = { speed = speed, x = px, y = py, h = h }
		p.launch = nil
	end
	self:updateALife(true)
	if label then self:toast(label, 3) end
	if not lane then events.emit("travel", from, to) end
end

-- Both ends of a lane are real maps, alive beside it as side scenes
-- (Game:retainField, Game:stageField): the one you left, kept behind the
-- mouth until it's well out of view, and the one you're heading for, built
-- a slice per frame as you come up on it and running from then on. Each
-- sits at an offset in the lane's coordinates (scene position + offset =
-- lane position) and is drawn there, so what you see ahead of you is the
-- destination itself. Out of the lane, only your ship and the camera move
-- over into it: nothing in it is rebuilt or respawned, and the lane goes
-- on behind you as a side scene of its own (self.trail) until it's out of
-- view.

-- Where the map at one end of the lane sits, in the lane's coordinates:
-- its centre straight on past the end by as far in as you'll arrive (a
-- site's pocket: its spawn point at the end of the lane). back: the map
-- you left, which is where it was when you entered.
function Game:laneEndCenter(back)
	local trip, lane = self.trip, self.lane
	if back and trip.origin then return trip.origin.x, trip.origin.y end
	local id = back and trip.from or trip.to
	local F = Fields[id]
	local s = back and -lane.half or lane.half
	local ex, ey = self:fromLane(s, 0)
	local h = self:laneHeading(s) + (back and pi or 0)
	local d = (F and F.radius or 10000) - 1500
	return ex + cos(h) * d, ey + sin(h) * d
end

-- The map at that end, if it's alive and ready to fly into, and its offset.
function Game:laneEndScene(back)
	local trip = self.trip
	if not trip then return end
	if back then
		if trip.originScene and not trip.originScene.released and trip.origin then
			return trip.originScene, trip.origin.x, trip.origin.y
		end
	else
		local d = trip.dest
		if d and d.scene and not d.scene.released then return d.scene, d.x, d.y end
	end
end

-- Every side scene alive beside this game, with its offset.
function Game:sideScenes()
	local list, trip = {}, self.trip
	if trip then
		if trip.originScene and not trip.originScene.released and trip.origin then
			list[#list + 1] = { scene = trip.originScene, x = trip.origin.x, y = trip.origin.y, origin = true }
		end
		if trip.dest and trip.dest.scene and not trip.dest.scene.released then
			list[#list + 1] = { scene = trip.dest.scene, x = trip.dest.x, y = trip.dest.y, dest = true }
		end
	end
	local t = self.trail
	if t and not t.scene.released then list[#list + 1] = { scene = t.scene, x = t.x, y = t.y, trail = true } end
	-- the lane built ahead of you, before you're in it
	local st = self.laneStage
	if st and st.scene and not st.scene.released then
		list[#list + 1] = { scene = st.scene, x = -st.trip.origin.x, y = -st.trip.origin.y, staged = true }
	end
	return list
end

-- Has a side scene woken this A-Life record? (The game you're in leaves it
-- to that scene.)
function Game:sideOwns(id)
	local trip = self.trip
	local d = trip and trip.dest and trip.dest.scene
	return d and not d.released and d.alifeOnline and d.alifeOnline[id] ~= nil
end

-- How far the view reaches from the ship, at the widest it can be.
local function viewReach(game)
	local w, h = love.graphics.getDimensions()
	local zoom = min(game.camera.zoom or 1, T.minZoom)
	return sqrt(w * w + h * h) / (2 * max(zoom, 0.01))
end
function Game:viewReach() return viewReach(self) end

-- Each step: the side scenes move on with the clock; the far end's
-- A-Life traffic near where you'll come in is woken there ahead of you;
-- the map you left goes once you're well past it, and the lane behind you
-- once it's out of view.
function Game:stepSides(dt)
	local p = self.player
	local px, py
	if p and not p.dead and p.body and not p.body:isDestroyed() then px, py = p.body:getPosition()
	else px, py = self.camera.x, self.camera.y end
	local vx, vy = 0, 0
	if p and p.body and not p.body:isDestroyed() then vx, vy = p.body:getLinearVelocity() end
	local reach = viewReach(self)
	for _, side in ipairs(self:sideScenes()) do
		local scene = side.scene
		local fx, fy = px - side.x, py - side.y
		scene.focus = scene.focus or {}
		scene.focus.x, scene.focus.y, scene.focus.vx, scene.focus.vy = fx, fy, vx, vy
		scene.camera.x, scene.camera.y = fx, fy
		scene.camera.zoom = self.camera.zoom
		scene:stepScene(dt, self.time)
		if side.dest and self.universe.clock >= (scene.prewakeNext or 0) then
			scene.prewakeNext = self.universe.clock + 0.5
			self:prewakeScene(scene, fx, fy)
		end
		-- far enough away to let go: past its edge by more than the view
		local r = scene.arenaRadius or 10000
		local away = sqrt(fx * fx + fy * fy)
		if side.origin and self.lane and p and p.laneEntered and away > r + reach + T.laneDropBehind then
			scene:releaseScene()
			self.trip.originScene = nil
		elseif side.trail then
			local s = self.trail
			local ex, ey = s.endX, s.endY
			if not ex or (fx - ex) ^ 2 + (fy - ey) ^ 2 > (reach + T.laneDropBehind) ^ 2 then
				scene:releaseScene()
				self.trail = nil
			end
		end
	end
end

-- Wake the A-Life ships of the map ahead that are near where you'll come
-- in, in that map, so they're flying there already when you arrive.
function Game:prewakeScene(scene, fx, fy)
	local u, ALife = self.universe, require("src.alife")
	local clock = u.clock
	scene.alifeOnline = scene.alifeOnline or {}
	for id, r in pairs(u.npcs or {}) do
		if r.area == scene.fieldId and not (self.alifeOnline and self.alifeOnline[id]) and not scene.alifeOnline[id]
			and r.state ~= "dead" and r.state ~= "escaped" and r.state ~= "transit" then
			ALife.advance(r, clock, u, scene)
			if r.area == scene.fieldId and r.state ~= "dead" and r.state ~= "escaped" and r.state ~= "transit" then
				local x, y = ALife.point(r, clock)
				if x and (x - fx) ^ 2 + (y - fy) ^ 2 < T.alifeNear ^ 2 then ALife.wake(scene, r) end
			end
		end
	end
end

-- Each frame: build on the map at whichever end you're heading for, once
-- you're coming up on it.
function Game:updateStaging()
	local trip, lane, p = self.trip, self.lane, self.player
	if not trip or not lane or not p or p.dead then return end
	local ps = self:toLane(p.body:getPosition())
	local reach = viewReach(self) + T.laneStageAhead
	local function stage(back)
		local id = back and trip.from or trip.to
		if not Fields[id] then return end
		local slot = back and "returning" or "dest"
		local st = trip[slot]
		if not st then
			st = { stage = self:stageField(id), back = back }
			trip[slot] = st
		end
		if st.scene or st.failed then return end
		if Game.advanceStage(st.stage, T.laneStageBudget) then
			if st.stage.failed then st.failed = true return end
			local scene = st.stage.scene
			scene.time = self.time
			if back then
				-- the map you left, built again because you turned round
				local x, y = self:laneEndCenter(true)
				trip.origin = trip.origin or { x = x, y = y }
				trip.originScene = scene
				st.scene = scene
			else
				st.scene = scene
				st.x, st.y = self:laneEndCenter(false)
				self:clearArrival(scene, st.x, st.y)
			end
		end
	end
	if lane.half - ps < reach then stage(false) end
	if trip.moon and p.laneEntered and not trip.originScene and ps + lane.half < reach then
		local vx, vy = p.body:getLinearVelocity()
		local _, _, ph = self:toLane(p.body:getPosition())
		if vx * cos(ph) + vy * sin(ph) < 0 then stage(true) end
	end
end

-- Finish building the map at that end now (you got there before it was
-- done). Returns whether it's ready.
function Game:finishStaging(back)
	local trip = self.trip
	if self:laneEndScene(back) then return true end
	local slot = back and "returning" or "dest"
	local st = trip[slot]
	if not st then
		st = { stage = self:stageField(back and trip.from or trip.to), back = back }
		trip[slot] = st
	end
	if st.failed then return false end
	if not st.scene then
		while not Game.advanceStage(st.stage, 1) do end
		if st.stage.failed then st.failed = true return false end
		local scene = st.stage.scene
		scene.time = self.time
		st.scene = scene
		if back then
			local x, y = self:laneEndCenter(true)
			trip.origin = trip.origin or { x = x, y = y }
			trip.originScene = scene
		else
			st.x, st.y = self:laneEndCenter(false)
			self:clearArrival(scene, st.x, st.y)
		end
	end
	return self:laneEndScene(back) ~= nil
end

-- The road carries on into the map ahead: its ring of rock past the edge
-- is cleared along the line you'll come in on, as wide as the road, so
-- you fly out of the lane between the same walls and not into a field.
-- (scene at ox, oy from the lane)
function Game:clearArrival(scene, ox, oy)
	if self.trip.moon then return end
	local half = self.lane.half
	local ex, ey = self:fromLane(half, 0)
	ex, ey = ex - ox, ey - oy
	local h = self:laneHeading(half)
	local tx, ty = cos(h), sin(h)
	local W = T.laneWidth
	-- (the ring past the edge, and the map's own loose rock for the first
	-- stretch in, so you don't come out of the lane into it)
	local function inRoad(e, x, y)
		if e.giant or e.miningId then return false end
		local dx, dy = x - ex, y - ey
		return dx * tx + dy * ty < (e.outer and 1000 or 3000) and abs(dy * tx - dx * ty) < W + e.radius
	end
	local keep = {}
	for _, e in ipairs(scene.sleepers or {}) do
		if not inRoad(e, e.body.x, e.body.y) then keep[#keep + 1] = e end
	end
	scene.sleepers = keep
	local gone = {}
	for _, e in ipairs(scene.entities) do
		if e.kind == "asteroid" and not e.removed and inRoad(e, e.body:getPosition()) then gone[#gone + 1] = e end
	end
	for _, e in ipairs(gone) do scene:remove(e) end
end

-- Out of the far end of the lane into the map that's been running there
-- (back: you turned round, into the one you left). Only your ship and
-- the camera cross over, exactly as they were.
function Game:arrive(back)
	local p, trip = self.player, self.trip
	if not p or p.dead or not trip then return end
	local to, from = trip.to, trip.from
	if back then to, from = from, to end
	if not Fields[to] then to = Fields.start end
	local scene, ox, oy = self:laneEndScene(back)
	if not scene then
		self:finishStaging(back)
		scene, ox, oy = self:laneEndScene(back)
	end
	if not scene then return self:arriveCut(back) end
	-- a scene the clock ran on without (debug time skips, tests): bring
	-- its saved objects up to now first
	if (scene.lastClock or self.universe.clock) < self.universe.clock - 1 then scene:syncAreaMotion() end
	local px, py = p.body:getPosition()
	local vx, vy = p.body:getLinearVelocity()
	local at = { x = px - ox, y = py - oy, angle = p.body:getAngle(), vx = vx, vy = vy }
	local spin = p.body:getAngularVelocity()
	local carry = self:carryFlight(p)
	local ship = Ship.record(p)
	local camX, camY = self.camera.x, self.camera.y
	local effects = self.effects
	-- the far end's other scene goes; the lane carries on behind you
	local other = back and trip.dest and trip.dest.scene or not back and trip.originScene
	if other and other ~= scene then other:releaseScene() end
	if trip.returning and trip.returning.scene ~= scene and trip.returning.scene then trip.returning.scene:releaseScene() end
	if self.trail then self.trail.scene:releaseScene(); self.trail = nil end
	local ex, ey = self:fromLane(back and -self.lane.half or self.lane.half, 0)
	local laneScene = self:retainField({ lane = true })
	local moon = trip.moon
	self:loadField(to, { player = ship, at = at, prepared = scene, retain = true })
	p = self.player
	p.body:setAngularVelocity(spin)
	self:restoreFlight(p, carry, -ox, -oy)
	p.driverCooldown = T.driverCooldown
	if not moon then p.laneFade = 1 end

	self.inputTranslation = { x = -ox, y = -oy }
	self.camera.x, self.camera.y = camX - ox, camY - oy
	self.camera.backgroundX = (self.camera.backgroundX or 0) + ox
	self.camera.backgroundY = (self.camera.backgroundY or 0) + oy
	for _, fx in ipairs(effects or {}) do
		if fx.x then fx.x, fx.y = fx.x - ox, fx.y - oy; table.insert(self.effects, fx) end
	end
	-- the lane, behind you now: its own coordinates, less the offset
	self.trail = { scene = laneScene, x = -ox, y = -oy, endX = ex, endY = ey }
	self:updateALife(true)
end

-- No map could be built at that end: the old way, a cut to it, behind the
-- glow.
function Game:arriveCut(back)
	local p, trip = self.player, self.trip
	local to, from = trip.to, trip.from
	if back then to, from = from, to end
	if not Fields[to] then to = Fields.start end
	local exit = self:laneExit(back)
	local at = { driver = from, exit = exit }
	local F = Fields[to]
	if F.instance and F.spawn then
		local a = exit.angle
		local sp = min(sqrt(exit.vx ^ 2 + exit.vy ^ 2), T.siteArriveSpeed)
		at = { x = F.spawn[1], y = F.spawn[2], angle = a, vx = cos(a) * sp, vy = sin(a) * sp }
	end
	self:loadField(to, { player = Ship.record(p), at = at })
	self.flash = { t = 0, life = T.laneCoverOut, peak = 1 }
end

-- What a ship carries across a handoff besides its record: its throttle
-- and burn state, its weapons' timing and its controls.
function Game:carryFlight(p)
	local c = { control = {}, weapons = {}, flight = {} }
	for k, v in pairs(p.intent) do c.control[k] = v end
	for i, w in ipairs(p.weapons) do
		c.weapons[i] = { aim = w.aim, cooldown = w.cooldown, ammo = w.ammo, firing = w.firing, barrel = w.barrel }
	end
	for _, k in ipairs({ "power", "spool", "mainBurn", "retroBurn", "sideBurn", "turnBurn", "foreBurn", "afterburn", "burnerLocked" }) do c.flight[k] = p[k] end
	return c
end

function Game:restoreFlight(p, c, dx, dy)
	for k, v in pairs(c.flight) do p[k] = v end
	for i, w in ipairs(c.weapons) do
		if p.weapons[i] then for k, v in pairs(w) do p.weapons[i][k] = v end end
	end
	for k, v in pairs(c.control) do p.intent[k] = v end
	if p.intent.aimX then p.intent.aimX = p.intent.aimX + dx end
	if p.intent.aimY then p.intent.aimY = p.intent.aimY + dy end
end

-- How you come out of the lane when it has to cut: pointing and moving
-- exactly as you were, in from the destination map's edge on the lane's
-- line (Game:placeAtDriver), or back off a moon trip where you were
-- relative to the planet you left.
function Game:laneExit(back)
	local p = self.player
	local vx, vy = p.body:getLinearVelocity()
	local exit = { angle = p.body:getAngle(), vx = vx, vy = vy, spin = p.body:getAngularVelocity(), moon = self.trip and self.trip.moon }
	if self.lane and self.trip then
		local px, py = p.body:getPosition()
		local cx, cy = self:laneEndCenter(back)
		exit.ox, exit.oy = px - cx, py - cy
		exit.free, exit.continuous = true, true
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
		p.body:setAngularVelocity(exit.spin or 0)
		local sp = sqrt(exit.vx ^ 2 + exit.vy ^ 2)
		local fx, fy = cos(exit.angle), sin(exit.angle)
		if sp > 50 then fx, fy = exit.vx / sp, exit.vy / sp end
		-- a station can't be swept, so slide the run sideways off one
		for _ = 1, (exit.continuous and 0 or 4) do
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
function laneXYFor(lane, s, n) return laneXY(lane.R, lane.rot or 0, s, n) end

function Game:fromLane(s, n)
	return laneXY(self.lane.R, self.lane.rot or 0, s, n)
end

-- The arc radius and turn of a lane `length` long leaving along bearing.
-- A moon's highway keeps its gentle S; a driver's lane runs dead straight
-- along the line it fired you on (an arc this big is a line), so flying
-- straight on keeps you on the road.
function Game.laneShape(length, bearing, moon)
	local Rc = moon and max(T.laneArc, length * 0.9) or 1e9
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
	self.lane = { half = self.trip.length / 2, R = Game.laneShape(self.trip.length, 0, self.trip.moon), rot = self.trip.rot or 0 }
	self.arenaRadius = 1e7
	self:populateLane()
end

-- Everything on the road, laid out once when you enter and left alone
-- until you leave: no pop-in, nothing invented as you go. A fresh layout
-- every trip (the planets have moved since the last one). Rocks drifting across the road and walls of rock either side. The first and
-- last few thousand px stay clear for the drivers.
function Game:populateLane()
	local lane, trip = self.lane, self.trip
	local rng = love.math.newRandomGenerator(random(1, 2147483646))
	local W = T.laneWidth
	local s1, s2 = -lane.half + 3000, lane.half - 3000
	local span = max(0, s2 - s1)
	-- off the road, the field reaches back past the mouth over the run-in
	-- from the map's edge, so the space you cross into the lane isn't bare
	-- (but not inside the map you left, which is there itself)
	local lead = trip.moon and T.rampLead or T.laneRunup
	local o1 = -lane.half - lead - 2000
	local ospan = max(0, s2 - o1)
	local O = trip.origin
	local OR = O and Fields[trip.from] and (Fields[trip.from].radius or 10000) + T.mapOuter + 600
	-- nor inside the map ahead, or its ring of rock past its edge: that's
	-- there itself, built ahead of you, and it's what you'll fly into
	local dest = Fields[trip.to]
	local DX, DY, DR
	if dest and not dest.transit and not trip.moon and T.mapOuter > 0 then
		DX, DY = self:laneEndCenter(false)
		DR = (dest.radius or 10000) + T.mapOuter + 600
	end
	-- what's on the road: the mix where you're headed
	local mix = dest and dest.mix
	-- Keeping rocks apart: a grid of what's been placed, so each check
	-- looks at a few neighbours (Game:isClear walks every entity, and a
	-- lane lays out tens of thousands of rocks).
	local CELL = 800
	local grid = {}
	local function key(cx, cy) return cx * 65536 + cy end
	local function at(s, n, r)
		local x, y = self:fromLane(s, n)
		if OR and (x - O.x) ^ 2 + (y - O.y) ^ 2 < (OR + r) ^ 2 then return end
		if DR and (x - DX) ^ 2 + (y - DY) ^ 2 < (DR + r) ^ 2 then return end
		local cx, cy = floor(x / CELL), floor(y / CELL)
		for i = cx - 1, cx + 1 do
			for j = cy - 1, cy + 1 do
				for _, q in ipairs(grid[key(i, j)] or {}) do
					if (q[1] - x) ^ 2 + (q[2] - y) ^ 2 < (q[3] + r) ^ 2 then return end
				end
			end
		end
		local k = key(cx, cy)
		grid[k] = grid[k] or {}
		table.insert(grid[k], { x, y, r })
		return x, y
	end
	-- on the road
	for _ = 1, floor(span / 10000 * T.laneRocks) do
		local s, n = s1 + rng:random() * span, (rng:random() * 2 - 1) * W * 0.9
		local cluster = rng:random() < 0.25 and 3 or 1
		-- the road itself is clear, so the way on reads at a glance: the
		-- only rocks on it are ones drifting across it from the sides
		local across = (n > 0 and -1 or 1) * (120 + rng:random() * 200)
		n = (n > 0 and 1 or -1) * (W + rng:random() * T.laneRamp)
		for k = 1, cluster do
			local r = 25 + rng:random() ^ 2 * (k == 1 and 140 or 50)
			local x, y = at(s + (k - 1) * 260, n + (rng:random() - 0.5) * 400, r + 60)
			if x then
				local e = self:spawnAsteroid(x, y, r, self:pickDebris(mix), nil, true)
				e.lane = "rock"
				local _, _, phi = self:toLane(x, y)
				-- (it lies still asleep, so it's still beside the road when
				-- you get there however long the trip; it starts drifting
				-- in once it wakes, as you come up on it)
				e.drift = { -sin(phi) * across, cos(phi) * across }
			end
		end
	end
	-- off the road, either side
	for _ = 1, floor(ospan / 10000 * T.laneOffroad) do
		local side = rng:random() < 0.5 and -1 or 1
		local s, n = o1 + rng:random() * ospan, side * (W + 200 + rng:random() * (T.laneRamp + 2000))
		local r = 30 + rng:random() ^ 2 * 160
		local x, y = at(s, n, r + 40)
		if x then
			local e = self:spawnAsteroid(x, y, r, self:pickDebris(mix), nil, true)
			e.lane = "offroad"
		end
	end
	-- A denser debris belt continues beyond the soft edge. Lay it out with
	-- the rest of the trip; it must not pop into view as the player wanders.
	if span>0 and T.laneOffroad>0 then
		local edge=self:laneBoundary()
		local depth=self:moonHazardDepth()
		lane.hazardDepth=depth
		local bands=math.max(1,math.ceil((depth+500)/6500))
		for _,side in ipairs({-1,1}) do
			for band=1,bands do
				for _=1,math.max(1,floor(ospan/10000*T.laneOffroad*2)) do
					local s=o1+rng:random()*ospan
					local n=side*(edge-500+((band-1)+rng:random())/bands*(depth+500))
					local r=30+rng:random()^2*160
					local x,y=at(s,n,r+40)
					if x then
						local e=self:spawnAsteroid(x,y,r,self:pickDebris(mix),nil,true)
						e.lane="hazard"
					end
				end
			end
		end
	end
end

-- Several screens of continuous debris beyond the region where braking
-- ramps up. Keep the field density when widening it and avoid lane-coordinate
-- inversion at the inside of the arc.
function Game:moonHazardDepth()
 local w,h=love.graphics.getDimensions()
 local zoom=T.minZoom
 local view=math.sqrt(w*w+h*h)/math.max(.01,zoom)
 return math.min(math.max(T.laneHazardDepth,T.edgeSoft+view*2),
  self.lane.R-self:laneBoundary()-1000)
end

-- How fast the shot off a driver carries you at distance s along the
-- lane: launched at the driver's speed (T.driverExitSpeed), slowing at a
-- steady rate so it's down to `top` (your own ship's top speed) at the far
-- end, then nothing: you're flying yourself, at a pace your ship can
-- handle on any map, however small. A steady slowing takes 2L/v to cover
-- the lane.
function Game:shotLaunch()
	return T.driverExitSpeed
end
function Game:shotSpeed(s, top)
	local lane = self.lane
	local v0, v1 = self:shotLaunch(), top or T.laneEntrySpeed
	local u = max(0, min(1, (s + lane.half) / (2 * lane.half)))
	if u >= 1 then return 0 end
	return sqrt(v0 * v0 * (1 - u) + v1 * v1 * u)
end

function Game:laneBoundary()
 return T.laneWidth+T.laneRamp+2500
end

function Game:updateLane(dt)
	local lane, p = self.lane, self.player
	if not lane then return end
	local W = T.laneWidth
	for _, e in ipairs(self.entities) do
		local b = e.body
		-- (rock is left alone in a lane: it's most of what's there, tens of
		-- thousands of pieces, and none of what follows applies to it)
		if not e.removed and e.kind ~= "asteroid" and b:getType() == "dynamic" then
			local x, y = b:getPosition()
			local s, n, phi = self:toLane(x, y)
			local tx, ty = cos(phi), sin(phi)
			local m = b:getMass()
			if e.kind == "ship" then
				-- in the lane: the buff (thrust up, drag down)
				local k = self:laneStrength(n)
				-- (not on a moon trip: just your own ship in open space)
				e.laneBuff = k > 0 and not (self.trip and self.trip.moon) and k or nil
				if e == p then
					-- A driver's lane: you're the shot. Your speed along the
					-- road is the shot's, losing pace at a steady rate from
					-- the launch to your own ship's speed at the far end
					-- (Game:shotSpeed); your engine only steers you across
					-- it. Your drag is measured against the shot, so steering
					-- feels like ordinary flight. A moon trip is just your
					-- own ship in open space.
					local flow = 0
					if not (self.trip and self.trip.moon) then
						e.laneBuff = 1
						e.ownTop = e.ownTop or Ship.performance(e).topSpeed
						local c = self:shotSpeed(s, e.ownTop)
						if c > 0 then
							-- The shot is the least you're doing, never the
							-- most: your drag is measured against the shot
							-- less your own top speed, so at full throttle you
							-- do the shot's speed, and on the afterburner more.
							-- (At the end that frame is still: it's just you.)
							flow = max(0, c - e.ownTop)
							local vx, vy = b:getLinearVelocity()
							local va = vx * tx + vy * ty
							if va < c then b:setLinearVelocity(vx + tx * (c - va), vy + ty * (c - va)) end
						end
					end
					e.laneFrame = true
					if flow ~= 0 then e.flowX, e.flowY = tx * flow, ty * flow else e.flowX, e.flowY = nil, nil end
				elseif e.cruise and not (self.trip and self.trip.moon) then
					-- traffic rides the lane the same way, its own direction
					local flow = T.laneFlow * (e.cruiseDir or 1) * k
					e.laneFrame = true
					if flow ~= 0 then e.flowX, e.flowY = tx * flow, ty * flow else e.flowX, e.flowY = nil, nil end
				end
			end
			-- Shared soft lateral edge, including moon trips. Debris beyond
			-- it stays in place instead of being herded back into the road.
			-- (you, in a driver's lane: only past the far side of the
			-- walls, so the rock is all that's in your way, never an
			-- edge pinning you against it)
			local edge = self:laneBoundary()
			if e == p and not (self.trip and self.trip.moon) then edge = edge + (lane.hazardDepth or 0) + 1000 end
			local over = abs(n) - edge
			local moonDebris=e.kind=="asteroid"
			if over > 0 and not moonDebris then
				local sign=n>0 and 1 or -1
				local nx,ny=-sin(phi)*sign,cos(phi)*sign
				local vx,vy=b:getLinearVelocity()
				local force=softBoundary(over,vx*nx+vy*ny,m)
				b:applyForce(nx*force,ny*force)
			end
			if s < -lane.half and e ~= p and e.kind == "ship" and not (self.trip and self.trip.moon) then b:applyForce(tx * (-lane.half - s) * m * 6, ty * (-lane.half - s) * m * 6) end
		end
	end
	if not p or p.dead then return end
	local ps, pn, ph = self:toLane(p.body:getPosition())
	local R = p.runup
	if R then
		-- the run-up: held on the line into the mouth, braking from the
		-- driver's speed to the lane's
		local tx, ty = cos(R.h), sin(R.h)
		local x, y = p.body:getPosition()
		local u = max(0, min(1, ((x - R.x) * tx + (y - R.y) * ty) / T.laneRunup))
		-- easing off only a little: you hit the lane still carrying most of
		-- the driver's kick
		local keep = self:shotLaunch()
		local sp = R.speed + (keep - R.speed) * u * u
		local it = p.intent
		it.thrust, it.strafe, it.boost = 0, 0, false
		it.firePrimary, it.fireSecondary, it.fireTertiary = false, false, false
		p.body:setLinearVelocity(tx * sp, ty * sp)
		p.body:setAngle(R.h)
		p.body:setAngularVelocity(0)
		if u >= 1 then
			p.runup = nil
			self:toast("ON THE HIGHWAY", 1.5)
		end
		return
	end
	if ps > -lane.half then p.laneEntered = true end
	if ps > lane.half - 400 and not p.launch then self.pendingArrive = true end
	-- turned round and flew back out the near end: home again (off a
	-- map's edge you start short of the mouth, so only once you're in)
	local vx, vy = p.body:getLinearVelocity()
	local reversing = vx * cos(ph) + vy * sin(ph) < 0
	-- (only off a moon hop: a driver's lane has no way back)
	if self.trip.moon and ps < -lane.half - 200 and (p.laneEntered or not self.trip.origin or reversing) then self.pendingArrive = "back" end
end

-- Traffic flies its own side of the lane at its own speed, nose along
-- the lane: thrusting (and side-jetting) to match the velocity it wants.
function Game:cruise(e, dt)
	local x, y = e.body:getPosition()
	local along, n, phi = self:toLane(x, y)
	local dir = e.cruiseDir or (self:laneFlow(n) >= 0 and 1 or -1)
	local tx, ty = cos(phi) * dir, sin(phi) * dir
	local want = T.laneFlow * (e.cruiseSpeed or 1)
	local across = e.cruiseOffset and (e.cruiseOffset - n) * 0.4 or 0
	local wvx, wvy = tx * want - sin(phi) * across, ty * want + cos(phi) * across
	-- Retaliation still runs for the same trader while it flies its lane.
	-- (not a lane-behind-you ghost: its record went back to the universe)
	if e.def and not e.ghostCruise then AI.think(self, e, dt or 1 / 120) end
	AI.navigate(self,e,wvx,wvy,sqrt(wvx*wvx+wvy*wvy),0,0,self.lane.half-along*dir)
	if not e.aggressor then e.intent.aimX, e.intent.aimY = x + tx * 1000, y + ty * 1000 end
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
	if e.locationId then return Locations.position(e.locationId, self.universe.clock) end
	local w, d, t = self.well, e.drift, self.universe.clock
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
function Game:spawnCloudCity(a, k, locationId, layoutId)
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
	local id = layoutId or Stations.cityId(k)
	if not data.stations[id] then
		local _, err = data.defineStation(Stations.city(k))
		if err then error(err) end
	end
	local def = data.stations[id]
	local e = { kind = "station", city = true, invulnerable = true, id = self:nextId(), team = 0, body = body,
		def = def, key = ("%s/runtime_station_%d"):format(self.fieldId or "?", n), locationId = locationId,
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
	if locationId then
		local location = Locations.get(locationId)
		e.key, e.name = location.id, location.name
	end
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
	if locationId then self:bindLocation(e, locationId) end
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
-- turning slowly (Game:updateRotors spins it from the clock). Four elevator
-- anchors (data/station_ladder_anchor.lua) hold still where the tethers
-- come up from the surface; the ring runs through them, and each has a
-- dock and berths for the traffic waiting on the Ladder.
local LADDER_SPIN = 0.006   -- radians a second (about 50 px/s at the rim)
function Game:spawnHeavenLadder(cx, cy, R)
	local w = self.well
	local surface = w and w.radius or R - 1000
	local thick, gaps, gapW = 100, 8, 700   -- thick: half the ring's depth (the anchors' channel is 110 each side)
	local gapA = gapW / R
	local segments = {}
	for i = 0, gaps - 1 do
		local a1 = (i + 0.5) / gaps * pi * 2 + gapA / 2
		local a2 = (i + 1.5) / gaps * pi * 2 - gapA / 2
		local n = math.ceil((a2 - a1) * R / 400)
		for k = 0, n - 1 do
			local b1, b2 = a1 + (a2 - a1) * k / n, a1 + (a2 - a1) * (k + 1) / n
			local e = self:addStructure({
				cx + cos(b1) * (R - thick), cy + sin(b1) * (R - thick),
				cx + cos(b2) * (R - thick), cy + sin(b2) * (R - thick),
				cx + cos(b2) * (R + thick), cy + sin(b2) * (R + thick),
				cx + cos(b1) * (R + thick), cy + sin(b1) * (R + thick),
			}, { role = "ladder" })
			-- the gate lights at each end of an arc, either side of a gap
			e.gate = (k == 0 and 1 or 0) + (k == n - 1 and 2 or 0)
			-- lit windows, in districts: each arc is cut into modules of
			-- different lengths, and each module is housing (a dense warm
			-- grid), industry (one sparse amber strip), a greenhouse (a
			-- green band on the planet side), a sign (a short cyan run) or
			-- dark; within a module some rooms are out. Deterministic, so
			-- the ring looks the same every visit.
			local function hash(...)
				local h = 2166136261
				for _, v in ipairs({ ... }) do h = (h * 16777619 + v * 2654435761) % 4294967296 end
				return h
			end
			local wins = {}
			local step = 34 / R                      -- one window's pitch, as an angle
			local rows = { -0.75, -0.45, -0.15, 0.15, 0.45, 0.75 }
			local t = b1 + step
			local m = 0
			while t < b2 - step do
				m = m + 1
				local h = hash(i, k, m)
				local len = 3 + h % 9                 -- windows in this module
				local kind = math.floor(h / 16) % 10   -- 0-4 housing, 5-6 industry, 7 greenhouse, 8 sign, 9 dark
				local lit = 0.55 + (math.floor(h / 256) % 40) / 100
				for j = 0, len - 1 do
					local tj = t + j * step
					if tj > b2 - step then break end
					for r, off in ipairs(rows) do
						local show, col
						if kind <= 4 then
							show, col = r >= 2 and r <= 5, (hash(i, k, m, j, r) % 100 < lit * 100) and 1 or nil
						elseif kind <= 6 then
							show, col = r == 3 and j % 2 == 0, 4
						elseif kind == 7 then
							show, col = r <= 2, 2
						elseif kind == 8 then
							show, col = r == 4 and j < 4, 3
						end
						if show and col then
							local rr = R + off * thick
							wins[#wins + 1] = { cx + cos(tj) * rr, cy + sin(tj) * rr, col }
						end
					end
				end
				t = t + (len + 1 + math.floor(h / 4096) % 3) * step   -- a gap of bulkhead between modules
			end
			e.windows = wins
			e.body:setType("kinematic")
			segments[#segments + 1] = e
		end
	end
	self.ladder = { segments = segments, spin = LADDER_SPIN, cx = cx, cy = cy }
	-- the elevators: still anchors on the ring, tethers down to the surface
	for i = 0, 3 do
		local a = (i * 2 + 1) / gaps * pi * 2
		local ux, uy, nx, ny = cos(a), sin(a), -sin(a), cos(a)
		local tw = 24
		local top = R - 560   -- the anchor's tether head
		self:addStructure({
			cx + ux * surface + nx * tw, cy + uy * surface + ny * tw,
			cx + ux * top + nx * tw, cy + uy * top + ny * tw,
			cx + ux * top - nx * tw, cy + uy * top - ny * tw,
			cx + ux * surface - nx * tw, cy + uy * surface - ny * tw,
		}, { role = "tether" })
		-- one station, four access points: they share its location ID and
		-- key (so its storage, hangar and market), and Game:locationEntity
		-- picks the nearest when given a position. The first is bound to the
		-- location; the rest hold still where they are.
		local ids = self.field and self.field.ladderIds
		local id = ids and ids[i + 1]
		local st = self:spawnStation("ladder_anchor", cx + ux * R, cy + uy * R, 0, false, id)
		st.body:setAngle(a)
		st.body:setAngularVelocity(0)
		st.accessIndex = i + 1
		if id then
			-- each anchor is its own location; the station record is the Ladder's
			st.key = ids[1]
			st.name = require("src.locations").get(ids[1]).name .. (" (anchor %d)"):format(i + 1)
		end
	end
end

end
