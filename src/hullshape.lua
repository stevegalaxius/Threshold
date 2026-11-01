--[[
	Hull outlines made of parts. A hull in data/hulls.lua gives either one
	`shape` (x,y pairs, nose to +x) or a list of `parts`, each its own
	polygon that can overlap the others:

	  parts = {
	    { shape = { ... } },                          -- hull colour
	    { shape = { ... }, shade = 0.6 },             -- darker
	    { shape = { ... }, tint = { 0.3, -0.1, -0.2 } },  -- shifted toward red
	  }

	shade multiplies the ship's colour, tint is added to it (after shade).
	The wreck stays whole, but the parts besides the biggest can be shot
	off, each taking its share of the loot (Game:breakablePieces).

	Optional tags on a part (the F2 editor, src/editor/, sets them all):
	  name       label, for the editor and for reading the data file
	  color      { r, g, b }: a fixed colour that ignores the ship's paint
	             (shade and tint still apply to it)
	  mirror     true: also add a copy reflected across the ship's axis
	             (y -> -y), which breaks off on its own. Asymmetric bits
	             just leave it off.
	  layer      "hull" (default), "detail" (drawn without an outline) or
	             "glow" (no outline, drawn additively)
	  collide    false: drawn only, no physics shape on the wreck, never
	             takes hits and never breaks off (antennae, fins, glow)
	  cargo      true: carries loot. If no part says cargo, every part does.
	  core       true: this part is the wreck's core instead of the biggest
	  breakable  false: never shoots off; stays with the core
	  armor      multiplier on the part's share of the wreck's toughness
	  mass       multiplier on the part's share of the wreck's weight when it
	             breaks away (heavy engine blocks, light fins)
	  explode    true: bursts into pickups when shot off instead of drifting
	             away as a small wreck
	  lights     lights placed on the part, in ship space, that go with it
	             when it breaks off and go dark on a wreck:
	               { x, y, kind = "window" | "nav" | "strobe",
	                 color = { r, g, b }, size = px, rate = flashes/s,
	                 phase = 0..1 }
	             windows stutter when the ship is hit and go out one by one
	             as it's damaged; nav lights are steady, red to port and
	             green to starboard; strobes double-flash white
	  role       free tag for later systems: engine, cockpit, weapon, dock,
	             light, antenna, rack, ...

	HullShape.prepare fills in, for every part: tris (for filling a concave
	outline), cx/cy (its centre), area and reach (furthest point from the
	centre). hull.shape becomes every point of every part, which is all the
	code that only wants the hull's extent needs.
]]

local HullShape = {}

local abs, max, min, sqrt = math.abs, math.max, math.min, math.sqrt

local function area(t)
	return abs((t[3] - t[1]) * (t[6] - t[2]) - (t[5] - t[1]) * (t[4] - t[2])) / 2
end

-- Check one outline. Returns the outline (without a repeated closing
-- point) and its triangles, or nil and what's wrong with it.
function HullShape.check(s)
	if type(s) ~= "table" or #s < 6 or #s % 2 ~= 0 then
		return nil, "needs a shape of at least 3 x,y pairs"
	end
	-- an outline that repeats its first point to close itself is fine
	if #s >= 8 and s[#s - 1] == s[1] and s[#s] == s[2] then
		local trimmed = {}
		for k = 1, #s - 2 do trimmed[k] = s[k] end
		s = trimmed
	end
	local ok, tris = pcall(love.math.triangulate, s)
	if not ok then return nil, "its outline crosses itself" end
	return s, tris
end

-- The mirror image of a part across the ship's axis, as its own part.
local function reflect(part)
	local twin = {}
	for k, v in pairs(part) do twin[k] = v end
	local s, out = part.shape, {}
	-- reversed, so the outline keeps its winding
	for k = #s - 1, 1, -2 do
		table.insert(out, s[k]); table.insert(out, -s[k + 1])
	end
	twin.shape, twin.mirror, twin.twin = out, nil, true
	if part.lights then
		twin.lights = {}
		for _, l in ipairs(part.lights) do
			local m = {}
			for k, v in pairs(l) do m[k] = v end
			m.y = -(l.y or 0)
			table.insert(twin.lights, m)
		end
	end
	return twin
end

function HullShape.prepare(def)
	def.parts = def.parts or { { shape = def.shape } }
	-- mirrored parts get their twin right after them
	local expanded = {}
	for _, part in ipairs(def.parts) do
		table.insert(expanded, part)
		if part.mirror and type(part.shape) == "table" then table.insert(expanded, reflect(part)) end
	end
	def.parts = expanded
	local all = {}
	for i, part in ipairs(def.parts) do
		local s, tris = HullShape.check(part.shape)
		if not s then error(("hull '%s' part %d %s"):format(def.id, i, tris), 0) end
		part.shape, part.tris = s, tris
		local A, cx, cy = 0, 0, 0
		for _, t in ipairs(tris) do
			local a = area(t)
			A = A + a
			cx = cx + (t[1] + t[3] + t[5]) / 3 * a
			cy = cy + (t[2] + t[4] + t[6]) / 3 * a
		end
		part.area = max(A, 1)
		part.cx, part.cy = cx / part.area, cy / part.area
		local reach = 0
		for k = 1, #s, 2 do
			reach = max(reach, sqrt((s[k] - part.cx) ^ 2 + (s[k + 1] - part.cy) ^ 2))
			table.insert(all, s[k]); table.insert(all, s[k + 1])
		end
		part.reach = reach
	end
	def.shape = all
end

-- A part's colour on a ship painted `col`.
function HullShape.color(part, col)
	col = part.color or col
	local s, t = part.shade or 1, part.tint
	local r, g, b = col[1] * s, col[2] * s, col[3] * s
	if t then r, g, b = r + t[1], g + t[2], b + t[3] end
	return { max(0, min(1, r)), max(0, min(1, g)), max(0, min(1, b)) }
end

-- Draw parts (all of the hull's, or just `only`: one part or a list of
-- them), offset by -ox,-oy.
-- fill(partColour) and line(partColour) return the colour to use, or nil
-- to skip that pass; lineWidth is for the outline.
function HullShape.draw(hull, col, fill, line, lineWidth, only, ox, oy)
	local lg = love.graphics
	local list = only and (only.shape and { only } or only) or hull.parts
	if ox then lg.push(); lg.translate(-ox, -oy) end
	-- part by part, so a later part sits on top of the ones before it
	if lineWidth then lg.setLineWidth(lineWidth) end
	for _, part in ipairs(list) do
		local pc = HullShape.color(part, col)
		local f = fill and fill(pc)
		if f then
			lg.setColor(f)
			if part.layer == "glow" then lg.setBlendMode("add") end
			for _, t in ipairs(part.tris) do lg.polygon("fill", t) end
			if part.layer == "glow" then lg.setBlendMode("alpha") end
		end
		local l = (part.layer == nil or part.layer == "hull") and line and line(pc)
		if l then
			lg.setColor(l)
			lg.polygon("line", part.shape)
		end
	end
	if ox then lg.pop() end
end

-- Is x,y inside a part's outline?
function HullShape.contains(part, x, y)
	local s = part.shape
	local hit, n = false, #s
	local jx, jy = s[n - 1], s[n]
	for k = 1, n, 2 do
		local ix, iy = s[k], s[k + 1]
		if (iy > y) ~= (jy > y) and x < (jx - ix) * (y - iy) / (jy - iy) + ix then hit = not hit end
		jx, jy = ix, iy
	end
	return hit
end

HullShape.WINDOW = { 1, 0.86, 0.55 }
HullShape.PORT = { 1, 0.15, 0.12 }       -- nav lights: red to port (y < 0)
HullShape.STARBOARD = { 0.15, 1, 0.3 }   -- green to starboard (y > 0)
HullShape.STROBE = { 1, 1, 1 }

-- A steady 0..1 number per light, from where it sits.
local function hash(l)
	local v = math.sin(l.x * 12.9898 + l.y * 78.233) * 43758.5453
	return v - math.floor(v)
end

-- A light's default colour: windows warm (some cooler), nav lights by
-- side (white on the spine), strobes white.
function HullShape.lightColor(l)
	if l.color then return l.color end
	if l.kind == "nav" then
		if l.y < -0.5 then return HullShape.PORT elseif l.y > 0.5 then return HullShape.STARBOARD end
		return HullShape.STROBE
	elseif l.kind == "strobe" then
		return HullShape.STROBE
	end
	local h = hash(l)
	if h > 0.8 then return { 0.75, 0.9, 1 } end      -- the odd cabin in cold light
	return HullShape.WINDOW
end

-- How bright a light is at `time` (0 = off), for a ship in state
-- { damage = 0..1, flash = >0 just after a hit }.
--   window  steady; they stutter when the ship's hit and go out one by
--           one as it's damaged
--   nav     steady running light
--   strobe  a sharp double flash, rate times a second
function HullShape.brightness(l, time, state)
	time = time or 0
	local damage = state and state.damage or 0
	local flash = state and state.flash or 0
	local h = hash(l)
	if l.kind == "strobe" then
		local t = (time * (l.rate or 1) + (l.phase or h)) % 1
		return (t < 0.04 or (t > 0.1 and t < 0.14)) and 1 or 0
	end
	if l.kind == "nav" then
		if flash > 0 and math.sin(time * 70 + h * 40) > 0.3 then return 0.2 end
		return 1
	end
	-- windows
	if h < damage * 1.1 then return 0 end               -- this deck's lost power
	if flash > 0 and math.sin(time * 55 + h * 90) > 0 then return 0 end
	return 1
end

-- Draw the lights on parts (all of the hull's, or `only`), offset like
-- HullShape.draw. minSize keeps them visible when zoomed far out.
function HullShape.drawLights(hull, time, minSize, only, ox, oy, state)
	local lg = love.graphics
	local list = only and (only.shape and { only } or only) or hull.parts
	if ox then lg.push(); lg.translate(-ox, -oy) end
	for _, part in ipairs(list) do
		for _, l in ipairs(part.lights or {}) do
			local b = HullShape.brightness(l, time, state)
			if b > 0 then
				local c = HullShape.lightColor(l)
				local r = max(l.size or 1.2, minSize or 0)
				if l.kind == "nav" or l.kind == "strobe" then
					-- a pinpoint with a small soft halo
					lg.setBlendMode("add")
					lg.setColor(c[1], c[2], c[3], (l.kind == "strobe" and 0.45 or 0.22) * b)
					lg.circle("fill", l.x, l.y, r * (l.kind == "strobe" and 3 or 2))
					lg.setBlendMode("alpha")
					lg.setColor(c[1] * 0.4 + 0.6, c[2] * 0.4 + 0.6, c[3] * 0.4 + 0.6, b)
					lg.circle("fill", l.x, l.y, r * 0.7)
				else
					lg.setColor(c[1], c[2], c[3], 0.9 * b)
					lg.rectangle("fill", l.x - r * 0.6, l.y - r * 0.6, r * 1.2, r * 1.2)
				end
			end
		end
	end
	if ox then lg.pop() end
end

return HullShape
