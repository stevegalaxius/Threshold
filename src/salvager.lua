-- Salvage board work: loose cargo -> local station resale, never spawned loot.
-- Any hauler can take it (scavenger-tempered haulers prefer it); there is no
-- separate salvager job or population.
local Fields,L,G=require('src.fields'),require('src.locations'),require('src.travelgraph')
local T,data,Stats=require('src.tuning'),require('src.data'),require('src.stats')
local Ship,Hold=require('src.ship'),require('src.inventory.hold')
local Repairs,Supplies=require('src.npc_repair'),require('src.supplies')
local Homes=require('src.npc_home')
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
   if id=='steel_plate' or require('src.markets').items[id] then require('src.stockpile').add(game.universe,node,id,n)
   else Hold.placeStack(shelf,stack) end -- other goods remain ordinary resale
   -- a salvager sells at T.npcSalvageRate of the station's price, not the
   -- player's dump rate (T.sellRate, half): at that rate a salvage run
   -- barely paid for its own fuel, and broke haulers lived on it
   local v=game.sellPrice(stack)
   if T.sellRate>0 then v=math.floor(v/T.sellRate*T.npcSalvageRate) end
   total=total+v;sold[id]=n
   if h then Hold.take(h,id,n) else cargo[id]=cargo[id]-n end
  end
 end
 if h then r.ship.hold=Hold.serialize(h);cargo=Hold.totals(h) end
 r.ship.cargo=cargo;r.salvageCargo={};r.salvageUntil=nil;r.salvageReturn=nil;r.salvageGoal=nil
 total=require('src.accounts').pay(game.universe,node,total,'bought')
 r.credits=(r.credits or 0)+total;r.salvageEarnings=(r.salvageEarnings or 0)+total
 r.salvageSales=r.salvageSales or {}
 for id,n in pairs(sold) do r.salvageSales[id]=(r.salvageSales[id] or 0)+n end
 if total>0 then require('src.events').emit('salvage_sale',r.id,node,sold,total) end
 return total
end
local function pathVia(source,waypoint,target,clock)
 local first=G.live(source,waypoint,clock)
 local second=G.live(waypoint,target,clock)
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
 local Access=require('src.npc_access')
 local u=game.universe
 local target=L.station(r.area,'trade')
 if not target or not Access.canDock(r,target,u) then
  target=nil
  for _,id in ipairs(L.stations(r.area,'trade')) do
   if Access.canDock(r,id,u) then target=id;break end
  end
  local home=Homes.get(r)
  if not target and Access.canDock(r,home,u) then target=home end
 end
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
-- Planet systems with a driver and a trade station post salvage work.
function S.hasWork(area)
 local f=Fields[area]
 return f and not f.instance and not Fields.moons[area] and f.driverId and L.station(area,'trade') and true or false
end
-- Salvage is posted per piece: one listing for each wreck, saved husk or
-- container, or loose cargo lying in a planet system, worth what it holds,
-- withdrawn once it's gone. A hauler plans its trip to a known wreck
-- instead of sweeping buoys on the chance of debris (an always-open board
-- of every station pair sent haulers on thousands of empty runs an hour).
local function itemValue(id,n) local d=data.items[id];return d and (d.price or 0)*n or 0 end
local function holdValue(hold,cargo)
 local v=0
 if hold then local h=Hold.deserialize(hold);for id,n in pairs(Hold.totals(h)) do v=v+itemValue(id,n) end
 else for id,n in pairs(cargo or {}) do v=v+itemValue(id,n) end end
 return v
end
-- the steel a dead ship's hull strips to (src/offline_loot.lua), until stripped
local function hullValue(w)
 if w.stripped or not (w.ship and data.hulls[w.ship.hull]) then return 0 end
 local ok,steel=pcall(function() return require('src.game').wreckSteel(data.hulls[w.ship.hull]) end)
 return ok and itemValue('steel_plate',steel or 0) or 0
end
function S.pieces(u,clock)
 local list={}
 local function add(area,id,value,hull)
 value=value+(hull or 0)
  -- (an emptied wreck or container is no salvage: it was being claimed again
  -- and again after it had been stripped)
  if (value or 0)<=0 then return end
  local f=Fields[area];if not f or f.instance then return end
  local root=Fields.moons[area] and Fields.moons[area].parent or area
  if not S.hasWork(root) then return end
  local target=L.station(area,'trade') or L.station(root,'trade')
  if target then list[#list+1]={area=area,root=root,id=id,target=target,value=value,hullOnly=value==(hull or 0) and (hull or 0)>0} end
 end
 for id,w in pairs(u.alifeWrecks or {}) do
  if clock<w.expires then add(w.area,'w:'..id,holdValue(w.lootHold or w.ship and w.ship.hold,not w.lootHold and w.ship and w.ship.cargo or nil),hullValue(w)) end
 end
 for area,a in pairs(u.areas or {}) do for _,o in ipairs(a.objects or {}) do
  if (o.kind=='husk' or o.kind=='container') and o.hold then add(area,'o:'..tostring(o.id),holdValue(o.hold)) end
 end end
 for id,record in pairs(require('src.loose').records(u)) do
  if record.kind=='loot' and not record.site and (record.count or 0)>0 then add(record.area,'l:'..tostring(id),itemValue(record.item,record.count)) end
 end
 table.sort(list,function(a,b) return a.id<b.id end)
 return list
end
function S.refresh(u,clock)
 local specs={}
 for _,p in ipairs(S.pieces(u,clock)) do
  specs[#specs+1]={kind='salvage',source=p.target,target=p.target,system=p.root,item=p.id,piece=p.id,
   pieceArea=p.area,value=p.value,hullOnly=p.hullOnly or nil,cooldown=30}
 end
 Tasks.sync(u,'salvage',specs,function(o)return o.kind=='salvage' end)
 -- a listing kept from the last refresh takes what its piece is worth now
 local now={} for _,spec in ipairs(specs) do now[spec.piece]=spec end
 for _,o in pairs(Tasks.state(u).offers) do
  local spec=o.kind=='salvage' and o.piece and now[o.piece]
  if spec then o.value,o.hullOnly=spec.value,spec.hullOnly end
 end
end
function S.seed(game) S.refresh(game.universe,game.universe.clock) end
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
 localPickup=true,
 eligible=function(u,r,o,node)
  -- any trade station in the wreck's planet system can send a crew
  if not o.piece then return false end -- (a pre-per-piece listing in an old save)
  -- a stripped hull is only worth it to a crew that can drill it for steel
  if o.hullOnly and not require('src.wreck_salvage').weapon(r.ship) then return false end
  local area=L.get(node).area
  local root=Fields.moons[area] and Fields.moons[area].parent or area
  if o.system~=root or not L.byId[o.target] then return false end
  -- only where there's salvage to collect, and not more crews than pieces:
  -- an always-open board sent haulers on thousands of empty sweeps an hour
  local pieces,crews=require('src.offline_loot').supply(u,o.pieceArea or L.get(o.target).area,u.clock)
  if pieces<=crews*T.salvagePiecesPerCrew then return false end
  local h=r.ship.hold and Hold.deserialize(r.ship.hold)
  if h then return Hold.room(h,'steel_plate',1)>0 end
  local used=0
  for id,n in pairs(r.ship.cargo or {}) do used=used+data.items[id].volume*n end
  return (data.hulls[r.ship.hull].hold or 0)-used>=data.items.steel_plate.volume
 end,
 feasible=function(u,r,o,node,clock) return node==o.target or G.itinerary(node,o.target,clock)~=nil end,
 score=function(u,r,o)
  -- what's in it, less a nominal charge for flying to another body
  local here=r.node and L.byId[r.node] and L.byId[r.node].area
  return (o.value or 0)-(here==o.pieceArea and 0 or T.salvageTripCost)
 end,
 prepare=function(u,r,t,node,clock)
  -- straight to the wreck's area: the crew collects there (src/offline_loot.lua)
  t.route=node==t.target and {node,node} or G.live(node,t.target,clock)
  if not t.route then return false end
  if #t.route==1 then t.route[2]=t.route[1] end
  r.lastSalvageTarget=t.target;t.phase='collecting'
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
return S
