-- Fleet supply is an abstract wider market. Physical used lots remain shared
-- with the player; factory output influences new arrivals without capping them.
local data=require('src.data')
local S={}
local function config() return require('data.industry').npcShips end
local function random() return love.math.random() end
local function decay(entry,clock)
 return entry.count*2^(-math.max(0,clock-entry.at)/(config().productionHalfLifeHours*3600))
end
function S.produced(u,key,hull,n)
 local state=require('src.dealers').state(u,key)
 state.production=state.production or {}
 local old=state.production[hull]
 state.production[hull]={count=(old and decay(old,u.clock) or 0)+n,at=u.clock}
end
function S.weight(u,hull)
 local weight=config().baselineWeight
 for _,state in pairs(u.dealers or {}) do
  local entry=state.production and state.production[hull]
  if entry then weight=weight+decay(entry,u.clock) end
 end
 return weight
end
function S.wholesale(u,key,state,def,clock)
 if not def.assembly then return end
 local interval=config().wholesaleHours*3600
 state.wholesaleAt=state.wholesaleAt or clock+interval
 if clock<state.wholesaleAt then return end
 -- One sale per observed interval, never a catch-up purge of the showroom.
 state.wholesaleAt=clock+interval
 for i,lot in ipairs(state.lots) do
  if not lot.used and clock-(lot.manufacturedAt or 0)>=interval then
   table.remove(state.lots,i)
   require('src.simulation_history').note(u,'ship_wholesale',clock,nil,{},
    {station=key,hull=lot.hull,lot=lot.id},key)
   return
  end
 end
end
local function fitted(hull,policy,u,area,stock)
 local D=require('src.dealers');local loadout={}
 for i,id in ipairs(hull.loadout) do loadout[i]=id end
 -- Fit from what the arrival region actually stocks (src/availability.lua).
 if u and area then loadout=require('src.availability').regionalFit(u,area,hull,loadout,stock) end
 -- Capability requests select compatible equipment, independent of maker.
 for _,capability in ipairs({'drill','armed'}) do
  if (policy.requires or {})[capability] then
   local function has()
    return require('src.npc_access').capabilities({ship={hull=hull.id,loadout=loadout}})[capability]
   end
   if not has() then
    local installed=false
    for i,slot in ipairs(hull.slots) do
     local id=(capability=='drill' and 'drill_' or 'gun_')..slot.size:lower()..'_base'
     local module=data.modules[id]
     if module and u and area then id=require('src.availability').regionalFit(u,area,{slots={slot}},{id},stock)[1];module=data.modules[id] end
     if module and data.fits(slot,module) then loadout[i]=id;installed=true;break end
    end
    if not installed or not has() then return end
   end
  end
 end
 local stats=require('src.stats').compute(hull,loadout)
 local price=D.price(hull,loadout)
 if price>policy.budget or stats.thrust<=0 or stats.powerOut<=0 or stats.hold<(policy.minCargo or 0) then return end
 local capabilities=require('src.npc_access').capabilities({ship={hull=hull.id,loadout=loadout}})
 for name in pairs(policy.requires or {}) do if not capabilities[name] then return end end
 return loadout,price
end
function S.generated(u,policy,roll,area)
 local choices,total={},0
 local stock=area and require('src.availability').modules(u,area)
 local ids={}
 if policy.hulls then for _,id in ipairs(policy.hulls) do ids[#ids+1]=id end
 else for _,lineup in pairs(require('data.industry').lineups) do for _,id in ipairs(lineup) do ids[#ids+1]=id end end end
 table.sort(ids)
 for _,id in ipairs(ids) do
  local loadout,price=fitted(data.hulls[id],policy,u,area,stock)
  if loadout then
   choices[#choices+1]={hull=id,loadout=loadout,price=price,base=S.weight(u,id)}
  end
 end
 -- Role fit decides; factory output, regional lots, local stock and recent
 -- danger shade it (src/ship_fit.lua). Nothing here consumes stock.
 local danger
 if policy.role then danger=select(2,require('src.ship_fit').rank(u,area,policy.role,choices,stock,policy.sharpness))
 else for _,c in ipairs(choices) do c.weight=c.base end end
 for _,c in ipairs(choices) do total=total+c.weight end
 if total<=0 then return end
 local pick=(roll or random)()*total;local choice=choices[#choices]
 for _,candidate in ipairs(choices) do pick=pick-candidate.weight;if pick<0 then choice=candidate;break end end
 local D=require('src.dealers')
 local lot=D.roll({hulls={choice.hull},trims={'stock'}},{serial=0},choice.hull)
 lot.loadout=choice.loadout;lot.price=choice.price
 lot.armor=require('src.stats').compute(data.hulls[choice.hull],lot.loadout).armor
 local ship=D.ship(lot)
 -- Starting supplies belong to the abstract arrival, not local station stock.
 local used=0
 for id,n in pairs(ship.cargo) do used=used+data.items[id].volume*n end
 local hold=require('src.stats').compute(data.hulls[ship.hull],ship.loadout).hold
 for _,moduleId in ipairs(ship.loadout) do
  local module=moduleId and data.modules[moduleId]
  local ammo=module and module.weapon and data.ammoFor(module)
  if ammo and not ship.cargo[ammo] then
   local n=math.min(data.items[ammo].stack or 1,math.floor(math.max(0,hold-used)/data.items[ammo].volume))
   ship.cargo[ammo]=n;used=used+n*data.items[ammo].volume
  end
 end
 return ship,{source='generated',hull=ship.hull,price=choice.price,weight=choice.weight,fit=choice.fit,danger=danger}
end
function S.acquire(u,area,policy,roll)
 roll=roll or random
 -- A faction with its own service fleet issues those hulls directly.
 local fleet=policy.fleets and policy.fleets[require('src.npc_access').owner(area) or '']
 if fleet then
  local p={};for k,v in pairs(policy) do p[k]=v end;p.hulls=fleet
  local ship,acq=S.generated(u,p,roll,area)
  if ship then return ship,acq end
 end
 if roll()<config().usedChance then
  local candidate=require('src.dealers').purchaseCandidate(u,area,policy,true)
  if candidate then return require('src.dealers').ship(candidate.lot),{source='used',candidate=candidate} end
 end
 return S.generated(u,policy,roll,area)
end
function S.complete(u,r,acquisition,policy)
 if policy.rank then r.rank=policy.rank;r.rankXp=require('src.npc_rank').tiers[policy.rank].xp end
 if acquisition.source=='used' then
  assert(require('src.dealers').buyForNpc(u,r,acquisition.candidate,policy),'arrival ship sale changed during creation')
  r.shipAcquisition.source='used'
 else
  r.shipAcquisition=acquisition
  r.credits=(r.credits or 0)+policy.budget-acquisition.price
  require('src.simulation_history').note(u,'npc_ship_generated',u.clock,r.area,{r.id},
   {hull=r.ship.hull,price=acquisition.price,weight=acquisition.weight,fit=acquisition.fit})
 end
end
return S
