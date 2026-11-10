-- Local quotes and shared factory time. Updated with the economy, never per
-- frame; stock catch-up uses the preceding interval's saved allocation.
local L=require('src.locations')
local Ammo=require('src.ammunition')
local C={items={nitrates=true,fertilizer=true,explosives=true,steel_plate=true},products={'fertilizer','explosives'},smooth=600,shift=.05}
C.groups={chemicals={'fertilizer','explosives'},ammunition=Ammo.products}
for _,item in ipairs(Ammo.products) do C.products[#C.products+1]=item;C.items[item]=true end
function C.state(u)
 u.chemicalEconomy=u.chemicalEconomy or {prices={},factories={},bids={}}
 return u.chemicalEconomy
end
function C.capacity(key) local p=L.byId[L.canonical(key)];return p and (p.chemicalCapacity or p.ammunitionCapacity) or 0 end
function C.productsFor(key)
 local p=L.byId[L.canonical(key)]
 return p and p.ammunitionCapacity and C.groups.ammunition or C.groups.chemicals
end
function C.recipe(item)
 return Ammo.byItem[item] or require('src.commodities').byId[item=='fertilizer' and 'make_fertilizer' or 'make_explosives']
end
function C.price(u,key,item)
 local s=C.state(u);local prices=s.prices[L.canonical(key)]
 local multiplier=prices and prices[item] or 1
 return math.floor(require('src.data').items[item].price*multiplier*100+.5)/100
end
function C.factory(u,key)
 local factories=C.state(u).factories
 if not factories[key] then
  local products=C.productsFor(key);local mix={}
  for _,item in ipairs(products) do mix[item]=1/#products end
  factories[key]={mix=mix,profit={}}
 end
 return factories[key]
end
function C.scale(u,key,item)
 if C.capacity(key)<=0 then return 0 end
 return C.factory(u,key).mix[item] or 0
end
function C.shop()
 return {id='chemicals',name='Chemicals',description='Nitrates, agricultural fertilizer and industrial explosives.',sells={{'nitrates',1},{'fertilizer',1},{'explosives',1}}}
end
local function move(value,target,step)
 if target>value then return math.min(target,value+step) end
 return math.max(target,value-step)
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
    local recipe=Ammo.byItem[item]
    target=math.max(.5,1-have/math.max(1,C.capacity(key)*2*(recipe and recipe.batch or 1)))
   end
   local alpha=1-math.exp(-dt/C.smooth)
   prices[item]=math.max(.5,math.min(2,(prices[item] or 1)+(target-(prices[item] or 1))*alpha))
   if bids[item] and want>0 and have<want*2 then
    bids[item][#bids[item]+1]={target=key,amount=math.ceil(want*2-have),price=C.price(u,key,item)}
   end
  end
 end
 state.bids=bids;state.at=clock
 local G,Transport=require('src.travelgraph'),require('src.transport')
 for _,key in ipairs(stations) do
  if C.capacity(key)>0 then
   local plant=C.factory(u,key);local best,bestProfit
   local products=C.productsFor(key)
   for _,item in ipairs(products) do
    local revenue,demand=0,0
    for _,bid in ipairs(bids[item]) do
     if bid.target~=key and G.itinerary(key,bid.target,clock) then
      local freight=Transport.quote({source=key,target=bid.target,amount=1},clock).creditsPerUnit
      revenue=math.max(revenue,bid.price-freight)
      demand=demand+bid.amount
     end
    end
    if snapshot[key][item]>=demand then revenue=0 end
    local recipe=C.recipe(item)
    local cost=0
    for _,input in ipairs(require('src.commodities').inputs(recipe)) do cost=cost+C.price(u,key,input.item)*input.n end
    plant.profit[item]=revenue*(recipe.batch or 1)-cost
    if revenue>0 and plant.profit[item]>0 and (not bestProfit or plant.profit[item]>bestProfit) then best,bestProfit=item,plant.profit[item] end
   end
   local target={};for _,item in ipairs(products) do target[item]=0 end
   if best then
    local tied,total={},0
    for _,item in ipairs(products) do
     if plant.profit[item]>0 and bestProfit-plant.profit[item]<=math.max(1,bestProfit*.1) then
      tied[#tied+1]=item;total=total+(plant.mix[item] or 0)
     end
    end
    for _,item in ipairs(tied) do target[item]=total>0 and (plant.mix[item] or 0)/total or 1/#tied end
   end
   local step=math.min(1,C.shift*dt/E.tick)
   for _,item in ipairs(products) do plant.mix[item]=move(plant.mix[item] or 0,target[item],step) end
   local total=0;for _,item in ipairs(products) do total=total+plant.mix[item] end
   if total>1 then for _,item in ipairs(products) do plant.mix[item]=plant.mix[item]/total end end
  end
 end
end
function C.panel(game,Slab)
 local u=game.universe;local state=C.state(u);local keys={}
 for key in pairs(state.factories) do if C.capacity(key)>0 then keys[#keys+1]=key end end
 table.sort(keys)
 for _,key in ipairs(keys) do
  local plant=state.factories[key];local S=require('src.stockpile')
  local ammo=L.get(key).ammunitionCapacity~=nil
  Slab.Text(L.get(key).name..' — '..C.capacity(key)..(ammo and ' batches/hour' or ' units/hour')..' shared capacity')
  for _,input in ipairs(ammo and {'steel_plate','explosives'} or {'nitrates'}) do
   Slab.Text(('  %s: %d at %.2f cr'):format(require('src.data').items[input].name,S.count(u,key,input),C.price(u,key,input)))
  end
  for _,item in ipairs(C.productsFor(key)) do
   Slab.Text(('  %s: %.0f%% capacity | stock %d | price %.2f | margin %.2f cr/batch'):format(require('src.data').items[item].name,100*plant.mix[item],S.count(u,key,item),C.price(u,key,item),plant.profit[item] or 0))
  end
 end
 for _,item in ipairs(C.products) do
  local total=0;for _,bid in ipairs(state.bids[item] or {}) do total=total+bid.amount end
  Slab.Text(('Customer demand: %d %s'):format(total,require('src.data').items[item].name))
 end
end
return C
