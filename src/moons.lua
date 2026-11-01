--[[
	Moons, and getting to them. Each moon is its own small map (Fields.moons
	in src/fields.lua lists them); you don't take a mass driver there.

	  on-ramps  every planet with moons has an on-ramp on the edge of its map
	            for each one, the way the moon lies from the planet right
	            now (Fields.moonAngle), so it slides round the edge as the
	            moon orbits. A moon's map has one, back toward its planet.
	            Fly off the edge of the map through one and you're on the
	            highway (src/transit.lua, Game:launchTrip): the same run-up,
	            lane and arrival as a mass driver trip, only short (the
	            moon's gap), with the moon drawn ahead at the end. You come
	            off it in from the moon's map edge, flying as you were.

	Everything comes from a moon's data entry (parent, period, phase,
	gap), so a new moon needs no code here.

	Added to Game by src/game.lua: require("src.moons")(Game).
]]

local T = require("src.tuning")
local Fields = require("src.fields")

local sqrt, cos, sin, pi, abs = math.sqrt, math.cos, math.sin, math.pi, math.abs

local function wrap(a) return (a + pi) % (2 * pi) - pi end

return function(Game)

-- The on-ramps in this map: { to, label, angle(clock), a, x, y, radius }.
function Game:spawnMoonGates()
	self.moonGates = {}
	local id, F = self.fieldId, self.field
	if not F.planetR then return end
	local function add(to, angle)
		table.insert(self.moonGates, { to = to, label = "Highway to " .. Fields[to].name, angle = angle, radius = 0 })
	end
	for _, m in ipairs(Fields.moonsOf(id)) do
		add(m, function(clock) return Fields.moonAngle(m, clock) end)
	end
	local moon = Fields.moons[id]
	if moon then
		add(moon.parent, function(clock) return Fields.moonAngle(id, clock) + pi end)
	end
	self:placeMoonGates()
end

function Game:placeMoonGates()
	local clock = self.universe and self.universe.clock or 0
	local d = self.arenaRadius - T.rampInset
	for _, g in ipairs(self.moonGates or {}) do
		local a = g.angle(clock)
		g.a, g.x, g.y, g.d = a, cos(a) * d, sin(a) * d, d
		g.half = T.rampWidth / 2 / self.arenaRadius   -- how wide it is, as an angle
	end
end

-- Off the edge of the map through an on-ramp, heading out: onto the
-- highway to that moon (or back to the planet).
function Game:updateMoonGates(dt)
	if not self.moonGates or #self.moonGates == 0 then return end
	self:placeMoonGates()
	local p = self.player
	if not p or p.dead or p.dockState or self.state ~= "playing" or self.lane then return end
	local x, y = p.body:getPosition()
	local r = sqrt(x * x + y * y)
	if r < self.arenaRadius - T.rampInset then return end
	local vx, vy = p.body:getLinearVelocity()
	if vx * x + vy * y <= 0 then return end
	local a = math.atan2(y, x)
	for _, g in ipairs(self.moonGates) do
		if abs(wrap(a - g.a)) < g.half then
			local m = Fields.moons[g.to] or Fields.moons[self.fieldId]
			return self:launchTrip(g.to, { bearing = a, length = m.gap })
		end
	end
end

end
