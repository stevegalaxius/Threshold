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
local E={scaleMin=.25,scaleMax=4,scaleStep=.05,tick=60,lot=120,hours=2,halfLife=4*3600,expire=1200,reserveHours=1,scope='economy'}
-- Every trade station keeps at least this much of these on hand.
E.floor={deuterium_canister=40}

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
local function adjust(u,unmet)
 u.industry=u.industry or {}
 for _,c in ipairs(C.list) do
  if c.adaptive then
  for key in pairs(c.make) do
   local t=u.industry[key] or {};u.industry[key]=t
   local v=t[c.id] or 1
   local have=Stock.count(u,key,c.item)
   -- stock piling up here always slows it, whatever anyone else is short of
   if have>=E.lot*2 then v=v*(1-E.scaleStep)
   -- Unsupplied demand must propagate upstream even while inputs are scarce.
   elseif (unmet[c.item] or 0)>0 and have<E.lot then v=v*(1+E.scaleStep) end
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
local function inputPlan(u,key)
 if not planning or planning.u~=u then return require('src.industry').inputPlan(u,key) end
 local plan=planning.stations[key]
 if not plan then plan=require('src.industry').inputPlan(u,key);planning.stations[key]=plan end
 return plan
end
local function capacityUse(u,key,item)
 local n=item==Food.item and Food.rates(key) or 0
 for _,c in ipairs(C.list) do if c.item==item then n=n+(c.use[key] or 0) end end
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
local function makes(key,item)
 local place=L.byId[key];if not place then return false end
 if item==Food.item then local _,make=Food.rates(key);return make>0 end
 for _,c in ipairs(C.list) do for _,output in ipairs(C.outputs(c)) do if output.item==item and (c.make[key] or 0)>0 then return true end end end
 return false
end
function E.target(u,key,item,supplier)
 local use=serviceUse(u,key,item)
 if item==Food.item then use=math.max(use,Food.rates(key)) end
 for _,c in ipairs(C.list) do if c.item==item then use=math.max(use,c.use[key] or 0) end end
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
 local set,list={},{}
 local function add(item) if item and not set[item] then set[item]=true;list[#list+1]=item end end
 for _,c in ipairs(C.list) do for _,output in ipairs(C.outputs(c)) do add(output.item) end;for _,input in ipairs(C.inputs(c)) do add(input.item) end end
 for _,item in pairs(require('src.ore').items) do add(item) end
 add(require('src.reactor_fuel').item())
 add(Food.item)
 table.sort(list)
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
local function hubWants(u,all)
 local plan={hubs={},want={},kind={},made={},u=u}
 for _,s in ipairs(all) do
  local p=L.byId[s]
  if p.hub then local r=root(p.area);if not plan.hubs[r] or s<plan.hubs[r] then plan.hubs[r]=s end end
 end
 if not next(plan.hubs) then return plan end
 for _,s in ipairs(all) do
  local r=root(L.byId[s].area);plan.made[r]=plan.made[r] or {}
  for _,item in ipairs(goods()) do if makes(s,item) then plan.made[r][item]=true end end
 end
 for _,h in pairs(plan.hubs) do plan.want[h],plan.kind[h]={},{} end
 for _,item in ipairs(goods()) do
  local imported,total={},0
  for r,h in pairs(plan.hubs) do if not (plan.made[r] or {})[item] then
   local n=0
   for _,s in ipairs(all) do
    if s~=h and root(L.byId[s].area)==r then n=n+E.target(u,s,item,false) end
   end
   imported[r]=n;total=total+n
  end end
  for r,h in pairs(plan.hubs) do
   if imported[r] then plan.want[h][item],plan.kind[h][item]=imported[r],'import'
   else plan.want[h][item],plan.kind[h][item]=total,'export' end
  end
 end
 return plan
end
E.hubWants=hubWants
-- The hub that serves a station's planet system, if it has one.
function E.hubFor(id)
 local p=L.byId[id];if not p then return end
 local r,best=root(p.area)
 for _,place in pairs(L.byId) do
  if place.kind=='station' and place.hub and root(place.area)==r and (not best or place.id<best) then best=place.id end
 end
 return best
end
-- Whether s may sell item to c under hub routing.
local function routed(plan,s,c,item)
 local rs,rc=root(L.byId[s].area),root(L.byId[c].area)
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

function E.update(u,clock)
 if clock<(u.economyNext or 0) then return end
 u.economyNext=clock+E.tick
 local state=Tasks.state(u)
 Transport.refreshOffers(u,clock)
 -- count what's ordered or on the way; an order nobody has taken in
 -- E.expire seconds is withdrawn, to be placed again from wherever the
 -- stock is now
 local inbound,committed={},{}
 for id,o in pairs(state.offers) do
  if o.layoutScope==E.scope then
   if o.state=='available' and clock-(o.placed or clock)>E.expire then state.offers[id]=nil
   else
    local k=o.target..'|'..o.item;inbound[k]=(inbound[k] or 0)+o.amount
    if o.state~='available' then committed[k]=(committed[k] or 0)+o.amount end
   end
  end
 end
 local reach={}
 local all=stations()
 local inhabited=stations(true)
 require('src.industry').update(u,clock,inhabited)
 planning={u=u,stations={}}
 require('src.markets').update(u,clock,all,committed)
 planning.stations={}
 hubPlan=hubWants(u,all)
 -- Output bins may have filled since these orders were posted. Keep
 -- committed cargo, but release unclaimed excess rather than tying up sources.
 local remaining,availableOrders={},{}
 for id,o in pairs(state.offers) do if o.layoutScope==E.scope and o.state=='available' then availableOrders[#availableOrders+1]={id=id,o=o} end end
 table.sort(availableOrders,function(a,b)return tostring(a.id)<tostring(b.id) end)
 for _,entry in ipairs(availableOrders) do
  local o=entry.o;local k=o.target..'|'..o.item
  if remaining[k]==nil then
   local producer=makes(o.target,o.item);local want=hubTarget(u,o.target,o.item,producer)
   remaining[k]=math.max(0,want*(producer and 1 or 2)-Stock.count(u,o.target,o.item)-(committed[k] or 0))
  end
  local amount=math.min(o.amount,remaining[k])
  if amount<=0 then state.offers[entry.id]=nil else o.amount=amount;remaining[k]=remaining[k]-amount end
 end
 inbound={}
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
  for _,s in ipairs(participants) do
   local have=math.max(0,Stock.count(u,s,item)-Transport.reserved(u,s,item,nil,true))
   local producer=makes(s,item)
   local want=hubTarget(u,s,item,producer)
   E.shortage(u,s,item,Stock.count(u,s,item),want,clock)
   local level=producer and want or want*2
   -- a hub's stock is all for passing on: imports to its own system,
   -- exports to other hubs (routed decides which way)
   spare[s]=have-((hubPlan.kind[s] and hubPlan.kind[s][item]) and 0 or level)
   local coming=have+(inbound[s..'|'..item] or 0)
   if want>0 and coming<want then buyers[#buyers+1]={c=s,short=level-coming,need=want-coming,fill=coming/want} end
  end
  -- neediest first: the emptiest shelf against its target gets first call
  table.sort(buyers,function(a,b) return a.fill<b.fill or a.fill==b.fill and a.c<b.c end)
  for _,entry in ipairs(buyers) do
   local c,short=entry.c,entry.short;local need=entry.need
   while short>0 do
    local best,bestScore
    for _,s in ipairs(participants) do
     if s~=c and spare[s]>=math.min(T.orderMinLoad,short) and routed(hubPlan,s,c,item) then
      local k=s..'>'..c
      if reach[k]==nil then reach[k]=reachable(s,c,clock) end
      if reach[k] then
       local score=distance(s,c,clock)*100-spare[s]
       local Chemicals=require('src.markets')
       if Chemicals.items[item] then
        local amount=math.min(math.max(1,math.floor(30/require('src.data').items[item].volume)),short,spare[s])
        score=Chemicals.price(u,s,item)+Transport.payment(Transport.quote({source=s,target=c,item=item,amount=amount},clock))/amount-spare[s]*1e-6
       end
       if not bestScore or score<bestScore then best,bestScore=s,score end
      end
     end
    end
    if not best then
     -- only real scarcity counts: spare stock that just can't reach this
     -- buyer is a hauling problem, not a reason to make or dig more
     local anywhere=false
     for _,s in ipairs(participants) do if s~=c and spare[s]>=math.min(T.orderMinLoad,short) then anywhere=true;break end end
     -- counted against its target, not the reorder level
     if not anywhere then unmet[item]=(unmet[item] or 0)+math.max(0,need-(entry.short-short)) end
     break
    end
    -- hub to hub is a trunk run: a bulk lot for a big freighter
    local trunk=hubPlan.kind[best]~=nil and hubPlan.kind[c]~=nil and root(L.byId[best].area)~=root(L.byId[c].area)
    local n=math.min(math.max(1,math.floor((trunk and T.trunkLot or 30)/require('src.data').items[item].volume)),short,spare[best])
    -- a bare shelf before a low one
    local priority=Stock.count(u,c,item)==0 and 1 or 0
    local critical=item==Food.item or item=='water' or item==require('src.reactor_fuel').item()
    local production=capacityUse(u,c,item)>0
    local urgency=(critical and 3 or production and 2 or 1)*math.max(0,1-entry.fill)
    Tasks.post(u,Transport.quote({kind='transport',source=best,target=c,item=item,amount=n,stocked=true,
     layoutScope=E.scope,order=true,priority=priority,urgency=urgency,cooldown=30,placed=clock,npcClaimAt=clock+T.freightListingSeconds,
     trunk=trunk or nil,requires=trunk and {capabilities={'cargo','bulk'}} or nil},clock,u))
    spare[best]=spare[best]-n;short=short-n
   end
  end
 end
 u.economyUnmet=unmet
 adjust(u,unmet)
 planning=nil;hubPlan=nil
end

return E
