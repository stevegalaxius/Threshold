-- Transport tasks: carry a station's order (src/economy.lua) from the
-- station that has the goods to the one that wants them. The destination
-- commissions the shipment: it pays the courier, then buys the goods from
-- the source (src/accounts.lua).
local Tasks=require('src.tasks')
local Fields=require('src.fields')
local L=require('src.locations')
local G=require('src.travelgraph')
local Hold=require('src.inventory.hold')
local data=require('src.data')
local J=require('src.jobs')
local T=require('src.tuning')
local Personality=require('src.personality')
local Transport={}
local function hold(r)
 local h=r.ship.hold and Hold.deserialize(r.ship.hold,function(id)return data.items[id]~=nil end)
 if h then h.climateRules=true end   -- a ship's hold: delicate cargo only in climate grids
 return h
end
local function room(r,item,amount)
 local h=hold(r)
 if h then return Hold.room(h,item,amount) end
 if data.items[item].delicate then
  local space=require('src.ship').climateSpace(data.hulls[r.ship.hull],r.ship.loadout)
  return math.max(0,math.floor(space/data.items[item].volume))
 end
 local used=0
 for id,n in pairs(r.ship.cargo or {}) do used=used+data.items[id].volume*n end
 return math.max(0,math.floor(((data.hulls[r.ship.hull].hold or 0)-used)/data.items[item].volume))
end
local function cargo(r,item,amount)
 local h=hold(r)
 if h then
  local totals=Hold.totals(h);totals[item]=(totals[item] or 0)+amount
  Hold.sync(h,totals);r.ship.hold=Hold.serialize(h);r.ship.cargo=Hold.totals(h)
 else
  r.ship.cargo=r.ship.cargo or {}
  r.ship.cargo[item]=(r.ship.cargo[item] or 0)+amount
 end
end
-- Put amount of item into (or, negative, out of) an NPC record's hold.
Transport.carry=cargo
-- How many of item an NPC record's hold has room for (climate rules included).
Transport.room=room
function Transport.route(source,target,clock)
 local a,b=L.byId[source],L.byId[target]
 if not a or not b or source==target then return end
 return G.itinerary(source,target,clock)
end
-- Quote the delivery route, excluding empty travel to pickup and service detours.
-- Only mass-driver legs cover AU; local and moon-gate legs use the base rate.
-- AU is quoted to hundredths so the displayed distance explains the price.
function Transport.quote(t,clock,u)
 -- delicate cargo needs a climate-controlled hold
 if t.item and data.items[t.item] and data.items[t.item].delicate then t.requires={capabilities={'cargo','climate'}} end
 clock=t.placed or t.assigned or clock or 0
 if t.routeAU==nil then
  local route=Transport.route(t.source,t.target,clock) or {}
  local au=0
  for i=2,#route do
   local a,b=L.byId[route[i-1]],L.byId[route[i]]
   if a.kind=='driver' and b.kind=='driver' and a.area~=b.area then
    au=au+Fields.distance(a.area,b.area,clock)
   end
  end
  t.routeAU=math.floor(au*100+.5)/100
 end
 local Chemicals=require('src.markets')
 if u and t.item and (Chemicals.items[t.item] or Chemicals.floats(t.target,t.item) or Chemicals.floats(t.source,t.item)) then
  t.commodityBuyPrice=t.commodityBuyPrice or Chemicals.price(u,t.source,t.item)
  t.commoditySellPrice=t.commoditySellPrice or Chemicals.price(u,t.target,t.item)
 end
 -- Quotes are frozen once taken. A partial load keeps its original handling share.
 if t.creditsPerUnit==nil then
  local volume=t.item and data.items[t.item] and data.items[t.item].volume or 1
  local base=volume*(T.freightCreditsPerM3+t.routeAU*T.freightCreditsPerM3AU)
  -- valuable cargo pays more to carry (the courier carries the risk)
  local d=t.item and data.items[t.item]
  local worth=t.commodityBuyPrice or (d and d.price) or 0
  base=base+worth*T.freightValueShare
  t.premiumPerUnit=u and Transport.premium(u,t,base,clock) or 0
  t.creditsPerUnit=base+t.premiumPerUnit
  if t.handlingPerUnit==nil then
   t.handlingPerUnit=T.freightHandling/math.max(1,t.amount or 1)
   t.handlingLimit=T.freightHandling
  end
 end
 return t
end
-- Scarcity premium per unit: the destination shares part of the price gap
-- between source and target with whoever hauls it, more the longer its
-- shortage has gone unserved. Goods without a market price earn none.
function Transport.premium(u,t,base,clock)
 local buy,sell=t.commodityBuyPrice,t.commoditySellPrice
 if not (buy and sell) or sell<=buy then return 0 end
 local age=require('src.economy').shortageAge(u,t.target,t.item,clock or u.clock or 0)
 local urgency=math.min(T.freightUrgencyMax,1+age/(T.freightUrgencyHours*3600))
 return math.min((sell-buy)*T.freightGapShare*urgency,base*T.freightPremiumCap)
end
-- Keep quote previews, manifest settlement and history on the same invoice.
function Transport.invoice(t)
 Transport.quote(t)
 local manifest=t.manifest or {t};local budget=t.handlingLimit or 0
 for _,line in ipairs(manifest) do Transport.quote(line);budget=math.max(budget,line.handlingLimit or 0) end
 local bill={total=0,handling=0,volume=0,lines={}}
 for _,line in ipairs(manifest) do
  local handling=math.min(budget,line.amount*(line.handlingPerUnit or 0));budget=budget-handling
  local payment=math.floor(line.amount*line.creditsPerUnit+handling+1e-7)
  bill.lines[#bill.lines+1]={task=line,payment=payment,handling=handling}
  bill.total=bill.total+payment;bill.handling=bill.handling+handling
  bill.volume=bill.volume+line.amount*(data.items[line.item] and data.items[line.item].volume or 1)
 end
 return bill
end
function Transport.payment(t) return Transport.invoice(t).total end
-- What a station-to-station delivery's goods cost the buyer: the seller's
-- live price, plus T.hubMarkup when the seller is a logistics hub.
local function isHub(key) local p=L.byId[L.canonical(key)];return p and p.hub end
function Transport.goodsPrice(u,source,item)
 local unit=require('src.markets').price(u,source,item)
 if isHub(source) then unit=unit*(1+T.hubMarkup) end
 return unit
end
function Transport.settleGoods(u,line,buyer)
 local Accounts=require('src.accounts')
 local value=math.floor(Transport.goodsPrice(u,line.source,line.item)*line.amount+.5)
 local paid=Accounts.pay(u,buyer,value,'bought',line.item)
 Accounts.receive(u,line.source,paid,'sold',line.item)
 return paid
end
-- Upgrade unclaimed economy listings; accepted contracts retain their quote.
function Transport.refreshOffers(u,clock)
 for _,o in pairs(Tasks.state(u).offers) do
  if o.kind=='transport' and o.layoutScope=='economy' and o.state=='available' then
   local fresh=o.handlingPerUnit==nil
   -- an unclaimed listing follows today's prices, so its premium tracks
   -- the shortage; taking the job freezes the quote
   o.creditsPerUnit,o.commodityBuyPrice,o.commoditySellPrice=nil,nil,nil
   Transport.quote(o,clock,u)
   if fresh then o.npcClaimAt=math.max(o.npcClaimAt or 0,clock+T.freightListingSeconds) end
  end
 end
end
-- Reservations remain on the board until pickup; loaded cargo is no longer
-- counted at the source. No duplicate stock ledger needs save reconciliation.
-- What's promised out of a source walks the whole board, and a trader
-- weighing the board asks it for every offer on it: the board squared, in
-- one step. While a scan is open (Transport.beginScan .. endScan, around a
-- stretch that only reads the board), the orders are sorted by source and
-- good once and each question reads just its own few.
local scan
-- (true if this call opened it: only the one that opened it closes it. A
-- scan never outlives the instant it was opened in, and Tasks.post, the one
-- way an order joins the board, has it sorted again: Transport.rescan)
-- (still: the caller only reads, stock included, so counts can be kept too)
function Transport.beginScan(u,still)
 if scan and scan.u==u and scan.clock==u.clock then return false end
 scan={u=u,clock=u.clock,still=still};return true
end
function Transport.endScan() scan=nil end
function Transport.rescan() if scan then scan.groups=nil;scan.stock=nil;scan.loads=nil end end
-- The open freight at a pickup bound for one area, in cubic metres: what a
-- hauler could fill its bay with there (prepare's milk run).
function Transport.loadAt(u,source,area)
 local loads=scan and scan.u==u and scan.clock==u.clock and scan.loads
 if scan and scan.u==u and scan.clock==u.clock and not loads then
  loads={};scan.loads=loads
  for _,o in pairs(Tasks.state(u).offers) do
   if o.kind=='transport' and o.order and o.state=='available' and o.item and o.source and L.byId[o.target] then
    local k=o.source..'|'..L.byId[o.target].area
    loads[k]=(loads[k] or 0)+(o.amount or 0)*(data.items[o.item] and data.items[o.item].volume or 1)
   end
  end
 end
 if loads then return loads[source..'|'..area] or 0 end
 local v=0
 for _,o in pairs(Tasks.state(u).offers) do
  if o.kind=='transport' and o.order and o.state=='available' and o.item and o.source==source and L.byId[o.target] and L.byId[o.target].area==area then
   v=v+(o.amount or 0)*(data.items[o.item] and data.items[o.item].volume or 1)
  end
 end
 return v
end
local none={}
local function ordersFrom(u,source,item)
 if not scan or scan.u~=u or scan.clock~=u.clock or source==nil or item==nil then return nil end
 local groups=scan.groups
 if not groups then
  groups={};scan.groups=groups
  for _,o in pairs(Tasks.state(u).offers) do
   if o.order and not o.loaded and o.source~=nil and o.item~=nil then
    local byItem=groups[o.source];if not byItem then byItem={};groups[o.source]=byItem end
    local list=byItem[o.item];if not list then list={};byItem[o.item]=list end
    list[#list+1]=o
   end
  end
 end
 return groups[source] and groups[source][item] or none
end
function Transport.reserved(u,source,item,except,includeOpen)
 local n=0
 local group=ordersFrom(u,source,item)
 if group then
  local offers=Tasks.state(u).offers
  for _,o in ipairs(group) do
   -- (still on the board, still not loaded: either may have changed since the sort)
   if offers[o.id]==o and not o.loaded and (not except or o.id~=except and o.manifestRoot~=except) and (includeOpen or o.state~='available') then n=n+(o.amount or 0) end
  end
  return n
 end
 for _,o in pairs(Tasks.state(u).offers) do
  if o.order and o.source==source and o.item==item and not o.loaded and (not except or o.id~=except and o.manifestRoot~=except)
   and (includeOpen or o.state~='available') then n=n+(o.amount or 0) end
 end
 return n
end
function Transport.scanning(u) return scan~=nil and scan.u==u and scan.clock==u.clock end
function Transport.available(u,source,item,except)
 -- (a trader reading the board asks this once per offer, and most offers
 -- share a source and good: a scan opened as still moves no stock, so
 -- each pair is counted once)
 local have
 if scan and scan.still and scan.u==u and scan.clock==u.clock and source~=nil and item~=nil then
  local stock=scan.stock;if not stock then stock={};scan.stock=stock end
  local at=stock[source];if not at then at={};stock[source]=at end
  have=at[item]
  if not have then have=J.available(u,source,item);at[item]=have end
 else
  have=J.available(u,source,item)
 end
 return math.max(0,have-Transport.reserved(u,source,item,except))
end
-- A cheap estimate for comparison and fleet planning, in game seconds.
function Transport.duration(o,station,clock)
 local a,b=L.byId[o.source],L.byId[o.target]
 local localTime=a and b and a.area==b.area and 120 or 300
 return localTime+(o.routeAU or 0)*120+(station and station~=o.source and 180 or 0)
end
local function lines(t) return t.manifest or {t} end
-- Whether a route exists, remembered for a while: idle traders weigh every
-- job on the board, and planning each one in full was a lag spike.
local reach,reachAt={},nil
local function reachable(a,b,clock,sameArea)
 if not reachAt or clock<reachAt or clock-reachAt>600 then reach,reachAt={},clock end
 local key=a..'|'..b
 if reach[key]==nil then
  reach[key]=(sameArea and G.itinerary(a,b,clock) or Transport.route(a,b,clock))~=nil
 end
 return reach[key]
end
function Transport.usable(u,r,o,clock)
 if r.suspendedTask or r.service or r.worldRecovery or r.action or r.state=='stranded' then return 0 end
 if r.fuelStatus=='stranded' or r.fuelStatus=='empty' then return 0 end
 if require('src.reactor_fuel').remaining(r.ship)<=0 then return 0 end
 if (require('src.work_preferences').weight(r,'transport') or 0)<=0 then return 0 end
 local access=require('src.npc_access');local capabilities=access.capabilities(r)
 if not access.eligible(r,o,capabilities) or not access.eligible(r,Tasks.definitions.transport,capabilities) then return 0 end
 local station=r.node or r.station
 if not L.byId[station] then return 0 end
 local def=Tasks.definitions.transport
 if not def.eligible(u,r,o,station,clock) or not def.feasible(u,r,o,station,clock) then return 0 end
 return math.min(data.hulls[r.ship.hull].hold or 0,room(r,o.item,1000000)*data.items[o.item].volume)
end
function Transport.load(u,r,t)
 local saved=require('src.persistence').copy(r.ship);local totals={}
 for _,line in ipairs(lines(t)) do
  if room(r,line.item,line.amount)<line.amount
   or ((line.mine or line.stocked) and Transport.available(u,line.source,line.item,t.id)<line.amount+(totals[line.item] or 0)) then r.ship=saved;return false end
  cargo(r,line.item,line.amount);totals[line.item]=(totals[line.item] or 0)+line.amount
 end
 r.ship=saved
 for _,line in ipairs(lines(t)) do
  if line.mine or line.stocked then assert(require('src.stockpile').take(u,line.source,line.item,line.amount,nil,t.id)) end
  cargo(r,line.item,line.amount)
  local o=Tasks.state(u).offers[line.id];if o then o.loaded=true end
 end
 t.phase='delivery';return true
end
Tasks.register('transport',{
 requires={capabilities={'cargo'}},
 plan=function(t,station,clock)
  if t.phase=='pickup' then return G.itinerary(station,t.source,clock) end
  return Transport.route(station,t.target,clock)
 end,
 eligible=function(u,r,o,station,clock)
  -- Old reserved manifests may finish, but never issue new placeholder ore.
  if o.item=='martian_ore' then return false end
  -- Work elsewhere means flying there empty first (a pickup leg).
  if station~=o.source and (r.task or not L.byId[station]) then return false end
  local source,target=L.byId[o.source],L.byId[o.target]
  if not source or not target then return false end
  local from,to=source.area,target.area
  -- Retired return manifests can remain reserved in old saves until delivery.
  -- Once released, they must not let an empty strip mine generate more cargo.
  if J.isMine(from) and to==J.oreTo and (not (o.mine or o.order) or o.item~=J.item) then return false end
  if o.cap and J.available(u,o.target,o.item)>=o.cap then return false end
  -- a hauler waits for a load: an order is taken once the freight at its
  -- pickup for that area fills T.freightMinRun, it has waited
  -- T.freightMaxWait, or a shelf of food, water or fuel is nearly bare
  if o.order and not r.player and (o.urgency or 0)<2.5 and clock-(o.placed or clock)<T.freightMaxWait
   and Transport.loadAt(u,o.source,to)<T.freightMinRun then return false end
  -- an order takes whatever part of it this hold can carry
  local need=o.order and math.min(o.amount,T.orderMinLoad) or o.amount
  return room(r,o.item,need)>=need
   and (not (o.mine or o.stocked) or Transport.available(u,o.source,o.item,o.id)>=need)
 end,
 feasible=function(u,r,o,station,clock)
  return (station==o.source or reachable(station,o.source,clock,true)) and reachable(o.source,o.target,clock)
 end,
 score=function(u,r,o,station,clock)
  Transport.quote(o,clock,u)
  local amount=math.min(o.amount,room(r,o.item,o.amount))
  -- credits per second of the whole job, the empty run to the pickup included
  local pay
  if o.manifest or o.creditsPerUnit==nil then
   local quote=require('src.persistence').copy(o);quote.amount=amount
   pay=Transport.payment(quote)
  else
   -- (a plain quoted listing: the same sum Transport.invoice makes, without
   -- copying the offer to change its amount; this runs for every job read)
   pay=math.floor(amount*o.creditsPerUnit+math.min(o.handlingLimit or 0,amount*(o.handlingPerUnit or 0))+1e-7)
  end
  local reward=pay/Transport.duration(o,station,clock)
  local p=Personality.ensure(r)
  local ambition,aggression=p.ambition,p.aggression or .5
  local age=require('src.economy').shortageAge(u,o.target,o.item,clock)
  age=math.max(age,math.max(0,clock-(o.placed or o.readyAt or clock)))
  -- a timid trader shies from long interplanetary runs (open space, pirates)
  local risk=(o.routeAU or 0)*T.freightRiskPerAU*(1-aggression)
  -- each trader reads the board a little differently, so a fleet doesn't
  -- all chase the single best-paying job into one dock queue
  local h=0;local key=tostring(r.id)..tostring(o.id)
  for i=1,#key do h=(h*31+key:byte(i))%1000003 end
  local taste=1+T.freightScoreJitter*((h%1000)/500-1)
  return (o.order and 1000000 or 0)+(o.urgency or o.priority or 0)*10000
   +age*100+math.min(T.freightScoreCap,reward*100*taste*(1-math.min(.9,risk)))*(0.5+ambition)
   -(station~=o.source and 50*(1-ambition) or 0)
 end,
 prepare=function(u,r,t,station,clock)
  Transport.quote(t,clock,u)
  t.route=Transport.route(t.source,t.target,clock)
  if not t.route then return false end
  if t.order then
   local offers=Tasks.state(u).offers
   local candidates={t};local others={}
   -- A full bay: every open order at this pickup for the same drop-off, or
   -- for another station in the same area (a milk run: dropped off in
   -- turn, the first drop-off's orders first).
   local area=L.byId[t.target] and L.byId[t.target].area
   local capabilities=require('src.npc_access').capabilities(r)
   for _,o in pairs(offers) do
    -- (freight only: satellite jobs are board orders too, carrying no item)
    if o.id~=t.id and o.kind=='transport' and o.order and o.state=='available' and (o.readyAt or 0)<=clock and (r.player or Tasks.npcMayClaim(u,o,clock))
     and not r.player and o.source==t.source and o.item
     and (o.target==t.target or (not t.trunk and not o.trunk and L.byId[o.target] and L.byId[o.target].area==area and Transport.route(t.target,o.target,clock)~=nil))
     and require('src.npc_access').eligible(r,o,capabilities) then others[#others+1]=o end
   end
   table.sort(others,function(a,b)
    local sa,sb=a.target==t.target,b.target==t.target
    if sa~=sb then return sa end
    if a.target~=b.target then return a.target<b.target end
    return a.id<b.id end)
   for _,o in ipairs(others) do candidates[#candidates+1]=o end
   local saved=require('src.persistence').copy(r.ship)
   local manifest={};local planned={}
   for _,o in ipairs(candidates) do
    local n=math.min(o.amount,room(r,o.item,o.amount),Transport.available(u,o.source,o.item,o.id)-(planned[o.item] or 0))
    if n>0 then
     local line=require('src.persistence').copy(o);line.amount=n
     Transport.quote(line,clock,u);manifest[#manifest+1]=line;planned[o.item]=(planned[o.item] or 0)+n
     cargo(r,line.item,n) -- reserve grid space while fitting the other lines
    end
   end
   r.ship=saved
   if #manifest==0 or manifest[1].id~=t.id then return false end
   t.manifest=manifest;t.amount=manifest[1].amount
   for _,line in ipairs(manifest) do
    local o=offers[line.id];o.amount=line.amount;o.owner=r.id;o.state='reserved';o.manifestRoot=t.id
   end
  elseif room(r,t.item,t.amount)<t.amount then return false end
  t.phase='pickup'
  if station~=t.source then return true end
  if Transport.load(u,r,t) then return true end
  for _,line in ipairs(lines(t)) do
   local o=Tasks.state(u).offers[line.id];if o then o.owner=nil;o.state='available';o.manifestRoot=nil end
  end
  return false
 end,
 complete=function(u,r,t,station,clock)
  if t.settled then return true end
  Transport.quote(t,clock,u)
  if t.phase=='pickup' then
   if station~=t.source then return false end
   if not Transport.load(u,r,t) then Tasks.release(u,r,'nothing to pick up',clock) end
   return false
  end
  if station~=t.target then return false end
  local required={}
  for _,line in ipairs(lines(t)) do
   required[line.item]=(required[line.item] or 0)+line.amount
   local count=(r.ship.cargo or {})[line.item] or 0
   if count<required[line.item] then Tasks.release(u,r,'cargo lost',clock);return false end
  end
  -- (a milk run's invoice is made once, at the first drop-off, and each
  -- stop is paid its own lines)
  local invoice=t.invoice or Transport.invoice(t);t.invoice=invoice
  local paid,total=0,0
  local here,later={},{}
  for _,charge in ipairs(invoice.lines) do
   if charge.task.target==nil or charge.task.target==station then here[#here+1]=charge else later[#later+1]=charge end
  end
  for _,charge in ipairs(here) do
   local line=charge.task;paid=paid+charge.payment
   cargo(r,line.item,-line.amount)
   -- (a player's buy order goes to their storage or stall: src/buy_orders.lua)
   if line.playerOrder then require('src.buy_orders').delivered(u,line.playerOrder,station,line.item,line.amount,clock)
   elseif line.mine or line.stocked then J.deliver(u,station,line.item,line.amount) end
   if line.intake then require('src.merchants').received(u,line.intake,station,line.item,line.amount) end
   require('src.economy').stat(u,'hauled',line.item,line.amount)
   local payment=require('src.accounts').pay(u,station,charge.payment,'freight',line.item);total=total+line.amount
   paid=paid-(charge.payment-payment)
   -- an economy order is a sale: the buyer pays the seller for the goods
   -- (after the courier), and a hub sells on at a markup
   if line.layoutScope=='economy' and not line.playerOrder and not line.intake then
    local goods=Transport.settleGoods(u,line,station)
    require('src.markets').landed(u,station,line.item,line.amount,goods+payment)
   end
   if (line.premiumPerUnit or 0)>0 then require('src.economy').ledger(u,station,'premium',math.floor(line.amount*line.premiumPerUnit),line.item) end
   require('src.simulation_history').note(u,'freight_delivered',clock,L.byId[station].area,{r.id},
    {taskId=line.id,source=line.source,target=line.target,item=line.item,amount=line.amount,routeAU=line.routeAU,creditsPerUnit=line.creditsPerUnit,premiumPerUnit=line.premiumPerUnit,handling=charge.handling,payment=payment,commodityBuyPrice=line.commodityBuyPrice,commoditySellPrice=line.commoditySellPrice},station)
   if line.id~=t.id then Tasks.state(u).offers[line.id]=nil end
  end
  local state=Tasks.state(u);state.delivered=state.delivered or {};state.delivered[station]=(state.delivered[station] or 0)+total
  r.credits=(r.credits or 0)+paid
  r.freightEarnings=(r.freightEarnings or 0)+paid
  if #later>0 then
   -- on to the next drop-off with what's left aboard
   local manifest,lines_={},{}
   for _,charge in ipairs(later) do manifest[#manifest+1]=charge.task;lines_[#lines_+1]=charge end
   invoice.lines=lines_;t.manifest=manifest;t.target=manifest[1].target;t.route=nil
   return false
  end
  r.lastDestination=station;r.lastOrigin=t.source
  t.settled=true

  return true
 end
})
function Transport.seed(u)
 local state=Tasks.state(u)
 state.transportSeeded=true
 Transport.refreshOffers(u,u.clock)
 for _,o in pairs(state.offers) do if o.kind=='transport' then Transport.quote(o,u.clock) end end
 for _,r in pairs(u.npcs or {}) do
  local t=r.task or r.suspendedTask
  if t and t.kind=='transport' then Transport.quote(t,u.clock) end
 end
 -- Nothing is authored any more: every haul is a station's order
 -- (src/economy.lua). Syncing an empty list clears the old cargo and
 -- freight runs from saves, leaving reserved trips to finish.
 local specs={}
 Tasks.sync(u,'transport',specs,function(o)return o.kind=='transport' end)
end
return Transport
