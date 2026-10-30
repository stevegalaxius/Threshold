--[[
	The Hangar tab of the station screen: the ship you're flying and the
	ships parked at this station. Each parked ship has two buttons:

	  Fly    swap: fly it out, and the ship you're in is parked instead
	  Cargo  the Cargo tab, with that ship's hold where station storage
	         usually is, to move things between your ships

	Hangars are per station and last between levels (src/world.lua).
	The screen only draws and reports clicks; the cargo screen
	(src/ui/cargo.lua) owns the tabs and acts on them.
]]

local data = require("src.data")
local stats = require("src.stats")
local Hold = require("src.inventory.hold")
local HUD = require("src.hud")

local Hangar = {}

local lg = love.graphics
local floor, max, min = math.floor, math.max, math.min

local W, ROW, HEAD, PAD = 640, 58, 48, 16

local function inRect(r, x, y)
	return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

-- Rows and buttons on screen.
local function layout(game)
	local p = game.player
	local st = p and p.dockState and p.dockState.station
	if not st then return nil end
	local list = game:hangar(st)
	local sw, sh = lg.getDimensions()
	local rows = max(1, #list)
	local ph = HEAD + ROW + 34 + rows * ROW + PAD
	local x, y = floor((sw - W) / 2), max(70, floor((sh - ph) / 2))
	local L = { x = x, y = y, w = W, h = ph, station = st, list = list, rows = {} }
	L.current = { x = x + PAD, y = y + HEAD, w = W - PAD * 2, h = ROW - 6 }
	local ry = y + HEAD + ROW + 34
	for i, rec in ipairs(list) do
		local r = { i = i, rec = rec, x = x + PAD, y = ry, w = W - PAD * 2, h = ROW - 6 }
		r.fly = { x = r.x + r.w - 150, y = r.y + 12, w = 64, h = 26 }
		r.cargo = { x = r.x + r.w - 78, y = r.y + 12, w = 70, h = 26 }
		table.insert(L.rows, r)
		ry = ry + ROW
	end
	return L
end

-- Name and a line of numbers for a ship record (or the live ship).
local function describe(rec, live)
	local hull = data.hulls[rec.hull]
	local s = stats.compute(hull, rec.loadout or hull.loadout)
	local armor = live and live.armor or rec.armor or s.armor
	local used, total = 0, s.hold
	if rec.hold then used, total = Hold.cells(rec.hold) end
	local fitted = 0
	for i in ipairs(hull.slots) do
		local id = (rec.loadout or hull.loadout)[i]
		if id then fitted = fitted + 1 end
	end
	return ("%s  \194\183  %s %s"):format(hull.name, hull.maker, hull.class),
		("Armor %d / %d    Hold %d / %d m3    %d of %d slots fitted"):format(armor, s.armor, used, total, fitted, #hull.slots)
end

local function button(r, label, hot, col)
	col = col or HUD.AQUA
	lg.setColor(col[1], col[2], col[3], hot and 0.4 or 0.18)
	lg.rectangle("fill", r.x, r.y, r.w, r.h, 5, 5)
	lg.setColor(HUD.INK)
	lg.printf(label, r.x, r.y + 6, r.w, "center")
end

function Hangar.draw(game, mx, my)
	local L = layout(game)
	if not L then return end
	HUD.panel(L.x, L.y, L.w, L.h)
	lg.setFont(HUD.font(16))
	lg.setColor(HUD.INK)
	lg.print("Hangar \194\183 " .. L.station.name, L.x + PAD, L.y + 14)

	-- the ship you're in
	local p = game.player
	local c = L.current
	lg.setColor(0.3, 1, 0.5, 0.1)
	lg.rectangle("fill", c.x, c.y, c.w, c.h, 5, 5)
	local name, line = describe({ hull = p.hull.id, loadout = p.loadout, hold = p.hold }, p)
	lg.setFont(HUD.font(10))
	lg.setColor(HUD.DIM)
	lg.print("FLYING", c.x + 10, c.y + 6)
	lg.setFont(HUD.font(14))
	lg.setColor(HUD.INK)
	lg.print(name, c.x + 10, c.y + 17)
	lg.setFont(HUD.font(11))
	lg.setColor(HUD.DIM)
	lg.print(line, c.x + 10, c.y + 35)

	lg.setFont(HUD.font(12))
	lg.setColor(HUD.DIM)
	lg.print("Parked here", L.x + PAD, L.y + HEAD + ROW + 12)
	if #L.rows == 0 then
		lg.print("No other ships here yet. (Debug panel, Ship: \"Park a new ship here\")", L.x + PAD + 10, L.y + HEAD + ROW + 44)
	end
	for _, r in ipairs(L.rows) do
		local hot = inRect(r, mx, my)
		lg.setColor(0, 0, 0, 0.35)
		lg.rectangle("fill", r.x, r.y, r.w, r.h, 5, 5)
		lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], hot and 0.45 or 0.25)
		lg.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1, 5, 5)
		local n, l = describe(r.rec)
		lg.setFont(HUD.font(14))
		lg.setColor(HUD.INK)
		lg.print(n, r.x + 10, r.y + 9)
		lg.setFont(HUD.font(11))
		lg.setColor(HUD.DIM)
		lg.print(l, r.x + 10, r.y + 29)
		lg.setFont(HUD.font(12))
		button(r.fly, "Fly", inRect(r.fly, mx, my), { 0.3, 1, 0.5 })
		button(r.cargo, "Cargo", inRect(r.cargo, mx, my))
	end
end

-- What a click asks for: { fly = i }, { cargo = rec } or nil.
function Hangar.mousepressed(game, mx, my)
	local L = layout(game)
	if not L then return nil end
	for _, r in ipairs(L.rows) do
		if inRect(r.fly, mx, my) then return { fly = r.i } end
		if inRect(r.cargo, mx, my) then return { cargo = r.rec } end
	end
	return nil
end

Hangar.layout = layout     -- for the autotest

return Hangar
