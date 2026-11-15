--[[
	The search behind an NPC's detour round scenery (Nav.waypoint,
	src/local_navigation.lua): A* over a grid of points between the ship and
	where it's going, then the path pulled straight wherever it can be.

	It works on plain numbers only (the ship's circle, the obstacles as
	circles and polygons with their bounds), so the background thread can
	run it (src/worker_jobs.lua). P.pack / P.unpack carry the obstacles
	across as one block of numbers.

	P.search returns { path = { {x, y}, ... }, ttl = seconds to keep it }.
]]
local Sweep = require("src.collision_prediction")
local ffi = require("ffi")
local sqrt, min, max = math.sqrt, math.min, math.max
local P = {}

local function distance(ax, ay, bx, by) return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- The grid's pitch, and so how far past the padding its points can reach.
function P.step(radius, padding, direct) return max(180, radius * 2, (direct + padding * 2) / 36) end

function P.search(x, y, gx, gy, radius, padding, direct, prims)
	local function clear(ax, ay, bx, by)
		local loX, hiX = min(ax, bx) - radius, max(ax, bx) + radius
		local loY, hiY = min(ay, by) - radius, max(ay, by) + radius
		for i = 1, #prims do
			local o = prims[i]
			if o.maxx >= loX and o.minx <= hiX and o.maxy >= loY and o.miny <= hiY
				and Sweep.sweepCircle(ax, ay, radius, o, bx - ax, by - ay, 1) then return false end
		end
		return true
	end
	local step = P.step(radius, padding, direct)
	local minx, miny = min(x, gx) - padding, min(y, gy) - padding
	local nx = math.ceil((math.abs(gx - x) + padding * 2) / step)
	local ny = math.ceil((math.abs(gy - y) + padding * 2) / step)
	local function heuristic(px, py) return distance(px, py, gx, gy) end
	local start = { x = x, y = y, cost = 0 }; start.score = direct
	local open = { start }; local nodes = {}; local finish
	local directions = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
	for _ = 1, 1600 do
		if #open == 0 then break end
		local best = 1
		for i = 2, #open do if open[i].score < open[best].score then best = i end end
		local current = table.remove(open, best); current.closed = true
		if heuristic(current.x, current.y) < step * 2 and clear(current.x, current.y, gx, gy) then finish = current; break end
		local ix = math.floor((current.x - minx) / step + .5)
		local iy = math.floor((current.y - miny) / step + .5)
		for _, v in ipairs(directions) do
			local cx, cy = ix + v[1], iy + v[2]
			if cx >= 0 and cx <= nx and cy >= 0 and cy <= ny then
				local key = cx + cy * (nx + 1); local node = nodes[key]
				if not node or not node.closed then
					local px, py = minx + cx * step, miny + cy * step
					local cost = current.cost + distance(current.x, current.y, px, py)
					if (not node or cost < node.cost) and clear(current.x, current.y, px, py) then
						if not node then node = { x = px, y = py }; nodes[key] = node; open[#open + 1] = node end
						node.cost, node.score, node.parent = cost, cost + heuristic(px, py), current
					end
				end
			end
		end
	end
	if not finish then return { path = { { gx, gy } }, ttl = 2 } end
	local reverse = { { gx, gy } }
	while finish.parent do reverse[#reverse + 1] = { finish.x, finish.y }; finish = finish.parent end
	local path = {}; local ax, ay = x, y; local i = #reverse
	while i >= 1 do
		local nextIndex = i
		for j = 1, i do if clear(ax, ay, reverse[j][1], reverse[j][2]) then nextIndex = j; break end end
		local point = reverse[nextIndex]; path[#path + 1] = point; ax, ay = point[1], point[2]; i = nextIndex - 1
	end
	return { path = path, ttl = 8 }
end

-- Obstacles as doubles: for each, the count of numbers that follow, then a
-- circle's x, y, r (three) or a polygon's points (four or more).
function P.pack(prims)
	local n = 0
	for i = 1, #prims do n = n + 1 + (prims[i].r and 3 or #prims[i].p) end
	local data = love.data.newByteData(max(1, n) * 8)
	local d = ffi.cast("double*", data:getFFIPointer())
	local k = 0
	for i = 1, #prims do
		local o = prims[i]
		if o.r then
			d[k], d[k + 1], d[k + 2], d[k + 3] = 3, o.x, o.y, o.r; k = k + 4
		else
			local p = o.p
			d[k] = #p; k = k + 1
			for j = 1, #p do d[k] = p[j]; k = k + 1 end
		end
	end
	return { data = data, n = n }
end
function P.unpack(packed)
	local d = ffi.cast("double*", packed.data:getFFIPointer())
	local prims, k = {}, 0
	while k < packed.n do
		local count = d[k]; k = k + 1
		local o
		if count == 3 then
			o = { x = d[k], y = d[k + 1], r = d[k + 2] }
			o.minx, o.miny, o.maxx, o.maxy = o.x - o.r, o.y - o.r, o.x + o.r, o.y + o.r
		else
			local p = {}
			local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
			for j = 1, count, 2 do
				local px, py = d[k + j - 1], d[k + j]
				p[j], p[j + 1] = px, py
				minx, maxx, miny, maxy = min(minx, px), max(maxx, px), min(miny, py), max(maxy, py)
			end
			o = { p = p, minx = minx, miny = miny, maxx = maxx, maxy = maxy }
		end
		k = k + count
		prims[#prims + 1] = o
	end
	return prims
end

return P
