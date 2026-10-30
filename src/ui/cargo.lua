--[[
	The cargo screen: your hold's grids, laid out so you can move things by
	hand. Two ways in:

	  docked    opens by itself; your hold on the left, this station's
	            storage on the right. E, Enter or (A) launches.
	  in space  Tab opens and closes it (Esc closes too). Just your hold.
	            The game keeps running, and you can still fly with the keys.

	Mouse:
	  drag            pick up a stack and drop it somewhere else; dropping
	                  on a part-full stack of the same item tops it up
	  R (dragging)    rotate
	  Shift-drag      take half the stack
	  Ctrl-click      quick move to the other side (docked)
	  right-click     in space: eject the stack out behind the ship
	                  docked: unbox an ammo crate into loose rounds
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
local HUD = require("src.hud")
local stats = require("src.stats")
local T = require("src.tuning")

local Cargo = { open = false }

local lg = love.graphics
local floor, max, min = math.floor, math.max, math.min

local GAP, PAD, HEAD = 16, 14, 40

-- Is the screen up?
function Cargo.isOpen(game)
	if game.state == "docked" then return true end
	return Cargo.open and game.player and not game.player.dead
end

-- The holds on show: { title, hold, ship (if it's a ship's hold) }.
local function sides(game)
	local p = game.player
	if not p or p.dead or not p.hold then return {} end
	local list = { { title = "Your hold \194\183 " .. p.hull.name, hold = p.hold, ship = p } }
	if game.state == "docked" and p.dockState then
		table.insert(list, { title = "Station storage", hold = game:stationStorage(p.dockState.station), storage = true })
	end
	return list
end

-- Where everything sits on screen: the equipment panel on the left, then
-- each hold. A side's main grid is on top, any further grids (Cargo Pods)
-- in a row underneath. One cell size for every grid, as big as fits.
local EW, ROW, HULL_H = 260, 30, 110

local function layout(game)
	local sw, sh = lg.getDimensions()
	local list = sides(game)
	if #list == 0 then return nil end
	local p = game.player
	local eh = HEAD + HULL_H + #p.hull.slots * ROW + PAD
	local function size(side, cs)
		local g1 = side.hold.grids[1]
		local w, rowW, rowH = g1.w * cs, 0, 0
		for i = 2, #side.hold.grids do
			local g = side.hold.grids[i]
			rowW = rowW + (i > 2 and GAP or 0) + g.w * cs
			rowH = max(rowH, g.h * cs)
		end
		local h = 18 + g1.h * cs + (rowH > 0 and (24 + rowH) or 0)
		return max(w, rowW, 300), h
	end
	local function measure(cs)
		local tw, th = EW + GAP, 0
		for i, side in ipairs(list) do
			local w, h = size(side, cs)
			tw, th = tw + w + PAD * 2 + (i > 1 and GAP or 0), max(th, h)
		end
		return tw, max(th + HEAD + PAD * 2, eh)
	end
	local cs = 30
	while cs > 6 do
		local tw, ph = measure(cs)
		if tw <= sw - 32 and ph + 100 <= sh then break end
		cs = cs - 1
	end
	local L = { cs = cs, sides = list, grids = {} }
	local tw, ph = measure(cs)
	for _, side in ipairs(list) do side.w, side.h = size(side, cs) end
	local x = floor((sw - tw) / 2)
	local y = max(56, floor((sh - ph - 50) / 2))

	-- Equipment: the hull outline with numbered hardpoints, then a row per slot.
	local E = { x = x, y = y, pw = EW, ph = ph, slots = {} }
	E.hull = { x = x + PAD, y = y + HEAD, w = EW - PAD * 2, h = HULL_H - 16 }
	for i, slot in ipairs(p.hull.slots) do
		table.insert(E.slots, { i = i, slot = slot, x = x + PAD, y = y + HEAD + HULL_H + (i - 1) * ROW, w = EW - PAD * 2, h = ROW - 4 })
	end
	L.equip = E
	x = x + EW + GAP

	for _, side in ipairs(list) do
		side.x, side.y, side.pw, side.ph = x, y, side.w + PAD * 2, ph
		side.sort = { x = x + side.pw - PAD - 56, y = y + 12, w = 56, h = 22 }
		local gx, gy = x + PAD, y + HEAD + 18
		local g1 = side.hold.grids[1]
		table.insert(L.grids, { side = side, g = g1, x = gx, y = gy, label = g1.name })
		local rx, ry = gx, gy + g1.h * cs + 24
		for i = 2, #side.hold.grids do
			local g = side.hold.grids[i]
			table.insert(L.grids, { side = side, g = g, x = rx, y = ry, label = g.name })
			rx = rx + g.w * cs + GAP
		end
		x = x + side.pw + GAP
	end
	L.bottom = y + ph
	return L
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
local function changed(side)
	if side and side.ship then
		side.ship.cargo = Hold.totals(side.ship.hold)    -- a refit can swap the hold table
		Ship.updateMass(side.ship)
	end
end

local function sideOf(L, hold)
	for _, side in ipairs(L.sides) do
		if side.hold == hold then return side end
	end
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
		Grid.place(f.grid, { id = h.id, n = h.n, x = f.x, y = f.y, w = fw, h = fh, rot = h.rot0 })
		return
	end
	local hold = (h.side and h.side.ship) and h.side.ship.hold or f.hold
	local left = h.n - Hold.add(hold, h.id, h.n)
	local p = game.player
	if left > 0 and p and p.dockState and p.dockState.done then
		left = left - Hold.add(game:stationStorage(p.dockState.station), h.id, left)
	end
	if left > 0 and p and not p.dead then game:eject(p, h.id, left) end
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
	Cargo.open = false
end

-- Called every frame: tidy up if the screen went away under us (undocked,
-- died) while something was in hand.
function Cargo.update(game)
	if Cargo.hand and not Cargo.isOpen(game) then
		local h = Cargo.hand
		returnHand(game)
		changed(h.side)
	end
	if game.state == "dead" then Cargo.open = false end
end

-- Mouse ------------------------------------------------------------------

local function inRect(r, x, y)
	return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

-- Ctrl-click: send a stack to the other side.
local function quickMove(game, L, r, s)
	local other
	for _, side in ipairs(L.sides) do
		if side ~= r.side then other = side end
	end
	if not other then return end
	local k = Hold.add(other.hold, s.id, s.n)
	if k == 0 then game:toast("NO ROOM", 1) return end
	s.n = s.n - k
	if s.n <= 0 then Grid.remove(r.g, s) end
	changed(r.side); changed(other)
end

-- Right-click on a crate at a station: unbox as many rounds as fit.
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
	local L = layout(game)
	if not L then return true end
	if Cargo.hand then return true end
	for _, side in ipairs(L.sides) do
		if button == 1 and inRect(side.sort, mx, my) then
			if not Hold.sort(side.hold) then game:toast("CAN'T SORT: IT WOULDN'T ALL FIT", 1.4) end
			changed(side)
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
	if button == 1 and double and data.items[s.id].kind == "module" then
		if game.state == "docked" then quickFit(game, L, r, s) else game:toast("DOCK AT A STATION TO REFIT", 1.4) end
		return true
	end
	local ctrl = mods and mods.ctrl or love.keyboard.isDown("lctrl", "rctrl")
	local shift = mods and mods.shift or love.keyboard.isDown("lshift", "rshift")
	if button == 2 then
		if game.state == "docked" then
			unbox(game, r, s)
		else
			Grid.remove(r.g, s)
			changed(r.side)
			game:eject(r.side.ship, s.id, s.n)
		end
	elseif button == 1 and ctrl then
		quickMove(game, L, r, s)
	elseif button == 1 then
		local take = s.n
		if shift and s.n > 1 then take = floor(s.n / 2) end
		local hand = {
			id = s.id, n = take, w = s.w, h = s.h, rot = s.rot, w0 = s.w, h0 = s.h, rot0 = s.rot,
			dx = cx - s.x, dy = cy - s.y, side = r.side,
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
	local target = Grid.at(r.g, cx, cy)
	local _, _, cap = Shapes.of(h.id)
	if target and target.id == h.id and target.n < cap then
		return r, x, y, "merge", target
	end
	return r, x, y, Grid.isFree(r.g, x, y, h.w, h.h) and "place" or "blocked"
end

function Cargo.mousereleased(game, mx, my, button)
	if not Cargo.isOpen(game) then return false end
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
		Grid.place(r.g, { id = h.id, n = h.n, x = x, y = y, w = h.w, h = h.h, rot = h.rot })
		changed(r.side); changed(h.side)
	elseif not r and not overPanel(L, mx, my) and game.state ~= "docked" then
		Cargo.hand = nil
		game:eject(h.side.ship, h.id, h.n)
		changed(h.side)
	else
		finish(game, L)
	end
	return true
end

function Cargo.keypressed(game, key)
	if key == "tab" then Cargo.toggle(game); return true end
	if not Cargo.isOpen(game) then return false end
	if key == "r" and Cargo.hand then
		local h = Cargo.hand
		h.w, h.h, h.rot = h.h, h.w, not h.rot
		h.dx, h.dy = min(h.dy, h.w - 1), min(h.dx, h.h - 1)
		return true
	end
	if key == "escape" and game.state ~= "docked" then Cargo.close(game); return true end
	return false
end

-- Drawing ------------------------------------------------------------------

local function drawStack(item, n, x, y, w, h, cs, alpha)
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
		if w >= cs * 2 then
			lg.printf(item.name, x + 5, y + 4, w - 10, "left")
		end
	end
end

local function tooltip(item, n, mx, my, hint)
	local _, _, cap = Shapes.of(item.id)
	local lines = {
		item.name .. (item.maker and ("  \194\183  " .. item.maker) or ""),
		("%d / %d per stack    %.2f m3    %.2f t"):format(n, cap, item.volume * n, item.mass * n),
	}
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
		lg.setColor(i == 1 and HUD.INK or HUD.DIM)
		lg.print(l, x + 10, y + 6 + (i - 1) * 16)
	end
end

local SLOT_LABEL = { primary = "PRIMARY", secondary = "SECONDARY", auxiliary = "AUXILIARY", engine = "ENGINE",
	reactor = "REACTOR", utility = "UTILITY", thruster = "THRUSTER" }

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
	local pts = {}
	for k = 1, #shape, 2 do
		table.insert(pts, ox + shape[k] * sc)
		table.insert(pts, oy + shape[k + 1] * sc)
	end
	local c = p.color
	lg.setColor(c[1], c[2], c[3], 0.12)
	local ok, tris = pcall(love.math.triangulate, pts)
	if ok then for _, t in ipairs(tris) do lg.polygon("fill", t) end end
	lg.setColor(c[1], c[2], c[3], 0.8)
	lg.setLineWidth(1.5)
	lg.polygon("line", pts)
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

function Cargo.draw(game)
	if not Cargo.isOpen(game) then return end
	local L = layout(game)
	if not L then return end
	local cs = L.cs
	local sw, sh = lg.getDimensions()
	local mx, my = love.mouse.getPosition()
	local docked = game.state == "docked"

	lg.setColor(0, 0, 0, docked and 0.55 or 0.3)
	lg.rectangle("fill", 0, 0, sw, sh)

	drawEquipment(game, L, mx, my)

	for _, side in ipairs(L.sides) do
		HUD.panel(side.x, side.y, side.pw, side.ph)
		lg.setFont(HUD.font(16))
		lg.setColor(HUD.INK)
		lg.print(side.title, side.x + PAD, side.y + 12)
		local used, total = Hold.cells(side.hold)
		lg.setFont(HUD.font(12))
		lg.setColor(HUD.DIM)
		lg.printf(("%d / %d m3"):format(used, total), side.x, side.y + 16, side.pw - PAD - 66, "right")
		local b = side.sort
		local hot = not Cargo.hand and inRect(b, mx, my)
		lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], hot and 0.35 or 0.15)
		lg.rectangle("fill", b.x, b.y, b.w, b.h, 5, 5)
		lg.setColor(HUD.INK)
		lg.printf("Sort", b.x, b.y + 4, b.w, "center")
	end

	for _, r in ipairs(L.grids) do
		lg.setFont(HUD.font(12))
		lg.setColor(HUD.DIM)
		lg.print(("%s  %d x %d"):format(r.label, r.g.w, r.g.h), r.x, r.y - 17)
		lg.setColor(0, 0, 0, 0.35)
		lg.rectangle("fill", r.x, r.y, r.g.w * cs, r.g.h * cs)
		lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.12)
		lg.setLineWidth(1)
		for cy = 0, r.g.h - 1 do
			for cx = 0, r.g.w - 1 do lg.rectangle("line", r.x + cx * cs + 0.5, r.y + cy * cs + 0.5, cs - 1, cs - 1) end
		end
		for _, s in ipairs(r.g.stacks) do
			drawStack(data.items[s.id], s.n, r.x + s.x * cs, r.y + s.y * cs, s.w * cs, s.h * cs, cs, 1)
		end
	end

	-- Status and help along the bottom.
	local p = game.player
	lg.setFont(HUD.font(13))
	lg.setColor(HUD.INK)
	local hint
	if docked then
		hint = "Drag to move   R rotate   Shift-drag split   Ctrl-click move across   Drag or double-click a module to fit it   Right-click unbox a crate   E, Enter or (A) launch"
	else
		hint = "Drag to move   R rotate   Shift-drag split   Right-click or drag out to eject   Tab or Esc close"
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
		drawStack(data.items[h.id], h.n, mx - h.dx * cs - cs / 2, my - h.dy * cs - cs / 2, h.w * cs, h.h * cs, cs, 0.85)
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
			local hint2
			if docked and item.kind == "module" then hint2 = "Drag onto a slot or double-click to fit"
			elseif docked and item.kind == "crate" then hint2 = "Right-click: unbox into loose rounds"
			elseif not docked then hint2 = "Right-click: eject" end
			tooltip(item, s.n, mx, my, hint2)
		end
	end
end

Cargo.layout = layout       -- for the autotest

return Cargo
