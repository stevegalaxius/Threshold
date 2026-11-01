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

return HullShape
