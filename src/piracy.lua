-- Cargo acquisition and return duties for the existing persistent pirates.
local T=require('src.tuning')
local L=require('src.locations')
local G=require('src.travelgraph')
local Fields=require('src.fields')
local Ship=require('src.ship')
local Hold=require('src.inventory.hold')
local Tasks=require('src.tasks')
local Loot=require('src.loot')
local Grid=require('src.inventory.grid')
local Repairs=require('src.npc_repair')
local Supplies=require('src.supplies')
local Homes=require('src.npc_home')
local P={}
local itinerary=G.itinerary
P.route=itinerary
function P.unload(u,r)
 local base=r.piracy and r.piracy.base or r.homeStation or L.station(nil,'pirateBase')
 local stashState=u.piracy or {stashes={}};u.piracy=stashState
 local stash=stashState.stashes[base] or {};stashState.stashes[base]=stash
 local h=r.ship.hold and Hold.deserialize(r.ship.hold,function(id)return require('src.data').items[id]~=nil end)
 local cargo=h and Hold.totals(h) or r.ship.cargo or {}
 -- Loaded containers are transferred as stacks, before count-based cargo.
 if h then
  stashState.containers=stashState.containers or {}
  local containers=stashState.containers[base] or {};stashState.containers[base]=containers
  for _,g in ipairs(h.grids) do for i=#g.stacks,1,-1 do
   local s=g.stacks[i]
   if s.stolen then
    local destination=containers
    if not s.inner then
     stashState.stacks=stashState.stacks or {};stashState.stacks[base]=stashState.stacks[base] or {}
     destination=stashState.stacks[base]
    end
    destination[#destination+1]={id=s.id,n=s.n,inner=s.inner and Hold.serialize(s.inner),wear=s.wear}
    stash[s.id]=(stash[s.id] or 0)+s.n
    if r.stolenCargo then r.stolenCargo[s.id]=math.max(0,(r.stolenCargo[s.id] or 0)-s.n) end
    Grid.remove(g,s)
   end
  end end
  cargo=Hold.totals(h)
 end
 for id,count in pairs(r.stolenCargo or {}) do
  local n=math.min(count,cargo[id] or 0)
  if n>0 then
   if h then Hold.take(h,id,n) else cargo[id]=cargo[id]-n;if cargo[id]==0 then cargo[id]=nil end end
   stash[id]=(stash[id] or 0)+n
  end
 end
 if h then r.ship.hold=Hold.serialize(h);cargo=Hold.totals(h) end
 r.ship.cargo=cargo;r.stolenCargo={};r.lootUntil=nil
end
function P.returnRecord(game,r)
 if r.piracy then return true end
 local A=require('src.alife')
 if r.encounter then require('src.encounters').finish(game.universe,r,game.universe.npcs[r.encounter.target],game.universe.clock,r) end
 local base=Homes.get(r)
 if not base then r.taskStatus='no pirate home station';return false end
 local source=r.state=='travel' and r.route[r.index] or r.node or r.route[r.index]
 local path=itinerary(source,base,game.universe.clock)
 if not path then r.taskStatus='no route to '..L.get(base).name;return false end
 Tasks.release(game.universe,r,'returning with loot',game.universe.clock)
 -- A service visit under way (repair, fuel) would hand back the route it saved
 -- when it ends, the old one, not this one: the ship docked at the service
 -- station and then left for where it was before the loot. Home docks and
 -- repairs it anyway; upkeep plans again from there if it still needs to.
 r.service,r.serviced=nil,nil
 require('src.alife_trace').note(r,game.universe.clock,'piracy','returning to '..base)
 r.piracy={phase='escape',base=base,origin=L.rally(r.home,source,game.universe.clock) or L.station(r.home,'trade'),started=game.universe.clock}
 r.taskWorker=true;r.taskStatus='returning to '..L.get(base).name
 if r.state=='travel' then
  local previous=r.route[(r.index-2)%#r.route+1]
  r.route={previous};for _,id in ipairs(path) do r.route[#r.route+1]=id end;r.index=2
  require('src.queue').leg(r) -- the leg under way may now end at a driver or a dock
 else
  r.route=path;r.index=1
  if #path>1 then A.start(r,game.universe.clock,2)
  else r.state='docked';r.node=base;Repairs.begin(r,r.node,game.universe.clock,T.pirateRest) end
 end
 return true
end
function P.beginReturn(game,e,r)
 if r.piracy then return true end
 local A=require('src.alife');A.capture(game,e,false)
 if not P.returnRecord(game,r) then return false end
 e.combatTarget,e.lock,e.aggressor,e.tractorTarget=nil,nil,nil,nil
 e.serviceDockedAt,e.serviceDeparture=nil,nil
 e.intent.tractor=false;A.bindRoute(game,e,r)
 return true
end
-- Pirates carrying loot: home to the base, unload, then back to the hunting
-- grounds. Movement, docking and upkeep are the shared NPC loop's (src/npc.lua);
-- once back on the raid network the pirate is a 'security' job again.
local NPC=require('src.npc')
local function next(c)
 local u,r,clock=c.u,c.r,c.clock
 local duty=r.piracy
 local base=duty.base or Homes.get(r)
 if duty.phase=='escape' then
  if L.canonical(c.node)~=L.canonical(base) then
   local path=itinerary(c.node,base,clock)
   if path then return {route=path} end
  end
  P.unload(u,r)
  Supplies.refill(r,base)
  local path=itinerary(base,duty.origin,clock)
  if path and #path>1 then
   duty.phase='redeploy';r.taskStatus='returning to hunting grounds'
   return {route=path}
  end
 end
 -- Back where it set out (or no way back): rejoin the raid network.
 local area=L.get(c.node).area
 local rally=L.rally(area,c.node,clock)
 local path=rally and itinerary(c.node,rally,clock)
 r.piracy=nil;r.taskWorker=nil;r.taskStatus=nil;r.area=area
 if path and #path>1 then return {route=path} end
 return nil -- the shared loop roams it to a buoy
end
NPC.job('piracy',{
 match=function(r) return r.piracy~=nil end,
 docks=function(r,id) return r.piracy and r.piracy.phase=='escape' and L.canonical(id)==L.canonical(r.piracy.base or Homes.get(r)) end,
 stay=function() return T.pirateRest end,
 next=next,
 roam=function(r,node) local f=Fields[L.get(node).area];return f and f.buoyIds or {} end,
})
-- Kept for callers outside the loop: finish the current stop now.
function P.depart(u,r,clock)
 return NPC.decide(u,r,r.node or r.route[r.index],clock)
end
function P.advance(r,clock,u) return NPC.advance(r,clock,u) end
function P.think(game,e,dt,AI)
 if e.alifeRole~='pirate' then return false end
 local r=game.universe.npcs[e.alifeId];if not r then return false end
 Ship.ensureGridHold(e)
 if r.piracy then
  e.tractorTarget=nil;e.intent.tractor=false
  if e.alifeEgress or e.driverTractor or e.launch then AI.trade(game,e,dt);return true end
  AI.trade(game,e,dt);return true
 end
 -- Loot: the shared scavenging loop (src/scavenge.lua), then home to fence it.
 local Scavenge=require('src.scavenge')
 local now=game.universe.clock
 local hurt=e.armor<e.stats.armor*T.pirateRetreatHealth
 if Scavenge.taken(r)>0 and (Scavenge.done(r,now) or hurt) then
  if P.beginReturn(game,e,r) then AI.trade(game,e,dt);return true end
 end
 if hurt and Scavenge.taken(r)>0 then e.tractorTarget=nil;e.intent.tractor=false;return false end
 return Scavenge.think(game,e,dt,AI,r,NPC)
end
return P
