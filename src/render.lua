--[[
	Draws the world. All placeholder art: ships are their hull outlines,
	asteroids are polygons. The real look (photo collage and drawn art,
	nearest-neighbor scaled) replaces this later without touching the game
	code, since nothing here affects the simulation.
]]

local data = require("src.data")
local Ship = require("src.ship")
local T = require("src.tuning")
local HullShape = require("src.hullshape")

local Render = {}

local lg = love.graphics
local cos, sin, floor, max, min, pi, sqrt = math.cos, math.sin, math.floor, math.max, math.min, math.pi, math.sqrt

local COLORS = {
	space = { 0.02, 0.035, 0.06 },
	grid = { 0.35, 0.75, 0.85, 0.06 },
	edge = { 0.4, 0.9, 1.0, 0.35 },
	flame = { 0.55, 0.85, 1.0 },
	enemyFlame = { 1.0, 0.6, 0.25 },
	gun = { 1.0, 0.92, 0.55 },
	artillery = { 1.0, 0.6, 0.25 },
	missile = { 1.0, 0.95, 0.9 },
	laser = { 0.6, 1.0, 1.0 },
	ammo = { 1.0, 0.78, 0.25 },
	salvage = { 0.45, 0.95, 0.85 },
	container = { 0.95, 0.55, 0.2 },
}
Render.COLORS = COLORS

-- Outlines are drawn in world units, so they'd thin to nothing zoomed out.
-- outline(w) keeps a line at least about w * 0.7 screen pixels wide.
local screenPx = 1
local function outline(w)
	return max(w, w * 0.7 * screenPx)
end


-- Paint jobs the player can pick from (debug panel for now). Enemies get
-- their color from data/enemies.lua.
Render.PAINTS = {
	{ name = "Glacier",  color = { 0.55, 0.9, 0.95 } },
	{ name = "Signal",   color = { 1.0, 0.85, 0.35 } },
	{ name = "Bone",     color = { 0.9, 0.88, 0.8 } },
	{ name = "Moss",     color = { 0.55, 0.85, 0.45 } },
	{ name = "Orchid",   color = { 0.85, 0.55, 0.95 } },
	{ name = "Ember",    color = { 1.0, 0.45, 0.3 } },
}

-- Starfield: three parallax layers of fixed random stars, tiled. Each layer
-- pans by `depth` of the camera motion and zooms by zoom^depth, so far layers
-- barely react to the wheel while near ones follow the world closely.
local TILE = 1024
local layers
local function buildStars()
	layers = {}
	local rng = love.math.newRandomGenerator(7)
	for li, depth in ipairs({ 0.15, 0.35, 0.6 }) do
		local stars = {}
		for _ = 1, 140 do
			table.insert(stars, { rng:random() * TILE, rng:random() * TILE, 0.25 + rng:random() * 0.5 * li / 3 })
		end
		layers[li] = { depth = depth, stars = stars, size = li }
	end
end

function Render.background(cam)
	if not layers then buildStars() end
	local w, h = lg.getDimensions()
	local hw, hh = w / 2, h / 2
	lg.clear(COLORS.space)
	for _, layer in ipairs(layers) do
		local scale = cam.zoom ^ layer.depth
		local cx, cy = cam.x * layer.depth, cam.y * layer.depth
		local size = max(1, layer.size * scale)
		-- Range of tiles covering the screen, in this layer's coordinates.
		local tx1, tx2 = floor((cx - hw / scale) / TILE), floor((cx + hw / scale) / TILE)
		local ty1, ty2 = floor((cy - hh / scale) / TILE), floor((cy + hh / scale) / TILE)
		for tx = tx1, tx2 do
			for ty = ty1, ty2 do
				for _, s in ipairs(layer.stars) do
					local x = hw + (s[1] + tx * TILE - cx) * scale
					local y = hh + (s[2] + ty * TILE - cy) * scale
					if x >= 0 and x <= w and y >= 0 and y <= h then
						lg.setColor(0.7, 0.9, 1, s[3])
						lg.rectangle("fill", floor(x), floor(y), size, size)
					end
				end
			end
		end
	end
end

local function drawGrid(game)
	local cam = game.camera
	local w, h = lg.getDimensions()
	local x1, y1 = cam:toWorld(0, 0)
	local x2, y2 = cam:toWorld(w, h)
	local step = 256
	lg.setColor(COLORS.grid)
	lg.setLineWidth(1)
	for x = floor(x1 / step) * step, x2, step do lg.line(x, y1, x, y2) end
	for y = floor(y1 / step) * step, y2, step do lg.line(x1, y, x2, y) end

	-- Arena edge
	lg.setColor(COLORS.edge)
	local R, n = game.arenaRadius, 360
	for i = 0, n - 1, 2 do
		local a1, a2 = i / n * pi * 2, (i + 1) / n * pi * 2
		lg.line(cos(a1) * R, sin(a1) * R, cos(a2) * R, sin(a2) * R)
	end
end

-- Re-entry glow: a hot plasma sheath on the leading side of anything
-- ploughing through the atmosphere (e.reentry, set by Game:updateAtmosphere).
local function drawReentry(e, size)
	local h = e.reentry
	if not h then return end
	local x, y = e.body:getPosition()
	local dx, dy = e.reentryX, e.reentryY
	local flick = 0.85 + love.math.random() * 0.3
	lg.setBlendMode("add")
	for k = 4, 1, -1 do
		local r = size * (0.6 + k * 0.3 + h * 0.5) * flick
		lg.setColor(1, 0.35 + k * 0.12, 0.1 + k * 0.08, (0.12 + 0.2 * h) * (1.2 - k * 0.2))
		lg.circle("fill", x + dx * size * 0.4, y + dy * size * 0.4, r)
	end
	-- white-hot core on the leading edge
	lg.setColor(1, 0.95, 0.8, 0.6 * h * flick)
	lg.circle("fill", x + dx * size * 0.8, y + dy * size * 0.8, size * (0.25 + 0.3 * h))
	-- flames streaming behind
	lg.setLineWidth(max(2, size * 0.18))
	for k = -2, 2 do
		local ox, oy = -dy * k * size * 0.3, dx * k * size * 0.3
		local len = size * (2.5 + 4 * h) * (1 - math.abs(k) * 0.18) * flick
		lg.setColor(1, 0.55, 0.2, (0.25 + 0.4 * h) * (1 - math.abs(k) * 0.25))
		lg.line(x + ox, y + oy, x + ox - dx * len, y + oy - dy * len)
	end
	lg.setBlendMode("alpha")
end

local function drawAsteroid(e)
	drawReentry(e, e.radius)
	local x, y = e.body:getPosition()
	lg.push()
	lg.translate(x, y)
	lg.rotate(e.body:getAngle())
	local s = e.shade
	if e.giant then
		lg.setColor(0.2 * s, 0.19 * s, 0.21 * s)
		for _, t in ipairs(e.tris) do lg.polygon("fill", t) end
		-- a few craters so it reads as rock at any zoom
		lg.setColor(0.15 * s, 0.14 * s, 0.16 * s)
		for _, c in ipairs(e.craters) do lg.circle("fill", c[1], c[2], c[3]) end
		lg.setColor(0.6 * s, 0.58 * s, 0.62 * s)
		lg.setLineWidth(outline(3))
		lg.polygon("line", e.outline)
	elseif e.verts then
		lg.setColor(0.24 * s, 0.24 * s, 0.27 * s)
		lg.polygon("fill", e.verts)
		lg.setColor(0.6 * s, 0.62 * s, 0.68 * s)
		lg.setLineWidth(outline(2))
		lg.polygon("line", e.verts)
	else
		lg.setColor(0.24 * s, 0.24 * s, 0.27 * s)
		lg.circle("fill", 0, 0, e.radius * 0.9)
		lg.setColor(0.6 * s, 0.62 * s, 0.68 * s)
		lg.circle("line", 0, 0, e.radius * 0.9)
	end
	lg.pop()
	-- heated rock: glowing orange over its whole face
	if e.reentry then
		lg.setBlendMode("add")
		lg.setColor(1, 0.45, 0.15, 0.45 * e.reentry)
		if e.verts then
			lg.push()
			lg.translate(x, y)
			lg.rotate(e.body:getAngle())
			lg.polygon("fill", e.verts)
			lg.pop()
		else
			lg.circle("fill", x, y, e.radius * 0.9)
		end
		lg.setBlendMode("alpha")
	end
end

local function drawStructure(game, e)
	local fill = (e.role == "hub") and { 0.2, 0.23, 0.28 } or (e.role == "ladder" or e.role == "tether") and { 0.26, 0.17, 0.13 } or { 0.16, 0.18, 0.22 }
	lg.setColor(fill)
	lg.polygon("fill", e.verts)
	lg.setColor(0.5, 0.58, 0.68)
	lg.setLineWidth(outline(2))
	lg.polygon("line", e.verts)
	-- running lights on every corner, blinking out of step
	local on = ((game.time + e.blink) % 1.6) < 0.25
	if on then
		local r = max(4, 3 * screenPx)
		lg.setColor(e.role == "ring" and { 1, 0.35, 0.3 } or { 0.5, 0.9, 1 })
		for i = 1, #e.verts, 2 do lg.circle("fill", e.verts[i], e.verts[i + 1], r) end
	end
end

-- A wheel station: smooth ring, spokes and hub, with lit windows along
-- the ring that turn with it.
local function drawStation(game, e)
	local x, y = e.body:getPosition()
	local R, tube, hub = e.ringR, e.tube, e.hub
	local ri, ro = R - tube / 2, R + tube / 2
	local seg = 512
	lg.push()
	lg.translate(x, y)
	lg.rotate(e.body:getAngle())
	-- spokes under the ring
	local sw = tube * 0.22
	for k = 0, e.spokes - 1 do
		lg.push()
		lg.rotate(k / e.spokes * pi * 2)
		lg.setColor(0.17, 0.19, 0.23)
		lg.rectangle("fill", hub * 0.9, -sw, ri - hub * 0.9 + 4, sw * 2)
		lg.setColor(0.5, 0.58, 0.68)
		lg.setLineWidth(outline(1.5))
		lg.rectangle("line", hub * 0.9, -sw, ri - hub * 0.9 + 4, sw * 2)
		lg.pop()
	end
	-- the ring, as one thick smooth stroke
	lg.setColor(0.2, 0.23, 0.28)
	lg.setLineWidth(tube)
	lg.circle("line", 0, 0, R, seg)
	-- a darker band down the middle of the ring
	lg.setColor(0.15, 0.17, 0.21)
	lg.setLineWidth(tube * 0.35)
	lg.circle("line", 0, 0, R, seg)
	lg.setColor(0.55, 0.63, 0.74)
	lg.setLineWidth(outline(2))
	lg.circle("line", 0, 0, ro, seg)
	lg.circle("line", 0, 0, ri, seg)
	-- windows along the ring's outer and inner faces
	lg.setColor(1, 0.86, 0.55, 0.85)
	local wr = max(tube * 0.05, 2 * screenPx)
	local nw = floor(R / 14)
	for i = 0, nw - 1 do
		local a = i / nw * pi * 2
		local c, s = cos(a), sin(a)
		if i % 7 ~= 3 then
			lg.circle("fill", c * (ro - tube * 0.16), s * (ro - tube * 0.16), wr)
			lg.circle("fill", c * (ri + tube * 0.16), s * (ri + tube * 0.16), wr)
		end
	end
	-- the dock: a square module on the outside of the ring, door facing out
	local d = e.dock
	if d then
		local x1, x2, hw = d.x1, d.x2, d.hw
		lg.setColor(0.2, 0.23, 0.28)
		lg.rectangle("fill", x1, -hw, x2 - x1, hw * 2)
		lg.setColor(0.55, 0.63, 0.74)
		lg.setLineWidth(outline(2))
		lg.rectangle("line", x1, -hw, x2 - x1, hw * 2)
		-- the door: hazard-striped, lit while a ship is coming in
		local busy = false
		for _, o in ipairs(game.entities) do
			if o.dockState and o.dockState.station == e and not o.dockState.done then busy = true end
		end
		local dw = hw * 0.7
		lg.setColor(0.09, 0.1, 0.13)
		lg.rectangle("fill", x2 - d.wall, -dw, d.wall, dw * 2)
		lg.setColor(busy and { 0.4, 1, 0.55 } or { 0.95, 0.75, 0.25 })
		for k = -3, 2 do
			local y0 = dw * k / 3
			lg.rectangle("fill", x2 - d.wall, y0, d.wall, dw / 6)
		end
		-- Runway lights: two rows running out from the door, plus a centre
		-- line of strobes chasing in toward it. Lights only: nothing out
		-- there collides.
		local lr = max(5, 3 * screenPx)
		local step = 80
		local n = floor(d.runway / step)
		for i = 0, n do
			local lx = x2 + 30 + i * step
			local fade = 1 - i / (n + 1) * 0.6
			lg.setColor(0.35, 1, 0.5, 0.75 * fade)
			lg.circle("fill", lx, dw, lr)
			lg.circle("fill", lx, -dw, lr)
			local phase = (game.time * 1.6 + i / n) % 1
			if phase < 0.12 then
				lg.setColor(1, 1, 1, fade)
				lg.circle("fill", lx, 0, lr * 1.8)
			else
				lg.setColor(1, 1, 1, 0.12 * fade)
				lg.circle("fill", lx, 0, lr)
			end
		end
		lg.setColor(1, 0.7, 0.2, (game.time % 0.8) < 0.4 and 1 or 0.35)
		lg.circle("fill", x2, hw, lr * 1.4)
		lg.circle("fill", x2, -hw, lr * 1.4)
	end
	-- hub
	lg.setColor(0.22, 0.25, 0.31)
	lg.circle("fill", 0, 0, hub, 96)
	lg.setColor(0.55, 0.63, 0.74)
	lg.setLineWidth(outline(2))
	lg.circle("line", 0, 0, hub, 96)
	lg.circle("line", 0, 0, hub * 0.45, 64)
	-- blinking beacons on the rim
	if (game.time % 1.6) < 0.25 then
		lg.setColor(1, 0.35, 0.3)
		local br = max(tube * 0.08, 4 * screenPx)
		for k = 0, 3 do
			local a = (k + 0.5) / 4 * pi * 2
			lg.circle("fill", cos(a) * ro, sin(a) * ro, br)
		end
	end
	lg.pop()
end

-- A navigation buoy: a small beacon with a slow pulse ring.
local function drawBuoy(game, e)
	local x, y = e.body:getPosition()
	local px = screenPx
	local r = max(14, 5 * px)
	local t = (game.time * 0.5 + e.blink) % 1
	lg.setColor(1, 0.75, 0.25, 0.35 * (1 - t))
	lg.setLineWidth(outline(2))
	lg.circle("line", x, y, r * (1.5 + t * 6))
	lg.setColor(0.2, 0.22, 0.26)
	lg.circle("fill", x, y, r, 6)
	lg.setColor(0.6, 0.66, 0.74)
	lg.circle("line", x, y, r, 6)
	lg.setColor(1, 0.75, 0.25, t < 0.15 and 1 or 0.4)
	lg.circle("fill", x, y, r * 0.4)
end

-- Mass drivers: a capture ring at the breech and a rail running outward,
-- with lights chasing along it in the direction it fires.
local function drawDriver(game, e)
	local x, y = game:driverBreech(e)
	local p = game.player
	local busy = p and not p.dead and (p.launch or (game.driverMenu and game.driverMenu.driver == e))
	local len, hw = T.driverBarrel, 80
	local lr = max(5, 3 * screenPx)
	lg.push()
	lg.translate(x, y)
	lg.rotate(e.angle)
	-- the barrel: a long armoured rail running out from the breech
	lg.setColor(0.2, 0.23, 0.28)
	lg.rectangle("fill", 0, -hw, len, hw * 2)
	lg.setColor(0.55, 0.63, 0.74)
	lg.setLineWidth(outline(2))
	lg.rectangle("line", 0, -hw, len, hw * 2)
	for k = 1, 6 do
		local cx = len * k / 7
		lg.line(cx, -hw, cx, hw)
	end
	-- coils lighting up down the barrel, faster while it's firing
	local rate = p and p.launch and 3 or 0.8
	for i = 0, 9 do
		local k = (i / 10 + game.time * rate) % 1
		lg.setColor(0.6, 0.95, 1, 0.8 * (1 - k))
		lg.rectangle("fill", k * len - 8, -hw + 10, 16, hw * 2 - 20)
	end
	-- the breech: hazard-striped, lit green while it has you
	local dw, wall = hw * 1.3, 60
	lg.setColor(0.09, 0.1, 0.13)
	lg.rectangle("fill", -wall, -dw, wall, dw * 2)
	lg.setColor(busy and { 0.4, 1, 0.55 } or { 0.95, 0.75, 0.25 })
	for k = -3, 2 do
		lg.rectangle("fill", -wall, dw * k / 3, wall, dw / 6)
	end
	-- runway lights back along the approach, strobes chasing in to the
	-- breech; off while someone's in it (the gun swings, they'd only mislead)
	local rw = 90
	local step = 75
	local n = floor(T.driverZone / step)
	for i = 0, busy and -1 or n do
		local lx = -wall - 30 - i * step
		local fade = 1 - i / (n + 1) * 0.6
		lg.setColor(0.35, 1, 0.5, 0.75 * fade)
		lg.circle("fill", lx, rw, lr)
		lg.circle("fill", lx, -rw, lr)
		local phase = (game.time * 1.6 + i / n) % 1
		if phase < 0.12 then
			lg.setColor(1, 1, 1, fade)
			lg.circle("fill", lx, 0, lr * 1.8)
		else
			lg.setColor(1, 1, 1, 0.12 * fade)
			lg.circle("fill", lx, 0, lr)
		end
	end
	lg.setColor(1, 0.7, 0.2, (game.time % 0.8) < 0.4 and 1 or 0.35)
	lg.circle("fill", -wall, dw, lr * 1.4)
	lg.circle("fill", -wall, -dw, lr * 1.4)
	lg.circle("fill", len, hw, lr * 1.4)
	lg.circle("fill", len, -hw, lr * 1.4)
	lg.pop()
end

-- The transit lane: a faint glow under its arc, fading out past its
-- edges the way the buff does, so the road reads without markings.
local function drawLane(game)
	local lane = game.lane
	-- the stretch the camera can see, with room to spare, so the glow never
	-- ends on screen
	local cam = game.camera
	local cs = game:toLane(cam.x, cam.y)
	local w, h = lg.getDimensions()
	local view = sqrt(w * w + h * h) / cam.zoom + T.laneWidth * 2
	local W = T.laneWidth
	local s1, s2 = max(-lane.half, cs - view), min(lane.half, cs + view)
	local pts = {}
	for s = s1, s2, 300 do
		local x, y = game:fromLane(s, 0)
		pts[#pts + 1] = x
		pts[#pts + 1] = y
	end
	if #pts < 4 then return end
	-- the road fades out over its last stretch as the planet comes up
	local fade = max(0, min(1, (lane.half - cs) / 15000))
	lg.setBlendMode("add")
	local bands = 6
	for k = bands, 1, -1 do
		local half = W + T.laneRamp * (k - 1) / bands
		lg.setColor(0.35, 0.6, 0.9, (k == 1 and 0.05 or 0.018) * fade)
		lg.setLineWidth(half * 2)
		lg.line(pts)
	end
	lg.setBlendMode("alpha")
	-- the far end
	if lane.half - cs < view then
		local x1, y1 = game:fromLane(lane.half, -W)
		local x2, y2 = game:fromLane(lane.half, W)
		lg.setColor(0.6, 0.95, 1, 0.5 * fade)
		lg.setLineWidth(outline(4))
		lg.line(x1, y1, x2, y2)
	end
end

-- Catch rings: a lit hoop for each braking ring, the next one brightest,
-- passed ones dimmed, joined by a faint guide line in to the driver. The
-- player's predicted path runs from the nose while inbound.
local function drawCatchRing(game, e)
	local x, y = e.body:getPosition()
	local p = game.player
	local inbound = p and not p.dead and p.catching
	local nextRing = inbound and game:nextCatchRing()
	local col = e.passed and { 0.4, 0.9, 0.5, 0.35 } or (e == nextRing and { 0.6, 1, 1, 0.95 } or { 0.55, 0.85, 1, 0.5 })
	local pulse = (e == nextRing) and (0.5 + 0.5 * sin(game.time * 6)) or 0
	lg.setColor(col[1], col[2], col[3], 0.06 + 0.06 * pulse)
	lg.circle("fill", x, y, e.radius)
	lg.setColor(col)
	lg.setLineWidth(outline(4 + 3 * pulse))
	lg.circle("line", x, y, e.radius, 64)
	-- the guide line toward the driver
	local dx, dy = cos(e.angle), sin(e.angle)
	lg.setColor(0.55, 0.85, 1, 0.12)
	lg.setLineWidth(outline(2))
	local reach = T.catchSpacing - e.radius
	lg.line(x - dx * e.radius, y - dy * e.radius, x - dx * reach, y - dy * reach)
end

local function drawPredicted(game)
	local p = game.player
	if not p or p.dead or not p.catching then return end
	local x, y = p.body:getPosition()
	local vx, vy = p.body:getLinearVelocity()
	lg.setColor(1, 0.85, 0.4, 0.45)
	lg.setLineWidth(outline(2))
	local n = 20
	for i = 0, n - 1, 2 do
		local t1, t2 = i / n * 3, (i + 1) / n * 3
		lg.line(x + vx * t1, y + vy * t1, x + vx * t2, y + vy * t2)
	end
end

-- The lane buff: a crackling outline round any ship inside a transit
-- lane.
local function drawLaneBuff(e)
	local buff = e.laneBuff or e.laneFade
	if not buff or buff <= 0 or (e.dockState and e.dockState.done) then return end
	local x, y = e.body:getPosition()
	local size = e.halfLength
	local hot = 0
	local flick = (0.85 + love.math.random() * 0.3) * buff
	lg.setBlendMode("add")
	for k = 3, 1, -1 do
		lg.setColor(0.45 + hot * 0.5, 0.85, 1 - hot * 0.4, (0.1 + 0.08 * hot) * (1.4 - k * 0.3))
		lg.circle("fill", x, y, size * (1 + k * 0.35 + hot * 0.4) * flick)
	end
	lg.setColor(0.8 + hot * 0.2, 0.95, 1, 0.5 + 0.3 * hot)
	lg.setLineWidth(max(1.5, size * 0.06))
	lg.circle("line", x, y, size * (1.15 + hot * 0.25) * flick, 24)
	-- streaks trailing behind, like re-entry flames but cold blue, longer
	-- the faster you go
	local vx, vy = e.body:getLinearVelocity()
	local sp = sqrt(vx * vx + vy * vy)
	if sp > 200 then
		local dx, dy = vx / sp, vy / sp
		local h = min(1.5, sp / T.laneEntrySpeed)
		lg.setLineWidth(max(2, size * 0.14))
		for k = -2, 2 do
			local ox, oy = -dy * k * size * 0.35, dx * k * size * 0.35
			local len = size * (2 + 4 * h) * (1 - math.abs(k) * 0.18) * flick
			lg.setColor(0.5, 0.85, 1, (0.18 + 0.25 * h) * (1 - math.abs(k) * 0.25) * buff)
			lg.line(x + ox, y + oy, x + ox - dx * len, y + oy - dy * len)
		end
	end
	lg.setBlendMode("alpha")
end

local PLANET_SEGMENTS = 2048   -- big planets need a smooth edge up close

-- The planet, with a hazy atmosphere and dashed rings that turn with the
-- planet's field so you can see which way it drags you.

local function drawPlanet(game, e)
	local x, y = e.body:getPosition()
	local R, c = e.radius, e.hue
	local w = game.well
	local dir = (w and w.swirl or 0) >= 0 and 1 or -1
	-- dashed rings that drift the way the well turns
	lg.setLineWidth(outline(2))
	for k = 1, 4 do
		local rr = R + k * 1500
		local n = floor(pi * rr / 900) * 2
		local turn = dir * game.time * 150 / rr
		lg.setColor(c[1], c[2], c[3], 0.16 - k * 0.025)
		for i = 0, n - 1, 2 do
			local a1, a2 = turn + i / n * pi * 2, turn + (i + 1) / n * pi * 2
			lg.line(x + cos(a1) * rr, y + sin(a1) * rr, x + cos(a2) * rr, y + sin(a2) * rr)
		end
	end
	if e.gas then
		-- a gas giant: see-through bands thickening toward the middle
		for k = 1, 12 do
			lg.setColor(c[1], c[2], c[3], 0.045)
			lg.circle("fill", x, y, R * (1 - (k - 1) / 13), PLANET_SEGMENTS)
		end
		lg.setColor(c[1], c[2], c[3], 0.5)
		lg.setLineWidth(outline(3))
		lg.circle("line", x, y, R, PLANET_SEGMENTS)
		return
	end
	-- atmosphere haze
	for k = 6, 1, -1 do
		lg.setColor(c[1], c[2], c[3], 0.05)
		lg.circle("fill", x, y, R + k * 140, PLANET_SEGMENTS)
	end
	lg.setColor(c[1] * 0.35, c[2] * 0.35, c[3] * 0.4)
	lg.circle("fill", x, y, R, PLANET_SEGMENTS)
	-- cloud bands, clipped to the disc
	lg.setColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.5)
	for k = -2, 2 do
		local y1, y2 = k * R * 0.3 - R * 0.05, k * R * 0.3 + R * 0.05
		local pts = {}
		for i = 0, 32 do
			local yy = y1 + (y2 - y1) * i / 32
			pts[#pts + 1] = x + sqrt(max(0, R * R - yy * yy)) * 0.98
			pts[#pts + 1] = y + yy
		end
		for i = 32, 0, -1 do
			local yy = y1 + (y2 - y1) * i / 32
			pts[#pts + 1] = x - sqrt(max(0, R * R - yy * yy)) * 0.98
			pts[#pts + 1] = y + yy
		end
		for _, t in ipairs(love.math.triangulate(pts)) do lg.polygon("fill", t) end
	end
	lg.setColor(c[1], c[2], c[3], 0.9)
	lg.setLineWidth(outline(3))
	lg.circle("line", x, y, R, PLANET_SEGMENTS)
end

local BARREL = { S = 7, M = 10, L = 16 }
local TURRET = { S = 4, M = 6, L = 9 }   -- turret base radius

local function drawShip(game, e)
	if e.dockState and e.dockState.done then return end
	drawReentry(e, e.halfLength)
	drawLaneBuff(e)
	local x, y = e.body:getPosition()
	local a = e.body:getAngle()
	local hull = e.hull
	local col = e.color
	local dark = { col[1] * 0.22, col[2] * 0.22, col[3] * 0.22 }

	lg.push()
	lg.translate(x, y)
	lg.rotate(a)

	-- Everything below is in the ship's own frame: +x is the nose, +y its right side.
	local fc = e.isPlayer and COLORS.flame or COLORS.enemyFlame
	local R = hull.radius
	if e.mainBurn > 0.05 then
		local len = R * (0.6 + e.mainBurn * 0.9) * (0.85 + love.math.random() * 0.3)
		if e.afterburn then len = len * 2.2 end
		local bx, wdt = e.tailX * 0.85, R * 0.35
		lg.setColor(fc[1], fc[2], fc[3], 0.35)
		lg.polygon("fill", bx, -wdt * 1.4, bx, wdt * 1.4, bx - len * 1.3, 0)
		lg.setColor(fc[1], fc[2], fc[3], 0.9)
		lg.polygon("fill", bx, -wdt, bx, wdt, bx - len, 0)
	end
	-- Maneuvering thrusters: small puffs on the side opposite the push.
	local function puff(px, py, dx, dy, k)
		local len = R * 0.45 * k * (0.8 + love.math.random() * 0.4)
		local qx, qy = -dy * 3, dx * 3
		lg.setColor(1, 1, 1, 0.75)
		lg.polygon("fill", px + qx, py + qy, px - qx, py - qy, px + dx * len, py + dy * len)
	end
	if math.abs(e.sideBurn) > 0.05 then
		local s = e.sideBurn > 0 and -1 or 1          -- pushing right fires the left-side jets
		local k = math.abs(e.sideBurn)
		puff(e.noseX * 0.4, s * R * 0.75, 0, s, k)
		puff(e.tailX * 0.5, s * R * 0.75, 0, s, k)
	end
	if math.abs(e.turnBurn or 0) > 0.05 then      -- jets helping a big hull turn
		local s = e.turnBurn > 0 and -1 or 1
		local k = math.abs(e.turnBurn)
		puff(e.noseX * 0.6, s * R * 0.75, 0, s, k)
		puff(e.tailX * 0.6, -s * R * 0.75, 0, -s, k)
	end
	if (e.foreBurn or 0) > 0.05 then                 -- jets standing in for the engine
		puff(e.tailX * 0.8, -R * 0.3, -1, 0, e.foreBurn)
		puff(e.tailX * 0.8, R * 0.3, -1, 0, e.foreBurn)
	end
	if e.retroBurn > 0.05 then
		puff(e.noseX * 0.6, -R * 0.35, 1, 0, e.retroBurn)
		puff(e.noseX * 0.6, R * 0.35, 1, 0, e.retroBurn)
	end

	-- Weapon barrels, each rotated to where its mount points it (slot.aim).
	-- Fixed and gimballed guns sit under the hull; turrets sit on top of it.
	local function barrel(w)
		local s = w.slot
		local len = BARREL[w.module.size] or 8
		local thick = (w.module.size == "L") and 5 or ((w.module.size == "M") and 4 or 3)
		if w.mount == "turret" then len, thick = len * 1.5, thick + 1 end
		lg.push()
		lg.translate(s.x or 0, s.y or 0)
		lg.rotate(w.aim or 0)
		lg.setColor(0.75, 0.78, 0.82)
		if w.w.kind == "laser" then lg.setColor(0.6, 0.95, 1) end
		if w.group == "auxiliary" then
			lg.rectangle("fill", -4, -4, 8, 8)
		else
			local n, gap = w.w.barrels or 1, w.w.barrelGap or 8
			for b = 1, n do
				local off = (b - (n + 1) / 2) * gap
				lg.rectangle("fill", 0, off - thick / 2, len, thick)
			end
		end
		if w.mount == "turret" then
			local r = TURRET[w.module.size] or 5
			lg.setColor(dark)
			lg.circle("fill", 0, 0, r)
			lg.setColor(col)
			lg.setLineWidth(outline(1.5))
			lg.circle("line", 0, 0, r)
		end
		lg.pop()
	end
	for _, w in ipairs(e.weapons) do
		if w.mount ~= "turret" then barrel(w) end
	end
	HullShape.draw(hull, col, function(c) return { c[1] * 0.22, c[2] * 0.22, c[3] * 0.22 } end,
		function(c) return c end, outline(2))
	if e.flash > 0 then
		HullShape.draw(hull, col, function() return { 1, 1, 1, 0.8 } end)
	end
	for _, w in ipairs(e.weapons) do
		if w.mount == "turret" then barrel(w) end
	end
	lg.pop()

	-- Armor bar for damaged enemies
	if not e.isPlayer and e.armor < e.stats.armor then
		local wdt = hull.radius * 2
		local fr = e.armor / e.stats.armor
		lg.setColor(0, 0, 0, 0.6)
		lg.rectangle("fill", x - wdt / 2, y - hull.radius - 12, wdt, 4)
		lg.setColor(e.color)
		lg.rectangle("fill", x - wdt / 2, y - hull.radius - 12, wdt * fr, 4)
	end
end

-- Tractor beam: a soft line to whatever it's reeling in, and its reach
-- while the key is held; a fainter one to a wreck you're looting.
local function drawTractor(game)
	local p = game.player
	if not p or p.dead then return end
	local x, y = p.body:getPosition()
	local c = COLORS.laser
	local held = game.looting
	if held and not held.removed and not p.intent.tractor then
		-- holding what you're looting: a fainter beam
		local tx, ty = held.body:getPosition()
		lg.setColor(c[1], c[2], c[3], 0.15)
		lg.setLineWidth(5)
		lg.line(x, y, tx, ty)
		lg.setColor(c[1], c[2], c[3], 0.45)
		lg.setLineWidth(1)
		lg.line(x, y, tx, ty)
		return
	end
	if not p.intent.tractor then return end
	lg.setColor(c[1], c[2], c[3], 0.08)
	lg.setLineWidth(1)
	lg.circle("line", x, y, Ship.tractorRange(p) + p.hull.radius, 64)
	local k = p.tractorTarget
	if not k and p.towTarget and not p.towTarget.removed then
		local tx, ty = p.towTarget.body:getPosition()
		k = { x = tx, y = ty }
	end
	if k then
		lg.setColor(c[1], c[2], c[3], 0.25)
		lg.setLineWidth(6)
		lg.line(x, y, k.x, k.y)
		lg.setColor(c[1], c[2], c[3], 0.7)
		lg.setLineWidth(1.5)
		lg.line(x, y, k.x, k.y)
	end
end

-- Cargo containers: a corrugated box, brighter when it has cargo in it.
local function drawContainer(game, e)
	local x, y = e.body:getPosition()
	lg.push()
	lg.translate(x, y)
	lg.rotate(e.body:getAngle())
	local c = COLORS.container
	local full = next(e.loot) ~= nil
	local w, h = e.w, e.h
	lg.setColor(c[1] * 0.18, c[2] * 0.18, c[3] * 0.18)
	lg.rectangle("fill", -w / 2, -h / 2, w, h)
	lg.setColor(c[1], c[2], c[3], full and 0.9 or 0.45)
	lg.setLineWidth(outline(1.5))
	lg.rectangle("line", -w / 2, -h / 2, w, h)
	lg.setLineWidth(outline(1))
	lg.setColor(c[1], c[2], c[3], full and 0.45 or 0.2)
	for i = 1, 5 do
		local lx = -w / 2 + w * i / 6
		lg.line(lx, -h / 2 + 3, lx, h / 2 - 3)
	end
	lg.pop()
end

-- What a tap of the tractor key would open: a ring around it.
local function drawLootHover(game)
	local e = game.hoverLoot
	if not e or e.removed then return end
	local x, y = e.body:getPosition()
	lg.setColor(1, 1, 1, 0.55)
	lg.setLineWidth(outline(1.5))
	lg.circle("line", x, y, e.radius + 8, 48)
end

-- Husks: the dead ship's outline, burnt dark, with a faint glow of its
-- paint and the odd flicker of fire.
local function drawHusk(game, h)
	local x, y = h.body:getPosition()
	lg.push()
	lg.translate(x, y)
	lg.rotate(h.body:getAngle())
	-- a whole wreck, or one part broken off (drawn about its own centre)
	HullShape.draw(h.hull, h.color, function() return { 0.06, 0.06, 0.07 } end,
		function(c) return { c[1] * 0.35, c[2] * 0.35, c[3] * 0.35 } end, outline(2),
		h.part or h.partsLeft, h.part and h.part.cx, h.part and h.part.cy)
	local f = sin(game.time * 7 + h.flicker) * sin(game.time * 3.1 + h.flicker * 2)
	if f > 0.6 then
		lg.setColor(1, 0.55, 0.2, (f - 0.6) * 2)
		lg.circle("fill", h.part and 0 or h.tailX * 0.3, 0, 3)
	end
	lg.pop()
end

local function drawBeams(game)
	for _, e in ipairs(game.entities) do
		if e.kind == "ship" then
			for _, w in ipairs(e.weapons) do
				-- Pulse: a very bright flash that fades out over the pulse length.
				local b = w.beam
				local age = b and (game.time - b[5])
				if b and age < b[6] then
					local k = 1 - age / b[6]
					local c = COLORS.laser
					local px = 1 / game.camera.zoom
					lg.setBlendMode("add")
					lg.setColor(c[1], c[2], c[3], 0.35 * k)
					lg.setLineWidth(max(18, 10 * px))
					lg.line(b[1], b[2], b[3], b[4])
					lg.setColor(c[1], c[2], c[3], 0.7 * k)
					lg.setLineWidth(max(8, 4 * px))
					lg.line(b[1], b[2], b[3], b[4])
					lg.setColor(1, 1, 1, k)
					lg.setLineWidth(max(3, 2 * px))
					lg.line(b[1], b[2], b[3], b[4])
					lg.circle("fill", b[3], b[4], (8 + love.math.random() * 4) * k)
					lg.setBlendMode("alpha")
				end
			end
		end
	end
end

local SHELL = { S = 3, M = 4, L = 6 }
local TORPEDO = { S = 4, M = 6, L = 9 }

-- Shots keep a minimum on-screen size, so they stay visible zoomed out.
local function drawProjectiles(game)
	local zoom = game.camera.zoom
	local px = 1 / zoom                            -- one screen pixel in world units
	local trail = 1
	lg.setLineWidth(max(1.5, 0.9 * px))
	for _, p in ipairs(game.projectiles) do
		if p.kind == "gun" then
			-- rounds fade out as they lose punch over their range
			local c = COLORS.gun
			local fade = p.maxLife and (0.15 + 0.85 * max(0, p.life / p.maxLife)) or 1
			lg.setColor(c[1], c[2], c[3], (c[4] or 1) * fade)
			lg.line(p.x - p.vx * 0.014 * trail, p.y - p.vy * 0.014 * trail, p.x, p.y)
		elseif p.kind == "artillery" then
			lg.setColor(COLORS.artillery)
			lg.circle("fill", p.x, p.y, max(SHELL[p.size] or 4, 1.3 * px))
			lg.setColor(1, 0.9, 0.7, 0.5)
			lg.line(p.x - p.vx * 0.012 * trail, p.y - p.vy * 0.012 * trail, p.x, p.y)
		elseif p.kind == "torpedo" then
			local r = max(TORPEDO[p.size] or 5, 1.8 * px)
			lg.setColor(1, 0.35, 0.2, 0.35)
			lg.circle("fill", p.x, p.y, r * 2.2)
			lg.setColor(1, 0.55, 0.3, 0.7)
			lg.line(p.x - p.vx * 0.03 * trail, p.y - p.vy * 0.03 * trail, p.x, p.y)
			lg.setColor(1, 0.9, 0.75)
			lg.circle("fill", p.x, p.y, r)
		elseif p.kind == "missile" then
			local a = math.atan2(p.vy, p.vx)
			lg.setColor(1, 0.7, 0.3, 0.6)
			lg.line(p.x, p.y, p.x - cos(a) * 22 * trail, p.y - sin(a) * 22 * trail)
			lg.setColor(COLORS.missile)
			lg.circle("fill", p.x, p.y, max(3, 1.2 * px))
		end
	end
end

local function drawPickups(game)
	for _, k in ipairs(game.pickups) do
		local item = data.items[k.item]
		local c = (item.kind == "salvage") and COLORS.salvage or COLORS.ammo
		local blink = 1
		if k == game.hoverPickup then
			lg.setColor(1, 1, 1, 0.6)
			lg.setLineWidth(outline(1.5))
			lg.circle("line", k.x, k.y, 16)
		end
		lg.push()
		lg.translate(k.x, k.y)
		lg.rotate(k.spin)
		lg.setColor(c[1], c[2], c[3], 0.25 * blink)
		lg.rectangle("fill", -8, -8, 16, 16)
		lg.setColor(c[1], c[2], c[3], blink)
		lg.setLineWidth(outline(2))
		lg.rectangle("line", -5, -5, 10, 10)
		lg.pop()
	end
end

local function drawEffects(game)
	for _, fx in ipairs(game.effects) do
		local k = fx.t / fx.life
		if fx.kind == "spark" then
			local c = fx.color or { 1, 0.8, 0.5 }
			lg.setColor(c[1], c[2], c[3], 1 - k)
			lg.rectangle("fill", floor(fx.x), floor(fx.y), 2, 2)
		elseif fx.kind == "explosion" and fx.dust then
			lg.setColor(0.6, 0.6, 0.65, (1 - k) * 0.35)
			lg.circle("fill", fx.x, fx.y, fx.r * (0.5 + k * 0.8))
		elseif fx.kind == "explosion" then
			lg.setColor(1, 0.75, 0.4, (1 - k) * 0.25)
			lg.circle("fill", fx.x, fx.y, fx.r * (0.3 + k * 0.7))
			lg.setColor(1, 0.85, 0.6, 1 - k)
			lg.setLineWidth(3 * (1 - k) + 1)
			lg.circle("line", fx.x, fx.y, fx.r * (0.4 + k * 0.8))
		elseif fx.kind == "muzzle" then
			lg.setColor(1, 0.95, 0.7, 1 - k)
			lg.circle("fill", fx.x + cos(fx.a) * 4, fx.y + sin(fx.a) * 4, 3 * fx.size + 2)
		end
	end
end

-- Faint ring at the reach of the player's longest weapon, so artillery range is readable.
local function drawRange(game)
	local p = game.player
	if not p or p.dead then return end
	local reach = 0
	for _, w in ipairs(p.weapons) do
		if w.group ~= "auxiliary" then reach = max(reach, w.ammo and data.items[w.ammo].shot.range or w.w.range or 0) end
	end
	if reach <= 0 then return end
	local x, y = p.body:getPosition()
	lg.setColor(0.6, 0.95, 1, 0.07)
	lg.setLineWidth(1)
	lg.circle("line", x, y, reach, 96)
end

function Render.world(game)
	screenPx = 1 / game.camera.zoom
	Render.background(game.camera)
	game.camera:apply()
	drawGrid(game)
	if game.lane then
		-- the planet you're heading for, where it'll be when you arrive
		if game.trip then
			local px, py, F = game:laneDestination()
			if F.planetR then
				drawPlanet(game, { radius = F.planetR, hue = F.hue or { 0.9, 0.7, 0.5 }, gas = F.gas,
					body = { getPosition = function() return px, py end } })
			end
		end
		drawLane(game)
	end
	drawRange(game)
	drawPredicted(game)
	drawPickups(game)
	for _, e in ipairs(game.entities) do
		if e.kind == "asteroid" then drawAsteroid(e)
		elseif e.kind == "structure" then drawStructure(game, e)
		elseif e.kind == "planet" then drawPlanet(game, e)
		elseif e.kind == "station" then drawStation(game, e)
		elseif e.kind == "buoy" then drawBuoy(game, e)
		elseif e.kind == "driver" then drawDriver(game, e)
		elseif e.kind == "catchring" then drawCatchRing(game, e)
		elseif e.kind == "husk" then drawHusk(game, e)
		elseif e.kind == "container" then drawContainer(game, e) end
	end
	drawLootHover(game)
	drawTractor(game)
	drawProjectiles(game)
	for _, e in ipairs(game.entities) do
		if e.kind == "ship" then drawShip(game, e) end
	end
	drawBeams(game)
	drawEffects(game)
	game:drawComputers(screenPx)
	game.camera:release()
end

Render.ship = drawShip

return Render
