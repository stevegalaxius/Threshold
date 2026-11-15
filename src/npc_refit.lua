--[[
	Regular refits: a docked NPC with spare credits looks at the modules this
	station has on its shelves and swaps at most one, if that clearly suits
	its job better (src/ship_fit.lua, with local danger). Rank decides how
	often it bothers and how big an improvement it needs.

	The shelf only steers the choice: stock is checked, never consumed.
	Cost: one check per ship per visit, slots x stocked modules stat passes.
]]
local data=require('src.data')
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

local function keeps(r,hull,loadout)
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
 local hull=data.hulls[r.ship.hull];if not hull then return end
 local stock=shelf(u,node);if not next(stock) then return end
 local base=r.ship.loadout;local trials={{loadout=base}}
 for i,slot in ipairs(hull.slots) do
  local cur=base[i] and data.modules[base[i]]
  for id in pairs(stock) do
   local m=data.modules[id]
   if id~=base[i] and data.fits(slot,m) and (not cur or m.family==cur.family) then
    local lo={};for k,v in ipairs(base) do lo[k]=v end
    for k=#base+1,#hull.slots do lo[k]=false end
    lo[i]=id
    local cost=(m.price or 0)-(cur and (cur.price or 0)*M.resale or 0)
    if cost<=(r.credits or 0) and keeps(r,hull,lo) then
     trials[#trials+1]={loadout=lo,slot=i,to=id,from=base[i],cost=math.max(0,cost)}
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
 for k=2,#trials do
  local t=trials[k];t.fit=F.score(role,t.m,ref,danger)
  if not best or t.fit>best.fit or t.fit==best.fit and t.cost<best.cost then best=t end
 end
 if not best or best.fit-now<tier.refitMargin then return end
 r.ship.loadout=best.loadout;r.credits=r.credits-best.cost
 local maximum=require('src.stats').compute(hull,best.loadout).armor
 r.ship.armor=math.min(r.ship.armor or maximum,maximum)
 local swap={slot=best.slot,from=best.from,to=best.to,cost=best.cost,fit=best.fit,was=now,clock=clock}
 r.lastRefit=swap
 require('src.simulation_history').note(u,'npc_refit',clock or u.clock,r.area,{r.id},swap,node)
 return swap
end
return M
