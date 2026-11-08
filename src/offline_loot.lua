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
local O={}
local function retained(game,area)
 return game.fieldId==area or game.trip and game.trip.originScene and game.trip.originScene.fieldId==area
  or game.arrivalPreview and game.arrivalPreview.game.fieldId==area
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
  if r.role~='salvager' and w.area==r.area and clock<w.expires then
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
   if r.role~='salvager' then
    for _,saved in ipairs(area.objects or {}) do
     local pose=Persistence.advanceRecord(saved,math.max(0,clock-area.capturedAt))
     result[#result+1]={kind='objects',id=saved.id,record=saved,x=pose.x,y=pose.y,list=area.objects}
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
 if source.list then for i,s in ipairs(source.list) do if s==source.record then table.remove(source.list,i);break end end end
end
local function available(game,r,s)
 local owner=s.record.lootOwner and game.universe.npcs[s.record.lootOwner]
 return not owner or owner==r or owner.state=='dead' or owner.state=='escaped' or not owner.offlineLoot
  or owner.offlineLoot.kind~=s.kind or owner.offlineLoot.id~=s.id or owner.area~=r.area
end
function O.position(r,clock)
 local job=r.offlineLoot
 if not job or not job.x then return end
 local fraction=math.max(0,math.min(1,(clock-job.started)/math.max(.01,job.approachAt-job.started)))
 return job.x+(job.tx-job.x)*fraction,job.y+(job.ty-job.y)*fraction
end
function O.release(game,r,clock)
 if not r.offlineLoot then return end
 local job=r.offlineLoot
 local x,y=O.position(r,clock)
 for _,s in ipairs(candidates(game,r,clock)) do if s.kind==job.kind and s.id==job.id and s.record.lootOwner==r.id then s.record.lootOwner=nil end end
 r.offlineLoot=nil
 if x and r.area then
  r.offset=nil
  local bx,by=require('src.alife').point(r,clock)
  if bx then
   local progress=math.max(0,math.min(1,(clock-(r.depart or clock))/math.max(.01,(r.arrive or clock)-(r.depart or clock))))
   r.offset={x=x-bx,y=y-by,progress=progress}
   r.pose={x=x,y=y,a=0,vx=0,vy=0,w=0,clock=clock}
  end
 end
end
local function canTake(game,dest,s)
 if s.kind=='pickups' then return Hold.room(dest,s.record.item,1)>0 end
 local h=s.kind=='combat' and sourceHold(game,s.record) or Hold.deserialize(s.record.hold)
 if s.record.kind=='container' and Hold.placeStack(Hold.clone(dest),{id=s.record.item,n=1,inner=h}) then return true end
 return Loot.takeStack(Hold.clone(dest),Hold.deserialize(Hold.serialize(h)))>0
end
-- Shared availability query for deciding whether a collector's local sweep is done.
function O.hasLoot(game,r,clock)
 local dest=recipient(r);if not dest then return false end
 local x,y=require('src.alife').point(r,clock)
 if not x then return false end
 local range=(r.role=='salvager' and T.salvagerRange or T.pirateLootRange)^2
 for _,source in ipairs(candidates(game,r,clock)) do
  if (source.x-x)^2+(source.y-y)^2<=range and available(game,r,source) and canTake(game,dest,source) then return true end
 end
 return false
end
function O.update(game,r,clock)
 local salvager=r.role=='salvager'
 local manifest=salvager and 'salvageCargo' or 'stolenCargo'
 local deadline=salvager and 'salvageUntil' or 'lootUntil'
 local returner=salvager and require('src.salvager').returnRecord or require('src.piracy').returnRecord
 if (not salvager and r.role~='pirate') or r.piracy or r.salvageReturn or r.encounter or r.state~='idle' and r.state~='travel'
  or game.alifeOnline and game.alifeOnline[r.id] then O.release(game,r,clock);return false end
 local loaded=0;for _,n in pairs(r[manifest] or {}) do loaded=loaded+n end
 if r[manifest] and (clock>=(r[deadline] or math.huge) or salvager and loaded>=T.salvagerLoad) then
  O.release(game,r,clock)
  if returner(game,r) then return true end
  if salvager then return false end
 end
 if not r.offlineLoot and clock<(r.lootCheckAt or 0) then return false end
 local dest=recipient(r);if not dest then O.release(game,r,clock);return false end
 local sources=candidates(game,r,clock);local source
 if r.offlineLoot then
  for _,s in ipairs(sources) do if s.kind==r.offlineLoot.kind and s.id==r.offlineLoot.id and available(game,r,s) then source=s;break end end
  if not source then O.release(game,r,clock);return false end
 else
  if clock<(r.lootCheckAt or 0) then return false end
  r.lootCheckAt=clock+2
  local x,y=require('src.alife').point(r,clock);if not x then return false end;local best=(salvager and T.salvagerRange or T.pirateLootRange)^2
  for _,s in ipairs(sources) do
   local d=(s.x-x)^2+(s.y-y)^2
   if d<best and available(game,r,s) and canTake(game,dest,s) then best=d;source=s end
  end
  if not source then return false end
  source.record.lootOwner=r.id
  local arrival=clock+math.max(1,math.sqrt(best)/math.max(1,r.speed))
  r.offlineLoot={id=source.id,kind=source.kind,readyAt=arrival,approachAt=arrival,started=clock,x=x,y=y,tx=source.x,ty=source.y,tick=clock}
  r.taskStatus='approaching saved loot'
 end
 r.offlineLoot.tx,r.offlineLoot.ty=source.x,source.y
 -- Pause the graph duty while spending actual simulated time approaching/looting.
 local elapsed=math.max(0,clock-r.offlineLoot.tick);r.offlineLoot.tick=clock
 if r.state=='travel' then r.depart=r.depart+elapsed;r.arrive=r.arrive+elapsed else r.untilTime=(r.untilTime or clock)+elapsed end
 if clock<r.offlineLoot.readyAt then return true end
 local n,id,moved=0
 local record=source.record
 if source.kind=='pickups' then
  id=record.item;n=Hold.add(dest,id,record.count);record.count=record.count-n
  if record.count==0 then remove(game,source) end
 else
  local h=source.kind=='combat' and sourceHold(game,record) or Hold.deserialize(record.hold)
  local oldMass=cargoMass(h)
  if record.kind=='container' then
   moved={id=record.item,n=1,inner=h}
   if Hold.placeStack(dest,moved) then n,id=1,record.item;remove(game,source) else moved=nil end
  end
  if n==0 then
   n,id,moved=Loot.takeStack(dest,h)
   if n>0 then
    if source.kind=='combat' then
     record.lootHold=Hold.serialize(h)
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
 if n==0 then O.release(game,r,clock);return false end
 if moved and (moved.inner or moved.wear~=nil) then moved.stolen=true end
 r.ship.hold=Hold.serialize(dest);r.ship.cargo=Hold.totals(dest)
 r[manifest]=r[manifest] or {};r[manifest][id]=(r[manifest][id] or 0)+n
 r[deadline]=r[deadline] or clock+(salvager and T.salvagerCollectTime or T.pirateLootTime)
 r.taskStatus='looting saved cargo'
 local count=0;for _,amount in pairs(r[manifest]) do count=count+amount end
 r.offlineLoot.readyAt=clock+1
 if count>=(salvager and T.salvagerLoad or T.pirateLootUnits) or clock>=r[deadline] or not canTake(game,dest,source) then
  O.release(game,r,clock);returner(game,r)
 end
 return true
end
return O
