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
	            to your hold. Take All, Ctrl-click or right-click takes;
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
	  right-click     quick move to the other panel, like Ctrl-click; in
	                  space with just your hold up: eject the stack out
	                  behind the ship
	  double-click    docked: unbox an ammo crate into loose rounds
	  drop outside    in space: eject it
	  Sort            tidy a hold (biggest items first, grouped by type)

	Anything you're holding when the screen closes goes back where it came
	from.
]]

local data = require("src.data")
local Ship = require("src.ship")
local Grid = require("src.inventory.grid")
local Hold = require("src.inventory.hold")
local Shapes = require("src.inventory.shapes")
local HullShape = require("src.hullshape")
local HUD = require("src.hud")
local Game = require("src.game")
local Hangar = require("src.ui.hangar")
local stats = require("src.stats")
local T = require("src.tuning")

local Cargo = { open = false, loot = nil, tab = "cargo", other = nil, filter = "all", marketLeft = "hold" }

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
		Cargo.trade = Hold.new({ { key = "trade", name = "Trade", w = T.tradeW, h = T.tradeH } })
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
		if Cargo.tab == "market" then
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
		table.insert(list, { title = e.kind == "husk" and "Wreck" or "Container", hold = e.hold, entity = e })
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
		if parent then
			table.insert(list, { title = "Container", hold = c, innerOf = c, parent = parent })
		elseif not (Cargo.hand and Cargo.hand.inner == c) then
			Cargo.inner = nil
		end
	end
	return list
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
	local item, m = data.items[id], data.modules[id]
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
	local showEquip = #list < 3
	local eh = showEquip and (HEAD + HULL_H + #p.hull.slots * ROW + PAD) or 0
	local function size(side, cs)
		local g1 = side.hold.grids[1]
		local w, rowW, rowH = g1.w * cs, 0, 0
		for i = 2, #side.hold.grids do
			local g = side.hold.grids[i]
			rowW = rowW + (i > 2 and GAP or 0) + g.w * cs
			rowH = max(rowH, g.h * cs)
		end
		local h = 18 + g1.h * cs + (rowH > 0 and (24 + rowH) or 0) + (side.trade and 118 or 0)
		return max(w, rowW, (side.innerOf or side.parked) and 380 or (side.entity or side.station) and 340 or 300), h
	end
	-- Panels stand in columns, one each, except at the market, where storage
	-- sits under your hold.
	local cols = {}
	for _, side in ipairs(list) do
		if side.storage and Cargo.tab == "market" and #cols > 0 then table.insert(cols[#cols], side)
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
	local cs = 30
	while cs > 6 do
		local tw, ph = measure(cs)
		if tw <= sw - 32 and ph + 190 <= sh then break end
		cs = cs - 1
	end
	local L = { cs = cs, sides = list, grids = {} }
	local tw, ph = measure(cs)
	for _, side in ipairs(list) do side.w, side.h = size(side, cs) end
	local x = floor((sw - tw) / 2)
	local y = max(80, floor((sh - ph - 50) / 2))

	-- Equipment: the hull outline with numbered hardpoints, then a row per slot.
	local E = { x = x, y = y, pw = EW, ph = ph, slots = {}, hidden = not showEquip }
	E.hull = { x = x + PAD, y = y + HEAD, w = EW - PAD * 2, h = HULL_H - 16 }
	if showEquip then
		for i, slot in ipairs(p.hull.slots) do
			table.insert(E.slots, { i = i, slot = slot, x = x + PAD, y = y + HEAD + HULL_H + (i - 1) * ROW, w = EW - PAD * 2, h = ROW - 4 })
		end
		x = x + EW + GAP
	else
		E.pw, E.ph = 0, 0
	end
	L.equip = E

	for _, col in ipairs(cols) do
		local cw = column(col, cs)
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
		if side.trade or side.market then side.sort = nil end
		if side.trade then
			local by = y + side.ph - PAD - 26
			side.clear = { x = x + PAD, y = by, w = 70, h = 26 }
			side.complete = { x = x + side.pw - PAD - 150, y = by, w = 150, h = 26 }
		end
		if side.pick then
			-- the market's left panel: Hold / Storage tabs in place of the title
			side.picks = {
				{ id = "hold", label = "Your hold", x = x + PAD, y = y + 10, w = 96, h = 24 },
				{ id = "storage", label = "Storage", x = x + PAD + 100, y = y + 10, w = 84, h = 24 },
			}
		end
		if side.market then
			-- filter buttons along the grid's label row
			side.filters = {}
			local fx = x + PAD
			for _, f in ipairs(FILTERS) do
				local fw = HUD.font(11):getWidth(f.label) + 12
				table.insert(side.filters, { id = f.id, label = f.label, x = fx, y = y + HEAD - 2, w = fw, h = 17 })
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
		local gx, gy = x + PAD, y + HEAD + 18
		local g1 = side.hold.grids[1]
		table.insert(L.grids, { side = side, g = g1, x = gx, y = gy, label = g1.name })
		local rx, ry = gx, gy + g1.h * cs + 24
		for i = 2, #side.hold.grids do
			local g = side.hold.grids[i]
			table.insert(L.grids, { side = side, g = g, x = rx, y = ry, label = g.name })
			rx = rx + g.w * cs + GAP
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
	local st = Cargo.tradeStation
	if not st then return end
	if s.owner == "station" then
		local shelf = game:stationMarket(st).hold
		local c = { id = s.id, n = s.n, inner = s.inner, resale = s.resale, wear = s.wear }
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
			if s.owner == "station" and not s.resale then out[s.id] = (out[s.id] or 0) + s.n end
		end
	end
	return out
end

-- Put a stack on the trade grid; true if there was room.
local function toTrade(L, r, s)
	local trade
	for _, side in ipairs(L.sides) do if side.trade then trade = side end end
	local c = { id = s.id, n = s.n, inner = s.inner, resale = s.resale, wear = s.wear, owner = r.side.market and "station" or "player" }
	if not Hold.placeStack(trade.hold, c) then return false end
	Grid.remove(r.g, s)
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
		Grid.place(f.grid, { id = h.id, n = h.n, x = f.x, y = f.y, w = fw, h = fh, rot = h.rot0, inner = h.inner,
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
	if st and Cargo.tab == "market" then
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
local TABS = { { id = "cargo", label = "Cargo" }, { id = "hangar", label = "Hangar" }, { id = "market", label = "Market" } }
function tabRects(game)
	local left, right, top
	if Cargo.tab == "hangar" then
		local H = Hangar.layout(game)
		if H then left, right, top = H.x, H.x + H.w, H.y end
	else
		local L = layout(game)
		if L then
			local last = L.sides[#L.sides]
			left = L.equip.hidden and L.sides[1].x or L.equip.x
			right, top = last.x + last.pw, L.sides[1].y
		end
	end
	if not left then return {} end
	local out, w, h = {}, 110, 28
	local x = floor((left + right - #TABS * (w + 4)) / 2)
	for i, t in ipairs(TABS) do
		out[i] = { id = t.id, label = t.label, x = x + (i - 1) * (w + 4), y = top - h, w = w, h = h }
	end
	return out
end

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
	if Cargo.tab == "market" and game.state == "docked" then
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

-- Double-click on a crate at a station: unbox as many rounds as fit.
local function unbox(game, r, s)
	local item = data.items[s.id]
	if item.kind ~= "crate" then return end
	local k = Hold.room(r.side.hold, item.ammo, s.n)
	if k == 0 then game:toast("NO ROOM TO UNBOX", 1.2) return end
	s.n = s.n - k
	if s.n <= 0 then Grid.remove(r.g, s) end
	Hold.add(r.side.hold, item.ammo, k)
	changed(r.side)
	game:toast(("Unboxed %d %s"):format(k, data.items[item.ammo].name), 1.2, "pickup")
end

-- Equipment ------------------------------------------------------------------

local function slotAt(L, mx, my)
	for _, r in ipairs(L.equip.slots) do
		if inRect(r, mx, my) then return r end
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

-- mods: { ctrl, shift } to stand in for the keyboard (the autotest uses it).
function Cargo.mousepressed(game, mx, my, button, mods)
	if not Cargo.isOpen(game) then return false end
	if game.state == "docked" and not Cargo.hand then
		for _, t in ipairs(tabRects(game)) do
			if button == 1 and inRect(t, mx, my) then Cargo.tab = t.id; Hangar.cancel() return true end
		end
		if Cargo.tab == "hangar" then
			local act = Hangar.mousepressed(game, mx, my, button)
			if act and act.fly then
				Cargo.other = nil
				game:flyFromHangar(act.fly)
			elseif act and act.cargo then
				Cargo.other, Cargo.tab = act.cargo, "cargo"
			elseif act and act.sell then
				local st = game.player.dockState.station
				local rec = game:hangar(st)[act.sell]
				local paid, why = game:sellShip(st, act.sell)
				if paid then
					if Cargo.other == rec then Cargo.other = nil end
					game:toast(("SOLD FOR %d CR"):format(paid), 1.4)
				else game:toast(why, 1.4) end
			elseif act and act.buy then
				local rec, why = game:buyShip(game.player.dockState.station, act.buy)
				if rec then Hangar.sel = rec; game:toast("SHIP PARKED IN THE HANGAR", 1.4)
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
		for _, f in ipairs(side.filters or {}) do
			if button == 1 and inRect(f, mx, my) then Cargo.filter = f.id return true end
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
	if er and button == 1 then takeFromSlot(game, L, er) return true end
	local r, cx, cy = cellAt(L, mx, my)
	local s = r and Grid.at(r.g, cx, cy)
	if not s then return true end
	-- double-click a module to fit it
	local now = love.timer.getTime()
	-- (the first click picks the stack up and puts it back as a new one,
	-- so match by place and item, not by the stack itself)
	local c = Cargo.lastClick
	local double = c and c.g == r.g and c.x == s.x and c.y == s.y and c.id == s.id and now - c.t < 0.35
	Cargo.lastClick = { g = r.g, x = s.x, y = s.y, id = s.id, t = now }
	if double and Cargo.tab == "market" and game.state == "docked" then double = false end   -- no opening or fitting at the market
	if button == 1 and double and data.items[s.id].kind == "container" then
		if s.inner then Cargo.inner = s.inner else game:toast("IT'S EMPTY", 1) end
		return true
	end
	if button == 1 and double and data.items[s.id].kind == "crate" and game.state == "docked" then
		unbox(game, r, s)
		return true
	end
	if button == 1 and double and data.items[s.id].kind == "module" then
		if game.state == "docked" then quickFit(game, L, r, s) else game:toast("DOCK AT A STATION TO REFIT", 1.4) end
		return true
	end
	local ctrl = mods and mods.ctrl or love.keyboard.isDown("lctrl", "rctrl")
	local shift = mods and mods.shift or love.keyboard.isDown("lshift", "rshift")
	local atMarket = Cargo.tab == "market" and game.state == "docked"
	if button == 2 and (#L.sides > 1 or atMarket) then
		quickMove(game, L, r, s)                   -- right-click: to the other panel
	elseif button == 2 and game.state ~= "docked" then
		Grid.remove(r.g, s)                        -- just your hold, in space: eject it
		changed(r.side)
		game:eject(r.side.ship, s.id, s.n, s.inner)
	elseif button == 1 and ctrl then
		quickMove(game, L, r, s)
	elseif button == 1 then
		local take = s.n
		if shift and s.n > 1 then take = floor(s.n / 2) end
		local hand = {
			id = s.id, n = take, w = s.w, h = s.h, rot = s.rot, w0 = s.w, h0 = s.h, rot0 = s.rot, inner = s.inner,
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
		Grid.place(r.g, { id = h.id, n = h.n, x = x, y = y, w = h.w, h = h.h, rot = h.rot, inner = h.inner,
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

function Cargo.keypressed(game, key)
	if key == "tab" and game.state == "docked" then
		if not Cargo.hand then
			for i, t in ipairs(TABS) do
				if t.id == Cargo.tab then Cargo.tab = (TABS[i + 1] or TABS[1]).id; break end
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
	if key == "escape" and game.state ~= "docked" then Cargo.close(game); return true end
	if key == "e" and Cargo.loot then Cargo.close(game); return true end
	return false
end

-- Drawing ------------------------------------------------------------------

-- tag (at the market): { color, frame = draw a frame in that color (whose
-- it is, on the trade grid) }. Prices are in the tooltip.
local function drawStack(item, n, x, y, w, h, cs, alpha, tag)
	local c = HUD.itemColor(item)
	lg.setColor(c[1], c[2], c[3], 0.32 * alpha)
	lg.rectangle("fill", x + 2, y + 2, w - 4, h - 4, 3, 3)
	lg.setColor(c[1], c[2], c[3], 0.95 * alpha)
	lg.setLineWidth(1)
	lg.rectangle("line", x + 2.5, y + 2.5, w - 5, h - 5, 3, 3)
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
local function tooltip(item, n, mx, my, hint, price)
	local _, _, cap = Shapes.of(item.id)
	local lines = {
		item.name .. (item.maker and ("  \194\183  " .. item.maker) or ""),
		("%d / %d per stack    %.2f m3    %.2f t"):format(n, cap, item.volume * n, item.mass * n),
	}
	if price then table.insert(lines, price) end
	if hint then table.insert(lines, hint) end
	local f = HUD.font(12)
	lg.setFont(f)
	local w = 0
	for _, l in ipairs(lines) do w = max(w, f:getWidth(l)) end
	w = w + 20
	local h = #lines * 16 + 12
	local sw, sh = lg.getDimensions()
	local x, y = min(mx + 18, sw - w - 4), min(my + 18, sh - h - 4)
	lg.setColor(0.02, 0.06, 0.09, 0.95)
	lg.rectangle("fill", x, y, w, h, 6, 6)
	lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.5)
	lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 6, 6)
	for i, l in ipairs(lines) do
		lg.setColor(i == 1 and HUD.INK or (price and i == 3) and PRICE or HUD.DIM)
		lg.print(l, x + 10, y + 6 + (i - 1) * 16)
	end
end

local SLOT_LABEL = { primary = "PRIMARY", secondary = "SECONDARY", auxiliary = "AUXILIARY", engine = "ENGINE",
	reactor = "REACTOR", utility = "UTILITY", thruster = "THRUSTER", computer = "COMPUTER" }

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
	local a = handling(p.hull, before, p.cargoMass + (h.from.slot and 0 or data.items[h.id].mass))
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
	HUD.panel(E.x, E.y, E.pw, E.ph)
	lg.setFont(HUD.font(16))
	lg.setColor(HUD.INK)
	lg.print("Equipment", E.x + PAD, E.y + 12)
	if not docked then
		lg.setFont(HUD.font(11))
		lg.setColor(HUD.DIM)
		lg.printf("dock to refit", E.x, E.y + 16, E.pw - PAD, "right")
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
		if r.slot.x then
			local sx, sy = ox + r.slot.x * sc, oy + (r.slot.y or 0) * sc
			local fits = hm and data.fits(r.slot, hm)
			local col = fits and { 0.4, 1, 0.55 } or HUD.AQUA
			lg.setColor(0.02, 0.06, 0.09, 0.9)
			lg.circle("fill", sx, sy, 7)
			lg.setColor(col[1], col[2], col[3], (hover == r or fits) and 1 or 0.7)
			lg.circle("line", sx, sy, 7)
			lg.printf(r.i, sx - 7, sy - 6, 14, "center")
		end
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
		lg.print((r.slot.x and (r.i .. "  ") or "") .. slotLabel(r.slot), r.x + 6, r.y + 2)
		lg.setFont(HUD.font(12))
		if m then
			lg.setColor(HUD.INK[1], HUD.INK[2], HUD.INK[3], alpha)
			lg.print(m.name, r.x + 6, r.y + 12)
		else
			lg.setColor(HUD.WARN[1], HUD.WARN[2], HUD.WARN[3], 0.8 * alpha)
			lg.print("empty", r.x + 6, r.y + 12)
		end
	end
end

-- Folder tabs sitting on the top edge of the window.
function drawTabs(game, mx, my)
	lg.setFont(HUD.font(14))
	for _, t in ipairs(tabRects(game)) do
		local on = Cargo.tab == t.id
		lg.setColor(0.02, 0.06, 0.09, 0.92)
		lg.rectangle("fill", t.x, t.y, t.w, t.h + 6, 6, 6)
		lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], on and 0.4 or (inRect(t, mx, my) and 0.22 or 0.1))
		lg.rectangle("fill", t.x, t.y, t.w, t.h + 6, 6, 6)
		lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], on and 0.8 or 0.35)
		lg.rectangle("line", t.x + 0.5, t.y + 0.5, t.w - 1, t.h + 5, 6, 6)
		lg.setColor(on and HUD.INK or HUD.DIM)
		lg.printf(t.label, t.x, t.y + 6, t.w, "center")
	end
end

-- The trade grid's totals and buttons, under the grid.
function drawTrade(game, L, side, mx, my)
	local get, pay = Game.tradeTotals(side.hold)
	local credits = game.universe.credits
	local x, w = side.x + PAD, side.pw - PAD * 2
	local y = side.y + HEAD + 18 + side.hold.grids[1].h * L.cs + 10
	lg.setFont(HUD.font(13))
	local function row(label, value, color, k)
		lg.setColor(HUD.DIM)
		lg.print(label, x, y + k * 19)
		lg.setColor(color)
		lg.printf(value, x, y + k * 19, w, "right")
	end
	row("You get", "+" .. HUD.credits(get), MINE, 0)
	row("You pay", "-" .. HUD.credits(pay), THEIRS, 1)
	local after = credits + get - pay
	row("Balance", HUD.credits(credits) .. "  ->  " .. HUD.credits(after), after < 0 and HUD.WARN or HUD.INK, 2)
	local problem = (get + pay > 0 or #side.hold.grids[1].stacks > 0) and game:tradeProblem(side.station, side.hold)
	if problem then
		lg.setColor(HUD.WARN)
		lg.printf(problem, x, y + 3 * 19, w, "right")
	end
	local c, cl = side.complete, side.clear
	local empty = #side.hold.grids[1].stacks == 0
	local ok = not empty and not problem
	lg.setColor(0.3, 1, 0.5, ok and (not Cargo.hand and inRect(c, mx, my) and 0.45 or 0.25) or 0.07)
	lg.rectangle("fill", c.x, c.y, c.w, c.h, 5, 5)
	lg.setColor(ok and HUD.INK or HUD.DIM)
	lg.printf("Complete trade", c.x, c.y + 5, c.w, "center")
	lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], (not empty and not Cargo.hand and inRect(cl, mx, my)) and 0.35 or 0.15)
	lg.rectangle("fill", cl.x, cl.y, cl.w, cl.h, 5, 5)
	lg.setColor(empty and HUD.DIM or HUD.INK)
	lg.printf("Clear", cl.x, cl.y + 5, cl.w, "center")
end

function Cargo.draw(game)
	if not Cargo.isOpen(game) then return end
	local L = layout(game)
	if not L then return end
	local cs = L.cs
	local sw, sh = lg.getDimensions()
	local mx, my = love.mouse.getPosition()
	local docked = game.state == "docked"
	local market = docked and Cargo.tab == "market"

	lg.setColor(0, 0, 0, docked and 0.55 or 0.3)
	lg.rectangle("fill", 0, 0, sw, sh)

	if docked then
		drawTabs(game, mx, my)
		if Cargo.tab == "hangar" then
			Hangar.draw(game, mx, my)
			lg.setFont(HUD.font(13))
			lg.setColor(HUD.DIM)
			local H = Hangar.layout(game)
			lg.printf("Click a ship to select   Drag to move, R rotate   Double-click or Fly to swap ships   Cargo opens its hold   Sell / Buy trade ships   Tab switch tabs   E launch",
				0, H and (H.y + H.h + 12) or (sh - 40), sw, "center")
			return
		end
	end

	drawEquipment(game, L, mx, my)

	for _, side in ipairs(L.sides) do
		HUD.panel(side.x, side.y, side.pw, side.ph)
		if side.picks then
			for _, pk in ipairs(side.picks) do
				local on = Cargo.marketLeft == pk.id
				lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], on and 0.4 or (not Cargo.hand and inRect(pk, mx, my) and 0.22 or 0.1))
				lg.rectangle("fill", pk.x, pk.y, pk.w, pk.h, 5, 5)
				lg.setFont(HUD.font(14))
				lg.setColor(on and HUD.INK or HUD.DIM)
				lg.printf(pk.label, pk.x, pk.y + 4, pk.w, "center")
			end
		else
			lg.setFont(HUD.font(16))
			lg.setColor(HUD.INK)
			lg.print(side.title, side.x + PAD, side.y + 12)
		end
		local used, total = Hold.cells(side.hold)
		lg.setFont(HUD.font(12))
		lg.setColor(HUD.DIM)
		if side.market then
			lg.setColor(HUD.INK)
			lg.printf(HUD.credits(game.universe.credits), side.x, side.y + 16, side.pw - PAD, "right")
		elseif side.picks then
			-- (the tabs take the title's place: the fill goes on the grid's label row)
			lg.printf(("%d / %d m3"):format(used, total), side.x, side.y + HEAD + 1, side.pw - PAD, "right")
		elseif not side.trade then
			lg.printf(("%d / %d m3"):format(used, total), side.x, side.y + 16,
				side.pw - PAD - (side.close and 176 or (side.take or side.switch) and 148 or 66), "right")
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
		if not r.side.market then lg.print(("%s  %d x %d"):format(r.label, r.g.w, r.g.h), r.x, r.y - 17) end
		lg.setColor(0, 0, 0, 0.35)
		lg.rectangle("fill", r.x, r.y, r.g.w * cs, r.g.h * cs)
		lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.12)
		lg.setLineWidth(1)
		for cy = 0, r.g.h - 1 do
			for cx = 0, r.g.w - 1 do lg.rectangle("line", r.x + cx * cs + 0.5, r.y + cy * cs + 0.5, cs - 1, cs - 1) end
		end
		for _, s in ipairs(r.g.stacks) do
			local tag = market and marketTag(r.side, s)
			local alpha = (r.side.market and Cargo.filter ~= "all" and filterOf(s.id) ~= Cargo.filter) and 0.25 or 1
			drawStack(data.items[s.id], s.n, r.x + s.x * cs, r.y + s.y * cs, s.w * cs, s.h * cs, cs, alpha, tag)
		end
	end

	-- Status and help along the bottom.
	local p = game.player
	lg.setFont(HUD.font(13))
	lg.setColor(HUD.INK)
	local hint
	if market then
		hint = "Drag goods onto the trade grid   Ctrl-click or right-click move across   Shift-drag split   Complete trade to settle   Tab switch tabs   E launch"
	elseif docked then
		hint = "Drag to move   R rotate   Shift-drag split   Ctrl-click or right-click move across   Drag or double-click a module to fit it   Double-click unbox a crate   E, Enter or (A) launch"
	else
		hint = "Drag to move   R rotate   Shift-drag split   Right-click or drag out to eject   Tab or Esc close"
		if Cargo.loot then hint = "Drag to move   R rotate   Shift-drag split   Ctrl-click or right-click take   Take All   E, Tab or Esc close" end
	end
	local problem = docked and Ship.launchProblem(p)
	if problem then
		lg.setColor(HUD.WARN)
		lg.printf(("Mass %.0f t      Can't launch: %s"):format(p.body:getMass(), problem), 0, L.bottom + 10, sw, "center")
	else
		lg.printf(("Mass %.0f t"):format(p.body:getMass()), 0, L.bottom + 10, sw, "center")
	end
	lg.setColor(HUD.DIM)
	lg.printf(hint, 0, L.bottom + 30, sw, "center")

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
		drawStack(data.items[h.id], h.n, mx - h.dx * cs - cs / 2, my - h.dy * cs - cs / 2, h.w * cs, h.h * cs, cs, 0.85,
			market and marketTag(h.side, h, h.owner))
	else
		local er = slotAt(L, mx, my)
		local fitted = er and p.loadout[er.i]
		if fitted then
			tooltip(data.items[fitted], 1, mx, my, docked and "Drag to the hold to unfit" or "Dock at a station to refit")
		end
		local r, cx, cy = cellAt(L, mx, my)
		local s = r and Grid.at(r.g, cx, cy)
		if s then
			local item = data.items[s.id]
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
			elseif docked and item.kind == "crate" then hint2 = "Double-click: unbox into loose rounds"
			elseif item.kind == "container" and s.inner then
				local k, m = 0, 0
				for id, n in pairs(Hold.totals(s.inner)) do k, m = k + n, m + data.items[id].mass * n end
				hint2 = ("Loaded: %d items, %.1f t   Double-click to open"):format(k, m)
			elseif r.side.entity or r.side.innerOf then hint2 = "Right-click: take"
			elseif not docked and #L.sides == 1 then hint2 = "Right-click: eject" end
			tooltip(item, s.n, mx, my, hint2, price)
		end
	end
end

Cargo.layout = layout       -- for the autotest

-- Where toasts go while the screen is up: under the window and its help.
function Cargo.toastY(game)
	local sh = lg.getHeight()
	if game.state == "docked" and Cargo.tab == "hangar" then return sh - 110 end
	local L = layout(game)
	return L and min(L.bottom + 54, sh - 60) or sh - 110
end

return Cargo
