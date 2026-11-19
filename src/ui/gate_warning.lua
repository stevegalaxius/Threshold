--[[
	The popup at a wildcat site's gate in (src/sites.lua, a gate piece with
	warning = true): the site's flavour text, and that there's no way back
	until the whole crew is beaten. Held at the breech while it's up, like
	the driver's targeting window (game.driverMenu = { driver, warning }).
	Enter or Engage goes through (Game:engageGate); Esc or Turn back
	drifts you free (Game:closeDriverMenu).
]]
local HUD = require("src.hud")
local lg = love.graphics
local W = {}

function W.isOpen(game) return game.driverMenu ~= nil and game.driverMenu.warning == true end

local function layout()
	local w, h = lg.getDimensions()
	local pw, ph = 560, 300
	local x, y = (w - pw) / 2, (h - ph) / 2
	return { x = x, y = y, w = pw, h = ph,
		engage = { x = x + 24, y = y + ph - 64, w = 240, h = 40 },
		back = { x = x + pw - 264, y = y + ph - 64, w = 240, h = 40 } }
end
local function inside(r, mx, my) return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h end

local function button(r, label, hot, color)
	lg.setColor(color[1], color[2], color[3], hot and 0.35 or 0.15)
	lg.rectangle("fill", r.x, r.y, r.w, r.h, 4, 4)
	lg.setColor(color)
	lg.rectangle("line", r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1, 4, 4)
	lg.printf(label, r.x, r.y + 12, r.w, "center")
end

function W.draw(game)
	if not W.isOpen(game) then return end
	local g = game.driverMenu.driver
	local L = layout()
	local mx, my = love.mouse.getPosition()
	HUD.panel(L.x, L.y, L.w, L.h)
	lg.setFont(HUD.font(16))
	lg.setColor(HUD.WARN)
	lg.print("ACCELERATION GATE  -  " .. (g.name or "GATE"):upper(), L.x + 24, L.y + 18)
	lg.setFont(HUD.font(13))
	lg.setColor(HUD.INK)
	lg.printf(g.warning or "", L.x + 24, L.y + 56, L.w - 48)
	lg.setColor(HUD.WARN)
	lg.printf("There is no way back through this gate. The only way out is past every hostile inside.",
		L.x + 24, L.y + L.h - 124, L.w - 48)
	lg.setFont(HUD.font(13))
	button(L.engage, "ENGAGE  [Enter]", inside(L.engage, mx, my), HUD.WARN)
	button(L.back, "TURN BACK  [Esc]", inside(L.back, mx, my), HUD.AQUA)
end

function W.keypressed(game, key)
	if not W.isOpen(game) then return false end
	if key == "escape" then game:closeDriverMenu()
	elseif key == "return" or key == "kpenter" then game:engageGate() end
	return true
end

function W.mousepressed(game, mx, my, button)
	if not W.isOpen(game) then return false end
	if button ~= 1 then return true end
	local L = layout()
	if inside(L.engage, mx, my) then game:engageGate()
	elseif inside(L.back, mx, my) then game:closeDriverMenu() end
	return true
end

return W
