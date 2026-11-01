--[[
	Moons, and getting to them. Each moon is its own small map (Fields.moons
	in src/fields.lua lists them); you don't take a mass driver there.

	  gates     every planet with moons has a gate for each one on the edge
	            of its map, sitting the way the moon lies from the planet
	            right now (Fields.moonAngle), so it slides round the edge
	            as the moon orbits. A moon's map has one gate, back toward
	            its planet. They're markers, not solid: fly out through
	            one (moving outward) and you're on the crossing.
	  crossing  a short stretch of open space (the "crossing" field), flown
	            at your own speed: the planet you left is drawn behind you
	            and the one you're heading for ahead. Reach the far end and
	            you come in through the destination's gate; turn round and
	            go back past the start and you're home again.

	Everything comes from a moon's data entry (parent, period, phase,
	gap), so a new moon needs no code here.

	Added to Game by src/game.lua: require("src.moons")(Game).
]]

local T = require("src.tuning")
local Ship = require("src.ship")
local Fields = require("src.fields")
local events = require("src.events")

local sqrt, cos, sin, pi, max = math.sqrt, math.cos, math.sin, math.pi, math.max

return function(Game)

-- Gates -----------------------------------------------------------------------

-- The gates in this map: { to, label, angle(), x, y, radius }.
function Game:spawnMoonGates()
	self.moonGates = {}
	if self.fieldId ~= "crossing" then self.crossing = nil end
	local id, F = self.fieldId, self.field
	if not F.planetR then return end
	local d = self.arenaRadius - T.gateInset
	local function add(to, label, angle)
		table.insert(self.moonGates, { to = to, label = label, angle = angle, d = d, radius = T.gateRadius })
	end
	for _, m in ipairs(Fields.moonsOf(id)) do
		add(m, "To " .. Fields[m].name, function(clock) return Fields.moonAngle(m, clock) end)
	end
	local moon = Fields.moons[id]
	if moon then
		add(moon.parent, "To " .. Fields[moon.parent].name, function(clock) return Fields.moonAngle(id, clock) + pi end)
	end
	self:placeMoonGates()
end

function Game:placeMoonGates()
	local clock = self.universe and self.universe.clock or 0
	for _, g in ipairs(self.moonGates or {}) do
		local a = g.angle(clock)
		g.x, g.y, g.a = cos(a) * g.d, sin(a) * g.d, a
	end
end

function Game:updateMoonGates(dt)
	if self.fieldId == "crossing" then return self:updateCrossing(dt) end
	if not self.moonGates or #self.moonGates == 0 then return end
	self:placeMoonGates()
	local p = self.player
	if not p or p.dead or p.dockState or self.state ~= "playing" then return end
	local x, y = p.body:getPosition()
	local vx, vy = p.body:getLinearVelocity()
	for _, g in ipairs(self.moonGates) do
		local dx, dy = x - g.x, y - g.y
		-- inside it and heading out of the map
		if dx * dx + dy * dy < g.radius * g.radius and vx * cos(g.a) + vy * sin(g.a) > 0 then
			return self:beginCrossing(g.to)
		end
	end
end

-- Coming in through the gate that leads to `to` (the map you just left),
-- a little way inside the map, heading inward at the speed you came.
function Game:placeAtGate(p, to, exit)
	for _, g in ipairs(self.moonGates or {}) do
		if g.to == to then
			local d = g.d - T.gateArrive
			local x, y = cos(g.a) * d, sin(g.a) * d
			local h = g.a + pi
			local sp = exit and exit.speed or 0
			p.body:setPosition(x, y)
			p.body:setAngle(h)
			p.body:setLinearVelocity(cos(h) * sp, sin(h) * sp)
			self.camera.x, self.camera.y = x, y
			return true
		end
	end
	return false
end

-- The crossing ------------------------------------------------------------------

-- How long the crossing between a planet and its moon is (either way).
local function gap(a, b)
	local m = Fields.moons[a] or Fields.moons[b]
	return m and m.gap or T.crossingDefault
end

function Game:beginCrossing(to)
	local p = self.player
	if not p or p.dead then return end
	local from = self.fieldId
	local vx, vy = p.body:getLinearVelocity()
	local speed = max(T.crossingMinSpeed, sqrt(vx * vx + vy * vy))
	self.crossing = { from = from, to = to, length = gap(from, to) }
	local half = self.crossing.length / 2
	self:loadField("crossing", { player = Ship.record(p),
		at = { x = -half + T.gateArrive, y = 0, angle = 0, vx = speed, vy = 0 } })
	self:toast(("%s TO %s"):format(Fields[from].name:upper(), Fields[to].name:upper()), 3)
	events.emit("travel", from, to)
end

-- The crossing runs along +x from (-half, 0) to (half, 0). A few pieces of
-- the destination's debris drift in the middle.
function Game:buildCrossing()
	if not self.crossing then
		-- reached from the debug panel: Earth to Luna
		self.crossing = { from = "earth", to = "luna", length = gap("earth", "luna") }
	end
	local c = self.crossing
	local half = c.length / 2
	c.half = half
	self.arenaRadius = half + T.crossingMargin
	local dest = Fields[c.to]
	local mix = dest and dest.mix
	local n = math.floor(c.length / 1000 * T.crossingDebris)
	for _ = 1, n do
		local x = (love.math.random() * 2 - 1) * (half - 4000)
		local y = (love.math.random() * 2 - 1) * T.crossingSpread
		local kind = self:pickDebris(mix)
		local r = self:debrisSize(kind)
		if self:isClear(x, y, r + 40) then self:spawnDebris(kind, x, y, r) end
	end
end

-- Where the two ends' worlds are drawn: the one you left behind the start,
-- the one ahead past the finish (src/render.lua).
function Game:crossingEnds()
	local c = self.crossing
	if not c or not c.half then return end
	local A, B = Fields[c.from], Fields[c.to]
	return { F = A, x = -c.half - (A.planetR or 0) - T.crossingView, y = 0 },
		{ F = B, x = c.half + (B.planetR or 0) + T.crossingView, y = 0 }
end

function Game:updateCrossing(dt)
	local p, c = self.player, self.crossing
	if not p or p.dead or not c then return end
	local x = p.body:getPosition()
	if x > c.half then return self:endCrossing(c.to, c.from) end
	if x < -c.half then return self:endCrossing(c.from, c.to) end
end

-- Out of the crossing into `dest`, through its gate toward `other`.
function Game:endCrossing(dest, other)
	local p = self.player
	local vx, vy = p.body:getLinearVelocity()
	local sp = sqrt(vx * vx + vy * vy)
	self.crossing = nil
	self:loadField(dest, { player = Ship.record(p), at = { gate = other, exit = { speed = sp } } })
end

end
