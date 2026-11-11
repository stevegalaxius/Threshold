--[[
	Ship dealerships. A station's market profile (data/markets.lua) can name
	a dealer:

	  dealer = {
	    name     = "Hub Motors",        shown on the Shipyard tab
	    hulls    = { hull ids },        the range it sells (weighted equally)
	    lots     = 6,                   most ships on the lot at once
	    restock  = 10,                  game hours for one more ship to arrive
	    markup   = 1.0,                 on list price (0.85 for a used lot)
	    trims    = { "stock", ... },    which trims it rolls (default all)
	    frameSupply = true,            optional: consume delivered hull frames;
	                                    ships roll out of finished hull_frame
	                                    stock instead of arriving on a timer
	  }

	Every ship on the lot is a specific one: { id, hull, trim, paint,
	loadout, price }. Buying one takes it off the lot for good; the lot
	refills one ship at a time. State: universe.dealers[station key].

	Trims: a hull's own variants = { { id, name, loadout } } plus two made
	from its stock fit, "stripped" (hardpoints empty) and "stock".
]]

local data = require("src.data")
local Paint = require("src.paint")

local D = {}
local floor, max = math.floor, math.max
local HOUR = 3600
D.FRAME = "hull_frame"

local function copy(t) local o = {}; for k, v in pairs(t or {}) do o[k] = v end; return o end

function D.def(st)
	local mk = require("src.stockpile").definition(st)
	return mk and mk.dealer
end

local function fitValue(hull, loadout)
	local v = 0
	for i in ipairs(hull.slots) do
		local m = loadout and loadout[i] and data.modules[loadout[i]]
		if m then v = v + (m.price or 0) end
	end
	return v
end

-- A hull's trims: { id, name, loadout }.
function D.trims(hull)
	local out = {}
	local stripped = copy(hull.loadout)
	for i, slot in ipairs(hull.slots) do if slot.family == "hardpoint" then stripped[i] = false end end
	out[#out + 1] = { id = "stripped", name = "Stripped", loadout = stripped }
	out[#out + 1] = { id = "stock", name = "Stock", loadout = copy(hull.loadout) }
	for _, v in ipairs(hull.variants or {}) do
		out[#out + 1] = { id = v.id or v.name, name = v.name or v.id, loadout = data.fitLoadout(hull, v.loadout) }
	end
	return out
end

-- List price of a hull with this fit: the hull's price buys its stock fit.
function D.price(hull, loadout, markup)
	local v = (hull.price or 0) + fitValue(hull, loadout) - fitValue(hull, hull.loadout)
	return floor(max(0, v) * (markup or 1) / 10 + 0.5) * 10
end

-- Hull frames a hull takes to build: one per 20k of list price.
function D.frames(hull) return max(1, math.ceil((hull.price or 0) / 20000)) end

local function rand(n) return love and love.math and love.math.random(n) or math.random(n) end

function D.roll(def, state, hullId)
	local hull = data.hulls[hullId or def.hulls[rand(#def.hulls)]]
	if not hull then return nil end
	local pool = {}
	for _, t in ipairs(D.trims(hull)) do
		local ok = not def.trims
		for _, id in ipairs(def.trims or {}) do if id == t.id then ok = true end end
		if ok then pool[#pool + 1] = t end
	end
	if #pool == 0 then pool = { D.trims(hull)[2] } end
	local trim = pool[rand(#pool)]
	local paints = Paint.pool(hull)
	state.serial = (state.serial or 0) + 1
	return {
		id = state.serial, hull = hull.id, trim = trim.id, trimName = trim.name,
		paint = paints[rand(#paints)], loadout = trim.loadout,
		price = D.price(hull, trim.loadout, def.markup),
	}
end

-- Hulls a manufacturer can build from the frames it has.
local function buildable(def, frames)
	local out = {}
	for _, id in ipairs(def.hulls) do
		local h = data.hulls[id]
		if h and D.frames(h) <= frames then out[#out + 1] = id end
	end
	return out
end

local function manufacture(u, key, def, s)
	local S = require("src.stockpile")
	while #s.lots < (def.lots or 6) do
		local have = S.available(u, key, D.FRAME)
		local ids = buildable(def, have)
		if #ids == 0 then return end
		local id = ids[rand(#ids)]
		local amount=D.frames(data.hulls[id])
		assert(S.take(u,key,D.FRAME,amount))
		require('src.economy').consume(u,key,D.FRAME,amount)
		s.lots[#s.lots + 1] = D.roll(def, s, id)
	end
end

-- The station's lot, caught up to now. nil if it has no dealer.
function D.state(u, st)
	local def = D.def(st)
	if not def then return nil end
	local key = require("src.stockpile").key(st)
	u.dealers = u.dealers or {}
	local s = u.dealers[key]
	local clock = u.clock or 0
	local cap = def.lots or 6
	if not s then
		s = { lots = {}, next = clock + (def.restock or 10) * HOUR }
		u.dealers[key] = s
		for _ = 1, math.ceil(cap * 0.6) do s.lots[#s.lots + 1] = D.roll(def, s) end
	end
	if def.frameSupply then
		manufacture(u, key, def, s)
	else
		local step = (def.restock or 10) * HOUR
		while clock >= s.next do
			if #s.lots < cap then s.lots[#s.lots + 1] = D.roll(def, s) end
			s.next = s.next + step
		end
	end
	return s, def
end

-- Only empty sales slots request incoming frames; full lots have no
-- standing construction demand. Inventory queries need not build ships.
function D.frameTarget(u,key)
 local def=D.def(key);if not def or not def.frameSupply then return 0 end
 local state=u.dealers and u.dealers[key]
 local empty=math.max(0,(def.lots or 6)-(state and #state.lots or 0))
 local largest=1
 for _,id in ipairs(def.hulls) do largest=math.max(largest,D.frames(data.hulls[id])) end
 return empty*largest
end
function D.lots(u, st)
	local s = D.state(u, st)
	return s and s.lots or {}
end

function D.find(u, st, id)
	for i, lot in ipairs(D.lots(u, st)) do if lot.id == id then return lot, i end end
end

-- Take a ship off the lot (it's been sold).
function D.take(u, st, id)
	local s = D.state(u, st)
	local _, i = D.find(u, st, id)
	if i then return table.remove(s.lots, i) end
end

return D
