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

-- The icon drawn for an item id, or nil.
function Icons.get(item)
	return data.icons and data.icons[item]
end

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

-- Just the art, in art units around the current origin. col is the
-- primary paint (default: the item's kind colour). Parts draw in list
-- order like a weapon's art: hull parts outlined, detail darker, glow
-- additive.
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

-- fresh: the parts may have changed since last frame (the editor).
function Icons.drawArt(icon, col, alpha, lineWidth, fresh)
	alpha = alpha or 1
	local c = col or kindColor(data.items[icon.item] or {})
	local paint = { c[1], c[2], c[3] }
	for _, p in ipairs(icon.parts or {}) do
		if p.shape and #p.shape >= 6 then
			local layer = p.layer or "hull"
			local pc = Visual.partColor(p, paint)
			if layer == "detail" then pc = { pc[1] * 0.5, pc[2] * 0.5, pc[3] * 0.5 } end
			if layer == "glow" then lg.setBlendMode("add") end
			for _, s in ipairs({ p.shape, p.mirror and mirrored(p.shape) or nil }) do
				local tris = triangles(s, fresh)
				lg.setColor(pc[1], pc[2], pc[3], alpha)
				if tris then for _, tri in ipairs(tris) do lg.polygon("fill", tri) end end
				if layer == "hull" then
					lg.setColor(pc[1] * 0.3, pc[2] * 0.3, pc[3] * 0.3, alpha)
					lg.setLineWidth(lineWidth or 1)
					lg.polygon("line", s)
				end
			end
			if layer == "glow" then lg.setBlendMode("alpha") end
		end
	end
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
	Icons.drawArt(icon, nil, alpha, 1 / s)
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
