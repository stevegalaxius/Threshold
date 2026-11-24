-- The Manage tab: your business at this station on one screen.
--   panes   Market stall, Buy orders, Industry (production lines, where
--           the station has any: src/ui/industry.lua) and Services (food,
--           water and shore leave: src/ui/services.lua)
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
local Sheet = require("src.ui.shipsheet")
local Paint = require("src.paint")
local Dealers = require("src.dealers")
local View = { pane = "stall", pick = nil, qty = 10, deliver = "storage", catScroll = 0 }
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
	-- each satellite's refuel order button (drawSide's rows)
	f.sats = {}
	local Sat = require("src.satellites")
	local satTop = y + 144 + 104 + 36
	for i, r in ipairs(Sat.mine(u)) do
		f.sats[i] = { r = r, x = x + 340 - 14 - 112, y = satTop + (i - 1) * 46 - 3, w = 112, h = 22 }
	end
	-- the main column's panes: the stall, buy orders, the station's
	-- industry (where it has any) and its services
	local ids = { { "stall", "Market stall" }, { "orders", "Buy orders" }, { "deliveries", "Ship deliveries" } }
	if require("src.ui.industry").has(st) then ids[#ids + 1] = { "industry", "Industry" } end
	if require("src.ui.services").has(st) then ids[#ids + 1] = { "services", "Services" } end
	f.panes = {}
	local step=math.min(140,math.floor((w-352)/#ids))
 for i,p in ipairs(ids) do
  f.panes[i]={id=p[1],label=p[2],x=x+352+(i-1)*step,y=y,w=step-6,h=32}
 end
	local offered = false
	for _, p in ipairs(f.panes) do if p.id == View.pane then offered = true end end
	if not offered then View.pane = "stall" end
	f.main = { x = x + 352, y = y + 40, w = w - 352, h = h - 40 }
	if View.pane == "industry" or View.pane == "services" then f.view = View.pane; return f end
	f.stall = k and Stall.get(u, k)
	local m = f.main
	if View.pane=='orders' or View.pane=='deliveries' then
  f.main.x,f.main.w=x,w
  if View.pane=='deliveries' then return View.deliveryLayout(game,f) end
  return View.ordersLayout(game,f)
 end
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
	local hh = 40 + math.max(1, #mine) * 46
	card(s.x, cy, s.w, hh, ("YOUR SATELLITES · %d of %d"):format(#mine, Sat.playerCap))
	if #mine == 0 then text(s.x + 14, cy + 38, s.w - 28, "None up. Buy a satellite package at a logistics station and use it in orbit.", 12, HUD.DIM) end
	local J = require("src.sat_jobs")
	for i, r in ipairs(mine) do
		local ry = cy + 36 + (i - 1) * 46
		local fuel = Sat.fuel(u, r)
		local F = require("src.fields")[r.field]
		text(s.x + 14, ry, s.w - 140, (F and F.name or r.field) .. " · " .. HUD.credits(r.earned or 0), 13)
		bar(s.x + 14, ry + 22, s.w - 28, 8, fuel, fuel <= 0 and HUD.WARN or fuel < Sat.refuelAt and GOLD or HUD.AQUA)
		-- refuel: send a hauler (a board job), or how that's going
		local b = f.sats[i]
		local o = J.offer(u, "satrefuel", r.id)
		if o and o.owner then text(b.x - 20, b.y + 3, b.w + 20, "Hauler on the way", 11, GOOD, "right")
		elseif o and (o.npcClaimAt or 0) <= (u.clock or 0) then text(b.x - 20, b.y + 3, b.w + 20, "Job posted", 11, GOLD, "right")
		elseif fuel < 0.95 then
			Station.button(b, "Send hauler", false, (u.credits or 0) >= J.pay)
		else text(b.x - 20, b.y + 3, b.w + 20, "Full", 11, HUD.DIM, "right") end
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


-- Buy orders ---------------------------------------------------------------
local Orders = require("src.buy_orders")
local cache = {}
-- (the catalogue and quotes look across every station: worked out every
-- few seconds of game time, not every frame)
local function cached(key, clock, fn)
	local c = cache[key]
	local bucket = math.floor((clock or 0) / 5)
	if c and c.at == bucket then return c.v end
	local v = fn()
	cache[key] = { at = bucket, v = v }
	return v
end
local STATUS = { open = { "On the board", GOLD }, hauling = { "Hauler carrying it", GOOD },
	delivered = { "Delivered", HUD.DIM }, cancelled = { "Cancelled", HUD.DIM } }

local ShipDelivery=require('src.ship_delivery')

function View.deliveryLayout(game,f)
 local m,u=f.main,game.universe
 f.deliveries=true
 f.shipOrder=ShipDelivery.playerOrder(u,f.k)
 local options=cached('ships|'..f.k,u.clock,function() return ShipDelivery.catalogue(u,f.k,u.clock) end)
 local listW=math.min(350,math.floor(m.w*.36))
 f.shipList={x=m.x,y=m.y,w=listW,h=m.h}
 f.shipDetail={x=m.x+listW+12,y=m.y,w=m.w-listW-12,h=m.h}
 local rowH=48
 local visible=math.floor((m.h-40)/rowH)
 View.shipScroll=math.max(0,math.min(View.shipScroll or 0,#options-visible))
 f.shipRows={}
 if f.shipOrder and (f.shipOrder.status=='listed' or f.shipOrder.status=='in transit') then
  f.activeDelivery=f.shipOrder
 end
 for i,offer in ipairs(options) do
  if offer.hull==View.shipPick then f.shipQuote=offer end
  local index=i-View.shipScroll
  if index>=1 and index<=visible then
   f.shipRows[#f.shipRows+1]={offer=offer,x=m.x+8,y=m.y+34+(index-1)*rowH,w=listW-16,h=rowH-4}
  end
 end
 if not f.shipQuote then f.shipQuote=f.shipRows[1] and f.shipRows[1].offer end
 local detail=f.shipDetail
 f.shipAction={x=detail.x+14,y=detail.y+detail.h-45,w=detail.w-28,h=31}
 return f
end

function View.ordersLayout(game, f)
	local u, m = game.universe, f.main
	local clock = u.clock or 0
 f.orders=true
	f.cat = cached("cat|" .. tostring(f.k), clock, function() return Orders.catalogue(u, f.k, clock) end)
	local half = math.floor((m.w - 48) / 2)
	f.left, f.right = { x = m.x + 16, y = m.y + 36, w = half }, { x = m.x + 32 + half, y = m.y + 36, w = half }
	-- item tiles
	local T2, G2 = 48, 6
	local cols = math.max(1, math.floor((half + G2) / (T2 + G2)))
	local rows = math.max(1, math.floor((m.h - 248)/(T2+G2)))
	local maxScroll = math.max(0, math.ceil(#f.cat / cols) - rows)
	View.catScroll = math.max(0, math.min(View.catScroll, maxScroll))
	f.picks = {}
	for i = 1, cols * rows do
		local id = f.cat[i + View.catScroll * cols]
		if not id then break end
		local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
		f.picks[#f.picks + 1] = { id = id, x = f.left.x + c * (T2 + G2), y = f.left.y + 24 + r * (T2 + G2), w = T2, h = T2 }
	end
	local by = m.y+m.h-162
	f.formY = by
	f.steps = {}
	for i, d in ipairs({ -10, -1, 1, 10 }) do
		local bx = f.left.x + (i <= 2 and (i - 1) * 46 or 150 + (i - 3) * 46)
		f.steps[i] = { d = d, label = (d > 0 and "+" or "") .. d, x = bx, y = by, w = 40, h = 28 }
	end
	f.dest = { { id = "storage", label = "To storage", x = f.left.x, y = by + 38, w = 120, h = 28 },
		{ id = "stall", label = "To my stall", x = f.left.x + 126, y = by + 38, w = 120, h = 28 } }
	f.post = { x = f.left.x, y = by + 118, w = 180, h = 34 }
	-- the quote for what's picked
	if View.pick then
		f.quote = cached(("q|%s|%s|%d"):format(tostring(f.k), View.pick, View.qty), clock, function()
			local src = Orders.source(u, View.pick, View.qty, f.k, clock)
			if not src then return false end
			local n = math.min(View.qty, src.have)
			local unit, goods, freight = Orders.quote(u, View.pick, n, src.id, f.k, clock)
			return { src = src.id, n = n, unit = unit, goods = goods, freight = freight }
		end)
	end
	-- your orders
	f.rows = {}
	for i, o in ipairs(Orders.list(u)) do
		local ry = f.right.y + 24 + (i - 1) * 52
		if ry + 48 > m.y + m.h then break end
		f.rows[#f.rows + 1] = { o = o, y = ry, cancel = { x = f.right.x + f.right.w - 90, y = ry + 10, w = 84, h = 26 } }
	end
	return f
end

local function drawOrders(game, f, mx, my)
	local u, m = game.universe, f.main
	card(m.x, m.y, m.w, m.h, ("BUY ORDERS · %d of %d open · NPC haulers bring the goods here from wherever they're spare"):format(#Orders.open(u), Orders.max))
	text(f.left.x, f.left.y, f.left.w, "NEW ORDER · pick a good", 12, GOLD)
	for _, t in ipairs(f.picks) do
		local hot, sel = inside(t, mx, my), View.pick == t.id
		lg.setColor(1, 1, 1, (hot or sel) and 0.14 or 0.05); lg.rectangle("fill", t.x, t.y, t.w, t.h, 5, 5)
		lg.setColor(sel and GOLD or HUD.DIM); lg.rectangle("line", t.x + 0.5, t.y + 0.5, t.w - 1, t.h - 1, 5, 5)
		if not Icons.drawInRect(t.id, t.x + 4, t.y + 4, t.w - 8, t.h - 8, nil, 1, 3) then
			text(t.x + 2, t.y + 16, t.w - 4, itemName(t.id), 9, HUD.DIM, "center")
		end
	end
	if #f.picks == 0 then text(f.left.x, f.left.y + 30, f.left.w, "Nothing to spare anywhere right now.", 13, HUD.DIM) end
	local hover
	for _, t in ipairs(f.picks) do if inside(t, mx, my) then hover = t.id end end
	local name = hover or View.pick
	text(f.left.x, f.formY - 24, f.left.w, name and (itemName(name) .. " · list " .. HUD.credits(Stall.list(name))) or "Mouse wheel scrolls the goods.", 13, name and HUD.INK or HUD.DIM)
	for _, b in ipairs(f.steps) do Station.button(b, b.label, false, View.pick ~= nil) end
	text(f.left.x + 92, f.formY + 5, 58, tostring(View.qty), 16, HUD.INK, "center")
	local hasStall = Stall.get(u, f.k) ~= nil
	if View.deliver == "stall" and not hasStall then View.deliver = "storage" end
	for _, b in ipairs(f.dest) do Station.button(b, b.label, View.deliver == b.id, b.id == "storage" or hasStall) end
	local q = f.quote
	if View.pick and q then
		local place = L.byId[q.src]
		text(f.left.x, f.formY + 74, f.left.w, ("%d from %s%s"):format(q.n, place and place.name or q.src, q.n < View.qty and " (all it has spare)" or ""), 12, HUD.DIM)
		text(f.left.x, f.formY + 94, f.left.w, ("%s each (goods %s + freight %s) · paid now %s"):format(HUD.credits(q.unit),
			HUD.credits(math.floor(q.goods / q.n)), HUD.credits(math.ceil(q.freight / q.n)), HUD.credits(q.unit * q.n)), 12, (u.credits or 0) >= q.unit * q.n and HUD.INK or HUD.WARN)
	elseif View.pick then
		text(f.left.x, f.formY + 74, f.left.w, "No station can send any right now.", 12, HUD.WARN)
	end
	Station.button(f.post, "Post order", false, View.pick ~= nil and q and (u.credits or 0) >= q.unit * q.n)
	-- your orders
	text(f.right.x, f.right.y, f.right.w, "YOUR ORDERS", 12, GOLD)
	if #f.rows == 0 then text(f.right.x, f.right.y + 30, f.right.w, "None yet. Pick a good, set how many and post it: NPC haulers deliver it.", 12, HUD.DIM) end
	for _, row in ipairs(f.rows) do
		local o = row.o
		local st = Orders.status(u, o)
		lg.setColor(1, 1, 1, 0.05); lg.rectangle("fill", f.right.x, row.y, f.right.w, 46, 5, 5)
		Icons.drawInRect(o.item, f.right.x + 4, row.y + 4, 38, 38, nil, 1, 3)
		local to = L.byId[o.target]
		text(f.right.x + 50, row.y + 4, f.right.w - 150, ("%s ×%d%s"):format(itemName(o.item), o.amount, o.delivered > 0 and o.delivered < o.amount and (" (" .. o.delivered .. " in)") or ""), 13)
		text(f.right.x + 50, row.y + 24, f.right.w - 150, ((STATUS[st] or { st })[1]) .. " · to " .. (o.deliver == "stall" and "stall" or "storage") .. " at " .. (to and to.name or o.target), 11, (STATUS[st] or {})[2] or HUD.DIM)
		if st == "open" then Station.button(row.cancel, "Cancel", false, true) end
	end
end

local function drawShipOrders(game,f,mx,my)
 local list,detail=f.shipList,f.shipDetail
 card(list.x,list.y,list.w,list.h,'Ships available for delivery')
 card(detail.x,detail.y,detail.w,detail.h,'Delivery to '..(L.byId[f.k].name or f.k))
 for _,row in ipairs(f.shipRows) do
  local o=row.offer
  local selected=f.shipQuote==o
  local hull=data.hulls[o.hull]
  lg.setColor(1,1,1,selected and .16 or inside(row,mx,my) and .1 or .05)
  lg.rectangle('fill',row.x,row.y,row.w,row.h,4,4)
  local lot=Dealers.find(game.universe,o.source,o.lot)
  local paint=lot and (lot.color or Paint.preset(lot.paint)) or Paint.preset()
  require('src.ui.hangar').drawHull(hull,row.x+5,row.y+4,48,row.h-8,false,paint,1)
  text(row.x+59,row.y+5,row.w-67,hull.name,14,selected and GOLD or HUD.INK)
  text(row.x+59,row.y+23,row.w-67,HUD.credits(o.price+o.fee),12,HUD.DIM)
 end
 if #f.shipRows==0 then text(list.x+14,list.y+43,list.w-28,'No reachable ships available for delivery.',14,HUD.DIM) end
 local x,y,w=detail.x+14,detail.y+40,detail.w-28
 local order=f.activeDelivery
 if order then
  text(x,y,w,data.hulls[order.hull].name,20,HUD.INK)
  text(x,y+32,w,'From '..(L.byId[order.source].name or order.source),13,HUD.DIM)
  text(x,y+55,w,order.status=='listed' and 'Waiting for pickup' or 'In transit with an NPC carrier',14,GOOD)
  text(x,y+83,w,'Paid '..HUD.credits(order.price+order.fee),14,HUD.INK)
  if order.status=='listed' then Station.button(f.shipAction,'Cancel delivery and refund',inside(f.shipAction,mx,my),true) end
  return
 end
 local o=f.shipQuote
 if f.shipOrder and f.shipOrder.status=='delivered' then
  text(x,y,w,data.hulls[f.shipOrder.hull].name..' delivered to Hangar.',13,GOOD)
  y=y+21
 end
 if not o then return end
 local hull=data.hulls[o.hull]
 local lot=Dealers.find(game.universe,o.source,o.lot)
 if not lot then text(x,y,w,'This lot is no longer available.',14,HUD.WARN);return end
 local paint=lot.color or Paint.preset(lot.paint)
 text(x,y,w,hull.name,20,HUD.INK)
 text(x,y+28,w,(lot.trimName or 'Stock')..' · '..(paint.name or '')..' · '..hull.class,13,HUD.DIM)
 local previewW=math.floor(w*.46)
 Sheet.outline(hull,paint,x,y+49,previewW,79)
 local fitX,fitW=x+previewW+16,w-previewW-16
 text(fitX,y+49,fitW,'Equipment',13,GOLD)
 Sheet.slots(hull,lot.loadout,fitX,y+68,fitW,f.shipAction.y-10)
 local source=L.byId[o.source]
 text(x,f.shipAction.y-57,previewW,source.name or o.source,12,HUD.DIM)
 text(x,f.shipAction.y-29,w,'Hull '..HUD.credits(o.price)..'   +   delivery '..HUD.credits(o.fee),13,HUD.INK)
 Station.button(f.shipAction,'Order delivery · '..HUD.credits(o.price+o.fee),
  inside(f.shipAction,mx,my),game.universe.credits>=o.price+o.fee)
end

local function deliveryClick(game,f,mx,my)
 local u=game.universe
 if inside(f.shipAction,mx,my) then
  local order=f.activeDelivery
  local ok,why
  if order and order.status=='listed' then
   ok,why=ShipDelivery.cancelPlayer(u,f.k)
   game:toast(ok and 'SHIP ORDER CANCELED. FUNDS RETURNED' or why,2)
  elseif not order and f.shipQuote and u.credits>=f.shipQuote.price+f.shipQuote.fee then
   ok,why=ShipDelivery.orderPlayer(u,f.shipQuote)
   game:toast(ok and 'SHIP DELIVERY POSTED' or why,2)
  end
  cache={}
  return true
 end
 for _,row in ipairs(f.shipRows) do
  if inside(row,mx,my) then View.shipPick=row.offer.hull;break end
 end
 return true
end

function View.ordersClick(game, f, mx, my, button)
	local u = game.universe
	if button ~= 1 then return true end
	for _, t in ipairs(f.picks) do if inside(t, mx, my) then View.pick = t.id end end
	for _, b in ipairs(f.steps) do if inside(b, mx, my) then View.qty = math.max(1, math.min(500, View.qty + b.d)) end end
	for _, b in ipairs(f.dest) do if inside(b, mx, my) then View.deliver = b.id end end
	if inside(f.post, mx, my) and View.pick then
		local o, why = Orders.place(u, View.pick, View.qty, f.k, View.deliver, u.clock)
		cache = {}
		game:toast(o and ("ORDER POSTED: %d %s"):format(o.amount, itemName(o.item):upper()) or (why or ""):upper(), 2.5)
	end
	for _, row in ipairs(f.rows) do
		if inside(row.cancel, mx, my) and Orders.status(u, row.o) == "open" then
			local ok, why = Orders.cancel(u, row.o)
			cache = {}
			game:toast(ok and "ORDER CANCELLED: REFUNDED" or (why or ""):upper(), 2)
		end
	end
	return true
end

function View.draw(game)
	local f = View.layout(game)
	local u = game.universe
	local mx, my = love.mouse.getPosition()
 if not f.orders and not f.deliveries then drawSide(game,f) end
	for _, p in ipairs(f.panes) do Station.button(p, p.label, View.pane == p.id, true) end
 if f.deliveries then drawShipOrders(game,f,mx,my);return end
 if f.orders then drawOrders(game,f,mx,my);return end
	local m = f.main
	if f.view then
		require(f.view == "industry" and "src.ui.industry" or "src.ui.services").draw(game, mx, my, m.x, m.y, m.w, m.h)
		return
	end
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
	-- satellites: send a hauler to refuel one
	if button == 1 then
		for _, b in ipairs((f.orders or f.deliveries) and {} or f.sats) do
			if inside(b, mx, my) then
				local J = require("src.sat_jobs")
				if not J.offer(u, "satrefuel", b.r.id) or (J.offer(u, "satrefuel", b.r.id).npcClaimAt or 0) > (u.clock or 0) then
					local ok, why = require("src.satellites").orderRefuel(u, b.r.id)
					game:toast(ok and ("REFUEL JOB POSTED: " .. HUD.credits(J.pay) .. " WHEN IT'S DONE") or (why or ""):upper(), 2.5)
				end
				return true
			end
		end
		for _, p in ipairs(f.panes) do if inside(p, mx, my) then View.pane = p.id; return true end end
	end
	if f.deliveries then return button~=1 or deliveryClick(game,f,mx,my) end
 if f.orders then return View.ordersClick(game, f, mx, my, button) end
	if f.view then return true end
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
function View.wheelmoved(game, y)
 if View.pane=='orders' then View.catScroll=View.catScroll-y end
 if View.pane=='deliveries' then View.shipScroll=(View.shipScroll or 0)-y end
	if View.pane == "industry" then require("src.ui.industry").wheelmoved(game, y) end
end
return View
