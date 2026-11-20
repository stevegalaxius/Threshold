--[[
	Regular refits: a docked NPC with spare credits looks at the modules this
	station has on its shelves and swaps at most one, if that clearly suits
	its job better (src/ship_fit.lua, with local danger). Rank decides how
	often it bothers and how big an improvement it needs.

	The shelf only steers the choice: stock is checked, never consumed.
	Cost: one check per ship per visit, slots x stocked modules stat passes.
]]
local data=require('src.data')
local L=require('src.locations')
local F=require('src.ship_fit')
local Rank=require('src.npc_rank')
local M={}
M.minCredits=1000      -- below this a ship doesn't shop at all
M.resale=.5            -- credit back for the module taken out

local function shelf(u,node)
 local Stock=require('src.stockpile');local out={}
 local ok,shops=pcall(Stock.shops,node)
 for i,shop in ipairs(ok and shops or {}) do
  for _,e in ipairs(shop.sells or {}) do
   local id=e[1]
   if data.modules[id] and not out[id] then
    local okC,n=pcall(Stock.available,u,node,id,i)
    if shop.unlimited or (okC and n or 0)>0 then out[id]=true end
   end
  end
 end
 return out
end

local function shelfHas(u,node,id)
 local Stock=require('src.stockpile')
 local ok,shops=pcall(Stock.shops,node)
 for i,shop in ipairs(ok and shops or {}) do
  for _,e in ipairs(shop.sells or {}) do
   if e[1]==id then
    local okC,n=pcall(Stock.available,u,node,id,i)
    if shop.unlimited or (okC and n or 0)>0 then return true end
   end
  end
 end
 return false
end

-- The fit profile a ship is scored by: its group's, or for a group with
-- none of its own (wildcats, bounty hunters) the role it buys ships as.
function M.role(r)
 local g=r.populationGroup
 if g and F.profiles[g] then return g end
 local P=g and require('src.npc_templates').purchaseFor(r)
 return P and F.profiles[P.role] and P.role or nil
end
local function keeps(r,hull,loadout)
 return M.keeps(r,hull,loadout)
end
function M.keeps(r,hull,loadout)
 local P=r.populationGroup and require('src.npc_templates').purchaseFor(r)
 local need=P and P.requires or {}
 local s=require('src.stats').compute(hull,loadout)
 if s.thrust<=0 or s.powerOut<=0 then return false end
 if P and P.minCargo and s.hold<P.minCargo then return false end
 local caps=require('src.npc_access').capabilities({ship={hull=hull.id,loadout=loadout}})
 for name in pairs(need) do if not caps[name] then return false end end
 return true
end

-- Returns the swap made ({slot, from, to, cost}) or nil.
function M.dock(r,node,u,clock,roll)
 if not (r.ship and node and u) then return end
 local visit=tostring(node)..'@'..tostring(r.dockedAt or '')
 if r.refitVisit==visit then return end
 r.refitVisit=visit
 Rank.experience(r,1)
 local tier=Rank.get(r);roll=roll or love.math.random
 -- savings burn a hole in the pocket: a pilot holding more than
 -- T.npcSavings looks every visit and settles for a smaller improvement,
 -- the more it holds (this is where NPC money goes back to the stations)
 local T=require('src.tuning')
 local rich=(r.credits or 0)>T.npcSavings
 local chance=rich and 1 or tier.refitChance
 if (r.credits or 0)<M.minCredits or roll()>chance then return end
 if rich then tier=setmetatable({refitMargin=tier.refitMargin*T.npcSavings/r.credits},{__index=tier}) end
 local role=M.role(r)
 if not role then return end
 -- a whole new ship off the lot first; its old one goes up for sale
 local traded=M.hull(r,node,u,clock,tier.refitMargin)
 if traded then return traded end
 local hull=data.hulls[r.ship.hull];if not hull then return end
 local stock=shelf(u,node)
 -- and any player stall's modules here, at its price (src/npc_shopping.lua)
 local offers,stall=require('src.npc_shopping').offers(u,node)
 for id in pairs(offers or {}) do stock[id]=true end
 if not next(stock) then return end
 local base=r.ship.loadout;local trials={{loadout=base}}
 for i,slot in ipairs(hull.slots) do
  local cur=base[i] and data.modules[base[i]]
  for id in pairs(stock) do
   local m=data.modules[id]
   if id~=base[i] and data.fits(slot,m) and (not cur or m.family==cur.family) then
    local lo={};for k,v in ipairs(base) do lo[k]=v end
    for k=#base+1,#hull.slots do lo[k]=false end
    lo[i]=id
    -- the house's price unless only a stall has it, or the stall's is lower
    local price,fromStall=m.price or 0,false
    local house=shelfHas(u,node,id)
    if offers and offers[id] and (not house or offers[id]<price) then price,fromStall=offers[id],true end
    local cost=price-(cur and (cur.price or 0)*M.resale or 0)
    if cost<=(r.credits or 0) and keeps(r,hull,lo) then
     trials[#trials+1]={loadout=lo,slot=i,to=id,from=base[i],cost=math.max(0,cost),stall=fromStall}
    end
   end
  end
 end
 if #trials<2 then return end
 local danger=F.danger(u,r.area);local ref={}
 for _,t in ipairs(trials) do
  t.m=F.metrics(hull,t.loadout)
  for k,v in pairs(t.m) do if v>(ref[k] or 0) then ref[k]=v end end
 end
 local now=F.score(role,trials[1].m,ref,danger);local best
 -- faction pilots lean towards their own faction's weapons (src/faction_gear.lua)
 local Gear=require('src.faction_gear');local faction=Gear.faction(r)
 local function leaning(t)
  if not faction then return 0 end
  return ((Gear.prefersModule(faction,t.to) and 1 or 0)-(Gear.prefersModule(faction,t.from) and 1 or 0))*Gear.refitBonus
 end
 for k=2,#trials do
  local t=trials[k];t.fit=F.score(role,t.m,ref,danger)+leaning(t)
  if not best or t.fit>best.fit or t.fit==best.fit and t.cost<best.cost then best=t end
 end
 -- a Premium stall's module has to be a clearer improvement
 local margin=tier.refitMargin
 if best and best.stall and stall then margin=margin*require('src.stalls').byTag[stall.tag].factor^4 end
 if not best or best.fit-now<margin then return end
 if best.stall then
  -- bought off the player's stall: its stock and the player's takings
  local paid=require('src.stalls').sell(u,L.canonical(node),best.to,1,r,clock)
  if paid<=0 then return end
  local cur=best.from and data.modules[best.from]
  best.cost=math.max(0,paid-(cur and (cur.price or 0)*M.resale or 0))
 end
 r.ship.loadout=best.loadout;r.credits=r.credits-best.cost
 -- the house's module: the station banks what the pilot paid (a stall's
 -- takings went to the player above)
 if not best.stall and best.cost>0 then require('src.accounts').receive(u,node,best.cost,'sold','module:'..best.to) end
 local maximum=require('src.stats').compute(hull,best.loadout).armor
 r.ship.armor=math.min(r.ship.armor or maximum,maximum)
 local swap={slot=best.slot,from=best.from,to=best.to,cost=best.cost,fit=best.fit,was=now,clock=clock}
 r.lastRefit=swap
 require('src.simulation_history').note(u,'npc_refit',clock or u.clock,r.area,{r.id},swap,node)
 return swap
end
-- Ammo for each gun, chosen at the shelf before restocking: a gun keeps
-- what it loads while it has enough aboard or the station has it, else it
-- switches to the cheapest round it takes that this station has in stock.
-- (Runs on every docking at a market; it costs nothing until bought.)
function M.ammo(r,u,key,e)
 local ship=r.ship;if not ship then return end
 local loadout=e and e.loadout or ship.loadout or {}
 local loads=e and e.loads or ship.loads or {}
 local cargo=e and e.cargo or ship.cargo or {}
 local Stock=require('src.stockpile');local T=require('src.tuning')
 local function stocked(id) local ok,n=pcall(Stock.available,u,key,id);return ok and (n or 0)>0 end
 local function price(id)
  if type(key)=='table' then return data.items[id].price or 0 end
  return require('src.markets').price(u,key,id)
 end
 local changed=false
 for i,id in pairs(loadout) do
  local m=id and data.modules[id];local w=m and m.weapon
  if w and w.kind~='laser' and w.kind~='drill' then
   local opts=data.ammoOptions(m)
   if #opts>1 then
    local cur=opts[1]
    for _,o in ipairs(opts) do if o==loads[i] then cur=o end end
    local low=(cargo[cur] or 0)<(data.items[cur].stack or 1)*T.npcAmmoThreshold
    if low and not stocked(cur) then
     local best
     for _,o in ipairs(opts) do
      if o~=cur and stocked(o) and (not best or price(o)<price(best)) then best=o end
     end
     if best then loads[i]=best;changed=true end
    end
   end
  end
 end
 if changed then
  ship.loads=require('src.persistence').copy(loads)
  if e then e.loads=loads;require('src.ship').refit(e) end
 end
 return changed
end
-- What's aboard r's ship, moved into a hold for hull/loadout, plus what
-- the lot ship already carries (extra: its fuel) as far as it fits. nil
-- when the ship's own cargo doesn't all fit.
function M.moveHold(r,hull,loadout,extra)
 local Hold=require('src.inventory.hold')
 local actor={hull=hull,loadout=loadout,stats=require('src.stats').compute(hull,loadout)}
 local layout=require('src.ship').holdLayout(actor)
 local h
 if r.ship.hold then
  local left
  h,left=Hold.relayout(Hold.deserialize(r.ship.hold),layout)
  if next(left) then return end
 else
  h=Hold.new(layout,true)
  for id,n in pairs(r.ship.cargo or {}) do
   if n>0 and Hold.add(h,id,n)~=n then return end
  end
 end
 for id,n in pairs(extra or {}) do Hold.add(h,id,n) end
 return h
end
-- Trade the whole ship in for one on this station's dealer lot when one
-- scores better for the job by more than margin (the same fit scoring the
-- module refit and arrivals use). Its cargo moves into the new hold, so
-- a lot ship whose hold can't take it all isn't a choice. The old ship goes on the lot (Dealers.resell) at the
-- player's trade-in price. Returns the trade, or nil.
function M.hull(r,node,u,clock,margin)
 local D=require('src.dealers');local def=D.def(node)
 if not def or def.service then return end
 local role=M.role(r);if not role then return end
 -- (the hull and its fit only: the cargo moves across, it isn't sold)
 local credit=require('src.game').shipSellPrice({hull=r.ship.hull,loadout=r.ship.loadout})
 local budget=(r.credits or 0)+credit-M.minCredits
 -- (no role cap: the purchase budget only limits the hull an NPC starts
 -- in; one that has earned the money can trade up to anything on the lot)
 local choices={{hull=r.ship.hull,loadout=r.ship.loadout,price=0,key='0 current'}}
 for _,lot in ipairs(D.lots(u,node)) do
  local hull=data.hulls[lot.hull]
  local hold=hull and lot.price<=budget and keeps(r,hull,lot.loadout) and M.moveHold(r,hull,lot.loadout,lot.cargo)
  if hold then
   choices[#choices+1]={hull=lot.hull,loadout=lot.loadout,price=lot.price,lot=lot,hold=hold,key=('1 %08d'):format(lot.id)}
  end
 end
 if #choices<2 then return end
 local best=F.best(u,r.area,role,choices)
 if not best.lot or best.fit-choices[1].fit<(margin or 0) then return end
 local old=r.ship
 D.resell(u,node,old)
 D.take(u,node,best.lot.id)
 r.ship=D.ship(best.lot);r.ship.armor=best.lot.armor
 -- everything aboard moves across to the new hold
 local Hold=require('src.inventory.hold')
 if old.hold then r.ship.hold=Hold.serialize(best.hold) end
 r.ship.cargo=Hold.totals(best.hold)
 r.credits=(r.credits or 0)+credit-best.lot.price
 -- the dealer banks the sale and pays the trade-in out of its own account
 local Accounts=require('src.accounts')
 Accounts.receive(u,node,best.lot.price,'sold','ship:'..best.lot.hull)
 Accounts.pay(u,node,credit,'bought','ship:'..old.hull)
 local trade={from=old.hull,to=best.lot.hull,price=best.lot.price,credit=credit,fit=best.fit,was=choices[1].fit,clock=clock}
 r.lastShipTrade=trade
 require('src.simulation_history').note(u,'npc_ship_traded',clock or u.clock,r.area,{r.id},trade,node)
 return trade
end
-- The same refit for a live NPC ship docked in the scene you're flying
-- in, once per docking (src/npc_repair.lua). The record is brought up to
-- date from the ship first; a new module is fitted to the live ship, and a
-- new hull replaces it: the old ship stays where it was parked, now on the
-- dealer lot, and the new one wakes docked at the same station.
function M.online(game,e,r,st)
 local A=require('src.alife')
 A.capture(game,e,false)
 if r.state~='docked' or not r.ship then return end
 local u=game.universe;local node=st.locationId or st.key
 r.refitVisit=nil   -- (the docking itself is the once-per-visit guard here)
 local old=r.ship
 old.bay,old.mooring=e.bay,e.parkingMooring
 local result=M.dock(r,node,u,u.clock)
 old.bay,old.mooring=nil,nil
 if not result then return end
 if result.slot then
  e.loadout=require('src.persistence').copy(r.ship.loadout)
  require('src.ship').refit(e)
  e.armor=math.min(e.armor,e.stats.armor)
  return result
 end
 -- a whole new ship
 if r.docking then r.docking.mooring=nil end
 game:remove(e,true)
 A.wake(game,r)
 return result
end
return M
