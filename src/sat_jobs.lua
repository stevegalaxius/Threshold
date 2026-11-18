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

-- Where the job starts (the system's trade station; for a quiet region
-- with none, like Neptune or Pluto, the one in the region next door) and
-- the node in the satellite's own field it flies to before heading out to
-- the satellite (a station there, else a buoy or the holding point).
local function tradeStation(field)
 local s=L.station(root(field),'trade') or L.station(field,'trade')
 if s then return s end
 local near={}
 if Fields.moons[field] then near[#near+1]=Fields.moons[field].parent end
 for _,m in ipairs(Fields.moonsOf(field)) do near[#near+1]=m end
 for _,a in ipairs(near) do s=L.station(a,'trade') if s then return s end end
 for _,a in ipairs(near) do
  for _,id in ipairs(L.stations(a)) do if L.stationServices(id).market then return id end end
 end
end
function J.places(field)
 local source=tradeStation(field)
 local f=Fields[field]
 local here=L.stations(field)[1] or f and (f.buoyIds and f.buoyIds[1] or f.holdingId)
 return source,here or source
end

function J.post(u,r,kind)
 local source,target=J.places(r.field)
 if not source then return end
 kind=kind or 'satrefuel'
 -- cargo, not item/amount: the poster provides it, so it reserves no station stock
 -- listed to the player first (src/sat_quests.lua): haulers may only take
 -- it once it has gone T.satJobPlayerFirst unclaimed
 local clock=u.clock or 0
 -- (one the owner ordered goes straight to the haulers)
 return Tasks.post(u,{kind=kind,source=source,target=target,sat=r.id,order=true,cooldown=60,placed=clock,npcClaimAt=clock+(r.refuelOrdered and 0 or require('src.tuning').satJobPlayerFirst),
  cargo={item=J.cargo[kind],amount=1}})
end

-- satrefuel: top up a low satellite. satlaunch: replace a destroyed one.
local function wanted(kind,s)
 if kind=='satlaunch' then return s.lost end
 if s.lost then return false end
 -- the owner sent for a hauler (Sat.orderRefuel), however full it is
 if s.refuelOrdered then return true end
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
  if J.playerHolds(u,kind,o.sat) then return false end
  return s and wanted(kind,s) and L.canonical(node)==L.canonical(o.source) or false
 end,
 feasible=function(u,r,o,node,clock)
  local c=o.cargo or {item=J.cargo[kind],amount=1}
  if require('src.npc_operations').room(r,c.item)<c.amount then return false end
  -- a refuel's canister comes out of the posting station's own stock
  if kind=='satrefuel' and require('src.stockpile').available(u,o.source,c.item)<c.amount then return false end
  return o.source==o.target or G.itinerary(o.source,o.target,clock)~=nil
 end,
 score=function(u,r,o,node,clock) return clock-(o.readyAt or 0) end,
 prepare=function(u,r,t,node,clock)
  t.route=t.source==t.target and {node,node} or G.live(node,t.target,clock)
  if not t.route then return false end
  t.route=copy(t.route);t.phase=kind=='satlaunch' and 'launching satellite' or 'refuelling satellite'
  -- take the job's cargo aboard at the station that posted it: a refuel's
  -- canister (and a hub's restock) out of that station's stock; a launch's
  -- satellite package is still provided by the poster
  t.cargo=t.cargo or {item=J.cargo[kind],amount=1}
  t.loads={}
  local Stock,Transport=require('src.stockpile'),require('src.transport')
  local function load(item,want)
   local n=math.min(want,require('src.npc_operations').room(r,item))
   if kind=='satrefuel' then n=math.min(n,Stock.available(u,t.source,item)) end
   if n<=0 then return 0 end
   if kind=='satrefuel' then assert(Stock.take(u,t.source,item,n)) end
   Transport.carry(r,item,n);t.loads[item]=(t.loads[item] or 0)+n
   return n
  end
  if load(t.cargo.item,t.cargo.amount)<t.cargo.amount then
   -- (nothing to take after all: put back what was loaded)
   for item,n in pairs(t.loads) do Transport.carry(r,item,-n);Stock.add(u,t.source,item,n) end
   t.loads=nil;return false
  end
  local s=u.satellites and u.satellites[t.sat]
  if kind=='satrefuel' and s then
   for item,n in pairs(require('src.satellites').hubShortfall(u,s)) do
    load(item,n)
   end
  end
  t.cargoAboard=true
  return true
 end,
 plan=function(t) return copy(t.route) end,
 nextAction=function(ctx)
  local r,t=ctx.r,ctx.r.task
  if t.serviced or r.state~='idle' or L.canonical(r.node or '')~=L.canonical(t.target) then return end
  if r.action and r.action.kind=='work' then return r.action end
  local s=ctx.u.satellites and ctx.u.satellites[t.sat]
  if not s or not wanted(kind,s) then t.serviced=true;return end
  local spec=J.freeBerth(ctx,s,'satservice')
  if not spec then
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
  -- (the cargo was spent out at the satellite; if the job turned out not to
  -- be needed, the hauler keeps it)
  if t.done then
   -- the station that posted the run pays for it
   r.credits=(r.credits or 0)+require('src.accounts').pay(u,t.target,J.pay,'freight')
   -- (the player's own satellite: the player pays the fee)
   local s=u.satellites and u.satellites[t.sat]
   if s then require('src.satellites').bill(u,s,J.pay) end
  end
  return true
 end,
})
end
-- A berth of a satellite as an action target (t.id, t.berth): online, the
-- berth beside its live husk (or, for a launch, its empty slot); offline,
-- its home orbit slot. record = that berth's record, so the action claim
-- holds that one berth (a hub's other berth stays free).
Actions.registerTarget('satellite',{resolve=function(ctx,t)
 local Sat=require('src.satellites')
 local s=Sat.get(ctx.u,t.id);if not s then return end
 local i=t.berth or 1
 local berth=Sat.berth(s,i)
 local game=ctx.game
 if ctx.e and game and game.fieldId==s.field then
  local e=Sat.entity(game,t.id)
  if e then
   local x,y,vx,vy=Sat.berthPoint(e,ctx.e,i)
   return {x=x,y=y,vx=vx,vy=vy,entity=e,record=berth,sat=s,berth=i}
  end
 end
 local x,y=Sat.home(ctx.u,s,game);if not x then return end
 return {x=x,y=y,vx=0,vy=0,record=berth,sat=s,berth=i}
end})
-- A free berth of satellite s for this ship's work, or nil.
function J.freeBerth(ctx,s,operation)
 local Sat=require('src.satellites')
 local e=ctx.game and ctx.game.fieldId==s.field and Sat.entity(ctx.game,s.id)
 -- (a satellite with no docking module still has one spot to work from)
 for i=1,math.max(1,Sat.berthCount(s)) do
  local spec={kind='work',operation=operation,target={provider='satellite',id=s.id,berth=i}}
  local target=Actions.targets.satellite.resolve(ctx,spec.target)
  if target and Actions.available(ctx,target) and not Sat.playerOn(e,i) then return spec end
 end
end
-- On the berth: wait while the player holds it, else mark it this ship's.
local function onBerth(ctx,target)
 local Sat=require('src.satellites')
 if Sat.playerOn(target.entity,target.berth) then return false end
 return true
end
-- Take up to n of item the job loaded back out of the hauler (online, off
-- the live ship). Returns how many.
function J.unload(ctx,t,item,n)
 n=math.min(n,(t.loads or {})[item] or 0)
 if n<=0 then return 0 end
 t.loads[item]=t.loads[item]-n
 if ctx.e then
  Actions.recordOperation(ctx,function() require('src.transport').carry(ctx.r,item,-n);return 'done' end)
 else require('src.transport').carry(ctx.r,item,-n) end
 return n
end
-- Sit on the berth for J.stay seconds, then the job's effect.
local function service(ctx,target,dt,a)
 if not onBerth(ctx,target) then return 'running' end -- the player is on the berth
 a.held=(a.held or 0)+dt
 if a.held<J.stay then return 'running' end
 local Sat,t=require('src.satellites'),ctx.r.task
 local kind=t and t.kind
 if kind=='satlaunch' then
  if Sat.relaunch(ctx.u,target.sat.id,ctx.r.id) then
   t.done=true;J.unload(ctx,t,t.cargo.item,t.cargo.amount)
   if ctx.game and ctx.game.fieldId==target.sat.field and ctx.game.entities then Sat.populate(ctx.game) end
  end
 elseif kind=='satrefuel' then
  t.done=Sat.refuel(ctx.u,target.sat.id,ctx.r.id)
  if t.done then
   J.unload(ctx,t,t.cargo.item,t.cargo.amount) -- the canister went into its tank
   -- whatever else it brought goes onto a hub's shelf
   for item,n in pairs(t.loads or {}) do
    local k=J.unload(ctx,t,item,n)
    if k>0 then Sat.stockHub(ctx.u,target.sat,item,k) end
   end
  end
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
-- Never while the tank is empty, and never for more than J.hubWaitLimit
-- game seconds in a row: a ship that keeps flying past nodes without
-- stopping books its usual station visit after that.
J.hubWaitLimit=180
function J.holdForHub(r,clock,e)
 local fuel=require('src.reactor_fuel').condition(r,e)
 if fuel=='empty' or fuel=='stranded' then r.hubHeldSince=nil;return false end
 if r.hubHeldSince and clock-r.hubHeldSince>J.hubWaitLimit then
  if clock-r.hubHeldSince>J.hubWaitLimit*3 then r.hubHeldSince=nil end -- (a later need can try again)
  return false
 end
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
 local spec=J.freeBerth(ctx,hub,'hubservice')
 if not spec then return false end
 local a=Actions.request(ctx,spec);a.fromJob=true
 r.hubHeldSince=nil
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
 if not onBerth(ctx,target) then return 'running' end
 a.held=(a.held or 0)+dt
 if a.held<J.hubStay then return 'running' end
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
-- The player's station job for the same satellite (src/sat_quests.lua):
-- while they hold it, haulers leave this board job alone.
J.quest={satlaunch='sat_launch',satrefuel='sat_refuel'}
function J.playerHolds(u,kind,sat)
 for _,q in pairs(u.quests and u.quests.active or {}) do
  if q.kind==J.quest[kind] and q.subject==sat and not q.used then return true end
 end
 return false
end
-- A hauler already took this satellite's board job (so the player's
-- version isn't offered, or accepted, out from under it).
function J.npcHolds(u,kind,sat)
 for _,o in pairs(Tasks.state(u).offers) do
  if o.kind==kind and o.sat==sat and o.owner and o.owner~='player' then return true end
 end
 return false
end
function J.clear(u,id,kind)
 local offers=Tasks.state(u).offers
 for oid,o in pairs(offers) do
  if o.sat==id and o.state=='available' and (not kind or o.kind==kind) then offers[oid]=nil end
 end
end
-- Satellite ids with a job of this kind still on the board (taken or not).
-- This satellite's open refuel job, if any.
function J.offer(u,kind,sat)
 for _,o in pairs(Tasks.state(u).offers) do if o.kind==kind and o.sat==sat then return o end end
end
function J.open(u,kind)
 local out={}
 for _,o in pairs(Tasks.state(u).offers) do if o.kind==kind and o.sat then out[o.sat]=true end end
 return out
end
return J
