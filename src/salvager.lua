-- Civilian scavengers: loose cargo -> local station resale, never spawned loot.
local Fields,L,G=require('src.fields'),require('src.locations'),require('src.travelgraph')
local T,data,Stats=require('src.tuning'),require('src.data'),require('src.stats')
local Ship,Hold=require('src.ship'),require('src.inventory.hold')
local Homes,Population=require('src.npc_home'),require('src.population')
local Repairs,Supplies=require('src.npc_repair'),require('src.supplies')
local Fuel=require('src.reactor_fuel')
local Tasks=require('src.tasks')
local copy=require('src.persistence').copy
local NPC=require('src.npc')
local S={}
function S.system(area)
 local root=Fields.moons[area] and Fields.moons[area].parent or area
 local areas={root}
 for _,moon in ipairs(Fields.moonsOf(root)) do areas[#areas+1]=moon end
 return areas
end
local Scavenge=require('src.scavenge')
local function units(r) return Scavenge.taken(r) end
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
 r.ship.cargo=cargo;r.salvageCargo={};r.salvageUntil=nil;r.salvageReturn=nil;r.salvageGoal=nil
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
-- Debug callers use the shared controller for completion, upkeep and selection.
function S.depart(game,r,node,clock) return NPC.decide(game.universe,r,node,clock,game) end
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
 if not NPC.travel(game,r,target,game.universe.clock) then return false end
 if r.task then r.task.route=copy(r.route) end
 return true
end
function S.advance(game,r,clock) return NPC.advance(r,clock,game.universe,game) end
function S.create(game,area,node,clock)
 local def=data.enemies.salvager_packhorse;local hull=data.hulls[def.hull]
 local u=game.universe;u.nextNpcId=(u.nextNpcId or 0)+1
 local r={id='npc/'..u.nextNpcId,archetype=def.id,home=area,area=area,
  state='docked',node=node,route={node,node},index=1,untilTime=clock,speed=NPC.cruise(def.id),
  spread=0,taskWorker=true,credits=0,salvageCargo={},salvageGoal=node,
  ship={hull=def.hull,loadout=copy(def.loadout),cargo={},armor=Stats.compute(hull,def.loadout).armor}}
 require('src.npc_templates').apply(r,'salvager',area)
 require('src.personality').ensure(r)
 Homes.assign(r,node);u.npcs[r.id]=r
 Fuel.withRecord(r,function() end);r.fuelClock=clock
 NPC.advance(r,clock,u,game)
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
Tasks.register('salvage',{
 requires={capabilities={'cargo'}},
 docks=function(r,id) return L.canonical(id)==L.canonical(r.salvageGoal) end,
 nextAction=Scavenge.nextAction,
 pickedUp=Scavenge.pickedUp,
 stay=function() return T.salvagerStay end,
 before=function(c)
  local r,game,clock=c.r,c.game or {universe=c.u},c.clock
  if r.salvageReturn or not r.area then return end
  local done=Scavenge.done(r,clock)
  if not done and units(r)>0 and not (r.action and r.action.kind=='work') and clock>=(r.salvageCheckAt or 0) then
   r.salvageCheckAt=clock+T.securityThink
   done=not require('src.offline_loot').hasLoot(game,r,clock)
  end
  if done then S.returnRecord(game,r,false) end
 end,
 eligible=function(u,r,o,node)
  -- staying put is only a job where there are buoys to sweep on the way
  if o.source==o.target and #(Fields[L.get(o.target).area].buoyIds or {})==0 then return false end
  local area=L.get(node).area
  local root=Fields.moons[area] and Fields.moons[area].parent or area
  if node~=o.source or o.system~=root or not L.byId[o.source] or not L.byId[o.target] then return false end
  local h=r.ship.hold and Hold.deserialize(r.ship.hold)
  if h then return Hold.room(h,'scrap',1)>0 end
  local used=0
  for id,n in pairs(r.ship.cargo or {}) do used=used+data.items[id].volume*n end
  return (data.hulls[r.ship.hull].hold or 0)-used>=data.items.scrap.volume
 end,
 feasible=function(u,r,o,node,clock) return G.itinerary(o.source,o.target,clock)~=nil end,
 score=function(u,r,o)
  local areas=S.system(o.system);local wanted=areas[(r.salvageVisit or 0)%#areas+1]
  return (L.get(o.target).area==wanted and 10000 or 0)-(o.target==r.lastSalvageTarget and 100 or 0)
 end,
 prepare=function(u,r,t,node,clock)
  local area=L.get(t.target).area;local buoys=Fields[area].buoyIds
  local visit=(r.salvageVisit or 0)+1
  local waypoint=buoys[(visit-1)%math.max(1,#buoys)+1] or t.target
  t.route=pathVia(node,waypoint,t.target,clock)
  if not t.route then return false end
  r.salvageVisit=visit;r.lastSalvageTarget=t.target;t.phase='collecting'
  r.salvageGoal=t.target;r.salvageReturn=nil
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
