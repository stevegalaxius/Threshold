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
-- An orders facility builds one job at a time. When it has none, it picks
-- the hull the lot is shortest of (ties go round-robin after the last
-- one built) among those with room on the lot, and sticks with it until
-- that ship rolls out, so a heavy hull is never starved by light ones.
function I.job(u,key,id,def)
 local state=I.state(u,key,id)
 local D,C=require('src.dealers'),require('src.commodities')
 -- keep the current job unless nowhere on the lot can take that hull
 local current=state.selected and C.byId[state.selected]
 if current and D.room(u,key,current.outputs[1].hull)>0 then return state.selected end
 if current and (state.recipes and state.recipes[state.selected] and (state.recipes[state.selected].carry or 0)>0) then return state.selected end
 local lot=D.state(u,key);local count={}
 for _,l in ipairs(lot and lot.lots or {}) do count[l.hull]=(count[l.hull] or 0)+1 end
 local start=0;for i,r in ipairs(def.recipes) do if r==state.last then start=i end end
 local best,bestN
 for k=1,#def.recipes do
  local r=def.recipes[(start+k-1)%#def.recipes+1];local c=C.byId[r]
  local hull=c and c.outputs and c.outputs[1].hull
  if hull and D.room(u,key,hull)>0 then
   local n=count[hull] or 0
   if not bestN or n<bestN then best,bestN=r,n end
  end
 end
 state.selected=best
 return best or def.recipes[1]
end
-- A finished ship frees its facility to pick the next job.
function I.finished(u,key,recipe)
 for id,installation in pairs(I.installations(key)) do
  local def=I.definition(id,installation)
  if def.policy=='orders' then for _,r in ipairs(def.recipes) do if r==recipe then
   local state=I.state(u,key,id);state.selected=nil;state.last=recipe
  end end end
 end
end
function I.scale(u,key,c)
 for id,installation in pairs(I.installations(key)) do
  local def=I.definition(id,installation)
  for _,recipe in ipairs(def.recipes) do if recipe==c.id then
   if def.policy=='orders' then
    local selected=I.job(u,key,id,def)
    return selected==recipe and require('src.dealers').room(u,key,c.outputs[1].hull)>0 and 1 or 0
   end
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
  local room=require('src.industry_outputs').room(u,key,c,output)
  if roomOverride and output.item==c.item then room=roomOverride end
  n=math.min(n,room)
 end
 for _,input in ipairs(C.inputs(c)) do
  local available=S.available(u,key,input.item)
  if progress.budget then available=math.min(available,progress.budget[input.item] or 0) end
  n=math.min(n,math.floor((available+(progress.credit[input.item] or 0))/input.n+1e-9))
 end
 for _,input in ipairs(C.inputs(c)) do
  local credit=progress.credit[input.item] or 0
  local spent=math.max(0,math.ceil(n*input.n-credit-1e-9))
  if spent>0 then assert(S.take(u,key,input.item,spent));E.consume(u,key,input.item,spent) end
  progress.credit[input.item]=credit+spent-n*input.n
 end
 for _,output in ipairs(C.outputs(c)) do
  if n>0 then require('src.industry_outputs').add(u,key,output,n,c) end
 end
 return n
end
function I.flow(u,key,c,m,dt,rate,roomOverride)
 local S,E=require('src.stockpile'),require('src.economy')
 m.recipes=m.recipes or {};local state=m.recipes[c.id] or {carry=0};m.recipes[c.id]=state
 local work=state.carry+math.abs(rate)*dt/3600/(c.time or 1)
 state.budget=m.inputBudget and m.inputBudget[c.id]
 local whole=math.floor(work+1e-9);local done
 if rate<0 then
  done=math.min(whole,S.available(u,key,c.item));assert(S.take(u,key,c.item,done));E.consume(u,key,c.item,done)
 else done=I.produce(u,key,c,whole,state,roomOverride) end
 -- Blocked time cannot accumulate into an instant burst after resupply.
 state.carry=done<whole and 0 or work-whole
 if rate>0 and not roomOverride then
  for _,output in ipairs(require('src.commodities').outputs(c)) do
   if require('src.industry_outputs').room(u,key,c,output)<1 then state.carry=0 end
  end
 end
 state.budget=nil
 return done
end
-- Scheduled station facilities run independently of visibility or stock reads.
function I.update(u,clock,stations)
 local C=require('src.commodities');local Dealers=require('src.dealers')
 for _,key in ipairs(stations) do
  Dealers.update(u,key,clock)
  require('src.stockpile').count(u,key,require('src.food').item)
  for id,installation in pairs(I.installations(key)) do
   local def=I.definition(id,installation)
   local scheduled=false
   for _,recipe in ipairs(def.recipes) do if C.byId[recipe].stockless then scheduled=true end end
   if scheduled then
    local state=I.state(u,key,id);local previous=state.at or clock;state.at=clock
    -- Select once for this interval. Completion clears the job for the next
    -- update; another recipe must not receive the same elapsed work.
    local selected=def.policy=='orders' and I.job(u,key,id,def)
    local total=0
    for _,recipe in ipairs(def.recipes) do
     local c=C.byId[recipe]
     if c.stockless and (not selected or recipe==selected) then
      local rate=installation.capacity*I.scale(u,key,c)*require('src.food').output(u,key)
      total=total+I.flow(u,key,c,state,math.max(0,clock-previous),rate)
     end
    end
    state.completed=(state.completed or 0)+total
   end
  end
 end
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
-- Player-facing reasons, derived from the same limits as the executor.
function I.status(u,key,id,c)
 local S,C,data=require('src.stockpile'),require('src.commodities'),require('src.data')
 local def=I.definition(id,I.installations(key)[id])
 if (c.use[key] or 0)>0 then return 'Consuming '..data.items[c.item].name end
 if def.policy=='orders' and I.job(u,key,id,def)~=c.id then
  local next=require('src.commodities').byId[I.job(u,key,id,def)]
  return 'Queued: building '..(next and require('src.data').hulls[next.outputs[1].hull].name or 'another hull')..' first'
 end
 for _,o in ipairs(C.outputs(c)) do
  if require('src.industry_outputs').room(u,key,c,o)<1 then
   if o.kind=='ship' then
    local state,dealer=require('src.dealers').state(u,key)
    if state and #state.lots>=(dealer.lots or 6) then return 'Paused: sales lot full' end
    return 'Paused: no suitable commercial parking (guest space reserved)'
   end
   return 'Paused: '..data.items[o.item].name..' storage full'
  end
 end
 if I.scale(u,key,c)<=0 then return 'Idle: no profitable customer demand' end
 local progress
 if c.stockless then progress=I.state(u,key,id).recipes
 else for _,shop in pairs(S.record(u,key).shops or {}) do if shop.recipes and shop.recipes[c.id] then progress=shop.recipes;break end end end
 for _,input in ipairs(C.inputs(c)) do
  if S.available(u,key,input.item)+((progress and progress[c.id] and progress[c.id].credit or {})[input.item] or 0)<input.n then
   local reserved=S.reserved(u,key,input.item)
   return ('Waiting for %s%s'):format(data.items[input.item].name,reserved>0 and ' (stock reserved for freight)' or '')
  end
 end
 local carry=progress and progress[c.id] and progress[c.id].carry or 0
 local label=c.stockless and 'Building '..data.hulls[c.outputs[1].hull].name or 'Producing'
 return ('%s: %.0f%% of next batch%s'):format(label,carry*100,require('src.food').output(u,key)<1 and ' (slowed by food shortage)' or '')
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
    if not c.stockless then S.count(game.universe,key,c.item) end
    Slab.Text('  '..I.status(game.universe,key,id,c))
    Slab.Text(('  %s: %.0f%% | margin %.2f / processing unit'):format(recipe,I.scale(game.universe,key,c)*100,def.policy=='profit' and I.state(game.universe,key,id).profit[recipe] or 0))
    for _,o in ipairs(C.outputs(c)) do if o.kind=='ship' then Slab.Text('    Ship output: '..require('src.data').hulls[o.hull].name..' -> dealership') else Slab.Text(('    %s: stock %d | price %.2f'):format(require('src.data').items[o.item].name,S.count(game.universe,key,o.item),require('src.markets').price(game.universe,key,o.item))) end end
    for _,input in ipairs(C.inputs(c)) do Slab.Text(('    Input %s: %d available / %d physical'):format(require('src.data').items[input.item].name,S.available(game.universe,key,input.item),S.count(game.universe,key,input.item))) end
   end
  end
 end
end
return I
