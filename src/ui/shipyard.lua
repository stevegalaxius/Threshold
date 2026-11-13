--[[
	The Shipyard tab of the station screen: the ships on this station's
	dealer lot (src/dealers.lua, via Game:shipyard) as a list, and the
	selected one in detail.

	  list        silhouette in its paint, trim, maker and class, price, and
	              where it would park here (or that it won't fit)
	  detail      the hull with its slots numbered, its paint, its fit slot by slot,
	              its numbers against the ship you're flying, a map of the
	              bay with the new ship's footprint where it will park, an
	              optional trade-in from your stored ships, and Buy

	Selling a ship outright is on the Hangar tab's ship card. Buying goes
	through Game:buyShip (src/market.lua) with the paint and trade-in.
	This only draws and reports clicks; src/ui/cargo.lua owns the tabs.
]]

local data = require("src.data")
local HUD = require("src.hud")
local Paint = require("src.paint")
local Station = require("src.ui.station")
local Sheet = require("src.ui.shipsheet")
local Hangar = require("src.ui.hangar")

local Dealers = require("src.dealers")

local Yard = { sel = nil, tradeIn = nil, scroll = 0, confirm = false }

local lg = love.graphics
local floor, max, min = math.floor, math.max, math.min
local GAP, PAD = 16, 14
local LIST_W, ROW_H, LEFT_W = 300, 64, 360

local function inRect(r, x, y)
	return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

local function station(game)
	local p = game.player
	return p and p.dockState and p.dockState.station
end

-- Stored ships that can be traded in (not the one you're flying).
local function tradeable(game, st)
	local out = {}
	for _, rec in ipairs(game:hangar(st)) do out[#out + 1] = rec end
	return out
end

local function valid(game, st)
	local stock = game:shipyard(st)
	local found = false
	for _, lot in ipairs(stock) do if lot.id == Yard.sel then found = true end end
	if not found then Yard.sel = stock[1] and stock[1].id end
	if Yard.tradeIn then
		local here = false
		for _, rec in ipairs(game:hangar(st)) do if rec == Yard.tradeIn then here = true end end
		if not here then Yard.tradeIn = nil end
	end
end

function Yard.layout(game)
	local st = station(game)
	if not st then return nil end
	valid(game, st)
	local sw, sh = lg.getDimensions()
	local x, y, tw, ph = require("src.ui.station").body()
	local L = { x = x, y = y, w = tw, h = ph, station = st, stock = game:shipyard(st) }
	L.list = { x = x, y = y, w = LIST_W, h = ph }
	L.detail = { x = x + LIST_W + GAP, y = y, w = tw - LIST_W - GAP, h = ph }
	-- list rows
	local top = y + 44
	local visible = max(1, floor((ph - 44 - PAD) / ROW_H))
	Yard.scroll = max(0, min(Yard.scroll, #L.stock - visible))
	L.visibleRows = visible
	L.rows = {}
	for i, lot in ipairs(L.stock) do
		local k = i - Yard.scroll
		if lot.id == Yard.sel then L.lot = lot end
		if k >= 1 and k <= visible then
			table.insert(L.rows, { id = lot.id, lot = lot, x = x + 4, y = top + (k - 1) * ROW_H, w = LIST_W - 8, h = ROW_H - 2 })
		end
	end
	if not L.lot then return L end
	-- detail: left column (hull, paint, fit), right column (numbers, parking, buy)
	local D = L.detail
	L.lx, L.lw = D.x + PAD, LEFT_W
	L.rx = D.x + PAD + LEFT_W + 24
	L.rw = D.x + D.w - PAD - L.rx
	L.paintY = D.y + 188
	L.buy = { x = L.rx, y = D.y + D.h - PAD - 34, w = L.rw, h = 34 }
	L.tiPrev = { x = L.rx, y = L.buy.y - 104, w = 26, h = 24 }
	L.tiNext = { x = L.rx + L.rw - 26, y = L.tiPrev.y, w = 26, h = 24 }
	return L
end

-- Where a hull would park here: "inside", "mooring N" or nil.

local SALE = { 1, 0.78, 0.3 }
-- Where a lot ship stands on display: inside, at a berth, or still waiting.
local function displayText(lot)
	if lot.bay then return "On display in the hangar", SALE end
	if lot.mooring then return ("On display at berth %d"):format(lot.mooring), SALE end
	return "Arriving: waiting for space", HUD.DIM
end

local function parkingText(p)
	if not p then return "No room here", HUD.WARN end
	if p.bay then return "Fits inside", { 0.4, 1, 0.55 } end
	return ("Berth %d"):format(p.mooring), { 0.4, 1, 0.55 }
end

local function drawList(game, L, mx, my)
	local P = L.list
	Station.panel(P.x, P.y, P.w, P.h)
	lg.setFont(HUD.font(18))
	lg.setColor(HUD.INK)
	local def = Dealers.def(L.station)
	lg.print(def and def.name or "For sale here", P.x + PAD, P.y + 8)
	lg.setFont(HUD.font(12))
	lg.setColor(HUD.DIM)
	lg.print(def and (def.assembly and "Factory dealer" or "Used ship dealer") or "No dealer", P.x + PAD, P.y + 27)
	lg.printf(def and def.assembly and ("%d on the lot"):format(#L.stock) or ("%d / %d on the lot"):format(#L.stock, def and def.lots or 0), P.x, P.y + 27, P.w - PAD, "right")
	if #L.stock == 0 then
		lg.printf((def and (def.manufacturer and "The lot is empty. New ships roll out as the works finishes hull frames."
				or "The lot is empty. More ships come in over time.") or "This station has no ships for sale.")
			.. "\n\nYou can still sell your stored ships from their card on the Hangar tab.",
			P.x + PAD, P.y + 56, P.w - PAD * 2)
		return
	end
	for _, r in ipairs(L.rows) do
		local lot = r.lot
		local hull = data.hulls[lot.hull]
		local on, hot = r.id == Yard.sel, inRect(r, mx, my)
		if on or hot then
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], on and 0.16 or 0.07)
			lg.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)
		end
		lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.08)
		lg.line(r.x + 6, r.y + r.h + 0.5, r.x + r.w - 6, r.y + r.h + 0.5)
		local paint = Paint.preset(lot.paint)
		Hangar.drawHull(hull, r.x + 6, r.y + 8, 70, r.h - 16, false, paint, 1)
		lg.setFont(HUD.font(16))
		lg.setColor(HUD.INK)
		lg.print(hull.name, r.x + 86, r.y + 8)
		lg.setFont(HUD.font(13))
		lg.setColor(HUD.DIM)
		lg.print(("%s \194\183 %s"):format((lot.used and ("Used / "..math.floor(lot.condition*100).."%") or lot.trimName or lot.trim), hull.class), r.x + 86, r.y + 25)
		lg.setFont(HUD.font(15))
		lg.setColor(game:credits() >= lot.price and HUD.INK or HUD.WARN)
		lg.printf(HUD.credits(lot.price), r.x, r.y + 8, r.w - 8, "right")
		local text, col = displayText(lot)
		lg.setFont(HUD.font(12))
		lg.setColor(col)
		lg.print(text, r.x + 86, r.y + 42)
	end
	if #L.stock > L.visibleRows then
		lg.setFont(HUD.font(13))
		lg.setColor(HUD.DIM)
		lg.printf("scroll for more", P.x, P.y + P.h - 20, P.w - PAD, "right")
	end
end

-- The bay in miniature with the new ship's footprint where it will go.
local function drawParking(game, L, lot, x, y, w, h)
	local st = L.station
	local hullId = lot.hull
	local p = game:purchaseParking(st, lot, Yard.tradeIn)
	local text, col = displayText(lot)
	lg.setFont(HUD.font(14))
	lg.setColor(col)
	lg.printf(text, x, y - 15, w, "right")
	local W, H = game.hangarSize(st)
	local cs = max(3, min(14, floor(w / W), floor(h / H)))
	local gx, gy = x, y + 4
	lg.setColor(0, 0, 0, 0.35)
	lg.rectangle("fill", gx, gy, W * cs, H * cs)
	lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.08)
	for cy = 0, H - 1 do
		for cx = 0, W - 1 do lg.rectangle("line", gx + cx * cs + 0.5, gy + cy * cs + 0.5, cs - 1, cs - 1) end
	end
	local function block(owner, hull, bay, c, a)
		if not bay then return end
		local fw, fh = game.hangarFootprint(hull, bay.rot)
		lg.setColor(c[1], c[2], c[3], a)
		lg.rectangle("fill", gx + bay.x * cs + 1, gy + bay.y * cs + 1, fw * cs - 2, fh * cs - 2, 2, 2)
	end
	for _, rec in ipairs(game:hangar(st)) do
		if rec ~= Yard.tradeIn then block(rec, rec.hull, rec.bay, HUD.DIM, 0.35) end
	end
	block(game.player, game.player.hull.id, game.player.bay, HUD.DIM, 0.35)
	-- the rest of the lot on display, in the dealer's colour
	for _, other in ipairs(L.stock) do
		if other ~= lot then block(other, other.hull, other.bay, SALE, 0.3) end
	end
	if p and p.bay then
		local fw, fh = game.hangarFootprint(hullId, p.bay.rot)
		lg.setColor(0.4, 1, 0.55, 0.3)
		lg.rectangle("fill", gx + p.bay.x * cs, gy + p.bay.y * cs, fw * cs, fh * cs, 2, 2)
		lg.setColor(0.4, 1, 0.55, 0.9)
		lg.rectangle("line", gx + p.bay.x * cs + 0.5, gy + p.bay.y * cs + 0.5, fw * cs - 1, fh * cs - 1, 2, 2)
	end
	return gy + H * cs, p
end

local function drawDetail(game, L, mx, my)
	local D = L.detail
	Station.panel(D.x, D.y, D.w, D.h)
	local lot = L.lot
	if not lot then return end
	local hull = data.hulls[lot.hull]
	local paint = Paint.preset(lot.paint)
	local p = game.player

	-- left: identity, hull, paint, stock fit
	local x, w = L.lx, L.lw
	local y = Sheet.label(("%s \194\183 %s"):format(hull.maker, hull.class), x, D.y + 12)
	lg.setFont(HUD.font(24))
	lg.setColor(HUD.INK)
	lg.print(hull.name, x, y)
	y = Sheet.outline(hull, paint, x, y + 30, w, 108)
	Sheet.label("Paint", x, L.paintY - 17)
	local c = Paint.preset(lot.paint)
	lg.setColor(c[1], c[2], c[3])
	lg.rectangle("fill", x, L.paintY, 26, 26, 4, 4)
	lg.setFont(HUD.font(14))
	lg.setColor(HUD.INK)
	lg.print(lot.paint, x + 36, L.paintY + 5)
	y = Sheet.paragraph(Sheet.description(hull), x, L.paintY + 36, w, 4) + 8
	y = Sheet.label(("%s fit \194\183 %d slots"):format(lot.trimName or lot.trim, #hull.slots), x, y)
	Sheet.slots(hull, lot.loadout, x, y, w, D.y + D.h - PAD)

	-- right: numbers against what you fly
	local rx, rw = L.rx, L.rw
	lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.12)
	lg.rectangle("fill", rx - 6, D.y + 10, rw + 12, 26, 4, 4)
	lg.setFont(HUD.font(16))
	lg.setColor(HUD.INK)
	lg.print("Compared with your " .. p.hull.name, rx, D.y + 14)
	lg.setFont(HUD.font(12))
	lg.setColor(HUD.DIM)
	lg.printf("both empty, as fitted", rx, D.y + 17, rw, "right")
	y = D.y + 42
	local mine = Sheet.numbers(p.hull, p.loadout)
	y = Sheet.compare(Sheet.numbers(hull, lot.loadout), mine, rx, y, rw) + 14

	-- parking preview
	Sheet.label("On the lot", rx, y)
	local gridBottom, park = drawParking(game, L, lot, rx, y + 14, rw, L.tiPrev.y - y - 50)

	-- trade-in and price
	local T = L.tiPrev
	Sheet.label("Trade in", rx, T.y - 17)
	local ti = Yard.tradeIn
	local list = tradeable(game, L.station)
	Sheet.button(L.tiPrev, "<", inRect(L.tiPrev, mx, my), nil, #list > 0)
	Sheet.button(L.tiNext, ">", inRect(L.tiNext, mx, my), nil, #list > 0)
	lg.setFont(HUD.font(14))
	lg.setColor(ti and HUD.INK or HUD.DIM)
	lg.printf(ti and data.hulls[ti.hull].name .. (ti.color and ti.color.name and (" \194\183 " .. ti.color.name) or "")
		or (#list > 0 and "None" or "No stored ships"), T.x + 30, T.y + 5, rw - 60, "center")
	local price = lot.price
	local credit = ti and game.shipSellPrice(ti) or 0
	local cost = price - credit
	local yy = T.y + 32
	local function row(label, value, col)
		lg.setFont(HUD.font(14))
		lg.setColor(HUD.DIM)
		lg.print(label, rx, yy)
		lg.setColor(col or HUD.INK)
		lg.printf(value, rx, yy, rw, "right")
		yy = yy + 18
	end
	row("Price", HUD.credits(price))
	if ti then row("Trade-in (with its hold)", "- " .. HUD.credits(credit)) end
	row(cost >= 0 and "You pay" or "You receive", HUD.credits(math.abs(cost)), { 1, 0.83, 0.42 })

	local problem = game:shipBuyProblem(L.station, lot, ti)
	local label = problem and (problem == "NOT ENOUGH CREDITS" and "Not enough credits"
			or problem == "NO SUITABLE FREE PARKING" and "No room to park it here" or problem)
		or (ti and (Yard.confirm and "Click again to trade in & buy" or "Trade in & buy " .. hull.name))
		or ("Buy " .. hull.name)
	Sheet.button(L.buy, label, inRect(L.buy, mx, my), Sheet.GREEN, problem == nil)
end

function Yard.draw(game, mx, my)
	local L = Yard.layout(game)
	if not L then return end
	drawList(game, L, mx, my)
	drawDetail(game, L, mx, my)
end

-- What a click asks for: { buy = lot, tradeIn = rec } or nil.
function Yard.mousepressed(game, mx, my, button)
	local L = Yard.layout(game)
	if not L or button ~= 1 then return nil end
	local confirm = Yard.confirm
	Yard.confirm = false
	for _, r in ipairs(L.rows) do
		if inRect(r, mx, my) then
			Yard.sel = r.id
			return nil
		end
	end
	if not L.lot then return nil end
	local list = tradeable(game, L.station)
	local function step(d)
		if #list == 0 then return end
		local k = 0
		for i, rec in ipairs(list) do if rec == Yard.tradeIn then k = i end end
		k = (k + d) % (#list + 1)          -- 0 is "None"
		Yard.tradeIn = list[k]
	end
	if inRect(L.tiPrev, mx, my) then step(-1); return nil end
	if inRect(L.tiNext, mx, my) then step(1); return nil end
	if inRect(L.buy, mx, my) then
		if game:shipBuyProblem(L.station, L.lot, Yard.tradeIn) then return nil end
		if Yard.tradeIn and not confirm then Yard.confirm = true; return nil end
		return { buy = L.lot, tradeIn = Yard.tradeIn }
	end
	return nil
end

function Yard.wheelmoved(game, y)
	local L = Yard.layout(game)
	if not L then return end
	Yard.scroll = max(0, min(#L.stock - L.visibleRows, Yard.scroll - y))
end

function Yard.cancel()
	Yard.confirm = false
end

return Yard
