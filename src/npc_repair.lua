-- Shared dockside maintenance for persistent NPCs; never uses player credits.
local data=require('src.data')
local Stats=require('src.stats')
local L=require('src.locations')
local T=require('src.tuning')
local R={}
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
function R.stay(r,node,minimum)
 if not R.supports(node) then return minimum end
 return math.max(minimum,(R.maximum(r)-(r.ship.armor or R.maximum(r)))/T.npcRepairPerSecond)
end
function R.begin(r,node,at,minimum)
 r.repairAt=at;r.patrolRepairAt=nil
 r.untilTime=at+R.stay(r,node,minimum)
end
function R.advance(r,clock,node)
 if r.state~='docked' or r.ship.armor==0 then return end
 require('src.supplies').refill(r,node)
 local at=math.min(clock,r.untilTime)
 if R.supports(node) then
  local maximum=R.maximum(r)
  r.ship.armor=math.min(maximum,(r.ship.armor or maximum)+math.max(0,at-(r.repairAt or r.patrolRepairAt or at))*T.npcRepairPerSecond)
  if maximum-r.ship.armor<1e-6 then r.ship.armor=maximum;r.fleeing=nil end
 end
 r.repairAt=at;r.patrolRepairAt=nil
end
function R.online(game,e,dt)
 local r=e.alifeId and game.universe.npcs[e.alifeId]
 if not r or e.dead or e.removed or not e.dockState or not e.dockState.done then return end
 require('src.supplies').online(game,e)
 if game.stationServices(e.dockState.station).repair then
  e.armor=math.min(e.stats.armor,e.armor+T.npcRepairPerSecond*dt)
  r.ship.armor=e.armor
  if e.armor>=e.stats.armor then e.fleeing=nil;r.fleeing=nil end
 end
 r.repairAt=game.universe.clock;r.patrolRepairAt=nil
end
return R
