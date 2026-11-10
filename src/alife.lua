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
local NPC=require('src.npc')
local A = {}
-- Each NPC keeps its own small offset from the shared track, so two ships on
-- the same leg at the same time (or holding at the same buoy) aren't drawn on
-- top of each other on the map, and don't wake up inside each other.
function A.spread(r)
 local id=tostring(r.id or '')
 local n=tonumber(id:match('%d+$')) or 0
 for i=1,#id do n=n+id:byte(i)*i*7 end
 -- the golden angle: consecutive ids land far apart round the circle
 local a=n*2.399963;local d=T.npcSpread*(.4+.6*((n*.618034)%1))
 return math.cos(a)*d,math.sin(a)*d
end
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
  -- just off a mass driver's lane: wakes come in along its rail (below)
  r.driverArrival=(r.state=='transit' and from.kind=='driver') and clock or nil
  r.state='travel'; r.area=to.area; r.transit=nil
  r.arrive=clock+math.max(.1,Graph.length(graph(r.area),leg,clock)/r.speed)
 end
 -- a leg into a mass driver or a dock books its turn there
 if r.state=='travel' then require('src.queue').leg(r) else r.queue=nil end
 r.offset,r.pose,r.docking,r.savedOnline=nil,nil,nil,nil
 r.driverState,r.cityExit=nil,nil
end

A.start=start
Upkeep.install({start=start,graph=graph})
NPC.install({start=start,graph=graph})

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

local chooseClock,chooseCount=nil,0
-- Traders: the job board's transport work. Movement, docking and upkeep are
-- the shared NPC loop's (src/npc.lua).
NPC.job('trader',{
 match=function(r) return true end, -- registered last: any other civilian
 docks=function(r,id)
  id=L.canonical(id)
  -- a pickup loads at its source: a live ship that only passed by it
  -- circled the station's inspection point forever, never loading
  local t=r.task
  -- on the empty leg to a pickup only the source counts: passing through
  -- the delivery target (often on the way) docked there, then left and
  -- docked again on the next pass, over and over
  if t and t.phase=='pickup' then return id==t.source end
  return not t or id==t.target
 end,
 complete=function(c) Tasks.arrive(c.u,c.r,L.canonical(c.node),c.clock,c.game) end,
 next=function(c)
  local u,r,clock=c.u,c.r,c.clock
  local station=L.canonical(c.node)
  r.taskWorker=true
  if (r.nextTaskAt or 0)>clock then return {wait=r.nextTaskAt-clock} end
  -- Stagger job hunting: a few traders per tick, the rest try again shortly,
  -- so a new game's whole fleet doesn't weigh the job board in one frame.
  if not r.task then
   if chooseClock~=clock then chooseClock,chooseCount=clock,0 end
   if chooseCount>=T.taskChoosePerTick then return {wait=love.math.random()*2} end
   chooseCount=chooseCount+1
  end
  local task=Tasks.choose(u,r,station,clock)
  if not task then return {wait=8+love.math.random()*4} end
  r.nextTaskAt=nil
  local route=Tasks.plan(r,station,clock)
  if not route then Tasks.release(u,r,'no route',clock);return {wait=10} end
  r.onRoundTrip=nil;r.tripRoute=nil;r.tripDestination=nil
  return {route=route}
 end,
})

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
  route=copy(f.traderRoute),speed=NPC.cruise(kind),
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
 require('src.supplies').universe=u
 require('src.queue').universe=u
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
   -- every NPC flies at the shared cruise speed (older saves kept per-hull speeds)
   if r.archetype then r.speed=NPC.cruise(r.archetype) end
  end
  Homes.seed(u)
  Population.schedule(game,u.clock)
  A.repairMoonRoutes(game)
  A.repairApproachRoutes(game)
 end
end

local dockingStop=NPC.docksAt

function A.advance(r,clock,u,game)
 local fuelStatus=Fuel.advance(r,clock,u)
 if fuelStatus=='stranded' and require('src.distress').advance(game,r,clock) then fuelStatus=r.fuelStatus end
 if fuelStatus=='stranded' and Fuel.needsPropulsion(r) then return end
 if r.waitingForHome then return end
 if r.state=='dead' or r.state=='escaped' then return end
 -- Upkeep comes before every job: a due service visit owns the ship.
 if not r.service then Upkeep.plan(r,clock) end
 if r.service and Upkeep.advance(r,clock,u) then return end
 if game and not r.worldRecovery and not r.piracy and require("src.offline_loot").update(game,r,clock) then return end
 local result=NPC.advance(r,clock,u,game)
 Fuel.observe(u,r,clock)
 return result
end

local function journeyPoint(r,p,clock)
 -- A per-ship offset spreads traffic across the corridor without adding nodes.
 -- Keep it in the record so repeated sampling and save/load never reshuffle it.
 if r.spread==nil then r.spread=(love.math.random()*2-1)*T.alifeSpread end
 local leg=edge(r)
 -- a record with no area of its own (between areas, or one that no longer
 -- exists) is drawn on the graph of where its leg is going
 local g=Fields[r.area or ''] and graph(r.area) or graph(L.get(leg.to).area)
 -- A leg that crosses regions (a stale route) is drawn on the graph that
 -- holds both ends, or at its destination, instead of crashing.
 if not (g.nodes[leg.from] and g.nodes[leg.to]) then
  g=graph(L.get(leg.to).area)
  if not (g.nodes[leg.from] and g.nodes[leg.to]) then
   local x,y=L.position(leg.to,clock);return Graph.withSpread(x,y,p,r.spread)
  end
 end
 local x,y=Graph.point(g,leg,p,clock)
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
      local sx,sy=A.spread(r);r.offset={x=x-bx-sx,y=y-by-sy,progress=p}
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
     local sx,sy=A.spread(r);r.offset={x=x-bx-sx,y=y-by-sy,progress=p}
    end
   end
  end
 end
end

function A.point(r,clock)
 local x,y=A.trackPoint(r,clock)
 if not x or r.state=='docked' or r.offlineLoot or Mining.isMiner(r) and not (r.worldRecovery or r.waitingForHome) then return x,y end
 local sx,sy=A.spread(r)
 return x+sx,y+sy
end
function A.trackPoint(r,clock)
 if r.offlineLoot then local x,y=require("src.offline_loot").position(r,clock);if x then return x,y end end
 if Mining.isMiner(r) and not (r.worldRecovery or r.waitingForHome) then return Mining.point(nil,r,clock) end
 if r.state=='transit' then return nil end
 if r.state=='docked' then return L.position(r.route[r.index],clock) end
 if r.state=='idle' then
  local x,y=L.inspectionPosition(r.route[r.index],clock)
  return x+(r.offset and r.offset.x or 0),y+(r.offset and r.offset.y or 0)
 end
 -- through with the leg and waiting its turn at a driver or a dock: in line
 -- (it stops there on the way in, once it gets that close)
 local Q=require('src.queue')
 local p=progress(r,clock)
 if Q.waiting(r,clock) then
  local hx,hy=Q.holdPoint(r,clock)
  local nx,ny=L.position(r.route[r.index],clock)
  local x,y=journeyPoint(r,p,clock)
  if clock>=r.arrive or (x-nx)^2+(y-ny)^2<=(hx-nx)^2+(hy-ny)^2 then return hx,hy end
  return x,y
 end
 local x,y=journeyPoint(r,p,clock)
 if r.offset then
  local fade=(1-p)/math.max(.001,1-r.offset.progress)
  x,y=x+r.offset.x*fade,y+r.offset.y*fade
 end
 return x,y
end
-- Is world point x,y on screen (or within `margin` of its edge)?
function A.inView(game,x,y,margin)
 local c=game.camera;if not c or not love.graphics then return false end
 local w,h=love.graphics.getDimensions()
 local hw,hh=w/2/c.zoom+(margin or 0),h/2/c.zoom+(margin or 0)
 return math.abs(x-c.x)<hw and math.abs(y-c.y)<hh
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
  if known then
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
   local sx,sy=A.spread(r);r.offset={x=x-bx-sx,y=y-by-sy,progress=p}
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
 e.npcCruise=r.speed
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
  local g=source and source.kind=='driver' and source
  local fresh=r.driverArrival and game.universe.clock-r.driverArrival<T.npcDriverArrivalTime
  if g and fresh then
   -- off the lane: in from out along the rail, beyond the catch rings,
   -- lined up on the breech, as the player arrives (Game:placeForCatch)
   local gx,gy=game:driverBreech(g)
   local d=math.floor(T.catchRings+.5)*T.catchSpacing+T.catchApproach
   local off=(love.math.random()*2-1)*T.catchOffset
   local ox,oy=math.cos(g.angle),math.sin(g.angle)
   local ia=g.angle+math.pi
   e.body:setPosition(gx+ox*d-oy*off,gy+oy*d+ox*off);e.body:setAngle(ia)
   e.body:setLinearVelocity(math.cos(ia)*r.speed,math.sin(ia)*r.speed)
   r.driverArrival=nil
  elseif close(source) and dockingStop(r,leg.from) then
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
   -- The visit is done here: hand the route back now and plan the next
   -- leg like any departure (its job may start right here). Ending it on
   -- undock instead never fired: undocking wraps the live route index to
   -- 1 first, so the ship flew its service leg again and redocked here,
   -- 'heading to repair' for ever.
   A.capture(self,e,false);e.serviceDockedAt=nil
   serviced.index=#serviced.route;Upkeep.passed(serviced,#serviced.route)
   -- still docked here, now as itself
   serviced.state='docked';serviced.node=L.canonical(station.locationId);serviced.untilTime=self.universe.clock
  end
  local r=self.universe.npcs[e.alifeId]
  if Mining.isMiner(r) and not r.worldRecovery then return Mining.depart(self,e,station) end
  if not r then return true end
  return NPC.departOnline(self,e,station)
 end
 function Game:traderUndocked(e,station)
  if e.serviceDeparture then
   e.serviceDeparture,e.serviceDockedAt=nil,nil
   local r=self.universe.npcs[e.alifeId];A.capture(self,e,false)
   if r.index>=#r.route then Upkeep.passed(r,#r.route) end
   start(r,self.universe.clock,r.index%#r.route+1);bindRoute(self,e,r);return
  end
  local r=self.universe.npcs[e.alifeId]
  if Mining.isMiner(r) and not r.worldRecovery then return Mining.bind(self,e,r) end
  if e.npcDeparture then
   -- the record left when the ship asked to undock: its leg starts now
   e.npcDeparture=nil
   if r.state=='travel' or r.state=='transit' then start(r,self.universe.clock,r.index) end
  end
  bindRoute(self,e,r)
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
  require('src.supplies').universe=self.universe
  require('src.queue').universe=self.universe
  require('src.arbiter').update(self.universe,clock)
  require('src.economy').update(self.universe,clock)
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
   -- (a record the map ahead has woken is that map's: src/transit.lua)
   if not self.alifeOnline[id] and not (self.sideOwns and self:sideOwns(id)) then
    local localArea=r.area==self.fieldId and not self.lane and not self.flight
    if localArea or A.laneDirection(self,r) or force or clock>=(self.alifeRemoteNext or 0) then A.advance(r,clock,self.universe,self) end
    local lane=A.laneSample(self,r,clock)
    local egress=A.egressSample(self,r,clock)
    localArea=r.area==self.fieldId and not self.lane and not self.flight
    if px and (egress or lane or localArea and r.state~='dead' and r.state~='escaped' and r.state~='transit') then
     local x,y
     if egress then x,y=egress.x,egress.y elseif lane then x,y=lane.x,lane.y else x,y=A.point(r,clock) end
     local threshold=r.savedOnline and r.pose and math.abs(r.pose.clock-clock)<.001 and T.alifeFar or T.alifeNear
     -- never pop into existence on screen: a ship that turns up inside the
     -- view (off a turned-round leg, a driver's breech, a spawn) stays in
     -- its offline model until it's out of sight; docked ones appear in
     -- their berth and fresh driver arrivals come in along the rail
     local hidden=force or r.savedOnline or r.state=='docked' or (r.driverArrival and clock-r.driverArrival<T.npcDriverArrivalTime) or egress or lane or not A.inView(self,x,y,600)
     if (x-px)^2+(y-py)^2<threshold^2 and hidden then A.wake(self,r) end
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
 -- the area's base, plus whatever the arbiter says its open hauls need
 target=function(f,area) return L.station(area,'trade') and f.alifeTraders and f.alifeTraders+require('src.arbiter').extraTraders(area) end,
 -- the whole fleet stays within the areas' bases plus the arbiter's extras,
 -- however the free agents have spread out
 budget=function()
  local n=0
  for _,area in ipairs(Fields.list) do
   local f=Fields[area]
   if not f.instance and not f.transit and L.station(area,'trade') and f.alifeTraders then n=n+f.alifeTraders+require('src.arbiter').extraTraders(area) end
  end
  return n
 end,
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
