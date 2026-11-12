-- Cargo acquisition and return-to-storage work.
local T=require('src.tuning')
local L=require('src.locations')
local G=require('src.travelgraph')
local Fields=require('src.fields')
local Hold=require('src.inventory.hold')
local Tasks=require('src.tasks')
local Loot=require('src.loot')
local Grid=require('src.inventory.grid')
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
 r.task={id='fence/'..r.id..'/'..game.universe.clock,kind='fence',source=source,target=base}
 r.taskWorker=true;r.taskStatus='returning to '..L.get(base).name
 return require('src.npc').travel(game,r,base,game.universe.clock)
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
-- after returning, the shared controller selects the next eligible job.
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
 r.piracy=nil;Tasks.release(u,r,'completed',clock);r.taskWorker=true;r.taskStatus=nil;r.area=area
 if path and #path>1 then return {route=path} end
 return nil -- the shared idle policy returns it to its home base
end
Tasks.register('fence',{
 requires={capabilities={'cargo'}},
 docks=function(r,id) return r.piracy and r.piracy.phase=='escape' and L.canonical(id)==L.canonical(r.piracy.base or Homes.get(r)) end,
 stay=function() return T.pirateRest end,
 complete=function() return false end,
 continue=next,
})
-- Kept for callers outside the loop: finish the current stop now.
function P.depart(u,r,clock)
 return NPC.decide(u,r,r.node or r.route[r.index],clock)
end
function P.advance(r,clock,u) return NPC.advance(r,clock,u) end
function P.before(ctx)
 local r=ctx.r
 if r.piracy then return end
 local Scavenge=require('src.scavenge')
 local hurt=ctx.e and ctx.e.armor<ctx.e.stats.armor*T.pirateRetreatHealth
 if Scavenge.taken(r)>0 and (Scavenge.done(r,ctx.clock) or hurt) then
  P.returnRecord(ctx.game,r);return
 end
end
function P.nextAction(ctx)
 P.before(ctx)
 if not ctx.r.piracy then return require('src.scavenge').nextAction(ctx) end
end
return P
