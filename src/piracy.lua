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
-- Fencing: stolen cargo is sold to the pirate's home station and becomes
-- that station's ordinary market stock (src/stockpile.lua), on the shelf
-- for the player and the dark economy alike. A crate is broken open: the
-- crate and what was in it are stocked separately. The pirate is paid the
-- station's own bid, cut to T.pirateFenceRate for the risk the house takes.
local function fence(u,base,id,n,sold)
 if n<=0 or not require('src.data').items[id] then return end
 require('src.stockpile').add(u,base,id,n)
 sold[id]=(sold[id] or 0)+n
end
local function fenceHold(u,base,inner,sold)
 local h=type(inner)=='string' and Hold.deserialize(inner) or inner
 if not h then return end
 for _,g in ipairs(h.grids) do for _,s in ipairs(g.stacks) do
  fence(u,base,s.id,s.n,sold)
  if s.inner then fenceHold(u,base,s.inner,sold) end
 end end
end
P.fenceHold=fenceHold
-- Raid targeting by shortage: does this ship carry something the dark
-- station is short of (src/economy.lua records shortages per station)?
-- Raiders prefer such prey and hunt where it flies.
function P.wants(u,home,prey)
 local short=home and (require('src.stockpile').record(u,home).shortages)
 if not short or not next(short) or not prey or not prey.ship then return false end
 for id,n in pairs(prey.ship.cargo or {}) do if n>0 and short[id] then return true end end
 return false
end
function P.home(r) return r.piracy and r.piracy.base or Homes.get(r) end
-- Saves from before fencing kept loot in a dead stash; stock it once.
function P.settle(u)
 local old=u.piracy;if not old then return end
 local sold={}
 for base,stash in pairs(old.stashes or {}) do
  -- a stash counts crates and their contents by item already, except
  -- what was inside a crate, which only the saved crate holds
  if L.byId[base] then
   for id,n in pairs(stash) do fence(u,base,id,n,sold) end
   for _,c in ipairs((old.containers or {})[base] or {}) do if c.inner then fenceHold(u,base,c.inner,sold) end end
  end
 end
 u.piracy=nil
 return sold
end
function P.unload(u,r)
 local base=r.piracy and r.piracy.base or Homes.get(r) or L.station(nil,'pirateBase')
 P.settle(u)
 local sold={}
 local h=r.ship.hold and Hold.deserialize(r.ship.hold,function(id)return require('src.data').items[id]~=nil end)
 local cargo=h and Hold.totals(h) or r.ship.cargo or {}
 -- Stolen stacks (crates included) go first, then count-based cargo.
 if h then
  for _,g in ipairs(h.grids) do for i=#g.stacks,1,-1 do
   local s=g.stacks[i]
   if s.stolen then
    fence(u,base,s.id,s.n,sold)
    if s.inner then fenceHold(u,base,s.inner,sold) end
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
   fence(u,base,id,n,sold)
  end
 end
 if h then r.ship.hold=Hold.serialize(h);cargo=Hold.totals(h) end
 r.ship.cargo=cargo;r.stolenCargo={};r.lootUntil=nil
 local Markets=require('src.markets')
 local paid=0
 for id,n in pairs(sold) do paid=paid+Markets.price(u,base,id)*(1-T.marketSpread)*T.pirateFenceRate*n end
 paid=math.floor(paid+.5)
 if next(sold) then
  paid=require('src.accounts').pay(u,base,paid,'fenced')
  r.credits=(r.credits or 0)+paid
  require('src.simulation_history').note(u,'pirate_fenced',u.clock or 0,L.byId[base] and L.byId[base].area,{r.id},{station=base,goods=sold,paid=paid},base)
 end
 return sold,paid
end
function P.returnRecord(game,r)
 if r.piracy then return true end
 -- a wildcat takes its loot back to its site (src/wildcats.lua)
 if r.wildcat then return require('src.wildcats').goHome(game,r,'loot') end
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
   local path=G.live(c.node,base,clock)
   if path then return {route=path} end
  end
  P.unload(u,r)
  Supplies.refill(r,base)
  if r.wildcat then require('src.wildcats').atFence(u,r,base) end
  local path=G.live(base,duty.origin,clock)
  if path and #path>1 then
   duty.phase='redeploy';r.taskStatus='returning to hunting grounds'
   return {route=path}
  end
 end
 -- a wildcat's fence run is over: back to its site
 if r.wildcat and r.wildcat.fencing then return require('src.wildcats').fenced(c) end
 -- Back where it set out (or no way back): rejoin the raid network.
 local area=L.get(c.node).area
 local rally=L.rally(area,c.node,clock)
 local path=rally and G.live(c.node,rally,clock)
 r.piracy=nil;Tasks.release(u,r,'completed',clock);r.taskWorker=true;r.taskStatus=nil;r.area=area
 require('src.security').ensureRaids(u,area)
 if path and #path>1 then return {route=path} end
 return nil -- the shared idle policy returns it to its home base
end
-- Sent out from the base (a new raider, or one rested and refitted): the
-- same redeploy leg a fence run ends with, to a rally point in the region
-- it will hunt.
function P.deploy(game,r,base,area)
 local clock=game.universe.clock
 local rally=L.rally(area,base,clock)
 if not rally or not itinerary(base,rally,clock) then return false end
 r.piracy={phase='redeploy',base=base,origin=rally,started=clock}
 r.task={id='deploy/'..r.id..'/'..clock,kind='deploy',source=base,target=rally}
 r.taskWorker=true;r.taskStatus='heading out to '..L.get(rally).name;r.area=L.get(base).area
 require('src.alife_trace').note(r,clock,'piracy','deploying to '..area)
 return NPC.travel(game,r,rally,clock)
end
Tasks.register('deploy',{
 requires={capabilities={'armed'}},
 docks=function() return false end,
 complete=function() return false end,
 continue=next,
})
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
