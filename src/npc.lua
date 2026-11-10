-- One NPC AI. Every persistent ship (trader, pirate, patrol, salvager, miner)
-- runs this same loop:
--
--   travel -> arrive (dock or hold) -> stay -> decide -> travel ...
--
-- A job only answers "what next from here?" (`next`) and "is this stop the
-- end of my leg, and do I dock there?" (`docks`). Movement, docking, repair,
-- refuelling, upkeep visits, speed and the stuck-guard are shared, so every
-- job behaves the same way between decisions.
local L=require('src.locations')
local G=require('src.travelgraph')
local Fields=require('src.fields')
local T=require('src.tuning')
local data=require('src.data')
local Repairs=require('src.npc_repair')
local Supplies=require('src.supplies')
local Trace=require('src.alife_trace')
local Tasks=require('src.tasks')
local Actions=require('src.npc_actions')
local N={}
local deps={}
function N.install(d) for k,v in pairs(d) do deps[k]=v end end

-- One decision controller. Task handlers supply execution hooks, not AI loops.
local chooseClock,chooseCount
N.controller={name='npc',
 docks=function(r,id)
  local t=r.task
  return not t or L.canonical(id)==L.canonical(t.phase=='pickup' and t.source or t.target)
 end,
 complete=function(c) Tasks.arrive(c.u,c.r,L.canonical(c.node),c.clock,c.game) end,
 next=function(c)
  local u,r,node,clock=c.u,c.r,L.canonical(c.node),c.clock
  local work=N.work(r)
  if work and work.continue then
   local plan=work.continue(c)
   if plan then return plan end
  end
  if (r.nextTaskAt or 0)>clock then return {wait=r.nextTaskAt-clock} end
  if not r.task then
   if chooseClock~=clock then chooseClock,chooseCount=clock,0 end
   if chooseCount>=T.taskChoosePerTick then return {wait=2} end
   chooseCount=chooseCount+1
  end
  local task=Tasks.choose(u,r,node,clock)
  if not task then return end
  r.taskWorker=true;r.nextTaskAt=nil
  local route=Tasks.plan(r,node,clock)
  if not route then Tasks.release(u,r,'no route',clock);return end
  return {route=route,wait=task.duration,dock=task.dock}
 end,
 roam=function(r,node)
  local f=Fields[L.get(node).area];local nodes={}
  for _,id in ipairs(f.buoyIds or {}) do nodes[#nodes+1]=id end
  for _,id in ipairs(L.stations(f.id or L.get(node).area,'trade')) do nodes[#nodes+1]=id end
  return nodes
 end,
}

-- Speed -----------------------------------------------------------------------
-- One cruise speed for every NPC. Hulls only nudge it (±15%), so a pirate,
-- a hauler and a salvager crossing the same region take about the same time.
function N.cruise(archetype)
 local def=archetype and data.enemies[archetype]
 local own=def and def.ai and def.ai.cruise or T.npcCruise
 local factor=math.max(1-T.npcCruiseSpread,math.min(1+T.npcCruiseSpread,own/T.npcCruiseReference))
 return T.npcCruise*factor
end
-- The live ship's cruise, for onscreen steering.
function N.liveCruise(e)
 return e.npcCruise or (e.alifeRecord and e.alifeRecord.speed) or (e.def and e.def.ai and e.def.ai.cruise) or T.npcCruise
end
-- Approaching something to work it (a pickup, a wreck, a container): slow in.
function N.approach(e,d,stand)
 return math.min(N.liveCruise(e),math.max(20,(d-(stand or 0))*.6))
end

-- Active work supplies execution hooks; a ship's identity does not select them.
function N.work(r) return r and r.task and Tasks.definitions[r.task.kind] end
function N.context(game,r,clock,e,dt,AI,u)
 return {game=game,u=u or game.universe,r=r,clock=clock,e=e,dt=dt,AI=AI}
end
function N.runActions(ctx)
 local current=ctx.r.action
 if current and current.pausedAt and ctx.r.state=='docked' and Actions.definitions[current.kind].positioning then
  Actions.cancel(ctx,'replan work after docking');current=nil
 end
 if current and Actions.definitions[current.kind].route and current.fromJob then return Actions.step(ctx) end
 if current and not Actions.definitions[current.kind].route then
  local fromJob=current.fromJob
  local handled=Actions.step(ctx)
  return fromJob or handled and ctx.r.action~=nil
 end
 local work=N.work(ctx.r)
 if work and work.nextAction then
  local spec=work.nextAction(ctx)
  if spec then
   local a=Actions.request(ctx,spec);a.fromJob=true
   Actions.step(ctx);return true
  end
 end
 if ctx.r.action then Actions.step(ctx) end
 return false
end
function N.routeAction(ctx)
 local r=ctx.r;local target=r.route and r.route[#r.route]
 if not target then return end
 local kind=r.state=='idle' and 'hold' or N.docksAt(r,target) and 'dock' or 'travel'
 Actions.request(ctx,{kind=kind,target={provider='location',id=target},untilTime=r.untilTime})
end
function N.thinkWork(game,e,dt,AI)
 local r=game.universe.npcs[e.alifeId];if not r then return false end
 e.tractorTarget=nil;e.intent.tractor=false
 local ctx=N.context(game,r,game.universe.clock,e,dt,AI)
 if e.alifeEgress or e.driverTractor or e.launch or e.dockState then
  Actions.pause(ctx,'controlled transit');AI.trade(game,e,dt);return true
 end
 if r.action and r.action.completed then Actions.step(ctx) end
 local work=N.work(r)
 if work and work.before then work.before(ctx) end
 if N.runActions(ctx) then return true end
 N.updateOnline(game,e)
 N.routeAction(ctx)
 return Actions.step(ctx)
end

-- Docking ---------------------------------------------------------------------
-- Does the ship stop (dock) at `id`? Shared rules first, then the job's.
function N.docksAt(r,id)
 if r.worldRecovery then return id==r.worldRecovery.target end
 if r.service then return require('src.upkeep').isStation(r,id) end
 local action=r.action
 if action and action.target and (action.kind=='dock' or action.kind=='travel') and L.canonical(action.target.id)==L.canonical(id) then
  return action.kind=='dock'
 end
 local work=N.work(r)
 if work and work.docks then return work.docks(r,id) and L.get(id).kind=='station' end
 local j=N.controller
 if j and j.docks then return j.docks(r,id) and L.get(id).kind=='station' end
 return false
end

-- Arrive at the end of a leg: dock at a station the job wants, otherwise hold
-- position. Docking always repairs and restocks, whatever the job.
function N.arrive(r,node,at,u,game)
 r.offset,r.pose=nil,nil
 r.node=node;r.area=L.get(node).area;r.transit=nil
 r.route={node,node};r.index=1
 local j=N.controller
 local work=N.work(r)
 local stay=(work and work.stay and work.stay(r,node)) or (j and j.stay and j.stay(r,node)) or T.alifeStay
 if L.get(node).kind=='station' and N.docksAt(r,node) then
  r.state='docked'
  Supplies.refill(r,node)
  Repairs.begin(r,node,at,stay)
 else
  r.state='idle';r.untilTime=at+stay
 end
 if r.action and (r.action.kind=='travel' or r.action.kind=='dock') then
  Actions.complete({u=u or {},game=game,r=r,clock=at})
 end
end

-- Leave along `route` (a node list starting where the ship is).
local function go(r,route,at,ctx)
 if not route or #route==0 then return false end
 ctx=ctx or {u={},r=r,clock=at}
 local x,y=Actions.actorPosition(ctx)
 if not ctx.startingAction then Actions.cancel(ctx,'new route') end
 if #route==1 then route={route[1],route[1]} end
 r.route=route;r.index=1;r.offset=nil;r.pose=nil
 deps.start(r,at,2)
 if x and L.get(route[1]).area==r.area then
  local bx,by=L.position(route[1],at);r.offset={x=x-bx,y=y-by,progress=0}
 end
 if not ctx.startingAction then N.routeAction(ctx) end
 return true
end
N.go=go

-- Route action start: configure the existing graph/berthing kernel without
-- recursively requesting another action. New jobs can request travel/dock.
function N.beginRoute(ctx,action)
 local r=ctx.r;local target=action.target.id
 if not L.byId[target] then return false end
 if r.route and r.route[#r.route]==target and (r.state=='travel' or r.state=='transit') then return true end
 local moving=r.state=='travel' or r.state=='transit'
 local from=moving and r.route[r.index] or r.node or r.route[r.index]
 local route=G.itinerary(from,target,ctx.clock);if not route then return false end
 if moving then
  local previous=r.route[(r.index-2)%#r.route+1]
  r.route={previous};for _,id in ipairs(route) do r.route[#r.route+1]=id end;r.index=2
  require('src.queue').leg(r)
 else
  ctx.startingAction=true;go(r,route,ctx.clock,ctx);ctx.startingAction=nil
 end
 if ctx.e then require('src.alife').bindRoute(ctx.game,ctx.e,r) end
 return true
end

function N.travel(game,r,target,clock)
 local ctx=N.context(game,r,clock,game.alifeOnline and game.alifeOnline[r.id])
 if ctx.e then require('src.alife').capture(game,ctx.e,false) end
 local from=r.state=='travel' and r.route[r.index] or r.node or r.route[r.index]
 local route=G.itinerary(from,target,clock)
 if not route then return false end
 if r.state=='travel' then
  Actions.cancel(ctx,'new destination')
  local previous=r.route[(r.index-2)%#r.route+1]
  r.route={previous};for _,id in ipairs(route) do r.route[#r.route+1]=id end;r.index=2
  require('src.queue').leg(r);N.routeAction(ctx)
 else go(r,route,clock,ctx) end
 if ctx.e then require('src.alife').bindRoute(game,ctx.e,r) end
 return true
end

-- A ship with nothing to do still moves: it wanders to a nearby node of its
-- job, so nothing sits forever at one buoy because the board is busy.
local function wander(r,node,at,ctx)
 local j=N.controller
 local nodes=j and j.roam and j.roam(r,node) or {}
 local choices={}
 for _,id in ipairs(nodes) do if id~=node and L.byId[id] then choices[#choices+1]=id end end
 if #choices==0 then return false end
 r.wanderCount=(r.wanderCount or 0)+1
 local seed=(tonumber(tostring(r.id):match('%d+$')) or 0)+r.wanderCount
 local target=choices[seed%#choices+1]
 local route=G.itinerary(node,target,at)
 if not route then return false end
 Trace.note(r,at,'npc','no work at '..node..' -> wandering to '..target)
 r.taskStatus='looking for work'
 return go(r,route,at,ctx)
end

-- Decide what to do next, standing at `node` at time `at`. Returns true when
-- the ship has started moving (or was given something to wait for).
function N.decide(u,r,node,at,game)
 local j=N.controller;if not j then return false end
 local ctx=N.context(game or {universe=u},r,at,game and game.alifeOnline and game.alifeOnline[r.id],nil,nil,u)
 ctx.node=node
 if ctx.e then ctx.AI=require('src.ai') end
 if N.runActions(ctx) then return true end
 if j.complete then j.complete(ctx) end
 if L.get(node).kind=='station' then Supplies.refill(r,node) end
 -- Upkeep (fuel, repair, supplies) comes before work, from any state.
 local Upkeep=require('src.upkeep')
 if r.state=='docked' then r.state='idle';r.node=node end
 if Upkeep.plan(r,at) then return true end
 local plan=j.next(ctx)
 if plan and plan.route then
  r.stuckSince=nil
  if #plan.route<=1 or (#plan.route==2 and plan.route[1]==plan.route[2]) then
   -- work right here: hold (or stay docked) for its duration
   if plan.dock and L.get(node).kind=='station' then r.state='docked';Repairs.begin(r,node,at,plan.wait or T.alifeStay)
   else r.state='idle';r.untilTime=at+(plan.wait or T.patrolInspect) end
   r.node=node;r.route={node,node};r.index=1
   return true
  end
  return go(r,plan.route,at,ctx)
 end
 if plan and plan.wait then
  r.untilTime=at+plan.wait
  r.state=L.get(node).kind=='station' and N.docksAt(r,node) and 'docked' or 'idle'
  return true
 end
 -- Nothing to do. Don't sit still for ever: after a while, roam.
 r.stuckSince=r.stuckSince or at
 if j.roam and at-r.stuckSince>=T.npcIdleRoam and wander(r,node,at,ctx) then r.stuckSince=nil;return true end
 r.state=L.get(node).kind=='station' and N.docksAt(r,node) and 'docked' or 'idle'
 r.untilTime=at+(j.retry or 10)
 return false
end

-- The offline loop: complete every event up to `clock`.
function N.advance(r,clock,u,game)
 if r.state=='dead' or r.state=='escaped' then return end
 if r.encounter then Actions.pause({u=u,r=r,clock=clock},'combat');return end
 local ctx={u=u,game=game or {universe=u},r=r,clock=clock}
 local work=N.work(r)
 if work and work.before then work.before(ctx) end
 for _=1,128 do
  if not r.worldRecovery and N.runActions(ctx) then return end
  if r.state=='travel' or r.state=='transit' then
   -- (a ship queued at a driver or a dock waits its turn at the end of the leg)
   local at=require('src.queue').due(r)
   if clock<at then return end
   if r.index<#r.route and not N.docksAt(r,r.route[r.index]) then deps.start(r,at,r.index+1)
   else N.arrive(r,r.route[r.index],at,u,game) end
  elseif r.state=='docked' or r.state=='idle' then
   local node=r.node or r.route[r.index]
   if r.state=='docked' then Repairs.advance(r,clock,node) end
   require('src.reactor_fuel').observe(u,r,clock)
   if clock<(r.untilTime or 0) then return end
   local at=r.untilTime or clock
   if r.worldRecovery then require('src.world_reconcile').resume(u,r,at) end
   if not N.decide(u,r,node,at,game) then return end
   if r.state~='travel' and r.state~='transit' and (r.untilTime or 0)<=at then return end
  else return end
 end
end

-- Online: a live ship docked at `station` asks to leave. The same decision
-- the offline loop makes; the live ship then follows the record's new route.
function N.departOnline(game,e,station)
 local r=game.universe.npcs[e.alifeId]
 local A=require('src.alife')
 A.capture(game,e,false)
 local node=L.canonical(station.locationId)
 if r.worldRecovery then require('src.world_reconcile').resume(game.universe,r,game.universe.clock) end
 r.state='docked';r.node=node
 N.decide(game.universe,r,node,game.universe.clock,game)
 -- deliveries, sales and loot unloading changed the hold: keep the live ship in step
 e.cargo=require('src.persistence').copy(r.ship.cargo)
 if e.hold and r.ship.hold then e.hold=require('src.inventory.hold').deserialize(r.ship.hold,function(id) return data.items[id]~=nil end)
 elseif e.hold then require('src.inventory.hold').sync(e.hold,e.cargo) end
 require('src.ship').updateMass(e)
 if r.state~='travel' and r.state~='transit' then r.state='docked';return false end
 e.npcDeparture=true
 return true
end

-- Online: the live ship has reached the last stop of its route without
-- docking (a buoy, an inspection point). Same arrival as offline.
function N.holdOnline(game,e,node)
 local r=game.universe.npcs[e.alifeId]
 local A=require('src.alife')
 A.capture(game,e,false)
 N.arrive(r,node,game.universe.clock,game.universe,game)
 A.bindRoute(game,e,r)
end

-- Online: a live ship holding position whose stay is over.
function N.updateOnline(game,e)
 local r=game.universe.npcs[e.alifeId]
 if not r or r.state~='idle' or r.encounter or game.universe.clock<(r.untilTime or 0) then return end
 local A=require('src.alife')
 A.capture(game,e,false)
 r.ship.armor=e.armor;r.ship.cargo=require('src.persistence').copy(e.cargo)
 if e.hold then r.ship.hold=require('src.inventory.hold').serialize(e.hold) end
 N.decide(game.universe,r,r.node,game.universe.clock,game)
 A.bindRoute(game,e,r)
end
return N
