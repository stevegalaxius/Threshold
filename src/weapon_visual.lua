-- Shared ship weapon artwork for flight and the Shipyard preview.
--
-- A weapon module can carry its own art (drawn in the Shipyard's Weapons
-- tab): module.art = { parts = { { shape = {...}, barrel = true?, paint?,
-- shade?, color? }, ... }, muzzles = { { x, y }, ... } }, in mount space
-- (origin on the slot, +x along the line of fire). Barrel parts kick back
-- when the gun fires. Weapons without art get plain barrels.
local lg = love.graphics
local TURRET = { S = 4, M = 6, L = 9 }
local METAL = { 0.75, 0.78, 0.82 }
local KICK = 3          -- px a barrel recoils
local V = {}

local triCache = setmetatable({}, { __mode = "k" })
local function triangles(shape)
	local t = triCache[shape]
	if t == nil then
		local ok, tris = pcall(love.math.triangulate, shape)
		t = ok and tris or false
		triCache[shape] = t
	end
	return t
end

-- How far the barrels are pushed back: full just after a shot, eased out
-- over the first part of the cooldown.
function V.kick(w)
	local rate = w.w and w.w.fireRate
	if not rate or not w.cooldown or w.cooldown <= 0 then return 0 end
	local since = 1 / rate - w.cooldown
	local k = 1 - since / math.min(0.15, 0.6 / rate)
	return k > 0 and k * KICK or 0
end

function V.partColor(p, col)
	local c = p.color or (p.paint == "primary" and col) or (p.paint == "secondary" and { col[1] * 0.6, col[2] * 0.6, col[3] * 0.6 }) or METAL
	local s, t = p.shade or 1, p.tint or { 0, 0, 0 }
	return { math.min(1, c[1] * s + t[1]), math.min(1, c[2] * s + t[2]), math.min(1, c[3] * s + t[3]) }
end

-- Just the art, in mount space (no slot transform): the Shipyard draws it
-- like this on its canvas too.
function V.drawArt(art, col, dark, lineWidth, kick)
	for _, layer in ipairs({ false, true }) do
		for _, p in ipairs(art.parts or {}) do
			if (p.barrel == true) == layer and p.shape and #p.shape >= 6 then
				local list = { p.shape }
				if p.mirror then
					local m = {}
					for k = #p.shape - 1, 1, -2 do m[#m + 1] = p.shape[k]; m[#m + 1] = -p.shape[k + 1] end
					list[2] = m
				end
				lg.push()
				if layer and kick and kick > 0 then lg.translate(-kick, 0) end
				for _, s in ipairs(list) do
					local tris = triangles(s)
					lg.setColor(V.partColor(p, col))
					if tris then for _, tri in ipairs(tris) do lg.polygon("fill", tri) end end
					lg.setColor(dark)
					lg.setLineWidth(lineWidth or 1)
					lg.polygon("line", s)
				end
				lg.pop()
			end
		end
	end
end

function V.draw(w, col, dark, lineWidth)
		local s = w.slot
		local art = w.module.art
		local len = ({ S = 7, M = 10, L = 16 })[w.module.size] or 8
		local thick = (w.module.size == "L") and 5 or ((w.module.size == "M") and 4 or 3)
		if w.mount == "turret" then len, thick = len * 1.5, thick + 1 end
		lg.push()
		lg.translate(s.x or 0, s.y or 0)
		lg.rotate(w.aim or 0)
		-- the turret ring is part of the mount; art sits on top of it
		local function ring()
			local r = TURRET[w.module.size] or 5
			lg.setColor(dark)
			lg.circle("fill", 0, 0, r)
			lg.setColor(col)
			lg.setLineWidth(lineWidth or 1.5)
			lg.circle("line", 0, 0, r)
		end
		if art and art.parts and #art.parts > 0 then
			if w.mount == "turret" then ring() end
			V.drawArt(art, col, dark, (lineWidth or 1.5) * 0.6, V.kick(w))
			lg.pop()
			return
		end
		lg.setColor(METAL)
		if w.w.kind == "laser" then lg.setColor(0.6, 0.95, 1) end
		if w.bay then
			lg.rectangle("fill", -4, -4, 8, 8)
		else
			local n, gap = w.w.barrels or 1, w.w.barrelGap or 8
			for b = 1, n do
				local off = (b - (n + 1) / 2) * gap
				lg.rectangle("fill", 0, off - thick / 2, len, thick)
			end
		end
		if w.mount == "turret" then ring() end
		lg.pop()
end

-- Where shot k leaves the mount, in mount space: one of the art's muzzle
-- points (taking turns), or nil to fall back on barrels / barrelGap.
function V.muzzle(module, slot)
	local m = module.art and module.art.muzzles
	if not m or #m == 0 then return nil end
	slot.muzzleN = (slot.muzzleN or 0) % #m + 1
	local p = m[slot.muzzleN]
	return p[1] or p.x or 0, p[2] or p.y or 0
end
return V
