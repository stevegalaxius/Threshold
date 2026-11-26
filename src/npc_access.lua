-- Job access and police authority are independent of work preferences.
local data=require('src.data')
local L=require('src.locations')
local Rep=require('src.reputation')
local Dark=require('src.dark')
local A={}
function A.owner(area)
 local node=L.station(area,'trade')
 return node and Rep.ofNode(node) or Rep.ofArea(area)
end
function A.capabilities(r)
 local hold=data.hulls[r.ship.hull].hold or 0
 local c={cargo=hold>0,bulk=hold>=require('src.tuning').trunkMinHold,
  climate=require('src.ship').climateSpace(data.hulls[r.ship.hull],r.ship.loadout)>0,
  berths=#(data.hulls[r.ship.hull].berths or {})>0}   -- carries ships (src/berths.lua)
 for _,id in pairs(r.ship.loadout or {}) do
  local m=id and data.modules[id];local w=m and m.weapon
  if w then
   if w.kind=='drill' then c.drill=true
   elseif w.kind~='drone' then c.armed=true end
  end
 end
 return c
end
function A.authorized(r,kind,issuer,jurisdiction)
 if not r or not issuer or not jurisdiction then return false end
 for _,grant in ipairs(r.authorizations or {}) do
  if grant.kind==kind and grant.issuer==issuer and grant.jurisdiction==jurisdiction then return true end
 end
 return false
end
function A.policeGrant(r,area)
 if not r then return end
 for _,grant in ipairs(r.authorizations or {}) do
  if grant.kind=='police' and grant.issuer and grant.jurisdiction==area then return grant end
 end
end
function A.police(r,area) return A.policeGrant(r,area)~=nil end
-- Does this offer touch a dark grid (its stations or its area)?
function A.darkOffer(offer)
 return (offer.source and Dark.isDarkNode(offer.source)) or (offer.target and Dark.isDarkNode(offer.target))
  or (offer.area and Dark.isDarkArea(offer.area)) or false
end
function A.darkAccess(r) return r~=nil and require('src.npc_templates').darkAccess(r) end
-- Territory and port ownership both apply to docking. A fence run may use
-- its named fence; routine trips to that same station still need access.
function A.canDock(r,id,u,purpose)
 local place=L.byId[id]
 if not place or place.kind~='station' or not r or r.player then return true end
 if Dark.isDarkArea(place.area) and not A.darkAccess(r) then return false end
 local station=L.canonical(id)
 if purpose=='fence' and Dark.isFence(station) then return true end
 local owner,territory=Rep.ofNode(station),Rep.ofArea(place.area)
 return not Rep.hostileToCrew(u,owner,r) and (territory==owner or not Rep.hostileToCrew(u,territory,r))
end

function A.canStop(r,id,u)
 local task=r.task
 local purpose=not r.service and not r.worldRecovery and task and task.kind=='fence'
  and L.canonical(task.target)==L.canonical(id) and 'fence'
 return A.canDock(r,id,u,purpose)
end

-- Interregional itineraries can require a parent grid as well as the two
-- endpoints. A sister-moon trip crosses directly. Hostile transit remains
-- possible, but an NPC prefers work that passes through fewer hostile grids.
function A.travelRisk(r,from,to,u)
 local a,b=L.byId[from],L.byId[to]
 local faction=Rep.crewFaction(r)
 if not a or not b or not faction then return 0 end
 local function hostile(area) return Rep.stance(Rep.ofArea(area),faction,u)=='hostile' and 1 or 0 end
 local origin,dest=a.area,b.area
 if origin==dest then return 0 end
 local moons=require('src.fields').moons
 local left,right=moons[origin],moons[dest]
 local risk=hostile(dest)
 if left and right and left.parent==right.parent then return risk end
 if left and left.parent~=dest then risk=risk+hostile(left.parent) end
 if right and right.parent~=origin then risk=risk+hostile(right.parent) end
 return risk
end

function A.jobRisk(r,from,offer,u)
 local pickup=offer.source or from
 return A.travelRisk(r,from,pickup,u)+A.travelRisk(r,pickup,offer.target,u)
end

function A.eligible(r,offer,capabilities,u)
 if not A.canDock(r,offer.source,u) or not A.canDock(r,offer.target,u,offer.kind) then return false end
 if offer.kind then
  -- (whether this NPC works the dark side is the same for every offer it
  -- weighs: asked once and kept with its capabilities)
  local dark=capabilities and capabilities.darkAccess
  if dark==nil then
   dark=A.darkAccess(r)
   if capabilities then capabilities.darkAccess=dark end
  end
  if not dark and A.darkOffer(offer) then return false end
 end
 local req=offer.requires
 if not req then return true end
 for _,name in ipairs(req.capabilities or {}) do if not capabilities[name] then return false end end
 if req.authorization and not A.authorized(r,req.authorization,offer.issuer,offer.jurisdiction) then return false end
 return true
end
function A.raiding(r) return r and r.task and r.task.kind=='raid' and not r.service and not r.worldRecovery or false end
function A.defending(r,area)
 return A.police(r,area) or r and r.task and r.task.kind=='patrol' and r.task.jurisdiction==area or false
end
function A.civilian(r) return r and not A.raiding(r) and not A.defending(r,r.area) and not r.piracy or false end
return A
