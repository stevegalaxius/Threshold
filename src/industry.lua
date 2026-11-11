-- One facility controller; recipe/facility definitions live in data/industry.lua.
local D=require('data.industry')
local I={}
function I.installations(key)
 local p=require('src.locations').byId[key]
 return p and p.facilities or {}
end
function I.initial(key)
 local out=require('src.reserves').opening(key);local C=require('src.commodities')
 for _,recipe in ipairs(C.list) do if recipe.opening~=nil then out[recipe.item]=recipe.opening end end
 for id,installation in pairs(I.installations(key)) do
  for item,n in pairs(I.definition(id,installation).openingOutputs or {}) do out[item]=(out[item] or 0)+n end
  for item,hours in pairs(I.definition(id,installation).openingInputs or {}) do
   local maximum=0
   for _,recipe in ipairs(I.definition(id,installation).recipes) do
    for _,input in ipairs(C.inputs(C.byId[recipe])) do if input.item==item then maximum=math.max(maximum,input.n) end end
   end
   out[item]=(out[item] or 0)+installation.capacity*maximum*hours
  end
 end
 return out
end
function I.definition(id,installation) return assert(D.facilities[installation.type or id],'unknown facility '..id) end
function I.state(u,key,id)
 u.facilities=u.facilities or {};local k=key..'|'..id
 if not u.facilities[k] then
  local installation=assert(I.installations(key)[id]);local def=I.definition(id,installation)
  local mix={};for _,recipe in ipairs(def.recipes) do mix[recipe]=1/#def.recipes end
  u.facilities[k]={mix=mix,profit={}}
 end
 return u.facilities[k]
end
function I.scale(u,key,c)
 for id,installation in pairs(I.installations(key)) do
  local def=I.definition(id,installation)
  for _,recipe in ipairs(def.recipes) do if recipe==c.id then
   if def.policy=='profit' then return I.state(u,key,id).mix[recipe] or 0 end
   if def.policy=='adaptive' then return (u.industry and u.industry[key] and u.industry[key][recipe] or 1)/#def.recipes end
   return 1/#def.recipes
  end end
 end
 return 0
end
-- Execute whole batches. Input credits permit recipes to use fractions of a
-- cargo unit without fractional stock (e.g. one fertilizer feeds 20 food).
function I.produce(u,key,c,requested,progress,roomOverride)
 local S,C,E=require('src.stockpile'),require('src.commodities'),require('src.economy')
 progress.credit=progress.credit or {}
 local n=math.max(0,math.floor(requested+1e-9))
 for _,output in ipairs(C.outputs(c)) do
  local room=math.max(0,math.floor(((output.cap or c.cap)-S.count(u,key,output.item))/output.n))
  if roomOverride and output.item==c.item then room=roomOverride end
  n=math.min(n,room)
 end
 for _,input in ipairs(C.inputs(c)) do
  n=math.min(n,math.floor((S.available(u,key,input.item)+(progress.credit[input.item] or 0))/input.n+1e-9))
 end
 for _,input in ipairs(C.inputs(c)) do
  local credit=progress.credit[input.item] or 0
  local spent=math.max(0,math.ceil(n*input.n-credit-1e-9))
  if spent>0 then assert(S.take(u,key,input.item,spent));E.consume(u,key,input.item,spent) end
  progress.credit[input.item]=credit+spent-n*input.n
 end
 for _,output in ipairs(C.outputs(c)) do
  if n>0 then S.add(u,key,output.item,n*output.n);E.stat(u,'made',output.item,n*output.n) end
 end
 return n
end
function I.flow(u,key,c,m,dt,rate,roomOverride)
 local S,E=require('src.stockpile'),require('src.economy')
 m.recipes=m.recipes or {};local state=m.recipes[c.id] or {carry=0};m.recipes[c.id]=state
 local work=state.carry+math.abs(rate)*dt/3600/(c.time or 1)
 local whole=math.floor(work+1e-9);local done
 if rate<0 then
  done=math.min(whole,S.available(u,key,c.item));assert(S.take(u,key,c.item,done));E.consume(u,key,c.item,done)
 else done=I.produce(u,key,c,whole,state,roomOverride) end
 -- Blocked time cannot accumulate into an instant burst after resupply.
 state.carry=done<whole and 0 or work-whole
 if rate>0 and not roomOverride then
  for _,output in ipairs(require('src.commodities').outputs(c)) do
   if (output.cap or c.cap)-S.count(u,key,output.item)<output.n then state.carry=0 end
  end
 end
 return done
end
local function move(v,target,step) return target>v and math.min(target,v+step) or math.max(target,v-step) end
function I.allocate(u,clock,stations,market,dt)
 local C,S,G,Transport=require('src.commodities'),require('src.stockpile'),require('src.travelgraph'),require('src.transport')
 for _,key in ipairs(stations) do
  for id,installation in pairs(I.installations(key)) do
   local def=I.definition(id,installation)
   if def.policy=='profit' then
    local state=I.state(u,key,id);local best=nil
    for _,recipe in ipairs(def.recipes) do
     local c=C.byId[recipe];local revenue,cost=0,0
     for _,output in ipairs(C.outputs(c)) do
      local unit,demand=0,0
      for _,bid in ipairs(market.state(u).bids[output.item] or {}) do
       if bid.target~=key and G.itinerary(key,bid.target,clock) then
        unit=math.max(unit,bid.price-Transport.quote({source=key,target=bid.target,amount=1},clock).creditsPerUnit);demand=demand+bid.amount
       end
      end
      if S.count(u,key,output.item)>=demand then unit=0 end
      revenue=revenue+unit*output.n
     end
     for _,input in ipairs(C.inputs(c)) do cost=cost+market.price(u,key,input.item)*input.n end
     local profit=(revenue-cost)/(c.time or 1);state.profit[recipe]=profit
     if revenue>0 and profit>0 and (not best or profit>best) then best=profit end
    end
    local target,tied,total={}, {},0
    for _,recipe in ipairs(def.recipes) do
     target[recipe]=0
     if best and state.profit[recipe]>0 and best-state.profit[recipe]<=math.max(1,best*.1) then tied[#tied+1]=recipe;total=total+(state.mix[recipe] or 0) end
    end
    for _,recipe in ipairs(tied) do target[recipe]=total>0 and (state.mix[recipe] or 0)/total or 1/#tied end
    local sum=0
    for _,recipe in ipairs(def.recipes) do state.mix[recipe]=move(state.mix[recipe] or 0,target[recipe],math.min(1,.05*dt/60));sum=sum+state.mix[recipe] end
    if sum>1 then for _,recipe in ipairs(def.recipes) do state.mix[recipe]=state.mix[recipe]/sum end end
   end
  end
 end
end
function I.panel(game,Slab)
 local L,C,S=require('src.locations'),require('src.commodities'),require('src.stockpile')
 local keys={};for key,p in pairs(L.byId) do if p.facilities then keys[#keys+1]=key end end;table.sort(keys)
 for _,key in ipairs(keys) do
  for id,installation in pairs(I.installations(key)) do
   local def=I.definition(id,installation)
   Slab.Text(L.get(key).name..' / '..id..': '..installation.capacity..' processing units/hour ('..def.policy..')')
   for _,recipe in ipairs(def.recipes) do
    local c=C.byId[recipe]
    Slab.Text(('  %s: %.0f%% | margin %.2f / processing unit'):format(recipe,I.scale(game.universe,key,c)*100,def.policy=='profit' and I.state(game.universe,key,id).profit[recipe] or 0))
    for _,o in ipairs(C.outputs(c)) do Slab.Text(('    %s: stock %d | price %.2f'):format(require('src.data').items[o.item].name,S.count(game.universe,key,o.item),require('src.markets').price(game.universe,key,o.item))) end
    for _,input in ipairs(C.inputs(c)) do Slab.Text(('    Input %s: %d available / %d physical'):format(require('src.data').items[input.item].name,S.available(game.universe,key,input.item),S.count(game.universe,key,input.item))) end
   end
  end
 end
end
return I
