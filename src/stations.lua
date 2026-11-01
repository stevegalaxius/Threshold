--[[
	Station layouts as parts, the same format as hulls (src/hullshape.lua),
	so the Shipyard (F2) can open, redraw and export them.

	A station definition (data.stations, from station { } in data files or
	made here) is:
	  parts  polygons as for hulls; one or more parts say dock = true. Each
	         box is a docking module: its door faces out from the station centre.
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

-- Surface elevators ------------------------------------------------------
-- Fixed terminals use normal station parts/docks. Mars has exposed gantries
-- and repeated containers; Mercury uses a separate enclosed, tapered design.
-- Only the common geometric primitives are shared between the manufacturers.
local function elevatorLayout(id, name, surface, terminal, angles, industrial)
	local parts, tracks = {}, {}
	local function part(label, points, shade, angle, detail, tint)
		local shape = {}
		local c, s = cos(angle), sin(angle)
		for i = 1, #points, 2 do
			shape[#shape + 1] = round(points[i] * c - points[i + 1] * s)
			shape[#shape + 1] = round(points[i] * s + points[i + 1] * c)
		end
		local p = { name = label, shape = shape, shade = shade, tint = tint }
		if detail then p.layer, p.collide = "detail", false end
		parts[#parts + 1] = p
		return p
	end
	local function box(label, x1, y1, x2, y2, shade, angle, detail, tint)
		return part(label, { x1, y1, x2, y1, x2, y2, x1, y2 }, shade, angle, detail, tint)
	end
	for n, angle in ipairs(angles) do
		local prefix = "elevator " .. n .. " "
		local bottom, top = surface - 80, terminal - 480
		if industrial then
			-- Two heavy rails with visible cross bracing and open space between.
			for _, side in ipairs({ -1, 1 }) do
				box(prefix .. "rail", bottom, side * 145 - 36, top, side * 145 + 36, 0.65, angle)
			end
			for x = bottom, top - 200, 300 do
				box(prefix .. "cross member", x, -180, x + 42, 180, 0.8, angle)
				part(prefix .. "diagonal", { x, -145, x + 30, -145, x + 280, 145, x + 250, 145 }, 0.75, angle)
			end
			box(prefix .. "surface footing", surface - 140, -320, surface + 150, 320, 0.9, angle)
			-- Broad framed terminal, with container banks flanking the hangar.
			box(prefix .. "terminal back", terminal - 480, -740, terminal - 260, 740, 0.7, angle)
			for _, side in ipairs({ -1, 1 }) do
				local y1, y2 = side == 1 and 245 or -740, side == 1 and 740 or -245
				box(prefix .. "hangar deck", terminal - 320, y1, terminal + 560, y2, 0.95, angle)
				for k = 0, 3 do
					box(prefix .. "container " .. k, terminal - 250 + k * 195,
						y1 + 65, terminal - 90 + k * 195, y2 - 65, 0.8 + (k % 2) * 0.15,
						angle, true, { 0.025, -0.005, -0.02 })
				end
				box(prefix .. "outer frame", terminal - 420, side * 750 - 35, terminal + 620, side * 750 + 35, 0.65, angle)
			end
		else
			-- Mercury: enclosed blade, inset service channel, swept shoulders.
			part(prefix .. "spine", { bottom, -190, top, -95, top, 95, bottom, 190 }, 0.95, angle)
			box(prefix .. "recess", bottom + 140, -48, top, 48, 0.6, angle, true)
			part(prefix .. "surface plinth", { surface - 160, -400, surface + 100, -250,
				surface + 100, 250, surface - 160, 400 }, 1.05, angle)
			for _, side in ipairs({ -1, 1 }) do
				local points = { terminal - 520, side * 240, terminal + 500, side * 240,
					terminal + 420, side * 460, terminal - 100, side * 720, terminal - 680, side * 370 }
				part(prefix .. "swept terminal", points, 1.05, angle)
				box(prefix .. "inset band", terminal - 180, side * 460 - 32,
					terminal + 300, side * 460 + 32, 0.78, angle, true, { -0.01, 0.01, 0.025 })
			end
			box(prefix .. "terminal back", terminal - 550, -260, terminal - 310, 260, 0.8, angle)
			-- An offset pair of spars leaves the outward dock approach open.
			for _, side in ipairs({ -1, 1 }) do
				box(prefix .. "counterweight spar", terminal + 150, side * 650 - 30,
					terminal + 2100, side * 650 + 30, 0.75, angle)
				part(prefix .. "counterweight", { terminal + 1900, side * 440,
					terminal + 2550, side * 570, terminal + 2550, side * 770,
					terminal + 1900, side * 900 }, 0.9, angle)
			end
		end
		-- The dock is a recessed floor between solid shoulders; its door
		-- faces away from the planet. No docking arms are required.
		local dock = box(prefix .. "tractor dock", terminal - 300, -225, terminal + 500, 225, 0.45, angle, true)
		dock.dock, dock.dockRunway = true, 1100
		dock.lights = {}
		for _, side in ipairs({ -1, 1 }) do
			local x, y = terminal + 490, side * 215
			dock.lights[#dock.lights + 1] = { x = round(x * cos(angle) - y * sin(angle)),
				y = round(x * sin(angle) + y * cos(angle)), kind = "nav", size = 12 }
		end
		tracks[#tracks + 1] = { angle = angle, lower = surface + 160, upper = top, industrial = industrial }
	end
	return { id = id, name = name, parts = parts, color = { 0.55, 0.63, 0.74 }, elevatorTracks = tracks }
end

function Stations.heavenLadder(surface, ringRadius)
	return elevatorLayout("heaven_ladder", "Heaven-Ladder", surface, ringRadius + 1150, { 0, pi }, true)
end

function Stations.mercuryElevator(surface)
	return elevatorLayout("mercury_elevator", "Mercury Elevator", surface, surface + 3100, { -pi / 2 }, false)
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
