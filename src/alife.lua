-- Persistent station traders and planet/moon itineraries. Records own identity; bodies
-- are temporary representations. Remote travel advances timers, never positions.
local Fields = require('src.fields')
local L = require('src.locations')
local Graph = require('src.travelgraph')
local Ship = require('src.ship')
local Stats = require('src.stats')
local data = require('src.data')
local T = require('src.tuning')
local Hold = require('src.inventory.hold')
local copy = require('src.persistence').copy
local Tasks=require('src.tasks')
local Transport=require('src.transport')
local Security=require('src.security')
local Piracy=require("src.piracy")
local Repairs=require('src.npc_repair')
local Supplies=require('src.supplies')
local Encounters=require('src.encounters')
local Upkeep=require('src.upkeep')
local Fuel=require('src.reactor_fuel')
local Mining=require('src.mining')
local Salvager=require('src.salvager')
local Population=require('src.population')
local Homes=require('src.npc_home')
local Reconcile=require('src.world_reconcile')
local A = {}
local graphs = {}
local function graph(area)
 if not graphs[area] or graphs[area].version~=Fields[area].navigationVersion then graphs[area]=Graph.build(area) end
 return graphs[area]
end
local function edge(r)
 return {from=r.route[(r.index-2)%#r.route+1],to=r.route[r.index]}
end
-- Fuel shifts the leg clock only when the record advances. Between updates,
-- an unpowered ship must not be drawn ahead of where it will be pulled back.
local function legClock(r,clock)
 if (r.fuelStatus=='stranded' or r.fuelStatus=='empty') and r.fuelClock then return math.min(clock,r.fuelClock) end
 return clock
end
A.legClock=legClock
local function progress(r,clock)
 if r.encounter then return r.encounter.progress end
 clock=legClock(r,clock)
 return math.max(0,math.min(1,(clock-r.depart)/math.max(.01,r.arrive-r.depart)))
end
local function start(r,clock,index)
 r.index=index; r.depart=clock
 local leg=edge(r)
 local from,to=L.get(leg.from),L.get(leg.to)
 if from.area~=to.area then
  local lane=Graph.transit(leg.from,leg.to,clock)
  if not lane then
   -- Two nodes in different regions with no direct lane between them (a
   -- one-way route wrapping round to its start, say). Route there properly
   -- through the gates and drivers instead of crashing.
   local path=Graph.itinerary(leg.from,leg.to,clock)
   assert(path and #path>1,'invalid inter-region journey '..tostring(leg.from)..' -> '..tostring(leg.to))
   print(('A-Life: %s rerouted %s -> %s'):format(tostring(r.id),leg.from,leg.to))
   r.route=path;r.onRoundTrip=nil;r.tripRoute=nil
   return start(r,clock,2)
  end
  r.state='transit'; r.area=nil; r.transit=lane
  lane.speed=lane.kind=='driver' and T.laneFlow or r.speed
  r.arrive=clock+lane.length/lane.speed
 else
  r.state='travel'; r.area=to.area; r.transit=nil
  r.arrive=clock+math.max(.1,Graph.length(graph(r.area),leg,clock)/r.speed)
 end
 r.offset,r.pose,r.docking,r.savedOnline=nil,nil,nil,nil
 r.driverState,r.cityExit=nil,nil
end

A.start=start
Upkeep.install({start=start,graph=graph})

local function roundTrip(home,to,clock,homeStation)
 local a,b=homeStation or L.station(home,'trade'),L.station(to,'trade')
 if not a or not b then return end
 local out,back=home..'/to_'..to,to..'/to_'..home
 if not L.byId[out] or not L.byId[back] then return end
 local route={a}
 local function walk(area,from,dest)
  local path=Graph.route(graph(area),from,dest,clock)
  if not path then return false end
  for _,leg in ipairs(path.legs) do route[#route+1]=leg.edge.to end
  return true
 end
 if not walk(home,a,out) then return end
 route[#route+1]=back
 if not walk(to,back,b) or not walk(to,b,back) then return end
 route[#route+1]=out
 if not walk(home,out,a) then return end
 table.remove(route) -- The home station is already the first node of the loop.
 return route
end
A.roundTrip=roundTrip

local function neighbours(area)
 local result={}
 local moon=Fields.moons[area]
 if moon and L.station(moon.parent,'trade') then result[#result+1]=moon.parent end
 for _,id in ipairs(Fields.moonsOf(area)) do
  if L.station(id,'trade') then result[#result+1]=id end
 end
 return result
end

-- Plan the next journey when leaving either trading destination.
local function adoptTrip(r,station,clock,u)
 station=L.canonical(station)
 if r.taskWorker and u then
  if (r.nextTaskAt or 0)>clock then return false end
  Tasks.arrive(u,r,station,clock)
  Supplies.refill(r,station)
  local task=Tasks.choose(u,r,station,clock)
  if not task then r.nextTaskAt=clock+10;return false end
  r.nextTaskAt=nil
  local route=Tasks.plan(r,station,clock)
  if not route then Tasks.release(u,r,'no route',clock);return false end
  r.route=route;r.index=1;r.onRoundTrip=nil;r.tripRoute=nil;r.tripDestination=nil
  return true
 end
 if r.tripDestination and (station==(r.tradeHome or Homes.get(r))
  or station==L.station(r.tripDestination,'trade')) then
  -- Plan at departure: buoys orbit while moon exits stay fixed. Existing saves
  -- pick up the new connections here without moving ships already in flight.
  local route=roundTrip(r.home,r.tripDestination,clock,r.tradeHome or Homes.get(r))
  if not route then return false end
  r.tripRoute=route
  r.route=copy(route); r.onRoundTrip=true
  for i,id in ipairs(route) do if id==station then r.index=i; break end end
  return true
 end
end

function A.createTrader(game,area,i)
 local u,f=game.universe,Fields[area]
 local kinds={'freighter','packhorse_trader','runner_trader'}
 local kind=kinds[(i-1)%#kinds+1]
 local def=data.enemies[kind]; local hull=data.hulls[def.hull]
 u.nextNpcId=u.nextNpcId+1
 local id='npc/'..u.nextNpcId
 local loadout=copy(def.loadout or hull.loadout)
 local stats=Stats.compute(hull,loadout)
 local r={id=id,area=area,home=area,role='trader',archetype=kind,
  route=copy(f.traderRoute),speed=def.ai.cruise or T.traderCruise,
  spread=(love.math.random()*2-1)*T.alifeSpread,
  ship={hull=def.hull,loadout=loadout,cargo=copy(def.cargo or {}),armor=stats.armor}}
 Homes.assign(r,assert(L.station(area,'trade'),'trader region has no trading station'))
 -- Every trader works the dispatch board (transport jobs to other regions,
 -- and Mars's ore runs from Phobos and Deimos). The old fixed local circuit
 -- is only the route it starts docked on.
 r.taskWorker=true
 start(r,u.clock,i%#r.route+1)
 u.npcs[id]=r
 return r
end

function A.seed(game)
 local u=game.universe
 u.npcs=u.npcs or {}; u.npcAreas=u.npcAreas or {}; u.nextNpcId=u.nextNpcId or 0
 Reconcile.prepare(game,start)
 -- All populations exist before visiting their regions. Do not refill departed
 -- or dead traders when an area is loaded.
 for _,area in ipairs(Fields.list) do
  local f=Fields[area]
  if f.alifeTraders and L.station(area,'trade') and not u.npcAreas[area] then
   u.npcAreas[area]=true
   for i=1,f.alifeTraders do
    local r=A.createTrader(game,area,i)
    local elapsed=(r.arrive-r.depart)*i/(f.alifeTraders+1)
    r.depart,r.arrive=r.depart-elapsed,r.arrive-elapsed
    if r.taskWorker then -- start docked, where work is handed out
     r.route=copy(f.traderRoute);r.onRoundTrip=nil;r.tripDestination=nil;r.tripRoute=nil
     local station=L.stations(area,'trade')[(i-1)%#L.stations(area,'trade')+1]
     for index,id in ipairs(r.route) do if id==station then r.index=index;break end end
     r.state='docked';r.untilTime=u.clock+i*2
    end
   end
  end
 end
 -- Saves from the Mars-only job module: those haulers join the task board.
 -- Saves with plain circuit traders: they join the board at their next
 -- docking stop (a round trip under way finishes first).
 for _,r in pairs(u.npcs) do
  if r.role=='trader' and not r.piracy then r.taskWorker=true end
  if r.job then
   if r.job.phase=='delivery' and r.ship.cargo then r.ship.cargo.martian_ore=nil end
   r.job,r.jobStatus,r.onRoundTrip,r.tripDestination,r.tripRoute=nil,nil,nil,nil,nil
  end
 end
 -- Keep records from the preceding Earth prototype; schedule a moon itinerary
 -- at a home docking stop, without teleporting an existing ship.
 local legacy={}
 for _,r in pairs(u.npcs) do
  if not r.home then r.home=r.area; legacy[#legacy+1]=r end
 end
 table.sort(legacy,function(a,b) return a.id<b.id end)
 for i,r in ipairs(legacy) do
  local destinations=neighbours(r.home)
  if i%T.alifeMoonEvery==0 and #destinations>0 then
   r.tripDestination=destinations[(i/T.alifeMoonEvery-1)%#destinations+1]
   r.tripRoute=roundTrip(r.home,r.tripDestination,u.clock)
  end
 end
 if not game.preview then
  Transport.seed(u)
  -- Upgrade one existing local trader per eligible planet, without moving it
  -- or changing its fixed archetype. Work starts at its next docking stop.
  for _,area in ipairs(Fields.list) do
   if area~='mars' and Fields[area].driverId and L.station(area,'trade') then
    local worker
    for _,r in pairs(u.npcs) do
     if r.role=='trader' and r.home==area and not r.onRoundTrip and not r.tripDestination
      and r.state~='dead' and r.state~='escaped' and (not worker or r.id<worker.id) then worker=r end
    end
    if worker then worker.taskWorker=true end
   end
  end
  Security.seed(game,start)
  Mining.seed(game)
  Salvager.seed(game)
  for _,r in pairs(u.npcs) do
   if not r.ship.fuelInitialized then Fuel.withRecord(r,function() end);r.fuelClock=u.clock end
  end
  Homes.seed(u)
  Population.schedule(game,u.clock)
  A.repairMoonRoutes(game)
  A.repairApproachRoutes(game)
 end
end

local function dockingStop(r,id)
 if r.worldRecovery then return id==r.worldRecovery.target end
 if r.service then return Upkeep.isStation(r,id) end
 if r.role=='salvager' then return id==r.salvageGoal end
 if r.piracy then return id==r.route[#r.route] end
 if Security.shouldDock(r,id) then return true end
 if Security.isRole(r) and not r.piracy then return false end
 if L.get(id).kind~='station' then return false end
 id=L.canonical(id)
 if r.taskWorker then return id==(r.task and r.task.target) or not r.task end
 return not r.onRoundTrip or id==(r.tradeHome or Homes.get(r))
  or id==L.station(r.tripDestination,'trade')
end

function A.advance(r,clock,u,game)
 local fuelStatus=Fuel.advance(r,clock,u)
 if fuelStatus=='stranded' and require('src.distress').advance(game,r,clock) then fuelStatus=r.fuelStatus end
 if fuelStatus=='stranded' and Fuel.needsPropulsion(r) then return end
 if r.waitingForHome then return end
 -- Upkeep comes before every role: a due service visit owns the ship.
 if r.state~='dead' and r.state~='escaped' and not r.service then Upkeep.plan(r,clock) end
 if r.service and Upkeep.advance(r,clock,u) then return end
 if r.piracy and not r.worldRecovery then
  local result=Piracy.advance(r,clock,u,start)
  Fuel.observe(u,r,clock);return result
 end
 if game and not r.worldRecovery and require("src.offline_loot").update(game,r,clock) then return end
 if r.role=='salvager' and not r.worldRecovery then
  local result=Salvager.advance(game or {universe=u},r,clock,start)
  Fuel.observe(u,r,clock);return result
 end
 if Mining.isMiner(r) and not r.worldRecovery then
  local result=Mining.advance(game or {universe=u},r,clock)
  Fuel.observe(u,r,clock);return result
 end
 if Security.isRole(r) and not r.worldRecovery then
  local result=Security.advance(r,clock,u,start)
  Fuel.observe(u,r,clock);return result
 end
 if r.encounter then return end
 if r.state=='dead' or r.state=='escaped' then return end
 -- Complete elapsed activities using their event times, not frame steps.
 while true do
  if r.state=='travel' or r.state=='transit' then
   if clock<r.arrive then return end
   local at=r.arrive
   r.offset,r.pose=nil,nil
   if dockingStop(r,r.route[r.index]) then
    r.state='docked';r.node=r.route[r.index];Repairs.begin(r,r.node,at,T.alifeStay)
   else start(r,at,r.index%#r.route+1) end
  elseif r.state=='docked' then
   Repairs.advance(r,clock,r.route[r.index])
   Fuel.observe(u,r,clock)
   if clock<r.untilTime then return end
   if r.worldRecovery then
    Reconcile.resume(u,r,r.untilTime)
    if r.role=='salvager' then
     r.salvageGoal=r.node
     if r.task then r.task.target=r.node end
     return Salvager.advance(game or {universe=u},r,clock,start)
    end
    if r.piracy then return Piracy.advance(r,clock,u,start) end
    if Mining.isMiner(r) then return Mining.advance(game or {universe=u},r,clock) end
    if Security.isRole(r) then return Security.advance(r,clock,u,start) end
   end
   if r.taskWorker and not u then return end
   local adopted=adoptTrip(r,r.route[r.index],r.untilTime,u)
   if r.taskWorker and u and not adopted then r.untilTime=clock+10;return end
   start(r,r.untilTime,r.index%#r.route+1)
  else return end
 end
end

local function journeyPoint(r,p,clock)
 -- A per-ship offset spreads traffic across the corridor without adding nodes.
 -- Keep it in the record so repeated sampling and save/load never reshuffle it.
 if r.spread==nil then r.spread=(love.math.random()*2-1)*T.alifeSpread end
 local x,y=Graph.point(graph(r.area),edge(r),p,clock)
 return Graph.withSpread(x,y,p,r.spread)
end

-- Repair already-saved moon itineraries too. Rebase the same ship's current
-- leg at its existing position rather than retaining a stale driver detour.
function A.repairMoonRoutes(game)
 local function strip(route,index)
  local result,map={},{}
  local changed=false
  for i,id in ipairs(route) do
   if L.get(id).kind~='driver' then result[#result+1]=id; map[i]=#result
   else changed=true end
  end
  if not changed then return route,index,false end
  local nextIndex=index or 1
  while not map[nextIndex] do nextIndex=nextIndex%#route+1 end
  return result,map[nextIndex],true
 end
 for _,r in pairs(game.universe.npcs) do
  if r.state=='transit' and not r.transit.speed then
   local clock=game.universe.clock
   local p=progress(r,clock)
   r.transit.speed=r.speed
   local duration=r.transit.length/r.speed
   r.depart=clock-p*duration; r.arrive=r.depart+duration
  end
  if r.tripRoute and not r.taskWorker then
   r.tripRoute=strip(r.tripRoute)
   if r.onRoundTrip then
    local route,index,changed=strip(r.route,r.index)
    if changed then
     local clock=game.universe.clock
     local x,y
     if r.state=='travel' then
      if r.pose and math.abs(r.pose.clock-clock)<.001 then x,y=r.pose.x,r.pose.y
      else x,y=A.point(r,clock) end
     end
     r.route,r.index=route,index
     if x then
      local duration=math.max(.1,Graph.length(graph(r.area),edge(r),clock)/r.speed)
      local p=math.min(.99,Graph.project(graph(r.area),edge(r),x,y,clock))
      r.depart=clock-p*duration; r.arrive=r.depart+duration
      local bx,by=journeyPoint(r,p,clock)
      r.offset={x=x-bx,y=y-by,progress=p}
     end
    end
   end
  end
 end
end

-- Insert newly authored orbital approaches into existing saved journeys.
-- Keep a travelling ship at its current position while rebasing its next leg.
function A.repairApproachRoutes(game)
 local clock=game.universe.clock
 for _,r in pairs(game.universe.npcs) do
  if r.state~='dead' and r.state~='escaped' and r.route then
   local route,map,first={}, {}, {}
   local changed=false
   for i,to in ipairs(r.route) do
    local from=r.route[(i-2)%#r.route+1]
    local a,b=L.get(from),L.get(to)
    first[i]=#route+1
    if a.area==b.area and Fields[a.area].buoyCorridor
     and (a.kind=='station' or b.kind=='station')
     and a.kind~='buoy' and b.kind~='buoy' then
     local path=Graph.route(graph(a.area),from,to,clock)
     if path then
      for j=1,#path.legs-1 do route[#route+1]=path.legs[j].edge.to;changed=true end
     end
    end
    route[#route+1]=to;map[i]=#route
   end
   if changed then
    local x,y
    if r.state=='travel' then
     if r.pose then x,y=r.pose.x,r.pose.y else x,y=A.point(r,clock) end
    end
    local index=r.state=='travel' and first[r.index] or map[r.index]
    r.route,r.index=route,index
    if x then
     local duration=math.max(.1,Graph.length(graph(r.area),edge(r),clock)/r.speed)
     local p=math.min(.99,Graph.project(graph(r.area),edge(r),x,y,clock))
     r.depart=clock-p*duration;r.arrive=r.depart+duration
     local bx,by=journeyPoint(r,p,clock)
     r.offset={x=x-bx,y=y-by,progress=p}
    end
   end
  end
 end
end

function A.point(r,clock)
 if r.offlineLoot then local x,y=require("src.offline_loot").position(r,clock);if x then return x,y end end
 if Mining.isMiner(r) and not (r.worldRecovery or r.waitingForHome) then return Mining.point(nil,r,clock) end
 if r.state=='transit' then return nil end
 if r.state=='docked' then return L.position(r.route[r.index],clock) end
 if r.state=='idle' then
  local x,y=L.inspectionPosition(r.route[r.index],clock)
  return x+(r.offset and r.offset.x or 0),y+(r.offset and r.offset.y or 0)
 end
 local p=progress(r,clock)
 local x,y=journeyPoint(r,p,clock)
 if r.offset then
  local fade=(1-p)/math.max(.001,1-r.offset.progress)
  x,y=x+r.offset.x*fade,y+r.offset.y*fade
 end
 return x,y
end
function A.sample(r,clock)
 local x,y=A.point(r,clock)
 local xx,yy=A.point(r,clock+.02)
 local vx,vy=(xx-x)/.02,(yy-y)/.02
 return {x=x,y=y,vx=vx,vy=vy,heading=math.atan2(vy,vx)}
end

function A.laneDirection(game,r)
 if not game.lane or not game.trip or r.state~='transit' then return end
 local trip,t=game.trip,r.transit
 if t.from==trip.from and t.to==trip.to then return 1 end
 if t.from==trip.to and t.to==trip.from then return -1 end
end
function A.egressSample(game,r,clock)
 local entry=r.state=='transit' and r.transit.departure
 if not entry or game.lane or game.flight or entry.area~=game.fieldId then return end
 local elapsed=math.max(0,clock-entry.clock)
 return {x=entry.x+entry.vx*elapsed,y=entry.y+entry.vy*elapsed,
  vx=entry.vx,vy=entry.vy,heading=math.atan2(entry.vy,entry.vx)}
end
function A.laneSample(game,r,clock)
 local dir=A.laneDirection(game,r)
 if not dir then return end
 local speed=r.transit.speed or r.speed
 clock=legClock(r,clock)
 local fraction=math.min(1,(clock-r.depart)/math.max(.01,r.arrive-r.depart))
 local along=(-game.lane.half+fraction*game.trip.length)*dir
 local n=(r.laneOffset or -math.min(T.laneWidth*.65,math.max(T.laneMedian+200,500+math.abs(r.spread or 0))))*dir
 local entry=r.transit.departure
 local anchor=entry and dir==1 and game.trip.origin and game.trip.originScene
  and game.trip.originScene.fieldId==entry.area
 if anchor then
  local s0,n0=game:toLane(entry.x+game.trip.origin.x,entry.y+game.trip.origin.y)
  -- Headway since entry, excluding time the leg clock was held for lack of power.
  along=s0+math.max(0,clock-r.depart-(entry.distance or 0)/speed)*speed
  n=n0
 end
 local x,y=game:fromLane(along,n)
 local a=game:laneHeading(along)+(dir==-1 and math.pi or 0)
 return {x=x,y=y,vx=anchor and entry.vx or math.cos(a)*speed,
  vy=anchor and entry.vy or math.sin(a)*speed,heading=a,n=n,dir=dir,speed=speed,along=along,anchor=anchor}
end

local function shipRecord(e)
 local s=Ship.record(e)
 return {hull=s.hull,loadout=copy(s.loadout),armor=s.armor,color=copy(s.color),
  fuelCharge=s.fuelCharge,fuelInitialized=s.fuelInitialized,
  cargo=copy(s.cargo or e.cargo or {}),hold=s.hold and Hold.serialize(s.hold)}
end
-- End ownership before destroying a body; drawing can run before the next tick.
-- A nil reason only unloads the representation, preserving its live record.
function A.detach(game,e,reason)
 local id=e.alifeId
 if not id then return end
 if game.alifeOnline and game.alifeOnline[id] and game.alifeOnline[id]~=e then return end
 local r=game.universe.npcs and game.universe.npcs[id]
 if r and reason then
  r.state=reason
  Tasks.release(game.universe,r,reason,game.universe.clock)
 end
 if game.alifeOnline and game.alifeOnline[id]==e then game.alifeOnline[id]=nil end
end

function A.capture(game,e,remote)
 local r=game.universe.npcs and game.universe.npcs[e.alifeId]
 if not r then return end
 if e.dead then r.state='dead'; return end
 if e.removed or not e.body or e.body:isDestroyed() then r.state='escaped'; return end
 local clock=game.universe.clock
 r.savedOnline=nil
 local controlled=e.launch or e.driverTractor
 r.driverState=controlled and {phase=e.launch and 'launch' or 'tractor',
  driver=controlled.driver.locationId,to=controlled.to,t=controlled.t,
  ghost=controlled.ghost,angle=controlled.driver.angle} or nil
 r.cityExit=nil
 if e.dockExit and not remote then
  local exit=e.dockExit;local index=1
  for i,dock in ipairs(exit.station.docks or {exit.station.dock}) do if dock==exit.dock then index=i;break end end
  r.cityExit={station=exit.station.locationId,dock=index,side=exit.side,t=exit.t}
 end
 r.ship=shipRecord(e); r.power=e.power;r.fuelClock=clock
 Fuel.observe(game.universe,r,clock,e)
 if r.waitingForHome then
  r.state='idle';r.node=r.route[r.index]
  local x,y=e.body:getPosition();local vx,vy=e.body:getLinearVelocity()
  r.pose=not remote and {x=x,y=y,a=e.body:getAngle(),vx=vx,vy=vy,w=e.body:getAngularVelocity(),clock=clock} or nil
  return
 end
 if Mining.isMiner(r) and not (r.worldRecovery or r.waitingForHome) then return Mining.capture(game,e,r,remote) end
 if Security.isRole(r) and not r.piracy and not r.worldRecovery and not Security.shouldDock(r,r.route[r.index]) then return Security.capture(game,e,r,remote) end
 if e.alifeEgress then
  local x,y=e.body:getPosition(); local vx,vy=e.body:getLinearVelocity()
  local previous=r.transit.departure
  local distance=previous and (previous.distance or 0)+math.sqrt((x-previous.x)^2+(y-previous.y)^2) or 0
  r.transit.speed=math.max(50,math.sqrt(vx*vx+vy*vy))
  r.depart=clock-distance/r.transit.speed
  r.arrive=r.depart+r.transit.length/r.transit.speed
  r.transit.departure={x=x,y=y,vx=vx,vy=vy,clock=clock,area=game.fieldId,distance=distance,
   flightHeading=e.egressHeading,cruiseSpeed=e.egressSpeed}
  r.pose,r.offset,r.docking,r.savedOnline=nil,nil,nil,nil
  return
 end
 if e.alifeLane then
  local along,n=game:toLane(e.body:getPosition())
  local p=math.min(.999,((along*e.cruiseDir)+game.lane.half)/game.trip.length)
  local vx,vy=e.body:getLinearVelocity()
  r.transit.speed=math.max(50,math.sqrt(vx*vx+vy*vy))
  r.transit.departure=nil
  local duration=game.trip.length/r.transit.speed
  r.depart=clock-p*duration; r.arrive=r.depart+duration
  r.laneOffset=n*e.cruiseDir
  r.pose,r.offset,r.docking,r.savedOnline=nil,nil,nil,nil
  if not remote then
   local x,y=e.body:getPosition(); local vx,vy=e.body:getLinearVelocity()
   r.pose={x=x,y=y,a=e.body:getAngle(),vx=vx,vy=vy,w=e.body:getAngularVelocity(),clock=clock,
    lane=game.trip.from..'/'..game.trip.to..'/'..tostring(game.trip.rot)}
  end
  return
 end
 r.index=e.routeIndex or r.index
 r.docking=nil
 local ds=e.dockState
 if ds then
  local index
  for i,id in ipairs(r.route) do if id==ds.station.locationId then index=i; break end end
  r.index=assert(index,'trader docked outside its itinerary')
  r.state='docked'
  if r.role=='patrol' then r.node=ds.station.locationId end
  r.untilTime=clock+(ds.done and math.max(0,(ds.stay or T.alifeStay)-ds.t) or T.alifeStay)
  -- Preserve an in-progress physical docking operation for immediate save/load.
  r.docking={}
  for k,v in pairs(ds) do if type(v)~='table' and type(v)~='userdata' then r.docking[k]=v end end
  r.docking.mooring=copy(ds.mooring)
 else
  r.state='travel'
  local x,y=e.body:getPosition()
  -- The ship is flying on this map; a record bound here from between regions
  -- can still carry another region's area, so measure the leg on a graph
  -- that actually holds both of its nodes.
  local leg=edge(r)
  local g=e.travelGraph or graph(r.area or game.fieldId)
  if not (g.nodes[leg.from] and g.nodes[leg.to]) then g=graph(game.fieldId) end
  if g.nodes[leg.from] and g.nodes[leg.to] then r.area=g.area end
  local duration,p
  local known=g.nodes[leg.from] and g.nodes[leg.to]
  if known[leg.from] and g.nodes[leg.to] then
   duration=math.max(.1,Graph.length(g,leg,clock)/r.speed)
   p=Graph.project(g,leg,x,y,clock)
  else
   -- No local graph holds this leg (a stale cross-region route); hand it
   -- back nearly finished so the offline model takes over the next leg.
   duration,p=1,.99
  end
  -- Never advance a destination merely because an online ship is close to it;
  -- actual AI/docking changes routeIndex. Leave a little time for handoff.
  p=math.min(.99,p)
  if r.encounter then r.encounter.progress=p end
  r.depart=clock-p*duration; r.arrive=r.depart+duration
  if not remote and known then
   local bx,by=journeyPoint(r,p,clock)
   r.offset={x=x-bx,y=y-by,progress=p}
  end
 end
 r.pose=nil
 if not remote then
  local x,y=e.body:getPosition(); local vx,vy=e.body:getLinearVelocity()
  r.pose={x=x,y=y,a=e.body:getAngle(),vx=vx,vy=vy,w=e.body:getAngularVelocity(),clock=clock}
 else r.offset,r.docking=nil,nil end
end

local function bindRoute(game,e,r)
 if Mining.isMiner(r) and not (r.worldRecovery or r.waitingForHome or r.service) then return Mining.bind(game,e,r) end
 e.routeIndex=r.index; e.route={}
 e.travelGraph=graph(r.area or game.fieldId)   -- a record between regions flies out on this map
 e.taskWorker=r.taskWorker or r.worldRecovery~=nil
 for _,id in ipairs(r.route) do
  local place=L.get(id)
  -- a station with several access points: the one nearest the ship now
  local stop=place.area==game.fieldId and game:locationEntity(id,e.body:getPosition())
  if stop and place.kind=='station' and not dockingStop(r,id) then
   local station=stop
   stop={kind='waypoint',locationId=id,removed=false,inspection=station.city,body={getPosition=function()
    return Security.inspectionPoint(game,station,e)
   end,getLinearVelocityFromWorldPoint=function(_,x,y)
    local _,_,vx,vy=Security.inspectionPoint(game,station,e);return vx,vy
   end}}
  end
  if stop and place.kind=='driver' then
   local driver=stop
   stop={kind='driver',locationId=id,driver=driver,removed=false,body={getPosition=function() return game:driverBreech(driver) end}}
  end
  if not stop then
   stop={kind=place.kind,locationId=id,removed=false,body={getPosition=function() return L.position(id,game.universe.clock) end,
    getLinearVelocityFromWorldPoint=function() return L.velocity(id,game.universe.clock) end}}
   if place.area==game.fieldId and place.kind=='moon_gate' then
    stop.body={getPosition=function()
     local x,y=L.position(id,game.universe.clock)
     local radius=math.sqrt(x*x+y*y)
     local factor=1+T.alifeGateExit/radius
     return x*factor,y*factor
    end}
   end
  end
  if place.kind=="driver" then
   for i,node in ipairs(r.route) do if node==id and r.route[i+1] then stop.destination=L.get(r.route[i+1]).area;break end end
  end
  if r.waitingForHome then stop.hold=true;stop.inspection=true end
  e.route[#e.route+1]=stop
 end
end

A.bindRoute=bindRoute

function A.wake(game,r)
 Fuel.withRecord(r,function() end);r.fuelClock=game.universe.clock
 require("src.offline_loot").release(game,r,game.universe.clock)
 local s=r.ship
 local lane=A.laneSample(game,r,game.universe.clock)
 local egress=A.egressSample(game,r,game.universe.clock)
 local p=egress or lane or A.sample(r,game.universe.clock)
 local exact=r.pose and math.abs(r.pose.clock-game.universe.clock)<.001 and r.pose
 if exact and lane and exact.lane~=game.trip.from..'/'..game.trip.to..'/'..tostring(game.trip.rot) then exact=nil end
 local e=Ship.new(game,{hull=s.hull,loadout=s.loadout,cargo=s.cargo,
  hold=s.hold and Hold.deserialize(s.hold,function(id) return data.items[id]~=nil end),
  fuelCharge=s.fuelCharge,fuelInitialized=s.fuelInitialized,power=r.power,
  armor=s.armor,color=copy(s.color),team=data.enemies[r.archetype].team,
  enemy=data.enemies[r.archetype],x=exact and exact.x or p.x,y=exact and exact.y or p.y,
  angle=exact and exact.a or p.heading})
 e.alifeId=r.id
 Fuel.observe(game.universe,r,game.universe.clock,e)
 e.alifeRole=Security.isRole(r) and r.role or nil
 e.npcRole=r.role
 e.alifeRecord=r;e.alifeGame=game
 e.fleeing=r.fleeing
 if egress then
  e.driverProtected=r.transit.kind=='driver' or nil
  e.coasting=e.driverProtected or nil
  e.alifeEgress=true; e.intent=Ship.emptyIntent()
  local entry=r.transit.departure
  e.egressHeading=entry.flightHeading or math.atan2(entry.y,entry.x)
  e.egressSpeed=math.max(entry.cruiseSpeed or r.transit.speed,r.speed*.6)
 elseif lane then
  e.alifeLane=true; e.cruise=true; e.cruiseDir=lane.dir; e.cruiseOffset=lane.n
  e.cruiseSpeed=lane.speed/T.laneFlow
  if lane.anchor then
   r.depart=game.universe.clock-(lane.along*lane.dir+game.lane.half)/lane.speed
   r.arrive=r.depart+game.trip.length/lane.speed
   r.laneOffset=lane.n*lane.dir
   r.transit.departure=nil
  end
 else
  bindRoute(game,e,r)
  if exact and r.cityExit then
   local exit=r.cityExit;local station=game:locationEntity(exit.station)
   if station and station.city then
    local dock=(station.docks or {station.dock})[exit.dock]
    if dock then e.dockExit={station=station,dock=dock,side=exit.side,t=exit.t} end
   end
  end
  if exact and r.driverState then
   local state=r.driverState
   local g=game:locationEntity(state.driver)
   if g and not g.driverShip then
    local control={driver=g,to=state.to,t=state.t,ghost=state.ghost}
    if state.phase=='launch' then e.launch=control else e.driverTractor=control end
    g.driverShip=e;g.angle=state.angle;e.driverProtected=true
    if state.ghost then e.coasting=true;for _,f in ipairs(e.body:getFixtures()) do f:setSensor(true) end end
   end
  end
 end
 e.power=r.power or e.power
 e.body:setLinearVelocity(exact and exact.vx or p.vx,exact and exact.vy or p.vy)
 e.body:setAngularVelocity(exact and exact.w or 0)
 table.insert(game.entities,e)
 if r.state=='docked' then
  local st=game:locationEntity(r.route[r.index],p.x,p.y)
  if st and st.kind=='station' and st.def then game:dockInstantly(e,st,r.docking)
  else
   -- docked at something that isn't a dockable station here (e.g. an
   -- access point resolved to another entity): leave it in open space
   require('src.alife_trace').note(r,game.universe.clock,'wake','docked record at '..tostring(r.route[r.index])..' has no station entity here')
  end
  if e.dockState then
   e.dockState.stay=math.max(0,r.untilTime-game.universe.clock)
   if exact and r.docking and r.docking.berth==e.dockState.berth then
    local dock=e.dockState.dock
    e.dockState=copy(r.docking); e.dockState.station=st;e.dockState.dock=dock
    e.body:setPosition(exact.x,exact.y); e.body:setAngle(exact.a)
    e.body:setActive(e.dockState.phase=='tractor')
   end
  end
 end
 if not exact and not lane and r.state=='travel' then
  -- Local graph nodes name the station as a whole. Physical handoff uses
  -- the existing dock/undock transforms rather than spawning inside its hub.
  local leg=edge(r)
  local source=game:locationEntity(leg.from,p.x,p.y)
  local destination=game:locationEntity(leg.to,p.x,p.y)
  local function close(st)
   if not st or st.kind~='station' then return false end
   local x,y=st.body:getPosition()
   return (p.x-x)^2+(p.y-y)^2<((st.radius or st.def.radius or 1000)+e.halfLength)^2
  end
  if close(source) and dockingStop(r,leg.from) then
   e.routeIndex=(r.index-2)%#r.route+1
   game:dockInstantly(e,source)
   game:undockShip(e)
  elseif close(destination) and dockingStop(r,leg.to) then
   local x,y=require('src.ai').stopPoint(destination,e)
   e.body:setPosition(x,y)
   e.body:setAngle(game.dockAngle(destination,1)+math.pi)
   e.body:setLinearVelocity(destination.body:getLinearVelocityFromWorldPoint(x,y))
   game:beginDocking(e,destination,1)
  elseif close(source) or close(destination) then
   -- A pass-through station is not a dock. Materialize at its approach rather
   -- than inside its hull when the coarse leg ends at the station centre.
   local station=close(destination) and destination or source
   if station.city then e.body:setPosition(L.inspectionPosition(station.locationId,game.universe.clock))
   else e.body:setPosition(require('src.ai').stopPoint(station,e)) end
  end
 end

 game.alifeOnline[r.id]=e
 if r.warpUntil and game.universe.clock<r.warpUntil then
  local x,y=e.body:getPosition()
  game:addEffect({kind='warp_in',x=x,y=y,r=e.halfLength*2+60,
   t=game.universe.clock-r.spawnedAt,life=r.warpUntil-r.spawnedAt})
 end
 r.pose,r.savedOnline=nil,nil
 return e
end

-- Dead and escaped records stay only while something still points at them
-- (a live fight, a target, a task they own), plus a short linger for
-- history and debug views; then they are dropped so the universe stops growing.
function A.pruneGone(u,clock,online)
 local referenced={}
 for _,r in pairs(u.npcs or {}) do
  if r.state~='dead' and r.state~='escaped' then
   if r.encounter and r.encounter.target then referenced[r.encounter.target]=true end
   if r.targetId then referenced[r.targetId]=true end
  end
 end
 for _,o in pairs(u.tasks and u.tasks.offers or {}) do if o.owner then referenced[o.owner]=true end end
 for id,r in pairs(u.npcs or {}) do
  if (r.state=='dead' or r.state=='escaped') and not (online and online[id]) and not referenced[id] then
   r.goneAt=r.goneAt or clock
   if clock-r.goneAt>=T.alifeGoneLinger then u.npcs[id]=nil end
  end
 end
end

function A.install(Game)
 function Game:traderCanDepart(e,station)
  local serviced=self.universe.npcs[e.alifeId]
  if serviced and serviced.service and Upkeep.isStation(serviced,station.locationId) then
   if not Upkeep.canDepart(self,e,serviced) then return false end
   e.serviceDeparture=true;return true
  end
  local salvager=self.universe.npcs[e.alifeId]
  if salvager and salvager.role=='salvager' then
   A.capture(self,e,false)
   if salvager.worldRecovery then
    Reconcile.resume(self.universe,salvager,self.universe.clock)
    salvager.salvageGoal=station.locationId
    if salvager.task then salvager.task.target=station.locationId end
   end
   local ok=Salvager.depart(self,salvager,station.locationId,self.universe.clock)
   e.cargo=copy(salvager.ship.cargo);Ship.updateMass(e)
   if ok then e.salvagerDeparture=true end
   return ok
  end
  local recovering=self.universe.npcs[e.alifeId]
  local patrolRecovery=recovering.worldRecovery and recovering.role=='patrol'
  if recovering.worldRecovery then
   A.capture(self,e,false)
   Reconcile.resume(self.universe,recovering,self.universe.clock)
   if recovering.role=='trader' or recovering.role=='courier' then e.worldDeparture=true end
  end
  if Mining.isMiner(self.universe.npcs[e.alifeId]) then return Mining.depart(self,e,station) end
  local r=self.universe.npcs[e.alifeId]
  if Security.shouldDock(r,station.locationId) or patrolRecovery then
   A.capture(self,e,false)
   Security.advance(r,self.universe.clock,self.universe,start)
   if r.state~='travel' then return false end
   e.patrolDeparture=true;return true
  end
  if r and r.piracy then
   A.capture(self,e,false)
   if not Piracy.depart(self.universe,r,self.universe.clock,start) then return false end
   e.cargo=copy(r.ship.cargo);if e.hold then Hold.sync(e.hold,e.cargo) end;Ship.updateMass(e)
   e.pirateDeparture=true;return true
  end
  if not r or not r.taskWorker then return true end
  A.capture(self,e,false)
  local ok=adoptTrip(r,station.locationId,self.universe.clock,self.universe)
  -- Delivery may have unloaded cargo even when no next job is available.
  e.cargo=copy(r.ship.cargo);Ship.updateMass(e)
  if not ok then return false end
  e.jobPrepared=true
  return true
 end
 function Game:traderUndocked(e,station)
  if e.serviceDeparture then
   e.serviceDeparture,e.serviceDockedAt=nil,nil
   local r=self.universe.npcs[e.alifeId];A.capture(self,e,false)
   if r.index>=#r.route then Upkeep.passed(r,#r.route) end
   start(r,self.universe.clock,r.index%#r.route+1);bindRoute(self,e,r);return
  end
  if e.salvagerDeparture then
   e.salvagerDeparture=nil
   local r=self.universe.npcs[e.alifeId];start(r,self.universe.clock,2);bindRoute(self,e,r);return
  end
  local salvager=self.universe.npcs[e.alifeId]
  if salvager and salvager.role=='salvager' then bindRoute(self,e,salvager);return end
  if Mining.isMiner(self.universe.npcs[e.alifeId]) then return Mining.bind(self,e,self.universe.npcs[e.alifeId]) end
  local r=self.universe.npcs[e.alifeId]
  if e.patrolDeparture then e.patrolDeparture=nil;bindRoute(self,e,r);return end
  if e.pirateDeparture then e.pirateDeparture=nil;bindRoute(self,e,r);return end
  if e.worldDeparture then
   e.worldDeparture,e.jobPrepared=nil,nil
   start(r,self.universe.clock,r.index%#r.route+1);bindRoute(self,e,r);return
  end
  if e.jobPrepared or adoptTrip(r,station.locationId,self.universe.clock,self.universe) then
   e.jobPrepared=nil
   start(r,self.universe.clock,r.index%#r.route+1)
   bindRoute(self,e,r)
  end
 end
 function Game:captureALife(detach)
  for id,e in pairs(self.alifeOnline or {}) do
   A.capture(self,e,detach)
   local r=self.universe.npcs and self.universe.npcs[id]
   if not detach and r then r.savedOnline=true end
   if detach then
    if not e.removed then self:remove(e,true) end
    self.alifeOnline[id]=nil
   end
  end
  if detach and self.alifeActiveArea==self.fieldId then
   for _,r in pairs(self.universe.npcs or {}) do
    if r.area==self.fieldId then r.pose,r.offset,r.docking,r.savedOnline=nil,nil,nil,nil end
   end
   self.alifeActiveArea=nil
  end
 end
 function Game:updateALife(force)
  if self.preview then return end
  self.alifeActiveArea=self.fieldId
  self.alifeOnline=self.alifeOnline or {}
  local clock=self.universe.clock
  if not force and clock<(self.alifeNext or 0) then return end
  self.alifeNext=clock+T.alifeLocalTick
  Mining.update(self)
  Population.update(self,clock)
  local records=self.universe.npcs or {}
  Tasks.clean(self.universe,clock)
  A.pruneGone(self.universe,clock,self.alifeOnline)
  local px,py
  if self.player and not self.player.dead then px,py=self.player.body:getPosition() end
  for id,e in pairs(self.alifeOnline) do
   local x,y
   if not e.removed and e.body and not e.body:isDestroyed() then x,y=e.body:getPosition()
   else e.removed=true end
   if e.dead then
    -- Normal reap must still produce the wreck and death effects.
    A.capture(self,e,false)
    self.alifeOnline[id]=nil
   elseif e.removed then
    A.capture(self,e,false)
    self:remove(e,true)
    self.alifeOnline[id]=nil
   elseif e.alifeLane and select(1,self:toLane(e.body:getPosition()))*e.cruiseDir>=self.lane.half then
    A.capture(self,e,true)
    local r=records[id]
    start(r,clock,r.index%#r.route+1)
    self:remove(e,true); self.alifeOnline[id]=nil
   elseif e.alifeDepart then
    local vx,vy=e.body:getLinearVelocity()
    A.capture(self,e,true)
    local r=records[id]
    start(r,clock,r.index%#r.route+1)
    if not r.transit then
     -- the record's next leg isn't the crossing the ship reached (its
     -- itinerary changed under it): hand it to the record, which has
     -- already started that leg
     self:remove(e,true);self.alifeOnline[id]=nil
    else
    r.transit.speed=r.transit.kind=='driver' and T.laneFlow or math.max(50,math.sqrt(vx*vx+vy*vy))
    r.arrive=clock+r.transit.length/r.transit.speed
    e.alifeDepart=nil; e.alifeEgress=true; e.route=nil
    e.egressHeading=e.driverProtected and math.atan2(vy,vx) or math.atan2(y,x); e.egressSpeed=math.max(r.transit.speed,r.speed*.6)
    e.intent=Ship.emptyIntent()
    A.capture(self,e,true)
    end
   elseif not e.driverTractor and not e.launch and (not px or (x-px)^2+(y-py)^2>T.alifeFar^2) then
    A.capture(self,e,false)
    if not e.removed then self:remove(e,true) end
    self.alifeOnline[id]=nil
   end
  end
  for id,r in pairs(records) do
   if not self.alifeOnline[id] then
    local localArea=r.area==self.fieldId and not self.lane and not self.flight
    if localArea or A.laneDirection(self,r) or force or clock>=(self.alifeRemoteNext or 0) then A.advance(r,clock,self.universe,self) end
    local lane=A.laneSample(self,r,clock)
    local egress=A.egressSample(self,r,clock)
    localArea=r.area==self.fieldId and not self.lane and not self.flight
    if px and (egress or lane or localArea and r.state~='dead' and r.state~='escaped' and r.state~='transit') then
     local x,y
     if egress then x,y=egress.x,egress.y elseif lane then x,y=lane.x,lane.y else x,y=A.point(r,clock) end
     local threshold=r.savedOnline and r.pose and math.abs(r.pose.clock-clock)<.001 and T.alifeFar or T.alifeNear
     if (x-px)^2+(y-py)^2<threshold^2 then A.wake(self,r) end
    end
   end
  end
  Encounters.syncOnline(self)
  Encounters.update(self,clock)
  Encounters.materialize(self,px,py,clock)
  require("src.simulation_history").update(self)
  if clock>=(self.alifeRemoteNext or 0) then self.alifeRemoteNext=clock+T.alifeRemoteTick end
 end
end
Population.register('trader',{
 target=function(f,area) return L.station(area,'trade') and f.alifeTraders end,
 nodes=function(game,area)
  local f=Fields[area]
  return #f.buoyIds>0 and f.buoyIds or f.stationIds
 end,
 create=function(game,area,node,clock)
  local u=game.universe
  local r=A.createTrader(game,area,u.nextNpcId+1)
  -- Keep one dispatch worker available when its previous ship was lost.
  if area~='mars' and Fields[area].driverId then
   local dispatch=false
   for _,other in pairs(u.npcs) do
    if other~=r and other.home==area and other.taskWorker and other.state~='dead' and other.state~='escaped' then dispatch=true;break end
   end
   if not dispatch then
    r.taskWorker=true;r.onRoundTrip,r.tripDestination,r.tripRoute=nil,nil,nil
    r.route=copy(Fields[area].traderRoute);start(r,clock,1)
   end
  end
  return r
 end,
})
return A
