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

local function keeps(r,hull,loadout)
 return M.keeps(r,hull,loadout)
end
function M.keeps(r,hull,loadout)
 local T=r.populationGroup and require('src.npc_templates')[r.populationGroup]
 local need=T and T.purchase and T.purchase.requires or {}
 local s=require('src.stats').compute(hull,loadout)
 if s.thrust<=0 or s.powerOut<=0 then return false end
 if T and T.purchase.minCargo and s.hold<T.purchase.minCargo then return false end
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
 if (r.credits or 0)<M.minCredits or roll()>tier.refitChance then return end
 local role=r.populationGroup
 if not (role and F.profiles[role]) then return end
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
 local maximum=require('src.stats').compute(hull,best.loadout).armor
 r.ship.armor=math.min(r.ship.armor or maximum,maximum)
 local swap={slot=best.slot,from=best.from,to=best.to,cost=best.cost,fit=best.fit,was=now,clock=clock}
 r.lastRefit=swap
 require('src.simulation_history').note(u,'npc_refit',clock or u.clock,r.area,{r.id},swap,node)
 return swap
end
-- Trade the whole ship in for one on this station's dealer lot when one
-- scores better for the job by more than margin (the same fit scoring the
-- module refit and arrivals use). Its hold has to be empty, so nothing is
-- lost in the swap. The old ship goes on the lot (Dealers.resell) at the
-- player's trade-in price. Returns the trade, or nil.
function M.hull(r,node,u,clock,margin)
 local D=require('src.dealers');local def=D.def(node)
 if not def or def.service then return end
 local role=r.populationGroup
 local Hold=require('src.inventory.hold')
 local h=r.ship.hold and Hold.deserialize(r.ship.hold)
 for _,n in pairs(h and Hold.totals(h) or r.ship.cargo or {}) do if n>0 then return end end
 local credit=require('src.game').shipSellPrice(r.ship)
 local budget=(r.credits or 0)+credit-M.minCredits
 local choices={{hull=r.ship.hull,loadout=r.ship.loadout,price=0,key='0 current'}}
 for _,lot in ipairs(D.lots(u,node)) do
  local hull=data.hulls[lot.hull]
  if hull and lot.price<=budget and keeps(r,hull,lot.loadout) then
   choices[#choices+1]={hull=lot.hull,loadout=lot.loadout,price=lot.price,lot=lot,key=('1 %08d'):format(lot.id)}
  end
 end
 if #choices<2 then return end
 local best=F.best(u,r.area,role,choices)
 if not best.lot or best.fit-choices[1].fit<(margin or 0) then return end
 local old=r.ship
 D.resell(u,node,old)
 D.take(u,node,best.lot.id)
 r.ship=D.ship(best.lot);r.ship.armor=best.lot.armor
 r.credits=(r.credits or 0)+credit-best.lot.price
 local trade={from=old.hull,to=best.lot.hull,price=best.lot.price,credit=credit,fit=best.fit,was=choices[1].fit,clock=clock}
 r.lastShipTrade=trade
 require('src.simulation_history').note(u,'npc_ship_traded',clock or u.clock,r.area,{r.id},trade,node)
 return trade
end
return M
