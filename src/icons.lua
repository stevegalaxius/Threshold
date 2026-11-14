--[[
	Item art: one vector drawing per item, used both as its icon in the
	hold (and anywhere else items are listed) and as the thing you see
	floating in space when it's dropped.

	An icon is drawn in the Shipyard's Icons tab (F2) and lives in a data
	file of its own:

	  icon { id = "icon_shell_s", item = "shell_s", parts = { ... } }

	parts are like a weapon's art parts (src/weapon_visual.lua): shape,
	color, paint, shade, tint, mirror, layer. paint = "primary" wears the
	item's kind colour (the hold's ammo / salvage tint), "secondary" a
	darker shade of it; anything else is metal unless it has a color.

	Coordinates: the art sits on the item's hold footprint, w x h cells
	(src/inventory/shapes.lua), centred on 0,0 with the long side (w)
	along x. One cell is Icons.CELL units, so a 3 x 1 gun barrel's box runs
	from x = -24 to 24 and y = -8 to 8. The art doesn't have to fill the box:
	the outline is the item's real silhouette.

	In space the same art is drawn at its physical size, Icons.WORLD world
	pixels per unit. In the hold it is scaled to fill the stack's cells and
	turned with the stack when it's rotated. Items without an icon keep
	their old look (a tinted box in the hold, a spinning square in space).
]]

local data = require("src.data")
local Visual = require("src.weapon_visual")

local Icons = {}

Icons.CELL = 16      -- art units per hold cell (1 m)
Icons.WORLD = 1      -- world px per art unit when floating in space

local lg = love.graphics

-- Art made from a hull: its parts in their factory paint, scaled to fit
-- the item's footprint (drones are drawn as the drone itself).
local derived = {}
function Icons.fromHull(item, hullId)
	local hull = data.hulls[hullId]
	if not hull or not hull.parts then return nil end
	local Paint, HullShape = require("src.paint"), require("src.hullshape")
	local paint = Paint.preset(Paint.pool(hull)[1])
	local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(hull.parts) do
		for k = 1, #p.shape - 1, 2 do
			x0, x1 = math.min(x0, p.shape[k]), math.max(x1, p.shape[k])
			y0, y1 = math.min(y0, p.shape[k + 1]), math.max(y1, p.shape[k + 1])
		end
	end
	if x1 <= x0 or y1 <= y0 then return nil end
	local bw, bh = Icons.box(item)
	local sc = math.min((bw - 1) * 2 / (x1 - x0), (bh - 1) * 2 / (y1 - y0))
	local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
	local icon = { id = "icon_" .. item, item = item, hull = hullId, parts = {} }
	-- twins (mirror copies) are already in hull.parts, so nothing mirrors again
	for _, p in ipairs(hull.parts) do
		local shape = {}
		for k = 1, #p.shape - 1, 2 do
			shape[k], shape[k + 1] = (p.shape[k] - cx) * sc, (p.shape[k + 1] - cy) * sc
		end
		icon.parts[#icon.parts + 1] = { name = p.name, shape = shape, color = HullShape.color(p, paint), layer = p.layer }
	end
	return icon
end

-- The hull an item stands for (a drone's), or nil.
local function hullOf(def)
	return def and def.kind == "ammo" and def.family == "drone" and def.shot and def.shot.hull
end

-- The icon drawn for an item id, or nil: its own drawn art first, else
-- (for a drone) the drone's hull.
function Icons.get(item)
	local own = data.icons and data.icons[item]
	if own then return own end
	local h = hullOf(data.items[item])
	if not h then return nil end
	local d = derived[item]
	if d == nil or d.hull ~= h then
		d = Icons.fromHull(item, h) or false
		derived[item] = d
	end
	return d or nil
end
Icons.hullOf = function(item) return hullOf(data.items[item]) end

-- The footprint (w, h cells) an item's art is drawn on.
function Icons.footprint(item)
	local def = type(item) == "table" and item or data.items[item]
	if not def then return 1, 1 end
	local ok, w, h = pcall(require("src.inventory.shapes").of, def.id)
	if ok and w then return w, h end
	return def.w or 1, def.h or 1
end

-- The art box in art units: half width, half height.
function Icons.box(item)
	local w, h = Icons.footprint(item)
	return w * Icons.CELL / 2, h * Icons.CELL / 2
end

-- How far the art reaches from its centre (art units), for hover rings
-- and pick radii.
function Icons.reach(icon)
	if icon.reach then return icon.reach end
	local r = 0
	for _, p in ipairs(icon.parts or {}) do
		for k = 1, #(p.shape or {}) - 1, 2 do
			r = math.max(r, math.sqrt(p.shape[k] ^ 2 + p.shape[k + 1] ^ 2))
		end
	end
	icon.reach = math.max(r, 4)
	return icon.reach
end

local function kindColor(itemDef)
	local HUD = require("src.hud")
	return HUD.itemColor(itemDef) or { 0.75, 0.78, 0.82 }
end

-- Just the art, in art units around the current origin, in the game's
-- own look: like a hull, a part is a dark fill (its colour x 0.22) inside a
-- bright contour in its colour, with a faint additive bloom along the
-- contour. lineWidth is the contour width in art units (callers pass a
-- fixed number of screen px divided by their scale, so every item's
-- contours match the ships'). Layers:
--   hull    dark fill + bright contour (default)
--   detail  contour only, no fill (bands, seams, panel lines)
--   glow    filled bright and additive (lights, fuses, hot bits)
-- col is the primary paint (default: the item's kind colour).
local triCache = setmetatable({}, { __mode = "k" })
local function triangles(shape, fresh)
	local t = triCache[shape]
	if fresh then t = nil end
	if t == nil then
		local ok, tris = pcall(love.math.triangulate, shape)
		t = ok and tris or false
		if not fresh then triCache[shape] = t end
	end
	return t
end
local function mirrored(shape)
	local m = {}
	for k = #shape - 1, 1, -2 do m[#m + 1] = shape[k]; m[#m + 1] = -shape[k + 1] end
	return m
end

Icons.FILL = 0.22        -- fill brightness, as hulls (src/render.lua)
Icons.BLOOM = 0.16       -- alpha of the faint bloom along contours (0 = off)

-- fresh: the parts may have changed since last frame (the editor).
function Icons.drawArt(icon, col, alpha, lineWidth, fresh)
	alpha = alpha or 1
	lineWidth = lineWidth or 1
	local c = col or kindColor(data.items[icon.item] or {})
	local paint = { c[1], c[2], c[3] }
	local contours = {}
	lg.setLineJoin("bevel")
	for _, p in ipairs(icon.parts or {}) do
		if p.shape and #p.shape >= 6 then
			local layer = p.layer or "hull"
			local pc = Visual.partColor(p, paint)
			for _, s in ipairs({ p.shape, p.mirror and mirrored(p.shape) or nil }) do
				local tris = triangles(s, fresh)
				if layer == "glow" then
					lg.setBlendMode("add")
					lg.setColor(pc[1], pc[2], pc[3], alpha)
					if tris then for _, tri in ipairs(tris) do lg.polygon("fill", tri) end end
					lg.setBlendMode("alpha")
				else
					if layer == "hull" and tris then
						local f = Icons.FILL
						lg.setColor(pc[1] * f, pc[2] * f, pc[3] * f, alpha)
						for _, tri in ipairs(tris) do lg.polygon("fill", tri) end
					end
					lg.setColor(pc[1], pc[2], pc[3], alpha)
					lg.setLineWidth(lineWidth)
					lg.polygon("line", s)
					contours[#contours + 1] = { s, pc }
				end
			end
		end
	end
	-- the faint bloom: the contours again, wider and additive
	if Icons.BLOOM > 0 then
		lg.setBlendMode("add")
		lg.setLineWidth(lineWidth * 3)
		for _, k in ipairs(contours) do
			local pc = k[2]
			lg.setColor(pc[1], pc[2], pc[3], Icons.BLOOM * alpha)
			lg.polygon("line", k[1])
		end
		lg.setBlendMode("alpha")
	end
	lg.setLineJoin("miter")
end

-- Draw an item's icon filling the rect x, y, w, h (screen px), turned a
-- quarter if rot. Returns false if the item has no icon.
function Icons.drawInRect(itemId, x, y, w, h, rot, alpha, pad)
	local icon = Icons.get(itemId)
	if not icon then return false end
	local bw, bh = Icons.box(itemId)
	pad = pad or 3
	local aw, ah = w - pad * 2, h - pad * 2
	if rot then aw, ah = ah, aw end
	local s = math.min(aw / (bw * 2), ah / (bh * 2))
	if s <= 0 then return true end
	lg.push()
	lg.translate(x + w / 2, y + h / 2)
	if rot then lg.rotate(math.pi / 2) end
	lg.scale(s)
	Icons.drawArt(icon, nil, alpha, 1.5 / s)
	lg.pop()
	return true
end

-- Draw an item floating in space at x, y turned to angle (world space).
-- Returns false if it has no icon.
function Icons.drawWorld(itemId, x, y, angle, alpha, lineWidth)
	local icon = Icons.get(itemId)
	if not icon then return false end
	lg.push()
	lg.translate(x, y)
	lg.rotate(angle or 0)
	lg.scale(Icons.WORLD)
	Icons.drawArt(icon, nil, alpha, (lineWidth or 1) / Icons.WORLD)
	lg.pop()
	return true
end

-- World px from an item's centre to the edge of its art (or nil).
function Icons.worldReach(itemId)
	local icon = Icons.get(itemId)
	return icon and Icons.reach(icon) * Icons.WORLD
end

return Icons
