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
local scan
local function hold(r)
 local h=r.ship.hold and Hold.deserialize(r.ship.hold,function(id)return data.items[id]~=nil end)
 if h then h.climateRules=true end   -- a ship's hold: delicate cargo only in climate grids
 return h
end
local function measureRoom(r,item,amount,h)
 h=h or hold(r)
 if h then return Hold.room(h,item,amount) end
 if data.items[item].delicate then
  local space=require('src.ship').climateSpace(data.hulls[r.ship.hull],r.ship.loadout)
  return math.max(0,math.floor(space/data.items[item].volume))
 end
 local used=0
 for id,n in pairs(r.ship.cargo or {}) do used=used+data.items[id].volume*n end
 return math.max(0,math.floor(((data.hulls[r.ship.hull].hold or 0)-used)/data.items[item].volume))
end
-- Eligibility and scoring repeatedly ask about the same cargo on an
-- unchanged ship. Keep exact room results for this read-only board scan.
local function room(r,item,amount)
 if not scan or not scan.still or not amount then return measureRoom(r,item,amount) end
 local rooms=scan.rooms
 if not rooms or rooms.actor~=r then rooms={actor=r};scan.rooms=rooms end
 local byAmount=rooms[item]
 if not byAmount then byAmount={};rooms[item]=byAmount end
 local available=byAmount[amount]
 if available==nil then
  -- (the hold is unpacked once per ship per board scan, not per offer)
  if rooms.hold==nil then rooms.hold=r.ship.hold and hold(r) or false end
  available=measureRoom(r,item,amount,rooms.hold or nil)
  byAmount[amount]=available
 end
 return available
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
-- Trial packing for a manifest: one hold unpacked once and filled in
-- place, never written back to the ship. (Fitting each line by copying the
-- whole ship and re-serialising its hold made garbage enough to stall a
-- frame for a docked hauler choosing freight.)
local function fitter(r)
 local h=hold(r);local extra={}
 local f={}
 function f.room(item,amount)
  if h then return Hold.room(h,item,amount) end
  if data.items[item].delicate then
   local space=require('src.ship').climateSpace(data.hulls[r.ship.hull],r.ship.loadout)
   return math.max(0,math.floor(space/data.items[item].volume))
  end
  local used=0
  for id,n in pairs(r.ship.cargo or {}) do used=used+data.items[id].volume*n end
  for id,n in pairs(extra) do used=used+data.items[id].volume*n end
  return math.max(0,math.floor(((data.hulls[r.ship.hull].hold or 0)-used)/data.items[item].volume))
 end
 function f.add(item,n)
  if h then local totals=Hold.totals(h);totals[item]=(totals[item] or 0)+n;Hold.sync(h,totals)
  else extra[item]=(extra[item] or 0)+n end
 end
 return f
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
-- Courier standing: a courier who loses cargo it doesn't own answers for
-- it with its standing at the buyer's faction, in proportion to the share
-- of the load lost (a whole load lost or the ship destroyed: all of it).
-- The player's is their faction standing (src/reputation.lua); an NPC
-- keeps its own, r.courierRep[faction]. Standing gates how much cargo
-- value a courier is trusted with (Transport.trustedValue).
local function buyerFaction(key) return key and require('src.reputation').ofNode(L.canonical(key)) end
function Transport.courierStanding(u,r,key)
 local f=buyerFaction(key);if not f then return 0 end
 if r.player then return require('src.reputation').standing(u,f) end
 return (r.courierRep or {})[f] or 0
end
-- share: 1 for a clean delivery, -x for a share x of the load lost
function Transport.answer(u,r,key,share)
 local f=buyerFaction(key);if not f or share==0 then return end
 local by=share>0 and T.courierRepGain*share or T.courierRepLoss*share
 if r.player then require('src.reputation').addStanding(u,f,by);return end
 r.courierRep=r.courierRep or {}
 r.courierRep[f]=math.max(-100,math.min(100,(r.courierRep[f] or 0)+by))
end
function Transport.trustedValue(u,r,key)
 local rep=Transport.courierStanding(u,r,key)
 if rep<=T.courierBanRep then return 0 end
 return T.courierTrustValue*2^(rep/T.courierTrustDoubling)
end
-- how many units of an order a courier is trusted to carry (math.huge for
-- a trade run, which the trader owns)
function Transport.trustedUnits(u,r,o)
 if o.trade or not o.item then return math.huge end
 local price=Transport.goodsPrice(u,o.source,o.item)
 if price<=0 then return math.huge end
 return math.floor(Transport.trustedValue(u,r,o.target)/price)
end
-- Trade runs: an NPC trader buys a price-driven good at the source and
-- sells it at the destination, keeping the spread and carrying the risk
-- (lost cargo is its own loss). No courier fee; the player can't take one
-- (src/player_contracts.lua), but couriers still carry every other order.
function Transport.tradeCost(u,line)
 return math.floor(Transport.goodsPrice(u,line.source,line.item)*line.amount+.5)
end
function Transport.tradeValue(u,line,station)
 local buyer=station or line.target
 local price=require('src.markets').price(u,buyer,line.item)
 if line.shortageBid then
  return math.min(math.floor(line.shortageBid*line.amount+.5),math.floor(require('src.accounts').spendable(u,buyer)))
 end
 return math.floor(price*line.amount+.5)
end
function Transport.settleGoods(u,line,buyer)
 local Accounts=require('src.accounts')
 local seller=line.originalSource or line.source
 local value=math.floor(Transport.goodsPrice(u,seller,line.item)*line.amount+.5)
 local paid=Accounts.pay(u,buyer,value,'bought',line.item)
 Accounts.receive(u,seller,paid,'sold',line.item)
 return paid
end
local function courierCost(u,o)
 return math.floor(Transport.goodsPrice(u,o.source,o.item)*o.amount+.5)+Transport.payment(o)
end
function Transport.refreshOffers(u,clock)
 local Accounts=require('src.accounts')
 local Economy=require('src.economy')
 local incoming,budget,candidates={},{},{}
 for _,o in pairs(Tasks.state(u).offers) do
  if o.layoutScope=='economy' then
   if o.state=='available' then candidates[#candidates+1]=o
   else
    local key=o.target..'|'..o.item
    incoming[key]=(incoming[key] or 0)+o.amount
   end
  end
 end
 table.sort(candidates,function(a,b)
  local x,y=a.placed or 0,b.placed or 0
  return x<y or x==y and a.id<b.id
 end)
 for _,o in ipairs(candidates) do
  local trader=o.trade or o.tradeOptional
  local wasOptional=o.tradeOptional
  local fresh=o.handlingPerUnit==nil
  o.creditsPerUnit,o.commodityBuyPrice,o.commoditySellPrice=nil,nil,nil
  Transport.quote(o,clock,u)
  if trader then
   o.trade,o.tradeOptional=true,nil
   local account=Accounts.of(o.target)
   if budget[account]==nil then budget[account]=Accounts.spendable(u,o.target) end
   local key=o.target..'|'..o.item
   if clock-(o.placed or clock)>=T.tradeCourierAfter
    and J.available(u,o.target,o.item)+(incoming[key] or 0)<Economy.target(u,o.target,o.item) then
    o.creditsPerUnit=data.items[o.item].volume*(T.freightCreditsPerM3+o.routeAU*T.freightCreditsPerM3AU)
    o.premiumPerUnit=0
    local cost=courierCost(u,o)
    if budget[account]>=cost then
     budget[account]=budget[account]-cost
     incoming[key]=(incoming[key] or 0)+o.amount
     o.trade,o.tradeOptional=nil,true
     fresh=not wasOptional
    end
   end
  end
  if fresh then o.npcClaimAt=math.max(o.npcClaimAt or 0,clock+T.freightListingSeconds) end
 end
end
-- Reservations remain on the board until pickup; loaded cargo is no longer
-- counted at the source. No duplicate stock ledger needs save reconciliation.
-- What's promised out of a source walks the whole board, and a trader
-- weighing the board asks it for every offer on it: the board squared, in
-- one step. While a scan is open (Transport.beginScan .. endScan, around a
-- stretch that only reads the board), the orders are sorted by source and
-- good once and each question reads just its own few.
-- (true if this call opened it: only the one that opened it closes it. A
-- scan never outlives the instant it was opened in, and Tasks.post, the one
-- way an order joins the board, has it sorted again: Transport.rescan)
-- (still: the caller only reads, stock included, so counts can be kept too)
function Transport.beginScan(u,still)
 if scan and scan.u==u and scan.clock==u.clock then return false end
 scan={u=u,clock=u.clock,still=still};return true
end
function Transport.endScan() scan=nil end
function Transport.rescan() if scan then scan.groups=nil;scan.stock=nil;scan.loads=nil;scan.rooms=nil end end
local function releaseFunds(u,line)
 local amount=(line.reservedPurchase or 0)+(line.reservedFee or 0)+(line.prepaidFee or 0)
 if amount>0 then require('src.accounts').refund(u,line.target,amount) end
 line.reservedPurchase,line.reservedFee,line.prepaidFee=nil,nil,nil
end
local function reserveFunds(u,t,line)
 local purchase,fee
 if t.buyerFunded then
  purchase=Transport.tradeCost(u,line)
  fee=Transport.payment(line)
 elseif line.trade and line.shortageBid then
  purchase=math.floor(line.shortageBid*line.amount+.5)
  if purchase<=Transport.tradeCost(u,line) then return false end
 else return true end
 if not require('src.accounts').reserve(u,line.target,purchase+(fee or 0)) then return false end
 line.reservedPurchase,line.reservedFee=purchase,fee
 return true
end
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
   if offers[o.id]==o and not o.relay and not o.loaded and (not except or o.id~=except and o.manifestRoot~=except) and (includeOpen or o.state~='available') then n=n+(o.amount or 0) end
  end
  return n
 end
 for _,o in pairs(Tasks.state(u).offers) do
  if o.order and o.source==source and o.item==item and not o.relay and not o.loaded and (not except or o.id~=except and o.manifestRoot~=except)
   and (includeOpen or o.state~='available') then n=n+(o.amount or 0) end
 end
 return n
end
function Transport.scanning(u) return scan~=nil and scan.u==u and scan.clock==u.clock end
function Transport.available(u,source,item,except)
 local offer=except and Tasks.state(u).offers[except]
 if offer and offer.relay and offer.source==source and offer.item==item then
  return offer.loaded and 0 or offer.amount
 end
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
-- A relay changes custody. The original trade and the station handling
-- the cargo must both be allowed under the same rules as economy dispatch.
function Transport.embargoed(t,via)
 local Rep=require('src.reputation')
 for _,line in ipairs(lines(t)) do
  if line.layoutScope=='economy' or line.relay or via then
   if Rep.embargoed(line.source,line.target,line.item)
    or line.originalSource and Rep.embargoed(line.originalSource,line.target,line.item)
    or via and (Rep.embargoed(line.source,via,line.item) or Rep.embargoed(via,line.target,line.item)) then
    return true
   end
  end
 end
 return false
end

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
 if not access.eligible(r,o,capabilities,u) or not access.eligible(r,Tasks.definitions.transport,capabilities) then return 0 end
 local station=r.node or r.station
 if not L.byId[station] then return 0 end
 local def=Tasks.definitions.transport
 if not def.eligible(u,r,o,station,clock) or not def.feasible(u,r,o,station,clock) then return 0 end
 return math.min(data.hulls[r.ship.hull].hold or 0,room(r,o.item,1000000)*data.items[o.item].volume)
end
function Transport.load(u,r,t)
 local fit=fitter(r);local totals={}
 for _,line in ipairs(lines(t)) do
  if fit.room(line.item,line.amount)<line.amount
   or ((line.mine or line.stocked) and Transport.available(u,line.source,line.item,t.id)<line.amount+(totals[line.item] or 0)) then return false end
  fit.add(line.item,line.amount);totals[line.item]=(totals[line.item] or 0)+line.amount
 end
 local cost=0
 for _,line in ipairs(lines(t)) do if line.trade then cost=cost+Transport.tradeCost(u,line) end end
 -- A reservation keeps its financing terms. Release before taking any stock
 -- if the pilot can no longer fund the purchase at pickup.
 if cost>0 and (r.player or (r.credits or 0)-cost<T.tradeReserve) then return false end
 if t.buyerFunded then
  local line=lines(t)[1]
  local Accounts=require('src.accounts')
  if not line.reservedPurchase and not reserveFunds(u,t,line) then return false end
  line.prepaidGoods,line.prepaidFee=line.reservedPurchase,line.reservedFee
  line.reservedPurchase,line.reservedFee=nil,nil
  Accounts.receive(u,line.source,line.prepaidGoods,'sold',line.item)
  require('src.economy').ledger(u,line.target,'bought',line.prepaidGoods,line.item)

 end
 for _,line in ipairs(lines(t)) do
  if not line.relay and (line.mine or line.stocked) then assert(require('src.stockpile').take(u,line.source,line.item,line.amount,nil,t.id)) end
  if line.trade then
   local cost=Transport.tradeCost(u,line)
   require('src.accounts').receive(u,line.source,cost,'sold',line.item)
   r.credits=(r.credits or 0)-cost;r.tradeSpent=(r.tradeSpent or 0)+cost;line.tradeCost=cost
  end
  cargo(r,line.item,line.amount)
  local o=Tasks.state(u).offers[line.id];if o then o.loaded=true;o.loadedAt=u.clock end
 end
 t.phase='delivery';return true
end
-- Both terms have the same route. Compare the earnings on the quantity
-- this pilot can finance or is trusted to deliver.
local function freightTerms(u,r,o,capacity)
 local price=Transport.goodsPrice(u,o.source,o.item)
 local spendable=math.max(0,(r.credits or 0)-T.tradeReserve)
 local units=price>0 and math.min(capacity,math.floor(spendable/price)) or capacity
 local value
 if o.shortageBid then
  value=Transport.tradeValue(u,{target=o.target,item=o.item,amount=units,shortageBid=o.shortageBid})
 else
  local priceAtDelivery=require('src.markets').expectedTradePrice(u,o.target,o.item,units)
  value=math.floor(priceAtDelivery*units+.5)
 end
 local profit=value-math.floor(price*units+.5)
 local courierUnits,fee=0,0
 if o.tradeOptional then
  courierUnits=math.min(capacity,Transport.trustedUnits(u,r,o))
  fee=math.floor(courierUnits*(o.creditsPerUnit or 0)+math.min(o.handlingLimit or 0,courierUnits*(o.handlingPerUnit or 0))+1e-7)
 end
 if not r.player and profit>0 and profit>=fee then return units,profit,true end
 return courierUnits,fee,false
end
-- A relay offer is also the station's sealed freight record until pickup.
-- Its volume counts against the receiving station's bonded storage.
local function availableRelayVolume(u,station)
 local room=T.freightRelayVolume
 for _,o in pairs(Tasks.state(u).offers) do
  if o.relay and o.source==station and not o.loaded and data.items[o.item] then
   room=room-o.amount*data.items[o.item].volume
  end
 end
 return room
end

function Transport.returnStation(t)
 return t and (t.originalSource or t.source)
end

function Transport.recoveryMode(u,t,station,clock)
 local place=L.byId[station]
 if not t or t.kind~='transport' or t.phase~='delivery' or not place or place.kind~='station' then return end
 local returning=true
 local volume=0
 local Stock=require('src.stockpile')
 for _,line in ipairs(lines(t)) do
  -- Prepaid contracts have a separate escrow and settlement.
  if line.target==station or line.playerOrder or line.intake or line.house or not (line.stocked or line.mine) then return end
  if (line.originalSource or line.source)~=station then returning=false end
  -- Prepaid contracts have a separate escrow: they may only be unwound at
  -- the seller (Transport.unwindPrepaid), never relayed through a third station.
  if (line.buyerFunded or t.buyerFunded or line.prepaidGoods or line.prepaidFee) and not returning then return end
  volume=volume+line.amount*data.items[line.item].volume
 end
 if returning then
  for _,line in ipairs(lines(t)) do
   if not Stock.stock(u,station,Stock.shopFor(station,line.item)) then return end
  end
  return 'return'
 end
 if Transport.embargoed(t,station) or volume>availableRelayVolume(u,station) then return end
 for _,line in ipairs(lines(t)) do
  if line.trade or line.relay and line.source~=station or not Transport.route(station,line.target,clock) then return end
 end
 return 'transfer'
end

function Transport.recoveryStops(u,r,t,area,x,y,clock)
 local options={}
 for _,station in ipairs(L.stations(area)) do
  if not (t.recoveryTried and t.recoveryTried[station])
   and require('src.npc_access').canDock(r,station,u)
   and require('src.dock_room').capacity(station,r.ship.hull)>0 then
   local mode=Transport.recoveryMode(u,t,station,clock)
   if mode then
    local px,py=L.position(station,clock)
    options[#options+1]={station=station,mode=mode,distance=(px-x)^2+(py-y)^2}
   end
  end
 end
 table.sort(options,function(a,b)
  return a.distance<b.distance or a.distance==b.distance and a.station<b.station
 end)
 return options
end

-- Undo a prepaid sale: the seller hands back what the buyer paid for the
-- goods and the unused fee escrow goes back to the buyer. The buyer is made
-- whole even when part of the load was lost on the way.
function Transport.unwindPrepaid(u,line)
 local goods=line.prepaidGoods or 0
 if goods>0 then
  local Accounts=require('src.accounts')
  Accounts.pay(u,line.source,goods)
  Accounts.refund(u,line.target,goods)
 end
 line.prepaidGoods=nil
 releaseFunds(u,line)
end
local function prepaid(t,line) return t.buyerFunded or line.buyerFunded or line.prepaidGoods or line.prepaidFee end
function Transport.hasPrepaid(t)
 for _,line in ipairs(lines(t)) do if prepaid(t,line) then return true end end
 return false
end
-- Cargo the hauler itself owns: bought trade goods, or a stranded load it
-- had to pay the seller for. Sold at the next station that lists the item
-- (Transport.sellOwned, on every dock).
local function own(r,item,n)
 if n<=0 then return end
 r.ownedCargo=r.ownedCargo or {}
 r.ownedCargo[item]=(r.ownedCargo[item] or 0)+n
end
-- A loaded job that ends without delivery or return. Seller-owned goods
-- (stocked or mined, not prepaid) are bought from the seller at its price,
-- as far as the hauler's credits go; the rest is written off and taken off
-- the ship. Bought trade goods were the hauler's already.
function Transport.strand(u,r,t,clock)
 if r.player or r.state=='dead' or r.state=='escaped' then return end
 local aboard={}
 for _,line in ipairs(lines(t)) do
  local have=aboard[line.item] or math.max(0,((r.ship.cargo or {})[line.item] or 0)-((r.ownedCargo or {})[line.item] or 0))
  local n=math.min(have,line.amount or 0)
  aboard[line.item]=have-n
  if n>0 then
   if line.trade then own(r,line.item,n)
   elseif not prepaid(t,line) then
    local seller=line.originalSource or line.source
    local unit=Transport.goodsPrice(u,seller,line.item)
    local afford=unit>0 and math.min(n,math.floor(math.max(0,r.credits or 0)/unit)) or n
    local cost=math.floor(unit*afford+.5)
    if cost>0 then
     r.credits=(r.credits or 0)-cost
     require('src.accounts').receive(u,seller,cost,'sold',line.item)
    end
    own(r,line.item,afford)
    if n>afford then cargo(r,line.item,-(n-afford)) end
   end
  end
 end
end
local function buys(station,item)
 for _,shop in ipairs(require('src.stockpile').shops(station)) do
  if require('src.stockpile').lists(shop,item) then return true end
 end
end
function Transport.sellOwned(u,r,station)
 if not r.ownedCargo or r.player then return end
 local place=L.byId[station]
 if not place or place.kind~='station' then return end
 local held=r.task and lines(r.task) or {}
 for item,n in pairs(r.ownedCargo) do
  local have=math.min(n,(r.ship.cargo or {})[item] or 0)
  -- (never sell goods a current job still needs aboard)
  for _,line in ipairs(held) do if line.item==item and r.task.phase=='delivery' then have=0 end end
  if have<=0 and ((r.ship.cargo or {})[item] or 0)<=0 then r.ownedCargo[item]=nil
  elseif have>0 and buys(station,item) then
   local value=Transport.tradeValue(u,{item=item,amount=have},station)
   r.credits=(r.credits or 0)+require('src.accounts').pay(u,station,value,'bought',item)
   J.deliver(u,station,item,have)
   cargo(r,item,-have)
   r.ownedCargo[item]=n-have>0 and n-have or nil
  end
 end
 if not next(r.ownedCargo) then r.ownedCargo=nil end
end
-- Last resort for loaded prepaid freight that can neither be delivered nor
-- returned: refund the buyer, take the cargo off the ship, end the job.
-- Never waits, so a loaded prepaid job always ends.
function Transport.cancelPrepaid(u,r,t,reason,clock)
 for _,line in ipairs(lines(t)) do
  if prepaid(t,line) then Transport.unwindPrepaid(u,line) end
  if not line.trade then
   local have=(r.ship.cargo or {})[line.item] or 0
   local n=math.min(have,line.amount or 0)
   if n>0 then cargo(r,line.item,-n) end
  end
  Tasks.state(u).offers[line.id]=nil
 end
 t.settled=true
 Tasks.state(u).offers[t.id]=nil
 Tasks.release(u,r,reason or 'freight cancelled',clock)
end
function Transport.unloadRecovery(u,r,t,station,clock)
 if t.recoveryStop~=station then return end
 local mode=Transport.recoveryMode(u,t,station,clock)
 if not mode then return end
 local invoice=t.invoice or Transport.invoice(t)
 local aboard,losses={},{}
 for _,charge in ipairs(invoice.lines) do
  local line=charge.task
  local item=line.item
  local have=aboard[item] or ((r.ship.cargo or {})[item] or 0)
  local amount=math.min(line.amount,have)
  aboard[item]=have-amount
  if amount>0 then
   if mode=='return' then
    assert(J.deliver(u,station,item,amount))
    if line.trade then
     local refund=math.min(Transport.tradeValue(u,{item=item,amount=amount},station),
      math.floor((line.tradeCost or 0)*amount/line.amount))
     r.credits=(r.credits or 0)+require('src.accounts').pay(u,station,refund,'trade return',item)
    end
   else
    local budget=math.floor(charge.payment*amount/line.amount)
    local payment=not line.relay and require('src.accounts').pay(u,line.target,math.floor(budget*T.freightRelayShare),'freight',item) or 0
    r.credits=(r.credits or 0)+payment
    r.freightEarnings=(r.freightEarnings or 0)+payment
    -- The replacement inherits the original seller and remaining fee.
    Tasks.post(u,Transport.quote({kind='transport',order=true,stocked=true,relay=true,
     layoutScope='freight_recovery',relayScope=line.relayScope or line.layoutScope,originalSource=Transport.returnStation(line),
     source=station,target=line.target,item=item,amount=amount,
     creditsPerUnit=(budget-payment)/amount,handlingPerUnit=0,handlingLimit=0,
     urgency=math.max(1.5,line.urgency or 0),priority=line.priority,placed=clock,npcClaimAt=clock,
     cooldown=line.cooldown,requires=line.requires},clock,u))
   end
   cargo(r,item,-amount)
  end
  if mode=='return' and prepaid(t,line) then Transport.unwindPrepaid(u,line) end
  if not line.trade then
   local loss=losses[line.target] or {missing=0,total=0}
   loss.missing=loss.missing+line.amount-amount
   loss.total=loss.total+line.amount
   losses[line.target]=loss
  end
  Tasks.state(u).offers[line.id]=nil
 end
 for destination,loss in pairs(losses) do
  if loss.missing>0 then Transport.answer(u,r,destination,-loss.missing/loss.total) end
 end
 t.settled=true
 Tasks.state(u).offers[t.id]=nil
 Tasks.release(u,r,mode=='return' and 'freight returned' or 'freight transferred',clock)
 return mode
end

-- Only a pilot with dark contacts, the appetite for the risk, and a
-- reachable fence turns a failed delivery into theft.
function Transport.freightFence(u,r,t,from,clock,cargoOnboard)
 if r.agenda and #r.agenda>0 then return end
 local Access=require('src.npc_access')
 if not Access.darkAccess(r) and not require('src.reputation').cartelCrew(r) then return end
 local traits=Personality.ensure(r)
 if traits.ambition<.9 or traits.aggression<.8 then return end
 if Transport.recoveryMode(u,t,Transport.returnStation(t),clock)~='return' then return end
 local carrying=false
 for _,line in ipairs(lines(t)) do
  if line.trade then return end
  if (cargoOnboard[line.item] or 0)>(r.stolenCargo and r.stolenCargo[line.item] or 0) then carrying=true end
 end
 if not carrying then return end
 for _,station in ipairs(require('src.dark').fences()) do
  if require('src.npc_access').canDock(r,station,u,'fence')
   and require('src.dock_room').capacity(station,r.ship.hull)>0 and G.live(from,station,clock) then return station end
 end
end

function Transport.abscond(u,r,t,fence,clock)
 r.stolenCargo=r.stolenCargo or {}
 local aboard,destinations={},{}
 for _,line in ipairs(lines(t)) do
  local have=aboard[line.item] or math.max(0,(r.ship.cargo[line.item] or 0)-(r.stolenCargo[line.item] or 0))
  local amount=math.min(have,line.amount)
  aboard[line.item]=have-amount
  if amount>0 then r.stolenCargo[line.item]=(r.stolenCargo[line.item] or 0)+amount end
  destinations[line.target]=true
  Tasks.state(u).offers[line.id]=nil
 end
 for destination in pairs(destinations) do Transport.answer(u,r,destination,-1) end
 t.settled=true
 Tasks.state(u).offers[t.id]=nil
 Tasks.release(u,r,'absconded with freight',clock)
 r.piracy={phase='escape',base=fence,freightTheft=true,started=clock}
 r.task={id='fence/'..r.id..'/'..clock,kind='fence',target=fence}
 r.taskStatus='taking stolen freight to a fence'
end

-- Give another pilot a chance to collect a released shipment.
local function recentlyStalled(r,o,clock)
 local last=r.lastTask
 return last and last.id==o.id and last.status=='pickup stalled'
  and clock-last.clock<3*T.freightStallTime
end

Tasks.register('transport',{
 requires={capabilities={'cargo'}},
 -- a courier job dropped with the cargo aboard (the ship destroyed or
 -- the job abandoned) loses the whole load
 release=function(u,r,t,reason,clock)
  if t.settled then return end
  for _,line in ipairs(lines(t)) do releaseFunds(u,line) end
  if t.phase~='delivery' then return end
  if t.relay then Tasks.state(u).offers[t.id]=nil end
  Transport.strand(u,r,t,clock)
  local carried=0
  for _,line in ipairs(lines(t)) do if not line.trade then carried=carried+(line.amount or 0) end end
  if carried>0 then Transport.answer(u,r,t.target,-1) end

 end,
 plan=function(t,station,clock)
  if not t.recoveryStop and Transport.embargoed(t) then return end
  if t.phase=='pickup' then return G.itinerary(station,t.source,clock) end
  return Transport.route(station,t.recoveryStop or t.target,clock)
 end,
 eligible=function(u,r,o,station,clock)
  if recentlyStalled(r,o,clock) or Transport.embargoed(o) then return false end
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
  -- (a ship already leaving loaded tops up its hold: src/npc_agenda.lua)
  -- (a bare or badly short shelf at the target never waits for a fuller load)
  if o.order and not r.player and not r.agendaFilling and (o.priority or 0)<1 and (o.urgency or 0)<1.5 and clock-(o.placed or clock)<T.freightMaxWait
   and Transport.loadAt(u,o.source,to)<T.freightMinRun then return false end
  -- an order takes whatever part of it this hold can carry
  local need=o.order and math.min(o.amount,T.orderMinLoad) or o.amount
  -- a courier is trusted with only so much of someone else's cargo: it
  -- takes the part of a valuable order it's trusted with, or none
  if o.order and not o.tradeOptional then
   local trusted=Transport.trustedUnits(u,r,o)
   if trusted<1 then return false end
   need=math.min(need,trusted)
  end
  if o.trade or o.tradeOptional then
   local units=freightTerms(u,r,o,math.min(o.amount,room(r,o.item,o.amount)))
   if units<1 then return false end
   need=math.min(need,units)
  end
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
  if o.trade or o.tradeOptional then
   amount,pay=freightTerms(u,r,o,amount)
  elseif o.manifest or o.creditsPerUnit==nil then
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
  -- a tired crew would rather finish near home, where it rests
  -- (src/crew_fatigue.lua)
  local Fatigue=require('src.crew_fatigue')
  if r.homeStation and Fatigue.level(r)>=Fatigue.threshold(r)*T.fatigueHomeward then
   local function system(key) local p=L.byId[L.canonical(key)];local a=p and p.area;return a and Fields.moons[a] and Fields.moons[a].parent or a end
   if system(o.target)~=system(r.homeStation) then risk=risk+T.fatigueAwayPenalty*Fatigue.level(r) end
  end
  -- each trader reads the board a little differently, so a fleet doesn't
  -- all chase the single best-paying job into one dock queue
  local h=0;local key=tostring(r.id)..tostring(o.id)
  for i=1,#key do h=(h*31+key:byte(i))%1000003 end
  local taste=1+T.freightScoreJitter*((h%1000)/500-1)
  -- need (urgency and shortage age) against pay, weighed by personality:
  -- an ambitious trader chases the rate, a steady one the oldest shortage.
  -- Both are capped so neither swamps the other; the empty run to a pickup
  -- elsewhere is already in the rate (Transport.duration).
  local need=math.min(T.freightNeedCap,(o.urgency or o.priority or 0)*10000+age*100)
  return (o.order and 1000000 or 0)+need*(1.5-ambition)
   +math.min(T.freightScoreCap,reward*100*taste*(1-math.min(.9,risk)))*(0.5+ambition)
 end,
 prepare=function(u,r,t,station,clock)
  if Transport.embargoed(t) then return false end
  Transport.quote(t,clock,u)
  t.route=Transport.route(t.source,t.target,clock)
  if not t.route then return false end
  local listed={}
  if t.order then
   local offers=Tasks.state(u).offers
   if t.trade or t.tradeOptional then
    local capacity=math.min(t.amount,room(r,t.item,t.amount),Transport.available(u,t.source,t.item,t.id))
    local units,_,trade=freightTerms(u,r,t,capacity)
    if units<1 then return false end
    t.buyerFunded=t.tradeOptional and not trade or nil
    t.amount,t.trade,t.tradeOptional=units,trade or nil,nil
   end
   local candidates={t};local others={}
   -- A full bay: every open order at this pickup for the same drop-off, or
   -- for another station in the same area (a milk run: dropped off in
   -- turn, the first drop-off's orders first).
   local area=L.byId[t.target] and L.byId[t.target].area
   local capabilities=require('src.npc_access').capabilities(r)
   for _,o in pairs(offers) do
    -- (freight only: satellite jobs are board orders too, carrying no item)
    if not t.relay and not o.relay and not t.trade and not t.buyerFunded and not o.trade and not o.tradeOptional and o.id~=t.id and o.kind=='transport' and o.order and o.state=='available' and (o.readyAt or 0)<=clock and (r.player or Tasks.npcMayClaim(u,o,clock))
     and not r.player and not Transport.embargoed(o) and not recentlyStalled(r,o,clock) and o.source==t.source and o.item
     and (o.target==t.target or (not t.trunk and not o.trunk and L.byId[o.target] and L.byId[o.target].area==area and Transport.route(t.target,o.target,clock)~=nil))
     and require('src.npc_access').eligible(r,o,capabilities,u) then others[#others+1]=o end
   end
   table.sort(others,function(a,b)
    local sa,sb=a.target==t.target,b.target==t.target
    if sa~=sb then return sa end
    if a.target~=b.target then return a.target<b.target end
    return a.id<b.id end)
   for _,o in ipairs(others) do candidates[#candidates+1]=o end
   local fit=fitter(r)
   local manifest={};local planned={}
   for _,o in ipairs(candidates) do
    local n=math.min(o.amount,Transport.available(u,o.source,o.item,o.id)-(planned[o.item] or 0),Transport.trustedUnits(u,r,o))
    if n>0 then n=math.min(n,fit.room(o.item,o.amount)) end
    if n>0 then
     local line=require('src.persistence').copy(o);line.amount=n
     Transport.quote(line,clock,u);manifest[#manifest+1]=line;planned[o.item]=(planned[o.item] or 0)+n
     fit.add(line.item,n) -- reserve grid space while fitting the other lines
    end
   end
   if #manifest==0 or manifest[1].id~=t.id then return false end
   if not reserveFunds(u,t,manifest[1]) then return false end
   t.manifest=manifest;t.amount=manifest[1].amount
   for _,line in ipairs(manifest) do
    local o=offers[line.id];listed[o.id]=o.amount
    o.amount=line.amount;o.owner=r.id;o.state='reserved';o.manifestRoot=t.id
   end
  elseif room(r,t.item,t.amount)<t.amount then return false end
  t.phase='pickup'
  if station~=t.source or Transport.load(u,r,t) then
   for _,line in ipairs(lines(t)) do
    local amount=listed[line.id]
    local o=amount and Tasks.state(u).offers[line.id]
    -- Buy orders already repost their outstanding balance at settlement.
    if o and not o.playerOrder and amount>line.amount then
     local remainder=require('src.persistence').copy(o)
     remainder.amount=amount-line.amount
     remainder.owner,remainder.manifestRoot,remainder.loaded,remainder.loadedAt=nil,nil,nil,nil
     Tasks.post(u,remainder)
    end
   end
   return true
  end
  for _,line in ipairs(lines(t)) do
   releaseFunds(u,line)
   local o=Tasks.state(u).offers[line.id]
   if o then
    o.owner,o.state,o.manifestRoot=nil,'available',nil
    o.amount=listed[o.id] or o.amount
   end
  end
  return false
 end,
 complete=function(u,r,t,station,clock)
  if t.settled then return true end
  if t.recoveryStop==station then
   if r.state~='docked' then return false end
   if not Transport.unloadRecovery(u,r,t,station,clock) then
    t.recoveryTried=t.recoveryTried or {};t.recoveryTried[station]=true
    t.recoveryStop=nil
   end
   return false -- recovery settles its own board entries and records its outcome
  end
  if Transport.embargoed(t) then
   if t.phase=='pickup' then Tasks.release(u,r,'freight embargoed',clock) end
   return false
  end
  Transport.quote(t,clock,u)
  if t.phase=='pickup' then
   if station~=t.source then return false end
   if not Transport.load(u,r,t) then Tasks.release(u,r,'nothing to pick up',clock) end
   return false
  end
  if station~=t.target then return false end
  -- (a milk run's invoice is made once, at the first drop-off, and each
  -- stop is paid its own lines)
  local invoice=t.invoice or Transport.invoice(t);t.invoice=invoice
  local paid,total=0,0
  local here,later={},{}
  for _,charge in ipairs(invoice.lines) do
   if charge.task.target==nil or charge.task.target==station then here[#here+1]=charge else later[#later+1]=charge end
  end
  -- cargo that went missing on the way (robbed, jettisoned) is not
  -- delivered: what's aboard is, paid pro rata, and a courier answers for
  -- the rest with its standing at the buyer's faction (Transport.answer)
  local aboard={};local carried,lost=0,0
  for _,charge in ipairs(here) do
   local line=charge.task
   if aboard[line.item]==nil then aboard[line.item]=(r.ship.cargo or {})[line.item] or 0 end
   local n=math.max(0,math.min(line.amount,aboard[line.item]))
   aboard[line.item]=aboard[line.item]-n
   if not line.trade then carried=carried+line.amount;lost=lost+line.amount-n end
   if line.reservedPurchase then line.fundedValue=math.floor(line.reservedPurchase*n/line.amount+.5) end
   if n<line.amount then
    charge.payment=line.amount>0 and math.floor(charge.payment*n/line.amount) or 0
    if line.tradeCost then line.tradeCost=math.floor(line.tradeCost*n/math.max(1,line.amount)) end
    if line.prepaidGoods then line.prepaidGoods=math.floor(line.prepaidGoods*n/line.amount) end
    line.amount=n
   end
  end
  if carried>0 then Transport.answer(u,r,station,lost>0 and -lost/carried or 1) end
  for _,charge in ipairs(here) do
   local line=charge.task;paid=paid+charge.payment
   -- a trader is paid the station's price as it docks, before its own
   -- cargo lands on the shelf and pulls that price down
   if line.trade then line.tradeValue=line.fundedValue or Transport.tradeValue(u,line,station) end
   cargo(r,line.item,-line.amount)
   -- (a player's buy order goes to their storage or stall: src/buy_orders.lua)
   if line.playerOrder then require('src.buy_orders').delivered(u,line.playerOrder,station,line.item,line.amount,clock)
   elseif line.mine or line.stocked then J.deliver(u,station,line.item,line.amount) end
   if line.intake then require('src.merchants').received(u,line.intake,station,line.item,line.amount) end
   require('src.economy').stat(u,'hauled',line.item,line.amount)
   local payment
   if line.trade then
    -- the trader sells to the station at its price today
    local value=line.tradeValue
    if line.reservedPurchase then
     require('src.accounts').refund(u,station,line.reservedPurchase-value)
     line.reservedPurchase=nil
     require('src.economy').ledger(u,station,'bought',value,line.item)
    else require('src.accounts').pay(u,station,value,'bought',line.item) end
    require('src.markets').landed(u,station,line.item,line.amount,value)
    paid=paid-charge.payment+value;payment=0;total=total+line.amount
    r.tradeEarnings=(r.tradeEarnings or 0)+value
    require('src.economy').ledger(u,station,'trade margin',value-(line.tradeCost or 0),line.item)
   else
   local Accounts=require('src.accounts')
   if line.prepaidFee then
    payment=charge.payment
    Accounts.refund(u,station,line.prepaidFee-payment)
    line.prepaidFee=nil
    require('src.economy').ledger(u,station,'freight',payment,line.item)
   else payment=Accounts.pay(u,station,charge.payment,'freight',line.item) end
   total=total+line.amount
   paid=paid-(charge.payment-payment)
   end
   -- an economy order is a sale: the buyer pays the seller for the goods
   -- (after the courier), and a hub sells on at a markup
   if (line.layoutScope=='economy' or line.relayScope=='economy') and not line.trade and not line.playerOrder and not line.intake then
    local goods=line.prepaidGoods or Transport.settleGoods(u,line,station)
    require('src.markets').landed(u,station,line.item,line.amount,goods+payment)
   end
   if (line.premiumPerUnit or 0)>0 then require('src.economy').ledger(u,station,'premium',math.floor(line.amount*line.premiumPerUnit),line.item) end
   require('src.simulation_history').note(u,'freight_delivered',clock,L.byId[station].area,{r.id},
    {taskId=line.id,source=line.source,target=line.target,item=line.item,amount=line.amount,routeAU=line.routeAU,creditsPerUnit=line.creditsPerUnit,premiumPerUnit=line.premiumPerUnit,handling=charge.handling,payment=payment,trade=line.trade,tradeCost=line.tradeCost,tradeValue=line.tradeValue,commodityBuyPrice=line.commodityBuyPrice,commoditySellPrice=line.commoditySellPrice},station)
   if line.id~=t.id then Tasks.state(u).offers[line.id]=nil end
  end
  local state=Tasks.state(u);state.delivered=state.delivered or {};state.delivered[station]=(state.delivered[station] or 0)+total
  r.credits=(r.credits or 0)+paid
  local fees=0;for _,charge in ipairs(here) do if not charge.task.trade then fees=fees+charge.payment end end
  r.freightEarnings=(r.freightEarnings or 0)+math.min(paid,fees)
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
