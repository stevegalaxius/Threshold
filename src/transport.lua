-- Authored dispatch work: placeholder scrap, real ore and commodity hauls
-- from station stock (src/commodities.lua). No prices or NPC credits yet.
local Tasks=require('src.tasks')
local Fields=require('src.fields')
local L=require('src.locations')
local G=require('src.travelgraph')
local Hold=require('src.inventory.hold')
local data=require('src.data')
local J=require('src.jobs')
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
 if not a or not b or a.area==b.area then return end
 return G.itinerary(source,target,clock)
end
Tasks.register('transport',{
 roles={trader=true,courier=true},
 plan=function(t,station,clock)
  if t.phase=='pickup' then return G.itinerary(station,t.source,clock) end
  return Transport.route(station,t.target,clock)
 end,
 eligible=function(u,r,o,station,clock)
  -- Old reserved manifests may finish, but never issue new placeholder ore.
  if o.item=='martian_ore' then return false end
  -- Work elsewhere means flying there empty first (a pickup leg).
  if station~=o.source and (r.task or not L.byId[station] or not G.itinerary(station,o.source,clock)) then return false end
  local source,target=L.byId[o.source],L.byId[o.target]
  if not source or not target then return false end
  local from,to=source.area,target.area
  -- Retired return manifests can remain reserved in old saves until delivery.
  -- Once released, they must not let an empty strip mine generate more cargo.
  if J.isMine(from) and to==J.oreTo and (not o.mine or o.item~=J.item) then return false end
  -- Mars's dispatch workers run the moon supply/ore circuit. Existing trips
  -- elsewhere finish normally before the worker chooses its next duty.
  if r.home=='mars' and r.taskWorker and not
   (from==J.oreTo and J.isMine(to) or from~=J.oreTo and to==J.oreTo) then return false end
  if o.cap and J.available(u,o.target,o.item)>=o.cap then return false end
  return room(r,o.item,o.amount)>=o.amount
   and (not (o.mine or o.stocked) or J.available(u,o.source,o.item)>=o.amount)
   and Transport.route(o.source,o.target,clock)~=nil
 end,
 score=function(u,r,o,station,clock)
  -- Oldest dispatch first, with immediate return trips deprioritized.
  -- Work at this station before work elsewhere.
  return clock-(o.readyAt or 0)-(r.lastOrigin==o.target and 100000 or 0)-(station~=o.source and 1000000 or 0)
 end,
 prepare=function(u,r,t,station,clock)
  t.route=Transport.route(t.source,t.target,clock)
  if not t.route or room(r,t.item,t.amount)<t.amount then return false end
  if station~=t.source then t.phase='pickup';return true end
  if (t.mine or t.stocked) and not J.take(u,t.source,t.item,t.amount) then return false end
  cargo(r,t.item,t.amount);t.phase='delivery'
  return true
 end,
 complete=function(u,r,t,station,clock)
  if t.phase=='pickup' then
   -- Arrived empty at the source: load up, then carry on to the target.
   if station~=t.source then return false end
   if room(r,t.item,t.amount)<t.amount or ((t.mine or t.stocked) and not J.take(u,t.source,t.item,t.amount)) then
    Tasks.release(u,r,'nothing to pick up',clock);return false
   end
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
  local state=Tasks.state(u);state.delivered=state.delivered or {}
  state.delivered[station]=(state.delivered[station] or 0)+t.amount
  r.lastDestination=station;r.lastOrigin=t.source
  return true
 end
})
function Transport.seed(u)
 local state=Tasks.state(u)
 state.transportSeeded=true
 -- Saved manifests reconcile with the current ports when loading the world.
 -- Reservations survive; new ports receive work without resetting the board.
 local specs={}
 for _,from in ipairs(Fields.list) do
  if Fields[from].driverId then
   for _,to in ipairs(Fields.list) do
    if from~=to and Fields[to].driverId then
     for _,source in ipairs(L.stations(from,'trade')) do
      for _,target in ipairs(L.stations(to,'trade')) do
       specs[#specs+1]={kind='transport',source=source,target=target,item='scrap',amount=5}
      end
     end
    end
   end
  end
 end
 -- Commodities go from the regions that make them to the ones that use them.
 for _,c in ipairs(require('src.commodities').list) do
  for from in pairs(c.make) do for to in pairs(require('src.commodities').takers(c)) do
   for _,a in ipairs(L.stations(from,'trade')) do for _,b in ipairs(L.stations(to,'trade')) do
    specs[#specs+1]={kind='transport',source=a,target=b,item=c.item,amount=c.amount,stocked=true,cap=c.cap}
   end end
  end end
 end
 -- Mars hauls ore down from its mining moons and sends supplies back up.
 for _,mine in ipairs(J.mines) do
  local a=L.station(mine,'mining')
  if a then
   for _,b in ipairs(L.stations(J.oreTo,'trade')) do
    specs[#specs+1]={kind='transport',source=a,target=b,item=J.item,amount=10,mine=mine}
   end
  end
 end
 -- Planets and their moons trade with each other too.
 for _,moon in ipairs(Fields.list) do
  local parent=Fields.moons and Fields.moons[moon] and Fields.moons[moon].parent
  if parent then
   for _,a in ipairs(L.stations(moon,'trade')) do
    for _,b in ipairs(L.stations(parent,'trade')) do
     -- These two strip mines ship real ore, not generated return cargo.
     if not J.isMine(moon) then
      specs[#specs+1]={kind='transport',source=a,target=b,item='scrap',amount=5}
     end
     specs[#specs+1]={kind='transport',source=b,target=a,item='scrap',amount=5}
    end
   end
  end
 end
 Tasks.sync(u,'transport',specs,function(o)return o.kind=='transport' end)
end
return Transport
