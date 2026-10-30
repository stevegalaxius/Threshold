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

-- Where each grid sits on screen. A side's main grid is on top, any
-- further grids (Cargo Pods) in a row underneath. One cell size for
-- everything, as big as fits.
local function layout(game)
	local sw, sh = lg.getDimensions()
	local list = sides(game)
	if #list == 0 then return nil end
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
	local cs = 30
	while cs > 6 do
		local tw, th = 0, 0
		for i, side in ipairs(list) do
			local w, h = size(side, cs)
			tw, th = tw + w + PAD * 2 + (i > 1 and GAP or 0), max(th, h)
		end
		if tw <= sw - 32 and th + HEAD + PAD * 2 + 120 <= sh then break end
		cs = cs - 1
	end
	local L = { cs = cs, sides = list, grids = {} }
	local tw, th = 0, 0
	for i, side in ipairs(list) do
		side.w, side.h = size(side, cs)
		tw, th = tw + side.w + PAD * 2 + (i > 1 and GAP or 0), max(th, side.h)
	end
	local x = floor((sw - tw) / 2)
	local y = max(60, floor((sh - th - HEAD - PAD * 2 - 60) / 2))
	for _, side in ipairs(list) do
		side.x, side.y, side.pw, side.ph = x, y, side.w + PAD * 2, th + HEAD + PAD * 2
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
	L.bottom = y + th + HEAD + PAD * 2
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
	for _, side in ipairs(L.sides) do
		if mx >= side.x and mx < side.x + side.pw and my >= side.y and my < side.y + side.ph then return side end
	end
end

-- After any change to a ship's hold: the cargo counts, mass and HUD follow.
local function changed(side)
	if side and side.ship then
		side.ship.cargo = Hold.totals(side.hold)
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
	local left = h.n - Hold.add(f.hold, h.id, h.n)
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
	local r, cx, cy = cellAt(L, mx, my)
	local s = r and Grid.at(r.g, cx, cy)
	if not s then return true end
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
		hint = "Drag to move   R rotate   Shift-drag split   Ctrl-click move across   Right-click unbox a crate   E, Enter or (A) launch"
	else
		hint = "Drag to move   R rotate   Shift-drag split   Right-click or drag out to eject   Tab or Esc close"
	end
	lg.printf(("Mass %.0f t"):format(p.body:getMass()), 0, L.bottom + 10, sw, "center")
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
		drawStack(data.items[h.id], h.n, mx - h.dx * cs - cs / 2, my - h.dy * cs - cs / 2, h.w * cs, h.h * cs, cs, 0.85)
	else
		local r, cx, cy = cellAt(L, mx, my)
		local s = r and Grid.at(r.g, cx, cy)
		if s then
			local item = data.items[s.id]
			local hint2
			if docked and item.kind == "crate" then hint2 = "Right-click: unbox into loose rounds"
			elseif not docked then hint2 = "Right-click: eject" end
			tooltip(item, s.n, mx, my, hint2)
		end
	end
end

Cargo.layout = layout       -- for the autotest

return Cargo
