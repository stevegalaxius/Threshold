-- Loose objects: every floating item and drilled rock has exactly one plain
-- record, and the record is the only authority. Live pickups and asteroid
-- bodies are disposable views: Mining.materialize streams them in by distance,
-- they write back on capture, and they are dropped without losing anything.
-- Records live in the mining state's resource table (one table, one owner);
-- mining-specific records carry a site, generic loot does not.
local T=require('src.tuning')
local Lo={}
local function persistence() return require('src.persistence') end

function Lo.records(u)
 local records=require('src.jobs').state(u).resources
 return records
end

-- Where a record is now. Rocks keep mining's settle-into-the-belt model;
-- items use the damped-current model that live pickups follow.
function Lo.position(record,clock)
 if record.kind=='rock' then return require('src.mining').rockPosition(record,clock) end
 local elapsed=math.max(0,clock-(record.clock or clock))
 if record.orbit then
  local view={x=record.x,y=record.y,vx=record.vx,vy=record.vy,orbit=record.orbit}
  local out=persistence().advanceRecord(view,elapsed)
  return out.x,out.y,out.vx,out.vy
 end
 local drag=T.pickupDrag
 local travel=(1-math.exp(-drag*elapsed))/drag
 return record.x+record.vx*travel,record.y+record.vy*travel,
  record.vx*math.exp(-drag*elapsed),record.vy*math.exp(-drag*elapsed)
end

-- Give a freshly spawned live pickup its record; it is a view from now on.
function Lo.adopt(game,p)
 if game.preview or not game.universe or not game.fieldId or p.looseId then return end
 local u=game.universe
 u.nextLooseId=(u.nextLooseId or 0)+1
 local id='loot/'..u.nextLooseId
 Lo.records(u)[id]={id=id,area=game.fieldId,kind='loot',item=p.item,count=p.count,
  x=p.x,y=p.y,vx=p.vx,vy=p.vy,spin=p.spin,clock=u.clock,orbit=persistence().orbit(game,p.x,p.y)}
 p.looseId=id
 game.miningLive=game.miningLive or {}
 game.miningLive[id]={kind='loot',object=p}
 return id
end

-- Write a live pickup back to its record (or retire the record when empty).
function Lo.write(game,record,p)
 if p.count<=0 or p.gone then
  if record.site then require('src.mining').advanceProduction(game.universe,game.universe.clock,record.site) end
  Lo.records(game.universe)[record.id]=nil;return
 end
 record.x,record.y,record.vx,record.vy,record.count=p.x,p.y,p.vx,p.vy,p.count
 record.spin,record.clock=p.spin,game.universe.clock
 record.orbit=persistence().orbit(game,p.x,p.y)
end

-- Offline consumers (salvagers, pirates) see every loot record in an area that
-- has no live view and isn't reserved for a mining site.
function Lo.offline(game,area,clock)
 local result={}
 for id,record in pairs(Lo.records(game.universe)) do
  if record.kind=='loot' and record.area==area and not record.site and record.count>0
   and not (game.miningLive and game.miningLive[id]) then
   local x,y=Lo.position(record,clock)
   result[#result+1]={record=record,x=x,y=y}
  end
 end
 return result
end
function Lo.remove(u,id)
 local record=Lo.records(u)[id]
 if record and record.site then require('src.mining').advanceProduction(u,u.clock,record.site) end
 Lo.records(u)[id]=nil
end
return Lo
