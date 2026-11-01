--[[
	Station layouts as parts, the same format as hulls (src/hullshape.lua),
	so the Shipyard (F2) can open, redraw and export them.

	A station definition (data.stations, from station { } in data files or
	made here) is:
	  parts  polygons as for hulls; exactly one part says dock = true. Its
	         box is the docking module: the door is its +x end, facing out.
	  dock   optional overrides for the dock: wall, runway, capture
	  color  outline colour (fill is a darker shade of it)

	Stations.ring builds the classic wheel: a ring of arc segments, four
	spokes, a hub and a square dock on the rim, with windows along the
	ring and red beacons on it. Game:spawnWheelStation asks for
	"ring_<R>_<tube>", and a station { } with that id (say, exported from
	the Shipyard into the mods folder) replaces the generated one.
]]

local Stations = {}

local cos, sin, pi, max, floor = math.cos, math.sin, math.pi, math.max, math.floor

local function round(v) return floor(v + 0.5) end

function Stations.ringId(R, tube)
	return ("ring_%d_%d"):format(R, tube)
end

function Stations.ring(R, tube)
	local parts = {}
	local ri, ro = R - tube / 2, R + tube / 2
	local hub = R * 0.2
	local ARCS, SEG = 16, 12           -- ring pieces, and segments in each
	local winR = max(tube * 0.05, 2)
	for a = 0, ARCS - 1 do
		local shape = {}
		local a1, a2 = a / ARCS * pi * 2, (a + 1) / ARCS * pi * 2
		for k = 0, SEG do
			local t = a1 + (a2 - a1) * k / SEG
			table.insert(shape, round(cos(t) * ro)); table.insert(shape, round(sin(t) * ro))
		end
		for k = SEG, 0, -1 do
			local t = a1 + (a2 - a1) * k / SEG
			table.insert(shape, round(cos(t) * ri)); table.insert(shape, round(sin(t) * ri))
		end
		-- windows along the outer and inner faces, skipping every seventh
		local lights = {}
		local n = max(1, floor(R / 14 / ARCS))
		for k = 0, n - 1 do
			if k % 7 ~= 3 then
				local t = a1 + (a2 - a1) * (k + 0.5) / n
				local c, s = cos(t), sin(t)
				table.insert(lights, { x = round(c * (ro - tube * 0.16)), y = round(s * (ro - tube * 0.16)), kind = "window", size = winR })
				table.insert(lights, { x = round(c * (ri + tube * 0.16)), y = round(s * (ri + tube * 0.16)), kind = "window", size = winR })
			end
		end
		-- red beacons on the rim, between the spokes
		if a % (ARCS / 4) == ARCS / 8 then
			local t = a1
			table.insert(lights, { x = round(cos(t) * ro), y = round(sin(t) * ro), kind = "strobe",
				color = { 1, 0.35, 0.3 }, size = max(tube * 0.06, 3), rate = 1 / 1.6 })
		end
		table.insert(parts, { name = "ring " .. (a + 1), shape = shape, lights = lights })
	end
	-- spokes, drawn under the ring
	local sw = tube * 0.22
	for k = 0, 3 do
		local t = k / 4 * pi * 2
		local c, s = cos(t), sin(t)
		local px, py = -s * sw, c * sw
		local h0, h1 = hub * 0.9, ri + 4
		table.insert(parts, 1, { name = "spoke " .. (k + 1), shade = 0.85, shape = {
			round(c * h0 + px), round(s * h0 + py), round(c * h1 + px), round(s * h1 + py),
			round(c * h1 - px), round(s * h1 - py), round(c * h0 - px), round(s * h0 - py) } })
	end
	-- the hub, and a ring of detail on it
	local hubShape, inner = {}, {}
	for k = 0, 47 do
		local t = k / 48 * pi * 2
		table.insert(hubShape, round(cos(t) * hub)); table.insert(hubShape, round(sin(t) * hub))
		table.insert(inner, round(cos(t) * hub * 0.45)); table.insert(inner, round(sin(t) * hub * 0.45))
	end
	table.insert(parts, { name = "hub", shape = hubShape, shade = 1.1 })
	table.insert(parts, { name = "hub core", shape = inner, layer = "detail", collide = false })
	-- the dock: a square module on the rim along +x, door facing out
	local D = max(300, tube * 2)
	local x1, x2, hw = R + tube / 2 - tube * 0.3, R + tube / 2 + D, D / 2
	table.insert(parts, { name = "dock", dock = true, shape = { round(x1), round(-hw), round(x2), round(-hw), round(x2), round(hw), round(x1), round(hw) } })
	return {
		id = Stations.ringId(R, tube), name = ("Ring station %d"):format(R),
		parts = parts, color = { 0.55, 0.63, 0.74 },
	}
end

return Stations
