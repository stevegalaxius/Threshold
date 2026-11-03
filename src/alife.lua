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
local Encounters=require('src.encounters')
local A = {}
local graphs = {}
local function graph(area)
 if not graphs[area] then graphs[area]=Graph.build(area) end
 return graphs[area]
end
local function edge(r)
 return {from=r.route[(r.index-2)%#r.route+1],to=r.route[r.index]}
end
local function progress(r,clock)
 if r.encounter then return r.encounter.progress end
 return math.max(0,math.min(1,(clock-r.depart)/math.max(.01,r.arrive-r.depart)))
end
local function start(r,clock,index)
 r.index=index; r.depart=clock
 local leg=edge(r)
 local from,to=L.get(leg.from),L.get(leg.to)
 if from.area~=to.area then
  local lane=assert(Graph.transit(leg.from,leg.to,clock),'invalid inter-region journey')
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

local function roundTrip(home,to,clock,homeStation)
 local a,b=homeStation or Fields[home].stationIds[1],Fields[to].stationIds[1]
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
 if moon and Fields[moon.parent].stationIds[1] then result[#result+1]=moon.parent end
 for _,id in ipairs(Fields.moonsOf(area)) do
  if Fields[id].stationIds[1] then result[#result+1]=id end
 end
 return result
end

-- Plan the next journey when leaving either trading destination.
local function adoptTrip(r,station,clock,u)
 station=L.canonical(station)
 if r.taskWorker and u then
  if (r.nextTaskAt or 0)>clock then return false end
  Tasks.arrive(u,r,station,clock)
  local task=Tasks.choose(u,r,station,clock)
  if not task then r.nextTaskAt=clock+10;return false end
  r.nextTaskAt=nil
  local route=Tasks.plan(r,station,clock)
  if not route then Tasks.release(u,r,'no route',clock);return false end
  r.route=route;r.index=1;r.onRoundTrip=nil;r.tripRoute=nil;r.tripDestination=nil
  return true
 end
 if r.home=='mars' and u then
  if not require('src.jobs').depart(u,r,station,clock) then return false end
 end
 if r.tripDestination and (station==(r.tradeHome or Fields[r.home].stationIds[1])
  or station==Fields[r.tripDestination].stationIds[1]) then
  -- Plan at departure: buoys orbit while moon exits stay fixed. Existing saves
  -- pick up the new connections here without moving ships already in flight.
  local route=roundTrip(r.home,r.tripDestination,clock,r.tradeHome)
  if not route then return false end
  r.tripRoute=route
  r.route=copy(route); r.onRoundTrip=true
  for i,id in ipairs(route) do if id==station then r.index=i; break end end
  return true
 end
end

function A.seed(game)
 local u=game.universe
 u.npcs=u.npcs or {}; u.npcAreas=u.npcAreas or {}; u.nextNpcId=u.nextNpcId or 0
 local kinds={'freighter','packhorse_trader','runner_trader'}
 -- All populations exist before visiting their regions. Do not refill departed
 -- or dead traders when an area is loaded.
 for _,area in ipairs(Fields.list) do
  local f=Fields[area]
  if f.alifeTraders and not u.npcAreas[area] then
   u.npcAreas[area]=true
   for i=1,f.alifeTraders do
    local kind=kinds[(i-1)%#kinds+1]
    local def=data.enemies[kind]; local hull=data.hulls[def.hull]
    u.nextNpcId=u.nextNpcId+1
    local id='npc/'..u.nextNpcId
    local loadout=copy(def.loadout or hull.loadout)
    local stats=Stats.compute(hull,loadout)
    local r={id=id,area=area,home=area,role='trader',archetype=kind,
     route=copy(f.traderRoute),speed=def.ai.cruise or T.traderCruise,
     spread=(love.math.random()*2-1)*T.alifeSpread,
     ship={hull=def.hull,loadout=loadout,cargo=copy(def.cargo or hull.cargo),armor=stats.armor,color=copy(def.color)}}
    local destinations=neighbours(area)
    if i%T.alifeMoonEvery==0 and #destinations>0 then
     r.tripDestination=destinations[(i/T.alifeMoonEvery-1)%#destinations+1]
     r.tripRoute=roundTrip(area,r.tripDestination,u.clock)
     if r.tripRoute then r.route=copy(r.tripRoute); r.onRoundTrip=true end
    end
    start(r,u.clock,r.onRoundTrip and 2 or i%#r.route+1)
    local elapsed=(r.arrive-r.depart)*i/(f.alifeTraders+1)
    r.depart,r.arrive=r.depart-elapsed,r.arrive-elapsed
    if area=='mars' then
     r.route=copy(f.traderRoute);r.onRoundTrip=nil;r.tripDestination=nil;r.tripRoute=nil
     r.index=i%2==0 and 3 or 1;r.state='docked';r.untilTime=u.clock+i*2
    end
    u.npcs[id]=r
   end
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
   if area~='mars' and Fields[area].driverId and Fields[area].stationIds[1] then
    local worker
    for _,r in pairs(u.npcs) do
     if r.role=='trader' and r.home==area and not r.onRoundTrip and not r.tripDestination
      and r.state~='dead' and r.state~='escaped' and (not worker or r.id<worker.id) then worker=r end
    end
    if worker then worker.taskWorker=true end
   end
  end
  Security.seed(game,start)
  A.repairMoonRoutes(game)
  A.repairApproachRoutes(game)
 end
end

local function dockingStop(r,id)
 if Security.isRole(r) then return false end
 if L.get(id).kind~='station' then return false end
 id=L.canonical(id)
 if r.taskWorker then return id==(r.task and r.task.target) or not r.task end
 return not r.onRoundTrip or id==(r.tradeHome or Fields[r.home].stationIds[1])
  or id==Fields[r.tripDestination].stationIds[1]
end

function A.advance(r,clock,u)
 if Security.isRole(r) then return Security.advance(r,clock,u,start) end
 if r.encounter then return end
 if r.state=='dead' or r.state=='escaped' then return end
 -- Complete elapsed activities using their event times, not frame steps.
 while true do
  if r.state=='travel' or r.state=='transit' then
   if clock<r.arrive then return end
   local at=r.arrive
   r.offset,r.pose=nil,nil
   if dockingStop(r,r.route[r.index]) then
    r.state='docked'; r.untilTime=at+T.alifeStay
   else start(r,at,r.index%#r.route+1) end
  elseif r.state=='docked' then
   if clock<r.untilTime then return end
   if r.taskWorker and not u then return end
   local adopted=adoptTrip(r,r.route[r.index],r.untilTime,u)
   if (r.home=='mars' or r.taskWorker) and u and not adopted then r.untilTime=clock+10;return end
   start(r,r.untilTime,r.index%#r.route+1)
  else return end
 end
end

local function journeyPoint(r,p,clock)
 -- A per-ship offset spreads traffic across the corridor without adding nodes.
 -- Keep it in the record so repeated sampling and save/load never reshuffle it.
 if r.spread==nil then r.spread=(love.math.random()*2-1)*T.alifeSpread end
 local x,y=Graph.point(graph(r.area),edge(r),p,clock)
 local radius=math.sqrt(x*x+y*y)
 if radius>0 then
  local across=r.spread*math.sin(math.pi*p)
  x,y=x+x/radius*across,y+y/radius*across
 end
 return x,y
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
    if a.area==b.area and Fields[a.area].tradeBuoys
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
 local fraction=math.min(1,(clock-r.depart)/math.max(.01,r.arrive-r.depart))
 local along=(-game.lane.half+fraction*game.trip.length)*dir
 local n=(r.laneOffset or -math.min(T.laneWidth*.65,math.max(T.laneMedian+200,500+math.abs(r.spread or 0))))*dir
 local entry=r.transit.departure
 local anchor=entry and dir==1 and game.trip.origin and game.trip.originScene
  and game.trip.originScene.fieldId==entry.area
 if anchor then
  local s0,n0=game:toLane(entry.x+game.trip.origin.x,entry.y+game.trip.origin.y)
  along=s0+(clock-entry.clock)*speed
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
  cargo=copy(s.cargo),hold=s.hold and Hold.serialize(s.hold)}
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
 r.ship=shipRecord(e); r.power=e.power
 if Security.isRole(r) then return Security.capture(game,e,r,remote) end
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
  r.untilTime=clock+(ds.done and math.max(0,(ds.stay or T.alifeStay)-ds.t) or T.alifeStay)
  -- Preserve an in-progress physical docking operation for immediate save/load.
  r.docking={}
  for k,v in pairs(ds) do if type(v)~='table' and type(v)~='userdata' then r.docking[k]=v end end
 else
  r.state='travel'
  local x,y=e.body:getPosition()
  local duration=math.max(.1,Graph.length(graph(r.area),edge(r),clock)/r.speed)
  local p=Graph.project(graph(r.area),edge(r),x,y,clock)
  -- Never advance a destination merely because an online ship is close to it;
  -- actual AI/docking changes routeIndex. Leave a little time for handoff.
  p=math.min(.99,p)
  if r.encounter then r.encounter.progress=p end
  r.depart=clock-p*duration; r.arrive=r.depart+duration
  if not remote then
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
 e.routeIndex=r.index; e.route={}
 e.travelGraph=graph(r.area)
 e.taskWorker=r.taskWorker
 for _,id in ipairs(r.route) do
  local place=L.get(id)
  -- a station with several access points: the one nearest the ship now
  local stop=place.area==game.fieldId and game:locationEntity(id,e.body:getPosition())
  if stop and place.kind=='station' and not dockingStop(r,id) then
   local station=stop
   stop={kind='waypoint',locationId=id,removed=false,inspection=station.city,body={getPosition=function()
    if station.city then return L.inspectionPosition(id,game.universe.clock) end
    return require('src.ai').stopPoint(station)
   end,getLinearVelocityFromWorldPoint=function(_,x,y)
    if station.city then return L.inspectionVelocity(id,game.universe.clock) end
    return station.body:getLinearVelocityFromWorldPoint(x,y)
   end}}
  end
  if stop and place.kind=='driver' then
   local driver=stop
   stop={kind='driver',locationId=id,driver=driver,removed=false,body={getPosition=function() return game:driverBreech(driver) end}}
  end
  if not stop then
   stop={kind=place.kind,locationId=id,removed=false}
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
  e.route[#e.route+1]=stop
 end
end

A.bindRoute=bindRoute

function A.wake(game,r)
 local s=r.ship
 local lane=A.laneSample(game,r,game.universe.clock)
 local egress=A.egressSample(game,r,game.universe.clock)
 local p=egress or lane or A.sample(r,game.universe.clock)
 local exact=r.pose and math.abs(r.pose.clock-game.universe.clock)<.001 and r.pose
 if exact and lane and exact.lane~=game.trip.from..'/'..game.trip.to..'/'..tostring(game.trip.rot) then exact=nil end
 local e=Ship.new(game,{hull=s.hull,loadout=s.loadout,cargo=s.cargo,
  hold=s.hold and Hold.deserialize(s.hold,function(id) return data.items[id]~=nil end),
  armor=s.armor,color=copy(s.color),team=data.enemies[r.archetype].team,
  enemy=data.enemies[r.archetype],x=exact and exact.x or p.x,y=exact and exact.y or p.y,
  angle=exact and exact.a or p.heading})
 e.alifeId=r.id
 e.alifeRole=Security.isRole(r) and r.role or nil
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
  game:dockInstantly(e,st)
  e.dockState.stay=math.max(0,r.untilTime-game.universe.clock)
  if exact and r.docking then
   e.dockState=copy(r.docking); e.dockState.station=st
   e.body:setPosition(exact.x,exact.y); e.body:setAngle(exact.a)
   e.body:setActive(e.dockState.phase=='tractor')
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

function A.install(Game)
 function Game:traderCanDepart(e,station)
  local r=self.universe.npcs[e.alifeId]
  if not r or r.home~='mars' and not r.taskWorker then return true end
  A.capture(self,e,false)
  local ok=adoptTrip(r,station.locationId,self.universe.clock,self.universe)
  if not ok then return false end
  e.cargo=copy(r.ship.cargo);Ship.updateMass(e)
  e.jobPrepared=true
  return true
 end
 function Game:traderUndocked(e,station)
  local r=self.universe.npcs[e.alifeId]
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
  Security.updateSpawns(self,clock)
  local records=self.universe.npcs or {}
  Tasks.clean(self.universe,clock)
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
    r.transit.speed=r.transit.kind=='driver' and T.laneFlow or math.max(50,math.sqrt(vx*vx+vy*vy))
    r.arrive=clock+r.transit.length/r.transit.speed
    e.alifeDepart=nil; e.alifeEgress=true; e.route=nil
    e.egressHeading=e.driverProtected and math.atan2(vy,vx) or math.atan2(y,x); e.egressSpeed=math.max(r.transit.speed,r.speed*.6)
    e.intent=Ship.emptyIntent()
    A.capture(self,e,true)
   elseif not e.driverTractor and not e.launch and (not px or (x-px)^2+(y-py)^2>T.alifeFar^2) then
    A.capture(self,e,false)
    if not e.removed then self:remove(e,true) end
    self.alifeOnline[id]=nil
   end
  end
  for id,r in pairs(records) do
   if not self.alifeOnline[id] then
    local localArea=r.area==self.fieldId and not self.lane and not self.flight
    if localArea or A.laneDirection(self,r) or force or clock>=(self.alifeRemoteNext or 0) then A.advance(r,clock,self.universe) end
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
  if clock>=(self.alifeRemoteNext or 0) then self.alifeRemoteNext=clock+T.alifeRemoteTick end
 end
end
return A
