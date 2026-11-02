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
 return math.max(0,math.min(1,(clock-r.depart)/math.max(.01,r.arrive-r.depart)))
end
local function start(r,clock,index)
 r.index=index; r.depart=clock
 local leg=edge(r)
 local from,to=L.get(leg.from),L.get(leg.to)
 if from.area~=to.area then
  local lane=assert(Graph.transit(leg.from,leg.to),'invalid inter-region journey')
  r.state='transit'; r.area=nil; r.transit=lane
  lane.speed=r.speed
  r.arrive=clock+lane.length/lane.speed
 else
  r.state='travel'; r.area=to.area; r.transit=nil
  r.arrive=clock+math.max(.1,Graph.length(graph(r.area),leg,clock)/r.speed)
 end
 r.offset,r.pose,r.docking,r.savedOnline=nil,nil,nil,nil
end

local function roundTrip(home,to,clock)
 local a,b=Fields[home].stationIds[1],Fields[to].stationIds[1]
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

-- A local trader can adopt its moon itinerary on departure from its home dock.
local function adoptTrip(r,station)
 if r.tripRoute and not r.onRoundTrip and station==r.tripRoute[1] then
  r.route=copy(r.tripRoute); r.index=1; r.onRoundTrip=true
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
 if not game.preview then A.repairMoonRoutes(game) end
end

function A.advance(r,clock)
 if r.state=='dead' or r.state=='escaped' then return end
 -- Complete elapsed activities using their event times, not frame steps.
 while true do
  if r.state=='travel' or r.state=='transit' then
   if clock<r.arrive then return end
   local at=r.arrive
   r.offset,r.pose=nil,nil
   if L.get(r.route[r.index]).kind=='station' then
    r.state='docked'; r.untilTime=at+T.alifeStay
   else start(r,at,r.index%#r.route+1) end
  elseif r.state=='docked' then
   if clock<r.untilTime then return end
   adoptTrip(r,r.route[r.index])
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
  if r.tripRoute then
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

function A.point(r,clock)
 if r.state=='transit' then return nil end
 if r.state=='docked' then return L.position(r.route[r.index],clock) end
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
function A.capture(game,e,remote)
 local r=game.universe.npcs and game.universe.npcs[e.alifeId]
 if not r then return end
 if e.dead then r.state='dead'; return end
 if e.removed then r.state='escaped'; return end
 local clock=game.universe.clock
 r.savedOnline=nil
 r.ship=shipRecord(e); r.power=e.power
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
 for _,id in ipairs(r.route) do
  local place=L.get(id)
  local stop=place.area==game.fieldId and game:locationEntity(id)
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
  e.route[#e.route+1]=stop
 end
end

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
 if egress then
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
 else bindRoute(game,e,r) end
 e.power=r.power or e.power
 e.body:setLinearVelocity(exact and exact.vx or p.vx,exact and exact.vy or p.vy)
 e.body:setAngularVelocity(exact and exact.w or 0)
 table.insert(game.entities,e)
 if r.state=='docked' then
  local st=game:locationEntity(r.route[r.index])
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
  local source=game:locationEntity(leg.from)
  local destination=game:locationEntity(leg.to)
  local function close(st)
   if not st or st.kind~='station' then return false end
   local x,y=st.body:getPosition()
   return (p.x-x)^2+(p.y-y)^2<((st.radius or st.def.radius or 1000)+e.halfLength)^2
  end
  if close(source) then
   e.routeIndex=(r.index-2)%#r.route+1
   game:dockInstantly(e,source)
   game:undockShip(e)
  elseif close(destination) then
   local x,y=require('src.ai').stopPoint(destination)
   e.body:setPosition(x,y)
   e.body:setAngle(game.dockAngle(destination,1)+math.pi)
   e.body:setLinearVelocity(destination.body:getLinearVelocityFromWorldPoint(x,y))
   game:beginDocking(e,destination,1)
  end
 end

 game.alifeOnline[r.id]=e
 r.pose,r.savedOnline=nil,nil
 return e
end

function A.install(Game)
 function Game:traderUndocked(e,station)
  local r=self.universe.npcs[e.alifeId]
  if adoptTrip(r,station.locationId) then
   start(r,self.universe.clock,2)
   bindRoute(self,e,r)
  end
 end
 function Game:captureALife(detach)
  for id,e in pairs(self.alifeOnline or {}) do
   A.capture(self,e,detach)
   local r=self.universe.npcs and self.universe.npcs[id]
   if not detach and r then r.savedOnline=true end
   if detach then
    if not e.removed then self:remove(e) end
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
  local records=self.universe.npcs or {}
  local px,py
  if self.player and not self.player.dead then px,py=self.player.body:getPosition() end
  for id,e in pairs(self.alifeOnline) do
   local x,y
   if not e.removed then x,y=e.body:getPosition() end
   if e.dead then
    -- Normal reap must still produce the wreck and death effects.
    A.capture(self,e,false)
    self.alifeOnline[id]=nil
   elseif e.removed then
    A.capture(self,e,false)
    self.alifeOnline[id]=nil
   elseif e.alifeLane and select(1,self:toLane(e.body:getPosition()))*e.cruiseDir>=self.lane.half then
    A.capture(self,e,true)
    local r=records[id]
    start(r,clock,r.index%#r.route+1)
    self:remove(e); self.alifeOnline[id]=nil
   elseif e.alifeDepart then
    local vx,vy=e.body:getLinearVelocity()
    A.capture(self,e,true)
    local r=records[id]
    start(r,clock,r.index%#r.route+1)
    r.transit.speed=math.max(50,math.sqrt(vx*vx+vy*vy))
    r.arrive=clock+r.transit.length/r.transit.speed
    e.alifeDepart=nil; e.alifeEgress=true; e.route=nil
    e.egressHeading=math.atan2(y,x); e.egressSpeed=math.max(r.transit.speed,r.speed*.6)
    e.intent=Ship.emptyIntent()
    A.capture(self,e,true)
   elseif not px or (x-px)^2+(y-py)^2>T.alifeFar^2 then
    A.capture(self,e,false)
    if not e.removed then self:remove(e) end
    self.alifeOnline[id]=nil
   end
  end
  for id,r in pairs(records) do
   if not self.alifeOnline[id] then
    local localArea=r.area==self.fieldId and not self.lane and not self.flight
    if localArea or A.laneDirection(self,r) or force or clock>=(self.alifeRemoteNext or 0) then A.advance(r,clock) end
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
  if clock>=(self.alifeRemoteNext or 0) then self.alifeRemoteNext=clock+T.alifeRemoteTick end
 end
end
return A
