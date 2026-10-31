--[[
	The Hangar tab of the station screen: the station's hangar bay as a
	grid, like a hold. Every ship takes a footprint the size of its hull
	(Game.hangarFootprint: a Wisp 4 x 2, an Anvil 8 x 3, a Bastion 14 x 5),
	including the one you're docked in, so a bay only fits so many.

	  click         select a ship (its details and buttons show on the right)
	  drag          move it to another spot; R rotates while dragging
	  double-click  fly a parked ship (the one you're in stays parked)
	  Fly           the same, for the selected ship
	  Cargo         the Cargo tab, with that ship's hold where station
	                storage usually is

	Bays are per station and last between levels (src/world.lua). This
	only draws and reports clicks; the cargo screen (src/ui/cargo.lua)
	owns the tabs and acts on Fly and Cargo.
]]

local HullShape = require("src.hullshape")
local data = require("src.data")
local stats = require("src.stats")
local Hold = require("src.inventory.hold")
local HUD = require("src.hud")
local T = require("src.tuning")

local Hangar = { sel = nil, hand = nil }

local lg = love.graphics
local floor, max, min = math.floor, math.max, math.min

local GAP, PAD, HEAD, IW = 16, 14, 46, 270

local function inRect(r, x, y)
	return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

local function footprint(game, hullId, rot)
	return game.hangarFootprint(hullId, rot)
end

-- Where everything is on screen.
local function layout(game)
	local p = game.player
	local st = p and p.dockState and p.dockState.station
	if not st then return nil end
	local sw, sh = lg.getDimensions()
	local W, H = T.hangarW, T.hangarH
	local cs = min(30, floor((sw - 32 - IW - GAP - PAD * 2) / W), floor((sh - 220) / H))
	local bw, bh = W * cs + PAD * 2, HEAD + H * cs + PAD
	local tw = bw + GAP + IW
	local x, y = floor((sw - tw) / 2), max(80, floor((sh - bh - 40) / 2))
	local L = { x = x, y = y, w = tw, h = bh, cs = cs, station = st, list = game:hangar(st) }
	L.bay = { x = x, y = y, w = bw, h = bh }
	L.gx, L.gy = x + PAD, y + HEAD
	L.info = { x = x + bw + GAP, y = y, w = IW, h = bh }
	L.ships = {}
	local function add(owner, hullId, bay, i)
		if not bay then return end
		local w, h = footprint(game, hullId, bay.rot)
		table.insert(L.ships, { owner = owner, hull = hullId, bay = bay, i = i,
			x = L.gx + bay.x * cs, y = L.gy + bay.y * cs, w = w * cs, h = h * cs })
	end
	for i, rec in ipairs(L.list) do add(rec, rec.hull, rec.bay, i) end
	add(p, p.hull.id, p.bay)
	local ix, iw = L.info.x + PAD, IW - PAD * 2
	L.fly = { x = ix, y = L.info.y + L.info.h - 44, w = floor(iw / 2) - 4, h = 30 }
	L.cargo = { x = ix + floor(iw / 2) + 4, y = L.fly.y, w = floor(iw / 2) - 4, h = 30 }
	return L
end

local function shipAt(L, mx, my)
	for _, s in ipairs(L.ships) do
		if inRect(s, mx, my) then return s end
	end
end

-- The selected ship, if it's still here: the player's ship by default.
local function selected(game, L)
	local sel = Hangar.sel
	for _, s in ipairs(L.ships) do if s.owner == sel then return s end end
	Hangar.sel = game.player
	return nil
end

-- Name and lines of numbers for a ship record (or the live ship).
local function describe(rec, live)
	local hull = data.hulls[rec.hull]
	local s = stats.compute(hull, rec.loadout or hull.loadout)
	local armor = live and live.armor or rec.armor or s.armor
	local used, total = 0, s.hold
	if rec.hold then used, total = Hold.cells(rec.hold) end
	local fitted = 0
	for i in ipairs(hull.slots) do
		if (rec.loadout or hull.loadout)[i] then fitted = fitted + 1 end
	end
	return hull, {
		("%s, %s"):format(hull.maker, hull.class),
		("Armor %d / %d"):format(armor, s.armor),
		("Hold %d / %d m3"):format(used, total),
		("%d of %d slots fitted"):format(fitted, #hull.slots),
	}
end

-- A hull's outline inside a w x h box, nose to the right (or down, rotated).
local function drawHull(hull, x, y, w, h, rot, col, alpha)
	local nx, tx, wy = 0, 0, 0
	for i = 1, #hull.shape, 2 do
		nx, tx = max(nx, hull.shape[i]), min(tx, hull.shape[i])
		wy = max(wy, math.abs(hull.shape[i + 1]))
	end
	local len, wid = nx - tx, wy * 2
	local bw, bh = w, h
	if rot then bw, bh = h, w end
	local sc = min(bw / len, bh / wid) * 0.86
	lg.push()
	lg.translate(x + w / 2, y + h / 2)
	if rot then lg.rotate(math.pi / 2) end
	lg.scale(sc)
	lg.translate(-(nx + tx) / 2, 0)
	HullShape.draw(hull, col, function(c) return { c[1], c[2], c[3], 0.18 * alpha } end,
		function(c) return { c[1], c[2], c[3], 0.9 * alpha } end, 1.5 / sc)
	lg.pop()
	lg.setLineWidth(1)
end

local function button(r, label, hot, col, enabled)
	col = col or HUD.AQUA
	local a = enabled == false and 0.06 or (hot and 0.4 or 0.18)
	lg.setColor(col[1], col[2], col[3], a)
	lg.rectangle("fill", r.x, r.y, r.w, r.h, 5, 5)
	lg.setColor(enabled == false and HUD.DIM or HUD.INK)
	lg.printf(label, r.x, r.y + 8, r.w, "center")
end

-- Where the ship in hand would land.
local function dropSpot(game, L, mx, my)
	local h = Hangar.hand
	local cx, cy = floor((mx - L.gx) / L.cs), floor((my - L.gy) / L.cs)
	local bay = { x = cx - h.dx, y = cy - h.dy, rot = h.rot }
	return bay, game:hangarFree(L.station, h.owner, h.hull, bay)
end

function Hangar.draw(game, mx, my)
	local L = layout(game)
	if not L then return end
	local p, cs = game.player, L.cs
	local sel = selected(game, L)

	-- the bay
	local B = L.bay
	HUD.panel(B.x, B.y, B.w, B.h)
	lg.setFont(HUD.font(16))
	lg.setColor(HUD.INK)
	lg.print("Hangar \194\183 " .. L.station.name, B.x + PAD, B.y + 12)
	local used = 0
	for _, s in ipairs(L.ships) do used = used + (s.w / cs) * (s.h / cs) end
	lg.setFont(HUD.font(12))
	lg.setColor(HUD.DIM)
	lg.printf(("%d ships    %d / %d cells"):format(#L.ships, used, T.hangarW * T.hangarH), B.x, B.y + 16, B.w - PAD, "right")
	lg.setColor(0, 0, 0, 0.35)
	lg.rectangle("fill", L.gx, L.gy, T.hangarW * cs, T.hangarH * cs)
	lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.1)
	for cy = 0, T.hangarH - 1 do
		for cx = 0, T.hangarW - 1 do lg.rectangle("line", L.gx + cx * cs + 0.5, L.gy + cy * cs + 0.5, cs - 1, cs - 1) end
	end

	local h = Hangar.hand
	for _, s in ipairs(L.ships) do
		local flying = s.owner == p
		local col = flying and { 0.4, 1, 0.55 } or p.color
		local alpha = (h and h.owner == s.owner) and 0.35 or 1
		lg.setColor(col[1], col[2], col[3], 0.1 * alpha)
		lg.rectangle("fill", s.x + 2, s.y + 2, s.w - 4, s.h - 4, 4, 4)
		local hot = not h and inRect(s, mx, my)
		lg.setColor(col[1], col[2], col[3], ((sel == s) and 0.95 or (hot and 0.6 or 0.3)) * alpha)
		lg.setLineWidth(sel == s and 2 or 1)
		lg.rectangle("line", s.x + 2.5, s.y + 2.5, s.w - 5, s.h - 5, 4, 4)
		lg.setLineWidth(1)
		drawHull(data.hulls[s.hull], s.x + 4, s.y + 4, s.w - 8, s.h - 8, s.bay.rot, col, alpha)
		if cs >= 18 then
			lg.setFont(HUD.font(10))
			lg.setColor(HUD.INK[1], HUD.INK[2], HUD.INK[3], alpha)
			lg.print((flying and "FLYING  " or "") .. data.hulls[s.hull].name, s.x + 6, s.y + 4)
		end
	end
	if h then
		local bay, ok = dropSpot(game, L, mx, my)
		local w, ht = footprint(game, h.hull, h.rot)
		lg.setColor(ok and 0.3 or 1, ok and 1 or 0.35, ok and 0.5 or 0.3, 0.25)
		for cy = bay.y, bay.y + ht - 1 do
			for cx = bay.x, bay.x + w - 1 do
				if cx >= 0 and cy >= 0 and cx < T.hangarW and cy < T.hangarH then
					lg.rectangle("fill", L.gx + cx * cs + 1, L.gy + cy * cs + 1, cs - 2, cs - 2)
				end
			end
		end
		drawHull(data.hulls[h.hull], mx - (h.dx + 0.5) * cs, my - (h.dy + 0.5) * cs, w * cs, ht * cs, h.rot,
			h.owner == p and { 0.4, 1, 0.55 } or p.color, 0.8)
	end

	-- the selected ship
	local I = L.info
	HUD.panel(I.x, I.y, I.w, I.h)
	local owner = sel and sel.owner or p
	local flying = owner == p
	local rec = flying and { hull = p.hull.id, loadout = p.loadout, hold = p.hold } or owner
	local hull, lines = describe(rec, flying and p or nil)
	lg.setFont(HUD.font(10))
	lg.setColor(HUD.DIM)
	lg.print(flying and "FLYING" or "PARKED", I.x + PAD, I.y + 14)
	lg.setFont(HUD.font(18))
	lg.setColor(HUD.INK)
	lg.print(hull.name, I.x + PAD, I.y + 26)
	drawHull(hull, I.x + PAD, I.y + 56, I.w - PAD * 2, 70, false, flying and { 0.4, 1, 0.55 } or p.color, 1)
	lg.setFont(HUD.font(12))
	for k, l in ipairs(lines) do
		lg.setColor(k == 1 and HUD.DIM or HUD.INK)
		lg.print(l, I.x + PAD, I.y + 136 + (k - 1) * 18)
	end
	lg.setColor(HUD.DIM)
	if flying and not p.bay then
		lg.printf("On the landing pad: the bay is full.", I.x + PAD, L.fly.y - 44, I.w - PAD * 2)
	elseif flying then
		lg.printf("The ship you're in. Pick a parked ship to fly or open its hold.", I.x + PAD, L.fly.y - 44, I.w - PAD * 2)
	end
	lg.setFont(HUD.font(13))
	button(L.fly, "Fly", not h and inRect(L.fly, mx, my), { 0.3, 1, 0.5 }, not flying)
	button(L.cargo, "Cargo", not h and inRect(L.cargo, mx, my), nil, not flying)
end

-- What a click asks for: { fly = i }, { cargo = rec } or nil. Pressing on
-- a ship selects it and picks it up to move.
function Hangar.mousepressed(game, mx, my, button)
	local L = layout(game)
	if not L or button ~= 1 then return nil end
	local sel = selected(game, L)
	local parked = sel and sel.owner ~= game.player and sel.i
	if inRect(L.fly, mx, my) then return parked and { fly = sel.i } or nil end
	if inRect(L.cargo, mx, my) then return parked and { cargo = sel.owner } or nil end
	local s = shipAt(L, mx, my)
	if not s then return nil end
	local now = love.timer.getTime()
	local c = Hangar.lastClick
	local double = c and c.owner == s.owner and now - c.t < 0.35
	Hangar.lastClick = { owner = s.owner, t = now }
	Hangar.sel = s.owner
	if double and s.i then return { fly = s.i } end
	Hangar.hand = { owner = s.owner, hull = s.hull, rot = s.bay.rot,
		dx = floor((mx - s.x) / L.cs), dy = floor((my - s.y) / L.cs) }
	return nil
end

function Hangar.mousereleased(game, mx, my)
	local h = Hangar.hand
	if not h then return end
	local L = layout(game)
	local bay, ok
	if L then bay, ok = dropSpot(game, L, mx, my) end
	Hangar.hand = nil
	if not ok then return end
	if h.owner == game.player then game.player.bay = bay else h.owner.bay = bay end
end

function Hangar.keypressed(game, key)
	local h = Hangar.hand
	if key == "r" and h then
		h.rot = not h.rot
		local w, ht = footprint(game, h.hull, h.rot)
		h.dx, h.dy = min(h.dy, w - 1), min(h.dx, ht - 1)
		return true
	end
	return false
end

-- Drop whatever's in hand (the screen closed or the tab changed).
function Hangar.cancel()
	Hangar.hand = nil
end

Hangar.layout = layout     -- for the autotest

return Hangar
