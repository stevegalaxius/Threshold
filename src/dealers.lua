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
	    assembly = "ship_assembly",     optional: installed assembly facility;
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
		id = state.serial, hull = hull.id, dealerStock=true, trim = trim.id, trimName = trim.name,
		paint = paints[rand(#paints)], loadout = trim.loadout,
		price = D.price(hull, trim.loadout, def.markup),
	}
end

-- Read/initialize dealer inventory. Reads never advance replenishment.
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
		for _=1,math.ceil(cap*.6) do
   local lot=D.roll(def,s);local parking=require('src.dealer_parking').plan(u,key,lot.hull,1)[1]
   if parking then lot.bay,lot.mooring=parking.bay,parking.mooring;s.lots[#s.lots+1]=lot end
  end
	end

 for _,lot in ipairs(s.lots) do lot.dealerStock=true end
	return s, def
end

-- Scheduled by industry, never by UI/read access.
function D.update(u,key,clock)
 local s,def=D.state(u,key);if not s or def.assembly then return end
 local step=(def.restock or 10)*HOUR
 local elapsed=math.max(0,math.floor((clock-s.next)/step)+1)
 local count=math.min(elapsed,math.max(0,(def.lots or 6)-#s.lots))
 for _=1,count do
  local lot=D.roll(def,s);local parking=require('src.dealer_parking').plan(u,key,lot.hull,1)[1]
  if parking then lot.bay,lot.mooring=parking.bay,parking.mooring;s.lots[#s.lots+1]=lot end
 end
 s.next=s.next+elapsed*step
end
function D.room(u,key,hull)
 local s,def=D.state(u,key);if not s then return 0 end
 local allowed=false;for _,id in ipairs(def.hulls) do if id==hull then allowed=true end end
 if not allowed then return 0 end
 return #require('src.dealer_parking').plan(u,key,hull,math.max(0,(def.lots or 6)-#s.lots))
end
function D.output(u,key,hull,n)
 local s,def=D.state(u,key)
 assert(D.room(u,key,hull)>=n,'dealer output overflow')
 local placements=require('src.dealer_parking').plan(u,key,hull,n)
 assert(#placements==n,'no physical space for manufactured ship')
 for i=1,n do
  local lot=D.roll(def,s,hull);lot.bay,lot.mooring=placements[i].bay,placements[i].mooring;s.lots[#s.lots+1]=lot
 end
end
-- Only empty sales slots request incoming frames; full lots have no
-- standing construction demand. Inventory queries need not build ships.
function D.frameTarget(u,key)
 local def=D.def(key);if not def or not def.assembly then return 0 end
 local installation=require('src.industry').installations(key)[def.assembly]
 if not installation then return 0 end
 local s=D.state(u,key);local maximum,slots=0,0
 for _,id in ipairs(require('src.industry').definition(def.assembly,installation).recipes) do
  local recipe=require('src.commodities').byId[id]
  local room=D.room(u,key,recipe.outputs[1].hull)
  if room>0 then
   slots=math.max(slots,room)
   for _,input in ipairs(require('src.commodities').inputs(recipe)) do if input.item==D.FRAME then maximum=math.max(maximum,input.n) end end
  end
 end
 return math.min(math.max(0,(def.lots or 6)-#s.lots),slots)*maximum
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
