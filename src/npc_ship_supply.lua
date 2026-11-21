-- Fleet supply: an arriving NPC buys a real ship off a lot in its region
-- (new or used, the same lots the player buys from), or a faction pilot is
-- issued one off its military yard. When no lot has a ship for the job,
-- the pilot arrives in one bought elsewhere (S.generated, the same choice
-- seeding makes), so losses are replaced and the fleet keeps its size.
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
-- Fit loadout (changed in place) for the job's capabilities: a drill in
-- every hardpoint that takes one for a miner (it works rock with every drill
-- it carries, src/npc_operations.lua; bays keep their weapons), a gun where
-- an armed job has none. Equipment is chosen by what it does, not by maker,
-- from what the region stocks when u and area are given. Returns loadout,
-- or nil when the hull can't do the job.
local function install(hull,policy,loadout,u,area,stock)
 local function regional(slot,id)
  if data.modules[id] and u and area then id=require('src.availability').regionalFit(u,area,{slots={slot}},{id},stock)[1] end
  return id
 end
 for _,capability in ipairs({'drill','armed'}) do
  if (policy.requires or {})[capability] then
   local function has()
    return require('src.npc_access').capabilities({ship={hull=hull.id,loadout=loadout}})[capability]
   end
   if capability=='drill' then
    for i,slot in ipairs(hull.slots) do
     local id=regional(slot,'drill_'..slot.size:lower()..'_base')
     local module=id and data.modules[id]
     if module and module.weapon and module.weapon.kind=='drill' and data.fits(slot,module) then loadout[i]=id end
    end
   end
   if not has() then
    local installed=false
    for i,slot in ipairs(hull.slots) do
     local id=regional(slot,(capability=='drill' and 'drill_' or 'gun_')..slot.size:lower()..'_base')
     local module=id and data.modules[id]
     if module and data.fits(slot,module) then loadout[i]=id;installed=true;break end
    end
    if not installed or not has() then return end
   end
  end
 end
 return loadout
end
local function usable(hull,policy,loadout,price)
 local stats=require('src.stats').compute(hull,loadout)
 if price>policy.budget or stats.thrust<=0 or stats.powerOut<=0 or stats.hold<(policy.minCargo or 0) then return false end
 local capabilities=require('src.npc_access').capabilities({ship={hull=hull.id,loadout=loadout}})
 for name in pairs(policy.requires or {}) do if not capabilities[name] then return false end end
 return true
end
local function fitted(hull,policy,u,area,stock)
 local loadout={}
 for i,id in ipairs(hull.loadout) do loadout[i]=id end
 -- Fit from what the arrival region actually stocks (src/availability.lua).
 if u and area then loadout=require('src.availability').regionalFit(u,area,hull,loadout,stock) end
 if not install(hull,policy,loadout,u,area,stock) then return end
 local price=require('src.dealers').price(hull,loadout)
 if not usable(hull,policy,loadout,price) then return end
 return loadout,price
end
-- A lot's ship as the dealer would refit it for the job before the sale:
-- the modules it adds are charged at list price on top of the lot price
-- (what it takes out stays with the dealer). Returns loadout, price, or
-- nil when even refitted it can't do the job within the budget.
function S.refit(u,area,lot,policy,stock)
 local hull=data.hulls[lot.hull];if not hull then return end
 local loadout={}
 for i=1,#hull.slots do loadout[i]=lot.loadout[i] or false end
 if not install(hull,policy,loadout,u,area,stock) then return end
 local price=lot.price
 for i in ipairs(hull.slots) do
  local id=loadout[i]
  if id and id~=lot.loadout[i] then price=price+(data.modules[id].price or 0) end
 end
 if not usable(hull,policy,loadout,price) then return end
 return loadout,price
end
function S.generated(u,policy,roll,area,seeding)
 local choices,total={},0
 local stock=area and not seeding and require('src.availability').modules(u,area)
 local ids={}
 if policy.hulls then for _,id in ipairs(policy.hulls) do ids[#ids+1]=id end
 else for _,lineup in pairs(require('data.industry').lineups) do for _,id in ipairs(lineup) do ids[#ids+1]=id end end end
 table.sort(ids)
 for _,id in ipairs(ids) do
  local loadout,price=fitted(data.hulls[id],policy,u,not seeding and area or nil,stock)
  if loadout then
   choices[#choices+1]={hull=id,loadout=loadout,price=price,base=S.weight(u,id)}
  end
 end
 -- Role fit decides; factory output, regional lots, local stock and recent
 -- danger shade it (src/ship_fit.lua). Nothing here consumes stock.
 local danger
 if policy.role then danger=select(2,require('src.ship_fit').rank(u,area,policy.role,choices,stock,policy.sharpness,seeding))
 else for _,c in ipairs(choices) do c.weight=c.base end end
 -- a faction's own pilots favor its makers' hulls (src/faction_gear.lua)
 local faction=policy.faction=='$owner' and area and require('src.npc_access').owner(area) or policy.faction
 if faction and faction~='$owner' then
  local Gear=require('src.faction_gear')
  for _,c in ipairs(choices) do if Gear.prefersHull(faction,c.hull) then c.weight=c.weight*Gear.hullWeight end end
 end
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
-- A ship for a pilot the world starts with (src/alife.lua, src/mining.lua
-- seeding): the same role, budget and rank roll an arrival uses, and the
-- same choice of hull and fit (S.generated), made on the spot since no
-- shipyard has built anything yet. Returns ship, policy.
function S.seed(u,area,role)
 local Templates=require('src.npc_templates');local Rank=require('src.npc_rank')
 local base=Templates.purchase(role);if not base then return end
 local policy=Rank.policy(base,Rank.roll())
 -- a faction's police and couriers fly its own service hulls
 local owner=require('src.npc_access').owner(area)
 local fleet=policy.fleets and policy.fleets[owner or '']
 if fleet then policy.hulls=fleet end
 -- The world was running before the game began: what a dealer happens to
 -- have on its lot or shelf this minute doesn't decide what it flies.
 local ship=S.generated(u,policy,nil,area,true)
 return ship,policy
end
-- A seeded pilot set up like an arrival: its rank, its pocket money and
-- full magazines (src/supplies.lua). r may be nil when creation failed.
function S.settle(r,policy)
 if not r then return end
 if policy and policy.rank then r.rank=policy.rank;r.rankXp=require('src.npc_rank').tiers[policy.rank].xp end
 r.shipAcquisition=r.shipAcquisition or {source='seeded'}
 r.credits=(r.credits or 0)+require('src.tuning').npcStartingCredits
 require('src.supplies').provision(r)
 return r
end
function S.acquire(u,area,policy,roll)
 roll=roll or random
 -- A faction with its own service fleet issues those hulls: off its
 -- military yard's lot when it has one (no ship there, no new recruit),
 -- otherwise made on the spot.
 local owner=require('src.npc_access').owner(area)
 local fleet=policy.fleets and policy.fleets[owner or '']
 if fleet and require('src.dealers').serviceYard(owner) then
  local ship,acq=S.fromYard(u,owner,policy)
  if ship then return ship,acq end
  return nil
 end
 local candidate=require('src.dealers').purchaseCandidate(u,area,policy,false)
 if candidate then
  local ship=require('src.dealers').ship(candidate.lot)
  if candidate.loadout then
   -- the refit keeps the lot's wear: armor in the same share of full
   local Stats,hull=require('src.stats'),data.hulls[ship.hull]
   local before=math.max(1,Stats.compute(hull,ship.loadout).armor or 1)
   ship.loadout=require('src.persistence').copy(candidate.loadout)
   ship.armor=Stats.compute(hull,ship.loadout).armor*math.min(1,(ship.armor or before)/before)
  end
  return ship,{source='used',candidate=candidate}
 end
 -- No lot here has a ship for the job: the pilot flies in with one bought
 -- elsewhere, chosen as at seeding, so the fleet holds its fixed size
 -- (T.fleet) instead of shrinking with every loss.
 local ship,acq=S.generated(u,policy,roll,area,true)
 if ship then acq.source='arrived';return ship,acq end
 return nil
end
-- Take a finished hull for `faction` off its military yard. policy.hulls
-- narrows the choice (a flagship asks for its one hull); policy.requires
-- and minCargo are checked as for any purchase. The best fit for the role
-- goes first, by armour when there's no role.
function S.fromYard(u,faction,policy)
 local D=require('src.dealers')
 local key=D.serviceYard(faction);if not key then return end
 local want;if policy.hulls then want={};for _,id in ipairs(policy.hulls) do want[id]=true end end
 local best,bestArmor
 for _,lot in ipairs(D.lots(u,key,true)) do
  local hull=data.hulls[lot.hull]
  local ok=hull and (not want or want[lot.hull])
  if ok then
   local stats=require('src.stats').compute(hull,lot.loadout)
   if (stats.hold or 0)<(policy.minCargo or 0) then ok=false end
   local caps=require('src.npc_access').capabilities({ship={hull=lot.hull,loadout=lot.loadout}})
   for name in pairs(policy.requires or {}) do if not caps[name] then ok=false end end
   -- (police keep the heavy hull for the flagship: smallest first, and a
   -- hull over the pilot's rank budget only when nothing else is there)
   local rank=-(hull.armor or 0)
   if ok and policy.budget and D.price(hull,lot.loadout)>policy.budget then rank=rank-1e9 end
   if ok and (not best or rank>bestArmor or rank==bestArmor and lot.id<best.id) then best,bestArmor=lot,rank end
  end
 end
 if not best then return end
 D.take(u,key,best.id)
 local ship=D.ship(best)
 require('src.simulation_history').note(u,'npc_ship_issued',u.clock,nil,{},{station=key,hull=best.hull,lot=best.id},key)
 return ship,{source='yard',station=key,hull=best.hull,price=0,lot=best.id}
end
function S.complete(u,r,acquisition,policy)
 if policy.rank then r.rank=policy.rank;r.rankXp=require('src.npc_rank').tiers[policy.rank].xp end
 if acquisition.source=='used' then
  if require('src.dealers').buyForNpc(u,r,acquisition.candidate,policy) then
   r.shipAcquisition.source='used'
  else
   -- the lot sold while the pilot was being created: they arrive in the
   -- same hull bought elsewhere, as when no lot has one
   r.shipAcquisition={source='arrived',hull=r.ship and r.ship.hull,price=0}
   r.credits=(r.credits or 0)+require('src.tuning').npcStartingCredits
  end
 else
  -- issued off a faction yard: the faction pays, the pilot starts with
  -- the same pocket money as anyone
  r.shipAcquisition=acquisition
  r.credits=(r.credits or 0)+require('src.tuning').npcStartingCredits
 end
end
return S
