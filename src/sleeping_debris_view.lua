-- Render culling only. Stationary rocks use a grid, orbiting rocks use
-- radial bands, and linearly drifting rocks still get checked individually.
local View = {}
local CELL = 4096
local caches = setmetatable({}, { __mode = "k" })

local function bucket(buckets, key)
	local result = buckets[key]
	if not result then result = {}; buckets[key] = result end
	return result
end

local function add(cache, e)
	local group
	if e.sleep.still then
		local x, y = math.floor(e.body.x / CELL), math.floor(e.body.y / CELL)
		group = bucket(bucket(cache.columns, x), y)
	elseif e.sleep.r then
		group = bucket(cache.orbits, math.floor(e.sleep.r / CELL))
	else
		group = cache.drifting
	end
	group[e] = true
	cache.members[e] = group
end

function View.add(list, e)
	local cache = caches[list]
	if cache then add(cache, e) end
end

function View.remove(list, e)
	local cache = caches[list]
	if cache then
		cache.members[e][e] = nil
		cache.members[e] = nil
	end
end

function View.visit(list, x, y, hw, hh, nearest, furthest, stationary, moving)
	local cache = caches[list]
	if not cache then
		cache = { columns = {}, orbits = {}, drifting = {}, members = {} }
		for _, e in ipairs(list) do add(cache, e) end
		caches[list] = cache
	end
	local left, right = math.floor((x - hw) / CELL), math.floor((x + hw) / CELL)
	local top, bottom = math.floor((y - hh) / CELL), math.floor((y + hh) / CELL)
	for col = left, right do
		local column = cache.columns[col]
		if column then
			for row = top, bottom do
				local cell = column[row]
				if cell then
					for e in pairs(cell) do
						if not e.removed then stationary(e, e.body.x, e.body.y) end
					end
				end
			end
		end
	end
	if nearest then
		for band = math.floor(nearest / CELL), math.floor(furthest / CELL) do
			local group = cache.orbits[band]
			if group then
				for e in pairs(group) do moving(e) end
			end
		end
	end
	for e in pairs(cache.drifting) do moving(e) end
end

return View
