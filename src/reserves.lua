-- Declarative minimum service inventory, separate from ongoing consumption.
local R={policies={}}
for item,policy in pairs(require('data.industry').reserves) do R.policies[item]=policy end
for _,recipe in ipairs(require('data.industry').recipes) do if recipe.reserve then R.policies[recipe.item]=recipe.reserve end end
function R.minimum(key,item)
 local policy=R.policies[item];if not policy then return 0 end
 local L=require('src.locations');local place=L.byId[key]
 if not place then return 0 end
 if policy.service=='supplies' then
  if not require('src.supplies').supports(key) then return 0 end
 elseif policy.service=='listed' then
  -- the shelf its market data writes for it (data/markets.lua), nothing else
  local n=R.listed(key,item);if n==0 then return 0 end
  policy={minimum=n*require('src.data').items[item].stack,excludeProducers=policy.excludeProducers}
 elseif policy.service and not L.stationServices(key)[policy.service] then return 0 end
 if policy.excludeProducers then
  for _,c in ipairs(require('src.commodities').list) do
   if (c.make[key] or 0)>0 then
    for _,o in ipairs(require('src.commodities').outputs(c)) do if o.item==item then return 0 end end
   end
  end
 end
 return policy.minimum or (policy.stacks or 0)*require('src.data').items[item].stack
end
-- Stacks of an item a station's own market data lists (0 for none).
function R.listed(key,item)
 local mk=require('src.stockpile').definition(key);local n=0
 if not mk then return 0 end
 for _,e in ipairs(mk.sells or {}) do if e[1]==item then n=n+e[2] end end
 for _,shop in ipairs(mk.shops or {}) do for _,e in ipairs(shop.sells or {}) do if e[1]==item then n=n+e[2] end end end
 return n
end
function R.opening(key)
 local out={}
 for item,policy in pairs(R.policies) do out[item]=R.minimum(key,item)*(policy.openingMultiplier or 1) end
 return out
end
return R
