-- Local market quotes, independent of the production controller.
local L=require('src.locations')
local T=require('src.tuning')
local C={items={},products={},smooth=600}
for item in pairs(T.priceDriven or {}) do C.products[#C.products+1]=item;C.items[item]=true end
for _,recipe in ipairs(require('data.industry').recipes) do
 if recipe.market then
  for _,o in ipairs(require('src.commodities').outputs(recipe)) do
   if not C.items[o.item] then C.products[#C.products+1]=o.item end
   C.items[o.item]=true
  end
 end
end
-- Does this station's price for this good float with its stock? Market
-- goods float everywhere. On a dark grid nothing has a fixed price: the
-- shadow market bids up whatever it's short of, food and fuel included,
-- and that bid is what draws smugglers in.
function C.floats(key,item)
 return C.items[item] or (key~=nil and require('src.dark').isDarkNode(key)) or false
end
function C.state(u) u.markets=u.markets or {prices={},bids={}};return u.markets end
-- The quoted price: the stock-driven multiplier, times what the news has
-- done to it here (src/news.lua: speculation on stories, quest shocks).
local News=require('src.news')
--
-- A station never sells a good it bought in for less than it paid for it
-- landed (goods and freight, C.landed) plus T.resaleMargin, fixed-price
-- goods like fuel included: hubs passing fuel on at list price after
-- paying the freight to bring it were where the factions' money went.
-- (Up to T.priceCrisisMax times list.)
function C.price(u,key,item)
 key=L.canonical(key)
 local s=C.state(u);local prices=s.prices[key]
 local multiplier=prices and prices[item] or 1
 if u.news then multiplier=multiplier*News.factor(u,key,item) end
 -- lasting world-state changes (a leaderless faction's markets: src/worldstate.lua)
 if u.worldstate then multiplier=multiplier*require('src.worldstate').mul(u,'price',key,item) end
 local list=require('src.data').items[item].price
 local p=list*multiplier
 local basis=C.basis(u,key,item)
 if basis and not T.priceDriven[item] then p=math.max(p,math.min(list*T.priceCrisisMax,basis*(1+T.resaleMargin))) end
 return math.floor(p*100+.5)/100
end
-- Where a station sits in its system's supply chain bends its price:
--  crisis   a shortage left unserved past T.priceCrisisHours may climb
--           to T.priceCrisisMax instead of 2x;
--  maker    a station that makes the good sells it T.makerDiscount under
--           what its stock alone would say;
--  landed   a station that imports through its system's hub never prices
--           the good below the hub's price plus the local freight to bring
--           it over, so goods get dearer the further they travel.
local function makes(key,item) return require('src.commodities').makes(key,item) end
local hubs={}   -- station -> its hub (fixed by the world layout)
-- What a unit of a good cost this station landed, averaged over its stock
-- (nil until it has bought some in). Kept on the stockpile record.
function C.basis(u,key,item)
 local b=require('src.stockpile').record(u,L.canonical(key)).basis
 return b and b[item]
end
function C.landed(u,key,item,amount,cost)
 if not amount or amount<=0 or not cost or cost<=0 then return end
 local S=require('src.stockpile');key=L.canonical(key)
 local r=S.record(u,key);r.basis=r.basis or {}
 local held=math.max(0,S.count(u,key,item)-amount)
 local old=r.basis[item] or cost/amount
 r.basis[item]=(old*held+cost)/(held+amount)
end
function C.shape(u,key,item,target,want,clock,state)
 local E=require('src.economy')
 if want>0 and E.shortageAge(u,key,item,clock)>=T.priceCrisisHours*3600 then
  local age=E.shortageAge(u,key,item,clock)/(T.priceCrisisHours*3600)
  target=target+(T.priceCrisisMax-2)*math.min(1,age-1)
 end
 if makes(key,item) then
  -- a maker of a price-driven good prices by its own output shelf: dear
  -- when freight has emptied it, cheap when full (src/economy.lua adjust
  -- runs the plant by the same shelf)
  if T.priceDriven[item] then
   local fill=math.min(1,require('src.stockpile').count(u,key,item)/(require('src.economy').lot*T.makerShelfLots))
   return T.makerPriceEmpty-(T.makerPriceEmpty-T.makerPriceFull)*fill
  end
  return target*(1-T.makerDiscount)
 end
 local hub=hubs[key];if hub==nil then hub=E.hubFor(key) or false;hubs[key]=hub end
 if hub and hub~=key and want>0 then
  local d=require('src.data').items[item]
  local hubPrice=(state.prices[hub] or {})[item] or 1
  local freight=(d.volume or 1)*T.freightCreditsPerM3/math.max(1,d.price or 1)
  target=math.max(target,hubPrice+freight)
 end
 return target
end
local function stockPrice(ratio,crisis)
 if ratio>=1 then return math.max(.5,1-.5*(ratio-1)) end
 return 1+(crisis-1)*(1-ratio)
end
function C.expectedTradePrice(u,buyer,item,amount)
 local current=C.price(u,buyer,item)
 local state=C.state(u)
 local snapshot=state.deliveryStock and state.deliveryStock[buyer..'|'..item]
 if not snapshot or snapshot.want<=0 then return current end
 -- Prices already react to committed shipments at the next market tick.
 -- Include this claim too, weighted by how far the market can move en route.
 local ratio=(snapshot.have+amount)/snapshot.want
 local projected=stockPrice(ratio,T.priceCrisisMax)*require('src.data').items[item].price
 return math.min(current,(current+projected)*.5)
end
function C.update(u,clock,stations,inbound,pause)
 local S,E=require('src.stockpile'),require('src.economy')
 local state=C.state(u);local dt=state.at and math.max(0,clock-state.at) or E.tick
 -- Read all inventory before changing any prices or allocation. This settles
 -- elapsed production against its old settings and keeps results query-order independent.
 local snapshot={}
 for i,key in ipairs(stations) do
  if pause and i>1 then pause() end
  snapshot[key]={}
  for item in pairs(C.items) do snapshot[key][item]=S.count(u,key,item) end
  if require('src.dark').isDarkNode(key) then for _,item in ipairs(E.goods()) do snapshot[key][item]=S.count(u,key,item) end end
 end
 local bids,deliveryStock={},{}
 for _,item in ipairs(C.products) do bids[item]={} end
 for _,key in ipairs(stations) do
  if pause then pause() end
  local prices=state.prices[key] or {};state.prices[key]=prices
  local floating=C.items
  if require('src.dark').isDarkNode(key) then
   floating={};for item in pairs(C.items) do floating[item]=true end
   for _,item in ipairs(E.goods()) do floating[item]=true end
  end
  local dark=floating~=C.items
  for item in pairs(floating) do
   -- a dark maker prices against the stock it keeps for itself, not its
   -- whole buffer, so a full farm sells cheap and the gap to a hungry
   -- station is what pays the smuggler
   -- (a hub or customs depot wants the stock it holds for its system)
   local want=E.hubTarget(u,key,item,dark and not C.items[item] and (makes(key,item) or item==require('src.food').item and select(2,require('src.food').rates(key))>0) or nil)
   local coming=(inbound[key..'|'..item] or 0)
   local have=snapshot[key][item]+coming
   if T.priceDriven[item] and want>0 then deliveryStock[key..'|'..item]={have=have,want=want} end
   local target
   if want>0 then
    local ratio=have/want
    target=ratio<1 and 2-ratio or math.max(.5,1-.5*(ratio-1))
    -- a price-driven consumer's bid climbs to the crisis cap as its shelf
    -- (stock plus inbound) empties, so a long haul still pays
    if T.priceDriven[item] and ratio<1 and not E.isBuffer(key,item) then target=1+(T.priceCrisisMax-1)*(1-ratio) end
   else
    -- No local use means no scarcity premium, including an empty factory shelf.
    local reference=require('src.commodities').output(key,item)
    target=math.max(.5,1-have/math.max(1,reference*2))
   end
   local driven=T.priceDriven[item]
   local buffer=driven and E.isBuffer(key,item)
   if buffer then target=1+(target-1)*T.hubPriceBand end
   target=C.shape(u,key,item,target,want,clock,state)
   local alpha=1-math.exp(-dt/C.smooth)
   local top=want>0 and (E.shortageAge(u,key,item,clock)>=T.priceCrisisHours*3600 or driven and not buffer and have<want) and T.priceCrisisMax or 2
   -- (a price-driven maker with a full shelf may sell under the usual floor,
   -- so a far buyer's haul can still pay)
   local floor=driven and makes(key,item) and T.makerPriceFull or T.priceFloor
   prices[item]=math.max(floor,math.min(top,(prices[item] or 1)+(target-(prices[item] or 1))*alpha))
   -- (bid for what the station's next order will be: up to its order level)
   -- (a price-driven good bids only up to its target: bidding to the
   -- reorder level kept every shelf bidding and its makers at full tilt)
   local level=want>0 and (makes(key,item) and want*2 or driven and want or E.orderLevel(u,key,item,want,false)) or 0
   -- (a bare shelf of a small, slow good bids at least a minimum load, or
   -- its makers never hear of it)
   if driven and want>0 and have<=0 then level=math.max(level,T.orderMinLoad) end
   if bids[item] and want>0 and have<level then
    bids[item][#bids[item]+1]={target=key,amount=math.ceil(level-have),price=C.price(u,key,item)}
   end
  end
 end
 state.bids=bids;state.deliveryStock=deliveryStock;state.at=clock
 if pause then pause() end
 require('src.industry').allocate(u,clock,stations,C,dt,pause)
end
return C
