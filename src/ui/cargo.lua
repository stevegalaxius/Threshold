--[[
	The cargo screen: your hold's grids, laid out so you can move things by
	hand. Two ways in:

	  docked    opens by itself, with three tabs (Tab cycles): Cargo, your
	            hold next to this station's storage, plus a parked ship's
	            hold after it if you open one (Ships / Next / x); Hangar
	            (src/ui/hangar.lua); and Market. E, Enter or (A) launches.
	  market    your hold and storage, one shared trade grid, and the
	            station's shelf. Both sides put goods on the trade grid
	            (each stack keeps owner = "player" or "station"), and
	            Complete trade settles it (src/market.lua). Leave the tab
	            and everything on it goes home.
	  in space  Tab opens and closes it (Esc closes too). Just your hold.
	            The game keeps running, and you can still fly with the keys.
	  looting   a tap of E on a wreck or container in range opens it next
	            to your hold. Take All or Ctrl-click takes (or the right-click menu);
	            your tractor beam tries to keep it in reach, and the
	            window closes if it slips out of range anyway.

	A loaded cargo container in any hold (a Hauler's wreck packs its cargo
	in them) opens with a double-click as one more panel. A ship with room
	can move the whole container across instead.

	Mouse:
	  drag            pick up a stack and drop it somewhere else; dropping
	                  on a part-full stack of the same item tops it up
	  R (dragging)    rotate
	  Shift-drag      take half the stack
	  Ctrl-click      quick move to the other side (docked)
	  double-click    open a container, fit a module (docked), use a
	                  usable item, or else quick move like Ctrl-click
	  right-click     a menu of what you can do with the stack: use it
	                  (src/item_use.lua), open, fit, move/take across,
	                  split, eject one or all (in space)
	  drop outside    in space: eject it
	  Sort            tidy a hold (biggest items first, grouped by type)

	Anything you're holding when the screen closes goes back where it came
	from.
]]

local data = require("src.data")
local ShipEntry=require('src.inventory.ship_entry')
local function itemFor(id) return data.items[id] or ShipEntry.item(id) end
local Ship = require("src.ship")

-- The ammo the weapon in slot i can load, when there's a choice (else nil).
local function ammoList(p, i)
	local m = p.loadout[i] and data.modules[p.loadout[i]]
	local opts = m and data.ammoOptions(m)
	return opts and #opts > 0 and opts or nil
end

local function loadOptions(p, i)
	local m = p.loadout[i] and data.modules[p.loadout[i]]
	local opts = m and data.ammoOptions(m)
	return opts and #opts > 1 and opts or nil
end
local Grid = require("src.inventory.grid")
local Hold = require("src.inventory.hold")
local ItemUse = require("src.item_use")
local Shapes = require("src.inventory.shapes")
local HullShape = require("src.hullshape")
local HUD = require("src.hud")
local Sheet = require("src.ui.shipsheet")
local Game = require("src.game")
local Hangar = require("src.ui.hangar")
local Shipyard = require("src.ui.shipyard")
local IndustryView = require("src.ui.industry")
local Contracts = require("src.ui.contracts")
local Repair = require("src.ui.repair")
local Station=require("src.ui.station")
local stats = require("src.stats")
local T = require("src.tuning")

local Cargo = { open = false, loot = nil, tab = "cargo", other = nil, filter = "all", marketLeft = "hold" }

local function trading() return Cargo.tab=='market' end

local lg = love.graphics
local floor, max, min = math.floor, math.max, math.min

local GAP, PAD, HEAD = 16, 14, 40
local tabRects, drawTabs, sendHome, drawTrade, targetKey

-- Is the screen up?
function Cargo.isOpen(game)
	if game.state == "docked" then return true end
	return Cargo.open and game.player and not game.player.dead
end

-- The market's trade grid: lives only while the market tab is up.
local function tradeHold()
	if not Cargo.trade then
		Cargo.trade = Hold.new({
   {key='sell',name='You give',w=T.tradeW,h=T.tradeH},
   {key='buy',name='You receive',w=T.tradeW,h=T.tradeH},
  })
  Cargo.trade.grids[1].tradeOwner='player';Cargo.trade.grids[2].tradeOwner='station'
	end
	return Cargo.trade
end

-- The holds on show: { title, hold, ship (if it's a ship's hold) }.
local function sides(game)
	local p = game.player
	if not p or p.dead or not p.hold then return {} end
	local list = { { title = "Your hold \194\183 " .. p.hull.name, hold = p.hold, ship = p } }
	if game.state == "docked" and p.dockState then
		-- station storage, then a parked ship's hold if one is open (Cargo.other)
		local st = p.dockState.station
		table.insert(list, { title = "Station storage", hold = game:stationStorage(st), storage = true, station = st })
		if trading() then
			-- the market: your hold or storage (one at a time, picked with the
			-- panel's own tabs), the trade grid, then the station's shelf
			if Cargo.marketLeft == "storage" then table.remove(list, 1) else table.remove(list, 2) end
   list[1].pick = true
			Cargo.tradeStation = st
			table.insert(list, { title = "Trade", hold = tradeHold(), trade = true, station = st })
			table.insert(list, { title = st.name, hold = game:stationMarket(st).hold, market = true, station = st })
			return list
		end
		local rec = Cargo.other
		local parked = false
		for _, r in ipairs(game:hangar(st)) do if r == rec and r.hold then parked = true end end
		if parked then
			table.insert(list, { title = "Parked " .. data.hulls[rec.hull].name, hold = rec.hold, parked = rec, station = st })
		else
			Cargo.other = nil
		end
	elseif Cargo.loot then
		local e = Cargo.loot
		local title = e.kind == "husk" and "Wreck" or "Container"
		local o = e.origin
		if o then
			-- e.g. "Wreck · Freighter (Ferrous Freighter) · trader npc/47"
			title = title .. " \194\183 " .. (o.type and (o.type .. (o.hull and o.hull ~= o.type and " (" .. o.hull .. ")" or "")) or o.hull or "?")
			if o.npc then title = title .. " \194\183 " .. (o.role and (o.role .. " ") or "") .. o.npc end
		elseif e.kind == "husk" and e.hull and e.hull.name then
			title = title .. " \194\183 " .. e.hull.name
		end
		table.insert(list, { title = title, hold = e.hold, entity = e })
	end
	-- an opened container, if it's still in one of the holds on show
	-- (Cargo.inner is the container's own hold: the stack table holding it
	-- changes whenever it's picked up and put down)
	local c = Cargo.inner
	if c then
		local parent
		for _, side in ipairs(list) do
			for _, g in ipairs(side.hold.grids) do
				for _, st in ipairs(g.stacks) do if st.inner == c then parent = side end end
			end
		end
		-- Picking up the open container must not remove its panel and resize
  -- every grid beneath the cursor. Keep the same parent while it is held.
  if not parent and Cargo.hand and Cargo.hand.inner==c then
   for _,side in ipairs(list) do
    if side.hold==Cargo.hand.side.hold then parent=side;break end
   end
  end
		if parent then
			table.insert(list, { title = "Container", hold = c, innerOf = c, parent = parent })
		elseif not (Cargo.hand and Cargo.hand.inner == c) then
			Cargo.inner = nil
		end
	end
	return list
end

local function stockMatch(stack)
 local item=itemFor(stack.id)
 local query=(Cargo.search or ''):lower()
 return query=='' or (item.name..' '..(item.maker or '')):lower():find(query,1,true)~=nil
end

-- Where everything sits on screen: the equipment panel on the left, then
-- each hold. A side's main grid is on top, any further grids (Cargo Pods)
-- in a row underneath. One cell size for every grid, as big as fits.
local EW, ROW, HULL_H = 260, 30, 110

-- The market shelf's filters: which stacks stand out.
local FILTERS = {
	{ id = "all", label = "All" }, { id = "ammo", label = "Ammo" }, { id = "weapons", label = "Weapons" },
	{ id = "modules", label = "Modules" }, { id = "misc", label = "Misc" },
}
local function filterOf(id)
	local item, m = itemFor(id), data.modules[id]
 if item.kind=="ship" then return "ships" end
	if item.kind == "ammo" then return "ammo" end
	if m then return m.family == "weapon" and "weapons" or "modules" end
	return "misc"
end

local function layout(game)
	local sw, sh = lg.getDimensions()
	local list = sides(game)
	if #list == 0 then return nil end
	local p = game.player
	-- in space the equipment panel is only a readout; with three holds up
	-- it makes way for them
	local showEquip = #list<3
	local eh = showEquip and (HEAD + HULL_H + #p.hull.slots * ROW + PAD) or 0
	local function size(side, cs)
		local g1 = side.hold.grids[1]
		local w, rowW, rowH = g1.w * cs, 0, 0
		for i = 2, #side.hold.grids do
			local g = side.hold.grids[i]
			if side.trade then rowW=max(rowW,g.w*cs);rowH=rowH+g.h*cs+(i>2 and 24 or 0)
   else rowW = rowW + (i > 2 and GAP or 0) + g.w * cs;rowH = max(rowH, g.h * cs) end
		end
		local h = 18 + g1.h * cs + (rowH > 0 and (24 + rowH) or 0) + (side.trade and 194 or 0)
  do
   local header=(side.pick or side.market) and (side.market and 142 or 98) or side.trade and 70 or 58
   h=g1.h*cs+(rowH>0 and (24+rowH) or 0)+header+(side.trade and 194 or 14)-HEAD-PAD*2
  end
		return max(w, rowW, (side.innerOf or side.parked) and 380 or side.market and 360 or (side.entity or side.station) and 340 or 300), h
	end
	-- Panels stand in columns, one each, except at the market, where storage
	-- sits under your hold.
	local cols = {}
	for _, side in ipairs(list) do
		if side.storage and trading() and #cols > 0 then table.insert(cols[#cols], side)
		else table.insert(cols, { side }) end
	end
	local STACKED = HEAD + PAD * 2 + GAP          -- what a panel under another adds besides its own height
	local function column(col, cs)
		local cw, ch = 0, 0
		for k, side in ipairs(col) do
			local w, h = size(side, cs)
			cw, ch = max(cw, w), ch + h + (k > 1 and STACKED or 0)
		end
		return cw, ch
	end
	local function measure(cs)
		local tw, th = showEquip and (EW + GAP) or 0, 0
		for i, col in ipairs(cols) do
			local w, h = column(col, cs)
			tw, th = tw + w + PAD * 2 + (i > 1 and GAP or 0), max(th, h)
		end
		return tw, max(th + HEAD + PAD * 2, eh)
	end
	local cs = Station.CELL
	while cs > 6 do
		local tw, ph = measure(cs)
		if tw <= Station.frameW() and ph <= select(4, Station.body()) then break end
		cs = cs - 1
	end

	local L = { cs = cs, sides = list, grids = {} }
	local tw, ph = measure(cs)
	ph = max(ph, select(4, Station.body()))   -- panels reach the footer, like every tab
	for _, side in ipairs(list) do side.w, side.h = size(side, cs) end
	local x = floor((sw - tw) / 2)
	local y = Station.BODY_Y

	-- Equipment: the hull outline with numbered hardpoints, then a row per slot.
	local equipmentWidth=EW
	local E = { x = x, y = y, pw = equipmentWidth, ph = ph, slots = {}, hidden = not showEquip }
	E.hull = { x = x + PAD, y = y + HEAD, w = equipmentWidth - PAD * 2, h = HULL_H - 16 }
	if showEquip then
		for i, slot in ipairs(p.hull.slots) do
			local r = { i = i, slot = slot, x = x + PAD, y = y + HEAD + HULL_H + (i - 1) * ROW, w = equipmentWidth - PAD * 2, h = ROW - 4 }
			-- weapon slots get a button that picks which trigger fires them
			if slot.family == "hardpoint" or slot.family == "bay" then
				r.trig = { x = r.x + r.w - 46, y = r.y + 4, w = 40, h = r.h - 8 }
				-- and one that picks which ammo it loads
				r.load = { x = r.trig.x - 96, y = r.y + 4, w = 92, h = r.h - 8 }
			end
			table.insert(E.slots, r)
		end
		x = x + EW + GAP
	else
		E.pw, E.ph = 0, 0
	end
	L.equip = E

	for _,col in ipairs(cols) do
		local cw=column(col,cs)
		local cy = y
		for k, side in ipairs(col) do
			side.x, side.y, side.pw = x, cy, cw + PAD * 2
			side.ph = k < #col and (side.h + HEAD + PAD * 2) or (y + ph - cy)
			cy = cy + side.ph + GAP
		end
		x = x + cw + PAD * 2 + GAP
	end
	for _, side in ipairs(list) do
		local x, y = side.x, side.y
		side.sort = { x = x + side.pw - PAD - 56, y = y + 12, w = 56, h = 22 }
		if side.trade or side.market or side.shipEntries then side.sort = nil end
		if side.trade then
			local by=y+side.ph
   side.complete={x=x+PAD,y=by-54,w=side.pw-PAD*2-108,h=32}
   side.clear={x=x+side.pw-PAD-100,y=by-54,w=100,h=32}
		end
		if side.pick then
			-- the market's left panel: Hold / Storage tabs in place of the title
			side.picks = {
				{ id = "hold", label = "Ship hold", x = x + PAD, y = y + 48, w = 96, h = 24 },
				{ id = "storage", label = "Station storage", x = x + PAD + 100, y = y + 48, w = 124, h = 24 },
			}
		end
		if side.market then
			-- filter buttons along the grid's label row
			side.filters = {}
			-- the station's shops: a dropdown (the menu opens below it)
			local shops = Game.marketShops(side.station)
			side.shopMenu = { x = x + PAD, y = y + 44, w = side.pw - PAD * 2, h = 28 }
			side.shops = {}
			for i, shop in ipairs(shops) do
				table.insert(side.shops, { i = i, label = shop.name, desc = shop.description,
					x = side.shopMenu.x, y = side.shopMenu.y + side.shopMenu.h + 2 + (i - 1) * 44, w = side.shopMenu.w, h = 42 })
			end
			local fx = x + PAD
			for _, f in ipairs(FILTERS) do
				local fw = HUD.font(11):getWidth(f.label) + 12
				table.insert(side.filters, { id = f.id, label = f.label, x = fx, y = y + 100, w = fw, h = 20 })
				fx = fx + fw + 4
			end
		end
		if side.entity or side.innerOf then side.take = { x = side.sort.x - 82, y = y + 12, w = 76, h = 22 } end
		if side.innerOf then side.close = { x = side.take.x - 28, y = y + 12, w = 22, h = 22 } end
		-- storage: open a parked ship's hold; a parked ship: the next one, or close
		if (side.parked or (side.storage and not Cargo.other and Cargo.tab ~= "market")) and #game:hangar(side.station) > 0 then
			side.switch = { x = side.sort.x - 70, y = y + 12, w = 64, h = 22, label = side.parked and "Next" or "Ships" }
		end
		if side.parked then side.close = { x = side.switch.x - 28, y = y + 12, w = 22, h = 22 } end
		-- with a parked ship open: which panel right-click sends things to
		if targetKey(side) and Cargo.other and Cargo.tab == "cargo" then
			side.target = { x = x + side.pw - PAD - 64, y = y + HEAD - 2, w = 64, h = 17 }
		end
		local gx, gy = x+PAD,y+((side.pick or side.market) and (side.market and 142 or 98) or side.trade and 70 or 58)
		local g1 = side.hold.grids[1]
		table.insert(L.grids, { side = side, g = g1, x = gx, y = gy, label = g1.name })
		local rx, ry = gx, gy + g1.h * cs + 24
		for i = 2, #side.hold.grids do
			local g = side.hold.grids[i]
			table.insert(L.grids, { side = side, g = g, x = rx, y = ry, label = g.name })
			if side.trade then ry=ry+g.h*cs+24 else rx = rx + g.w * cs + GAP end
		end
	end
	L.bottom = y + ph
	return L
end

-- The panels right-click can target: "hold", "storage" or "parked".
function targetKey(side)
	return side.ship and "hold" or side.storage and "storage" or side.parked and "parked" or nil
end

-- Which grid cell is under a screen point.
local function cellAt(L, mx, my)
	for _, r in ipairs(L.grids) do
		local cx, cy = floor((mx - r.x) / L.cs), floor((my - r.y) / L.cs)
		if cx >= 0 and cy >= 0 and cx < r.g.w and cy < r.g.h then return r, cx, cy end
	end
end

local function overPanel(L, mx, my)
	local E = L.equip
	if mx >= E.x and mx < E.x + E.pw and my >= E.y and my < E.y + E.ph then return E end
	for _, side in ipairs(L.sides) do
		if mx >= side.x and mx < side.x + side.pw and my >= side.y and my < side.y + side.ph then return side end
	end
end

-- After any change to a ship's hold: the cargo counts, mass and HUD follow.
local changed
function changed(side)
	if side and side.ship then
		side.ship.cargo = Hold.totals(side.ship.hold)    -- a refit can swap the hold table
		Ship.updateMass(side.ship)
	elseif side and side.entity then
		side.entity.loot = Hold.totals(side.hold)
		side.entity.massDirty = true                     -- the game reweighs containers
	elseif side and side.parent then
		changed(side.parent)                             -- what a container holds weighs on its hold
	end
end

-- Move a whole stack into a hold; returns how many went in. A loaded
-- container goes as itself (the same stack, so its cargo comes along).
local function moveInto(hold, s)
	if s.inner then
		local copy = { id = s.id, n = s.n, inner = s.inner }
		return Hold.placeStack(hold, copy) and s.n or 0
	end
	return Hold.add(hold, s.id, s.n)
end

local function sideOf(L, hold)
	for _, side in ipairs(L.sides) do
		if side.hold == hold then return side end
	end
end

-- Market ---------------------------------------------------------------------

-- A stack off the trade grid goes back to whoever put it there: the
-- station's to its shelf, yours to your hold or else storage. Nothing is
-- ever lost: if there's truly no room, the grid grows a row.
function sendHome(game, s)
 if ShipEntry.item(s.id) then
  local home=s.owner=='station' and Cargo.shipStock or Cargo.shipOwned
  if home then
   while not Hold.placeStack(home,s) do Grid.addRows(home.grids[1],1) end
  end
  return
 end
	local st = Cargo.tradeStation
	if not st then return end
	if s.owner == "station" then
		local shelf = game:stationMarket(st).hold
		local c = { id = s.id, n = s.n, inner = s.inner, shipRecord=s.shipRecord, resale = s.resale, wear = s.wear }
		while not Hold.placeStack(shelf, c) do Grid.addRows(shelf.grids[1], 1) end
		return
	end
	local p = game.player
	local left = s.n
	if p and not p.dead and p.hold then left = left - moveInto(p.hold, s) end
	local storage = game:stationStorage(st)
	while left > 0 do
		left = left - moveInto(storage, { id = s.id, n = left, inner = s.inner })
		if left > 0 then Grid.addRows(storage.grids[1], 1) end
	end
	if p and p.hold then changed({ ship = p }) end
end

-- Everything on the trade grid goes home (leaving the market tab, undocking,
-- saving).
function Cargo.clearTrade(game)
	local t = Cargo.trade
	if not t then return end
	for _, g in ipairs(t.grids) do
		for i = #g.stacks, 1, -1 do
			local s = g.stacks[i]
			Grid.remove(g, s)
			sendHome(game, s)
		end
	end
end

-- What of the station's stock is out on the trade grid: { id = n }.
local function stockOut()
	local out = {}
	for _, g in ipairs(Cargo.trade and Cargo.trade.grids or {}) do
		for _, s in ipairs(g.stacks) do
			if s.owner == "station" and not s.resale and not ShipEntry.item(s.id) then out[s.id] = (out[s.id] or 0) + s.n end
		end
	end
	return out
end

-- Put a stack on the trade grid; true if there was room.
local function toTrade(L, r, s)
	local trade
	for _, side in ipairs(L.sides) do if side.trade then trade = side end end
	-- the station's shelf stacks without limit: take one ordinary stack off it
	local _, _, cap = Shapes.of(s.id)
	local n = r.side.market and min(s.n, cap) or s.n
	local c = { id = s.id, n = n, inner = s.inner, shipRecord=s.shipRecord, resale = s.resale, wear = s.wear, owner = r.side.market and "station" or "player" }
	local grid=trade.hold.grids[c.owner=='station' and 2 or 1]
 if not Hold.placeStack({grids={grid}},c) then return false end
	if n < s.n then s.n = s.n - n else Grid.remove(r.g, s) end
	changed(r.side)
	return true
end

-- Put what's in hand back where it came from. If its spot has been taken
-- meanwhile (you reeled something in) and the hold is full, the rest floats
-- out behind the ship, or at a station goes into storage.
local function returnHand(game)
	local h = Cargo.hand
	if not h then return end
	Cargo.hand = nil
	local f = h.from
	if f.slot then
		local p = game.player
		p.loadout[f.slot] = h.id
		Ship.refit(p)
		return
	end
	if f.stack and f.stack.n > 0 then
		local still = false
		for _, s in ipairs(f.grid.stacks) do if s == f.stack then still = true end end
		if still then f.stack.n = f.stack.n + h.n; return end
	end
	local fw, fh = h.w0, h.h0
	if Grid.isFree(f.grid, f.x, f.y, fw, fh) then
		Grid.place(f.grid, { id = h.id, n = h.n, x = f.x, y = f.y, w = fw, h = fh, rot = h.rot0, inner = h.inner, shipRecord=h.shipRecord,
			owner = h.side.trade and h.owner or nil, resale = h.resale, wear = h.wear })
		return
	end
	if h.side.trade or h.side.market then sendHome(game, h) return end
	local hold = (h.side and h.side.ship) and h.side.ship.hold or f.hold
	local left = h.n - moveInto(hold, h)
	local p = game.player
	if left > 0 and p and p.dockState and p.dockState.done then
		left = left - moveInto(game:stationStorage(p.dockState.station), { id = h.id, n = left, inner = h.inner })
	end
	if left > 0 and p and not p.dead then game:eject(p, h.id, left, h.inner) end
end

local function finish(game, L)
	local fromSide = Cargo.hand and Cargo.hand.side
	returnHand(game)
	if L then
		for _, side in ipairs(L.sides) do changed(side) end
	elseif fromSide then
		changed(fromSide)
	end
end

function Cargo.toggle(game)
	if game.state == "docked" then return end
	if Cargo.open then Cargo.close(game) else Cargo.open = true end
end

function Cargo.close(game)
	Cargo.menu = nil
	finish(game, layout(game))
	Cargo.open, Cargo.loot = false, nil
end

-- Open a wreck or container next to your hold.
function Cargo.openLoot(game, e)
	if Cargo.hand then finish(game, layout(game)) end
	Cargo.open, Cargo.loot = true, e
end

-- Is the thing being looted still there and in reach?
local function lootInReach(game)
	local e, p = Cargo.loot, game.player
	if not e or e.removed or e.dead or not p or p.dead or game.state == "docked" then return false end
	local x, y = e.body:getPosition()
	return Ship.distanceTo(p, x, y) - e.radius < Ship.tractorRange(p) * 1.3
end

-- Called every frame: tidy up if the screen went away under us (undocked,
-- died) while something was in hand.
function Cargo.update(game)
	if game.openLoot then
		Cargo.openLoot(game, game.openLoot)
		game.openLoot = nil
	end
	if Cargo.loot and not lootInReach(game) then
		local h, p = Cargo.hand, game.player
		if h and h.side.entity and Cargo.loot.removed and p and p.hold then
			-- it blew up while you held something from it: that goes to your hold
			h.from = { grid = p.hold.grids[1], hold = p.hold, x = -1, y = -1 }
		end
		local docked = game.state == "docked"
		if not docked and Cargo.loot.removed then game:toast("IT'S GONE", 1.2) end
		if docked then finish(game, nil); Cargo.loot = nil else Cargo.close(game) end
	end
	game.looting = Cargo.loot      -- the tractor beam holds it in reach (Game:updateLootHold)
	if Cargo.hand and not Cargo.isOpen(game) then
		local h = Cargo.hand
		returnHand(game)
		changed(h.side)
	end
	if game.state == "dead" then Cargo.open = false end
	local p = game.player
	local st = game.state == "docked" and p and p.dockState and p.dockState.station
	if st and trading() then
		game:marketTick(st, stockOut())
	elseif Cargo.trade and not Cargo.hand then
		Cargo.clearTrade(game)
	end
end

-- Mouse ------------------------------------------------------------------

local function inRect(r, x, y)
	return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

-- The station screen's tabs: folder tabs on top of the window, centred
-- over it. The window is the panels of whichever tab is showing.
local TABS={{id='cargo',label='Storage'},{id='contracts',label='Contracts'},{id='market',label='Market'},{id='shipyard',label='Shipyard'},{id='hangar',label='Hangar'},{id='repair',label='Repair'},{id='industry',label='Industry'}}
-- The tabs this station offers: Storage, then its services (Game.stationServices).
local function offered(game)
 local p=game.player;local st=p and p.dockState and p.dockState.station
 local have=Game.stationServices(st);local out={}
 for _,t in ipairs(TABS) do if t.id=='cargo' or t.id=='contracts' or have[t.id] or t.id=='industry' and IndustryView.has(st) then out[#out+1]=t end end
 return out
end
-- Leave a tab this station doesn't offer (after docking somewhere else).
local function checkTab(game)
 if game.state~='docked' or Cargo.hand then return end
 for _,t in ipairs(offered(game)) do if t.id==Cargo.tab then return end end
 Cargo.setTab(game,'cargo')
end
function Cargo.setTab(game,id)
 Cargo.shopOpen=false
 if Cargo.hand then return false end
 local ok=false;for _,t in ipairs(offered(game)) do if t.id==id then ok=true end end
 if not ok then return false end
 if trading() and id~=Cargo.tab then Cargo.clearTrade(game) end
 Cargo.searchFocus=false
 if id~=Cargo.tab then
  Cargo.search='';Cargo.shipOwned=nil;Cargo.shipStation=nil
  if id=='market' then
   if Cargo.marketLeft=='ships' then Cargo.marketLeft='hold' end
   for _,g in ipairs(tradeHold().grids) do if #g.stacks==0 then g.w,g.h,g.cells=T.tradeW,T.tradeH,{} end end
  end
  Cargo.filter='all'
 end
 Cargo.tab=id;Hangar.cancel();Shipyard.cancel();if id=='hangar' then Hangar.focus(game) end;return true
end
function Cargo.workspace(game)
 local fx,fw=Station.frame()
 if Cargo.tab=='hangar' or Cargo.tab=='shipyard' or Cargo.tab=='repair' or Cargo.tab=='industry' then
  local _,by,_,bh=Station.body();return {x=fx,w=fw,bottom=by+bh}
 end
 local _,by,_,bh=Station.body()
 return {x=fx,w=fw,bottom=by+bh}
end
function tabRects(game)
 local frame=Cargo.workspace(game);local out={}
 local tabs=offered(game);local step=math.min(120,(frame.w-28)/#tabs)
 for i,t in ipairs(tabs) do out[i]={id=t.id,label=t.label,x=frame.x+14+(i-1)*step,y=66,w=step-8,h=28} end
 return out
end

-- In flight the inventory has its own tabs (Inventory, Reputation, Contracts), shown
-- while nothing is open next to your hold. More screens go in SPACE_TABS.
local SPACE_TABS={{id='hold',label='Inventory'},{id='reputation',label='Reputation'},{id='contracts',label='Contracts'}}
Cargo.spaceTab='hold'
local function spaceTabs(game)
 if game.state=='docked' or Cargo.other or Cargo.loot then return nil end
 -- same frame and tab row as the station screen
 local fx,fw=Station.frame()
 local out={}
 for i,t in ipairs(SPACE_TABS) do out[i]={id=t.id,label=t.label,x=fx+14+(i-1)*120,y=66,w=112,h=28} end
 return out,{x=fx,y=Station.BODY_Y,w=fw}
end
Cargo.spaceTabs=spaceTabs

local function playerSideOf(L)
	for _, side in ipairs(L.sides) do
		if side.ship then return side end
	end
end

-- Ctrl-click: send a stack to the other side.
local function quickMove(game, L, r, s)
	-- a parked ship's hold is open: right-click / Ctrl-click sends to the
	-- target panel (Cargo.target; the parked ship to start with), and from
	-- the target to your hold (or from your hold to storage)
	local from = targetKey(r.side)
	if from and r.side.target then
		local tgt = Cargo.target or "parked"
		local want = from ~= tgt and tgt or (tgt == "hold" and "storage" or "hold")
		for _, sd in ipairs(L.sides) do
			if targetKey(sd) == want then
				local k = moveInto(sd.hold, s)
				if k == 0 then game:toast("NO ROOM", 1) return end
				s.n = s.n - k
				if s.n <= 0 then Grid.remove(r.g, s) end
				changed(r.side); changed(sd)
				return
			end
		end
	end
	if trading() and game.state == "docked" then
		if r.side.trade then
			Grid.remove(r.g, s)
			sendHome(game, s)
		elseif not toTrade(L, r, s) then
			game:toast("THE TRADE GRID IS FULL", 1.2)
		end
		return
	end
	-- from your hold to the last panel (an open container, the wreck or
	-- storage); from anywhere else to your hold
	local other = r.side.ship and L.sides[#L.sides] or playerSideOf(L)
	if not other or other == r.side then return end
	if s.inner == other.hold then return end            -- not into itself
	local k = moveInto(other.hold, s)
	if k == 0 then game:toast("NO ROOM", 1) return end
	s.n = s.n - k
	if s.n <= 0 then Grid.remove(r.g, s) end
	changed(r.side); changed(other)
end

-- Take All: everything that fits goes into your hold.
local function takeAll(game, L, side)
	local mine = playerSideOf(L)
	if not mine then return end
	local full = false
	for _, g in ipairs(side.hold.grids) do
		for i = #g.stacks, 1, -1 do
			local s = g.stacks[i]
			local k = moveInto(mine.hold, s)
			s.n = s.n - k
			if s.n <= 0 then Grid.remove(g, s) else full = true end
		end
	end
	if full then game:toast("HOLD FULL", 1.2) end
	changed(side); changed(mine)
end


-- Equipment ------------------------------------------------------------------

local function slotAt(L, mx, my)
	for _, r in ipairs(L.equip.slots) do
		if inRect(r, mx, my) then return r end
		-- or its marker on the hull outline
		if r.mx and (r.mx - mx) ^ 2 + (r.my - my) ^ 2 <= 81 then return r end
	end
end

-- A Cargo Pod with something in its grid can't come out.
local function podBusy(p, i)
	for _, g in ipairs(p.hold.grids) do
		if g.key == "slot" .. i and #g.stacks > 0 then return true end
	end
	return false
end

local function playerSide(L)
	for _, side in ipairs(L.sides) do
		if side.ship then return side end
	end
end

-- Pick a fitted module up off its slot (docked only).
local function takeFromSlot(game, L, r)
	local p = game.player
	local id = p.loadout[r.i]
	if not id then return end
	if game.state ~= "docked" then game:toast("DOCK AT A STATION TO REFIT", 1.4) return end
	if podBusy(p, r.i) then game:toast("EMPTY THE CARGO POD FIRST", 1.4) return end
	local w, h = Shapes.of(id)
	Cargo.hand = { id = id, n = 1, w = w, h = h, rot = false, w0 = w, h0 = h, rot0 = false,
		dx = 0, dy = 0, side = playerSide(L), from = { slot = r.i } }
	p.loadout[r.i] = false
	Ship.refit(p)
end

-- Fit the module in hand into slot i. Whatever was there goes where the
-- new one came from: the other slot, the same spot in the hold, or the
-- first free space (storage if the hold is full). Returns true if it fit.
local function fitHand(game, L, i)
	local p, h = game.player, Cargo.hand
	local m = data.modules[h.id]
	local slot = p.hull.slots[i]
	if game.state ~= "docked" then game:toast("DOCK AT A STATION TO REFIT", 1.4) return false end
	if not m or not data.fits(slot, m) then return false end
	if h.from.slot == i then return false end
	local old = p.loadout[i]
	if old and podBusy(p, i) then game:toast("EMPTY THE CARGO POD FIRST", 1.4) return false end
	if old then
		local f = h.from
		local om = data.modules[old]
		if f.slot and data.fits(p.hull.slots[f.slot], om) then
			p.loadout[f.slot] = old
		else
			local ow, oh = Shapes.of(old)
			local placed = false
			if f.grid and not f.stack and Grid.isFree(f.grid, f.x, f.y, ow, oh) then
				Grid.place(f.grid, { id = old, n = 1, x = f.x, y = f.y, w = ow, h = oh, rot = false })
				placed = true
			end
			if not placed and Hold.add(p.hold, old, 1) == 1 then placed = true end
			if not placed and p.dockState and Hold.add(game:stationStorage(p.dockState.station), old, 1) == 1 then placed = true end
			if not placed then game:toast("NO ROOM FOR THE OLD MODULE", 1.4) return false end
		end
	end
	Cargo.hand = nil
	p.loadout[i] = h.id
	Ship.refit(p)
	for _, side in ipairs(L.sides) do changed(side) end
	return true
end

-- Double-click a module in a hold: fit it into the first matching empty
-- slot, or else swap it into the first matching one.
local function quickFit(game, L, r, s)
	local p = game.player
	local m = data.modules[s.id]
	if not m then return end
	local best
	for i, slot in ipairs(p.hull.slots) do
		if data.fits(slot, m) and not best and not p.loadout[i] then best = i end
	end
	for i, slot in ipairs(p.hull.slots) do
		if data.fits(slot, m) and not best then best = i end
	end
	if not best then game:toast("NO SLOT FITS " .. m.name:upper(), 1.4) return end
	Grid.remove(r.g, s)
	Cargo.hand = { id = s.id, n = 1, w = s.w, h = s.h, rot = s.rot, w0 = s.w, h0 = s.h, rot0 = s.rot,
		dx = 0, dy = 0, side = r.side, from = { grid = r.g, hold = r.side.hold, x = s.x, y = s.y } }
	if not fitHand(game, L, best) then finish(game, L) end
end

-- A double-click: Cargo.quickFit for the autotest.
Cargo.quickFit = function(game, x, y)
	local L = layout(game)
	local r, cx, cy = cellAt(L, x, y)
	local s = r and Grid.at(r.g, cx, cy)
	if s then quickFit(game, L, r, s) end
end


-- Right-click menu --------------------------------------------------------

-- Right-clicking a stack opens a small menu of what you can do with it.
-- Cargo.menu = { x, y, items = { {label, run, why} }, r, s }; an item with
-- `why` is shown greyed out with the reason.
local MENU_W, MENU_ROW = 190, 24

local function stillThere(m)
	local s = m.s
	return Grid.at(m.r.g, s.x, s.y) == s
end

local function menuItems(game, L, r, s, mx, my)
	local items, p = {}, game.player
	local item = itemFor(s.id)
	local docked = game.state == "docked"
	local atMarket = trading() and docked
	local own = r.side.ship == p and not r.side.trade
	local function add(label, run, why) items[#items + 1] = { label = label, run = run, why = why } end
	if own and ItemUse.usable(s.id) then
		local ok, why = ItemUse.can(game, p, s.id)
		add("Use: " .. ItemUse.label(s.id), function()
			local ok2, why2 = ItemUse.begin(game, p, s.id)
			if ok2 then changed(r.side) elseif why2 then game:toast(why2, 1.5) end
		end, not ok and why or nil)
	end
	if item.kind == "container" and not atMarket then
		add("Open", function()
			if s.inner then Cargo.inner = s.inner else game:toast("IT'S EMPTY", 1) end
		end, not s.inner and "empty" or nil)
	end
	if item.kind == "module" and not atMarket then
		add("Fit to ship", function() quickFit(game, L, r, s) end, not docked and "dock to refit" or nil)
	end
	if #L.sides > 1 or atMarket then
		local label = (r.side.entity or r.side.innerOf) and "Take"
			or r.side.market and "Put on trade grid"
			or atMarket and "Move to trade grid"
			or "Move to other panel"
		add(label, function() quickMove(game, L, r, s) end)
	end
	if s.n > 1 and not r.side.market then
		add("Split stack", function()
			Cargo.lastClick = nil
			Cargo.mousepressed(game, mx, my, 1, { shift = true })
		end)
	end
	if r.side.ship and not docked and not r.side.trade then
		local function eject(n)
			return function()
				n = min(n, s.n)
				s.n = s.n - n
				if s.n <= 0 then Grid.remove(r.g, s) end
				changed(r.side)
				game:eject(r.side.ship, s.id, n, s.n <= 0 and s.inner or nil)
			end
		end
		if s.n > 1 then add("Eject one", eject(1)) end
		add(s.n > 1 and ("Eject all (" .. s.n .. ")") or "Eject", eject(s.n))
	end
	return items
end

local function menuRects(m)
	local sw, sh = lg.getDimensions()
	local h = #m.items * MENU_ROW + 8
	local x = min(m.x, sw - MENU_W - 4)
	local y = min(m.y, sh - h - 4)
	local rects = {}
	for i, it in ipairs(m.items) do
		rects[i] = { x = x + 4, y = y + 4 + (i - 1) * MENU_ROW, w = MENU_W - 8, h = MENU_ROW, it = it }
	end
	return { x = x, y = y, w = MENU_W, h = h }, rects
end

-- Returns true if the click was taken by the menu (always, while it's open).
local function menuClick(game, mx, my, button)
	local m = Cargo.menu
	Cargo.menu = nil
	local box, rects = menuRects(m)
	-- a right-click elsewhere reopens the menu there (the click goes on to
	-- the normal handler); on the menu itself it just closes it
	if button == 2 then return inRect(box, mx, my) end
	if button ~= 1 then return true end
	for _, b in ipairs(rects) do
		if inRect(b, mx, my) then
			if b.it.why then game:toast(string.upper(b.it.why), 1.2)
			elseif stillThere(m) then b.it.run() end
			return true
		end
	end
	return true
end

-- Pick the open menu's first item whose label starts with `prefix` (for
-- the autotest). Returns true if it ran.
function Cargo.menuChoose(game, prefix)
	local m = Cargo.menu
	if not m then return false end
	local _, rects = menuRects(m)
	for _, b in ipairs(rects) do
		if b.it.label:sub(1, #prefix) == prefix then
			menuClick(game, b.x + 2, b.y + 2, 1)
			return not b.it.why
		end
	end
	Cargo.menu = nil
	return false
end

local function drawMenu(game)
	local m = Cargo.menu
	if not m then return end
	if not stillThere(m) then Cargo.menu = nil return end
	local mx, my = love.mouse.getPosition()
	local box, rects = menuRects(m)
	lg.setColor(0.03, 0.07, 0.1, 0.97)
	lg.rectangle("fill", box.x, box.y, box.w, box.h, 5, 5)
	lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.5)
	lg.rectangle("line", box.x, box.y, box.w, box.h, 5, 5)
	lg.setFont(HUD.font(13))
	for _, b in ipairs(rects) do
		if not b.it.why and inRect(b, mx, my) then
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.22)
			lg.rectangle("fill", b.x, b.y, b.w, b.h, 4, 4)
		end
		lg.setColor(b.it.why and HUD.DIM or HUD.INK)
		local label = b.it.label .. (b.it.why and ("  (" .. b.it.why .. ")") or "")
		local f = HUD.font(13)
		while #label > 3 and f:getWidth(label) > b.w - 16 do label = label:sub(1, -5) .. "..." end
		lg.print(label, b.x + 8, b.y + 4)
	end
end

-- mods: { ctrl, shift } to stand in for the keyboard (the autotest uses it).
function Cargo.mousepressed(game, mx, my, button, mods)
	if not Cargo.isOpen(game) then return false end
	if Cargo.menu and menuClick(game, mx, my, button) then return true end
	-- an open shop menu takes the click: pick a shop, or close it
	if button == 1 then
		local tabs = spaceTabs(game)
		for _, t in ipairs(tabs or {}) do
			if inRect(t, mx, my) then Cargo.spaceTab = t.id; return true end
		end
		if tabs and Cargo.spaceTab == "reputation" then return true end
  if tabs and Cargo.spaceTab == "contracts" then return Contracts.mousepressed(game,mx,my,button) end
	end
	if Cargo.shopOpen then
		Cargo.shopOpen = false
		local L = layout(game)
		for _, side in ipairs(L and L.sides or {}) do
			for _, b in ipairs(side.shops or {}) do
				if button == 1 and inRect(b, mx, my) then
					if b.i ~= game:currentShop(side.station) then Cargo.clearTrade(game); game:setShop(side.station, b.i) end
				end
			end
		end
		return true
	end
	if game.state == "docked" and not Cargo.hand then
  local frame=Cargo.workspace(game)
  if button==1 and mx>=frame.x+frame.w-130 and mx<=frame.x+frame.w-14 and my>=24 and my<=54 then
   Cargo.clearTrade(game);game:undock();return true
  end
		for _, t in ipairs(tabRects(game)) do
			if button == 1 and inRect(t, mx, my) then Cargo.setTab(game,t.id);return true end
		end
		if Cargo.tab == "hangar" then
			local act = Hangar.mousepressed(game, mx, my, button)
			if act and act.fly then
				Cargo.other = nil
				game:flyFromHangar(act.fly)
			elseif act and act.cargo ~= nil then
				Cargo.setTab(game, "cargo"); Cargo.other = act.cargo or nil
			elseif act and act.sell then
				local st = game.player.dockState.station
				local rec = game:hangar(st)[act.sell]
				local paid, why = game:sellShip(st, act.sell)
				if paid then
					if Cargo.other == rec then Cargo.other = nil end
					game:toast(("SOLD FOR %d CR"):format(paid), 1.4)
				else game:toast(why, 1.4) end
			elseif act and act.move then
    local ok,why=game:moveStationShip(game.player.dockState.station,act.move,act.outside)
    if not ok then game:toast(why,1.4) end
			end
			return true
		end
		if Cargo.tab == "contracts" then return Contracts.mousepressed(game,mx,my,button) end
  if Cargo.tab == "industry" then return true end
		if Cargo.tab == "repair" then
			local act = Repair.mousepressed(game, mx, my, button)
			local st = game.player.dockState.station
			if act and act.cancelRepair then
				act.cancelRepair.repairOrder=nil;game:toast('REPAIRS CANCELLED',1.4)
			elseif act and act.repair then
				local pts, paid = game:repairShip(st, act.repair)
				if pts then game:toast(("REPAIRING %d ARMOR, UP TO %s"):format(pts, HUD.credits(paid):upper()), 1.4)
				else game:toast(paid, 1.4) end
			elseif act and act.repairAll then
				local owners = { game.player }
				for _, rec in ipairs(game:hangar(st)) do owners[#owners + 1] = rec end
				local pts, paid = 0, 0
				for _, o in ipairs(owners) do
					local a, b = game:repairShip(st, o)
					if a then pts, paid = pts + a, paid + b end
				end
				game:toast(pts > 0 and ("REPAIRING %d ARMOR, UP TO %s"):format(pts, HUD.credits(paid):upper()) or "NO REPAIR ORDERS STARTED", 1.4)
			end
			return true
		end
		if Cargo.tab == "shipyard" then
			local act = Shipyard.mousepressed(game, mx, my, button)
			if act and act.buy then
				local st = game.player.dockState.station
				if act.tradeIn and Cargo.other == act.tradeIn then Cargo.other = nil end
				local rec, why = game:buyShip(st, act.buy, { paint = act.paint, tradeIn = act.tradeIn })
				if rec then Hangar.sel = rec; game:toast("BOUGHT. PARKED: "..game:shipParkingLabel(st,rec):upper(),1.6)
				else game:toast(why, 1.4) end
			end
			return true
		end
	end
	local L = layout(game)
	if not L then return true end
	if Cargo.hand then return true end
	for _, side in ipairs(L.sides) do
		if button == 1 and side.switch and inRect(side.switch, mx, my) then
			-- each parked ship in turn
			local list = game:hangar(side.station)
			local nextRec = list[1]
			for i, r in ipairs(list) do if r == Cargo.other then nextRec = list[i + 1] or list[1] end end
			Cargo.other = nextRec
			return true
		end
		if button == 1 and side.complete and inRect(side.complete, mx, my) then
			local ok, res = game:completeTrade(side.station, side.hold)
			if ok then
    Cargo.shipOwned=nil
				game:toast("TRADE COMPLETE  " .. (res >= 0 and "+" or "") .. HUD.credits(res), 1.6, "pickup")
				for _, sd in ipairs(L.sides) do changed(sd) end
			else
				game:toast(res, 1.4)
			end
			return true
		end
		if button == 1 and side.clear and inRect(side.clear, mx, my) then
			Cargo.clearTrade(game)
			return true
		end
  if button==1 and side.shopMenu and inRect(side.shopMenu,mx,my) and #side.shops>1 then Cargo.shopOpen=true;return true end
		for _, f in ipairs(side.filters or {}) do
			if button == 1 and inRect(f, mx, my) then Cargo.filter = f.id; return true end
		end
		for _, pk in ipairs(side.picks or {}) do
			if button == 1 and inRect(pk, mx, my) then Cargo.marketLeft = pk.id return true end
		end
		if button == 1 and side.target and inRect(side.target, mx, my) then
			Cargo.target = targetKey(side)
			return true
		end
		if button == 1 and side.sort and inRect(side.sort, mx, my) then
			if not Hold.sort(side.hold) then game:toast("CAN'T SORT: IT WOULDN'T ALL FIT", 1.4) end
			changed(side)
			return true
		end
		if button == 1 and side.close and inRect(side.close, mx, my) then
			if side.parked then Cargo.other = nil else Cargo.inner = nil end
			return true
		end
		if button == 1 and side.take and inRect(side.take, mx, my) then
			takeAll(game, L, side)
			return true
		end
	end
	local er = slotAt(L, mx, my)
	if er and button == 1 and er.trig and inRect(er.trig, mx, my) then
		Ship.toggleTrigger(game.player, er.i)
		return true
	end
	if er and (button == 1 or button == 2) and er.load and inRect(er.load, mx, my) and loadOptions(game.player, er.i) then
		local p, opts = game.player, loadOptions(game.player, er.i)
		local cur, n = Ship.loadFor(p, er.i), 1
		for j, id in ipairs(opts) do if id == cur then n = j end end
		n = button == 1 and n % #opts + 1 or (n - 2) % #opts + 1
		Ship.setLoad(p, er.i, opts[n])
		return true
	end
	if er and button == 1 then takeFromSlot(game, L, er) return true end
	local r, cx, cy = cellAt(L, mx, my)
	local s = r and Grid.at(r.g, cx, cy)
	if not s or r.side.market and not stockMatch(s) then return true end
 Cargo.searchFocus=false
	-- double-click a module to fit it
	local now = love.timer.getTime()
	-- (the first click picks the stack up and puts it back as a new one,
	-- so match by place and item, not by the stack itself)
	local c = Cargo.lastClick
	local double = c and c.g == r.g and c.x == s.x and c.y == s.y and c.id == s.id and now - c.t < 0.35
	Cargo.lastClick = { g = r.g, x = s.x, y = s.y, id = s.id, t = now }
	if button == 1 and double and trading() and game.state == "docked" then
		Cargo.lastClick = nil
		quickMove(game, L, r, s)                   -- at the market: onto the trade grid (or back)
		return true
	end
	if button == 1 and double and itemFor(s.id).kind == "container" then
		if s.inner then Cargo.inner = s.inner else game:toast("IT'S EMPTY", 1) end
		return true
	end
	if button == 1 and double and itemFor(s.id).kind == "module" then
		if game.state == "docked" then quickFit(game, L, r, s) else game:toast("DOCK AT A STATION TO REFIT", 1.4) end
		return true
	end
	-- anything else: use it if it's usable and yours, or else send it to the
	-- other panel (never ejects; that's a drag out or the right-click menu)
	if button == 1 and double then
		Cargo.lastClick = nil
		if r.side.ship == game.player and not r.side.trade and ItemUse.usable(s.id) then
			local ok, why = ItemUse.begin(game, game.player, s.id)
			if ok then changed(r.side) elseif why then game:toast(why, 1.5) end
		elseif #L.sides > 1 then
			quickMove(game, L, r, s)
		end
		return true
	end
	local ctrl = mods and mods.ctrl or love.keyboard.isDown("lctrl", "rctrl")
	local shift = mods and mods.shift or love.keyboard.isDown("lshift", "rshift")
	local atMarket = trading() and game.state == "docked"
	if button == 2 then
		local items = menuItems(game, L, r, s, mx, my)        -- right-click: what you can do with it
		if #items > 0 then Cargo.menu = { x = mx + 2, y = my + 2, r = r, s = s, items = items } end
	elseif button == 1 and ctrl then
		quickMove(game, L, r, s)
	elseif button == 1 then
		local take = s.n
		-- a shelf stack has no limit; you pick up one ordinary stack of it
		if r.side.market then local _, _, cap = Shapes.of(s.id); take = min(take, cap) end
		if shift and take > 1 then take = floor(take / 2) end
		local hand = {
			id = s.id, n = take, w = s.w, h = s.h, rot = s.rot, w0 = s.w, h0 = s.h, rot0 = s.rot, inner = s.inner, shipRecord=s.shipRecord,
			dx = cx - s.x, dy = cy - s.y, side = r.side,
			owner = r.side.market and "station" or s.owner or "player", resale = s.resale,
			from = { grid = r.g, hold = r.side.hold, x = s.x, y = s.y },
		}
		if take < s.n then
			s.n = s.n - take
			hand.from.stack = s
		else
			Grid.remove(r.g, s)
		end
		Cargo.hand = hand
		changed(r.side)
	end
	return true
end

-- Where the stack in hand would land: the grid under the cursor and the
-- top-left cell, keeping the spot you grabbed it by under the cursor.
local function dropSpot(L, mx, my)
	local h = Cargo.hand
	local r, cx, cy = cellAt(L, mx, my)
	if not r then return nil end
	local x, y = cx - h.dx, cy - h.dy
	if h.inner and r.side.hold == h.inner then return r, x, y, "blocked" end   -- not into itself
	-- at the market, the station's goods stay on its shelf or the trade grid,
	-- and yours stay off its shelf
	if r.side.market and h.owner ~= "station" then return r, x, y, "blocked" end
	if h.owner == "station" and not (r.side.market or r.side.trade) then return r, x, y, "blocked" end
 if r.side.trade and r.g.tradeOwner~=h.owner then return r,x,y,'blocked' end
	if not r.side.trade and (not not ShipEntry.item(h.id))~=(not not r.side.shipEntries) then return r,x,y,'blocked' end
 local target = Grid.at(r.g, cx, cy)
	local _, _, cap = Shapes.of(h.id)
	if target and target.id == h.id and target.n < cap and not target.inner and not h.inner
		and target.resale == h.resale and (not r.side.trade or target.owner == h.owner) then
		return r, x, y, "merge", target
	end
	return r, x, y, Grid.isFree(r.g, x, y, h.w, h.h) and "place" or "blocked"
end

function Cargo.mousereleased(game, mx, my, button)
	if not Cargo.isOpen(game) then return false end
	if game.state == "docked" and Cargo.tab == "hangar" then
		if button == 1 then Hangar.mousereleased(game, mx, my) end
		return true
	end
	local h = Cargo.hand
	if button ~= 1 or not h then return true end
	local L = layout(game)
	local er = slotAt(L, mx, my)
	if er then
		if not fitHand(game, L, er.i) then finish(game, L) end
		return true
	end
	local r, x, y, how, target = dropSpot(L, mx, my)
	if how == "merge" then
		local _, _, cap = Shapes.of(h.id)
		local k = min(cap - target.n, h.n)
		target.n, h.n = target.n + k, h.n - k
		if h.n > 0 then returnHand(game) else Cargo.hand = nil end
		changed(r.side); changed(h.side)
	elseif how == "place" then
		Cargo.hand = nil
		Grid.place(r.g, { id = h.id, n = h.n, x = x, y = y, w = h.w, h = h.h, rot = h.rot, inner = h.inner, shipRecord=h.shipRecord,
			owner = r.side.trade and h.owner or nil, resale = (r.side.trade or r.side.market) and h.resale or nil })
		changed(r.side); changed(h.side)
	elseif not r and not overPanel(L, mx, my) and game.state ~= "docked" and h.side.ship then
		Cargo.hand = nil
		game:eject(h.side.ship, h.id, h.n, h.inner)
		changed(h.side)
	else
		finish(game, L)
	end
	return true
end

function Cargo.textinput(game,text)
 if game.state=='docked' and trading() and Cargo.searchFocus then Cargo.search=(Cargo.search or '')..text;return true end
end
function Cargo.keypressed(game, key)
 if game.state=='docked' and trading() and Cargo.searchFocus then
  if key=='escape' or key=='return' then Cargo.searchFocus=false
  elseif key=='backspace' then local utf8=require('utf8');local offset=utf8.offset(Cargo.search or '',-1);if offset then Cargo.search=Cargo.search:sub(1,offset-1) end end
  return true
 end
	if key == "tab" and game.state == "docked" then
		if not Cargo.hand then
			local tabs = offered(game)
			for i, t in ipairs(tabs) do
				if t.id == Cargo.tab then Cargo.setTab(game,(tabs[i+1] or tabs[1]).id);break end
			end
			Hangar.cancel()
		end
		return true
	end
	if game.state == "docked" and Cargo.tab == "hangar" and Hangar.keypressed(game, key) then return true end
	if key == "tab" then Cargo.toggle(game); return true end
	if not Cargo.isOpen(game) then return false end
	if key == "r" and Cargo.hand then
		local h = Cargo.hand
		h.w, h.h, h.rot = h.h, h.w, not h.rot
		h.dx, h.dy = min(h.dy, h.w - 1), min(h.dx, h.h - 1)
		return true
	end
	if key == "escape" and Cargo.menu then Cargo.menu = nil; return true end
	if key == "escape" and game.state ~= "docked" then Cargo.close(game); return true end
	if key == "e" and Cargo.loot then Cargo.close(game); return true end
	if key == "u" and not Cargo.hand then
		-- use the hovered stack (only from your own hold)
		local L = layout(game)
		local mx, my = love.mouse.getPosition()
		local r, cx, cy = L and cellAt(L, mx, my)
		local s = r and Grid.at(r.g, cx, cy)
		if s and r.side.ship == game.player and ItemUse.usable(s.id) then
			local ok, why = ItemUse.begin(game, game.player, s.id)
			if ok then changed(r.side) elseif why then game:toast(why, 1.5) end
			return true
		end
	end
	return false
end

-- Drawing ------------------------------------------------------------------

-- tag (at the market): { color, frame = draw a frame in that color (whose
-- it is, on the trade grid) }. Prices are in the tooltip.
local function drawStack(item, n, x, y, w, h, cs, alpha, tag, entry)
	local c = item.kind=='ship' and HUD.AQUA or HUD.itemColor(item)
	lg.setColor(c[1], c[2], c[3], 0.32 * alpha)
	lg.rectangle("fill", x + 2, y + 2, w - 4, h - 4, 3, 3)
	lg.setColor(c[1], c[2], c[3], 0.95 * alpha)
	lg.setLineWidth(1)
	lg.rectangle("line", x + 2.5, y + 2.5, w - 5, h - 5, 3, 3)
	if item.kind=='ship' then
  local Paint=require('src.paint');local hull=data.hulls[item.hull]
  local paint=entry and entry.shipRecord and entry.shipRecord.color or Paint.preset(Paint.pool(hull)[1])
  Hangar.drawHull(hull,x+4,y+16,w-8,math.max(4,h-20),entry and entry.rot or false,paint,alpha)
 end
 if cs >= 16 then
		lg.setFont(HUD.font(cs >= 24 and 11 or 9))
		lg.setColor(HUD.INK[1], HUD.INK[2], HUD.INK[3], alpha)
		if n > 1 then lg.printf(n, x, y + h - (cs >= 24 and 16 or 13), w - 5, "right") end
		if w >= cs * 2 and cs >= 22 then
			-- clipped to the stack, so a long name on a 1-cell-tall stack doesn't spill
			local sx, sy, sw2, sh2 = lg.getScissor()
			lg.intersectScissor(x + 2, y + 2, w - 4, h - (n > 1 and 14 or 4))
			lg.printf(item.name, x + 5, y + 4, w - 10, "left")
			lg.setScissor(sx, sy, sw2, sh2)
		end
	end
	if tag and tag.frame then
		lg.setColor(tag.color[1], tag.color[2], tag.color[3], alpha)
		lg.setLineWidth(2)
		lg.rectangle("line", x + 1, y + 1, w - 2, h - 2, 3, 3)
		lg.setLineWidth(1)
	end
end

local MINE, THEIRS = { 0.45, 1, 0.55 }, { 1, 0.72, 0.28 }

-- At the market: what a stack on show is worth to you, and how to draw it.
local function marketTag(side, s, owner)
	owner = owner or (side.market and "station") or s.owner or "player"
	local station = owner == "station"
	local v = station and Game.buyPrice(s) or Game.sellPrice(s)
	return { color = station and THEIRS or MINE, frame = side.trade, value = v, station = station }
end

local function clock(t)
	t = math.ceil(t)
	return ("%d:%02d"):format(floor(t / 60), t % 60)
end

local PRICE = { 0.45, 1, 0.55 }

-- price: a line in green under the stats (at the market).
-- The mouseover card: name and maker, a kind / size line, a description,
-- the stack's numbers, then price and what you can do with it.
local SIZE_NAME = { S = "Small", M = "Medium", L = "Large", any = "Any size" }
local function kindLine(item)
	local m = data.modules[item.id]
	if item.kind == "ship" then return "Ship" end
	if m then return "Module \194\183 " .. (m.computer and "Computer" or ((m.family == "computer" or m.family == "utility") and "Utility" or m.family:gsub("^%l", string.upper))) end
	if item.kind == "ammo" then return "Ammo \194\183 " .. ((item.family or "?"):gsub("^%l", string.upper)) end
	if item.kind == "container" then return "Container" end
	return (item.kind and item.kind:gsub("^%l", string.upper)) or "Item"
end
local function describe(item)
	local m = data.modules[item.id]
	local d = item.description or item.desc or (m and (m.description or m.desc))
	if d then return d end
	if item.kind == "ship" then return "Includes its installed modules and cargo." end
	if item.kind == "ammo" and item.shot then
		local sh, out = item.shot, {}
		if item.family == "drone" then return "Launches a drone that fights for you and docks back afterwards." end
		if sh.damage then out[#out + 1] = ("%d damage"):format(sh.damage) end
		if sh.splash then out[#out + 1] = ("%d splash"):format(sh.splash) end
		if sh.speed then out[#out + 1] = ("speed %d"):format(sh.speed) end
		if sh.range then out[#out + 1] = ("range %d"):format(sh.range) end
		local fits = item.family == "missile" and ("Fits %s launchers of size %s or bigger."):format(item.family, item.size)
			or ("Fits %s weapons of caliber %s."):format(item.family, item.size or "?")
		return table.concat(out, " \194\183 ") .. ". " .. fits
	end
	if m then
		local out = {}
		local w = m.weapon
		if w then
			if w.fireRate then out[#out + 1] = ("%.1f shots/s"):format(w.fireRate) end
			if w.gimbal then out[#out + 1] = ("gimbal %d\194\176"):format(w.gimbal) end
			if w.chambers then out[#out + 1] = "fires " .. table.concat(w.chambers, "/") .. " ammo" end
		end
		if m.powerDraw then out[#out + 1] = ("draws %s power"):format(m.powerDraw) end
		if #out > 0 then return table.concat(out, " \194\183 ") .. "." end
	end
	return nil
end
-- Module stats, one line each, for the mouseover: { label, value, format,
-- better } where better is 1 if more is better, -1 if less is.
local MODULE_STATS = {
	{ "thrust", "Thrust", "%d kN", 1 }, { "sideThrust", "Maneuvering", "%d kN", 1 },
	{ "turn", "Turn", "%d", 1 }, { "powerOut", "Power output", "%g/s", 1 },
	{ "powerCap", "Power storage", "%d", 1 }, { "armor", "Armor", "%d", 1 },
	{ "hold", "Hold", "%d m3", 1 }, { "tractorRange", "Tractor range", "%d px", 1 },
	{ "tractorPower", "Tractor power", "%g", 1 }, { "radarRange", "Radar range", "%d px", 1 },
	{ "uplinkRange", "Uplink range", "%d px", 1 }, { "controlLimit", "Drones", "%d", 1 },
	{ "lockCone", "Lock cone", "%d\194\176", 1 }, { "predictionTime", "Lead prediction", "%gs", 1 },
	{ "lookahead", "Lookahead", "%gs", 1 },
}
local WEAPON_STATS = {
	{ "fireRate", "Fire rate", "%g/s", 1 }, { "damage", "Damage", "%g", 1 }, { "range", "Range", "%d px", 1 },
	{ "gimbal", "Gimbal", "%d\194\176", 1 }, { "spread", "Spread", "%g\194\176", -1 },
	{ "beams", "Beams", "%d", 1 }, { "capacity", "Tubes (S rounds)", "%d", 1 }, { "recoil", "Recoil", "%g", -1 }, { "powerPerShot", "Power per shot", "%g", -1 },
	{ "powerPerSecond", "Power per second", "%g", -1 },
}
local function moduleLines(m)
	local out = {}
	local w = m.weapon
	if w then
		for _, st in ipairs(WEAPON_STATS) do
			local v = w[st[1]]
			if type(v) == "number" then out[#out + 1] = { key = "w." .. st[1], label = st[2], value = v, fmt = st[3], better = st[4] } end
		end
		if w.chambers then out[#out + 1] = { label = "Fires", text = table.concat(w.chambers, " / ") .. " ammo" } end
	end
	for _, st in ipairs(MODULE_STATS) do
		local v = m[st[1]]
		if type(v) == "number" and v ~= 0 then out[#out + 1] = { key = st[1], label = st[2], value = v, fmt = st[3], better = st[4] } end
	end
	if m.flares then out[#out + 1] = { label = "Countermeasures", text = "Flares" } end
	out[#out + 1] = { key = "powerDraw", label = "Power draw", value = m.powerDraw or 0, fmt = "%g/s", better = -1 }
	return out
end
local GOOD, BAD, FLAVOR = { 0.35, 1, 0.45 }, { 1, 0.4, 0.35 }, { 1, 0.82, 0.45 }

-- A mouseover card in the style of an RPG item tooltip: name and size,
-- kind and maker, one line per stat (with the change against what's fitted
-- in green or red), flavour text, then price and what you can do.
-- Returns w, h, draw(x, y).
local function card(item, n, hint, price, against, header)
	local W, P = 300, 12
	local big, small, tiny = HUD.font(15), HUD.font(12), HUD.font(11)
	local m = data.modules[item.id]
	local size = item.size and (SIZE_NAME[item.size] or item.size)
	if m then
		-- the badge says what slot it takes: "Medium engine", "Small bay"
		local fam = m.family == "computer" and "utility" or m.family   -- (old name)
		size = (m.size == "any" or not m.size) and (fam:gsub("^%l", string.upper)) or ((SIZE_NAME[m.size] or m.size) .. " " .. fam)
	elseif item.kind == "ammo" then
		-- ammo says what it is and its size: "Small rounds", "Medium shells"
		local WHAT = { gun = "rounds", artillery = "shells", missile = "tube", torpedo = "torpedo tube", drone = "drone" }
		local what = WHAT[item.family] or item.family or "ammo"
		size = item.size and ((SIZE_NAME[item.size] or item.size) .. " " .. what) or (what:gsub("^%l", string.upper))
	end
	-- the category badge sits above the type badge
	local category = (item.kind or "item"):gsub("^%l", string.upper)
	local lines = m and moduleLines(m) or nil
	if not m and item.kind == "ammo" and item.shot then
		-- ammo gets stat lines like a module
		lines = {}
		for _, st in ipairs({ { "damage", "Damage", "%g" }, { "splash", "Splash radius", "%g px" }, { "speed", "Speed", "%d px/s" },
			{ "accel", "Acceleration", "%d px/s2" }, { "turnRate", "Turn", "%.1f rad/s" }, { "range", "Range", "%d px" },
			{ "armTime", "Arm time", "%gs" }, { "fuse", "Proximity fuse", "%d px" }, { "pellets", "Pellets", "%d" },
			{ "knockback", "Knockback", "%d" } }) do
			local v = item.shot[st[1]]
			if type(v) == "number" then lines[#lines + 1] = { label = st[2], value = v, fmt = st[3] } end
		end
		lines[#lines + 1] = { label = "Fits", text = ("%s %s"):format(SIZE_NAME[item.size] or item.size or "?", item.family or "") }
	end
	local diff = {}
	local am = against and against ~= item.id and data.modules[against]
	if lines and am then
		local was = {}
		for _, l in ipairs(moduleLines(am)) do if l.key then was[l.key] = l.value end end
		for _, l in ipairs(lines) do if l.key then diff[l.key] = l.value - (was[l.key] or 0) end end
	end
	-- every card: the item's own description, else a placeholder
	local desc = item.description or item.desc or (m and (m.description or m.desc))
	if item.kind == "ship" and not desc then desc = describe(item) end
	if not desc then
		desc = ("Placeholder description: %s is a %s waiting on its real flavour text. This line is long enough to wrap so the layout can be checked."):format(item.name, kindLine(item):lower())
	end
	local descLines = {}
	if desc and desc ~= "" then _, descLines = small:getWrap('"' .. desc .. '"', W - P * 2) end
	-- the bar under the description: mass, and price when you're trading
	local stats = item.kind == "ship" and {} or {
		{ "Mass", ("%g t"):format(math.floor((item.mass or (m and m.mass) or 0) * n * 100 + 0.5) / 100) },
	}
	-- price joins the bar only at a market: "Buy for" / "Sells for"
	if price and item.kind ~= "ship" then
		local label, value = price:match("^(%a+ for) (.*)$")
		stats[#stats + 1] = { label or "Price", value or price, color = PRICE }
		price = nil
	end
	-- the bar's mass shows the change against the fitted module too
	if am and #stats > 0 then
		local d = (m.mass or 0) - (am.mass or 0)
		if math.abs(d) > 1e-6 then stats[1].diff, stats[1].good = (d > 0 and "+" or "-") .. ("%g t"):format(math.abs(d)), d < 0 end
	end
	local h = P + (header and 16 or 0) + 20 + 4 + ((item.maker or size) and 18 or 0) + (lines and (#lines * 16 + 6) or 0)
		+ (#descLines > 0 and (#descLines * 15 + 8) or 0) + (#stats > 0 and 40 or 0)

		+ (price and 20 or 0) + (hint and 24 or 0) + P - 4
	return W, h, function(x, y)
		lg.setColor(0.02, 0.06, 0.09, 0.96)
		lg.rectangle("fill", x, y, W, h, 6, 6)
		lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.5)
		lg.rectangle("line", x + 0.5, y + 0.5, W - 1, h - 1, 6, 6)
		local cy = y + P
		if header then lg.setFont(tiny); lg.setColor(HUD.DIM); lg.print(header, x + P, cy); cy = cy + 16 end
		-- badges on the right: category on top, type and size under it
		local function badge(text, by, strong)
			local bw = tiny:getWidth(text) + 14
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], strong and 0.25 or 0.12)
			lg.rectangle("fill", x + W - P - bw, by, bw, 16, 4, 4)
			lg.setFont(tiny); lg.setColor(strong and HUD.INK or HUD.DIM)
			lg.printf(text, x + W - P - bw, by + 2, bw, "center")
			return bw
		end
		local badgeW = item.kind ~= "ship" and badge(category, cy + 1, false) or 0
		local sizeW = size and badge(size, cy + 20, true) or 0
		-- the name in the item's own colour, as it shows in the hold
		lg.setFont(big); lg.setColor(item.kind == "ship" and HUD.AQUA or HUD.itemColor(item))
		lg.printf(item.name .. (n and n > 1 and ("  \195\151" .. n) or ""), x + P, cy, W - P * 2 - badgeW - 6, "left")
		cy = cy + 20
		-- the maker under the name, in a soft blue-grey
		if item.maker then
			lg.setFont(small); lg.setColor(0.62, 0.7, 0.82)
			lg.printf(item.maker, x + P, cy + 1, W - P * 2 - sizeW - 6, "left")
		end
		if item.maker or size then cy = cy + 18 end
		cy = cy + 4
		if lines then
			cy = cy + 2
			lg.setFont(small)
			for _, l in ipairs(lines) do
				lg.setColor(HUD.DIM); lg.print(l.label, x + P, cy)
				local text = l.text or l.fmt:format(l.value)
				local d = l.key and diff[l.key]
				local dx = 0
				if d and math.abs(d) > 1e-6 then
					local good = d * l.better > 0
					local ds = (d > 0 and "+" or "-") .. l.fmt:format(math.abs(d))
					lg.setColor(good and GOOD or BAD)
					lg.printf(ds, x + P, cy, W - P * 2, "right")
					dx = small:getWidth(ds) + 10
				end
				lg.setColor(HUD.INK); lg.printf(text, x + P, cy, W - P * 2 - dx, "right")
				cy = cy + 16
			end
			cy = cy + 4
		end
		if #descLines > 0 then
			cy = cy + 4
			lg.setFont(small); lg.setColor(FLAVOR)
			for _, l in ipairs(descLines) do lg.print(l, x + P, cy); cy = cy + 15 end
			cy = cy + 4
		end
		if #stats > 0 then
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.2)
			lg.line(x + P, cy + 4, x + W - P, cy + 4)
			local cw = (W - P * 2) / #stats
			for i, st in ipairs(stats) do
				local sx = x + P + (i - 1) * cw
				lg.setFont(tiny); lg.setColor(HUD.DIM); lg.print(st[1], sx, cy + 10)
				lg.setFont(small:getWidth(st[2]) > cw - 6 and tiny or small); lg.setColor(st.color or HUD.INK); lg.print(st[2], sx, cy + 23)
				if st.diff then
					lg.setColor(st.good and GOOD or BAD)
					lg.print(st.diff, sx + small:getWidth(st[2]) + 8, cy + 23)
				end
			end
			cy = cy + 40
		end
		if price then lg.setFont(small); lg.setColor(PRICE); lg.print(price, x + P, cy + 2); cy = cy + 20 end
		if hint then
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.2)
			lg.line(x + P, cy + 4, x + W - P, cy + 4)
			lg.setFont(tiny); lg.setColor(HUD.DIM); lg.print(hint, x + P, cy + 9)
		end
	end
end

-- against: the module id this one would replace; its own card ("Currently
-- fitted") is drawn alongside so the two can be read side by side.
local function tooltip(item, n, mx, my, hint, price, against)
	local sw, sh = lg.getDimensions()
	local w, h, draw = card(item, n, hint, price, against)
	local x, y = min(mx + 18, sw - w - 4), min(my + 18, sh - h - 4)
	draw(x, y)
	local am = against and against ~= item.id and data.items[against]
	if am then
		local w2, h2, draw2 = card(am, 1, nil, nil, nil, "Currently fitted")
		local x2 = x + w + 6
		if x2 + w2 > sw - 4 then x2 = x - w2 - 6 end
		draw2(x2, min(y, sh - h2 - 4))
	end
end

local SLOT_LABEL = { hardpoint = "HARDPOINT", bay = "BAY", engine = "ENGINE",
	reactor = "REACTOR", utility = "UTILITY", computer = "UTILITY" }

local function slotLabel(slot)
	return SLOT_LABEL[slot.family] .. (slot.size ~= "any" and (" " .. slot.size) or "")
end

-- Handling numbers for a hull with a loadout and cargo mass (tonnes).
local function handling(hull, loadout, cargoMass)
	local s = stats.compute(hull, loadout)
	local m = (s.mass + cargoMass) * T.massScale
	local thrust = math.max(s.thrust, s.sideThrust * T.sideScale) * T.FORCE_PER_KN * T.thrustScale   -- jets stand in for a missing engine
	return {
		{ "Top speed", math.sqrt(thrust / (hull.drag * T.dragScale)), "%.0f px/s" },
		{ "Acceleration", thrust / m, "%.0f px/s2" },
		{ "Turn", s.turn, "%.0f" },
		{ "Spare power", s.powerNet, "%+.0f/s" },
		{ "Mass", m, "%.0f t" },
	}
end

-- The before -> after readout while a module hovers over a slot it fits.
local function drawReadout(game, i, x, y)
	local p, h = game.player, Cargo.hand
	local after = {}
	for k, v in pairs(p.loadout) do after[k] = v end
	local old = after[i]
	after[i] = h.id
	if h.from.slot then after[h.from.slot] = old or false end
	local cargoMass = p.cargoMass + (old and not h.from.slot and data.modules[old].mass or 0)
	local before = {}
	for k, v in pairs(p.loadout) do before[k] = v end
	if h.from.slot then before[h.from.slot] = h.id end
	local a = handling(p.hull, before, p.cargoMass + (h.from.slot and 0 or itemFor(h.id).mass))
	local b = handling(p.hull, after, cargoMass)
	local w, rh = 300, 18
	local ph = #a * rh + 16
	lg.setColor(0.02, 0.06, 0.09, 0.95)
	lg.rectangle("fill", x, y, w, ph, 6, 6)
	lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.5)
	lg.rectangle("line", x + 0.5, y + 0.5, w - 1, ph - 1, 6, 6)
	lg.setFont(HUD.font(12))
	for k, row in ipairs(a) do
		local ny = y + 8 + (k - 1) * rh
		local before, now = row[2], b[k][2]
		lg.setColor(HUD.DIM)
		lg.print(row[1], x + 10, ny)
		lg.printf(row[3]:format(before), x, ny, 170, "right")
		local better = (row[1] == "Mass") and now < before - 0.5 or now > before + 0.5
		local worse = (row[1] == "Mass") and now > before + 0.5 or now < before - 0.5
		lg.setColor(better and { 0.5, 1, 0.6 } or (worse and HUD.WARN or HUD.INK))
		lg.printf("-> " .. row[3]:format(now), x, ny, w - 10, "right")
	end
end

local function drawEquipment(game, L, mx, my)
	local p, E, h = game.player, L.equip, Cargo.hand
	if E.hidden then return end
	local docked = game.state == "docked"
	Station.panel(E.x,E.y,E.pw,E.ph)
	lg.setFont(HUD.font(16))
	lg.setColor(HUD.INK)
	lg.print("Equipment", E.x + PAD, E.y + 12)
	if not docked then
		lg.setFont(HUD.font(11))
		lg.setColor(HUD.DIM)
		lg.printf("dock to refit", E.x + PAD, E.y + 41, E.pw - PAD * 2, "right")
	end

	-- Hull outline, nose to the right, with each hardpoint numbered.
	local shape = p.hull.shape
	local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
	for k = 1, #shape, 2 do
		x1, x2 = min(x1, shape[k]), max(x2, shape[k])
		y1, y2 = min(y1, shape[k + 1]), max(y2, shape[k + 1])
	end
	local hb = E.hull
	local sc = min((hb.w - 20) / (x2 - x1), (hb.h - 10) / (y2 - y1))
	local ox, oy = hb.x + hb.w / 2 - (x1 + x2) / 2 * sc, hb.y + hb.h / 2 - (y1 + y2) / 2 * sc
	local c = p.color
	lg.push()
	lg.translate(ox, oy)
	lg.scale(sc)
	HullShape.draw(p.hull, c, function(pc) return { pc[1], pc[2], pc[3], 0.12 } end,
		function(pc) return { pc[1], pc[2], pc[3], 0.8 } end, 1.5 / sc)
	lg.pop()
	lg.setLineWidth(1)

	local hm = h and data.modules[h.id]
	local hover = slotAt(L, mx, my)
	lg.setFont(HUD.font(10))
	for _, r in ipairs(E.slots) do
		-- every placed slot gets an unnumbered marker in its family's colour;
		-- hovering its row (or the marker) highlights it and draws a leader
		if r.slot.x then
			local sx, sy = ox + r.slot.x * sc, oy + (r.slot.y or 0) * sc
			r.mx, r.my = sx, sy
			local fits = hm and data.fits(r.slot, hm)
			local col = fits and { 0.4, 1, 0.55 } or Sheet.familyColor(r.slot)
			local big = hover == r or fits
			lg.setColor(0.02, 0.06, 0.09, 0.9)
			lg.circle("fill", sx, sy, big and 8 or 6)
			lg.setColor(col[1], col[2], col[3], big and 1 or 0.85)
			lg.setLineWidth(big and 2 or 1.5)
			lg.circle("line", sx, sy, big and 8 or 6)
			lg.setLineWidth(1)
		end
	end
	if hover and hover.mx then
		local c = Sheet.familyColor(hover.slot)
		lg.setColor(c[1], c[2], c[3], 0.6)
		lg.line(hover.x + 2, hover.y + hover.h / 2, hover.mx, hover.my)
	end

	-- One row per slot.
	for _, r in ipairs(E.slots) do
		local id = p.loadout[r.i]
		local m = id and data.modules[id]
		local fits = hm and data.fits(r.slot, hm)
		local alpha = (hm and not fits) and 0.35 or 1
		local hot = hover == r
		lg.setColor(0, 0, 0, 0.35)
		lg.rectangle("fill", r.x, r.y, r.w, r.h, 5, 5)
		if fits then
			lg.setColor(0.3, 1, 0.5, hot and 0.35 or 0.15)
			lg.rectangle("fill", r.x, r.y, r.w, r.h, 5, 5)
		elseif hot and not h then
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.15)
			lg.rectangle("fill", r.x, r.y, r.w, r.h, 5, 5)
		end
		lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.3 * alpha)
		lg.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1, 5, 5)
		lg.setFont(HUD.font(10))
		lg.setColor(HUD.DIM[1], HUD.DIM[2], HUD.DIM[3], alpha)
		local fc = Sheet.familyColor(r.slot)
		lg.setColor(fc[1], fc[2], fc[3], alpha)
		lg.print(slotLabel(r.slot), r.x + 6, r.y + 2)
		lg.setFont(HUD.font(12))
		if m then
			lg.setColor(HUD.INK[1], HUD.INK[2], HUD.INK[3], alpha)
			lg.print(m.name, r.x + 6, r.y + 12)
		else
			lg.setColor(HUD.WARN[1], HUD.WARN[2], HUD.WARN[3], 0.8 * alpha)
			lg.print("empty", r.x + 6, r.y + 12)
		end
		local opts = r.load and ammoList(p, r.i)
		if opts then
			local t, on = r.load, inRect(r.load, mx, my)
			local id = Ship.loadFor(p, r.i)
			local have = (p.cargo[id] or 0) > 0
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], ((on and #opts > 1) and 0.35 or 0.12) * alpha)
			lg.rectangle("fill", t.x, t.y, t.w, t.h, 4, 4)
			local col = have and HUD.INK or HUD.WARN
			lg.setColor(col[1], col[2], col[3], (#opts > 1 and 1 or 0.55) * alpha)
			local item=data.items[id];local label=item.shortName or item.name
			local font=HUD.font(10)
			if font:getWidth(label)>t.w-4 then font=HUD.font(8) end
			lg.setFont(font)
			lg.printf(label, t.x + 2, t.y + (t.h - font:getHeight()) / 2, t.w - 4, "center")
		end
		if r.trig then
			local t, on = r.trig, inRect(r.trig, mx, my)
			local trig = Ship.triggerFor(p, r.i)
			local col = trig == "secondary" and { 0.8, 0.9, 1 } or (trig == "tertiary" and { 1, 0.85, 0.7 } or HUD.INK)
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], (on and 0.35 or 0.12) * alpha)
			lg.rectangle("fill", t.x, t.y, t.w, t.h, 4, 4)
			lg.setColor(col[1], col[2], col[3], alpha)
			lg.setFont(HUD.font(11))
			lg.printf(Ship.TRIGGER_TAG[trig], t.x, t.y + (t.h - 11) / 2 - 1, t.w, "center")
		end
	end
end

-- Folder tabs sitting on the top edge of the window.
function drawTabs(game,mx,my)
 local p=game.player;local st=p.dockState.station;local f=Cargo.workspace(game)
 Station.panel(f.x,12,f.w,88)
 Station.ledgerText(f.x,12,st.name,game:shipParkingLabel(st,p)..'  \194\183  '..require('src.food').label(game.universe,st.key or st.locationId))
 lg.setFont(HUD.font(16));lg.setColor(HUD.INK);lg.printf(HUD.credits(game:credits()),f.x+f.w-340,21,190,'right')
 Station.button({x=f.x+f.w-130,y=24,w=116,h=30},'Undock',false)
 lg.setFont(HUD.font(14))
 for _,t in ipairs(tabRects(game)) do Station.button(t,t.label,Cargo.tab==t.id) end
end

-- The trade grid's totals and buttons, under the grid.
function drawTrade(game, L, side, mx, my)
	local get, pay = Game.tradeTotals(side.hold)
	local credits = game.universe.credits
	local x, w = side.x + PAD, side.pw - PAD * 2
	local y=side.y+side.ph-190
	lg.setFont(HUD.font(13))
	local function row(label, value, color, k)
		lg.setColor(HUD.DIM)
		lg.print(label, x, y + k * 19)
		lg.setColor(color)
		lg.printf(value, x, y + k * 19, w, "right")
	end
	row("Sell value",HUD.credits(get),HUD.INK,0)
 row("Buy cost",HUD.credits(pay),HUD.INK,1)
 row(pay>=get and "You pay" or "You receive",HUD.credits(math.abs(pay-get)),pay>=get and THEIRS or MINE,2)
	local after = credits + get - pay
	row("Balance", HUD.credits(credits) .. "  ->  " .. HUD.credits(after), after < 0 and HUD.WARN or HUD.INK, 3)
	local problem = (get+pay>0) and game:tradeProblem(side.station,side.hold)
	if problem then
		lg.setColor(HUD.WARN)
		lg.printf(problem, x, y + 4 * 19, w, "right")
	end
	local c, cl = side.complete, side.clear
	local empty=true;for _,g in ipairs(side.hold.grids) do if #g.stacks>0 then empty=false end end
	local ok = not empty and not problem
 Station.button(c,'Complete trade',ok,ok)
 Station.button(cl,'Clear',false,not empty)
end

function Cargo.draw(game)
	if not Cargo.isOpen(game) then return end
	checkTab(game)
	local L = layout(game)
	if not L then return end
	local cs = L.cs
	local sw, sh = lg.getDimensions()
	local mx, my = love.mouse.getPosition()
	local docked = game.state == "docked"
	local market = docked and trading()

	lg.setColor(0, 0, 0, docked and 0.55 or 0.3)
	lg.rectangle("fill", 0, 0, sw, sh)

	if docked then
		drawTabs(game, mx, my)
		if Cargo.tab == "hangar" then
			Hangar.draw(game, mx, my)
			lg.setFont(HUD.font(14))
			lg.setColor(HUD.DIM)
			Station.footer('Drag a ship to another spot in the bay or onto a free berth outside.','Click selects  \194\183  R rotates while dragging  \194\183  Double-click flies  \194\183  Mouse wheel scrolls berths')
			return
		end
		if Cargo.tab == "repair" then
			Repair.draw(game, mx, my)
			lg.setFont(HUD.font(14))
			Station.footer('Repairs restore armor at this station\'s rate per point.','Short on credits? Repair fixes as much as you can pay for.')
			return
		end
		if Cargo.tab == "contracts" then
   Contracts.draw(game)
   Station.footer('Global freight orders shared with NPCs. Payment is for delivery; cargo is supplied by the source.', 'Pick up and deliver through this tab · Loaded contracts must be returned to their source to cancel · Mouse wheel scrolls')
   return
  end
  if Cargo.tab == "industry" then
			IndustryView.draw(game, mx, my)
			lg.setFont(HUD.font(14))
			Station.footer('What this station makes, what it is waiting on, and where its output goes.','Shares move with the facility policy  \194\183  Inputs arrive by freight  \194\183  Mouse wheel scrolls')
			return
		end
		if Cargo.tab == "shipyard" then
			Shipyard.draw(game, mx, my)
			lg.setFont(HUD.font(14))
			Station.footer('Every ship on the lot is one of a kind: its own trim, paint and fit. Sold ships are gone until the dealer restocks.','Trade in a stored ship to put its value toward the price  \194\183  Sell ships outright from the Hangar tab')
			return
		end
	end

	local stabs, sframe = spaceTabs(game)
	if not docked then
		local fx, fw = Station.frame()
		local p = game.player
		Station.panel(fx, 12, fw, 88)
		Station.ledgerText(fx, 12, p.hull.name, Cargo.loot and "Looting" or "In flight \194\183 dock at a station to refit")
		lg.setFont(HUD.font(16)); lg.setColor(HUD.INK); lg.printf(HUD.credits(game:credits()), fx + fw - 340, 21, 190, "right")
		lg.setFont(HUD.font(12)); lg.setColor(HUD.DIM); lg.printf("Tab / Esc closes", fx + fw - 140, 24, 126, "right")
	end
	if stabs then
		lg.setFont(HUD.font(14))
		for _, t in ipairs(stabs) do Station.button(t, t.label, Cargo.spaceTab == t.id) end
		if Cargo.spaceTab == "reputation" then require("src.ui.reputation").draw(game, sframe) return end
  if Cargo.spaceTab == "contracts" then Contracts.draw(game) return end
	end
	drawEquipment(game, L, mx, my)

	for _, side in ipairs(L.sides) do
		Station.panel(side.x,side.y,side.pw,side.ph)
		if side.picks then
   lg.setFont(HUD.font(16));lg.setColor(HUD.INK);lg.print('Your inventory',side.x+PAD,side.y+12)
			for _, pk in ipairs(side.picks) do
				local on = Cargo.marketLeft == pk.id
    lg.setFont(HUD.font(13));Station.button(pk,pk.label,on)
			end
		else
			lg.setFont(HUD.font(16))
			lg.setColor(HUD.INK)
			lg.print(side.trade and 'Trade offer' or side.market and ('Shops \194\183 '..side.station.name) or side.title,side.x+PAD,side.y+12)
		end
		local used, total = Hold.cells(side.hold)
		lg.setFont(HUD.font(12))
		lg.setColor(HUD.DIM)
		if side.market then
			lg.setColor(HUD.INK)

		elseif side.picks then
			-- (the tabs take the title's place: the fill goes on the grid's label row)
			lg.printf((side.shipEntries and "%d / %d cells" or "%d / %d m3"):format(used,total),side.x,side.y+80,side.pw-PAD,"right")
		elseif not side.trade then
   lg.printf(("%d / %d m3"):format(used,total),side.x+PAD,side.y+41,side.pw-PAD*2,'right')
		end
		local b = side.sort
		if b then
			local hot = not Cargo.hand and inRect(b, mx, my)
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], hot and 0.35 or 0.15)
			lg.rectangle("fill", b.x, b.y, b.w, b.h, 5, 5)
			lg.setColor(HUD.INK)
			lg.printf("Sort", b.x, b.y + 4, b.w, "center")
		end
		if side.trade then drawTrade(game, L, side, mx, my) end
		local tg = side.target
		if tg then
			local on = (Cargo.target or "parked") == targetKey(side)
			lg.setColor(0.3, 1, 0.5, on and 0.4 or (not Cargo.hand and inRect(tg, mx, my) and 0.22 or 0.08))
			lg.rectangle("fill", tg.x, tg.y, tg.w, tg.h, 4, 4)
			lg.setFont(HUD.font(11))
			lg.setColor(on and HUD.INK or HUD.DIM)
			lg.printf("Target", tg.x, tg.y + 2, tg.w, "center")
			if on then
				lg.setColor(0.3, 1, 0.5, 0.6)
				lg.setLineWidth(2)
				lg.rectangle("line", side.x + 1, side.y + 1, side.pw - 2, side.ph - 2, 10, 10)
				lg.setLineWidth(1)
			end
		end
  if side.shopMenu then
   local cur=game:currentShop(side.station);local shops=Game.marketShops(side.station)
   local m=side.shopMenu
   lg.setFont(HUD.font(14));Station.button(m,'',Cargo.shopOpen or inRect(m,mx,my))
   lg.setColor(HUD.INK);lg.print(shops[cur].name,m.x+10,m.y+6)
   if #shops>1 then
    lg.setColor(HUD.DIM);lg.printf(('%d shops'):format(#shops),m.x,m.y+6,m.w-30,'right')
    local ax,ay=m.x+m.w-18,m.y+m.h/2
    lg.polygon('fill',ax-5,ay-3,ax+5,ay-3,ax,ay+3)
   end
   local desc=shops[cur] and shops[cur].description or ''
   if desc~='' then lg.setFont(HUD.font(12));lg.setColor(HUD.DIM);lg.printf(desc,side.x+PAD,side.y+76,side.pw-PAD*2) end
  end
		for _, f in ipairs(side.filters or {}) do
			local on = Cargo.filter == f.id
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], on and 0.4 or (inRect(f, mx, my) and 0.25 or 0.1))
			lg.rectangle("fill", f.x, f.y, f.w, f.h, 4, 4)
			lg.setFont(HUD.font(11))
			lg.setColor(on and HUD.INK or HUD.DIM)
			lg.printf(f.label, f.x, f.y + 2, f.w, "center")
		end
		local t = side.take
		if t then
			local hotT = not Cargo.hand and inRect(t, mx, my)
			lg.setColor(0.3, 1, 0.5, hotT and 0.4 or 0.18)
			lg.rectangle("fill", t.x, t.y, t.w, t.h, 5, 5)
			lg.setColor(HUD.INK)
			lg.printf("Take All", t.x, t.y + 4, t.w, "center")
		end
		local swr = side.switch
		if swr then
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], (not Cargo.hand and inRect(swr, mx, my)) and 0.35 or 0.15)
			lg.rectangle("fill", swr.x, swr.y, swr.w, swr.h, 5, 5)
			lg.setColor(HUD.INK)
			lg.printf(swr.label, swr.x, swr.y + 4, swr.w, "center")
		end
		local cl = side.close
		if cl then
			lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], (not Cargo.hand and inRect(cl, mx, my)) and 0.35 or 0.15)
			lg.rectangle("fill", cl.x, cl.y, cl.w, cl.h, 5, 5)
			lg.setColor(HUD.INK)
			lg.printf("x", cl.x, cl.y + 4, cl.w, "center")
		end
	end

	for _, r in ipairs(L.grids) do
		lg.setFont(HUD.font(12))
		lg.setColor(HUD.DIM)
		if not r.side.market then
   local label=("%s  %d x %d"):format(r.label,r.g.w,r.g.h)
   if docked then
    local width=r.g.w*cs
    if lg.getFont():getWidth(label)>width then label=r.label end
    if lg.getFont():getWidth(label)>width then
     while #label>0 and lg.getFont():getWidth(label..'...')>width do label=label:sub(1,-2) end
     label=label..'...'
    end
   end
   lg.print(label,r.x,r.y-17)
  end
		lg.setColor(0, 0, 0, 0.35)
		lg.rectangle("fill", r.x, r.y, r.g.w * cs, r.g.h * cs)
  if r.side.market and r.side.shipEntries and #r.g.stacks==0 then
   lg.setFont(HUD.font(12));lg.setColor(HUD.DIM)
   local st=r.side.station
   local message=#game:shipyard(st)==0 and 'This station has no ships for sale.\nStored ships can still be sold here.' or 'Ships for sale are in your trade offer.'
   lg.printf(message,r.x+8,r.y+12,r.g.w*cs-16,'left')
  end
		lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.12)
		lg.setLineWidth(1)
		for cy = 0, r.g.h - 1 do
			for cx = 0, r.g.w - 1 do lg.rectangle("line", r.x + cx * cs + 0.5, r.y + cy * cs + 0.5, cs - 1, cs - 1) end
		end
		for _, s in ipairs(r.g.stacks) do
			local tag = market and marketTag(r.side, s)
			local alpha = (r.side.market and Cargo.filter ~= "all" and filterOf(s.id) ~= Cargo.filter) and 0.25 or 1
   if r.side.market and not stockMatch(s) then alpha=0 end
			drawStack(itemFor(s.id), s.n, r.x + s.x * cs, r.y + s.y * cs, s.w * cs, s.h * cs, cs, alpha, tag,s)
		end
	end

	-- Status and help along the bottom.
	local p = game.player
	lg.setFont(HUD.font(13))
	lg.setColor(HUD.INK)
	local hint
	if market then
		hint = "Drag goods onto the trade grid   Ctrl-click or double-click move across   Right-click actions   Shift-drag split   Complete trade to settle   Tab switch tabs   E launch"
	elseif docked then
		hint = "Drag to move   R rotate   Shift-drag split   Ctrl-click or double-click move across   Right-click actions   Drag or double-click a module to fit it   E, Enter or (A) launch"
	else
		hint = "Drag to move   R rotate   Shift-drag split   Right-click or drag out to eject   Tab or Esc close"
		if Cargo.loot then hint = "Drag to move   R rotate   Shift-drag split   Ctrl-click or double-click take   Right-click actions   Take All   E, Tab or Esc close" end
	end
 do
  local r,cx,cy=cellAt(L,mx,my);local selected=Cargo.hand or r and Grid.at(r.g,cx,cy)
  if selected and not Cargo.hand and r.side.market and not stockMatch(selected) then selected=nil end
  local problem=docked and Ship.launchProblem(p)
  local title=problem and ("Can't launch: "..problem) or ('Mass %.0f t'):format(p.body:getMass())
  local details=hint
  if selected then
   local item=itemFor(selected.id);title=item.name
   details=('%d units • %d × %d cells'):format(selected.n,selected.w,selected.h)
   if market then local tag=marketTag(Cargo.hand and Cargo.hand.side or r.side,selected);details=details..' • '..(tag.station and 'Buy ' or 'Sell ')..HUD.credits(tag.value) end
  end
  Station.footer(title,details,problem and not selected)

 end

	local h = Cargo.hand
	if h then
		-- Footprint preview: green where it fits, red where it doesn't.
		local r, x, y, how = dropSpot(L, mx, my)
		if r then
			local ok = how ~= "blocked"
			lg.setColor(ok and 0.3 or 1, ok and 1 or 0.35, ok and 0.5 or 0.3, 0.28)
			if how == "merge" then
				local _, cx, cy = cellAt(L, mx, my)
				local t = Grid.at(r.g, cx, cy)
				lg.rectangle("fill", r.x + t.x * cs, r.y + t.y * cs, t.w * cs, t.h * cs)
			else
				for cy = y, y + h.h - 1 do
					for cx = x, x + h.w - 1 do
						if cx >= 0 and cy >= 0 and cx < r.g.w and cy < r.g.h then
							lg.rectangle("fill", r.x + cx * cs + 1, r.y + cy * cs + 1, cs - 2, cs - 2)
						end
					end
				end
			end
		elseif not overPanel(L, mx, my) and not docked then
			lg.setColor(HUD.WARN)
			lg.setFont(HUD.font(13))
			lg.print("Release to eject", mx + 16, my - 22)
		end
		local er = slotAt(L, mx, my)
		local hm = data.modules[h.id]
		if er and hm and data.fits(er.slot, hm) and docked then
			drawReadout(game, er.i, L.equip.x + L.equip.pw + 8, er.y)
		end
		drawStack(itemFor(h.id), h.n, mx - h.dx * cs - cs / 2, my - h.dy * cs - cs / 2, h.w * cs, h.h * cs, cs, 0.85,
			market and marketTag(h.side, h, h.owner),h)
	else
		local er = slotAt(L, mx, my)
		local fitted = er and p.loadout[er.i]
		if er and er.trig and inRect(er.trig, mx, my) then
			fitted = nil
			HUD.tip = nil
			lg.setFont(HUD.font(11))
			lg.setColor(HUD.DIM)
			lg.print("click: change which fire group this slot is in", mx + 14, my + 14)
		end
		if er and er.load and inRect(er.load, mx, my) and ammoList(p, er.i) then
			fitted = nil
			HUD.tip = nil
			lg.setFont(HUD.font(11))
			lg.setColor(HUD.DIM)
			lg.print(loadOptions(p, er.i) and "click: change which ammo this weapon loads (right-click: back)"
				or "this weapon chambers only this ammo", mx + 14, my + 14)
		end
		if fitted then
			tooltip(data.items[fitted], 1, mx, my, docked and "Drag to the hold to unfit" or "Dock at a station to refit")
		end
		local r, cx, cy = cellAt(L, mx, my)
		local s = r and Grid.at(r.g, cx, cy)
		if s and not Cargo.menu and (not r.side.market or stockMatch(s)) then
			local item = itemFor(s.id)
			local hint2, price
			if market then
				local tg = marketTag(r.side, s)
				price = (tg.station and "Buy for " or "Sells for ") .. HUD.credits(tg.value) .. (s.inner and " (with its contents)" or "")
				if s.resale then
					hint2 = ("Resale: sold on in %s"):format(clock(s.resale - game.universe.clock))
				elseif tg.station and r.side.market then
					local t = game:restockIn(r.side.station, s.id)
					if t then hint2 = ("More in %s"):format(clock(t)) end
				end
			elseif docked and item.kind == "module" then hint2 = "Drag onto a slot or double-click to fit"
			elseif item.kind == "container" and s.inner then
				local k, m = 0, 0
				for id, n in pairs(Hold.totals(s.inner)) do k, m = k + n, m + data.items[id].mass * n end
				hint2 = ("Loaded: %d items, %.1f t   Double-click to open"):format(k, m)
			else hint2 = "Right-click: actions" end
			if r.side.ship == game.player and ItemUse.usable(s.id) then
				local ok, why = ItemUse.can(game, game.player, s.id)
				local use = "U: " .. ItemUse.label(s.id) .. (ok and "" or " (" .. why .. ")")
				hint2 = hint2 and (use .. "   " .. hint2) or use
			end
			-- a module is compared with what's fitted where it would go
			local against
			local im = data.modules[s.id]
			if im and game.player then
				local pl = game.player
				for k, slot in ipairs(pl.hull.slots) do
					if data.fits(slot, im) then against = pl.loadout[k] or nil; if against then break end end
				end
			end
			tooltip(item, s.n, mx, my, hint2, price, against)
		end
	end
	-- the open shop menu, over everything else
	if Cargo.shopOpen then
		for _, side in ipairs(L.sides) do
			if side.shops then
				local cur = game:currentShop(side.station)
				local last = side.shops[#side.shops]
				lg.setColor(0.03, 0.07, 0.1, 0.97)
				lg.rectangle("fill", side.shopMenu.x - 2, side.shops[1].y - 2, side.shopMenu.w + 4, last.y + last.h - side.shops[1].y + 4, 5, 5)
				for _, b in ipairs(side.shops) do
					local hot = inRect(b, mx, my)
					lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], b.i == cur and 0.3 or (hot and 0.2 or 0.06))
					lg.rectangle("fill", b.x, b.y, b.w, b.h, 4, 4)
					lg.setFont(HUD.font(14)); lg.setColor(HUD.INK)
					lg.print(b.label, b.x + 10, b.y + 4)
					lg.setFont(HUD.font(12)); lg.setColor(HUD.DIM)
					local d = b.desc or ""
					local f = HUD.font(12)
					while #d > 3 and f:getWidth(d) > b.w - 20 do d = d:sub(1, -5) .. "..." end
					lg.print(d, b.x + 10, b.y + 23)
				end
			end
		end
	end
	drawMenu(game)
end

function Cargo.wheelmoved(game,y)
 if not Cargo.isOpen(game) then return false end
 if game.state=='docked' and Cargo.tab=='hangar' then Hangar.wheelmoved(game,y) end
 if game.state=='docked' and Cargo.tab=='shipyard' then Shipyard.wheelmoved(game,y) end
 if game.state=='docked' and Cargo.tab=='industry' then IndustryView.wheelmoved(game,y) end
 if game.state=='docked' and Cargo.tab=='contracts' or game.state~='docked' and Cargo.spaceTab=='contracts' then Contracts.wheelmoved(game,y) end
 return true
end
Cargo.tabs=TABS
Cargo.tabRects=tabRects
Cargo.layout = layout       -- for the autotest

-- Where toasts go while the screen is up: under the window and its help.
function Cargo.toastY(game)
	local sh = lg.getHeight()
	return sh - 110
end

return Cargo
