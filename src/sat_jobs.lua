-- Satellite work on the task board (src/tasks.lua).
--
-- When a satellite runs low on fuel (Sat.tick in src/satellites.lua) its
-- system's trade station posts one "satrefuel" order: take a deuterium
-- canister from there out to the satellite's map, fly out to the satellite
-- itself, lock on at its berth for J.stay seconds, and its tank is full
-- again. A destroyed satellite posts "satlaunch" the same way: fly the
-- package out to the old slot, hold there while it's set up, and a
-- replacement takes the slot (free for now).
--
-- The flight out and the hold are an ordinary NPC work action (src/
-- npc_actions.lua) on a "satellite" target, so it runs the same online
-- (the ship really flies there and sits on the berth) and offline (the
-- same travel and hold time). The target claim means one ship at a time
-- per satellite; a second one waits nearby until the berth is free. Any hauler can take it; scavenger and industrial tempers lean
-- towards it (src/work_preferences.lua). The order is removed once done.
local Fields,L,G=require('src.fields'),require('src.locations'),require('src.travelgraph')
local Tasks=require('src.tasks')
local copy=require('src.persistence').copy
local Actions=require('src.npc_actions')
local function Supplies() return require('src.supplies').universe end
local J={pay=900,stay=25}
-- What each job hands the hauler to carry out to the satellite: the same
-- item the player's version of the quest uses (src/sat_quests.lua).
J.cargo={satrefuel='deuterium_canister',satlaunch='satellite_package'}

local function root(area) return Fields.moons[area] and Fields.moons[area].parent or area end

-- Where the job starts (the system's trade station) and where it's done (a
-- station in the satellite's own field, else the start).
function J.places(field)
 local source=L.station(root(field),'trade') or L.station(field,'trade')
 local here=L.stations(field)[1]
 return source,here or source
end

function J.post(u,r,kind)
 local source,target=J.places(r.field)
 if not source then return end
 kind=kind or 'satrefuel'
 -- cargo, not item/amount: the poster provides it, so it reserves no station stock
 return Tasks.post(u,{kind=kind,source=source,target=target,sat=r.id,order=true,cooldown=60,
  cargo={item=J.cargo[kind],amount=1}})
end

-- satrefuel: top up a low satellite. satlaunch: replace a destroyed one.
local function wanted(kind,s)
 if kind=='satlaunch' then return s.lost end
 if s.lost then return false end
 local Sat=require('src.satellites')
 if (s.fuel or 1)<Sat.refuelAt then return true end
 local u=Supplies()
 return u and Sat.hubLow(u,s) or false
end
for _,kind in ipairs({'satrefuel','satlaunch'}) do
Tasks.register(kind,{
 requires={capabilities={'cargo'}},
 -- it holds off the station at the far end, not docked: the work is out
 -- at the satellite (nextAction)
 docks=function() return false end,
 stay=function() return J.stay end,
 eligible=function(u,r,o,node)
  local s=u.satellites and u.satellites[o.sat]
  return s and wanted(kind,s) and L.canonical(node)==L.canonical(o.source) or false
 end,
 feasible=function(u,r,o,node,clock)
  local c=o.cargo or {item=J.cargo[kind],amount=1}
  if require('src.npc_operations').room(r,c.item)<c.amount then return false end
  return o.source==o.target or G.itinerary(o.source,o.target,clock)~=nil
 end,
 score=function(u,r,o,node,clock) return clock-(o.readyAt or 0) end,
 prepare=function(u,r,t,node,clock)
  t.route=t.source==t.target and {node,node} or G.itinerary(node,t.target,clock)
  if not t.route then return false end
  t.route=copy(t.route);t.phase=kind=='satlaunch' and 'launching satellite' or 'refuelling satellite'
  -- take the job's cargo aboard at the station that posted it
  t.cargo=t.cargo or {item=J.cargo[kind],amount=1}
  require('src.transport').carry(r,t.cargo.item,t.cargo.amount);t.cargoAboard=true
  return true
 end,
 plan=function(t) return copy(t.route) end,
 nextAction=function(ctx)
  local r,t=ctx.r,ctx.r.task
  if t.serviced or r.state~='idle' or L.canonical(r.node or '')~=L.canonical(t.target) then return end
  if r.action and r.action.kind=='work' then return r.action end
  local s=ctx.u.satellites and ctx.u.satellites[t.sat]
  if not s or not wanted(kind,s) then t.serviced=true;return end
  local spec={kind='work',operation='satservice',target={provider='satellite',id=t.sat}}
  local target=Actions.targets.satellite.resolve(ctx,spec.target)
  if target and not Actions.available(ctx,target) then
   -- someone else is on the berth: wait off the station a while
   t.waitUntil=ctx.clock+J.stay
   return {kind='hold',key='satwait/'..t.sat..'/'..t.waitUntil,target={provider='location',id=t.target},untilTime=t.waitUntil}
  end
  if t.waitUntil and ctx.clock<t.waitUntil then return end
  r.taskStatus=kind=='satlaunch' and 'launching satellite' or 'refuelling satellite'
  return spec
 end,
 actionEnded=function(ctx,a,status)
  if a.operation=='satservice' and status=='done' then ctx.r.task.serviced=true end
 end,
 complete=function(u,r,t,node)
  if L.canonical(node)~=L.canonical(t.target) or not t.serviced then return false end
  local Sat=require('src.satellites')
  -- the cargo is spent on the satellite (or, if it's already fixed, kept)
  local s=u.satellites and u.satellites[t.sat]
  if t.cargoAboard and s and wanted(kind,s) then
   require('src.transport').carry(r,t.cargo.item,-t.cargo.amount);t.cargoAboard=nil
  end
  if t.done then r.credits=(r.credits or 0)+J.pay end
  return true
 end,
})
end
-- The satellite as an action target: online, its live husk (or, for a launch,
-- its empty slot), with the berth beside it as the place to stand; offline,
-- its home orbit slot. record = the satellite's record, so the action claim
-- keeps it to one ship at a time.
Actions.registerTarget('satellite',{resolve=function(ctx,t)
 local Sat=require('src.satellites')
 local s=Sat.get(ctx.u,t.id);if not s then return end
 local game=ctx.game
 if ctx.e and game and game.fieldId==s.field then
  local e=Sat.entity(game,t.id)
  if e then
   local x,y,vx,vy=Sat.berthPoint(e,ctx.e)
   return {x=x,y=y,vx=vx,vy=vy,entity=e,record=s,sat=s}
  end
 end
 local x,y=Sat.home(ctx.u,s,game);if not x then return end
 return {x=x,y=y,vx=0,vy=0,record=s,sat=s}
end})
-- Sit on the berth for J.stay seconds, then the job's effect.
local function service(ctx,target,dt,a)
 local other=ctx.e and target.entity and target.entity.satHeld
 if other and other~=ctx.e and other.dockState and not other.dead then return 'running' end -- the player is on the berth
 a.held=(a.held or 0)+dt
 if ctx.e and target.entity then target.entity.satHeld=ctx.e end
 if a.held<J.stay then return 'running' end
 if ctx.e and target.entity and target.entity.satHeld==ctx.e then target.entity.satHeld=nil end
 local Sat,t=require('src.satellites'),ctx.r.task
 local kind=t and t.kind
 if kind=='satlaunch' then
  if Sat.relaunch(ctx.u,target.sat.id,ctx.r.id) then
   t.done=true
   if ctx.game and ctx.game.fieldId==target.sat.field and ctx.game.entities then Sat.populate(ctx.game) end
  end
 elseif kind=='satrefuel' then
  t.done=Sat.refuel(ctx.u,target.sat.id,ctx.r.id)
  if t.done then Sat.restockHub(ctx.u,target.sat) end
 end
 return 'done'
end
Actions.registerOperation('satservice',{
 distance=function() return 0 end,
 inRange=function(ctx,target)
  local x,y=ctx.e.body:getPosition()
  return (x-target.x)^2+(y-target.y)^2<(target.entity and 120 or 400)^2
 end,
 offline=service,
 online=function(ctx,target,dt,a)
  -- hold station on the berth, matching the satellite's drift
  local e=ctx.e;local vx,vy=e.body:getLinearVelocity()
  ctx.AI.driveVelocity(e,target.vx or 0,target.vy or 0,(target.vx or 0)-vx,(target.vy or 0)-vy,e.def.ai.throttle)
  if target.entity then
   local ex,ey=target.entity.body:getPosition()
   e.intent.aimX,e.intent.aimY=ex,ey
   e.tractorTarget=target.entity;e.intent.tractor=true
  end
  return service(ctx,target,dt,a)
 end,
 missing=function() return 'failed','satellite gone' end,
})

-- Hub visits: an NPC short of fuel or supplies, deciding what to do next
-- at a route node, with a working hub nearer than any station that could
-- serve it, flies out to the hub, holds on the berth and buys off its shelf
-- (src/satellites.lua). Called from N.decide before ordinary upkeep; true
-- when the visit has started (or is still under way). Otherwise upkeep's
-- usual station visit takes over.
J.hubStay=15
-- The working hub nearer to the ship than any station that could serve
-- it, or nil.
function J.preferredHub(ctx)
 local r=ctx.r;local Sat=require('src.satellites')
 local x,y=Actions.actorPosition(ctx);if not x then return end
 local hub=Sat.nearestHub(ctx.u,r.area,x,y);if not hub then return end
 local hx,hy=Sat.home(ctx.u,hub,ctx.game)
 local hd=(hx-x)^2+(hy-y)^2
 for _,id in ipairs(L.stations(r.area)) do
  if require('src.supplies').supports(id) then
   local sx,sy=L.position(id,ctx.clock)
   if (sx-x)^2+(sy-y)^2<hd then return end
  end
 end
 return hub
end
-- From upkeep's planning mid-leg: a hub is the better stop, so don't book a
-- station visit now; the ship takes the hub at its next node (J.hubVisit).
function J.holdForHub(r,clock,e)
 if (r.hubCheckAt or 0)>clock then return r.hubHeld or false end
 r.hubCheckAt=clock+10
 local u=require('src.supplies').universe
 r.hubHeld=u and J.preferredHub({u=u,r=r,clock=clock,e=e,game=e and e.alifeGame or {universe=u}})~=nil or false
 return r.hubHeld
end
function J.hubVisit(ctx)
 local r=ctx.r;local Sat=require('src.satellites')
 if r.action and r.action.operation=='hubservice' then return true end
 if r.action and not Actions.definitions[r.action.kind].route then return false end
 if r.service or r.state~='idle' or not r.area or (r.nextHubAt or 0)>ctx.clock then return false end
 local need=require('src.upkeep').need(r,ctx.e)
 if need~='fuel' and need~='supplies' then return false end
 r.nextHubAt=ctx.clock+120
 local hub=J.preferredHub(ctx);if not hub then return false end
 local spec={kind='work',operation='hubservice',target={provider='satellite',id=hub.id}}
 local target=Actions.targets.satellite.resolve(ctx,spec.target)
 if not target or not Actions.available(ctx,target) then return false end
 local a=Actions.request(ctx,spec);a.fromJob=true
 r.taskStatus='stopping at '..(hub.name or 'a hub')
 Actions.step(ctx)
 return true
end
local function shop(ctx,target)
 local Sat=require('src.satellites')
 if not Sat.hubWorking(ctx.u,target.sat) then return 0 end
 local n=require('src.supplies').refillFrom(ctx.r,Sat.shelf(target.sat),ctx.u)
 if n>0 then Sat.hubServed(ctx.u,target.sat) end
 return n
end
local function hubHold(ctx,target,dt,a)
 local other=ctx.e and target.entity and target.entity.satHeld
 if other and other~=ctx.e and other.dockState and not other.dead then return 'running' end
 a.held=(a.held or 0)+dt
 if ctx.e and target.entity then target.entity.satHeld=ctx.e end
 if a.held<J.hubStay then return 'running' end
 if ctx.e and target.entity and target.entity.satHeld==ctx.e then target.entity.satHeld=nil end
 if ctx.e then Actions.recordOperation(ctx,function() shop(ctx,target);return 'done' end) else shop(ctx,target) end
 return 'done'
end
Actions.registerOperation('hubservice',{
 distance=function() return 0 end,
 inRange=function(ctx,target)
  local x,y=ctx.e.body:getPosition()
  return (x-target.x)^2+(y-target.y)^2<(target.entity and 120 or 400)^2
 end,
 offline=hubHold,
 online=function(ctx,target,dt,a)
  local e=ctx.e;local vx,vy=e.body:getLinearVelocity()
  ctx.AI.driveVelocity(e,target.vx or 0,target.vy or 0,(target.vx or 0)-vx,(target.vy or 0)-vy,e.def.ai.throttle)
  if target.entity then
   local ex,ey=target.entity.body:getPosition()
   e.intent.aimX,e.intent.aimY=ex,ey
  end
  return hubHold(ctx,target,dt,a)
 end,
 missing=function() return 'failed','hub gone' end,
})

-- The job is done (by anyone): drop the NPC orders for it nobody has taken.
function J.clear(u,id,kind)
 local offers=Tasks.state(u).offers
 for oid,o in pairs(offers) do
  if o.sat==id and o.state=='available' and (not kind or o.kind==kind) then offers[oid]=nil end
 end
end
-- Satellite ids with a job of this kind still on the board (taken or not).
function J.open(u,kind)
 local out={}
 for _,o in pairs(Tasks.state(u).offers) do if o.kind==kind and o.sat then out[o.sat]=true end end
 return out
end
return J
