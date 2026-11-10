-- Food is an operating cost, not a population simulation. Rates are crates
-- per game hour; farms turn delivered fertilizer into food.
local L=require('src.locations')
local F={item='food_crate',fertilizer='fertilizer',yield=20,transition=3600,minOutput=.5,cap=1000}
function F.rates(key)
 local place=L.byId[L.canonical(key)]
 if not place or place.kind~='station' then return 0,0 end
 local spec=place.food or {}
 return spec.use or require('src.world_layout').defaults.foodUse or 8,spec.make or 0
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
 local have=m.stock[F.item] or 0
 local function units(rate,field)
  local n=rate*dt/3600+(m[field] or 0)
  local whole=math.floor(n+1e-9);m[field]=n-whole
  return whole
 end
 local wanted=units(use,'foodUseCarry')
 local made=math.min(units(make,'foodMakeCarry'),math.max(0,F.cap-have+wanted))
 local E=require('src.economy')
 local Stock=require('src.stockpile')
 local short=0
 if make>0 then
  -- A fertilizer unit feeds twenty crates. Persist the unused nutrients,
  -- so frequent small updates cost the same as an offline catch-up.
  local credit=m.foodNutrients or 0
  local fertilizer=Stock.count(u,key,F.fertilizer)
  made=math.min(made,credit+fertilizer*F.yield)
  local spent=math.max(0,math.ceil((made-credit)/F.yield))
  if spent>0 then Stock.take(u,key,F.fertilizer,spent);E.consume(u,key,F.fertilizer,spent) end
  m.foodNutrients=credit+spent*F.yield-made
  -- Fertilizer runs out after this much crop output; calculate hunger
  -- after that point rather than treating the whole interval as supplied.
  local active=math.min(dt,(credit+fertilizer*F.yield)/make*3600)
  local net=make-use
  if net<0 then short=math.max(0,active-have/-net*3600) end
  local left=math.max(0,have+net*active)
  if use>0 then short=short+math.max(0,dt-active-left/use*3600) end
 elseif use>0 then short=math.max(0,dt-have/use*3600) end
 local eaten=math.min(wanted,have+made)
 local remaining=have+made-eaten
 m.stock[F.item]=remaining>0 and remaining or nil
 E.stat(u,'made',F.item,made);E.consume(u,key,F.item,eaten)
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
