-- Transport tasks: carry a station's order (src/economy.lua) from the
-- station that has the goods to the one that wants them. The destination
-- commissions the shipment; its operating budget is unlimited for now.
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
 return r.ship.hold and Hold.deserialize(r.ship.hold,function(id)return data.items[id]~=nil end)
end
local function room(r,item,amount)
 local h=hold(r)
 if h then return Hold.room(h,item,amount) end
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
function Transport.route(source,target,clock)
 local a,b=L.byId[source],L.byId[target]
 if not a or not b or source==target then return end
 return G.itinerary(source,target,clock)
end
-- Quote the delivery route, excluding empty travel to pickup and service detours.
-- Only mass-driver legs cover AU; local and moon-gate legs use the base rate.
-- AU is quoted to hundredths so the displayed distance explains the price.
function Transport.quote(t,clock)
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
 -- Existing flat-rate contracts retain their agreed price.
 if t.creditsPerUnit==nil then
  t.creditsPerUnit=math.floor((T.freightCreditsPerUnit+t.routeAU*T.freightCreditsPerAU)*100+.5)/100
 end
 return t
end
function Transport.payment(t)
 Transport.quote(t)
 return math.floor(t.amount*t.creditsPerUnit+1e-7)
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
  -- an order takes whatever part of it this hold can carry
  local need=o.order and math.min(o.amount,T.orderMinLoad) or o.amount
  return room(r,o.item,need)>=need
   and (not (o.mine or o.stocked) or J.available(u,o.source,o.item)>=need)
 end,
 feasible=function(u,r,o,station,clock)
  return (station==o.source or reachable(station,o.source,clock,true)) and reachable(o.source,o.target,clock)
 end,
 score=function(u,r,o,station,clock)
  -- Urgency stays first. Ambition weighs reward and distance against an
  -- empty pickup flight; age still breaks ties and keeps old work moving.
  Transport.quote(o,clock)
  -- A station's order for something it's short of beats placeholder work.
  -- A return trip is fine for orders (that's how empties get back to the
  -- makers); only placeholder work avoids shuttling straight back.
  return clock-(o.readyAt or 0)-(not o.order and r.lastOrigin==o.target and 100000 or 0)
   +Personality.freightScore(r,o.creditsPerUnit,o.routeAU,station~=o.source)
   +(o.order and 10000000*(1+(o.priority or 0)) or 0)
 end,
 prepare=function(u,r,t,station,clock)
  Transport.quote(t,clock)
  if t.order then
   -- fold in the other open orders on the same run, so one trip carries a
   -- full hold instead of a few canisters
   local offers=Tasks.state(u).offers;local fit=room(r,t.item,1e6)
   for id,o in pairs(offers) do
    if id~=t.id and o.order and o.state=='available' and o.source==t.source and o.target==t.target
     and o.item==t.item and t.amount+o.amount<=fit then
     Transport.quote(o,clock)
     if o.creditsPerUnit==t.creditsPerUnit and o.routeAU==t.routeAU then
      t.amount=t.amount+o.amount;offers[id]=nil
     end
    end
   end
   -- size the load to the hold (and to what's there), and say so on the
   -- order, so the station counts only what's really coming
   t.amount=math.min(t.amount,room(r,t.item,t.amount))
   if station==t.source then t.amount=math.min(t.amount,J.available(u,t.source,t.item)) end
   if t.amount<=0 then return false end
   local o=Tasks.state(u).offers[t.id];if o then o.amount=t.amount end
  end
  t.route=Transport.route(t.source,t.target,clock)
  if not t.route or room(r,t.item,t.amount)<t.amount then return false end
  if station~=t.source then t.phase='pickup';return true end
  if (t.mine or t.stocked) and not J.take(u,t.source,t.item,t.amount) then return false end
  cargo(r,t.item,t.amount);t.phase='delivery'
  return true
 end,
 complete=function(u,r,t,station,clock)
  if t.settled then return true end
  Transport.quote(t,clock)
  if t.phase=='pickup' then
   -- Arrived empty at the source: load up, then carry on to the target.
   if station~=t.source then return false end
   if t.order then t.amount=math.min(t.amount,math.max(1,J.available(u,t.source,t.item))) end
   if room(r,t.item,t.amount)<t.amount or ((t.mine or t.stocked) and not J.take(u,t.source,t.item,t.amount)) then
    Tasks.release(u,r,'nothing to pick up',clock);return false
   end
   local offer=Tasks.state(u).offers[t.id];if offer then offer.amount=t.amount end
   cargo(r,t.item,t.amount);t.phase='delivery';t.route=Transport.route(t.source,t.target,clock)
   return false
  end
  if station~=t.target then return false end
  local h=hold(r)
  local amount=h and Hold.count(h,t.item) or (r.ship.cargo or {})[t.item] or 0
  if amount<t.amount then
   Tasks.release(u,r,'cargo lost',clock);return false
  end
  cargo(r,t.item,-t.amount)
  if t.mine or t.stocked then J.deliver(u,station,t.item,t.amount) end
  require('src.economy').stat(u,'hauled',t.item,t.amount)
  local state=Tasks.state(u);state.delivered=state.delivered or {}
  state.delivered[station]=(state.delivered[station] or 0)+t.amount
  r.lastDestination=station;r.lastOrigin=t.source
  local paid=Transport.payment(t)
  r.credits=(r.credits or 0)+paid
  r.freightEarnings=(r.freightEarnings or 0)+paid
  t.settled=true
  require('src.simulation_history').note(u,'freight_delivered',clock,L.byId[station].area,{r.id},
   {taskId=t.id,source=t.source,target=t.target,item=t.item,amount=t.amount,routeAU=t.routeAU,creditsPerUnit=t.creditsPerUnit,payment=paid},station)
  return true
 end
})
function Transport.seed(u)
 local state=Tasks.state(u)
 state.transportSeeded=true
 for _,o in pairs(state.offers) do if o.kind=='transport' then Transport.quote(o,u.clock) end end
 for _,r in pairs(u.npcs or {}) do
  local t=r.task or r.suspendedTask
  if t and t.kind=='transport' then Transport.quote(t,u.clock) end
 end
 -- Nothing is authored any more: every haul is a station's order
 -- (src/economy.lua). Syncing an empty list clears the old scrap and
 -- freight runs from saves, leaving reserved trips to finish.
 local specs={}
 Tasks.sync(u,'transport',specs,function(o)return o.kind=='transport' end)
end
return Transport
