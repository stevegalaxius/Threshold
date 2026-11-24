-- Two storefronts at every station with a market:
--   Fuel      the real one: reactor fuel from the station's own stock, which
--             NPCs refuel from and src/economy.lua keeps ordered up.
--   Supplies  the debug fallback: unlimited fuel, ammunition and flares,
--             for the player only. NPCs never draw on it: they buy fuel,
--             ammunition and flares off the station's stock at its price.
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
 catalogue={id='supplies',name='Supplies (debug)',description='Unlimited reactor fuel, ammunition and countermeasures, for testing.',sells=sells,unlimited=true}
 itemCount=#data.list.items
 return catalogue
end
-- The real fuel storefront, from station stock.
local fuelShop
function S.fuelShop()
 fuelShop=fuelShop or {id='fuel',name='Fuel',description='Deuterium canisters from station stock.',sells={{Fuel.item(),10}}}
 return fuelShop
end
function S.supports(node)
 local place=node and L.byId[node]
 return place and place.kind=='station' and L.stationServices(node).market or false
end
local copy=require('src.persistence').copy
-- Cargo and fitting tables may be edited in place or replaced on capture.
local function same(a,b)
 if a==b then return true end
 if a then for k,v in pairs(a) do if not b or b[k]~=v then return false end end end
 if b then for k in pairs(b) do if not a or a[k]==nil then return false end end end
 return true
end

local profiles=setmetatable({}, {__mode='k'})
function S.targets(r,e)
 local ship=r.ship;local hull=e and e.hull or data.hulls[ship.hull]
 local loadout=e and e.loadout or ship.loadout or hull.loadout
 local loads=e and e.loads or ship.loads
 local fitting=Stats.fitted(hull,loadout)
 local powerOut=e and e.stats and e.stats.powerOut or fitting.powerOut
 local preset=r.archetype and data.enemies[r.archetype]
 local reserve=r.ammoReserve or preset and preset.ammoReserve
 local defaults=preset and preset.cargo
 local entry=profiles[r]
 if entry and entry.fitting==fitting and entry.powerOut==powerOut and entry.itemCount==#data.list.items
  and same(entry.loads,loads) and same(entry.reserve,reserve) and same(entry.defaults,defaults) then return entry.targets end
 local rates,targets,salvo={},{},{}
 for index,id in pairs(loadout) do
  local m=id and data.modules[id];local w=m and m.weapon
  if w and w.kind~='laser' and w.kind~='drill' then
   local ammo=data.ammoFor(m)
   local pick=loads and loads[index]
   if pick then for _,option in ipairs(data.ammoOptions(m)) do if option==pick then ammo=pick;break end end end
   if ammo then rates[ammo]=(rates[ammo] or 0)+(w.fireRate or 1) end
   if ammo and w.capacity then
    local tubes=math.max(1,math.floor(w.capacity/(({S=1,M=2,L=4})[data.items[ammo].size] or 1)))
    salvo[ammo]=(salvo[ammo] or 0)+tubes
   end
  end
  if m and m.flares then rates.flare=1 end
 end
 for id,rate in pairs(rates) do
  local amount=reserve and reserve[id] or defaults and defaults[id]
  local fallback=math.ceil(rate*T.npcAmmoSeconds)
  -- guided munitions fire in salvos: carry a few magazines, not 30 s of
  -- continuous fire (75 medium missiles a rack)
  if salvo[id] then fallback=math.min(fallback,salvo[id]*T.npcMissileSalvos) end
  targets[id]=math.max(0,amount or math.max(data.items[id].stack or 1,fallback))
 end
 if powerOut>0 then targets[Fuel.item()]=math.max(1,math.ceil(powerOut*T.reactorFuelReserveSeconds/T.reactorFuelEnergy)) end
 profiles[r]={fitting=fitting,powerOut=powerOut,itemCount=#data.list.items,loads=copy(loads),
  reserve=copy(reserve),defaults=copy(defaults),targets=targets}
 return targets
end
local function room(r,e,h,id)
 if h then return Hold.room(h,id,1,{pristine=true}) end
 local stats=e and e.stats or Stats.fitted(data.hulls[r.ship.hull],r.ship.loadout)
 local cargo=e and e.cargo or r.ship.cargo or {};local used=0
 for item,n in pairs(cargo) do used=used+data.items[item].volume*n end
 return math.max(0,math.floor((stats.hold-used)/data.items[id].volume+.000001))
end
function S.needs(r,e)
 local cargo=e and e.cargo or r.ship.cargo or {};local h=e and e.hold
 for id,target in pairs(S.targets(r,e)) do
  if (id==Fuel.item() and Fuel.condition(r,e)~='normal' or id~=Fuel.item() and (cargo[id] or 0)<target*T.npcAmmoThreshold) then
   if not h and r.ship.hold and not e then h=Hold.deserialize(r.ship.hold) end
   if room(r,e,h,id)>0 then return true end
  end
 end
 return false
end
-- Rearming/refuelling withdraws physical stock only. A shortage stays visible.
local function fuelAvailable(u,key)
 if not u or not key then return math.huge end
 return require('src.stockpile').available(u,key,Fuel.item())
end
-- What a unit costs here: the station's own quote, or a satellite shelf's
-- list price.
local function unitPrice(u,key,id)
 if type(key)=='table' then return data.items[id].price or 0 end
 return require('src.markets').price(u,key,id)
end
-- NPCs pay for what they take, like the player, down to a small reserve.
-- Fuel is the one exception: a ship that can't pay still gets enough to
-- leave (its credits stop at 0), so nobody is stranded at a dock.
local function charge(r,u,key,id,n)
 local p=unitPrice(u,key,id)
 -- (fuel goes out even to a ship that can't pay; the station banks only
 -- what it was actually paid, or it was minting the rest)
 local cost=math.min(n*p,math.max(0,r.credits or 0))
 r.credits=(r.credits or 0)-cost;r.suppliesSpent=(r.suppliesSpent or 0)+cost
 -- a broke hunter's ammo is billed to its system's bounty payer, which
 -- wants its wildcats dead: real money, not goods given away
 if r.populationGroup=='hunter' and n*p>cost and type(key)~='table' and require('src.ammunition').byItem[id] then
  local payer=require('src.wreck_bounty').payer(r.home or r.area)
  if payer and payer~=key then cost=cost+require('src.accounts').pay(u,payer,n*p-cost,'hunter supply',id) end
 end
 if id==Fuel.item() then r.fuelSpent=(r.fuelSpent or 0)+cost end
 if type(key)=='table' then
  -- a satellite hub's shelf: the takings go to whoever runs the satellite
  local Sat=require('src.satellites')
  local sat=Sat.get(u,(key.key or ''):match('^sat:(.+)$'))
  local acct=sat and Sat.account(sat)
  if acct then require('src.accounts').receive(u,acct,cost) end
  require('src.economy').ledger(u,key.key,'sold',cost,id)
 else require('src.accounts').receive(u,key,cost,'sold',id) end
end
local function affordable(r,u,key,id,missing)
 if id==Fuel.item() then return missing end
 -- a bounty hunter rearms on the station's tab, like fuel: a broke hunter
 -- with empty guns could never earn its way back (charge banks only
 -- what it actually paid)
 if r.populationGroup=='hunter' and require('src.ammunition').byItem[id] then return missing end
 local p=unitPrice(u,key,id)
 if p<=0 then return missing end
 return math.min(missing,math.floor(math.max(0,(r.credits or 0)-T.npcSupplyReserve)/p))
end
local function fill(r,e,h,cargo,u,key)
 local added,retry,creditLimited=0,false,false
 -- at a real shelf, pick each gun's ammo from what's on sale first
 if u and key then require('src.npc_refit').ammo(r,u,key,e) end
 local targets=S.targets(r,e);local order={}
 for id in pairs(targets) do order[#order+1]=id end
 table.sort(order,function(a,b)
  if a==Fuel.item() then return b~=a end
  if b==Fuel.item() then return false end
  return a<b
 end)
 for _,id in ipairs(order) do
  local target=targets[id]
  local wanted=math.max(0,target-(cargo[id] or 0))
  local missing=wanted;local n
  if id==Fuel.item() then
   missing=math.min(missing,fuelAvailable(u,key))
  elseif require('src.ammunition').byItem[id] and u and key then
   missing=math.min(missing,require('src.stockpile').available(u,key,id))
  end
  if missing>0 and u and key and (id==Fuel.item() or require('src.ammunition').byItem[id]) then
   local budget=affordable(r,u,key,id,missing)
   if budget<missing then creditLimited=true end
   missing=budget
  end
  if missing==0 then n=0
  elseif h then n=Hold.add(h,id,missing,{pristine=true})
  else n=math.min(missing,room(r,e,nil,id)) end
  if n>0 then cargo[id]=(cargo[id] or 0)+n;added=added+n end
  if missing<wanted and n==missing and room(r,e,h,id)>0 then retry=true end
  if n>0 and (id==Fuel.item() or require('src.ammunition').byItem[id]) and u and key then
   assert(require('src.stockpile').take(u,key,id,n),'supply stock changed during refill')
   require('src.economy').consume(u,type(key)=='table' and key.key or key,id,n)
   charge(r,u,key,id,n)
  end
 end
 return added,retry,creditLimited
end
-- A ship joining the world arrives already stocked to its own reserve
-- targets (ammunition, flares, fuel), out of the abstract arrival rather
-- than any station: a fleet appearing at once used to buy every shelf in
-- the system bare in its first hour.
function S.provision(r)
 if not r or not r.ship then return 0 end
 local h=r.ship.hold and Hold.deserialize(r.ship.hold)
 r.ship.cargo=h and Hold.totals(h) or r.ship.cargo or {}
 local n=fill(r,nil,h,r.ship.cargo,nil,nil)
 if h and n>0 then r.ship.hold=Hold.serialize(h) end
 return n
end
function S.refill(r,node,u,e)
 if not S.supports(node) then return 0 end
 u=u or S.universe
 if e then
  local n,retry,creditLimited=fill(r,e,e.hold,e.cargo,u,L.canonical(node))
  if n>0 then
   Ship.updateMass(e)
   r.ship.cargo=copy(e.cargo)
   r.ship.hold=e.hold and Hold.serialize(e.hold) or nil
  end
  return n,retry,creditLimited
 end
 local h=r.ship.hold and Hold.deserialize(r.ship.hold)
 r.ship.cargo=h and Hold.totals(h) or r.ship.cargo or {}
 local n,retry,creditLimited=fill(r,nil,h,r.ship.cargo,u,u and L.canonical(node))
 if h and n>0 then r.ship.hold=Hold.serialize(h) end
 return n,retry,creditLimited
end

function S.docked(r,node,u,e)
 local ship=e or r.ship
 local visit=r.dockSupplies
 if visit and visit.node==node and visit.hull==r.ship.hull
  and (not visit.retryAt or u.clock<visit.retryAt)
  and (not visit.credits or (r.credits or 0)<=visit.credits)
  and same(ship.cargo,visit.cargo) and same(ship.loadout,visit.loadout) and same(ship.loads,visit.loads) then return end
 local _,retry,creditLimited=S.refill(r,node,u,e)
 r.dockSupplies={node=node,hull=r.ship.hull,cargo=copy(ship.cargo),loadout=copy(ship.loadout),loads=copy(ship.loads),
  retryAt=retry and u.clock+T.npcSupplyRetry or nil,credits=creditLimited and (r.credits or 0) or nil}
end
-- Off a satellite's shelf (a hub, src/satellites.lua): the same reserve
-- targets, out of that shelf's stock. shelf = { key, marketId }.
function S.refillFrom(r,shelf,u)
 local h=r.ship.hold and Hold.deserialize(r.ship.hold)
 r.ship.cargo=h and Hold.totals(h) or r.ship.cargo or {}
 local n=fill(r,nil,h,r.ship.cargo,u,shelf)
 if h and n>0 then r.ship.hold=Hold.serialize(h) end
 return n
end
function S.online(game,e)
 local ds=e.dockState
 local r=e.alifeId and game.universe.npcs[e.alifeId]
 if not r or e.dead or e.removed or not e.cargo or not ds or not ds.done then return end
 local clock=game.universe.clock
 if ds.supplyCheckAt and clock<ds.supplyCheckAt then return end
 ds.supplyCheckAt=clock+T.alifeLocalTick
 S.docked(r,ds.station.locationId or ds.station.key,game.universe,e)
end
return S
