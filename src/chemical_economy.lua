-- Local quotes and shared factory time. Updated with the economy, never per
-- frame; stock catch-up uses the preceding interval's saved allocation.
local L=require('src.locations')
local C={items={nitrates=true,fertilizer=true,explosives=true},products={'fertilizer','explosives'},smooth=600,shift=.05}
function C.state(u)
 u.chemicalEconomy=u.chemicalEconomy or {prices={},factories={},bids={}}
 return u.chemicalEconomy
end
function C.capacity(key) local p=L.byId[L.canonical(key)];return p and p.chemicalCapacity or 0 end
function C.price(u,key,item)
 local s=C.state(u);local prices=s.prices[L.canonical(key)]
 local multiplier=prices and prices[item] or 1
 return math.floor(require('src.data').items[item].price*multiplier*100+.5)/100
end
function C.factory(u,key)
 local factories=C.state(u).factories
 factories[key]=factories[key] or {mix={fertilizer=.5,explosives=.5},profit={}}
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
 local bids={fertilizer={},explosives={}}
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
    target=math.max(.5,1-have/math.max(1,C.capacity(key)*2))
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
   for _,item in ipairs(C.products) do
    local revenue,demand=0,0
    for _,bid in ipairs(bids[item]) do
     if bid.target~=key and G.itinerary(key,bid.target,clock) then
      local freight=Transport.quote({source=key,target=bid.target,amount=1},clock).creditsPerUnit
      revenue=math.max(revenue,bid.price-freight)
      demand=demand+bid.amount
     end
    end
    if snapshot[key][item]>=demand then revenue=0 end
    local recipe=require('src.commodities').byId[item=='fertilizer' and 'make_fertilizer' or 'make_explosives']
    local cost=0
    for _,input in ipairs(require('src.commodities').inputs(recipe)) do cost=cost+C.price(u,key,input.item)*input.n end
    plant.profit[item]=revenue-cost
    if revenue>0 and plant.profit[item]>0 and (not bestProfit or plant.profit[item]>bestProfit) then best,bestProfit=item,plant.profit[item] end
   end
   local target={fertilizer=0,explosives=0}
   if best then
    local other=best=='fertilizer' and 'explosives' or 'fertilizer'
    if plant.profit[other]>0 and math.abs(bestProfit-plant.profit[other])<=math.max(1,bestProfit*.1) then
     local total=plant.mix.fertilizer+plant.mix.explosives
     if total>0 then for _,item in ipairs(C.products) do target[item]=plant.mix[item]/total end
     else target.fertilizer,target.explosives=.5,.5 end
    else target[best]=1 end
   end
   local step=math.min(1,C.shift*dt/E.tick)
   for _,item in ipairs(C.products) do plant.mix[item]=move(plant.mix[item],target[item],step) end
   -- Increasing an idle recipe while its peer ramps down must not exceed capacity.
   local total=plant.mix.fertilizer+plant.mix.explosives
   if total>1 then for _,item in ipairs(C.products) do plant.mix[item]=plant.mix[item]/total end end
  end
 end
end
function C.panel(game,Slab)
 local u=game.universe;local state=C.state(u);local keys={}
 for key in pairs(state.factories) do if C.capacity(key)>0 then keys[#keys+1]=key end end
 table.sort(keys)
 for _,key in ipairs(keys) do
  local plant=state.factories[key];local S=require('src.stockpile')
  Slab.Text(L.get(key).name..' — '..C.capacity(key)..' units/hour shared capacity')
  Slab.Text(('  Nitrates: %d at %.2f cr'):format(S.count(u,key,'nitrates'),C.price(u,key,'nitrates')))
  for _,item in ipairs(C.products) do
   Slab.Text(('  %s: %.0f%% capacity | stock %d | price %.2f | margin %.2f cr/unit'):format(item,100*plant.mix[item],S.count(u,key,item),C.price(u,key,item),plant.profit[item] or 0))
  end
 end
 for _,item in ipairs(C.products) do
  local total=0;for _,bid in ipairs(state.bids[item] or {}) do total=total+bid.amount end
  Slab.Text(('Customer demand: %d %s'):format(total,item))
 end
end
return C
