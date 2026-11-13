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
	    assembly = "intaki_assembly",   optional: installed assembly facility;
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
	if mk and mk.dealer then return mk.dealer end
 local place=require('src.locations').byId[require('src.stockpile').key(st)]
 -- a used lot only where there's a yard to sell from, and a small one:
 -- the dealerships are where the ships are
 local yard=false;for _,sv in ipairs(place and place.services or {}) do if sv=='shipyard' then yard=true end end
 if place and place.kind=='station' and not place.accessOf and yard then
  local policy=require('data.industry').usedShips
  return {name='Used ship exchange',hulls={'intaki_wisp'},lots=policy.lots,restock=policy.intervalHours,usedOnly=true}
 end
end

-- Used exchanges fill gaps in ship sales, never a factory's output space.
function D.buildsShips(st)
 local I=require('src.industry');local C=require('src.commodities')
 for id,installation in pairs(I.installations(require('src.stockpile').key(st))) do
  for _,recipe in ipairs(I.definition(id,installation).recipes) do
   for _,output in ipairs(C.byId[recipe].outputs or {}) do if output.kind=='ship' then return true end end
  end
 end
 return false
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
  cargo={[require('src.reactor_fuel').item()]=2},
  armor=require('src.stats').compute(hull,trim.loadout).armor,
	}
end

function D.rollUsed(def,state)
 local policy=require('data.industry').usedShips
 local preset=data.enemies[policy.presets[rand(#policy.presets)]]
 local lot=D.roll({hulls={preset.hull},trims={'stock'},markup=policy.markup},state,preset.hull)
 lot.loadout=copy(preset.loadout or data.hulls[preset.hull].loadout)
 lot.used=true;lot.condition=policy.minCondition+(policy.maxCondition-policy.minCondition)*rand(1000)/1000
 lot.trimName='Used';lot.price=D.price(data.hulls[lot.hull],lot.loadout,policy.markup*lot.condition)
 local stats=require('src.stats').compute(data.hulls[lot.hull],lot.loadout)
 lot.armor=stats.armor*lot.condition
 lot.cargo={[require('src.reactor_fuel').item()]=2}
 return lot
end
local function park(u,key,s,lot)
 -- used ships sit wherever: about half outside on the berths, half inside
 local h=0;for c in tostring(lot.id or #s.lots):gmatch('.') do h=(h*31+c:byte())%997 end
 local parking=require('src.dealer_parking').plan(u,key,lot.hull,1,h%2==0 and 'outside' or 'inside')[1]
 if not parking then return false end
 lot.bay,lot.mooring=parking.bay,parking.mooring;s.lots[#s.lots+1]=lot;return true
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
		local opening=def.usedOnly and (D.buildsShips(key) and 0 or 1) or cap
		for _=1,opening do
   local lot=def.usedOnly and D.rollUsed(def,s) or D.roll(def,s);local parking=require('src.dealer_parking').plan(u,key,lot.hull,1,(not def.usedOnly and D.buildsShips(key) or #s.lots%2==0) and 'outside' or 'inside')[1]
   if parking then lot.bay,lot.mooring=parking.bay,parking.mooring;s.lots[#s.lots+1]=lot end
  end
	end

 for _,lot in ipairs(s.lots) do lot.dealerStock=true end
	return s, def
end

-- Scheduled by industry, never by UI/read access.
function D.update(u,key,clock)
 local s,def=D.state(u,key);if not s then return end
 require('src.npc_ship_supply').wholesale(u,key,s,def,clock)
 if D.buildsShips(key) then return end
 local policy=require('data.industry').usedShips
 local step=(def.restock or policy.intervalHours)*HOUR
 s.next=s.next or clock+step
 local elapsed=math.max(0,math.floor((clock-s.next)/step)+1)
 local count=math.min(elapsed,math.max(0,(def.lots or 6)-#s.lots))
 for _=1,count do park(u,key,s,def.usedOnly and D.rollUsed(def,s) or D.roll(def,s)) end
 s.next=s.next+elapsed*step
end
function D.room(u,key,hull)
 local s,def=D.state(u,key);if not s then return 0 end
 local allowed=false;for _,id in ipairs(def.hulls) do if id==hull then allowed=true end end
 if not allowed then return 0 end
 -- A factory dealer fills whatever commercial parking it has (the guest
 -- share stays reserved); "lots" only caps restocking dealers.
 local cap=D.buildsShips(key) and 64 or math.max(0,(def.lots or 6)-#s.lots)
 return #require('src.dealer_parking').plan(u,key,hull,cap,'outside')
end
function D.output(u,key,hull,n)
 local s,def=D.state(u,key)
 assert(D.room(u,key,hull)>=n,'dealer output overflow')
 -- new ships go on display outside, on the berths, while there's room
 local placements=require('src.dealer_parking').plan(u,key,hull,n,'outside')
 assert(#placements==n,'no physical space for manufactured ship')
 for i=1,n do
  local lot=D.roll(def,s,hull);lot.manufacturedAt=u.clock;lot.bay,lot.mooring=placements[i].bay,placements[i].mooring;s.lots[#s.lots+1]=lot
 end
 require('src.npc_ship_supply').produced(u,key,hull,n)
end
-- Only empty sales slots request incoming frames; full lots have no
-- standing construction demand. Inventory queries need not build ships.
function D.frameTarget(u,key)
 local def=D.def(key);if not def or not def.assembly then return 0 end
 local installation=require('src.industry').installations(key)[def.assembly]
 if not installation then return 0 end
 local I,C=require('src.industry'),require('src.commodities')
 local selected=I.job(u,key,def.assembly,I.definition(def.assembly,installation))
 local recipe=C.byId[selected]
 if not recipe or D.room(u,key,recipe.outputs[1].hull)<1 then return 0 end
 for _,input in ipairs(C.inputs(recipe)) do if input.item==D.FRAME then return math.ceil(input.n) end end
 return 0
end
function D.lots(u, st)
 -- Sale stock is physically parked at the primary anchor, not cloned at
 -- every access point that shares the station's market.
 local id=type(st)=='table' and (st.locationId or st.key) or st
 if require('src.locations').canonical(id)~=id then return {} end
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

function D.ship(lot)
 return {hull=lot.hull,loadout=copy(lot.loadout),cargo=copy(lot.cargo),armor=lot.armor,
  color=Paint.preset(lot.paint),fuelCharge=0,fuelInitialized=true}
end
function D.purchaseCandidate(u,area,policy,usedOnly)
 local L=require('src.locations');local best
 for _,key in ipairs(L.stations(area)) do
  for _,lot in ipairs(D.lots(u,key)) do
   local r={ship=D.ship(lot)};local stats=require('src.stats').compute(data.hulls[lot.hull],lot.loadout)
   local capabilities=require('src.npc_access').capabilities(r);local eligible=(not usedOnly or lot.used) and lot.price<=policy.budget and stats.thrust>0 and stats.powerOut>0 and require('src.reactor_fuel').remaining(r.ship)>0
   if (stats.hold or 0)<(policy.minCargo or 0) then eligible=false end
   for capability in pairs(policy.requires or {}) do if not capabilities[capability] then eligible=false end end
   if eligible and (not best or lot.price<best.lot.price or lot.price==best.lot.price and key<best.station) then best={station=key,lot=lot} end
  end
 end
 return best
end
function D.buyForNpc(u,r,candidate,policy)
 local lot=D.find(u,candidate.station,candidate.lot.id)
 if lot~=candidate.lot then return false end
 D.take(u,candidate.station,lot.id)
 r.shipAcquisition={station=candidate.station,lot=lot.id,price=lot.price,budget=policy.budget,used=lot.used or false}
 r.credits=(r.credits or 0)+policy.budget-lot.price
 require('src.simulation_history').note(u,'npc_ship_purchased',u.clock,r.area,{r.id},{station=candidate.station,hull=lot.hull,price=lot.price,lot=lot.id},candidate.station)
 return true
end

return D
