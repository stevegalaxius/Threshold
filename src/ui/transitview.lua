--[[
	The trip itself: while game.flight runs (src/transit.lua), the world
	waits and this fills the screen. Stars stream past, and the orrery
	shows your dot arcing from where you left to where you're going.
]]

local HUD = require("src.hud")
local Fields = require("src.fields")
local T = require("src.tuning")

local TransitView = {}

local lg = love.graphics
local cos, sin, sqrt, pi, max, min = math.cos, math.sin, math.sqrt, math.pi, math.max, math.min

local COLORS = {
	venus = { 0.95, 0.85, 0.55 }, earth = { 0.45, 0.75, 1 }, mars = { 1, 0.5, 0.35 }, jupiter = { 0.9, 0.7, 0.5 },
}

-- Stars: fixed directions and speeds, streaming out from the middle.
local stars
local function makeStars()
	stars = {}
	local rng = love.math.newRandomGenerator(7)
	for i = 1, 260 do
		stars[i] = { a = rng:random() * pi * 2, d = rng:random(), v = 0.25 + rng:random() * 0.9 }
	end
end

-- Game-clock seconds of the trip done at fraction k (the clock jumps
-- forward on arrival; the orrery runs ahead of it to match).
local function T_clock(f, k)
	return T.flightClockPerAU * f.au * k
end

function TransitView.isOpen(game) return game.flight ~= nil end

function TransitView.draw(game)
	local f = game.flight
	if not f then return end
	if not stars then makeStars() end
	local w, h = lg.getDimensions()
	local cx, cy = w / 2, h / 2
	local k = min(1, f.t / max(f.dur, 0.01))
	lg.clear(0.01, 0.02, 0.05)
	-- star streaks: fast out of the gun, easing as the trip goes on
	local rush = 1.4 - k
	lg.setLineWidth(1.5)
	for _, s in ipairs(stars) do
		local d = (s.d + f.t * s.v * 0.35) % 1
		local r1 = d * d * w * 0.8
		local r2 = r1 + (8 + 160 * d) * rush
		lg.setColor(0.7, 0.9, 1, 0.15 + 0.6 * d)
		lg.line(cx + cos(s.a) * r1, cy + sin(s.a) * r1, cx + cos(s.a) * r2, cy + sin(s.a) * r2)
	end
	-- the orrery, bottom right
	local R = min(w, h) * 0.22
	local ox, oy = w - R - 40, h - R - 40
	HUD.panel(ox - R - 20, oy - R - 20, R * 2 + 40, R * 2 + 40)
	lg.setColor(1, 0.85, 0.4)
	lg.circle("fill", ox, oy, 6)
	local maxAU = 0
	for _, o in pairs(Fields.orbits) do maxAU = max(maxAU, o.au) end
	local function at(id, clock)
		local px, py = Fields.orbitPos(id, clock)
		local a = math.atan2(py, px)
		local r = R * sqrt(Fields.orbits[id].au / maxAU)
		return ox + cos(a) * r, oy + sin(a) * r, r
	end
	local clock = game.universe.clock + T_clock(f, k)
	for id in pairs(Fields.orbits) do
		local x, y, r = at(id, clock)
		lg.setColor(0.55, 0.7, 0.78, 0.3)
		lg.setLineWidth(1)
		lg.circle("line", ox, oy, r, 72)
		local c = COLORS[id] or { 1, 1, 1 }
		lg.setColor(c)
		lg.circle("fill", x, y, 5)
	end
	-- your path: a gentle arc from where you left to where you'll arrive
	local x1, y1 = at(f.from, game.universe.clock)
	local x2, y2 = at(f.to, game.universe.clock + T_clock(f, 1))
	local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
	local bx, by = mx + (mx - ox) * 0.25, my + (my - oy) * 0.25
	local function curve(u)
		local a, b, c = (1 - u) ^ 2, 2 * u * (1 - u), u * u
		return a * x1 + b * bx + c * x2, a * y1 + b * by + c * y2
	end
	lg.setColor(1, 0.85, 0.4, 0.5)
	local prevX, prevY = curve(0)
	for i = 1, 24 do
		local px, py = curve(i / 24)
		if i % 2 == 0 then lg.line(prevX, prevY, px, py) end
		prevX, prevY = px, py
	end
	local sx, sy = curve(k)
	lg.setColor(1, 1, 1)
	lg.circle("fill", sx, sy, 4)
	-- what's happening, top middle
	lg.setFont(HUD.font(22))
	lg.setColor(HUD.AQUA)
	lg.printf(("IN FLIGHT TO %s"):format(Fields[f.to].name:upper()), 0, 60, w, "center")
	lg.setFont(HUD.font(13))
	lg.setColor(HUD.DIM)
	lg.printf(("%.2f AU   from %s"):format(f.au, Fields[f.from].name), 0, 92, w, "center")
end

return TransitView
