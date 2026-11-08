--[[
	Spawn sets (data/spawn_sets.lua): placing containers and crates in an
	area. An area's generated baseline is placed when its map is built; once
	the area has been saved, its saved objects replace that baseline
	(Game:restoreArea), so each set lands once per save and nothing restocks
	by itself. Events place more with Spawn.place(game, setId).
]]
local data = require("src.data")
local LT = require("src.loot_tables")
local Spawn = {}

local function count(c)
	if type(c) == "number" then return c end
	c = c or { 1, 1 }
	return love.math.random(c[1] or 1, math.max(c[1] or 1, c[2] or c[1] or 1))
end

-- A clear spot in a zone: "field" (anywhere past minD), or { x, y, r }.
local function spot(game, zone, minD)
	for _ = 1, 30 do
		local x, y
		if type(zone) == "table" then
			local a, d = love.math.random() * math.pi * 2, love.math.random() * (zone.r or zone[3] or 0)
			x, y = (zone.x or zone[1]) + math.cos(a) * d, (zone.y or zone[2]) + math.sin(a) * d
		else
			local a = love.math.random() * math.pi * 2
			local lo = minD or 600
			local d = lo + love.math.random() * math.max(0, game.arenaRadius - lo - 300)
			x, y = math.cos(a) * d, math.sin(a) * d
		end
		if game:isClear(x, y, 80) then return x, y end
	end
end

-- Place one entry: crates (an item such as cargo_container) or container
-- objects drawn in the Shipyard, each filled from its loot table.
function Spawn.entry(game, p, minD)
	local placed = {}
	local ctx = { area = game.fieldId }
	for _ = 1, count(p.count) do
		local x, y = spot(game, p.zone or "field", minD)
		if not x then break end
		local e
		if p.container and data.wrecks[p.container] then
			e = game:spawnWreck(p.container, x, y, nil, nil, nil, p.loot)
		elseif data.items[p.item or "cargo_container"] then
			local id = p.item or "cargo_container"
			e = game:spawnContainer(x, y, id, false)
			game:fillContainer(e, LT.fill(data.items[id], ctx, p.loot))
		end
		placed[#placed + 1] = e
	end
	return placed
end

-- Place a whole set in the loaded area.
function Spawn.place(game, setId, minD)
	local set = data.spawnSets[setId]
	if not set then return {} end
	local out = {}
	for _, p in ipairs(set.place) do
		for _, e in ipairs(Spawn.entry(game, p, minD)) do out[#out + 1] = e end
	end
	return out
end

-- Does a set apply to an area? areas = "all", { area = true }, or area = id.
function Spawn.applies(set, area)
	if set.areas == "all" then return true end
	if type(set.areas) == "table" then return set.areas[area] == true end
	return set.area == area
end

-- The baseline for the area being built: every set that applies there.
function Spawn.baseline(game, minD)
	for _, id in ipairs(data.list.spawnSets) do
		if Spawn.applies(data.spawnSets[id], game.fieldId) then Spawn.place(game, id, minD) end
	end
end

return Spawn
