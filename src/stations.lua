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

-- A strip-mined moon, made from the editor's ordinary polygons, detail
-- layers, relative shading and lights. The terraced cut opens to +x;
-- ships use its recessed tractor dock, with no projecting docking arms.
function Stations.mine(id, name, R)
	local parts = {}
	local function polygon(name, points, shade, detail)
		local shape = {}
		for i, v in ipairs(points) do shape[i] = round(v * R) end
		local p = { name = name, shape = shape, shade = shade,
			layer = detail and "detail" or nil }
		if detail then p.collide = false end
		parts[#parts + 1] = p
		return p
	end
	local function box(name, x1, y1, x2, y2, shade, detail)
		return polygon(name, { x1, y1, x2, y1, x2, y2, x1, y2 }, shade, detail)
	end
	polygon("excavated moon", {
		-1.05, -0.18, -0.86, -0.63, -0.35, -0.84, 0.15, -0.78,
		0.55, -0.65, 0.91, -0.4, 0.65, -0.4, 0.65, -0.25,
		0.4, -0.25, 0.4, -0.15, 0.1, -0.15, 0.1, 0.15,
		0.4, 0.15, 0.4, 0.25, 0.65, 0.25, 0.65, 0.4, 0.9, 0.4,
		0.6, 0.69, 0.1, 0.81, -0.5, 0.74, -0.95, 0.35,
	}, 0.65)
	-- Broad excavation benches remain legible when zoomed out.
	for k = 1, 3 do
		local y = 0.28 + k * 0.12
		box("upper cut " .. k, -0.6, -y - 0.035, 0.52 - k * 0.06, -y, 0.45, true)
		box("lower cut " .. k, -0.6, y, 0.52 - k * 0.06, y + 0.035, 0.45, true)
	end
	-- Hard-edged processing modules and visible scaffold diagonals.
	for k = 0, 5 do
		local x = -0.73 + k * 0.24
		box("container " .. k, x, -0.89, x + 0.18, -0.73, k % 2 == 0 and 1 or 0.85)
		box("service frame " .. k, x, -0.98, x + 0.025, -0.61, 0.55)
		polygon("diagonal " .. k, { x, -0.98, x + 0.025, -0.98,
			x + 0.18, -0.73, x + 0.155, -0.73 }, 0.7, true)
	end
	box("processing spine", -0.82, -0.73, 0.76, -0.68, 0.8)
	local dock = box("tractor dock", 0.1, -0.13, 0.28, 0.13, 1.1)
	dock.dock = true
	dock.lights = {
		{ x = round(R * 0.26), y = round(-R * 0.12), kind = "strobe", size = 14 },
		{ x = round(R * 0.26), y = round(R * 0.12), kind = "strobe", size = 14 },
	}
	return { id = id, name = name .. " Strip Mine", parts = parts,
		color = { 0.55, 0.63, 0.74 } }
end

-- Cloud cities -----------------------------------------------------------

Stations.CITY_TUNNEL, Stations.CITY_HALF = 192, 896   -- tunnel half-height and half-length
local CITY_TUNNEL, CITY_HALF = Stations.CITY_TUNNEL, Stations.CITY_HALF

local function cityPart(y1, y2, w, ct, cb, role)
	return { verts = { -w + ct, y1, w - ct, y1, w, y1 + ct * 0.6, w, y2 - cb * 0.6, w - cb, y2, -w + cb, y2, -w, y2 - cb * 0.6, -w, y1 + ct * 0.6 },
		y1 = y1, y2 = y2, w = w, ct = ct, cb = cb, role = role }
end

local function cityParts(k)
	local parts = {}
	local function add(...) parts[#parts + 1] = cityPart(...) end
	local T, H = CITY_TUNNEL, CITY_HALF
	-- over the tunnel: the roof (overhanging the mouths on a big city),
	-- then more levels stepping in
	local roofW = H + 560 * (k - 1)
	local top = -T - 176 * k
	add(top, -T, roofW, 160 * k, 0, "roof")
	local levelW = roofW
	for i = 1, 2 * (k - 1) do
		levelW = levelW * 0.72
		local h = 288
		add(top - h, top + 8, levelW, 100, 0, "level")
		top = top - h
	end
	-- the spire: a collar and a mast
	add(top - 176, top + 16, 192, 96, 0, "collar")
	local mast = 1040 * k
	add(top - 176 - mast, top - 160, 40, 0, 0, "mast")
	-- under the tunnel: its floor, the deck, a collar and the stalk
	add(T, T + 160, H, 0, 0, "floor")
	local d1 = T + 144
	local d2 = d1 + 528 * k
	add(d1, d2, 1680 * k, 320 * k, 560 * k, "deck")
	local c2 = d2 + 336 * k
	add(d2 - 16, c2, 640 * k, 0, 400 * k, "collar")
	add(c2 - 16, c2 + 3600 * k, 240 * k, 0, 0, "stalk")
	return parts, top - 176 - mast
end


-- A cloud city as a station layout: its decks and spire as parts, the
-- tunnel through the middle as a dock open at both ends (the clamp in the
-- middle, nothing solid in the way), windows as lights, and a beacon on
-- the mast. k: size (1 or 2). Game:spawnCloudCity asks for "city_<k>".
function Stations.cityId(k) return ("city_%d"):format(k) end

local function round2(v) return floor(v + 0.5) end

function Stations.city(k)
	local raw, tip = cityParts(k)
	local T, H = CITY_TUNNEL, CITY_HALF
	local parts = {}
	-- the tunnel's dark inside, behind everything
	table.insert(parts, { name = "tunnel", shape = { -H, -T, H, -T, H, T, -H, T }, shade = 0.35, layer = "detail", collide = false })
	for i, p in ipairs(raw) do
		-- an unchamfered corner repeats a point; drop the repeats so the
		-- outline triangulates
		local shape = {}
		local v = p.verts
		for j = 1, #v, 2 do
			local x, y = round2(v[j]), round2(v[j + 1])
			local n = #shape
			if n == 0 or shape[n - 1] ~= x or shape[n] ~= y then
				table.insert(shape, x); table.insert(shape, y)
			end
		end
		while #shape > 6 and shape[1] == shape[#shape - 1] and shape[2] == shape[#shape] do
			table.remove(shape); table.remove(shape)
		end
		local part = { name = p.role .. " " .. i, shape = shape }
		-- windows: rows across each part at a fixed spacing, pairs down the stalk
		local lights = {}
		if p.role == "stalk" then
			for yy = p.y1 + 160, p.y2 - 120, 240 do
				table.insert(lights, { x = round2(-p.w * 0.6), y = round2(yy), kind = "window", size = 16 })
				table.insert(lights, { x = round2(p.w * 0.6), y = round2(yy), kind = "window", size = 16 })
			end
		elseif p.role ~= "mast" and p.role ~= "floor" then
			local row = 0
			for yy = p.y1 + 112, p.y2 - 96, 288 do
				local hw = p.w - max(p.ct, p.cb) - 80
				local j = 0
				for xx = -hw, hw, 112 do
					if (j + row * 3) % 7 ~= 3 then table.insert(lights, { x = round2(xx), y = round2(yy), kind = "window", size = 16 }) end
					j = j + 1
				end
				row = row + 1
			end
		end
		if #lights > 0 then part.lights = lights end
		table.insert(parts, part)
		-- darker bands: down the stalk, across the deck
		if p.role == "stalk" then
			table.insert(parts, { name = "stalk band", layer = "detail", collide = false, shade = 0.75, shape = {
				round2(-p.w * 0.3), round2(p.y1 + 16), round2(p.w * 0.3), round2(p.y1 + 16), round2(p.w * 0.3), round2(p.y2 - 16), round2(-p.w * 0.3), round2(p.y2 - 16) } })
		elseif p.role == "deck" then
			local w2 = p.w - p.ct * 0.5
			local yc = (p.y1 + p.y2) / 2
			table.insert(parts, { name = "deck band", layer = "detail", collide = false, shade = 0.75, shape = {
				round2(-w2), round2(yc - 40), round2(w2), round2(yc - 40), round2(w2), round2(yc + 40), round2(-w2), round2(yc + 40) } })
		end
	end
	-- the clamp: the dock, a tunnel open at both ends, nothing solid
	table.insert(parts, { name = "clamp", dock = true, dockBoth = true, dockRunway = H - 40 + 600, collide = false,
		layer = "detail", shade = 0.5, shape = { -40, -T, 40, -T, 40, T, -40, T } })
	-- the beacon on the mast
	table.insert(parts, { name = "beacon", layer = "detail", collide = false, shape = { -8, round2(tip) - 8, 8, round2(tip) - 8, 8, round2(tip) + 8, -8, round2(tip) + 8 },
		lights = { { x = 0, y = round2(tip), kind = "nav", color = { 1, 0.35, 0.3 }, size = 24 } } })
	return { id = Stations.cityId(k), name = ("Cloud city (size %d)"):format(k), parts = parts, color = { 0.55, 0.63, 0.74 },
		haze = -T - 60 }
end

return Stations
