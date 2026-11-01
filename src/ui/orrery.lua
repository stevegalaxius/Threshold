--[[
	The mass driver's targeting window: an orrery of the planets where they
	are right now. Fly into a driver's ring and it holds you there and
	opens this; click a planet (or press its number) to pay the fare and
	be fired toward it, or Esc to back out. Distances on the map are on a
	squashed scale (Fields.mapScale) so Mercury and Neptune both fit.

	game.driverMenu = { driver } while it's open (src/transit.lua).
]]

local HUD = require("src.hud")
local Fields = require("src.fields")

local Orrery = {}

local lg = love.graphics
local cos, sin, sqrt, pi = math.cos, math.sin, math.sqrt, math.pi

local function color(id) return Fields.orbits[id] and Fields.orbits[id].color end

function Orrery.isOpen(game) return game.driverMenu ~= nil end

-- Every planet with an orbit, inner to outer.
local function planets()
	local list = {}
	for id in pairs(Fields.orbits) do table.insert(list, id) end
	table.sort(list, function(a, b) return Fields.orbits[a].au < Fields.orbits[b].au end)
	return list
end

-- Where everything goes on screen: the panel, the Sun, each planet's dot
-- and its row in the list.
local function layout(game)
	local w, h = lg.getDimensions()
	local n = #planets()
	local rowH = math.max(40, math.min(54, math.floor((h - 190) / n)))
	local pw, ph = 760, 150 + n * rowH
	local x, y = (w - pw) / 2, (h - ph) / 2
	local R = math.min(220, (ph - 110) / 2)
	local cx, cy = x + 250, y + 70 + R
	local maxAU = 0
	for _, o in pairs(Fields.orbits) do maxAU = math.max(maxAU, o.au) end
	local L = { x = x, y = y, w = pw, h = ph, cx = cx, cy = cy, R = R, items = {} }
	local clock = game.universe.clock
	for i, id in ipairs(planets()) do
		local px, py = Fields.orbitPos(id, clock)
		local au = Fields.orbits[id].au
		local a = math.atan2(py, px)
		local r = R * Fields.mapScale(au)
		local item = { id = id, r = r, dx = cx + cos(a) * r, dy = cy + sin(a) * r, here = id == game.fieldId,
			row = { x = x + 500, y = y + 70 + (i - 1) * rowH, w = 240, h = rowH - 6 }, key = ("1234567890-"):sub(i, i) }
		if not item.here then
			item.au = Fields.distance(game.fieldId, id, clock)
			item.fare = game:driverFare(id)
		end
		table.insert(L.items, item)
	end
	L.cancel = { x = x + 500, y = y + ph - 60, w = 240, h = 40 }
	return L
end

local function inside(r, mx, my) return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h end

local function hovered(L, mx, my)
	for _, it in ipairs(L.items) do
		if not it.here and (inside(it.row, mx, my) or (mx - it.dx) ^ 2 + (my - it.dy) ^ 2 < 14 ^ 2) then return it end
	end
end

function Orrery.draw(game)
	if not game.driverMenu then return end
	local L = layout(game)
	local mx, my = love.mouse.getPosition()
	local hot = hovered(L, mx, my)
	local font = HUD.font
	HUD.panel(L.x, L.y, L.w, L.h)
	lg.setFont(font(16))
	lg.setColor(HUD.AQUA)
	lg.print("MASS DRIVER  -  PICK A TARGET", L.x + 20, L.y + 16)
	lg.setFont(font(12))
	lg.setColor(HUD.DIM)
	lg.print(("credits %s"):format(HUD.credits(game.universe.credits)), L.x + 20, L.y + 40)
	-- the Sun and the orbits
	lg.setColor(1, 0.85, 0.4)
	lg.circle("fill", L.cx, L.cy, 9)
	lg.setLineWidth(1)
	for _, it in ipairs(L.items) do
		lg.setColor(HUD.DIM[1], HUD.DIM[2], HUD.DIM[3], 0.35)
		lg.circle("line", L.cx, L.cy, it.r, 96)
	end
	-- a line to the one you're pointing at
	local here
	for _, it in ipairs(L.items) do if it.here then here = it end end
	if hot and here then
		lg.setColor(HUD.AQUA[1], HUD.AQUA[2], HUD.AQUA[3], 0.6)
		lg.line(here.dx, here.dy, hot.dx, hot.dy)
	end
	for _, it in ipairs(L.items) do
		local c = color(it.id) or HUD.INK
		lg.setColor(c)
		lg.circle("fill", it.dx, it.dy, it == hot and 9 or 7)
		if it.here then
			lg.setColor(HUD.INK)
			lg.circle("line", it.dx, it.dy, 13)
		end
		lg.setFont(font(12))
		lg.setColor(HUD.INK)
		lg.print(Fields[it.id].name, it.dx + 12, it.dy - 7)
		-- its row in the list
		local r = it.row
		local afford = it.fare and game.universe.credits >= it.fare
		lg.setColor(0, 0, 0, it == hot and 0.5 or 0.3)
		lg.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
		lg.setColor(c[1], c[2], c[3], it.here and 0.4 or 1)
		lg.setFont(font(14))
		lg.print(("%s  %s"):format(it.key, Fields[it.id].name), r.x + 10, r.y + 4)
		lg.setFont(font(12))
		if it.here then
			lg.setColor(HUD.DIM)
			lg.print("you are here", r.x + 10, r.y + r.h - 18)
		else
			lg.setColor(afford and HUD.INK or HUD.WARN)
			lg.print(("%.2f AU    %d cr"):format(it.au, it.fare), r.x + 10, r.y + r.h - 18)
		end
	end
	local c = L.cancel
	lg.setColor(0, 0, 0, inside(c, mx, my) and 0.5 or 0.3)
	lg.rectangle("fill", c.x, c.y, c.w, c.h, 6, 6)
	lg.setColor(HUD.INK)
	lg.setFont(font(13))
	lg.printf("Back out  (Esc)", c.x, c.y + 12, c.w, "center")
end

local function choose(game, it)
	if it and not it.here then game:fireDriver(it.id) end
end

function Orrery.mousepressed(game, mx, my, button)
	if not game.driverMenu or button ~= 1 then return false end
	local L = layout(game)
	if inside(L.cancel, mx, my) then game:closeDriverMenu() return true end
	choose(game, hovered(L, mx, my))
	return true
end

function Orrery.keypressed(game, key)
	if not game.driverMenu then return false end
	if key == "escape" then game:closeDriverMenu() return true end
	for _, it in ipairs(layout(game).items) do
		if key == it.key then choose(game, it) return true end
	end
	return true
end

return Orrery
