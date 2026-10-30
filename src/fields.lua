--[[
	Playing fields: what the arena is filled with. Each field has a name,
	where the player launches from, and a build function that places
	everything. Switch fields from the debug panel (F1) or with F2.

	  asteroids  open space with a scattering of breakable rocks
	  giant      one huge asteroid in the middle, far too big to damage,
	             that everyone fights around, plus some loose rocks
	  station    a space station in the middle: a hub, four docking arms
	             and an outer ring with gaps to fly through
]]

local Fields = {}

local cos, sin, pi, random = math.cos, math.sin, math.pi, love.math.random

Fields.list = { "asteroids", "giant", "station", "planet" }

Fields.asteroids = {
	name = "Asteroid field",
	spawn = { 0, 0 },
	radius = 10000,
	build = function(game)
		game:spawnAsteroids(220)
	end,
}

Fields.giant = {
	name = "Giant asteroid",
	spawn = { 0, 2600 },
	radius = 10000,
	build = function(game)
		game:spawnGiantAsteroid(0, 0, 1800)
		game:spawnAsteroids(110)
	end,
}

-- A rectangle from (x1,y1) to (x2,y2) with the given half-width, as a polygon.
local function bar(x1, y1, x2, y2, hw)
	local dx, dy = x2 - x1, y2 - y1
	local l = math.sqrt(dx * dx + dy * dy)
	local nx, ny = -dy / l * hw, dx / l * hw
	return { x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny }
end

local function ngon(cx, cy, r, n, rot)
	local v = {}
	for i = 0, n - 1 do
		local a = (rot or 0) + i / n * pi * 2
		table.insert(v, cx + cos(a) * r)
		table.insert(v, cy + sin(a) * r)
	end
	return v
end

Fields.station = {
	name = "Space station",
	spawn = { 0, 1500 },
	radius = 9000,
	build = function(game)
		-- Hub
		game:addStructure(ngon(0, 0, 230, 8, pi / 8), { role = "hub" })
		-- Four arms out to docking pods
		for k = 0, 3 do
			local a = k * pi / 2 + pi / 4
			local cx, cy = cos(a), sin(a)
			game:addStructure(bar(cx * 210, cy * 210, cx * 560, cy * 560, 34), { role = "arm" })
			game:addStructure(ngon(cx * 640, cy * 640, 100, 6, a), { role = "pod" })
		end
		-- Outer ring: segments with four gaps (on the axes) to fly through.
		local R, seg = 1000, 28
		for i = 0, seg - 1 do
			local a1, a2 = i / seg * pi * 2, (i + 1) / seg * pi * 2
			local mid = (a1 + a2) / 2
			local gap = false
			for k = 0, 3 do
				local d = math.abs(((mid - k * pi / 2) + pi) % (2 * pi) - pi)
				if d < pi / seg * 1.6 then gap = true end
			end
			if not gap then
				game:addStructure(bar(cos(a1) * R, sin(a1) * R, cos(a2) * R, sin(a2) * R, 26), { role = "ring" })
			end
		end
		-- A thin scattering of rocks well outside.
		game:spawnAsteroids(70, 1500)
	end,
}

Fields.planet = {
	name = "Planet",
	spawn = { 0, 14200 },
	radius = 24000,
	rockDrag = 0,
	build = function(game)
		-- 15000 px across: too big to see whole even zoomed all the way out.
		local R = 7500
		game:spawnPlanet(0, 0, R, 45, 0.1)
		-- A belt of rocks already in orbit, going the way the well turns.
		local w = game.well
		local placed = 0
		for _ = 1, 2000 do
			if placed >= 180 then break end
			local radius = 24 + random() ^ 2 * 80
			local a = random() * pi * 2
			local d = R + 1500 + random() * 4500
			local x, y = cos(a) * d, sin(a) * d
			if game:isClear(x, y, radius + 60) then
				local e = game:spawnAsteroid(x, y, radius)
				local v = math.sqrt(w.gm / d)
				e.body:setLinearVelocity(-sin(a) * v, cos(a) * v)
				placed = placed + 1
			end
		end
		game:spawnAsteroids(80, R + 7500)
	end,
}

return Fields
