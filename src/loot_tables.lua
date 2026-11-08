--[[
	Loot tables: the one roller behind every container, crate and chest.
	Tables live in data (data/loot_tables.lua, api.loot_table). An entry is
	an item ({ item = id, min, max, weight }) or another table
	({ table = id, weight }); either may carry areas = { area = true } to
	only count there. A table makes rolls = { min, max } weighted picks,
	plus everything in guaranteed.

	    LootTables.roll("lost_cargo", { area = "saturn" }) -> { item = count }
]]
local data = require("src.data")
local LT = {}

local function rnd(rng, a, b)
	if b <= a then return a end
	return rng and rng:random(a, b) or love.math.random(a, b)
end
local function frac(rng) return rng and rng:random() or love.math.random() end

local function fits(entry, ctx)
	if entry.areas and not (ctx.area and entry.areas[ctx.area]) then return false end
	if entry.item and not data.items[entry.item] then return false end
	if entry.table and not data.lootTables[entry.table] then return false end
	return true
end

local add
local function take(entry, ctx, out, rng, depth)
	if entry.table then return add(entry.table, ctx, out, rng, depth + 1) end
	local lo = entry.min or entry[2] or 1
	local n = rnd(rng, lo, math.max(lo, entry.max or entry[3] or lo))
	if n > 0 then out[entry.item] = (out[entry.item] or 0) + n end
end
function add(id, ctx, out, rng, depth)
	local t = data.lootTables[id]
	if not t or depth > 8 then return out end
	if t.areas and not (ctx.area and t.areas[ctx.area]) then return out end
	for _, g in ipairs(t.guaranteed) do if fits(g, ctx) then take(g, ctx, out, rng, depth) end end
	local pool, total = {}, 0
	for _, e in ipairs(t.entries) do
		if fits(e, ctx) then pool[#pool + 1] = e; total = total + (e.weight or 1) end
	end
	if total <= 0 then return out end
	for _ = 1, rnd(rng, t.rolls[1] or 1, t.rolls[2] or t.rolls[1] or 1) do
		local r = frac(rng) * total
		for _, e in ipairs(pool) do
			r = r - (e.weight or 1)
			if r <= 0 then take(e, ctx, out, rng, depth) break end
		end
	end
	return out
end

-- Roll a table: counts by item id. ctx: { area = id }; rng: optional
-- love RandomGenerator (seeded rolls for previews and tests).
function LT.roll(id, ctx, rng)
	return add(id, ctx or {}, {}, rng, 0)
end

-- An old inline loot list ({ { item, min, max, chance }, ... }) rolled the
-- old way: each line on its own chance.
function LT.rollInline(list, rng)
	local out = {}
	for _, l in ipairs(list or {}) do
		local item, lo, hi, chance = l[1], l[2] or 1, l[3] or l[2] or 1, l[4] or 1
		if data.items[item] and frac(rng) < chance then out[item] = (out[item] or 0) + rnd(rng, lo, math.max(lo, hi)) end
	end
	return out
end

-- What a container object or crate item holds when placed: its loot table
-- (or the one the placement names), else its inline list.
function LT.fill(def, ctx, tableId, rng)
	tableId = tableId or def.lootTable
	if tableId then return LT.roll(tableId, ctx, rng) end
	if def.loot and #def.loot > 0 then return LT.rollInline(def.loot, rng) end
	return {}
end

return LT
