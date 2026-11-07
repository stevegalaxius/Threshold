-- Civilian scavengers: loose cargo -> local station resale, never spawned loot.
local Fields,L,G=require('src.fields'),require('src.locations'),require('src.travelgraph')
local T,data,Stats=require('src.tuning'),require('src.data'),require('src.stats')
local Ship,Hold=require('src.ship'),require('src.inventory.hold')
local Homes,Population=require('src.npc_home'),require('src.population')
local Repairs,Supplies=require('src.npc_repair'),require('src.supplies')
local Fuel=require('src.reactor_fuel')
local Tasks=require('src.tasks')
local copy=require('src.persistence').copy
local S={}
function S.system(area)
 local root=Fields.moons[area] and Fields.moons[area].parent or area
 local areas={root}
 for _,moon in ipairs(Fields.moonsOf(root)) do areas[#areas+1]=moon end
 return areas
end
local function units(r)
 local n=0;for _,count in pairs(r.salvageCargo or {}) do n=n+count end;return n
end
function S.sell(game,r,node,clock)
 local sold,total={},0
 local h=r.ship.hold and Hold.deserialize(r.ship.hold)
 local cargo=h and Hold.totals(h) or r.ship.cargo
 local reserve=Supplies.targets(r)
 -- Match normal station trade: recovered goods become resale, at the same price.
 local shelf
 for id,count in pairs(r.salvageCargo or {}) do
  local n=math.min(count,math.max(0,(cargo[id] or 0)-(reserve[id] or 0)))
  if n>0 then
   local stack={id=id,n=n,resale=(clock or game.universe.clock)+T.resaleTime}
   shelf=shelf or game:stationMarket({key=node,locationId=node},1).hold
   Hold.placeStack(shelf,stack) -- full shelves sell stock onward, like player trade
   total=total+game.sellPrice(stack);sold[id]=n
   if h then Hold.take(h,id,n) else cargo[id]=cargo[id]-n end
  end
 end
 if h then r.ship.hold=Hold.serialize(h);cargo=Hold.totals(h) end
 r.ship.cargo=cargo;r.salvageCargo={};r.salvageUntil=nil
 r.credits=(r.credits or 0)+total;r.salvageEarnings=(r.salvageEarnings or 0)+total
 r.salvageSales=r.salvageSales or {}
 for id,n in pairs(sold) do r.salvageSales[id]=(r.salvageSales[id] or 0)+n end
 if total>0 then require('src.events').emit('salvage_sale',r.id,node,sold,total) end
 return total
end
local function pathVia(source,waypoint,target,clock)
 local first=G.itinerary(source,waypoint,clock)
 local second=G.itinerary(waypoint,target,clock)
 if not first or not second then return end
 for i=2,#second do first[#first+1]=second[i] end
 if #first==1 then first[2]=first[1] end
 return first
end
function S.depart(game,r,node,clock)
 if r.salvageGoal and L.byId[r.salvageGoal] and node~=r.salvageGoal then return false end
 Tasks.arrive(game.universe,r,node,clock,game)
 Supplies.refill(r,node);Fuel.observe(game.universe,r,clock)
 if r.fuelStatus=='stranded' then r.untilTime=clock+10;return false end
 local task=Tasks.choose(game.universe,r,node,clock)
 if not task then r.taskStatus='waiting for salvage work';r.untilTime=clock+10;return false end
 r.salvageGoal=task.target;r.salvageReturn=nil;r.route=copy(task.route);r.index=1
 r.taskStatus='roaming '..Fields[L.get(task.target).area].name
 return true
end
function S.returnRecord(game,r,maintenance)
 if r.salvageReturn then return true end
 if not r.area or r.state~='travel' and r.state~='idle' then return false end
 if not maintenance and r.task and r.area~=L.get(r.task.target).area then return false end
 local source=r.route[r.index]
 -- Finish an already committed gate crossing before choosing a local port.
 if L.get(source).kind=='moon_gate' or L.get(source).kind=='driver' then return false end
 local target=L.station(r.area,'trade') or Homes.get(r)
 local tail=target and G.itinerary(source,target,game.universe.clock)
 if not tail then r.taskStatus='no route to a salvage market';return false end
 require('src.offline_loot').release(game,r,game.universe.clock)
 r.salvageReturn=true;r.salvageGoal=target;r.taskStatus='returning to sell salvage'
 if r.task then r.task.phase='selling';r.task.target=target end
 if r.state=='travel' then
  local previous=r.route[(r.index-2)%#r.route+1]
  r.route={previous};for _,id in ipairs(tail) do r.route[#r.route+1]=id end;r.index=2
 else
  r.route=tail;r.index=1
  if #tail>1 then require('src.alife').start(r,game.universe.clock,2)
  else r.state='docked';r.node=target;Repairs.begin(r,target,game.universe.clock,T.salvagerStay) end
 end
 if r.task then r.task.route=copy(r.route) end
 return true
end
function S.advance(game,r,clock,start)
 if r.state=='dead' or r.state=='escaped' or r.encounter then return end
 if not r.salvageReturn and r.area and (units(r)>=T.salvagerLoad or units(r)>0 and clock>=(r.salvageUntil or 0)
  or units(r)>0 and not require('src.offline_loot').hasLoot(game,r,clock)) then S.returnRecord(game,r,false) end
 for _=1,64 do
  if r.state=='travel' or r.state=='transit' then
   if clock<r.arrive then return end
   local at=r.arrive
   if r.index<#r.route then start(r,at,r.index+1)
   else
    r.area=L.get(r.route[r.index]).area;r.transit=nil;r.state='docked';r.node=r.route[r.index]
    Repairs.begin(r,r.node,at,T.salvagerStay)
   end
  elseif r.state=='docked' then
   Repairs.advance(r,clock,r.node or r.route[r.index])
   if clock<r.untilTime then return end
   local at=r.untilTime
   if not S.depart(game,r,r.node or r.route[r.index],at) then return end
   start(r,at,2)
  else return end
 end
end
function S.think(game,e,dt,AI)
 local r=e.alifeRecord
 if not r or r.role~='salvager' then return false end
 if e.alifeEgress or e.driverTractor or e.launch then AI.trade(game,e,dt);return true end
 if not r.salvageReturn and (units(r)>=T.salvagerLoad or units(r)>0 and game.universe.clock>=(r.salvageUntil or 0)) then
  local A=require('src.alife');A.capture(game,e,false)
  if S.returnRecord(game,r,false) then A.bindRoute(game,e,r) end
  e.tractorTarget=nil;e.intent.tractor=false;AI.trade(game,e,dt);return true
 end
 if r.salvageReturn then e.intent.tractor=false;e.tractorTarget=nil;AI.trade(game,e,dt);return true end
 if game.time>=(e.salvageScanAt or 0) then
  e.salvageScanAt=game.time+T.securityThink
  local previous=e.salvagePickup;e.salvagePickup=nil
  local x,y=e.body:getPosition();local best=T.salvagerRange^2
  for _,p in ipairs(game.pickups) do
   local owner=p.collector
   if p.count>0 and not p.inner and (not owner or owner==e or owner.dead or owner.removed or owner.tractorTarget~=p)
    and Ship.canFit(e,p.item,1)>0 then
    local d=(p.x-x)^2+(p.y-y)^2
    if d<best then best=d;e.salvagePickup=p end
   end
  end
  if previous and previous~=e.salvagePickup and previous.collector==e then previous.collector=nil end
 end
 local p=e.salvagePickup;local exists=false
 for _,candidate in ipairs(game.pickups) do if candidate==p then exists=true;break end end
 if p and exists and p.count>0 and Ship.canFit(e,p.item,1)>0 then
  local x,y=e.body:getPosition();local dx,dy=p.x-x,p.y-y;local d=math.sqrt(dx*dx+dy*dy)
  local range=Ship.tractorRange(e)
  AI.navigate(game,e,dx,dy,math.min(e.def.ai.cruise,math.max(20,(d-range*.5)*.6)),p.vx,p.vy,d)
  e.intent.aimX,e.intent.aimY=p.x,p.y
  e.intent.tractor=Ship.distanceTo(e,p.x,p.y)<=range
  e.tractorTarget=e.intent.tractor and p or nil
  p.collector=e;r.taskStatus='collecting loose salvage';return true
 end
 e.tractorTarget=nil;e.intent.tractor=false
 if units(r)>0 then
  local A=require('src.alife');A.capture(game,e,false)
  if S.returnRecord(game,r) then A.bindRoute(game,e,r) end
 end
 AI.trade(game,e,dt);return true
end
function S.create(game,area,node,clock)
 local def=data.enemies.salvager_packhorse;local hull=data.hulls[def.hull]
 local u=game.universe;u.nextNpcId=(u.nextNpcId or 0)+1
 local r={id='npc/'..u.nextNpcId,role='salvager',archetype=def.id,home=area,area=area,
  state='docked',node=node,route={node,node},index=1,untilTime=clock,speed=def.ai.cruise,
  spread=0,taskWorker=true,credits=0,salvageCargo={},salvageGoal=node,
  ship={hull=def.hull,loadout=copy(def.loadout),cargo={},armor=Stats.compute(hull,def.loadout).armor}}
 Homes.assign(r,node);u.npcs[r.id]=r
 Fuel.withRecord(r,function() end);r.fuelClock=clock
 if S.depart(game,r,node,clock) then require('src.alife').start(r,clock,2) end
 return r
end
function S.seed(game)
 local specs={}
 for _,root in ipairs(Fields.list) do
  if Population.target(root,'salvager')>0 then
   local stations={}
   for _,area in ipairs(S.system(root)) do
    for _,node in ipairs(L.stations(area,'trade')) do stations[#stations+1]=node end
   end
   for _,source in ipairs(stations) do for _,target in ipairs(stations) do
    specs[#specs+1]={kind='salvage',source=source,target=target,system=root,cooldown=30}
   end end
  end
 end
 Tasks.sync(game.universe,'salvage',specs,function(o)return o.kind=='salvage' end)
 local u=game.universe;u.salvage=u.salvage or {seeded={}}
 for _,area in ipairs(Fields.list) do
  if Population.target(area,'salvager')>0 and not u.salvage.seeded[area] then
   u.salvage.seeded[area]=true
   for _=Population.count(u,area,'salvager')+1,Population.target(area,'salvager') do
    S.create(game,area,L.station(area,'trade'),u.clock)
   end
  end
 end
end
require('src.events').on('pickup',function(e,item,n)
 local r=e.alifeRecord
 if not r or r.role~='salvager' or r.salvageReturn then return end
 r.salvageCargo=r.salvageCargo or {};r.salvageCargo[item]=(r.salvageCargo[item] or 0)+n
 r.salvageUntil=r.salvageUntil or e.alifeGame.universe.clock+T.salvagerCollectTime
end)
Tasks.register('salvage',{
 roles={salvager=true},
 eligible=function(u,r,o,node)
  return node==o.source and o.system==r.home and L.byId[o.source] and L.byId[o.target]
   and G.itinerary(o.source,o.target,u.clock)~=nil
 end,
 score=function(u,r,o)
  local areas=S.system(r.home);local wanted=areas[(r.salvageVisit or 0)%#areas+1]
  return (L.get(o.target).area==wanted and 10000 or 0)-(o.target==r.lastSalvageTarget and 100 or 0)
 end,
 prepare=function(u,r,t,node,clock)
  local area=L.get(t.target).area;local buoys=Fields[area].buoyIds
  local visit=(r.salvageVisit or 0)+1
  local waypoint=buoys[(visit-1)%math.max(1,#buoys)+1] or t.target
  t.route=pathVia(node,waypoint,t.target,clock)
  if not t.route then return false end
  r.salvageVisit=visit;r.lastSalvageTarget=t.target;t.phase='collecting'
  return true
 end,
 plan=function(t)return copy(t.route) end,
 complete=function(u,r,t,node,clock,game)
  if node~=t.target then return false end
  -- Use the real scene's market helpers even when this NPC is remote.
  S.sell(assert(game,'salvager needs its current game context'),r,node,clock)
  return true
 end,
})
Population.register('salvager',{
 target=function(f,area) return not f.instance and not Fields.moons[area] and f.driverId and L.station(area,'trade') and T.salvagerPopulation end,
 nodes=function(game,area)return L.stations(area,'trade') end,
 create=function(game,area,node,clock)return S.create(game,area,node,clock) end,
})
return S
