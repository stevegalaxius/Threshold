-- Saved resources have a single authority: live scenes or remote records.
local Hold=require('src.inventory.hold')
local Ship=require('src.ship')
local Stats=require('src.stats')
local data=require('src.data')
local G=require('src.travelgraph')
local T=require('src.tuning')
local Persistence=require('src.persistence')
local Loot=require('src.loot')
local Loose=require('src.loose')
local Scavenge=require('src.scavenge')
local Actions=require('src.npc_actions')
local Wreck=require('src.wreck_salvage')
require('src.npc_operations')
local O={}
local function retained(game,area)
 if game.fieldId==area then return true end
 for _,side in ipairs(game.sideScenes and game:sideScenes() or {}) do
  if side.scene.fieldId==area then return true end
 end
 return false
end
local function sourceHold(game,wreck)
 if not wreck.lootHold then
  local s=wreck.ship;local hull=data.hulls[s.hull]
  local actor={hull=hull,loadout=s.loadout,cargo=s.cargo or {},stats=Stats.compute(hull,s.loadout),def=data.enemies[wreck.archetype],
   hold=s.hold and Hold.deserialize(s.hold)}
  if actor.hold then actor.cargo=Hold.totals(actor.hold) end
  wreck.lootHold=Hold.serialize(game.huskHold(actor));wreck.salvagedSlots=actor.salvagedSlots
 end
 return Hold.deserialize(wreck.lootHold)
end
local function cargoMass(hold)
 local mass=Hold.innerMass(hold,data.items)
 for id,n in pairs(Hold.totals(hold)) do mass=mass+data.items[id].mass*n end
 return mass
end
local function recipient(r)
 local hull=data.hulls[r.ship.hull]
 local actor={hull=hull,loadout=r.ship.loadout,cargo=r.ship.cargo or {},stats=Stats.compute(hull,r.ship.loadout)}
 if r.ship.hold then actor.hold=Hold.deserialize(r.ship.hold) else
  actor.hold=Hold.new(Ship.holdLayout(actor))
  for id,n in pairs(actor.cargo) do if Hold.add(actor.hold,id,n)~=n then return end end
 end
 return actor.hold
end
local function candidates(game,r,clock)
 local result={}
 for id,w in pairs(game.universe.alifeWrecks or {}) do
  if w.area==r.area and clock<w.expires then
   local x,y=G.wreckPoint(w,clock)
   local visible=false
   if game.fieldId==w.area and game.player and not game.player.dead then
    local px,py=game.player.body:getPosition();visible=(x-px)^2+(y-py)^2<T.alifeNear^2
   end
   if not visible then result[#result+1]={kind='combat',id=id,record=w,x=x,y=y} end
  end
 end
 if not retained(game,r.area) then
  local area=game.universe.areas and game.universe.areas[r.area]
  if area then
   for _,saved in ipairs(area.objects or {}) do
    local pose=Persistence.advanceRecord(saved,math.max(0,clock-area.capturedAt))
    result[#result+1]={kind='objects',id=saved.id,record=saved,x=pose.x,y=pose.y,list=area.objects}
   end
  end
 end
 -- Wrecks lying in the loaded area beyond the player's view: real husks,
 -- which an offline clean-up crew works like records (kind 'live').
 if Scavenge.profile(r) and Scavenge.profile(r).clears and game.fieldId==r.area and game.entities then
  local px,py
  if game.player and not game.player.dead then px,py=game.player.body:getPosition() end
  for _,o in ipairs(game.entities) do
   if o.kind=='husk' and o.origin and not o.dead and not o.removed and o~=game.looting and o.body and not o.body:isDestroyed() then
    local x,y=o.body:getPosition()
    if not px or (x-px)^2+(y-py)^2>=T.alifeNear^2 then
     o.liveLootId=o.liveLootId or ('live/'..tostring(o.id))
     result[#result+1]={kind='live',id=o.liveLootId,record=o,x=x,y=y}
    end
   end
  end
 end
 -- Loose items: one record each, whether or not their area is loaded. Any
 -- without a live view are fair game for an offline collector.
 if r.area then
  for _,loose in ipairs(Loose.offline(game,r.area,clock)) do
   result[#result+1]={kind='pickups',id=loose.record.id,record=loose.record,x=loose.x,y=loose.y}
  end
 end
 return result
end
local function remove(game,source)
 if source.kind=='pickups' then Loose.remove(game.universe,source.id);return end
 if source.kind=='live' then game:remove(source.record);return end
 if source.list then for i,s in ipairs(source.list) do if s==source.record then table.remove(source.list,i);break end end end
end
function O.release(game,r,clock)
 Actions.cancel({game=game,u=game.universe,r=r,clock=clock},'collection ended')
end
-- Wrecks of ships that died (not authored derelicts): a clean-up crew
-- strips these and hauls the hull away.
local function clearable(prof,s)
 return prof and prof.clears and (s.kind=='combat' or s.kind=='live' or s.kind=='objects' and s.record.kind=='husk' and s.record.origin~=nil)
end
-- The hold behind a source: a live husk's own (changed in place), else a copy
local function holdOf(game,s)
 if s.kind=='live' then return s.record.hold end
 if s.kind=='combat' then return sourceHold(game,s.record) end
 return s.record.hold and Hold.deserialize(s.record.hold)
end
local function bare(game,s)
 local h=holdOf(game,s)
 return not h or not next(Hold.totals(h))
end
local function canTake(game,dest,s)
 if s.kind=='pickups' then return Hold.room(dest,s.record.item,1)>0 end
 local h=holdOf(game,s);if not h then return false end
 if s.kind=='live' then h=Hold.clone(h) end
 if s.record.kind=='container' and Hold.placeStack(Hold.clone(dest),{id=s.record.item,n=1,inner=h}) then return true end
 return Loot.takeStack(Hold.clone(dest),Hold.deserialize(Hold.serialize(h)))>0
end
-- Shared availability query for deciding whether a collector's local sweep is done.
function O.hasLoot(game,r,clock)
 local ctx={game=game,u=game.universe,r=r,clock=clock,e=game.alifeOnline and game.alifeOnline[r.id]}
 return O.find(ctx)~=nil
end
local function world(ctx) return ctx.game or {universe=ctx.u} end
local function descriptor(source,area)
 if source.kind=='pickups' then return {provider='resource',id=source.id,expected='loot'} end
 return {provider='loot',source=source.kind,id=source.id,area=area}
end
local function sourceTarget(ctx,source)
 local record=source.record
 local x,y=source.x,source.y
 local vx,vy=0,0
 local noSurface=false
 if source.kind=='live' then
  if ctx.e and record.kind=='husk' then
   -- A dismantled/hollow hull need not have a fixture at its body origin.
   -- Aim at a remaining collision surface, cached until that piece breaks.
   local aim=ctx.e.recoveryAim
   if not aim or aim.object~=record or aim.fixture:isDestroyed() then
    aim=nil;local sx,sy=ctx.e.body:getPosition();local best=math.huge
    for _,fixture in ipairs(record.body:getFixtures()) do
     if not fixture:isSensor() then
      local lx,ly=fixture:getShape():computeMass(1)
      local wx,wy=record.body:getWorldPoint(lx,ly);local distance=(wx-sx)^2+(wy-sy)^2
      if distance<best then best=distance;aim={object=record,fixture=fixture,x=lx,y=ly} end
     end
    end
    ctx.e.recoveryAim=aim
   end
   if aim then x,y=record.body:getWorldPoint(aim.x,aim.y) else noSurface=true end
  end
  vx,vy=record.body:getLinearVelocityFromWorldPoint(x,y)
 end
 return {record=record,source=source,entity=source.kind=='live' and record or nil,
  x=x,y=y,vx=vx,vy=vy,radius=record.radius or 0,
  done=noSurface or (source.kind=='combat' or record.kind=='husk') and not Wreck.weapon(ctx.e or ctx.r.ship)}
end
Actions.registerTarget('loot',{resolve=function(ctx,t)
 local game=world(ctx)
 if t.source=='live' then
  if t.area~=ctx.r.area or game.fieldId~=t.area then return end
  for _,e in ipairs(game.entities or {}) do
   if (e.id==t.id or e.liveLootId==t.id) and not e.dead and not e.removed and e.body and not e.body:isDestroyed() then
    local x,y=e.body:getPosition()
    if not ctx.e and game.player and not game.player.dead then
     local px,py=game.player.body:getPosition()
     if (x-px)^2+(y-py)^2<T.alifeNear^2 then return end
    end
    return sourceTarget(ctx,{kind='live',id=t.id,record=e,x=x,y=y})
   end
  end
  return
 end
 for _,source in ipairs(candidates(game,ctx.r,ctx.clock)) do
  if source.kind==t.source and source.id==t.id then return sourceTarget(ctx,source) end
 end
end})
function O.find(ctx)
 local r,game=ctx.r,world(ctx)
 local prof=Scavenge.profile(r);if not prof then return end
 local dest=recipient(r);if not dest then return end
 local x,y=Actions.actorPosition(ctx);if not x then return end
 local best=Scavenge.range(prof)^2;local selected
 local function consider(source)
  local spec=descriptor(source,ctx.r.area)
  local target=Actions.resolve(ctx,{target=spec})
  -- A broken-off piece can cover the centre of the wreck it came from.
  -- Recover the occluding piece first instead of claiming an unreachable core.
  if ctx.e and target and target.entity and target.entity.kind=='husk' then
   local weapon=Wreck.weapon(ctx.e);if not weapon then return end
   local wx,wy=Ship.hardpoint(ctx.e,weapon.slot);local seen={}
   while target and target.entity and target.entity.kind=='husk' do
    if seen[target.entity] then return end
    seen[target.entity]=true
    local hit=game:raycast(wx,wy,target.x,target.y,ctx.e.team)
    if not hit or hit.entity==target.entity or hit.entity.kind~='husk' then break end
    if not prof.wrecks or prof.clears and not hit.entity.origin then return end
    spec=descriptor({kind='live',id=hit.entity.id},ctx.r.area)
    target=Actions.resolve(ctx,{target=spec})
   end
  end
  if not target or target.done or not Actions.available(ctx,target) or Actions.sinking(ctx.r,target.x,target.y) then return end
  local s=target.source
  if s and (s.kind=='combat' or s.record.kind=='husk') and not Wreck.weapon(ctx.e or r.ship) then return end
  local d=(target.x-x)^2+(target.y-y)^2
  if d<best then best=d;selected=spec end
 end
 if ctx.e then
  for _,p in ipairs(game.pickups or {}) do
   if p.looseId and not p.inner and p.count>0 and Ship.canFit(ctx.e,p.item,1)>0 then consider({kind='pickups',id=p.looseId}) end
  end
  for _,e in ipairs(game.entities or {}) do
   if not e.dead and not e.removed and e.body and not e.body:isDestroyed() and e~=game.looting then
    if e.kind=='container' and Loot.canTake(ctx.e,e) or e.kind=='husk' and prof.wrecks and (not prof.clears or e.origin) and (prof.clears or next(e.loot or {})) then
     consider({kind='live',id=e.id})
    end
   end
  end
 else
  for _,source in ipairs(candidates(game,r,ctx.clock)) do
   if canTake(game,dest,source) or clearable(prof,source) and bare(game,source) then consider(source) end
  end
 end
 return selected
end
function O.nextAction(ctx)
 local r=ctx.r
 if r.piracy or r.salvageReturn or r.service or r.worldRecovery or r.state=='docked' or Scavenge.done(r,ctx.clock) then return end
 if r.action and r.action.kind=='work' then return r.action end
 if ctx.clock<(r.lootCheckAt or 0) then return end
 r.lootCheckAt=ctx.clock+T.securityThink
 local target=O.find(ctx);if not target then return end
 local prof=Scavenge.profile(r)
 return {kind='work',operation=target.provider=='resource' and 'collect' or 'recover',target=target,
  clearWreck=prof.clears,markStolen=prof==Scavenge.PROFILES.pirate}
end
-- Inventory effects only. The shared runner owns approach, claims and time.
local function take(ctx,target)
 local game,r,clock=world(ctx),ctx.r,ctx.clock
 local source=target.source;local prof={clears=ctx.r.action.clearWreck}
 local dest=recipient(r);if not dest then return 'failed','no hold' end
 local n,id,moved=0
 local record=source.record
 if source.kind=='pickups' then
  id=record.item;n=Hold.add(dest,id,record.count);record.count=record.count-n
  if record.count==0 then remove(game,source) end
 else
  local h=holdOf(game,source)
  local oldMass=cargoMass(h)
  local wreck=source.kind=='combat' or record.kind=='husk'
  local weapon=wreck and Wreck.weapon(r.ship)
  if wreck and not weapon then return 'failed','no usable wreck-breaking weapon' end
  local drilled=weapon and weapon.w.kind=='drill'
  if wreck and not drilled then record.drilled=false end
  if wreck and not drilled and not record.shotSalvage then
   -- Remote stripping uses the same yield, rolled once and saved with the
   -- source so loading the area or claiming it again cannot reroll its cargo.
   for _,g in ipairs(h.grids) do for i=#g.stacks,1,-1 do
    local stack=g.stacks[i];stack.n=Wreck.survivors(stack.n,false)
    if stack.n==0 then require('src.inventory.grid').remove(g,stack) end
   end end
   record.shotSalvage=true
   if source.kind=='combat' then record.lootHold=Hold.serialize(h)
   elseif source.kind=='live' then record.loot=Hold.totals(h)
   else record.hold=Hold.serialize(h) end
  end
  if record.kind=='container' then
   moved={id=record.item,n=1,inner=h}
   if Hold.placeStack(dest,moved) then n,id=1,record.item;remove(game,source) else moved=nil end
  end
  if n==0 then
   n,id,moved=Loot.takeStack(dest,h)
   if n==0 and clearable(prof,source) and not next(Hold.totals(h)) then
    -- stripped bare: the clean-up crew drills the hull apart for its steel
    -- (the same fixed yield a live wreck gives: Game.wreckSteel)
    local hullId=source.kind=='combat' and record.ship and record.ship.hull or source.kind=='live' and record.hull.id or record.hull
    local steel=source.kind=='live' and (record.steel or 0) or require('src.game').wreckSteel(data.hulls[hullId])
    local got=drilled and Hold.add(dest,'steel_plate',steel) or 0
    if got>0 then r.ship.hold=Hold.serialize(dest);r.ship.cargo=Hold.totals(dest);Actions.pickedUp(ctx,'steel_plate',got) end
    if source.kind=='combat' then game.universe.alifeWrecks[source.id]=nil else remove(game,source) end
    require('src.events').emit('wreck_cleared',r,source.record)
    return 'done'
   end
   if n>0 then
    if source.kind=='combat' then
     record.lootHold=Hold.serialize(h)
    elseif source.kind=='live' then
     record.loot=Hold.totals(h)
    else
     record.hold=Hold.serialize(h)
     if record.mass then
      local previous=record.mass[3];local current=math.max(1,previous-(oldMass-cargoMass(h))*T.massScale)
      record.mass[3]=current;record.mass[4]=record.mass[4]*current/previous
     end
    end
   end
  end
 end
 if n==0 then
  if record.shotSalvage and not next(Hold.totals(holdOf(game,source))) then return 'done' end
  return 'failed','hold full'
 end
 if ctx.r.action.markStolen and moved and (moved.inner or moved.wear~=nil) then moved.stolen=true end
 r.ship.hold=Hold.serialize(dest);r.ship.cargo=Hold.totals(dest)
 Actions.pickedUp(ctx,id,n,moved)
 r.taskStatus=prof.clears and 'stripping a wreck' or 'looting saved cargo'
 return 'done'
end
local function recoverLive(ctx,target,dt,a)
 local e,object=ctx.e,target.entity
 if not object then return Actions.recordOperation(ctx,function() return take(ctx,target) end) end
 Ship.ensureGridHold(e)
 e.intent.firePrimary,e.intent.fireSecondary,e.intent.fireTertiary=false,false,false
 e.recoveryWeapon,e.recoveryTarget=nil,nil;e.intent.tractor=false;e.tractorTarget=nil
 if object.kind=='container' then
  if not Loot.canTake(e,object) then return 'failed','nothing recoverable or hold full' end
  object.lootCollector=e
  local n=Loot.pull(ctx.game,e,object,dt)
  return n>0 and 'done' or 'running'
 end
 local weapon=Wreck.weapon(e)
 if not weapon then return 'failed','no usable wreck-breaking weapon' end
 local wx,wy=Ship.hardpoint(e,weapon.slot)
 local hit=ctx.game:raycast(wx,wy,target.x,target.y,e.team)
 if hit and hit.entity~=object and hit.entity.kind=='husk' then return 'failed','another wreck blocks recovery' end
 ctx.r.taskStatus=weapon.w.kind=='drill' and 'stripping a wreck' or 'shooting a wreck'
 local prof={clears=a.clearWreck}
 if prof.clears and weapon.w.kind=='drill' and object.hold and next(object.loot or {}) then
  if ctx.clock<(a.nextTransfer or 0) then return 'running' end
  a.nextTransfer=ctx.clock+.5
  local n,id,moved=Loot.takeStack(e.hold,object.hold)
  if n<=0 then return 'failed','hold full' end
  e.cargo=Hold.totals(e.hold);Ship.updateMass(e);object.loot=Hold.totals(object.hold)
  require('src.events').emit('pickup',e,id,n,moved)
  return 'done'
 end
 local x,y=e.body:getPosition();local angle=e.body:getAngle()
 local bearing=math.atan2(target.y-y,target.x-x)
 e.intent.aimX,e.intent.aimY=target.x,target.y
 if e.hull.helm=='turn' then
  ctx.AI.faceDirection(e,target.x-x,target.y-y)
 end
 local diff=(bearing-angle-(weapon.aim or 0)+math.pi)%(2*math.pi)-math.pi
 e.recoveryWeapon=weapon
 e.recoveryTarget=object
 e.recoveryLocalX,e.recoveryLocalY=object.body:getLocalPoint(target.x,target.y)
 local trigger=({primary='firePrimary',secondary='fireSecondary',tertiary='fireTertiary'})[weapon.group]
 if trigger then e.intent[trigger]=math.abs(diff)<.2 and (not hit or hit.entity==object) end
 e.intent.targetDist=nil
 return 'running'
end
Actions.registerOperation('recover',{
 inRange=function(ctx,target,a)
  local e=ctx.e;local object=target.entity
  if not object or object.kind=='container' then
   return Ship.distanceTo(e,target.x,target.y)-(target.radius or 0)<=Ship.tractorRange(e)
  end
  local weapon=Wreck.weapon(e)
  if not weapon then return true end -- let the operation finish with its reason
  if a.clearWreck and weapon.w.kind=='drill' and next(object.loot or {}) then
   return Ship.distanceTo(e,target.x,target.y)-(target.radius or 0)<=Ship.tractorRange(e)
  end
  local wx,wy=Ship.hardpoint(e,weapon.slot)
  local hit=ctx.game:raycast(wx,wy,target.x,target.y,e.team)
  if hit and hit.entity~=object and hit.entity.kind=='husk' then return true end -- release/reselect the obstructed target
  if not hit or hit.entity~=object then return false end
  local reach=weapon.w.kind=='drill' and require('src.weapons').drillLength(e,weapon.w) or require('src.weapons').range(weapon)
  return (hit.x-wx)^2+(hit.y-wy)^2<=reach*reach
 end,
 keepDistance=function(ctx,target) return target.entity and target.entity.kind=='husk' end,
 distance=function(ctx,target)
  if not ctx.e then return 0 end
  local e=ctx.e
  local prof={clears=ctx.r.action.clearWreck}
  local weapon=target.entity and target.entity.kind=='husk' and Wreck.weapon(e)
  if weapon and weapon.w.kind~='drill' then
   return math.max((target.radius or 0)+(e.halfLength or 0)+80,math.min(700,require('src.weapons').range(weapon)*.6))
  end
  if target.entity and target.entity.kind=='husk' and not prof.clears then
   return math.max((target.radius or 0)+(e.halfLength or 0)+25,(e.def.ai.range or 700)*.6)
  end
  if target.entity and target.entity.kind=='husk' and not next(target.entity.loot or {}) then
   return (target.radius or 0)+(e.noseX or e.halfLength)+25
  end
  return math.max((target.radius or 0)+(e.halfLength or 0)+25,Ship.tractorRange(e)*.5+(e.halfLength or 0))
 end,
 offline=take,
 online=recoverLive,
 missing=function(ctx,a) return (a.progress or 0)>0 and 'done' or 'failed','target disappeared' end,
})
-- Convenience entry for resource/debug callers, using the common action runner.
function O.update(game,r,clock)
 return require('src.npc').runActions({game=game,u=game.universe,r=r,clock=clock})
end
return O
