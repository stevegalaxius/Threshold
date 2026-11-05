-- One supplies catalogue for station vendors and persistent NPC maintenance.
-- Supply is unlimited for now; NPC billing remains deferred with their economy.
local data,Stats=require('src.data'),require('src.stats')
local Hold,Ship=require('src.inventory.hold'),require('src.ship')
local L,T=require('src.locations'),require('src.tuning')
local Fuel=require('src.reactor_fuel')
local S={}
local catalogue,itemCount
function S.shop()
 if catalogue and itemCount==#data.list.items then return catalogue end
 local sells={}
 for _,id in ipairs(data.list.items) do
  if data.items[id].kind=='ammo' or id=='flare' or id==Fuel.item() then sells[#sells+1]={id,1} end
 end
 catalogue={id='supplies',name='Supplies',description='Reactor fuel, ammunition and countermeasures.',sells=sells,unlimited=true}
 itemCount=#data.list.items
 return catalogue
end
function S.supports(node)
 local place=node and L.byId[node]
 return place and place.kind=='station' and L.stationServices(node).market or false
end
local profiles={}
function S.targets(r,e)
 local ship=r.ship;local hull=e and e.hull or data.hulls[ship.hull]
 local loadout=e and e.loadout or ship.loadout or hull.loadout
 local key=(r.archetype or '')..':'..#data.list.items
 for i=1,#hull.slots do key=key..'/'..tostring(loadout[i]) end
 local preset=data.enemies[r.archetype] or {}
 local reserve=r.ammoReserve or preset.ammoReserve
 if not reserve and profiles[key] then return profiles[key] end
 local rates,targets={},{}
 for _,id in pairs(loadout) do
  local m=id and data.modules[id];local w=m and m.weapon
  if w and w.kind~='laser' and w.kind~='drill' then
   local ammo=data.ammoFor(m)
   if ammo then rates[ammo]=(rates[ammo] or 0)+(w.fireRate or 1) end
  end
  if m and m.flares then rates.flare=1 end
 end
 for id,rate in pairs(rates) do
  local amount=reserve and reserve[id] or preset.cargo and preset.cargo[id]
  targets[id]=math.max(0,amount or math.max(data.items[id].stack or 1,math.ceil(rate*T.npcAmmoSeconds)))
 end
 local stats=e and e.stats or Stats.compute(hull,loadout)
 if stats.powerOut>0 then targets[Fuel.item()]=math.max(1,math.ceil(stats.powerOut*T.reactorFuelReserveSeconds/T.reactorFuelEnergy)) end
 if not reserve then profiles[key]=targets end
 return targets
end
local function room(r,e,h,id)
 if h then return Hold.room(h,id,1,{pristine=true}) end
 local stats=e and e.stats or Stats.compute(data.hulls[r.ship.hull],r.ship.loadout)
 local cargo=e and e.cargo or r.ship.cargo or {};local used=0
 for item,n in pairs(cargo) do used=used+data.items[item].volume*n end
 return math.max(0,math.floor((stats.hold-used)/data.items[id].volume+.000001))
end
function S.needs(r,e)
 local cargo=e and e.cargo or r.ship.cargo or {};local h=e and e.hold
 for id,target in pairs(S.targets(r,e)) do
  if (cargo[id] or 0)<target*T.npcAmmoThreshold then
   if not h and r.ship.hold and not e then h=Hold.deserialize(r.ship.hold) end
   if room(r,e,h,id)>0 then return true end
  end
 end
 return false
end
local function fill(r,e,h,cargo)
 local added=0
 local targets=S.targets(r,e);local order={}
 for id in pairs(targets) do order[#order+1]=id end
 table.sort(order,function(a,b)
  if a==Fuel.item() then return b~=a end
  if b==Fuel.item() then return false end
  return a<b
 end)
 for _,id in ipairs(order) do
  local target=targets[id]
  local missing=math.max(0,target-(cargo[id] or 0));local n
  if missing==0 then n=0
  elseif h then n=Hold.add(h,id,missing,{pristine=true})
  else n=math.min(missing,room(r,e,nil,id)) end
  if n>0 then cargo[id]=(cargo[id] or 0)+n;added=added+n end
 end
 return added
end
function S.refill(r,node)
 if not S.supports(node) then return 0 end
 local h=r.ship.hold and Hold.deserialize(r.ship.hold)
 r.ship.cargo=h and Hold.totals(h) or r.ship.cargo or {}
 local n=fill(r,nil,h,r.ship.cargo)
 if h and n>0 then r.ship.hold=Hold.serialize(h) end
 return n
end
function S.online(game,e)
 local ds=e.dockState
 local r=e.alifeId and game.universe.npcs[e.alifeId]
 if not r or e.dead or e.removed or not e.cargo or not ds or not ds.done or ds.supplied then return end
 if not game.stationServices(ds.station).market then return end
 local n=fill(r,e,e.hold,e.cargo)
 ds.supplied=true
 if n>0 then
  Ship.updateMass(e)
  r.ship.cargo=require('src.persistence').copy(e.cargo)
  r.ship.hold=e.hold and Hold.serialize(e.hold) or nil
 end
end
return S
