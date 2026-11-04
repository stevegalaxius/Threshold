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
local P={}
local function itinerary(source,target,clock)
 if source==target then return {source} end
 local from,to=L.get(source).area,L.get(target).area
 if from~=to then
  local moon=Fields.moons[from]
  if moon then
   local gate=from..'/to_'..moon.parent
   local path=itinerary(source,gate,clock)
   local rest=itinerary(moon.parent..'/to_'..from,target,clock)
   if not path or not rest then return end
   for _,id in ipairs(rest) do path[#path+1]=id end
   return path
  end
  moon=Fields.moons[to]
  if moon then
   local path=itinerary(source,moon.parent..'/to_'..to,clock)
   local rest=itinerary(to..'/to_'..moon.parent,target,clock)
   if not path or not rest then return end
   for _,id in ipairs(rest) do path[#path+1]=id end
   return path
  end
  return require('src.transport').route(source,target,clock)
 end
 local path=G.route(G.build(L.get(source).area),source,target,clock)
 if not path then return end
 local result={source};for _,leg in ipairs(path.legs) do result[#result+1]=leg.edge.to end
 return result
end
P.route=itinerary
function P.unload(u,r)
 local stashState=u.piracy or {stashes={}};u.piracy=stashState
 local stash=stashState.stashes[T.pirateBase] or {};stashState.stashes[T.pirateBase]=stash
 local h=r.ship.hold and Hold.deserialize(r.ship.hold,function(id)return require('src.data').items[id]~=nil end)
 local cargo=h and Hold.totals(h) or r.ship.cargo or {}
 -- Loaded containers are transferred as stacks, before count-based cargo.
 if h then
  stashState.containers=stashState.containers or {}
  local containers=stashState.containers[T.pirateBase] or {};stashState.containers[T.pirateBase]=containers
  for _,g in ipairs(h.grids) do for i=#g.stacks,1,-1 do
   local s=g.stacks[i]
   if s.stolen then
    local destination=containers
    if not s.inner then
     stashState.stacks=stashState.stacks or {};stashState.stacks[T.pirateBase]=stashState.stacks[T.pirateBase] or {}
     destination=stashState.stacks[T.pirateBase]
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
function P.beginReturn(game,e,r)
 if r.piracy then return true end
 local A=require('src.alife')
 if r.encounter then require('src.encounters').finish(game.universe,r,game.universe.npcs[r.encounter.target],game.universe.clock,r) end
 A.capture(game,e,false)
 local source=r.state=='travel' and r.route[r.index] or r.node or r.route[r.index]
 local path=itinerary(source,T.pirateBase,game.universe.clock)
 if not path then r.taskStatus='no route to Milliways';return false end
 Tasks.release(game.universe,r,'returning with loot',game.universe.clock)
 r.piracy={phase='escape',origin=Fields[r.home].stationIds[1],started=game.universe.clock}
 r.taskWorker=true;r.taskStatus='escape to Milliways Freeport'
 if r.state=='travel' then
  local previous=r.route[(r.index-2)%#r.route+1]
  r.route={previous};for _,id in ipairs(path) do r.route[#r.route+1]=id end;r.index=2
 else
  r.route=path;r.index=1
  if #path>1 then A.start(r,game.universe.clock,2)
  else r.state='docked';r.untilTime=game.universe.clock+T.pirateRest end
 end
 e.combatTarget,e.lock,e.aggressor,e.tractorTarget=nil,nil,nil,nil
 e.intent.tractor=false;A.bindRoute(game,e,r)
 return true
end
-- Finish a stop, using the same route whether online or remote.
function P.depart(u,r,clock,start)
 local duty=r.piracy
 if not duty then return end
 if duty.phase=='escape' then
  P.unload(u,r)
  local path=itinerary(T.pirateBase,duty.origin,clock)
  if not path then r.taskStatus='waiting for route home';return false end
  duty.phase='redeploy';r.taskStatus='returning to hunting grounds'
  r.route=path;r.index=1
  if #path>1 then start(r,clock,2);return true end
 end
 -- Restore the existing pirate raid lifecycle at a reachable local buoy.
 local area=L.get(duty.origin).area;local f=Fields[area]
 local rally=f.buoyIds[1] or f.driverId
 local path=rally and itinerary(duty.origin,rally,clock)
 if not path or #path<2 then r.untilTime=clock+10;return false end
 r.piracy=nil;r.taskWorker=nil;r.taskStatus=nil;r.area=area
 r.route=path;r.index=1;start(r,clock,2)
 return true
end
function P.advance(r,clock,u,start)
 if r.state=='dead' or r.state=='escaped' or r.encounter then return end
 for _=1,128 do
  if r.state=='travel' or r.state=='transit' then
   if clock<r.arrive then return end
   local at=r.arrive
   if r.index<#r.route then start(r,at,r.index+1)
   else
    r.area=L.get(r.route[r.index]).area;r.transit=nil;r.state='docked';r.node=r.route[r.index]
    r.untilTime=at+T.pirateRest
   end
  elseif r.state=='docked' then
   if clock<r.untilTime then return end
   if not P.depart(u,r,r.untilTime,start) then return end
   if not r.piracy then return end
  else return end
 end
end
function P.think(game,e,dt,AI)
 if e.alifeRole~='pirate' then return false end
 local r=game.universe.npcs[e.alifeId];if not r then return false end
 Ship.ensureGridHold(e)
 if r.piracy then
  e.tractorTarget=nil;e.intent.tractor=false
  if e.alifeEgress or e.driverTractor or e.launch then AI.trade(game,e,dt);return true end
  AI.trade(game,e,dt);return true
 end
 -- Keep decisions bounded; pursuit and the beam itself still update each frame.
 local now=game.universe.clock
 local stolen=0;for _,n in pairs(r.stolenCargo or {}) do stolen=stolen+n end
 if stolen>0 and (stolen>=T.pirateLootUnits or now>=(r.lootUntil or 0) or e.armor<e.stats.armor*T.pirateRetreatHealth) then
  if P.beginReturn(game,e,r) then AI.trade(game,e,dt);return true end
 end
 local refresh=(e.pirateLootThink or 0)<=game.time
 if refresh then
  e.pirateLootThink=game.time+T.securityThink
  local previous=e.piratePickup;e.piratePickup=nil
  local x,y=e.body:getPosition();local distance=T.pirateLootRange^2
  for _,pickup in ipairs(game.pickups) do
   local owner=pickup.collector
   if not pickup.inner and pickup.count>0 and (not owner or owner==e or owner.dead or owner.removed or owner.tractorTarget~=pickup)
    and Ship.canFit(e,pickup.item,pickup.count)>0 then
    local d=(pickup.x-x)^2+(pickup.y-y)^2
    if d<distance then distance=d;e.piratePickup=pickup end
   end
  end
  if previous and previous~=e.piratePickup and previous.collector==e then previous.collector=nil end
  e.pirateContainer=nil
  for _,box in ipairs(game.entities) do
   if box.kind=='container' and box~=game.looting and not box.dead and not box.removed
    and (not box.lootCollector or box.lootCollector==e or box.lootCollector.dead or box.lootCollector.removed or box.lootCollector.pirateContainer~=box)
    and Loot.canTake(e,box) then
    local bx,by=box.body:getPosition();local d=(bx-x)^2+(by-y)^2
    if d<distance then e.pirateContainer=box;e.piratePickup=nil;distance=d end
   end
  end
 end
 local box=e.pirateContainer
 if box and not box.dead and not box.removed and box~=game.looting then
  local x,y=e.body:getPosition();local bx,by=box.body:getPosition();local vx,vy=box.body:getLinearVelocity()
  local dx,dy=bx-x,by-y;local d=math.sqrt(dx*dx+dy*dy)
  AI.navigate(game,e,dx,dy,math.min(400,math.max(0,(d-100)*.6)),vx,vy,d)
  e.intent.aimX,e.intent.aimY=bx,by;e.intent.tractor=true;e.tractorTarget=nil
  box.lootCollector=e;r.taskStatus='looting a cargo container'
  Loot.pull(game,e,box,dt)
  return true
 end
 local pickup=e.piratePickup
 local exists=false;for _,p in ipairs(game.pickups) do if p==pickup then exists=true;break end end
 if not exists or not pickup or pickup.count<=0 then
  e.intent.tractor=false;e.tractorTarget=nil
  -- Wrecks retain real cargo until broken open; fire on the wreck rather
  -- than copying its inventory into the pirate's hold.
  local wreck=e.pirateWreck
  if wreck and (wreck.dead or wreck.removed or not wreck.body or wreck.body:isDestroyed()) then wreck=nil end
  local range=T.pirateLootRange^2
  local x,y=e.body:getPosition()
  if refresh then
  wreck=nil
  for _,o in ipairs(game.entities) do
   if o.kind=='husk' and not o.dead and not o.removed and o.body and not o.body:isDestroyed() then
    local wx,wy=o.body:getPosition();local d=(wx-x)^2+(wy-y)^2
    if d<range then wreck,range=o,d end
   end
  end
  end
  if not wreck then e.pirateWreck=nil;return false end
  local wx,wy=wreck.body:getPosition();range=(wx-x)^2+(wy-y)^2
  if range>T.pirateLootRange^2 then e.pirateWreck=nil;return false end
  if e.pirateWreck~=wreck then e.pirateWreck=wreck;e.pirateSalvageUntil=now+T.pirateLootTime end
  if now>e.pirateSalvageUntil then return false end
  local wx,wy=wreck.body:getPosition();local d=math.sqrt(range)
  local vx,vy=wreck.body:getLinearVelocity()
  AI.navigate(game,e,wx-x,wy-y,math.max(0,math.min(400,(d-400)*.6)),vx,vy,d)
  e.intent.aimX,e.intent.aimY=wx,wy;e.lock=nil
  e.intent.firePrimary=d<(e.def.ai.range or 700)
  r.taskStatus='breaking open a wreck'
  return true
 end
 if e.armor<e.stats.armor*T.pirateRetreatHealth then
  e.tractorTarget=nil;e.intent.tractor=false
  return P.beginReturn(game,e,r) and (AI.trade(game,e,dt) or true) or false
 end
 local x,y=e.body:getPosition();local dx,dy=pickup.x-x,pickup.y-y
 local d=math.sqrt(dx*dx+dy*dy);local range=Ship.tractorRange(e)
 AI.navigate(game,e,dx,dy,math.min(e.def.ai.cruise or 600,math.max(20,(d-range*.5)*.6)),pickup.vx,pickup.vy,d)
 e.intent.aimX,e.intent.aimY=pickup.x,pickup.y;e.intent.firePrimary=false
 local near=Ship.distanceTo(e,pickup.x,pickup.y)<=range
 e.intent.tractor=near;e.tractorTarget=near and pickup or nil
 if near then pickup.collector=e end
 r.taskStatus='collecting exposed cargo'
 return true
end
require('src.events').on('pickup',function(e,item,n,stack)
 if e.alifeRole~='pirate' or not e.alifeRecord or e.alifeRecord.piracy then return end
 if stack and (stack.inner or stack.wear~=nil) then stack.stolen=true end
 local r=e.alifeRecord;r.stolenCargo=r.stolenCargo or {};r.stolenCargo[item]=(r.stolenCargo[item] or 0)+n
 r.lootUntil=r.lootUntil or (e.alifeGame.universe.clock+T.pirateLootTime)
end)
return P
