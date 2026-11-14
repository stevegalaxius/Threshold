--[[
	Role fit: how well a hull and loadout suit an NPC's job.

	The economy steers this choice but the NPC does not trade in it. Regional
	stock, scarcity and recent danger shade the score; nothing is consumed.

	F.metrics(hull, loadout)        -> { hold, armor, firepower, drill, agility }
	F.score(role, metrics, ref, danger) -> 0..1, against the best metric in ref
	F.danger(u, area)               -> 0..1 from recent NPC deaths in the area
	F.rank(u, area, role, choices)  -> sets choice.fit and choice.weight
	F.best(u, area, role, choices)  -> highest-fit choice (deterministic)
]]
local data=require('src.data')
local F={}
local SIZE={S=1,M=2,L=4}

-- What each job values. Weights are relative; missing stats count zero.
F.profiles={
 trader  ={hold=1,   armor=.3, agility=.3, firepower=.1},
 miner   ={drill=1,  hold=.6, armor=.2},
 salvager={hold=.6,  firepower=.5, armor=.4, agility=.2},
 patrol  ={firepower=1, armor=.6, agility=.5},
 pirate  ={firepower=1, agility=.7, armor=.3, hold=.2},
}
-- Danger pushes every role toward these stats, on top of its profile.
F.dangerWeights={armor=.6,firepower=.4}
F.dangerHours=24       -- deaths this recent count toward danger
F.dangerDeaths=6       -- this many recent deaths is full danger
F.sharpness=4          -- weight = (fit/best)^sharpness; higher = pickier
F.localHull=1.5        -- hull already on a lot in the region
F.missingModule=.75    -- per fitted module the region stocks none of

function F.metrics(hull,loadout)
 local s=require('src.stats').compute(hull,loadout)
 local m={hold=s.hold or 0,armor=s.armor or 0,firepower=0,drill=0,
  agility=(s.thrust or 0)/math.max(1,s.mass or 1)}
 for i in ipairs(hull.slots) do
  local mod=loadout[i] and data.modules[loadout[i]]
  local w=mod and mod.weapon
  if w then
   local size=SIZE[mod.size or 'S'] or 1
   if w.kind=='drill' then m.drill=m.drill+size
   else
    local mult=w.kind=='missile' and s.mult.missileDamage or s.mult.primaryDamage*s.mult.primaryFireRate
    m.firepower=m.firepower+size*mult
   end
  end
 end
 return m
end

local function weights(role,danger)
 local p=F.profiles[role] or F.profiles.trader;local w={}
 for k,v in pairs(p) do w[k]=v end
 for k,v in pairs(F.dangerWeights) do w[k]=(w[k] or 0)+v*(danger or 0) end
 return w
end

-- ref[stat] is the best value of that stat among the candidates.
function F.score(role,m,ref,danger)
 local w=weights(role,danger);local total,sum=0,0
 for k,v in pairs(w) do
  total=total+v
  local top=ref[k] or 0
  if top>0 then sum=sum+v*math.min(1,(m[k] or 0)/top) end
 end
 return total>0 and sum/total or 0
end

function F.danger(u,area)
 if not (u and area) then return 0 end
 local since=(u.clock or 0)-F.dangerHours*3600
 local deaths=require('src.simulation_history').recent(u,{kind='npc_died',area=area,since=since},F.dangerDeaths)
 return math.min(1,#deaths/F.dangerDeaths)
end

local function regionalHulls(u,area)
 local out={}
 if not (u and area) then return out end
 local D=require('src.dealers')
 for _,id in ipairs(require('src.locations').stations(area)) do
  local ok,lots=pcall(D.lots,u,id)
  for _,lot in ipairs(ok and lots or {}) do out[lot.hull]=true end
 end
 return out
end

-- How much of a fit the region cannot supply (regionalFit already swapped in
-- what it could). Only applies when the region stocks modules at all.
local function scarcity(loadout,stock)
 if not (stock and next(stock)) then return 1 end
 local k=1
 for _,id in ipairs(loadout) do
  if id and stock[id] and stock[id].count<=0 then k=k*F.missingModule end
 end
 return k
end

-- choices: { {hull=id, loadout=, base=weight?}, ... }. Each gets .fit (0..1)
-- and .weight (fit relative to the best, sharpened, times regional bias
-- and any base weight such as factory output).
function F.rank(u,area,role,choices,stock)
 local danger=F.danger(u,area);local ref={}
 for _,c in ipairs(choices) do
  c.metrics=F.metrics(data.hulls[c.hull],c.loadout)
  for k,v in pairs(c.metrics) do if v>(ref[k] or 0) then ref[k]=v end end
 end
 local best=0
 for _,c in ipairs(choices) do c.fit=F.score(role,c.metrics,ref,danger);best=math.max(best,c.fit) end
 local here=regionalHulls(u,area)
 for _,c in ipairs(choices) do
  local rel=best>0 and c.fit/best or 1
  c.weight=rel^F.sharpness*(c.base or 1)*(here[c.hull] and F.localHull or 1)*scarcity(c.loadout,stock)
 end
 return choices,danger
end

-- Highest fit, cheaper on ties, then stable by key.
function F.best(u,area,role,choices)
 F.rank(u,area,role,choices)
 local best
 for _,c in ipairs(choices) do
  if not best or c.fit>best.fit+1e-9
   or math.abs(c.fit-best.fit)<=1e-9 and ((c.price or 0)<(best.price or 0)
    or (c.price or 0)==(best.price or 0) and (c.key or '')<(best.key or '')) then best=c end
 end
 return best
end

return F
