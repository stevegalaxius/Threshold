--[[
	The trip itself: while game.flight runs (src/transit.lua), the world
	waits and this fills the screen. Your ship stays in the middle, engine
	blazing, while space goes to warp streaks around it; the orrery in the
	corner shows your dot arcing from where you left to where you're going.
]]

local HUD = require("src.hud")
local Fields = require("src.fields")
local T = require("src.tuning")
local Render = require("src.render")

local TransitView = {}

local lg = love.graphics
local cos, sin, sqrt, pi, max, min = math.cos, math.sin, math.sqrt, math.pi, math.max, math.min

local function color(id) return Fields.orbits[id] and Fields.orbits[id].color end

-- Warp streaks: each one a lane across the screen, its own speed and
-- length, streaming back past the ship.
local stars
local function makeStars()
	stars = {}
	local rng = love.math.newRandomGenerator(7)
	for i = 1, 320 do
		stars[i] = { u = rng:random(), across = rng:random() * 2 - 1, v = 0.6 + rng:random() * 1.6, b = 0.3 + rng:random() * 0.7 }
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
	lg.clear(0.01, 0.015, 0.04)
	-- warp: it builds over the first second out of the gun and drops away
	-- in the last half second before you arrive
	local warp = min(1, f.t / 1.0) * min(1, (f.dur - f.t) / 0.5 + 0.15)
	warp = max(0, warp)
	local p = game.player
	local heading = p and not p.removed and p.body:getAngle() or 0
	local hx, hy = cos(heading), sin(heading)
	local nx, ny = -hy, hx
	local span = sqrt(w * w + h * h) * 0.6
	for _, s in ipairs(stars) do
		local along = ((s.u - f.t * s.v * (0.15 + 1.2 * warp)) % 1) * 2 - 1
		local px = cx + (hx * along + nx * s.across) * span
		local py = cy + (hy * along + ny * s.across) * span
		local len = 2 + warp * (60 + 380 * s.v)
		lg.setLineWidth(1 + warp)
		lg.setColor(0.7, 0.88, 1, s.b * (0.4 + 0.6 * warp))
		lg.line(px, py, px - hx * len, py - hy * len)
	end
	-- your ship in the middle, engine lit
	if p and not p.dead then
		local cam = game.camera
		local x, y = p.body:getPosition()
		cam.x, cam.y = x, y
		cam:apply()
		Render.ship(game, p)
		cam:release()
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
		local r = R * Fields.mapScale(Fields.orbits[id].au)
		return ox + cos(a) * r, oy + sin(a) * r, r
	end
	local clock = game.universe.clock + T_clock(f, k)
	for id in pairs(Fields.orbits) do
		local x, y, r = at(id, clock)
		lg.setColor(0.55, 0.7, 0.78, 0.3)
		lg.setLineWidth(1)
		lg.circle("line", ox, oy, r, 72)
		local c = color(id) or { 1, 1, 1 }
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
