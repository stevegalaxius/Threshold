-- Shared dockside maintenance for persistent NPCs; never uses player credits.
local data=require('src.data')
local Stats=require('src.stats')
local L=require('src.locations')
local T=require('src.tuning')
local Plates=require('src.repair_materials')
local R={}
local function extendVisit(r,clock,at,maximum,u,node)
 if r.service and r.service.need=='repair' and r.ship.armor<maximum and clock>=r.untilTime then
  r.untilTime=at+Plates.duration(u,node,maximum-r.ship.armor,T.npcRepairPerSecond)
 end
end
function R.supports(node)
 local place=node and L.byId[node]
 if not place or place.kind~='station' then return false end
 return L.stationServices(node).repair or false
end
function R.maximum(r) return Stats.compute(data.hulls[r.ship.hull],r.ship.loadout).armor end
function R.needs(r,armor,maximum)
 maximum=maximum or R.maximum(r)
 return (armor or r.ship.armor or maximum)<maximum*T.npcRepairThreshold
end
function R.stay(r,node,minimum,u)
 if not R.supports(node) then return minimum end
 local missing=R.maximum(r)-(r.ship.armor or R.maximum(r))
 return math.max(minimum,u and Plates.duration(u,node,missing,T.npcRepairPerSecond) or missing/(T.npcRepairPerSecond*Plates.emergency))
end
function R.begin(r,node,at,minimum,u)
 r.repairAt=at;r.patrolRepairAt=nil
 r.untilTime=at+R.stay(r,node,minimum,u)
end
function R.advance(r,clock,node,u)
 if r.state~='docked' or r.ship.armor==0 then return end
 require('src.supplies').refill(r,node,u)
 -- A ship waiting for its next job search is still parked and repairing.
 local at=math.min(clock,math.max(r.untilTime or clock,r.nextDecisionAt or 0))
 if R.supports(node) then
  local maximum=R.maximum(r)
  local armor=r.ship.armor or maximum
  local elapsed=math.max(0,at-(r.repairAt or r.patrolRepairAt or at))
  r.ship.armor=math.min(maximum,armor+Plates.restore(assert(u),node,maximum-armor,elapsed,T.npcRepairPerSecond))
  if maximum-r.ship.armor<1e-6 then r.ship.armor=maximum;r.fleeing=nil end
  extendVisit(r,clock,at,maximum,u,node)
 end
 r.repairAt=at;r.patrolRepairAt=nil
end
function R.online(game,e,dt)
 local r=e.alifeId and game.universe.npcs[e.alifeId]
 if not r or e.dead or e.removed or not e.dockState or not e.dockState.done then return end
 require('src.supplies').online(game,e)
 if game.stationServices(e.dockState.station).repair then
  local st=e.dockState.station
  e.armor=math.min(e.stats.armor,e.armor+Plates.restore(game.universe,st.key or st.locationId,e.stats.armor-e.armor,dt,T.npcRepairPerSecond))
  r.ship.armor=e.armor
  extendVisit(r,game.universe.clock,game.universe.clock,e.stats.armor,game.universe,st.key or st.locationId)
  e.dockState.departAt=r.untilTime
  if e.armor>=e.stats.armor then e.fleeing=nil;r.fleeing=nil end
 end
 r.repairAt=game.universe.clock;r.patrolRepairAt=nil
end
return R
