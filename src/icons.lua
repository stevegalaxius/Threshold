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

	In space the size comes from the grid: Icons.WORLD world px per art
	unit, so every hold cell is the same size afloat and a 5 x 1 item is
	five times as long as a 1 x 1. An icon file can set the item's
	footprint (w, h): the editor's size boxes write it there. In the hold it is scaled to fill the stack's cells and
	turned with the stack when it's rotated. Items without an icon keep
	their old look (a tinted box in the hold, a spinning square in space).
]]

local data = require("src.data")
local Visual = require("src.weapon_visual")

local Icons = {}

Icons.CELL = 16      -- art units per hold cell (1 m)
Icons.WORLD = 0.5  -- world px per art unit in space: 6 px per hold cell (readable, still small beside a 72 px Wisp)

local lg = love.graphics

--[[ Boxes: 3D blocks drawn in a 3/4 oblique view (width straight across,
	depth receding up and to the right, height up), the way crates are
	drawn. An icon may list boxes = { { x, y, z, w, d, h, ... } } in cells
	(x along the width, y depth, z height, from the near bottom left
	corner). Each box becomes three parts (front, side, top) ahead of the
	icon's drawn parts, in list order (later boxes draw on top), and the lot is scaled to fill
	the footprint. A box is the item's kind colour (the hold background's)
	unless it sets shade (below 1: darker), light (0..1: towards white) or
	color { r, g, b }. Optional per box: name, layer ("detail" or "glow",
	as for parts), and
	open = true (no top face, for an open carton), hide = { front = true,
	side = true, top = true } to leave faces out. ]]
Icons.DEPTH = 0.315    -- screen x and -y per unit of depth
Icons.RISE = 0.55      -- screen -y per unit of height
Icons.FACE = { front = 0.24, side = 0.16, top = 0.34 }   -- fill brightness per face

local function project(x, y, z)
	return x + y * Icons.DEPTH, -(z * Icons.RISE + y * Icons.DEPTH)
end

function Icons.boxParts(boxes, bw, bh, kc, view)
	if require("src.icon_model").enabled(boxes) then return require("src.icon_model").parts(boxes,bw,bh,kc,view) end
	local list = boxes or {}
	local faces = {}
	local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
	for bi, b in ipairs(list) do
		local bx, by, bz = b.x or 0, b.y or 0, b.z or 0
		local X, Y, Z = bx + (b.w or 1), by + (b.d or 1), bz + (b.h or 1)
		local function face(kind, pts)
			if b.hide and b.hide[kind] then return end
			local shape = {}
			for _, q in ipairs(pts) do
				local sx, sy = project(q[1], q[2], q[3])
				shape[#shape + 1], shape[#shape + 2] = sx, sy
				x0, x1, y0, y1 = math.min(x0, sx), math.max(x1, sx), math.min(y0, sy), math.max(y1, sy)
			end
			local color = b.color
			if not color and b.light and kc then
				-- lighter towards white, keeping the hue (a shade above 1 clips and shifts it)
				local t = b.light
				color = { kc[1] + (1 - kc[1]) * t, kc[2] + (1 - kc[2]) * t, kc[3] + (1 - kc[3]) * t }
			end
			faces[#faces + 1] = { name = (b.name or "box") .. " " .. kind, shape = shape, color = color, paint = b.paint or (not b.color and "primary" or nil), shade = b.shade, tint = b.tint,
				fill = Icons.FACE[kind], layer = b.layer, fromBox = true, box = bi, face = kind }
		end
		face("front", { { bx, by, bz }, { X, by, bz }, { X, by, Z }, { bx, by, Z } })
		face("side", { { X, by, bz }, { X, Y, bz }, { X, Y, Z }, { X, by, Z } })
		if not b.open then face("top", { { bx, by, Z }, { X, by, Z }, { X, Y, Z }, { bx, Y, Z } }) end
	end
	if #faces == 0 then return faces, view end
	-- view: a fixed { k, cx, cy } (art units per cell and the centre), so
	-- adding or removing a box doesn't rescale the rest; else fill the
	-- footprint, centred, keeping proportions
	if not view then
		local pad = 0.5
		view = { math.min((bw - pad) * 2 / math.max(x1 - x0, 1e-6), (bh - pad) * 2 / math.max(y1 - y0, 1e-6)), (x0 + x1) / 2, (y0 + y1) / 2 }
	end
	local k, cx, cy = view[1], view[2], view[3]
	for _, f in ipairs(faces) do
		for j = 1, #f.shape - 1, 2 do
			f.shape[j], f.shape[j + 1] = (f.shape[j] - cx) * k, (f.shape[j + 1] - cy) * k
		end
	end
	return faces, view
end

-- Replace an icon's box faces (parts marked fromBox) with fresh ones built
-- from its boxes. own: the icon or editor design (w, h win over the item's).
function Icons.syncBoxes(icon)
 if not data.items[icon.item] then return icon end -- module items are created after icon files
 local signature=require('src.save').encode({boxes=icon.boxes,view=icon.boxView,paint=icon.paint,w=icon.w,h=icon.h,item=icon.item})
 if icon._boxSignature==signature then return icon end
	local kept = {}
	for _, p in ipairs(icon.parts or {}) do if not p.fromBox then kept[#kept + 1] = p end end
	local bw, bh = Icons.box(icon.item, icon)
	local def = data.items[icon.item]
	local kc = Icons.paint(icon)
	local parts, view = Icons.boxParts(icon.boxes, bw, bh, kc, icon.boxView)
	if icon.boxes and #icon.boxes > 0 then
		icon.boxView = view and { math.floor(view[1] * 1000 + 0.5) / 1000, math.floor(view[2] * 1000 + 0.5) / 1000, math.floor(view[3] * 1000 + 0.5) / 1000 }
	end
	-- drawn parts go over the boxes, in list order, except those marked
	-- under = true, which go beneath them
	local under = {}
	for _, p in ipairs(kept) do if p.under then under[#under + 1] = p end end
	for i = #under, 1, -1 do table.insert(parts, 1, under[i]) end
	for _, p in ipairs(kept) do if not p.under then parts[#parts + 1] = p end end
	icon.parts = parts
	icon.reach = nil
 icon._boxSignature=require("src.save").encode({boxes=icon.boxes,view=icon.boxView,paint=icon.paint,w=icon.w,h=icon.h,item=icon.item})
	return icon
end

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
	if own then
  if own.boxes and not own._runtimeSynced then Icons.syncBoxes(own);own._runtimeSynced=true end
  return own
 end
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

-- The footprint (w, h cells) an item's art is drawn on. own: a design or
-- icon whose w, h (set in the editor) win over the item's.
function Icons.footprint(item, own)
	if own and own.w and own.h then return own.w, own.h end
	local def = type(item) == "table" and item or data.items[item]
	if not def then return 1, 1 end
	local ok, w, h = pcall(require("src.inventory.shapes").of, def.id)
	if ok and w then return w, h end
	return def.w or 1, def.h or 1
end

-- The art box in art units: half width, half height.
function Icons.box(item, own)
	local w, h = Icons.footprint(item, own)
	return w * Icons.CELL / 2, h * Icons.CELL / 2
end

-- How far the art reaches from its centre (art units), for hover rings
-- and pick radii.
function Icons.reach(icon)
	if icon.reach then return icon.reach end
	local r = 0
	for _, p in ipairs(icon.parts or {}) do
		if p.badge then goto continue end   -- hold only: not part of the shape afloat
		for k = 1, #(p.shape or {}) - 1, 2 do
			r = math.max(r, math.sqrt(p.shape[k] ^ 2 + p.shape[k + 1] ^ 2))
		end
		::continue::
	end
	icon.reach = math.max(r, 4)
	return icon.reach
end

-- An icon's primary paint, like a ship's: paint = a preset name from
-- src/paint.lua ("Khaki", "Gunmetal", ...) or { r, g, b }; bare metal if
-- unset. Not the hold's kind colour, so items don't all look alike.
function Icons.paint(icon)
	local Paint = require("src.paint")
	local p = icon and icon.paint
	if type(p) == "string" then
		local pr = Paint.find(p)
		if pr then return pr.color end
	elseif type(p) == "table" then
		return p
	end
	return Paint.METAL
end

-- Just the art, in art units around the current origin, in the game's
-- own look: like a hull, a part is a dark fill (its colour x 0.22) inside a
-- bright contour in its colour. lineWidth is the contour width in art units (callers pass a
-- fixed number of screen px divided by their scale, so every item's
-- contours match the ships'). Layers:
--   hull    dark fill + bright contour (default)
--   detail  flat darker fill, no contour (bands, seams, panel lines)
--   glow    filled bright and additive (lights, fuses, hot bits)
--   glass   see-through: a dark tint over what's behind (dimmed to a
--           quarter) inside an outline in its colour
-- col is the primary paint (default: the item's kind colour).
-- A part with badge = true is a hold-only marker (what's in a generic
-- crate): drawn in the hold and the editor, left out when space is true.
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

-- fresh: the parts may have changed since last frame (the editor).
function Icons.drawArt(icon, col, alpha, lineWidth, fresh, space)
	alpha = alpha or 1
	lineWidth = lineWidth or 1
	local c = col or Icons.paint(icon)
	local paint = { c[1], c[2], c[3] }
	lg.setLineJoin("bevel")
	local modelDrawn=false
 for _, p in ipairs(icon.parts or {}) do
  if p.modelFace then
   if not modelDrawn then require('src.icon_model').draw(icon.parts,alpha);modelDrawn=true end
  elseif p.shape and #p.shape >= 6 and not (space and p.badge) then
			local layer = p.layer or "hull"
			local pc = Visual.partColor(p, paint)
			for _, s in ipairs({ p.shape, p.mirror and mirrored(p.shape) or nil }) do
				local tris = triangles(s, fresh)
				if layer == "glass" then
					if tris then
						-- mostly opaque and darker than its edge: what's behind shows
						-- through dimmed, never brighter than the glass's own outline
						lg.setColor(pc[1] * 0.45, pc[2] * 0.45, pc[3] * 0.45, alpha * 0.75)
						for _, tri in ipairs(tris) do lg.polygon("fill", tri) end
					end
					lg.setColor(pc[1], pc[2], pc[3], alpha)
					lg.setLineWidth(lineWidth)
					lg.polygon("line", s)
				elseif layer == "glow" then
					lg.setBlendMode("add")
					lg.setColor(pc[1], pc[2], pc[3], alpha)
					if tris then for _, tri in ipairs(tris) do lg.polygon("fill", tri) end end
					lg.setBlendMode("alpha")
				elseif layer == "detail" then
					-- a flat, darker fill with no contour, as on hulls and weapons
					if tris then
						lg.setColor(pc[1] * 0.5, pc[2] * 0.5, pc[3] * 0.5, alpha)
						for _, tri in ipairs(tris) do lg.polygon("fill", tri) end
					end
				else
					if layer == "hull" and tris then
						local f = p.fill or Icons.FILL
						lg.setColor(pc[1] * f, pc[2] * f, pc[3] * f, alpha)
						for _, tri in ipairs(tris) do lg.polygon("fill", tri) end
					end
					lg.setColor(pc[1], pc[2], pc[3], alpha)
					lg.setLineWidth(lineWidth)
					lg.polygon("line", s)
				end
			end
		end
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
	Icons.drawArt(icon, nil, alpha, 0.5 / s)
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
	local k = Icons.worldScale(itemId)
	lg.scale(k)
	Icons.drawArt(icon, nil, alpha, (lineWidth or 1) / k, nil, true)
	lg.pop()
	return true
end

-- World px per art unit for an item floating in space: the same for
-- every item, so its size afloat is its hold footprint and nothing else.
function Icons.worldScale(itemId)
	return Icons.WORLD
end

-- World px from an item's centre to the edge of its art (or nil).
function Icons.worldReach(itemId)
	local icon = Icons.get(itemId)
	return icon and Icons.reach(icon) * Icons.worldScale(itemId)
end

return Icons
