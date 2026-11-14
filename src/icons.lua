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

-- Just the art, in art units around the current origin. col is the
-- primary paint (default: the item's kind colour). Parts draw in list
-- order like a weapon's art: hull parts outlined, detail drawn without an
-- outline (in its own colour, unlike weapon art, which darkens it), glow
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

-- Baked icons ---------------------------------------------------------------
-- Every icon is rendered once into a sprite at a fixed resolution (RES px
-- per art unit), so all items share one line weight and one look however
-- big they are drawn. The bake adds, in order:
--   glow      a soft halo in the item's kind colour behind the art
--   lighting  a gentle top-left to bottom-right gradient over the fill
--   bevel     a bright rim on edges facing the light, a dark one opposite
-- Tune them here; Icons.clearCache() rebakes.
Icons.RES = 4            -- sprite px per art unit (64 px per hold cell)
Icons.LINE = 1.5         -- outline width, sprite px
Icons.GLOW = { radius = 7, strength = 0.55 }
Icons.LIGHT = { gradient = 0.22, rim = 0.45, shadow = 0.35, width = 2 }
local PAD = 12           -- sprite px of room around the art for the glow

local cache = setmetatable({}, { __mode = "k" })   -- icon -> sprite
local scratch = {}                                 -- w.."x"..h -> { a, b }
function Icons.clearCache() cache = setmetatable({}, { __mode = "k" }) end

local blurShader, shadeShader
local function shaders()
	if blurShader then return end
	blurShader = lg.newShader([[
		extern vec2 dir;      // one texel step along the blur
		extern float radius;
		vec4 effect(vec4 col, Image tex, vec2 uv, vec2 sc) {
			float a = 0.0, wsum = 0.0;
			for (int i = -16; i <= 16; i++) {
				float x = float(i);
				if (abs(x) > radius) continue;
				float w = exp(-x * x / (radius * radius * 0.5));
				a += Texel(tex, uv + dir * x).a * w;
				wsum += w;
			}
			return vec4(col.rgb, col.a * a / wsum);
		}
	]])
	shadeShader = lg.newShader([[
		extern vec2 texel;    // one sprite px in uv
		extern vec2 light;    // toward the light, in px
		extern float gradient, rim, shadow;
		vec4 effect(vec4 col, Image tex, vec2 uv, vec2 sc) {
			vec4 c = Texel(tex, uv);
			if (c.a <= 0.0) return c;
			// overall light falloff across the sprite
			float g = 1.0 + gradient * (0.5 - dot(uv - 0.5, normalize(vec2(1.0, 1.0))));
			// edges: inside here, outside a step toward / away from the light
			float toward = Texel(tex, uv + light * texel).a;
			float away = Texel(tex, uv - light * texel).a;
			float lit = max(0.0, c.a - toward);
			float dark = max(0.0, c.a - away);
			vec3 rgb = c.rgb * g;
			rgb = mix(rgb, vec3(1.0), lit * rim);
			rgb = rgb * (1.0 - dark * shadow);
			return vec4(rgb, c.a) * col;
		}
	]])
end

local function scratchPair(w, h)
	local key = w .. "x" .. h
	local s = scratch[key]
	if not s then
		s = { lg.newCanvas(w, h), lg.newCanvas(w, h) }
		scratch[key] = s
	end
	return s[1], s[2]
end

-- Render an icon to a sprite canvas (centre = art 0,0). fresh: don't
-- reuse a cached one (the editor, whose parts change under it).
function Icons.bake(icon, fresh, col)
	local sprite = not fresh and cache[icon]
	if sprite then return sprite end
	shaders()
	local bw, bh = Icons.box(icon.item)
	-- art that spills out of its box still gets room
	local r = Icons.reach(icon)
	if fresh then
		r = 4
		for _, p in ipairs(icon.parts or {}) do
			for k = 1, #(p.shape or {}) - 1, 2 do r = math.max(r, math.abs(p.shape[k]), math.abs(p.shape[k + 1])) end
		end
	end
	local hw, hh = math.max(bw, math.min(r, bw * 1.5)), math.max(bh, math.min(r, bh * 1.5))
	local W = math.ceil(hw * 2 * Icons.RES) + PAD * 2
	local H = math.ceil(hh * 2 * Icons.RES) + PAD * 2
	local c = col or kindColor(data.items[icon.item] or {})
	local art, tmp = scratchPair(W, H)
	local out = (not fresh and lg.newCanvas(W, H)) or Icons.editorCanvas(W, H)
	lg.push("all")
	lg.origin()
	-- 1. the art, flat
	lg.setCanvas(art); lg.clear(0, 0, 0, 0)
	lg.push(); lg.translate(W / 2, H / 2); lg.scale(Icons.RES)
	Icons.drawArt(icon, c, 1, Icons.LINE / Icons.RES, fresh)
	lg.pop()
	-- 2. glow: blur the silhouette both ways, tinted with the kind colour
	lg.setShader(blurShader)
	blurShader:send("radius", Icons.GLOW.radius)
	lg.setCanvas(tmp); lg.clear(0, 0, 0, 0)
	blurShader:send("dir", { 1 / W, 0 })
	lg.setColor(1, 1, 1, 1)
	lg.draw(art)
	lg.setCanvas(out); lg.clear(0, 0, 0, 0)
	blurShader:send("dir", { 0, 1 / H })
	lg.setColor(c[1], c[2], c[3], Icons.GLOW.strength)
	lg.draw(tmp)
	-- 3. the art on top, lit
	lg.setShader(shadeShader)
	local L = Icons.LIGHT
	shadeShader:send("texel", { 1 / W, 1 / H })
	shadeShader:send("light", { -L.width, -L.width })
	shadeShader:send("gradient", L.gradient)
	shadeShader:send("rim", L.rim)
	shadeShader:send("shadow", L.shadow)
	lg.setColor(1, 1, 1, 1)
	lg.setBlendMode("alpha", "premultiplied")
	lg.draw(art)
	lg.pop()
	sprite = { canvas = out, w = W, h = H }
	if not fresh then cache[icon] = sprite end
	return sprite
end

-- One reusable output canvas per size for the editor's live preview.
local editorOut = {}
function Icons.editorCanvas(w, h)
	local key = w .. "x" .. h
	editorOut[key] = editorOut[key] or lg.newCanvas(w, h)
	return editorOut[key]
end

-- Draw a baked sprite centred on the current origin, at art scale `s`
-- (screen px per art unit).
local function drawSprite(sprite, s, alpha)
	alpha = alpha or 1
	lg.setColor(alpha, alpha, alpha, alpha)   -- premultiplied: fade rgb too
	lg.setBlendMode("alpha", "premultiplied")
	local k = s / Icons.RES
	lg.draw(sprite.canvas, 0, 0, 0, k, k, sprite.w / 2, sprite.h / 2)
	lg.setBlendMode("alpha")
end

-- An icon, baked and drawn at art scale s around the current origin.
function Icons.drawBaked(icon, s, alpha, fresh, col)
	drawSprite(Icons.bake(icon, fresh, col), s, alpha)
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
	Icons.drawBaked(icon, s, alpha)
	lg.pop()
	return true
end

-- Draw an item floating in space at x, y turned to angle (world space).
-- Returns false if it has no icon.
function Icons.drawWorld(itemId, x, y, angle, alpha)
	local icon = Icons.get(itemId)
	if not icon then return false end
	lg.push()
	lg.translate(x, y)
	lg.rotate(angle or 0)
	Icons.drawBaked(icon, Icons.WORLD, alpha)
	lg.pop()
	return true
end

-- World px from an item's centre to the edge of its art (or nil).
function Icons.worldReach(itemId)
	local icon = Icons.get(itemId)
	return icon and Icons.reach(icon) * Icons.WORLD
end

return Icons
