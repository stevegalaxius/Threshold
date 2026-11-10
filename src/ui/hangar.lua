--[[
	The Hangar tab of the station screen. Two panels:

	  Berths     the station's interior bay as a grid, like a hold, with the
	             exterior moorings in a column beside it, behind the airlock
	             stripe. Every ship takes a footprint the size of its hull
	             (Game.hangarFootprint), including the one you're docked in.
	             Moorings are listed with their size limits and what's in
	             them; the mouse wheel scrolls them when there are many.
	  Ship card  the selected ship: name, hull with numbered slots, armor
	             and hold, its fit, where it's parked, and every action.

	  click         select a ship
	  drag          move it to another cell or onto a free berth; R rotates
	  double-click  fly a parked ship (the one you're in stays parked)
	  Fly / Open hold / Move / Sell   the same for the selected ship; Sell
	                asks for a second click

	Bays are per station and last between levels (src/world.lua). This only
	draws and reports clicks; the cargo screen (src/ui/cargo.lua) owns the
	tabs and acts on what mousepressed returns.
]]

local HullShape = require("src.hullshape")
local data = require("src.data")
local stats = require("src.stats")
local Hold = require("src.inventory.hold")
local HUD = require("src.hud")
local Station = require("src.ui.station")
local Sheet = require("src.ui.shipsheet")

local Hangar = { sel = nil, hand = nil, scroll = 0, confirmSell = nil }

local lg = love.graphics
local floor, max, min = math.floor, math.max, math.min

local GAP, PAD, HEAD = 16, 14, 64
local CARD_W, MOOR_W, AIRLOCK, ROW_H = 300, 210, 12, 46

local function inRect(r, x, y)
	return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
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
	local W, H = game.hangarSize(st)
	local fx, y, fw, ph = require("src.ui.station").body()
	-- cells: as big as fits beside the moorings and the card, 8..30 px
	local room = fw - CARD_W - GAP - PAD * 2 - AIRLOCK - GAP - MOOR_W
	local cs = max(8, min(30, floor(room / W), floor((ph - HEAD - PAD) / H)))
	local bw = PAD * 2 + W * cs + AIRLOCK + GAP + MOOR_W
	-- the card takes whatever width the bay leaves
	local tw, x = fw, fx
	local L = { x = x, y = y, w = tw, h = ph, cs = cs, station = st, list = game:hangar(st), gridW = W, gridH = H }
	L.bay = { x = x, y = y, w = bw, h = ph }
	L.gx, L.gy = x + PAD, y + HEAD
	L.airlock = { x = L.gx + W * cs, y = L.gy, w = AIRLOCK, h = H * cs }
	L.moor = { x = L.airlock.x + AIRLOCK + GAP, y = L.gy, w = MOOR_W, h = ph - HEAD - PAD }
	L.info = { x = x + bw + GAP, y = y, w = tw - bw - GAP, h = ph }
	L.ships, L.berths = {}, {}

	local slots = game:stationMoorings(st)
	local visible = max(1, floor((L.moor.h + 6) / (ROW_H + 6)))
	Hangar.scroll = max(0, min(Hangar.scroll, max(0, #slots - visible)))
	L.visibleRows, L.totalRows = visible, #slots
	for i, slot in ipairs(slots) do
		L.berths[i] = { x = L.moor.x, y = L.moor.y + (i - 1 - Hangar.scroll) * (ROW_H + 6), w = MOOR_W, h = ROW_H,
			index = i, slot = slot, visible = i > Hangar.scroll and i <= Hangar.scroll + visible }
	end

	local function add(owner, hullId, bay, i)
		local mooring = owner == p and owner.parkingMooring or owner.mooring
		if mooring and L.berths[mooring] then
			local row = L.berths[mooring]
			local ship = { owner = owner, hull = hullId, i = i, exterior = true, x = row.x, y = row.y, w = row.w, h = row.h }
			row.ship = ship
			if row.visible then table.insert(L.ships, ship) end
			return
		end
		if not bay then return end
		local w, h = footprint(game, hullId, bay.rot)
		table.insert(L.ships, { owner = owner, hull = hullId, bay = bay, i = i,
			x = L.gx + bay.x * cs, y = L.gy + bay.y * cs, w = w * cs, h = h * cs })
	end
	for i, rec in ipairs(L.list) do add(rec, rec.hull, rec.bay, i) end
	add(p, p.hull.id, p.bay)
	-- Visiting NPC ships docked inside occupy cells too; show them so the
	-- space they block isn't a mystery. They can't be selected or moved.
	L.visitors = {}
	for _, s in pairs(game:hangarGrid(st).stacks) do
		local o = s.owner
		if o ~= p and o.kind == "ship" and o.hull then
			table.insert(L.visitors, { hull = o.hull.id, rot = o.bay and o.bay.rot,
				x = L.gx + s.x * cs, y = L.gy + s.y * cs, w = s.w * cs, h = s.h * cs })
		end
	end

	-- the card's buttons, bottom up
	local I = L.info
	local bx, bw2 = I.x + PAD, I.w - PAD * 2
	local half = floor((bw2 - 8) / 2)
	L.sell = { x = bx, y = I.y + I.h - PAD - 30, w = bw2, h = 30 }
	L.cargo = { x = bx, y = L.sell.y - 38, w = half, h = 30 }
	L.move = { x = bx + half + 8, y = L.cargo.y, w = bw2 - half - 8, h = 30 }
	L.fly = { x = bx, y = L.cargo.y - 38, w = bw2, h = 30 }
	return L
end

local function shipAt(L, mx, my)
	for _, s in ipairs(L.ships) do
		if inRect(s, mx, my) then return s end
	end
end

-- The selected ship's entry, if it's on screen; the player's ship by default.
local function selected(game, L)
	local sel = Hangar.sel
	if sel ~= game.player then
		local here = false
		for _, rec in ipairs(L.list) do if rec == sel then here = true end end
		if not here then Hangar.sel = game.player end
	end
	for _, s in ipairs(L.ships) do if s.owner == Hangar.sel then return s end end
	return nil
end

local function listIndex(L, owner)
	for i, rec in ipairs(L.list) do if rec == owner then return i end end
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
Hangar.drawHull = drawHull

-- Where the ship in hand would land.
local function dropSpot(game, L, mx, my)
	local h = Hangar.hand
	local cx, cy = floor((mx - L.gx) / L.cs), floor((my - L.gy) / L.cs)
	local bay = { x = cx - h.dx, y = cy - h.dy, rot = h.rot }
	return bay, game:hangarFree(L.station, h.owner, h.hull, bay)
end

local ACTIVE = { 0.4, 1, 0.55 }

local function shipColor(game, owner)
	if owner == game.player then return ACTIVE end
	return owner.color or game.player.color
end

-- Ship name on its tile; small tiles get a smaller font, never nothing.
local function tileName(s, label, alpha)
	local size = (s.h >= 28 and s.w >= 60) and 13 or 12
	if s.h < 12 then return end
	local f = HUD.font(size)
	lg.setFont(f)
	local text = label
	while #text > 1 and f:getWidth(text) > s.w - 10 do text = text:sub(1, -2) end
	lg.setColor(0, 0, 0, 0.55 * alpha)
	lg.rectangle("fill", s.x + 3, s.y + 3, f:getWidth(text) + 6, size + 4, 2, 2)
	lg.setColor(HUD.INK[1], HUD.INK[2], HUD.INK[3], alpha)
	lg.print(text, s.x + 6, s.y + 4)
end

local function drawBerths(game, L, mx, my, sel)
	local p, cs, h = game.player, L.cs, Hangar.hand
	local B = L.bay
	Station.panel(B.x, B.y, B.w, B.h)
	lg.setFont(HUD.font(18))
	lg.setColor(HUD.INK)
	lg.print("Hangar \194\183 " .. L.station.name, B.x + PAD, B.y + 12)

	local used, inside, freeMoor = 0, 0, 0
	for _, s in ipairs(L.ships) do
		if not s.exterior then used = used + (s.w / cs) * (s.h / cs); inside = inside + 1 end
	end
	for _, row in ipairs(L.berths) do
		if not row.ship and not game:mooringTaken(L.station, row.index) then freeMoor = freeMoor + 1 end
	end
	lg.setFont(HUD.font(14))
	lg.setColor(HUD.DIM)
	lg.printf(("%d in bay  \194\183  %d / %d cells  \194\183  %d of %d berths free"):format(
		inside, used, L.gridW * L.gridH, freeMoor, #L.berths), B.x, B.y + 15, B.w - PAD, "right")

	Sheet.label(("Interior bay  %d \195\151 %d"):format(L.gridW, L.gridH), L.gx, L.gy - 18)
	Sheet.label("Outside berths", L.moor.x, L.gy - 18)

	-- grid
	lg.setColor(0, 0, 0, 0.35)
	lg.rectangle("fill", L.gx, L.gy, L.gridW * cs, L.gridH * cs)
	lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.1)
	for cy = 0, L.gridH - 1 do
		for cx = 0, L.gridW - 1 do lg.rectangle("line", L.gx + cx * cs + 0.5, L.gy + cy * cs + 0.5, cs - 1, cs - 1) end
	end
	-- airlock stripe between bay and moorings
	local A = L.airlock
	for yy = A.y, A.y + A.h - 4, 10 do
		lg.setColor(1, 0.83, 0.42, 0.28)
		lg.rectangle("fill", A.x + 3, yy, A.w - 6, 5)
	end

	-- moorings
	local hullId = h and h.hull or (sel and sel.hull) or p.hull.id
	local length, width = game.shipDimensions(hullId)
	for _, row in ipairs(L.berths) do
		if row.visible and not row.ship then
			local taken = game:mooringTaken(L.station, row.index)
			local small = length > row.slot.length or width > row.slot.width
			local ok = not taken and not small and game:mooringClear(L.station, row.index, hullId)
			local status = taken and "visiting ship" or small and "too small" or not ok and "blocked" or "free"
			local col = (h and ok) and ACTIVE or HUD.AQUA
			if h and ok and inRect(row, mx, my) then
				lg.setColor(col[1], col[2], col[3], 0.18)
				lg.rectangle("fill", row.x, row.y, row.w, row.h, 4, 4)
			end
			lg.setColor(col[1], col[2], col[3], (taken or small) and 0.15 or 0.35)
			lg.rectangle("line", row.x + 0.5, row.y + 0.5, row.w - 1, row.h - 1, 4, 4)
			lg.setFont(HUD.font(14))
			lg.setColor(HUD.INK[1], HUD.INK[2], HUD.INK[3], (taken or small) and 0.5 or 1)
			lg.print(("Berth %d"):format(row.index), row.x + 8, row.y + 6)
			lg.setFont(HUD.font(13))
			if taken or not ok then lg.setColor(HUD.WARN[1], HUD.WARN[2], HUD.WARN[3], 0.75) else lg.setColor(HUD.DIM) end
			lg.printf(status, row.x, row.y + 7, row.w - 8, "right")
			lg.setColor(HUD.DIM)
			lg.print(("fits up to %g \195\151 %g"):format(row.slot.length, row.slot.width), row.x + 8, row.y + 25)
		end
	end
	if L.totalRows > L.visibleRows then
		lg.setFont(HUD.font(13))
		lg.setColor(HUD.DIM)
		local above, below = Hangar.scroll, L.totalRows - L.visibleRows - Hangar.scroll
		if above > 0 then lg.printf(("\226\150\178 %d more"):format(above), L.moor.x, L.gy - 18, L.moor.w, "right") end
		if below > 0 then lg.printf(("\226\150\188 %d more (scroll)"):format(below), L.moor.x, L.moor.y + L.moor.h - 2, L.moor.w, "right") end
	end

	for _, v in ipairs(L.visitors or {}) do
		lg.setColor(HUD.DIM[1], HUD.DIM[2], HUD.DIM[3], 0.12)
		lg.rectangle("fill", v.x + 2, v.y + 2, v.w - 4, v.h - 4, 4, 4)
		lg.setColor(HUD.DIM[1], HUD.DIM[2], HUD.DIM[3], 0.5)
		lg.rectangle("line", v.x + 2.5, v.y + 2.5, v.w - 5, v.h - 5, 4, 4)
		drawHull(data.hulls[v.hull], v.x + 4, v.y + 4, v.w - 8, v.h - 8, v.rot or false, HUD.DIM, 0.5)
		tileName(v, "VISITING  " .. data.hulls[v.hull].name, 0.6)
	end
	-- ships, in the bay and on moorings
	for _, s in ipairs(L.ships) do
		local col = shipColor(game, s.owner)
		local alpha = (h and h.owner == s.owner) and 0.35 or 1
		local hot = not h and inRect(s, mx, my)
		lg.setColor(col[1], col[2], col[3], 0.1 * alpha)
		lg.rectangle("fill", s.x + 2, s.y + 2, s.w - 4, s.h - 4, 4, 4)
		lg.setColor(col[1], col[2], col[3], ((sel == s) and 0.95 or (hot and 0.6 or 0.3)) * alpha)
		lg.setLineWidth(sel == s and 2 or 1)
		lg.rectangle("line", s.x + 2.5, s.y + 2.5, s.w - 5, s.h - 5, 4, 4)
		lg.setLineWidth(1)
		local name = data.hulls[s.hull].name
		if s.exterior then
			drawHull(data.hulls[s.hull], s.x + 90, s.y + 4, s.w - 96, s.h - 8, false, col, alpha)
			lg.setFont(HUD.font(14))
			lg.setColor(HUD.INK[1], HUD.INK[2], HUD.INK[3], alpha)
			local mooring = s.owner == p and s.owner.parkingMooring or s.owner.mooring
			lg.print(("Berth %d"):format(mooring), s.x + 8, s.y + 6)
			lg.setFont(HUD.font(13))
			lg.setColor(s.owner == p and ACTIVE or HUD.DIM)
			lg.print((s.owner == p and "FLYING  " or "") .. name, s.x + 8, s.y + 25)
		else
			drawHull(data.hulls[s.hull], s.x + 4, s.y + 4, s.w - 8, s.h - 8, s.bay and s.bay.rot or false, col, alpha)
			tileName(s, (s.owner == p and "FLYING  " or "") .. name, alpha)
		end
	end

	-- the ship in hand
	if h then
		local over = false
		for _, row in ipairs(L.berths) do if row.visible and inRect(row, mx, my) then over = true end end
		local w, ht = footprint(game, h.hull, h.rot)
		if not over then
			local bay, ok = dropSpot(game, L, mx, my)
			lg.setColor(ok and 0.3 or 1, ok and 1 or 0.35, ok and 0.5 or 0.3, 0.25)
			for cy = bay.y, bay.y + ht - 1 do
				for cx = bay.x, bay.x + w - 1 do
					if cx >= 0 and cy >= 0 and cx < L.gridW and cy < L.gridH then
						lg.rectangle("fill", L.gx + cx * cs + 1, L.gy + cy * cs + 1, cs - 2, cs - 2)
					end
				end
			end
		end
		drawHull(data.hulls[h.hull], mx - (h.dx + 0.5) * cs, my - (h.dy + 0.5) * cs, w * cs, ht * cs, h.rot,
			shipColor(game, h.owner), 0.8)
	end
end

local function drawCard(game, L, mx, my, sel)
	local p, h = game.player, Hangar.hand
	local I = L.info
	Station.panel(I.x, I.y, I.w, I.h)
	local owner = sel and sel.owner or p
	local flying = owner == p
	local rec = flying and { hull = p.hull.id, loadout = p.loadout, hold = p.hold, armor = p.armor } or owner
	local hull = data.hulls[rec.hull]
	local loadout = rec.loadout or hull.loadout
	local s = stats.compute(hull, loadout)
	local x, w = I.x + PAD, I.w - PAD * 2
	local y = I.y + 12

	y = Sheet.label(flying and "Active ship" or "Stored ship", x, y)
	lg.setFont(HUD.font(20))
	lg.setColor(HUD.INK)
	lg.print(hull.name, x, y)
	y = y + 24
	local fw, fh = game.hangarFootprint(hull.id, false)
	lg.setFont(HUD.font(13))
	lg.setColor(HUD.DIM)
	lg.printf(("%s \194\183 %s \194\183 %d\195\151%d cells"):format(hull.maker, hull.class, fw, fh), x, y, w)
	y = y + 18
	local col = flying and p.color or owner.color or p.color
	y = Sheet.outline(hull, col, x, y, w, 58) + 2
	if col.name then
		lg.setColor(col[1], col[2], col[3])
		lg.rectangle("fill", x, y + 2, 10, 10, 2, 2)
		lg.setFont(HUD.font(13))
		lg.setColor(HUD.DIM)
		lg.print(col.name, x + 16, y)
		y = y + 22
	end

	local used, total = 0, s.hold
	if rec.hold then used, total = Hold.cells(rec.hold) end
	y = Sheet.bar("Armor", floor(rec.armor or s.armor), s.armor, x, y, w)
	y = Sheet.bar("Hold (m3)", used, total, x, y, w) + 2

	local fitted = 0
	for i in ipairs(hull.slots) do if loadout[i] then fitted = fitted + 1 end end
	y = Sheet.label(("Fit \194\183 %d of %d slots"):format(fitted, #hull.slots), x, y)
	y = Sheet.slots(hull, loadout, x, y, w, L.fly.y - 22) + 4

	lg.setFont(HUD.font(13))
	lg.setColor(HUD.DIM)
	lg.printf("Parked: " .. game:shipParkingLabel(L.station, owner), x, L.fly.y - 18, w)

	local busy = h ~= nil
	local canMove = owner.bay and game:mooringFit(L.station, hull.id, owner)
		or not owner.bay and game:hangarFit(L.station, hull.id, owner)
	Sheet.button(L.fly, flying and "Flying this ship" or "Fly this ship", not busy and inRect(L.fly, mx, my),
		Sheet.GREEN, not flying)
	Sheet.button(L.cargo, flying and "Fit & cargo" or "Open hold", not busy and inRect(L.cargo, mx, my))
	Sheet.button(L.move, owner.bay and "Move outside" or "Move inside", not busy and inRect(L.move, mx, my),
		nil, not not canMove)
	local price = not flying and game.shipSellPrice(owner)
	local confirming = Hangar.confirmSell == owner
	Sheet.button(L.sell, flying and "Can't sell the ship you're flying"
		or (confirming and ("Click again to sell for %s"):format(HUD.credits(price)))
		or ("Sell \194\183 %s"):format(HUD.credits(price)),
		not busy and inRect(L.sell, mx, my), HUD.WARN, not flying)
end

function Hangar.draw(game, mx, my)
	local L = layout(game)
	if not L then return end
	local sel = selected(game, L)
	drawBerths(game, L, mx, my, sel)
	drawCard(game, L, mx, my, sel)
end

-- What a click asks for: { fly = i }, { cargo = rec }, { move = owner,
-- outside = bool }, { sell = i } or nil. Pressing on a ship selects it
-- and picks it up to move.
function Hangar.mousepressed(game, mx, my, button)
	local L = layout(game)
	if not L or button ~= 1 then return nil end
	local sel = selected(game, L)
	local owner = sel and sel.owner or game.player
	local parked = owner ~= game.player and listIndex(L, owner)
	local confirm = Hangar.confirmSell
	Hangar.confirmSell = nil
	if inRect(L.sell, mx, my) then
		if not parked then return nil end
		if confirm == owner then return { sell = parked } end
		Hangar.confirmSell = owner
		return nil
	end
	if inRect(L.move, mx, my) then return { move = owner, outside = owner.bay ~= nil } end
	if inRect(L.fly, mx, my) then return parked and { fly = parked } or nil end
	if inRect(L.cargo, mx, my) then
		if parked then return { cargo = owner } end
		return { cargo = false }
	end

	local s = shipAt(L, mx, my)
	if not s then return nil end
	local now = love.timer.getTime()
	local c = Hangar.lastClick
	local double = c and c.owner == s.owner and now - c.t < 0.35
	Hangar.lastClick = { owner = s.owner, t = now }
	Hangar.sel = s.owner
	if double and s.i then return { fly = s.i } end
	Hangar.hand = { owner = s.owner, hull = s.hull, rot = s.bay and s.bay.rot or false,
		dx = s.exterior and 0 or floor((mx - s.x) / L.cs), dy = s.exterior and 0 or floor((my - s.y) / L.cs) }
	return nil
end

function Hangar.mousereleased(game, mx, my)
	local h = Hangar.hand
	if not h then return end
	local L = layout(game)
	local parking
	if L then
		for _, row in ipairs(L.berths) do
			if row.visible and inRect(row, mx, my) and game:mooringFits(L.station, row.index, h.hull, h.owner) then
				parking = { mooring = row.index }; break
			end
		end
		if not parking then
			local bay, ok = dropSpot(game, L, mx, my)
			if ok then parking = { bay = bay } end
		end
	end
	Hangar.hand = nil
	if not parking then return end
	game:applyParking(h.owner, parking)
	if h.owner == game.player then game:dockInstantly(h.owner, L.station, game:parkingPlacement(L.station, parking)) end
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

function Hangar.focus(game, ownerToShow)
	if ownerToShow then Hangar.sel = ownerToShow end
	Hangar.confirmSell = nil
	local L = layout(game)
	if not L then return end
	local owner = Hangar.sel
	local valid = owner == game.player or listIndex(L, owner) ~= nil
	if not valid then owner = game.player; Hangar.sel = owner end
	local index = owner == game.player and owner.parkingMooring or owner.mooring
	if index then Hangar.scroll = max(0, index - L.visibleRows) end
end

function Hangar.wheelmoved(game, y)
	local L = layout(game)
	if not L then return end
	Hangar.scroll = max(0, min(max(0, L.totalRows - L.visibleRows), Hangar.scroll - y))
end

-- Drop whatever's in hand (the screen closed or the tab changed).
function Hangar.cancel()
	Hangar.hand = nil
	Hangar.confirmSell = nil
end

Hangar.layout = layout     -- for the autotest

return Hangar
