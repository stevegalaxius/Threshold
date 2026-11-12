-- The saved homeStation belongs to the NPC, independently of its current area,
-- job or destination. Rosters derive from those records rather than a second list.
local L=require('src.locations')
local H={}
function H.assign(r,id)
 local place=L.get(id)
 assert(place.kind=='station','NPC home must be a station')
 r.homeStation=id
 return id
end
-- Homes are physical stations/access points, selected once rather than tied
-- to whichever station happened to be primary when the NPC spawned.
function H.choose(u,r)
 if not r.ship or not r.ship.hull then return H.get(r) end
 local G,Room=require('src.travelgraph'),require('src.dock_room')
 local region=r.home or r.area;local purpose=r.homePurpose or 'trade'
 local source=r.node or r.route and r.route[r.index or 1]
 if not source then
  local f=region and require('src.fields')[region]
  source=f and (f.buoyIds[1] or f.stationIds[1])
 end
 local counts={}
 for _,other in pairs(u.npcs or {}) do
  if other~=r and other.state~='dead' and other.state~='escaped' and other.homeStation then
   counts[other.homeStation]=(counts[other.homeStation] or 0)+1
  end
 end
 local function select(localOnly)
  local best,count,full
  for _,place in pairs(L.byId) do
   local parent=L.byId[L.canonical(place.id)]
   if place.kind=='station' and (not localOnly or place.area==region)
    and parent.uses and parent.uses[purpose] then
    local capacity=Room.capacity(place.id,r.ship.hull)
    local n=counts[place.id] or 0;local crowded=n>=capacity
    if capacity>0 and (not best or full and not crowded or full==crowded and (n<count or n==count and place.id<best))
     and (not source or G.itinerary(source,place.id,u.clock or 0,true)) then
     best,count,full=place.id,n,crowded
    end
   end
  end
  return best
 end
 local id=select(true) or select(false)
 if id then H.assign(r,id);r.homeDistributed=true end
 return id
end
function H.get(r,u)
 local place=r.homeStation and L.byId[r.homeStation]
 if place and place.kind=='station' then return H.assign(r,place.id) end
 if u then return H.choose(u,r) end
 local region=r.home or r.area
 local purpose=r.homePurpose or 'trade'
 local id=region and L.station(region,purpose) or L.station(nil,purpose)
 if not id and region then
  local G=require('src.travelgraph');local Fields=require('src.fields')
  local source=Fields[region].buoyIds[1] or Fields[region].stationIds[1] or Fields[region].holdingId
  for _,area in ipairs(Fields.list) do
   local candidate=L.station(area,purpose)
   if candidate and source and G.itinerary(source,candidate,0) then id=candidate;break end
  end
 end
 if id then return H.assign(r,id) end
 r.homeStation=nil
end
function H.seed(u)
 local pending={}
 for _,r in pairs(u.npcs) do
  if r.state~='dead' and r.state~='escaped' and r.ship and not r.homeDistributed then
   r.homeStation=nil;pending[#pending+1]=r
  end
 end
 table.sort(pending,function(a,b)return a.id<b.id end)
 for _,r in ipairs(pending) do H.choose(u,r) end
 for _,r in pairs(u.npcs) do if r.state~='dead' and r.state~='escaped' then H.get(r,u) end end
end
function H.residents(u,id)
 local list={}
 for _,r in pairs(u.npcs) do
  if r.state~='dead' and r.state~='escaped' and H.get(r)==id then list[#list+1]=r end
 end
 table.sort(list,function(a,b)return a.id<b.id end)
 return list
end
return H
