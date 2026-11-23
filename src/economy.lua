--[[
	The goods economy: stations order what they run short of, and haulers
	fill the orders from whoever has it. Nothing here is a hand-set route or
	a fixed amount; it settles from what stations actually use.

	  usage     every station keeps a decaying per-hour rate of what it uses
	            up (E.consume): fuel sold at Supplies, a commodity's use, a
	            recipe's inputs. Hauling stock out is not use.
	  target    how much a station wants on hand: service-use reserves plus
	            short factory buffers for allocated work with output room,
	            and never below service floors. Historical factory usage
	            does not keep importing inputs into a blocked factory.
	  orders    every E.tick seconds, for every good and every trade
	            station alike: a station that makes the good keeps
	            E.reserveHours of its use and offers the rest; any other
	            station below its target buys back up to twice it, and offers
	            whatever it holds over twice it. Buyers are served neediest
	            first, each from the nearest station with enough spare, in
	            orders of up to E.lot. Unclaimed orders expire after E.expire
	            and are placed again, so they follow wherever the stock is.
	  customs   a moon with a customs station (world_layout customs=true)
	            trades off the moon only through it: its factories ship
	            exports there, it passes them on to the planet's hub (or
	            the planet's stations), and goods for the moon arrive there.
	  hubs      a planet system with a logistics hub (world_layout hub=true)
	            trades with other systems only through it. The hub keeps a
	            depot of what its system uses but doesn't make (imports),
	            and collects what its system makes that other hubs import
	            (exports). Hub to hub is a trunk run: bigger lots, for bulk
	            freighters (T.trunkLot, T.trunkMinHold). Local stations
	            reorder from their hub instead of across the system.
	  stats     E.stat counts what was made, used and hauled of each good,
	            for the economy test's hourly table.

	Works on the universe table alone, so it runs the same offline.
]]
local L=require('src.locations')
local Fields=require('src.fields')
local Tasks=require('src.tasks')
local Transport=require('src.transport')
local Stock=require('src.stockpile')
local C=require('src.commodities')
local Food=require('src.food')
local T=require('src.tuning')
local Dark=require('src.dark')
local E={scaleMin=.25,scaleMax=4,scaleStep=.05,tick=60,lot=120,hours=2,halfLife=4*3600,expire=1200,reserveHours=1,scope='economy'}
-- Every trade station keeps at least this much of these on hand.
E.floor={deuterium_canister=40}
E.sliceFlows=6   -- stations caught up per piece of a spread update (E.spread)

-- Usage ----------------------------------------------------------------

local function record(u,key)
 local r=Stock.record(u,key);r.usage=r.usage or {};return r.usage
end
-- Running totals of what was made, used and hauled, by good.
function E.stat(u,kind,item,n)
 if not n or n<=0 then return end
 u.economyStats=u.economyStats or {}
 local t=u.economyStats[kind] or {};u.economyStats[kind]=t
 t[item]=(t[item] or 0)+n
end
-- Station credits (src/accounts.lua). Every credit a station pays
-- out (freight, buying from players) or takes in (selling to players) is
-- counted, per station and per game hour, so pay rates can be tuned
-- against the money they create. kind: 'freight', 'premium' (the scarcity
-- share of freight, also inside 'freight'), 'bought' (paid out), 'sold'
-- (taken in).
E.ledgerHours=48
function E.ledger(u,key,kind,n,item)
 if not n or n<=0 or not key then return end
 local book=u.economyLedger or {stations={},hours={}};u.economyLedger=book
 key=L.canonical(key)
 local s=book.stations[key] or {};book.stations[key]=s
 s[kind]=(s[kind] or 0)+n
 local hour=math.floor((u.clock or 0)/3600)
 local h=book.hours[hour]
 if not h then
  h={};book.hours[hour]=h
  for old in pairs(book.hours) do if old<=hour-E.ledgerHours then book.hours[old]=nil end end
 end
 h[kind]=(h[kind] or 0)+n
 if item then local byItem=h.items or {};h.items=byItem;local k=kind..':'..item;byItem[k]=(byItem[k] or 0)+n end
end
-- Net credits stations created in a game hour (paid out minus taken in).
function E.minted(u,hour)
 local h=u.economyLedger and u.economyLedger.hours[hour or math.floor((u.clock or 0)/3600)]
 if not h then return 0 end
 return (h.freight or 0)+(h.bought or 0)-(h.sold or 0)
end
function E.consume(u,key,item,n,industrial)
 if n<=0 or not u.clock then return end
 E.stat(u,'used',item,n)
 local m=record(u,key);local e=m[item] or {rate=0,at=u.clock}
 local dt=math.max(0,u.clock-e.at)
 -- an exponentially weighted rate, in units an hour
 local k=math.exp(-dt/E.halfLife)
 -- Older usage ledgers did not distinguish factory inputs from service.
 local inputs=e.inputRate
 if inputs==nil then
  inputs=0
  for _,c in ipairs(C.list) do if (c.make[key] or 0)>0 then
   for _,input in ipairs(C.inputs(c)) do if input.item==item then inputs=e.rate end end
  end end
 end
 e.inputRate=inputs*k+(industrial and n*3600/E.halfLife or 0)
 e.rate=e.rate*k;e.at=u.clock
 e.rate=e.rate+n*3600/E.halfLife
 m[item]=e
end
function E.rate(u,key,item)
 local e=record(u,key)[item];if not e then return 0 end
 return e.rate*math.exp(-math.max(0,u.clock-e.at)/E.halfLife)
end

-- Who uses and who supplies what -----------------------------------------

local function tradeStations(area) return L.stations(area,'trade') end
local function supportsSupplies(id) return require('src.supplies').supports(id) end
-- How hard a station runs each recipe, against its authored rate: it
-- speeds up while buyers of what it makes go short and it ships all it
-- makes, and slows down while its own stock sits unwanted (E.adjust).
function E.scale(u,key,c) return require('src.industry').scale(u,key,c) end
-- Whether the whole system is running down its stock of an item: all the
-- trade stations together hold less than T.adaptiveCushion times what
-- they want. A maker whose own shelf is full while everyone else drains
-- (the stock just hasn't been hauled away yet) must not throttle down.
local function draining(u,item,all)
 local have,want=0,0
 for _,s in ipairs(all) do have=have+Stock.count(u,s,item);want=want+E.target(u,s,item) end
 return want>0 and have<want*T.adaptiveCushion
end
-- The system-wide price of a good against its list price: the mean of
-- every trade station's price multiplier (1 = list).
function E.priceRatio(u,item,all)
 local Markets=require('src.markets');local list=require('src.data').items[item].price or 0
 if list<=0 or #all==0 then return end
 local sum=0;for _,s in ipairs(all) do sum=sum+Markets.price(u,s,item) end
 return sum/#all/list
end
local function adjust(u,unmet,all)
 u.industry=u.industry or {}
 local low={}
 for _,c in ipairs(C.list) do
  if c.adaptive then
  if low[c.item]==nil then low[c.item]=all and draining(u,c.item,all) or false end
  for key in pairs(c.make) do
   local t=u.industry[key] or {};u.industry[key]=t
   local v=t[c.id] or 1
   local have=Stock.count(u,key,c.item)
   -- some plants answer to the whole system's price of what they make
   -- (crack_ice: the universal price of fuel), not to their own shelf
   local ratio=c.globalPrice and all and E.priceRatio(u,c.item,all)
   if ratio then
    if ratio>1+T.globalPriceBand and have<(c.cap or math.huge)*.9 then v=v*(1+E.scaleStep)
    elseif ratio<1-T.globalPriceBand or have>=(c.cap or math.huge)*.9 then v=v*(1-E.scaleStep) end
   -- the system is running short: make more, unless its own storage is full
   elseif low[c.item] and have<(c.cap or math.huge)*.9 then v=v*(1+E.scaleStep)
   -- Unsupplied demand propagates upstream even while inputs are scarce,
   -- and before the shelf check: a plant holding a few lots must not slow
   -- while buyers elsewhere go without
   elseif (unmet[c.item] or 0)>0 and have<(c.cap or math.huge)*.9 then v=v*(1+E.scaleStep)
   -- stock piling up here slows it while the system is comfortable
   elseif have>=E.lot*2 then v=v*(1-E.scaleStep) end
   t[c.id]=math.max(E.scaleMin,math.min(E.scaleMax,v))
  end
  end
 end
 for _,c in ipairs(C.list) do for key,rate in pairs(c.use) do
  local t=u.industry[key] or {};u.industry[key]=t
  local target=math.max(E.scaleMin,math.min(1,Stock.available(u,key,c.item)/math.max(1,rate*E.hours)))
  local v=t[c.id] or 1;t[c.id]=v+math.max(-E.scaleStep,math.min(E.scaleStep,target-v))
 end end
end
-- One planning snapshot per station and phase of the minute update.
local planning
-- Outside the update, plans are remembered for one clock reading: a fast
-- step asks for the same station's plan for every ship it moves.
local loose=setmetatable({},{__mode='k'})
local function inputPlan(u,key)
 if not planning or planning.u~=u then
  local c=loose[u]
  if not c or c.clock~=u.clock then c={clock=u.clock,plans={}};loose[u]=c end
  local plan=c.plans[key]
  if not plan then plan=require('src.industry').inputPlan(u,key);c.plans[key]=plan end
  return plan
 end
 local plan=planning.stations[key]
 if not plan then plan=require('src.industry').inputPlan(u,key);planning.stations[key]=plan end
 return plan
end
-- Materialize one station's inputs per slice before targets start reading
-- them across the whole network. Market allocation starts a new snapshot.
local function preparePlans(u,stations,pause)
 planning={u=u,stations={}}
 for _,key in ipairs(stations) do
  inputPlan(u,key)
  pause()
 end
end
local function capacityUse(u,key,item)
 local n=item==Food.item and Food.rates(key) or 0
 for _,c in ipairs(C.byItem(item)) do n=n+(c.use[key] or 0) end
 return n+(inputPlan(u,key).rates[item] or 0)
end
local function serviceUse(u,key,item)
 local e=record(u,key)[item];if not e then return 0 end
 local inputs=e.inputRate
 if inputs==nil then
  inputs=0
  for _,c in ipairs(C.list) do if (c.make[key] or 0)>0 then
   for _,input in ipairs(C.inputs(c)) do if input.item==item then inputs=e.rate end end
  end end
 end
 return math.max(0,e.rate-inputs)*math.exp(-math.max(0,u.clock-e.at)/E.halfLife)
end
-- A supplier keeps only E.reserveHours of its own use back: what it makes
-- is for shipping, and hoarding hours of local sales starves everyone else.
-- (the minute update asks this for every good at every station, many times
-- over: it remembers the answers until it's done, in memo)
local memo
local function makesNow(key,item)
 local place=L.byId[key];if not place then return false end
 if item==Food.item then local _,make=Food.rates(key);return make>0 end
 return C.makes(key,item)
end
local function makes(key,item)
 if not memo then return makesNow(key,item) end
 if item==Food.item or not L.byId[key] then return makesNow(key,item) end
 local makers=memo.makers
 if not makers then
  -- every recipe once: who makes each good
  makers={};memo.makers=makers
  for _,c in ipairs(C.list) do for _,output in ipairs(C.outputs(c)) do if output.item then
   local set=makers[output.item];if not set then set={};makers[output.item]=set end
   for maker,rate in pairs(c.make) do if rate>0 then set[maker]=true end end
  end end end
 end
 local set=makers[item]
 return set~=nil and set[key]==true
end
local target
function E.target(u,key,item,supplier)
 -- (inside an update phase the answer can't change: remembered per phase)
 if planning and planning.u==u then
  local t=planning.targets;if not t then t={};planning.targets=t end
  local k=key..'|'..item..(supplier and '|s' or '')
  local v=t[k]
  if v==nil then v=target(u,key,item,supplier);t[k]=v end
  return v
 end
 return target(u,key,item,supplier)
end
target=function(u,key,item,supplier)
 local use=serviceUse(u,key,item)
 if item==Food.item then use=math.max(use,Food.rates(key)) end
 for _,c in ipairs(C.byItem(item)) do use=math.max(use,c.use[key] or 0) end
 local want=use*(supplier and E.reserveHours or E.hours)+(inputPlan(u,key).buffers[item] or 0)
 if item==require('src.dealers').FRAME then return require('src.dealers').frameTarget(u,key) end
 local floor=E.floor[item]
 if floor and supportsSupplies(key) then want=math.max(want,floor) end
 want=math.max(want,require('src.reserves').minimum(key,item))
 local place=L.byId[key]
 if place then want=math.max(want,place.reserves and place.reserves[item] or 0) end
 return math.ceil(want)
end
-- The goods that move: every commodity, its inputs, what the drills dig,
-- and reactor fuel. Every trade station can hold, sell and buy any of them;
-- nobody is listed by hand as a supplier or a user.
local function goods()
 if memo and memo.goods then return memo.goods end
 local set,list={},{}
 local function add(item) if item and not set[item] then set[item]=true;list[#list+1]=item end end
 for _,c in ipairs(C.list) do for _,output in ipairs(C.outputs(c)) do add(output.item) end;for _,input in ipairs(C.inputs(c)) do add(input.item) end end
 for _,item in pairs(require('src.ore').items) do add(item) end
 for _,item in pairs(require('src.ore').rare) do add(item) end
 add(require('src.reactor_fuel').item())
 add(Food.item)
 table.sort(list)
 if memo then memo.goods=list end
 return list
end
E.goods=goods
local function stations(food)
 local list={}
 for _,area in ipairs(Fields.list) do
  for _,id in ipairs(food and L.stations(area) or tradeStations(area)) do list[#list+1]=id end
 end
 return list
end

-- Distance between two stations, for picking the nearest supplier: the AU
-- between their planets (a moon counts as its planet), and 0 for the same.
local function root(area) local m=Fields.moons[area];return m and m.parent or area end
-- For hub routing the dark grids are one system: the dark network, whose
-- hub (Milliways, hub=true) is the one door between it and the white
-- systems. Distances still use the real planet (root).
local function hubRoot(area) if Dark.isDarkArea(area) then return 'dark' end return root(area) end
E.hubRoot=hubRoot
local function distance(a,b,clock)
 local ra,rb=root(L.byId[a].area),root(L.byId[b].area)
 if ra==rb then return 0 end
 if not Fields.orbits[ra] or not Fields.orbits[rb] then return 50 end
 return Fields.distance(ra,rb,clock)
end
local function reachable(a,b,clock)
 return a~=b and require('src.travelgraph').itinerary(a,b,clock)~=nil
end


-- Logistics hubs ---------------------------------------------------------

-- One plan per update: hubs[root]=station, want[hub][item] and kind
-- [hub][item] ('import' or 'export'), and made[root][item].
local hubPlan
-- What a hub or moon customs keeps for one of its stations: the station's
-- target and room for the lot it orders (E.orderLot) on top.
local function memberWant(u,s,item)
 local n=E.target(u,s,item,false)
 if n>0 and not makes(s,item) then n=n+E.orderLot(u,s,item) end
 return n
end
local function hubWants(u,all,pause)
 local plan={hubs={},want={},kind={},made={},u=u}
 for _,s in ipairs(all) do
  local p=L.byId[s]
  if p.hub then local r=hubRoot(p.area);if not plan.hubs[r] or s<plan.hubs[r] then plan.hubs[r]=s end end
 end
 if not next(plan.hubs) then return plan end
 for _,s in ipairs(all) do
  local r=hubRoot(L.byId[s].area);plan.made[r]=plan.made[r] or {}
  for _,item in ipairs(goods()) do if makes(s,item) then plan.made[r][item]=true end end
 end
 -- the drills count as making their ore: a system that mines a good
 -- exports it like one that makes it, instead of every hub importing it
 for _,site in pairs(require('src.mining').state(u).sites or {}) do
  local home=site.home and L.byId[site.home]
  if home and site.item then local r=hubRoot(home.area);plan.made[r]=plan.made[r] or {};plan.made[r][site.item]=true end
 end
 for _,h in pairs(plan.hubs) do plan.want[h],plan.kind[h]={},{} end
 -- moon customs: the depot every good leaving or reaching a moon goes
 -- through (on to its planet's hub). It holds what the moon imports for
 -- its stations and collects what the moon makes for export.
 plan.customs={}
 for _,s in ipairs(all) do
  local p=L.byId[s]
  if p.customs and (not plan.customs[p.area] or s<plan.customs[p.area]) then plan.customs[p.area]=s end
 end
 for area,cs in pairs(plan.customs) do
  plan.want[cs],plan.kind[cs]={},{}
  local made={}
  for _,s in ipairs(all) do if L.byId[s].area==area then for _,item in ipairs(goods()) do if makes(s,item) then made[item]=true end end end end
  for _,item in ipairs(goods()) do
   if made[item] then plan.want[cs][item],plan.kind[cs][item]=E.lot*2,'export'
   else
    local n=0
    for _,s in ipairs(all) do if s~=cs and L.byId[s].area==area then n=n+memberWant(u,s,item) end end
    if n>0 then plan.want[cs][item],plan.kind[cs][item]=n,'import' end
   end
  end
  if pause then pause() end
 end
 for _,item in ipairs(goods()) do
  if pause then pause() end
  local imported,total={},0
  for r,h in pairs(plan.hubs) do if not (plan.made[r] or {})[item] then
   local n=0
   for _,s in ipairs(all) do
    if s~=h and hubRoot(L.byId[s].area)==r then n=n+memberWant(u,s,item) end
   end
   imported[r]=n;total=total+n
   if pause then pause() end
  end end
  -- the systems that make it share the export stock between them: each
  -- exporting hub holds its share of what the importers want, not all of it
  local exporters=0
  for r in pairs(plan.hubs) do if not imported[r] then exporters=exporters+1 end end
  local share=math.ceil(total/math.max(1,exporters))
  for r,h in pairs(plan.hubs) do
   if imported[r] then plan.want[h][item],plan.kind[h][item]=imported[r],'import'
   else
    -- a system that makes the good exports it, unless its own makers
    -- can't cover its other stations: then the hub imports the gap (a
    -- small well that its own plants drink dry, a maker that's down)
    local short,spare=0,0
    for _,s in ipairs(all) do
     if s~=h and hubRoot(L.byId[s].area)==r then
      local n=Stock.count(u,s,item)
      if makes(s,item) then spare=spare+math.max(0,n-E.target(u,s,item,true))
      else short=short+math.max(0,memberWant(u,s,item)-n) end
     end
    end
    if short>spare then plan.want[h][item],plan.kind[h][item]=short-spare,'import'
    else plan.want[h][item],plan.kind[h][item]=share,'export' end
    if pause then pause() end
   end
  end
 end
 return plan
end
E.hubWants=hubWants
-- A station's measured service use of an item (units an hour, fading as it
-- goes stale): what src/economy_model.lua reads in live mode.
function E.serviceRate(u,key,item) return serviceUse(u,key,item) end
-- The smallest order worth posting for a good: one that pays a hauler at
-- least T.orderMinFreight over an AU, so cheap bulk (ore, ice) ships in big
-- lots and compact valuable goods in smaller ones; at least T.orderMinLoad
-- units and at most one ordinary lot (T.orderMaxVolume). A buyer's order
-- tops it up by a lot (E.orderLot): T.orderLotHours of its own use
-- (production inputs and service), never under the minimum.
local function orderCap(vol) return math.max(1,math.floor(T.orderMaxVolume/vol)) end
function E.minOrder(item)
 local d=require('src.data').items[item]
 local per=d.volume*(T.freightCreditsPerM3+T.freightCreditsPerM3AU)+(d.price or 0)*T.freightValueShare
 local n=math.ceil(math.max(0,T.orderMinFreight-T.freightHandling)/math.max(.01,per))
 return math.min(orderCap(d.volume),math.max(T.orderMinLoad,n))
end
-- What a buyer orders up to once it falls below its target (want): twice
-- the target, or the target and a lot on top. A maker keeps its target.
function E.orderLevel(u,key,item,want,producer)
 if producer or want<=0 then return want end
 return math.max(want*2,want+E.orderLot(u,key,item))
end
function E.orderLot(u,key,item)
 local vol=require('src.data').items[item].volume
 local rate=capacityUse(u,key,item)+serviceUse(u,key,item)
 return math.min(orderCap(vol),math.max(E.minOrder(item),math.ceil(rate*T.orderLotHours)))
end
-- The hub that serves a station's planet system, if it has one.
function E.hubFor(id)
 local p=L.byId[id];if not p then return end
 local r,best=hubRoot(p.area)
 for _,place in pairs(L.byId) do
  if place.kind=='station' and place.hub and hubRoot(place.area)==r and (not best or place.id<best) then best=place.id end
 end
 return best
end
-- Whether s may sell item to c under hub routing.
local function routed(plan,s,c,item)
 local as,ac=L.byId[s].area,L.byId[c].area
 -- dark goods enter the white network only at a fence, straight from
 -- any dark station; from there the white rules below move them on
 local darkS,darkC=Dark.isDarkNode(s),Dark.isDarkNode(c)
 if darkS and not darkC then return Dark.isFence(c) end
 local customs=plan.customs or {}
 local cs,cc=customs[as],customs[ac]
 if as==ac then
  -- a customs depot passes its moon's exports outward, never back in
  if s==cs and plan.kind[s][item]=='export' then return false end
 else
  -- off a moon only through its customs, onto a moon only into it
  if cs and s~=cs then return false end
  if cc and c~=cc then return false end
  -- customs sells its moon's imports only to that moon
  if s==cs and plan.kind[s][item]=='import' then return false end
 end
 local rs,rc=hubRoot(as),hubRoot(ac)
 local hs,hc=plan.hubs[rs],plan.hubs[rc]
 local kind=s==hs and plan.kind[s][item]
 if rs==rc then return kind~='export' or makes(s,item) end
 if kind=='import' then return false end
 -- a station in a system without a hub still buys straight from the
 -- maker; a hubbed system only takes deliveries at its hub, and between
 -- two hubbed systems it is hub to hub
 if hc and c~=hc then return false end
 if hs and hc and s~=hs then return false end
 return true
end
local function hubTarget(u,key,item,supplier)
 local plan=hubPlan
 if plan and plan.u==u and plan.want[key] then
  return math.max(plan.want[key][item] or 0,E.target(u,key,item,supplier))
 end
 return E.target(u,key,item,supplier)
end
E.hubTarget=hubTarget

-- Shortage lifetime belongs to the destination, not a replaceable offer.
function E.shortageAge(u,key,item,clock)
 local at=(Stock.record(u,key).shortages or {})[item]
 return at and math.max(0,clock-at) or 0
end
function E.shortage(u,key,item,have,want,clock)
 local record=Stock.record(u,key);record.shortages=record.shortages or {}
 if want>0 and have<want then record.shortages[item]=record.shortages[item] or clock
 else record.shortages[item]=nil end
end
-- Orders -----------------------------------------------------------------

-- The minute update, whole. pause (optional) is called between its pieces
-- (a station, a good): see E.spread, which uses it to run one piece a step.
local function run(u,clock,pause)
 pause=pause or function() end
 memo={}
 local state=Tasks.state(u)
 Transport.refreshOffers(u,clock)
 -- count what's ordered or on the way; an order nobody has taken in
 -- E.expire seconds is withdrawn, to be placed again from wherever the
 -- stock is now
 local committed={}
 for id,o in pairs(state.offers) do
  if o.layoutScope==E.scope then
   if o.state=='available' and clock-(o.placed or clock)>E.expire then state.offers[id]=nil
   else
    local k=o.target..'|'..o.item
    if o.state~='available' then committed[k]=(committed[k] or 0)+o.amount end
   end
  end
 end
 local reach={}
 local all=stations()
 local fences=Dark.fences()
 local inhabited=stations(true)
 require('src.industry').update(u,clock,inhabited,pause)
 pause()
 preparePlans(u,inhabited,pause)
 -- (the hub plan first: hubs and customs bid on the market for the stock
 -- they hold for their systems, so factories make it)
 hubPlan=nil
 local wants=hubWants(u,all,pause)
 hubPlan=wants
 pause()
 require('src.markets').update(u,clock,all,committed,pause)
 pause()
 preparePlans(u,inhabited,pause)
 -- Output bins may have filled since these orders were posted. Keep
 -- committed cargo, but release unclaimed excess rather than tying up sources.
 local levels,groups={},{}
 for _,o in pairs(state.offers) do
  if o.layoutScope==E.scope and o.state=='available' then
   local k=o.target..'|'..o.item
   if levels[k]==nil then
    levels[k]=0;groups[#groups+1]={key=k,target=o.target,item=o.item}
   end
  end
 end
 table.sort(groups,function(a,b)return a.key<b.key end)
 for i,g in ipairs(groups) do
  if (i-1)%8==0 then pause() end
  local producer=makes(g.target,g.item);local want=hubTarget(u,g.target,g.item,producer)
  levels[g.key]=E.orderLevel(u,g.target,g.item,want,producer)
 end
 pause()
 -- Claims, split loads and deliveries can arrive while targets are being
 -- calculated. Apply the limits in one pass over the current freight board.
 local remaining,availableOrders,claimed={},{},{}
 for id,o in pairs(state.offers) do if o.layoutScope==E.scope then
  local k=o.target..'|'..o.item
  if levels[k]~=nil then
   if o.state=='available' then availableOrders[#availableOrders+1]={id=id,o=o,key=k}
   else claimed[k]=(claimed[k] or 0)+o.amount end
  end
 end end
 table.sort(availableOrders,function(a,b)return tostring(a.id)<tostring(b.id) end)
 for _,entry in ipairs(availableOrders) do
  local o,k=entry.o,entry.key
  if remaining[k]==nil then
   local level=levels[k]
   if Dark.isFence(o.target) and o.source and Dark.isDarkNode(o.source) then
    level=math.max(level,math.floor(T.fenceStock/require('src.data').items[o.item].volume))
   end
   remaining[k]=math.max(0,level-Stock.count(u,o.target,o.item)-(claimed[k] or 0))
  end
  local amount=math.min(o.amount,remaining[k])
  if amount<=0 then state.offers[entry.id]=nil else o.amount=amount;remaining[k]=remaining[k]-amount end
 end
 pause()
 local inbound={}
 for _,o in pairs(state.offers) do if o.layoutScope==E.scope then
  local k=o.target..'|'..o.item;inbound[k]=(inbound[k] or 0)+o.amount
 end end
 -- what buyers wanted that no station could supply, by good
 local unmet={}
 for _,item in ipairs(goods()) do
  -- One rule for every good. A station that makes it keeps E.reserveHours
  -- of its own use and offers the rest. Any other station wants E.hours of
  -- its use; below that it buys back up to twice that, and anything over
  -- twice that is spare (a mine, a quarry, a hub that collected stock).
  local spare,buyers={},{}
  local participants=item==Food.item and inhabited or all
  -- what each source has promised to freight of this good (as
  -- Transport.reserved with open orders), summed in one pass over the
  -- board: asked station by station it was the slowest part of the update
  local promised={}
  for _,o in pairs(state.offers) do
   if o.item==item and o.order and o.source and not o.loaded then promised[o.source]=(promised[o.source] or 0)+(o.amount or 0) end
  end
  -- Cached routes and current stock can still hide costly dealer target checks.
  for i,s in ipairs(participants) do
   pause(i%8~=0)
   local count=Stock.count(u,s,item)
   local have=math.max(0,count-(promised[s] or 0))
   local producer=makes(s,item)
   local want=hubTarget(u,s,item,producer)
   E.shortage(u,s,item,count,want,clock)
   -- (a buyer orders up to a full lot over its target: a few hours of its
   -- own use, so the fleet moves the same goods in fewer, fuller trips)
   local level=E.orderLevel(u,s,item,want,producer)
   -- a hub's stock is all for passing on: imports to its own system,
   -- exports to other hubs (routed decides which way)
   spare[s]=have-((hubPlan.kind[s] and hubPlan.kind[s][item]) and 0 or level)
   local coming=have+(inbound[s..'|'..item] or 0)
   if want>0 and coming<want then buyers[#buyers+1]={c=s,short=level-coming,need=want-coming,fill=coming/want} end
  end
  -- neediest first: the emptiest shelf against its target gets first call
  table.sort(buyers,function(a,b) return a.fill<b.fill or a.fill==b.fill and a.c<b.c end)
  -- Two passes: first every buyer fills from its own network (white or
  -- dark), then what's still short may buy across. A dark farm feeds the
  -- dark stations before its surplus goes out to the white market.
  for pass=1,2 do
  for _,entry in ipairs(buyers) do
   local c,short=entry.c,entry.left or entry.short;local need=entry.need
   local darkBuyer=Dark.isDarkNode(c)
   -- a source waits until it can spare a full lot (E.orderLot) before it
   -- ships: a trickle of spare stock posted every minute filled the board
   -- with orders of a few cubic metres. Food, water and fuel take any part
   -- load once their shelf is bare.
   local critical=item==Food.item or item=='water' or item==require('src.reactor_fuel').item()
   -- (the gate is the volume floor alone: waiting for hours of use would
   -- leave a steady consumer dry while its supplier saves the lot up)
   -- Any bare shelf takes a part load too: a slow maker that can never
   -- spare a whole lot (composites, siloxanes, a small ice well) would
   -- otherwise hold its stock while every buyer sits empty.
   local minLot=Stock.count(u,c,item)==0 and T.orderMinLoad or E.minOrder(item)
   while short>0 do
    local best,bestScore
    for _,s in ipairs(participants) do
     -- hub to hub is a trunk run: it waits until the exporter can spare
     -- T.trunkMinOrders ordinary lots (at most a trunk lot), unless the
     -- importing hub is under half full
     local need=minLot
     if entry.fill>=.5 and hubPlan.kind[s] and hubPlan.kind[c] and root(L.byId[s].area)~=root(L.byId[c].area) then
      need=math.min(math.floor(T.trunkLot/require('src.data').items[item].volume),minLot*T.trunkMinOrders)
     end
     if s~=c and spare[s]>=math.min(need,short) and (pass==2 or Dark.isDarkNode(s)==darkBuyer) and routed(hubPlan,s,c,item) then
      local k=s..'>'..c
      if reach[k]==nil then reach[k]=reachable(s,c,clock) end
      if reach[k] then
       -- crossing between the white and dark networks costs like a long
       -- haul: each side buys from its own first and trades across only
       -- for what its own network can't spare
       local crossing=Dark.isDarkNode(s)~=Dark.isDarkNode(c) and T.darkCrossingAU or 0
       local score=(distance(s,c,clock)+crossing)*100-spare[s]
       local Chemicals=require('src.markets')
       if Chemicals.items[item] or Chemicals.floats(c,item) then
        local amount=math.min(math.max(1,math.floor(30/require('src.data').items[item].volume)),short,spare[s])
        score=Chemicals.price(u,s,item)+Transport.payment(Transport.quote({source=s,target=c,item=item,amount=amount},clock))/amount-spare[s]*1e-6
        if crossing>0 then score=score*(1+T.darkCrossingMarkup) end
       end
       if not bestScore or score<bestScore then best,bestScore=s,score end
      end
     end
    end
    if not best and pass==1 then break end
    if not best then
     -- only real scarcity counts: spare stock that just can't reach this
     -- buyer is a hauling problem, not a reason to make or dig more
     local anywhere=false
     for _,s in ipairs(participants) do if s~=c and spare[s]>=math.min(T.orderMinLoad,short) then anywhere=true;break end end
     -- counted against its target, not the reorder level
     if not anywhere then unmet[item]=(unmet[item] or 0)+math.max(0,need-(entry.short-short));entry.unmet=true end
     break
    end
    -- hub to hub is a trunk run: a bulk lot for a big freighter
    local trunk=hubPlan.kind[best]~=nil and hubPlan.kind[c]~=nil and root(L.byId[best].area)~=root(L.byId[c].area)
    local vol=require('src.data').items[item].volume
    local n=math.min(math.max(1,math.floor((trunk and T.trunkLot or T.orderMaxVolume)/vol)),short,spare[best])
    -- only a lot too big for an ordinary hold needs a bulk freighter: a
    -- short top-up between hubs is an ordinary order anyone can run
    if trunk and n*vol<=T.orderMaxVolume then trunk=false end
    -- a bare shelf before a low one
    local priority=Stock.count(u,c,item)==0 and 1 or 0
    local production=capacityUse(u,c,item)>0
    local urgency=(critical and 3 or production and 2 or 1)*math.max(0,1-entry.fill)
    Tasks.post(u,Transport.quote({kind='transport',source=best,target=c,item=item,amount=n,stocked=true,
     layoutScope=E.scope,order=true,priority=priority,urgency=urgency,cooldown=30,placed=clock,npcClaimAt=clock+T.freightListingSeconds,
     trunk=trunk or nil,requires=trunk and {capabilities={'cargo','bulk'}} or nil},clock,u))
    spare[best]=spare[best]-n;short=short-n
   end
   entry.left=short
  end
  end
  -- A buyer short for T.unmetShortageAge counts as unmet even with spare
  -- stock elsewhere: stock that isn't arriving is no use to it, so its
  -- makers aren't throttled to the floor while it starves.
  for _,entry in ipairs(buyers) do
   if not entry.unmet and E.shortageAge(u,entry.c,item,clock)>=T.unmetShortageAge then
    unmet[item]=(unmet[item] or 0)+math.max(0,entry.need)
   end
  end
  -- Fences: each buys the loot pirates sold at the dark stations (up to
  -- T.fenceStock m3 a good), from the one holding most. A dark station's
  -- own output stays home unless a white buyer is short (pass 2 above).
  -- A fence's stock over its own needs is spare like any white station's,
  -- so the passes above sell it on into the white network.
  for _,f in ipairs(fences) do if spare[f]~=nil then
   local vol=require('src.data').items[item].volume
   -- ordinary lots for any runner, not bulk trunk runs nobody took
   local lot=math.max(1,math.floor(T.orderMaxVolume/vol))
   local room=math.floor(T.fenceStock/vol)-Stock.count(u,f,item)-(inbound[f..'|'..item] or 0)
   while room>=math.min(T.orderMinLoad,lot) do
    local best,most
    for _,s in ipairs(participants) do if Dark.isDarkNode(s) then
     local kind=hubPlan.kind[s] and hubPlan.kind[s][item]
     local loot=(Stock.record(u,s).loot or {})[item] or 0
     local excess=math.min(loot,spare[s]-(kind and hubTarget(u,s,item,makes(s,item))*2 or 0))
     if excess>=math.min(T.orderMinLoad,lot) and (not most or excess>most) then
      local k=s..'>'..f
      if reach[k]==nil then reach[k]=reachable(s,f,clock) end
      if reach[k] then best,most=s,excess end
     end
    end end
    if not best then break end
    -- a full bulk load per run
    local n=math.min(lot,room,most)
    Tasks.post(u,Transport.quote({kind='transport',source=best,target=f,item=item,amount=n,stocked=true,
     layoutScope=E.scope,order=true,priority=0,urgency=1,cooldown=30,placed=clock,npcClaimAt=clock+T.freightListingSeconds},clock,u))
    spare[best]=spare[best]-n;room=room-n
    local loot=Stock.record(u,best).loot;loot[item]=loot[item]-n
    if loot[item]<=0 then loot[item]=nil end
   end
  end end
  pause()
 end
 u.economyUnmet=unmet
 adjust(u,unmet,all)
 hubPlan=nil
 -- the speculators read the prices this update settled (with a planning
 -- snapshot of their own: without one every target they ask for worked out
 -- its station's whole input plan again, dealer lot and all)
 planning={u=u,stations={}}
 require('src.merchants').update(u,clock,pause)
 planning=nil;memo=nil
end
-- All of it now (tests, forced catch-ups).
function E.update(u,clock)
 E.finish(u)
 if clock<(u.economyNext or 0) then return end
 u.economyNext=clock+E.tick
 run(u,clock)
 require('src.dark_runners').update(u,clock)
end
-- The same update a piece a step. All at once it was the longest step of
-- every minute by far (every good at every station): a hitch you could set
-- your watch by. E.spread starts it when it's due, E.pump runs the next
-- piece (Game:updateALife calls it every step), E.finish runs what's left
-- (before a save, or anything else that needs the books closed). Between
-- pieces the planning snapshots are put away, so everyone else reads live
-- numbers as usual. (Kept outside the universe table: a coroutine can't be
-- saved, and a universe that's dropped takes its half-done update with it.)
local spreading=setmetatable({},{__mode='k'})
local function resume(u,job)
 planning,hubPlan,memo=job.planning,job.hubPlan,job.memo
 local ok,err=coroutine.resume(job.co)
 job.planning,job.hubPlan,job.memo=planning,hubPlan,memo
 planning,hubPlan,memo=nil,nil,nil
 if not ok then spreading[u]=nil;error(debug.traceback(job.co,tostring(err)),0) end
 if coroutine.status(job.co)=='dead' then spreading[u]=nil end
end
function E.spread(u,clock)
 if spreading[u] then return E.pump(u) end
 if clock<(u.economyNext or 0) then return end
 u.economyNext=clock+E.tick
 require('src.dark_runners').update(u,clock)
 -- A piece ends at each station or good, and sooner (pause(true), asked
 -- inside the long loops) once it has done real work: planned a route or
 -- caught up a few stations' production. Counted, not timed, so the same
 -- game always splits the same way.
 local G=require('src.travelgraph')
 local plans,flows=G.planned,Stock.flowed
 local function pause(soft)
  if soft and G.planned==plans and Stock.flowed-flows<E.sliceFlows then return end
  coroutine.yield()
  plans,flows=G.planned,Stock.flowed
 end
 local job={co=coroutine.create(function() run(u,clock,pause) end)}
 spreading[u]=job
 resume(u,job)
end
function E.pump(u)
 local job=spreading[u]
 if job then resume(u,job) end
end
function E.finish(u)
 while spreading[u] do resume(u,spreading[u]) end
end
function E.spreading(u) return spreading[u]~=nil end

return E
