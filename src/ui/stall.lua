-- The Stall tab: rent a stall in this station's market, set its price
-- tag, move goods onto it from your hold and back, and read what sold
-- (src/stalls.lua). NPCs shop it on their visits (src/npc_shopping.lua).
local data = require("src.data")
local L = require("src.locations")
local HUD, Station = require("src.hud"), require("src.ui.station")
local Stall = require("src.stalls")
local Hold = require("src.inventory.hold")
local View = { scroll = 0 }

local function text(x, y, w, s, size, color)
	love.graphics.setFont(HUD.font(size or 14)); love.graphics.setColor(color or HUD.INK)
	love.graphics.printf(s, x, y, w, "left")
end
local function inside(r, x, y) return r and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h end
local function itemName(id) return data.items[id] and data.items[id].name or id end
local function here(game) local st = game.player and game.player.dockState and game.player.dockState.station; return st and L.canonical(st.key or st.locationId) end
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

function View.layout(game)
	local x, y, w, h = Station.body()
	local u, k = game.universe, here(game)
	local f = { x = x, y = y, w = w, h = h, k = k, rows = {}, buttons = {} }
	f.stall = k and Stall.get(u, k)
	if not f.stall then
		f.can, f.why = Stall.canRent(u, k)
		f.rent = { x = x + w - 220, y = y + 20, w = 200, h = 36 }
		return f
	end
	local s = f.stall
	-- price tags and close
	for i, t in ipairs(Stall.TAGS) do
		f.buttons[#f.buttons + 1] = { tag = t.id, label = t.name, x = x + 14 + (i - 1) * 130, y = y + 54, w = 120, h = 30 }
	end
	f.close = { x = x + w - 190, y = y + 54, w = 174, h = 30 }
	-- two columns: your hold, the stall
	local colW = math.floor((w - 42) / 2)
	f.left, f.right = { x = x + 14, y = y + 110, w = colW }, { x = x + 28 + colW, y = y + 110, w = colW }
	local rowH, top = 34, y + 140
	local hold = game.player.hold and Hold.totals(game.player.hold) or {}
	local maxRows = math.max(1, math.floor((h - 140 - 190) / rowH))
	for i, id in ipairs(sorted(hold)) do
		if i > maxRows then break end
		local ry = top + (i - 1) * rowH
		f.rows[#f.rows + 1] = { side = "hold", id = id, n = hold[id], y = ry,
			one = { x = f.left.x + colW - 170, y = ry, w = 76, h = 28 }, all = { x = f.left.x + colW - 86, y = ry, w = 76, h = 28 } }
	end
	for i, id in ipairs(sorted(s.stock)) do
		if i > maxRows then break end
		local ry = top + (i - 1) * rowH
		f.rows[#f.rows + 1] = { side = "stall", id = id, n = s.stock[id], y = ry,
			one = { x = f.right.x + colW - 170, y = ry, w = 76, h = 28 }, all = { x = f.right.x + colW - 86, y = ry, w = 76, h = 28 } }
	end
	f.ledgerY = top + maxRows * rowH + 16
	return f
end

function View.draw(game)
	local f = View.layout(game)
	local u = game.universe
	local x, y, w = f.x, f.y, f.w
	if not f.stall then
		Station.panel(x, y, w, 76)
		text(x + 14, y + 12, w - 260, ("Rent a stall in this market · %s an hour"):format(HUD.credits(Stall.rent)), 16, HUD.AQUA)
		text(x + 14, y + 40, w - 260, f.can and "Stock it with anything from your hold and pick a price tag. NPCs shop it when they dock here, and every sale pays you."
			or (f.why or ""), 13, f.can and HUD.DIM or HUD.WARN)
		Station.button(f.rent, "Rent stall", false, f.can)
		return
	end
	local s = f.stall
	local n, cr = Stall.recent(u, s)
	Station.panel(x, y, w, 96)
	text(x + 14, y + 10, w - 220, ("YOUR STALL · %d sale%s in the last day for %s · %s earned in all · rent %s/h"):format(n, n == 1 and "" or "s", HUD.credits(cr), HUD.credits(s.earned or 0), HUD.credits(Stall.rent)), 15, HUD.AQUA)
	for _, b in ipairs(f.buttons) do Station.button(b, b.label, s.tag == b.tag, true) end
	local tag = Stall.byTag[s.tag]
	text(x + 14 + 3 * 130 + 10, y + 60, w - 600, tag and tag.note or "", 13, HUD.DIM)
	Station.button(f.close, "Close stall", false, true)
	Station.panel(x, y + 104, w, f.h - 104)
	text(f.left.x, f.left.y, f.left.w, "YOUR HOLD", 14, HUD.DIM)
	text(f.right.x, f.right.y, f.right.w, "ON YOUR STALL · price each", 14, HUD.DIM)
	local any = { hold = false, stall = false }
	for _, row in ipairs(f.rows) do
		local col = row.side == "hold" and f.left or f.right
		any[row.side] = true
		local label = ("%s ×%d"):format(itemName(row.id), row.n)
		if row.side == "stall" then label = label .. " · " .. HUD.credits(Stall.price(s, row.id)) end
		text(col.x, row.y + 6, col.w - 180, label, 13)
		Station.button(row.one, row.side == "hold" and "Stock 1" or "Take 1", false, true)
		Station.button(row.all, row.side == "hold" and "Stock all" or "Take all", false, true)
	end
	if not any.hold then text(f.left.x, f.left.y + 32, f.left.w, "Nothing in your hold.", 13, HUD.DIM) end
	if not any.stall then text(f.right.x, f.right.y + 32, f.right.w, "Empty. Stock it from your hold.", 13, HUD.DIM) end
	text(x + 14, f.ledgerY, w - 28, "RECENT SALES", 14, HUD.DIM)
	for i, e in ipairs(s.ledger) do
		if i > 6 then break end
		text(x + 14, f.ledgerY + 6 + i * 22, w - 28, ("%s ×%d to %s · %s · %s"):format(itemName(e.item), e.n, e.buyer, HUD.credits(e.price), ago(u, e.at)), 13)
	end
	if #s.ledger == 0 then text(x + 14, f.ledgerY + 28, w - 28, "Nothing sold yet. NPCs browse when they dock here.", 13, HUD.DIM) end
end

function View.mousepressed(game, mx, my, button)
	if button ~= 1 then return true end
	local f = View.layout(game)
	local u = game.universe
	if not f.stall then
		if inside(f.rent, mx, my) then
			local s, why = Stall.open(u, f.k)
			game:toast(s and "STALL RENTED" or (why or ""):upper(), 2)
		end
		return true
	end
	for _, b in ipairs(f.buttons) do if inside(b, mx, my) then Stall.setTag(f.stall, b.tag) end end
	if inside(f.close, mx, my) then
		Stall.close(u, f.k, game); game:toast("STALL CLOSED: STOCK MOVED TO STORAGE", 2.5)
		return true
	end
	local hold = game.player.hold
	for _, row in ipairs(f.rows) do
		local n = inside(row.one, mx, my) and 1 or inside(row.all, mx, my) and row.n or 0
		if n > 0 and hold then
			if row.side == "hold" then Stall.stock(f.stall, hold, row.id, n)
			else
				local moved = Stall.unstock(f.stall, hold, row.id, n)
				if moved < n then game:toast("NO ROOM IN YOUR HOLD", 1.5) end
			end
			game.player.cargo = Hold.totals(hold); game.player.massDirty = true
		end
	end
	return true
end
function View.wheelmoved(game, y) end
return View
