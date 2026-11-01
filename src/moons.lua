--[[
	Moons, and getting to them. Each moon is its own small map (Fields.moons
	in src/fields.lua lists them); you don't take a mass driver there.

	  ways out  every planet with moons has a stretch of its map's edge for
	            each one (T.departArc wide), the way the moon lies from the
	            planet right now (Fields.moonAngle), so it slides round the
	            edge as the moon orbits. A moon's map has one, back toward
	            its planet. The map's edge lets you through there.
	  departure fly out past the edge there and it plays like a mass
	            driver's coast: you swing onto the bearing at your own
	            speed while the camera pulls wide, then you're in
	            transit (Game:launchTrip, a short lane, the moon's gap). You
	            come out of it into the moon's map flying as you were.

	Everything comes from a moon's data entry (parent, period, phase,
	gap), so a new moon needs no code here.

	Added to Game by src/game.lua: require("src.moons")(Game).
]]

local T = require("src.tuning")
local Fields = require("src.fields")

local sqrt, cos, sin, pi, abs = math.sqrt, math.cos, math.sin, math.pi, math.abs


return function(Game)

-- The ways out in this map: { to, label, angle(clock), a, x, y, length }.
-- x, y is the edge of the map in the direction of the moon (or planet).
function Game:spawnMoonGates()
	self.moonGates = {}
	local id, F = self.fieldId, self.field
	if not F.planetR then return end
	local function add(to, angle, m)
		table.insert(self.moonGates, { to = to, label = Fields[to].name, angle = angle, length = m.gap })
	end
	for _, m in ipairs(Fields.moonsOf(id)) do
		add(m, function(clock) return Fields.moonAngle(m, clock) end, Fields.moons[m])
	end
	local moon = Fields.moons[id]
	if moon then
		add(moon.parent, function(clock) return Fields.moonAngle(id, clock) + pi end, moon)
	end
	self:placeMoonGates()
end

function Game:placeMoonGates()
	local clock = self.universe and self.universe.clock or 0
	local R = self.arenaRadius
	for _, g in ipairs(self.moonGates or {}) do
		local a = g.angle(clock)
		g.a, g.x, g.y = a, cos(a) * R, sin(a) * R
	end
end

-- Which way out (x, y) is heading for, if it's off the map's edge toward
-- a moon (or back toward the planet).
function Game:moonGateAt(x, y)
	local a = math.atan2(y, x)
	local arc = T.departArc / 2 / self.arenaRadius
	for _, g in ipairs(self.moonGates or {}) do
		if abs((a - g.a + pi) % (2 * pi) - pi) < arc then return g end
	end
end

function Game:onMoonRoad(x, y) return self:moonGateAt(x, y) ~= nil end

-- Flying out past the edge toward a moon starts the departure, which
-- plays like a mass driver's coast: the ship swings onto the bearing at
-- the speed it was going while the camera pulls wide and the planet
-- falls away behind, then it's into transit (Game:launchTrip, placed so
-- nothing on screen jumps).
function Game:updateMoonGates(dt)
	if not self.moonGates or #self.moonGates == 0 then return end
	self:placeMoonGates()
	local p = self.player
	if not p or p.dead or p.dockState or self.state ~= "playing" or self.lane then return end
	if p.departure then return self:updateDeparture(p, dt) end
	local x, y = p.body:getPosition()
	if x * x + y * y < (self.arenaRadius - T.departInset) ^ 2 then return end
	local vx, vy = p.body:getLinearVelocity()
	if vx * x + vy * y <= 0 then return end
	local g = self:moonGateAt(x, y)
	if not g then return end
	local sp = sqrt(vx * vx + vy * vy)
	p.departure = { to = g.to, length = g.length, t = 0, speed0 = sp }
	self.savedZoom = self.savedZoom or self.camera.zoom
	self:toast(("TRANSIT TO %s"):format(Fields[g.to].name:upper()), 2.5)
end

function Game:updateDeparture(p, dt)
	local D = p.departure
	D.t = D.t + dt
	local u = math.min(1, D.t / T.departTime)
	-- the bearing: straight out from the planet where you are
	local x, y = p.body:getPosition()
	local b = math.atan2(y, x)
	D.bearing = b
	local it = p.intent
	it.thrust, it.strafe, it.boost = 0, 0, false
	it.firePrimary, it.fireSecondary, it.fireAux = false, false, false
	local a = p.body:getAngle()
	p.body:setAngle(a + ((b - a + pi) % (2 * pi) - pi) * math.min(1, dt * 3))
	p.body:setAngularVelocity(0)
	-- your own speed, just turned onto the bearing: no kick
	local s = D.speed0
	p.body:setLinearVelocity(cos(b) * s, sin(b) * s)
	if not D.ghost then
		D.ghost = true
		for _, f in ipairs(p.body:getFixtures()) do f:setSensor(true) end
	end
	local wide = math.min(self.savedZoom, T.cineZoom)
	self.cineZoom = self.savedZoom + (wide - self.savedZoom) * (1 - (1 - u) ^ 2)
	if u >= 1 then
		p.departure = nil
		self.flash = { t = 0, life = 0.5 }
		return self:launchTrip(D.to, { bearing = b, length = D.length })
	end
end

end
