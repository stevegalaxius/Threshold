-- Job access and police authority are independent of work preferences.
local data=require('src.data')
local A={}
function A.owner(area)
 local Rep=require('src.reputation')
 local node=require('src.locations').station(area,'trade')
 return node and Rep.ofNode(node) or Rep.ofArea(area)
end
function A.capabilities(r)
 local hold=data.hulls[r.ship.hull].hold or 0
 local c={cargo=hold>0,bulk=hold>=require('src.tuning').trunkMinHold,
  climate=require('src.ship').climateSpace(data.hulls[r.ship.hull],r.ship.loadout)>0}
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
 local Dark=require('src.dark')
 return (offer.source and Dark.isDarkNode(offer.source)) or (offer.target and Dark.isDarkNode(offer.target))
  or (offer.area and Dark.isDarkArea(offer.area)) or false
end
function A.darkAccess(r) return r~=nil and require('src.npc_templates').darkAccess(r) end
function A.eligible(r,offer,capabilities)
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
