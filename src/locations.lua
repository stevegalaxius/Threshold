-- Authored places exist independently of loaded physics bodies. These IDs
-- identify places, not their display names or their order in a spawn loop.
local Fields = require("src.fields")
local T = require("src.tuning")
local L = { byId = {}, byArea = {} }
local pi, cos, sin = math.pi, math.cos, math.sin

for _, area in ipairs(Fields.list) do
	L.byArea[area] = {}
	for _, location in ipairs(Fields[area].locations or {}) do
		assert(not L.byId[location.id], "duplicate location " .. location.id)
		assert(location.area == area, "location assigned to the wrong area")
		if location.id == "station/hub_station" then location.marketId = "venus/hub_station" end
		L.byId[location.id] = location
		L.byArea[area][#L.byArea[area] + 1] = location
	end
end

function L.get(id) return assert(L.byId[id], "unknown location " .. tostring(id)) end
function L.list(area) return L.byArea[area] or {} end

function L.rate(m)
	if m.period then return pi * 2 / (T.yearLength * m.period) end
	if m.surface then
		local at = m.flowRadius or m.radius
		return 290 * math.sqrt(m.surface / math.max(at, m.surface)) * T.currentScale * (m.speedScale or 1) / m.radius
	end
	return m.rate or 0
end

-- The optional third result is the radial bearing. Cloud-city orientation
-- and an idle driver's barrel use it; station spin is independent of orbit.
function L.position(id, clock)
	local m = L.get(id).motion
	if m.type == "fixed" then return m.x, m.y, 0 end
	if m.type == "cloud" then
		local r = m.r + m.up * sin(clock / m.upPeriod * pi * 2 + m.phase)
		local a = m.a + m.across * sin(clock / m.acrossPeriod * pi * 2 + m.phase * 0.7) / m.r
		return cos(a) * r, sin(a) * r, a
	end
	local a = m.phase + clock * L.rate(m)
	return (m.cx or 0) + cos(a) * m.radius, (m.cy or 0) + sin(a) * m.radius, a
end

function L.heading(id, clock)
	local location = L.get(id)
	if location.motion.type == "cloud" then
		local _, _, a = L.position(id, clock)
		return a + pi / 2
	end
	return (location.heading or 0) + (location.spin or 0) * clock
end

function L.velocity(id, clock)
	local x1, y1 = L.position(id, clock - 0.01)
	local x2, y2 = L.position(id, clock + 0.01)
	return (x2 - x1) / 0.02, (y2 - y1) / 0.02
end

function L.install(Game)
	function Game:bindLocation(e, id)
		local location = L.get(id)
		assert(location.area == self.fieldId, "binding a location from another area")
		e.locationId = id
		if e.kind == "station" then e.key, e.name = id, location.name end
		local clock = self.universe.clock
		e.body:setPosition(L.position(id, clock))
		e.body:setAngle(L.heading(id, clock))
		e.body:setLinearVelocity(L.velocity(id, clock))
		e.body:setAngularVelocity(location.spin or 0)
		return e
	end

	function Game:syncLocations()
		for _, e in ipairs(self.entities) do
			if e.locationId and not e.removed then
				e.body:setPosition(L.position(e.locationId, self.universe.clock))
				e.body:setAngle(L.heading(e.locationId, self.universe.clock))
				e.body:setLinearVelocity(L.velocity(e.locationId, self.universe.clock))
			end
		end
	end

	function Game:locationEntity(id)
		for _, e in ipairs(self.entities) do
			if e.locationId == id and not e.removed then return e end
		end
	end
end

return L
