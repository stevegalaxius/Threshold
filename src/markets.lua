-- Local market quotes, independent of the production controller.
local L=require('src.locations')
local T=require('src.tuning')
local C={items={},products={},smooth=600}
for _,recipe in ipairs(require('data.industry').recipes) do
 if recipe.market then
  for _,o in ipairs(require('src.commodities').outputs(recipe)) do
   if not C.items[o.item] then C.products[#C.products+1]=o.item end
   C.items[o.item]=true
  end
 end
end
function C.state(u) u.markets=u.markets or {prices={},bids={}};return u.markets end
function C.price(u,key,item)
 local s=C.state(u);local prices=s.prices[L.canonical(key)]
 local multiplier=prices and prices[item] or 1
 return math.floor(require('src.data').items[item].price*multiplier*100+.5)/100
end
-- Where a station sits in its system's supply chain bends its price:
--  crisis   a shortage left unserved past T.priceCrisisHours may climb
--           to T.priceCrisisMax instead of 2x;
--  maker    a station that makes the good sells it T.makerDiscount under
--           what its stock alone would say;
--  landed   a station that imports through its system's hub never prices
--           the good below the hub's price plus the local freight to bring
--           it over, so goods get dearer the further they travel.
local function makes(key,item)
 for _,recipe in ipairs(require('src.commodities').list) do
  if (recipe.make[key] or 0)>0 then
   for _,output in ipairs(require('src.commodities').outputs(recipe)) do if output.item==item then return true end end
  end
 end
 return false
end
local hubs={}   -- station -> its hub (fixed by the world layout)
function C.shape(u,key,item,target,want,clock,state)
 local E=require('src.economy')
 if want>0 and E.shortageAge(u,key,item,clock)>=T.priceCrisisHours*3600 then
  local age=E.shortageAge(u,key,item,clock)/(T.priceCrisisHours*3600)
  target=target+(T.priceCrisisMax-2)*math.min(1,age-1)
 end
 if makes(key,item) then return target*(1-T.makerDiscount) end
 local hub=hubs[key];if hub==nil then hub=E.hubFor(key) or false;hubs[key]=hub end
 if hub and hub~=key and want>0 then
  local d=require('src.data').items[item]
  local hubPrice=(state.prices[hub] or {})[item] or 1
  local freight=(d.volume or 1)*T.freightCreditsPerM3/math.max(1,d.price or 1)
  target=math.max(target,hubPrice+freight)
 end
 return target
end
function C.update(u,clock,stations,inbound)
 local S,E=require('src.stockpile'),require('src.economy')
 local state=C.state(u);local dt=state.at and math.max(0,clock-state.at) or E.tick
 -- Read all inventory before changing any prices or allocation. This settles
 -- elapsed production against its old settings and keeps results query-order independent.
 local snapshot={}
 for _,key in ipairs(stations) do
  snapshot[key]={}
  for item in pairs(C.items) do snapshot[key][item]=S.count(u,key,item) end
 end
 local bids={}
 for _,item in ipairs(C.products) do bids[item]={} end
 for _,key in ipairs(stations) do
  local prices=state.prices[key] or {};state.prices[key]=prices
  for item in pairs(C.items) do
   local want=E.target(u,key,item)
   local coming=(inbound[key..'|'..item] or 0)
   local have=snapshot[key][item]+coming
   local target
   if want>0 then
    local ratio=have/want
    target=ratio<1 and 2-ratio or math.max(.5,1-.5*(ratio-1))
   else
    -- No local use means no scarcity premium, including an empty factory shelf.
    local reference=0
    for _,recipe in ipairs(require('src.commodities').list) do
     for _,output in ipairs(require('src.commodities').outputs(recipe)) do
      if output.item==item then reference=reference+(recipe.make[key] or 0)*output.n end
     end
    end
    target=math.max(.5,1-have/math.max(1,reference*2))
   end
   target=C.shape(u,key,item,target,want,clock,state)
   local alpha=1-math.exp(-dt/C.smooth)
   local top=want>0 and E.shortageAge(u,key,item,clock)>=T.priceCrisisHours*3600 and T.priceCrisisMax or 2
   prices[item]=math.max(T.priceFloor,math.min(top,(prices[item] or 1)+(target-(prices[item] or 1))*alpha))
   if bids[item] and want>0 and have<want*2 then
    bids[item][#bids[item]+1]={target=key,amount=math.ceil(want*2-have),price=C.price(u,key,item)}
   end
  end
 end
 state.bids=bids;state.at=clock
 require('src.industry').allocate(u,clock,stations,C,dt)
end
return C
