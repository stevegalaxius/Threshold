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
local N={jobs={},order={}}
local deps={}
function N.install(d) for k,v in pairs(d) do deps[k]=v end end

-- Jobs ----------------------------------------------------------------------
-- definition = {
--   match(r)                       -> this record does this job
--   docks(r,node)                  -> docks (true) or holds (false) at the end of a leg
--   stay(r,node)                   -> seconds to stay after arriving (default T.alifeStay)
--   complete(ctx)                  -> work done on arrival (deliveries, sales, unloading)
--   next(ctx)                      -> {route=..., wait=...} or nil when there's nothing to do
--   before(ctx)                    -> optional, runs each advance before the loop
--   advance(game,r,clock)          -> optional: the job keeps its own world model (miners)
-- }
-- ctx = {u=,game=,r=,node=,clock=}
function N.job(name,definition)
 definition.name=name
 if not N.jobs[name] then N.order[#N.order+1]=name end
 N.jobs[name]=definition
end
function N.jobOf(r)
 if not r then return end
 for _,name in ipairs(N.order) do
  local j=N.jobs[name]
  if j.match(r) then return j end
 end
end

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

-- Docking ---------------------------------------------------------------------
-- Does the ship stop (dock) at `id`? Shared rules first, then the job's.
function N.docksAt(r,id)
 if r.worldRecovery then return id==r.worldRecovery.target end
 if r.service then return require('src.upkeep').isStation(r,id) end
 local j=N.jobOf(r)
 if j and j.docks then return j.docks(r,id) and L.get(id).kind=='station' end
 return false
end

-- Arrive at the end of a leg: dock at a station the job wants, otherwise hold
-- position. Docking always repairs and restocks, whatever the job.
function N.arrive(r,node,at)
 r.offset,r.pose=nil,nil
 r.node=node;r.area=L.get(node).area;r.transit=nil
 r.route={node,node};r.index=1
 local j=N.jobOf(r)
 local stay=(j and j.stay and j.stay(r,node)) or T.alifeStay
 if L.get(node).kind=='station' and N.docksAt(r,node) then
  r.state='docked'
  Supplies.refill(r,node)
  Repairs.begin(r,node,at,stay)
 else
  r.state='idle';r.untilTime=at+stay
 end
end

-- Leave along `route` (a node list starting where the ship is).
local function go(r,route,at)
 if not route or #route==0 then return false end
 if #route==1 then route={route[1],route[1]} end
 r.route=route;r.index=1
 deps.start(r,at,2)
 return true
end
N.go=go

-- A ship with nothing to do still moves: it wanders to a nearby node of its
-- job, so nothing sits forever at one buoy because the board is busy.
local function wander(r,node,at)
 local j=N.jobOf(r)
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
 return go(r,route,at)
end

-- Decide what to do next, standing at `node` at time `at`. Returns true when
-- the ship has started moving (or was given something to wait for).
function N.decide(u,r,node,at,game)
 local j=N.jobOf(r);if not j then return false end
 local ctx={u=u,game=game,r=r,node=node,clock=at}
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
  return go(r,plan.route,at)
 end
 if plan and plan.wait then
  r.untilTime=at+plan.wait
  r.state=L.get(node).kind=='station' and N.docksAt(r,node) and 'docked' or 'idle'
  return true
 end
 -- Nothing to do. Don't sit still for ever: after a while, roam.
 r.stuckSince=r.stuckSince or at
 if j.roam and at-r.stuckSince>=T.npcIdleRoam and wander(r,node,at) then r.stuckSince=nil;return true end
 r.state=L.get(node).kind=='station' and N.docksAt(r,node) and 'docked' or 'idle'
 r.untilTime=at+(j.retry or 10)
 return false
end

-- The offline loop: complete every event up to `clock`.
function N.advance(r,clock,u,game)
 if r.state=='dead' or r.state=='escaped' or r.encounter then return end
 local j=N.jobOf(r)
 if j and j.advance and not r.worldRecovery then return j.advance(game or {universe=u},r,clock) end
 if j and j.before then j.before({u=u,game=game,r=r,clock=clock}) end
 for _=1,128 do
  if r.state=='travel' or r.state=='transit' then
   if clock<r.arrive then return end
   local at=r.arrive
   if r.index<#r.route and not N.docksAt(r,r.route[r.index]) then deps.start(r,at,r.index+1)
   else N.arrive(r,r.route[r.index],at) end
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
 N.arrive(r,node,game.universe.clock)
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
