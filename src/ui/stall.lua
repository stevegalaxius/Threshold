-- The Manage tab: your business at this station on one screen.
--   left    This station (its standing toward you, what that unlocks,
--           whether it's home), your ships and storage here, and your
--           satellites wherever they are
--   right   your market stall (src/stalls.lua): rent it, pick a price
--           tag, click goods on and off it, and read what sold. NPCs shop
--           it on their visits (src/npc_shopping.lua).
-- Drawn as tiles and cards in the property gold, not the Jobs board's rows.
local data = require("src.data")
local L = require("src.locations")
local HUD, Station = require("src.hud"), require("src.ui.station")
local Stall = require("src.stalls")
local Hold = require("src.inventory.hold")
local Icons = require("src.icons")
local View = {}
local lg = love.graphics

local GOLD = { 1, 0.82, 0.45 }
local GOOD = { 0.5, 0.95, 0.6 }
local TILE, GAP = 74, 8

local function text(x, y, w, s, size, color, align)
	lg.setFont(HUD.font(size or 14)); lg.setColor(color or HUD.INK)
	lg.printf(s, x, y, w, align or "left")
end
local function inside(r, x, y) return r and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h end
local function itemName(id) return data.items[id] and data.items[id].name or id end
local function here(game)
	local st = game.player and game.player.dockState and game.player.dockState.station
	return st, st and L.canonical(st.key or st.locationId)
end
local function ago(u, at)
	local m = math.max(0, math.floor(((u.clock or 0) - at) / 60))
	if m < 60 then return m .. " min ago" end
	return math.floor(m / 60) .. " h ago"
end
local function sorted(t)
	local out = {}
	for id, n in pairs(t) do if n > 0 then out[#out + 1] = id end end
	table.sort(out, function(a, b) return itemName(a) < itemName(b) end)
	return out
end
-- A card: a panel with a gold title strip.
local function card(x, y, w, h, title)
	Station.panel(x, y, w, h)
	lg.setColor(GOLD[1], GOLD[2], GOLD[3], 0.12); lg.rectangle("fill", x + 1, y + 1, w - 2, 28, 5, 5)
	lg.setColor(GOLD[1], GOLD[2], GOLD[3], 0.6); lg.rectangle("fill", x + 1, y + 1, 4, 28)
	text(x + 14, y + 6, w - 28, title, 13, GOLD)
end
local function bar(x, y, w, h, frac, col)
	lg.setColor(1, 1, 1, 0.08); lg.rectangle("fill", x, y, w, h, 3, 3)
	lg.setColor(col[1], col[2], col[3], 0.85); lg.rectangle("fill", x, y, math.max(0, math.min(1, frac)) * w, h, 3, 3)
end

function View.layout(game)
	local x, y, w, h = Station.body()
	local u = game.universe
	local st, k = here(game)
	local f = { x = x, y = y, w = w, h = h, st = st, k = k, tiles = {}, tags = {} }
	f.side = { x = x, y = y, w = 340 }
	f.main = { x = x + 352, y = y, w = w - 352, h = h }
	f.stall = k and Stall.get(u, k)
	local m = f.main
	if not f.stall then
		f.can, f.why = Stall.canRent(u, k)
		f.rent = { x = m.x + 24, y = m.y + 200, w = 220, h = 40 }
		return f
	end
	for i, t in ipairs(Stall.TAGS) do
		f.tags[i] = { tag = t.id, label = t.name, note = t.note, x = m.x + 16 + (i - 1) * 124, y = m.y + 100, w = 118, h = 34 }
	end
	f.close = { x = m.x + m.w - 150, y = m.y + 40, w = 134, h = 30 }
	-- stall tiles, then hold tiles
	local cols = math.max(1, math.floor((m.w - 32 + GAP) / (TILE + GAP)))
	local function grid(list, counts, top, side, rows)
		for i, id in ipairs(list) do
			if i > cols * rows then break end
			local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
			f.tiles[#f.tiles + 1] = { side = side, id = id, n = counts[id], x = m.x + 16 + c * (TILE + GAP), y = top + r * (TILE + GAP), w = TILE, h = TILE }
		end
	end
	-- as many tile rows as fit above a few lines of sales
	local rows = math.max(1, math.min(3, math.floor((m.h - 172 - 120 - 76) / (2 * (TILE + GAP)))))
	f.stockTop = m.y + 172
	grid(sorted(f.stall.stock), f.stall.stock, f.stockTop + 24, "stall", rows)
	f.holdTop = f.stockTop + 24 + rows * (TILE + GAP) + 14
	local hold = game.player.hold and Hold.totals(game.player.hold) or {}
	grid(sorted(hold), hold, f.holdTop + 24, "hold", rows)
	f.ledgerTop = f.holdTop + 24 + rows * (TILE + GAP) + 14
	return f
end

local function drawSide(game, f)
	local u, s = game.universe, f.side
	local Rep = require("src.reputation")
	local cy = s.y
	-- this station
	local att = f.k and Rep.stationAttitude(u, f.k) or 0
	card(s.x, cy, s.w, 132, "THIS STATION")
	local home = u.home and L.canonical(u.home.key or "") == f.k
	text(s.x + 14, cy + 36, s.w - 28, (f.st and f.st.name or "?") .. (home and "  ·  home" or ""), 15)
	text(s.x + 14, cy + 58, s.w - 28, ("Standing: %s (%d)"):format(Rep.tierName(att), math.floor(att)), 13, HUD.DIM)
	-- standing bar, -100..100, with the stall's line marked
	local bx, by, bw = s.x + 14, cy + 82, s.w - 28
	bar(bx, by, bw, 10, (att + 100) / 200, att >= Stall.minRep and GOOD or HUD.WARN)
	local mx = bx + (Stall.minRep + 100) / 200 * bw
	lg.setColor(GOLD); lg.rectangle("fill", mx - 1, by - 3, 2, 16)
	text(s.x + 14, cy + 100, s.w - 28, att >= Stall.minRep and "Friendly enough to rent here" or "Stalls open at Friendly", 12, att >= Stall.minRep and GOOD or HUD.DIM)
	cy = cy + 144
	-- your ships and storage here
	local ships = f.st and game:hangar(f.st) or {}
	local storage = f.st and game:stationStorage(f.st)
	local held, kinds = 0, 0
	for _, n in pairs(storage and Hold.totals(storage) or {}) do held = held + n; kinds = kinds + 1 end
	card(s.x, cy, s.w, 92, "YOURS HERE")
	text(s.x + 14, cy + 36, s.w - 28, ("%d ship%s in the hangar"):format(#ships, #ships == 1 and "" or "s"), 13)
	text(s.x + 14, cy + 58, s.w - 28, ("%d item%s in storage (%d kinds)"):format(held, held == 1 and "" or "s", kinds), 13)
	cy = cy + 104
	-- your satellites
	local Sat = require("src.satellites")
	local mine = Sat.mine(u)
	local hh = 44 + math.max(1, #mine) * 46
	card(s.x, cy, s.w, hh, ("YOUR SATELLITES · %d of %d"):format(#mine, Sat.playerCap))
	if #mine == 0 then text(s.x + 14, cy + 38, s.w - 28, "None up. Buy a satellite package at a logistics station and use it in orbit.", 12, HUD.DIM) end
	for i, r in ipairs(mine) do
		local ry = cy + 36 + (i - 1) * 46
		local fuel = Sat.fuel(u, r)
		local F = require("src.fields")[r.field]
		text(s.x + 14, ry, s.w - 28, (F and F.name or r.field) .. " · " .. HUD.credits(r.earned or 0) .. " earned", 13)
		bar(s.x + 14, ry + 22, s.w - 28, 8, fuel, fuel <= 0 and HUD.WARN or fuel < Sat.refuelAt and GOLD or HUD.AQUA)
	end
end

local function drawTile(t, s, mx, my)
	local hot = inside(t, mx, my)
	lg.setColor(1, 1, 1, hot and 0.14 or 0.06); lg.rectangle("fill", t.x, t.y, t.w, t.h, 6, 6)
	lg.setColor(t.side == "stall" and GOLD or HUD.DIM); lg.setLineWidth(1); lg.rectangle("line", t.x + 0.5, t.y + 0.5, t.w - 1, t.h - 1, 6, 6)
	if not Icons.drawInRect(t.id, t.x + 6, t.y + 4, t.w - 12, t.h - 26, nil, 1, 4) then
		text(t.x + 4, t.y + 18, t.w - 8, itemName(t.id), 10, HUD.DIM, "center")
	end
	text(t.x, t.y + 4, t.w - 6, "×" .. t.n, 12, HUD.INK, "right")
	if t.side == "stall" then text(t.x, t.y + t.h - 19, t.w, HUD.credits(Stall.price(s, t.id)), 11, GOLD, "center") end
end

function View.draw(game)
	local f = View.layout(game)
	local u = game.universe
	local mx, my = love.mouse.getPosition()
	drawSide(game, f)
	local m = f.main
	if not f.stall then
		card(m.x, m.y, m.w, 270, "MARKET STALL")
		text(m.x + 24, m.y + 44, m.w - 48, "Rent a stall in this market", 20, HUD.INK)
		text(m.x + 24, m.y + 76, m.w - 48, ("Stock it with anything from your hold and pick one price tag. NPCs who dock here shop it alongside the house shelves, and every sale pays you. %s an hour."):format(HUD.credits(Stall.rent)), 13, HUD.DIM)
		local Rep = require("src.reputation")
		local okRep = f.k and Rep.stationAttitude(u, f.k) >= Stall.minRep
		local okCr = (u.credits or 0) >= Stall.rent
		for i, req in ipairs({ { okRep, "Friendly standing with this station" }, { okCr, "The first hour's rent" } }) do
			local ry = m.y + 130 + (i - 1) * 22
			lg.setColor(req[1] and GOOD or HUD.WARN); lg.circle("fill", m.x + 30, ry + 9, 4)
			text(m.x + 42, ry, m.w - 66, req[2], 13, req[1] and GOOD or HUD.WARN)
		end
		Station.button(f.rent, "Rent stall", false, f.can)
		if not f.can and f.why then text(f.rent.x + f.rent.w + 16, f.rent.y + 12, m.w - 300, f.why, 12, HUD.WARN) end
		return
	end
	local s = f.stall
	local n, cr = Stall.recent(u, s)
	card(m.x, m.y, m.w, m.h, "YOUR MARKET STALL")
	-- headline numbers
	local stats = { { HUD.credits(cr), "taken today" }, { tostring(n), n == 1 and "sale today" or "sales today" },
		{ HUD.credits(s.earned or 0), "earned in all" }, { HUD.credits(Stall.rent) .. "/h", "rent" } }
	for i, v in ipairs(stats) do
		local sx = m.x + 16 + (i - 1) * 150
		text(sx, m.y + 36, 140, v[1], 18, i == 1 and GOLD or HUD.INK)
		text(sx, m.y + 62, 140, v[2], 11, HUD.DIM)
	end
	Station.button(f.close, "Close stall", false, true)
	for _, t in ipairs(f.tags) do Station.button(t, t.label, s.tag == t.tag, true) end
	local tag = Stall.byTag[s.tag]
	text(m.x + 16 + 3 * 124 + 8, m.y + 110, m.w - 420, tag and tag.note or "", 12, HUD.DIM)
	local hover
	for _, t in ipairs(f.tiles) do if inside(t, mx, my) then hover = t end end
	text(m.x + 16, m.y + 146, m.w - 32, hover and (itemName(hover.id) .. " · list " .. HUD.credits(Stall.list(hover.id)) .. (hover.side == "hold" and " · click to put one out" or " · click to take one back"))
		or "Click a tile to move one; right-click moves the whole stack.", 12, hover and HUD.INK or HUD.DIM)
	text(m.x + 16, f.stockTop, m.w - 32, "ON YOUR STALL", 12, GOLD)
	text(m.x + 16, f.holdTop, m.w - 32, "YOUR HOLD", 12, HUD.DIM)
	local any = { stall = false, hold = false }
	for _, t in ipairs(f.tiles) do any[t.side] = true; drawTile(t, s, mx, my) end
	if not any.stall then text(m.x + 16, f.stockTop + 50, m.w - 32, "Empty. Click goods in your hold to put them out.", 13, HUD.DIM) end
	if not any.hold then text(m.x + 16, f.holdTop + 50, m.w - 32, "Nothing in your hold.", 13, HUD.DIM) end
	text(m.x + 16, f.ledgerTop, m.w - 32, "RECENT SALES", 12, GOLD)
	local room = math.max(1, math.floor((m.y + m.h - f.ledgerTop - 30) / 20))
	for i, e in ipairs(s.ledger) do
		if i > room then break end
		local ly = f.ledgerTop + 4 + i * 20
		text(m.x + 16, ly, m.w - 200, ("%s ×%d to %s"):format(itemName(e.item), e.n, e.buyer), 12)
		text(m.x + 16, ly, m.w - 32, HUD.credits(e.price) .. "  ·  " .. ago(u, e.at), 12, HUD.DIM, "right")
	end
	if #s.ledger == 0 then text(m.x + 16, f.ledgerTop + 24, m.w - 32, "Nothing sold yet. NPCs browse when they dock here.", 12, HUD.DIM) end
end

function View.mousepressed(game, mx, my, button)
	local f = View.layout(game)
	local u = game.universe
	if not f.stall then
		if button == 1 and inside(f.rent, mx, my) then
			local s, why = Stall.open(u, f.k)
			game:toast(s and "STALL RENTED" or (why or ""):upper(), 2)
		end
		return true
	end
	if button == 1 then
		for _, t in ipairs(f.tags) do if inside(t, mx, my) then Stall.setTag(f.stall, t.tag) end end
		if inside(f.close, mx, my) then
			Stall.close(u, f.k, game); game:toast("STALL CLOSED: STOCK MOVED TO STORAGE", 2.5)
			return true
		end
	end
	local hold = game.player.hold
	for _, t in ipairs(f.tiles) do
		if inside(t, mx, my) and hold then
			local n = button == 2 and t.n or 1
			if t.side == "hold" then Stall.stock(f.stall, hold, t.id, n)
			elseif Stall.unstock(f.stall, hold, t.id, n) < n then game:toast("NO ROOM IN YOUR HOLD", 1.5) end
			game.player.cargo = Hold.totals(hold); game.player.massDirty = true
		end
	end
	return true
end
function View.wheelmoved(game, y) end
return View
