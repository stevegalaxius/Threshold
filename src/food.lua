-- Food is an operating cost, not a population simulation. Rates are crates
-- per game hour; farms turn delivered fertilizer into food.
local L=require('src.locations')
local policy=require('data.industry').consumption.food
local recipe=require('src.commodities').byId[policy.recipe]
local F={item=policy.item,fertilizer=recipe.inputs[1].item,yield=1/recipe.inputs[1].n,transition=policy.transition,minOutput=policy.minOutput,cap=recipe.cap}
function F.rates(key)
 local place=L.byId[L.canonical(key)]
 if not place or place.kind~='station' then return 0,0 end
 local spec=place.food or {}
 return spec.use or require('src.world_layout').defaults.foodUse or 32,((place.facilities or {})[policy.facility] or {}).capacity or 0
end
function F.initial(key)
 local use,make=F.rates(key)
 return math.ceil(use*(require('src.world_layout').defaults.foodReserveHours or 4)+make)
end
function F.shop()
 return {id='food',name='Food supplies',description='Station provisions and agricultural freight.',sells={{F.item,1},{F.fertilizer,1}}}
end
function F.fertilizerUse(key)
 local _,make=F.rates(key)
 return make/F.yield
end
function F.initialFertilizer(key)
 local use=F.fertilizerUse(key)
 return math.ceil(use*(require('src.world_layout').defaults.foodReserveHours or 4))
end
local function move(output,target,seconds)
 local change=(1-F.minOutput)*seconds/F.transition
 return target>output and math.min(target,output+change) or math.max(target,output-change)
end
-- Called by stockpile catch-up with the actual food shop, once per interval.
-- Production and consumption stay separate, including at a surplus producer.
function F.flow(u,key,m,dt)
 local use,make=F.rates(key)
 local reserved=require('src.stockpile').reserved(u,key,F.item)
 local have=math.max(0,(m.stock[F.item] or 0)-reserved)
 local function units(rate,field)
  local n=rate*dt/3600+(m[field] or 0)
  local whole=math.floor(n+1e-9);m[field]=n-whole
  return whole
 end
 local wanted=units(use,'foodUseCarry')
 local E=require('src.economy')
 local Stock=require('src.stockpile')
 local made,short=0,0
 if make>0 then
  local recipe=require('src.commodities').byId[policy.recipe]
  m.recipes=m.recipes or {};local progress=m.recipes[recipe.id] or {carry=0,credit={}};m.recipes[recipe.id]=progress
  local credit=(progress.credit and progress.credit[F.fertilizer] or 0)*F.yield
  local fertilizer=Stock.available(u,key,F.fertilizer)
  made=require('src.industry').flow(u,key,recipe,m,dt,make,math.max(0,F.cap-have-reserved+wanted))
  local active=math.min(dt,(credit+fertilizer*F.yield)/make*3600)
  local net=make-use
  if net<0 then short=math.max(0,active-have/-net*3600) end
  local left=math.max(0,have+net*active)
  if use>0 then short=short+math.max(0,dt-active-left/use*3600) end
 elseif use>0 then short=math.max(0,dt-have/use*3600) end
 local eaten=math.min(wanted,have+made)
 local remaining=have+made-eaten
 m.stock[F.item]=remaining+reserved>0 and remaining+reserved or nil
 E.consume(u,key,F.item,eaten)
 local record=require('src.stockpile').record(u,key)
 local state=record.food or {output=1};record.food=state
 -- Integrate the supplied part first, then the time spent without food.
 -- Missed meals never accumulate into a hidden resupply debt.
 state.output=move(move(state.output,1,dt-short),F.minOutput,short)
end
function F.output(u,key)
 local r=u.stations and u.stations[L.canonical(key)]
 return r and r.food and r.food.output or 1
end
function F.status(u,key)
 key=L.canonical(key)
 local have=require('src.stockpile').count(u,key,F.item)
 local use,make=F.rates(key)
 local hours=use>0 and have/use or 0
 return {stock=have,use=use,make=make,hours=hours,output=F.output(u,key),
  condition=have==0 and 'Shortage' or hours<1 and 'Rationing' or 'Supplied'}
end
function F.label(u,key)
 local s=F.status(u,key)
 return ('Food: %s | %d crates / %.1fh | Industry %d%%'):format(s.condition,s.stock,s.hours,math.floor(s.output*100+.5))
end
return F
