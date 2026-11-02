-- First A-Life slice: Earth's existing traders. Records own identity; bodies
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
 r.index=index; r.state='travel'; r.depart=clock
 r.arrive=clock+math.max(.1,Graph.length(graph(r.area),edge(r),clock)/r.speed)
 r.offset,r.pose,r.docking=nil,nil,nil
end
function A.seed(game)
 local f=Fields[game.fieldId]
 if not f.alifeTraders then return end
 local u=game.universe
 u.npcs=u.npcs or {}; u.npcAreas=u.npcAreas or {}; u.nextNpcId=u.nextNpcId or 0
 if u.npcAreas[game.fieldId] then return end
 u.npcAreas[game.fieldId]=true
 local kinds={'freighter','packhorse_trader','runner_trader'}
 for i=1,f.alifeTraders do
  local kind=kinds[(i-1)%#kinds+1]
  local def=data.enemies[kind]; local hull=data.hulls[def.hull]
  u.nextNpcId=u.nextNpcId+1
  local id='npc/'..u.nextNpcId
  local loadout=copy(def.loadout or hull.loadout)
  local stats=Stats.compute(hull,loadout)
  local r={id=id,area=game.fieldId,role='trader',archetype=kind,
   route=copy(f.traderRoute),speed=def.ai.cruise or T.traderCruise,
   spread=(love.math.random()*2-1)*T.alifeSpread,
   ship={hull=def.hull,loadout=loadout,cargo=copy(def.cargo or hull.cargo),armor=stats.armor,color=copy(def.color)}}
  start(r,u.clock,i%#r.route+1)
  -- Start spread along existing journeys, rather than spawning replacements.
  local elapsed=(r.arrive-r.depart)*i/(f.alifeTraders+1)
  r.depart,r.arrive=r.depart-elapsed,r.arrive-elapsed
  u.npcs[id]=r
 end
end

function A.advance(r,clock)
 if r.state=='dead' or r.state=='escaped' then return end
 -- Complete elapsed activities using their event times, not frame steps.
 while true do
  if r.state=='travel' then
   if clock<r.arrive then return end
   local at=r.arrive
   r.offset,r.pose=nil,nil
   if L.get(r.route[r.index]).kind=='station' then
    r.state='docked'; r.untilTime=at+T.alifeStay
   else start(r,at,r.index%#r.route+1) end
  elseif r.state=='docked' then
   if clock<r.untilTime then return end
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

function A.point(r,clock)
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

function A.wake(game,r)
 local s=r.ship
 local p=A.sample(r,game.universe.clock)
 local exact=r.pose and math.abs(r.pose.clock-game.universe.clock)<.001 and r.pose
 local e=Ship.new(game,{hull=s.hull,loadout=s.loadout,cargo=s.cargo,
  hold=s.hold and Hold.deserialize(s.hold,function(id) return data.items[id]~=nil end),
  armor=s.armor,color=copy(s.color),team=data.enemies[r.archetype].team,
  enemy=data.enemies[r.archetype],x=exact and exact.x or p.x,y=exact and exact.y or p.y,
  angle=exact and exact.a or p.heading})
 e.alifeId=r.id; e.routeIndex=r.index; e.route={}
 for _,id in ipairs(r.route) do e.route[#e.route+1]=assert(game:locationEntity(id),'missing trader destination '..id) end
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
 game.alifeOnline[r.id]=e
 r.pose,r.savedOnline=nil,nil
 return e
end

function A.install(Game)
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
   elseif e.removed or not px or (x-px)^2+(y-py)^2>T.alifeFar^2 then
    A.capture(self,e,false)
    if not e.removed then self:remove(e) end
    self.alifeOnline[id]=nil
   end
  end
  for id,r in pairs(records) do
   if not self.alifeOnline[id] then
    local localArea=r.area==self.fieldId and not self.lane and not self.flight
    if localArea or force or clock>=(self.alifeRemoteNext or 0) then A.advance(r,clock) end
    if localArea and px and r.state~='dead' and r.state~='escaped' then
     local x,y=A.point(r,clock)
     local threshold=r.savedOnline and r.pose and math.abs(r.pose.clock-clock)<.001 and T.alifeFar or T.alifeNear
     if (x-px)^2+(y-py)^2<threshold^2 then A.wake(self,r) end
    end
   end
  end
  if clock>=(self.alifeRemoteNext or 0) then self.alifeRemoteNext=clock+T.alifeRemoteTick end
 end
end
return A
