--[[
	The pause menu. Esc (or Start on a gamepad) stops the game and opens
	it; Esc again, or Resume, carries on. Nothing moves while it's up.

	  1  Resume
	  2  Save           (the F5 quick save)
	  3  Load           (the newest save, like F9)
	  4  Quit           (saves on the way out, like closing the window)
]]

local HUD = require("src.hud")
local Cargo = require("src.ui.cargo")

local Pause = { open = false }

local lg = love.graphics

local function inside(r, mx, my) return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h end

local BUTTONS = {
	{ label = "Resume", run = function(game) Pause.toggle(game) end },
	{ label = "Save", run = function(game)
		Cargo.clearTrade(game)
		Pause.note = game:saveTo("quick") and "Game saved" or "Save failed"
	end },
	{ label = "Load last save", run = function(game)
		Cargo.close(game)
		if game:loadFrom() then Pause.open = false else Pause.note = "Couldn't load a save" end
	end },
	{ label = "Quit to desktop", run = function() love.event.quit() end },
}

local function layout()
	local w, h = lg.getDimensions()
	local pw, ph = 320, 90 + #BUTTONS * 56
	local x, y = (w - pw) / 2, (h - ph) / 2
	local L = { x = x, y = y, w = pw, h = ph, buttons = {} }
	for i, b in ipairs(BUTTONS) do
		L.buttons[i] = { x = x + 30, y = y + 70 + (i - 1) * 56, w = pw - 60, h = 44, b = b, key = tostring(i) }
	end
	return L
end

function Pause.isOpen() return Pause.open end

-- Esc / Start: open it, or close it if it's up. (Start on the death
-- screen still relaunches, see main.lua.)
function Pause.toggle(game)
	Pause.open, Pause.note = not Pause.open, nil
end

function Pause.draw(game)
	if not Pause.open then return end
	local w, h = lg.getDimensions()
	lg.setColor(0, 0, 0, 0.55)
	lg.rectangle("fill", 0, 0, w, h)
	local L = layout()
	local mx, my = love.mouse.getPosition()
	HUD.panel(L.x, L.y, L.w, L.h)
	lg.setFont(HUD.font(20))
	lg.setColor(HUD.AQUA)
	lg.printf("PAUSED", L.x, L.y + 22, L.w, "center")
	for _, r in ipairs(L.buttons) do
		lg.setColor(0, 0, 0, inside(r, mx, my) and 0.55 or 0.3)
		lg.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
		lg.setColor(HUD.INK)
		lg.setFont(HUD.font(14))
		lg.printf(("%s  %s"):format(r.key, r.b.label), r.x, r.y + 13, r.w, "center")
	end
	lg.setFont(HUD.font(11))
	lg.setColor(HUD.DIM)
	lg.printf(Pause.note or "Esc to resume", L.x, L.y + L.h - 22, L.w, "center")
end

function Pause.keypressed(game, key)
	if not Pause.open then return false end
	if key == "escape" then Pause.toggle(game) return true end
	for _, r in ipairs(layout().buttons) do
		if key == r.key then r.b.run(game) return true end
	end
	return true
end

function Pause.mousepressed(game, mx, my, button)
	if not Pause.open then return false end
	if button ~= 1 then return true end
	for _, r in ipairs(layout().buttons) do
		if inside(r, mx, my) then r.b.run(game) return true end
	end
	return true
end

return Pause
