-- The saved homeStation belongs to the NPC, independently of its current area,
-- job or destination. Rosters derive from those records rather than a second list.
local L=require('src.locations')
local H={}
function H.assign(r,id)
 id=L.canonical(id)
 local place=L.get(id)
 assert(place.kind=='station','NPC home must be a station')
 r.homeStation=id
 if r.role=='miner' then r.base=id end -- legacy mining saves use base too
 return id
end
function H.get(r)
 local place=r.homeStation and L.byId[r.homeStation]
 if place and place.kind=='station' then return H.assign(r,place.id) end
 -- Legacy assignments are migrated once; subsequent list reordering cannot
 -- move a resident. Replacing a removed station assigns a new home, not a pose.
 local old=r.role=='miner' and r.base or r.tradeHome
 local region=r.home or r.area
 local id=old and L.byId[old] and old
 if not id then
  if r.role=='pirate' then id=L.station(nil,'pirateBase')
  elseif region then id=L.station(region,r.role=='miner' and 'mining' or 'trade') end
 end
 if id then return H.assign(r,id) end
end
function H.seed(u)
 for _,r in pairs(u.npcs) do H.get(r) end
end
function H.residents(u,id)
 id=L.canonical(id);local list={}
 for _,r in pairs(u.npcs) do
  if r.state~='dead' and r.state~='escaped' and H.get(r)==id then list[#list+1]=r end
 end
 table.sort(list,function(a,b)return a.id<b.id end)
 return list
end
return H
