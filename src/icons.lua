-- Parametric item icons, shared by inventory and dropped-item rendering.
-- Authored files store editable solids in boxes; parts are generated picking
-- faces only. The editor and inventory use the same depth-tested renderer.
local data = require("src.data")

local Icons = {}

Icons.CELL = 16      -- art units per hold cell (1 m)
Icons.WORLD = 0.5  -- world px per art unit in space: 6 px per hold cell (readable, still small beside a 72 px Wisp)

local lg = love.graphics

function Icons.boxParts(boxes,bw,bh,paint,view)
 return require('src.icon_model').parts(boxes,bw,bh,paint,view)
end

-- Projected faces are derived picking data, never editable polygon art.
function Icons.syncBoxes(icon)
 if not data.items[icon.item] then return icon end
 local signature=require('src.save').encode({boxes=icon.boxes,view=icon.boxView,paint=icon.paint,w=icon.w,h=icon.h,item=icon.item})
 if icon._boxSignature==signature then return icon end
 local bw,bh=Icons.box(icon.item,icon)
 icon.parts,icon.boxView=Icons.boxParts(icon.boxes,bw,bh,Icons.paint(icon),icon.boxView)
 icon.reach=nil
 icon._boxSignature=require('src.save').encode({boxes=icon.boxes,view=icon.boxView,paint=icon.paint,w=icon.w,h=icon.h,item=icon.item})
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
	local icon = { id = "icon_" .. item, item = item, hull = hullId, hullScale=sc,hullX=cx,hullY=cy, parts = {} }
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

-- Authored icons have one rendering path: the depth-tested parametric model.
-- Drone items without authored icons use the existing ship renderer.
function Icons.drawArt(icon,col,alpha,lineWidth)
 if icon.hull then
  local c=col or Icons.paint(icon)
  lg.push();lg.scale(icon.hullScale or 1);lg.translate(-(icon.hullX or 0),-(icon.hullY or 0))
  require('src.hullshape').draw(require('src.data').hulls[icon.hull],c,function(p)return {p[1]*.22,p[2]*.22,p[3]*.22}end,function(p)return p end,(lineWidth or 1)/(icon.hullScale or 1))
  lg.pop()
 else require('src.icon_model').draw(icon.parts or {},alpha or 1) end
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
