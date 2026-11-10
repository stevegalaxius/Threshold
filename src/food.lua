-- Food is an operating cost, not a population simulation. Rates are crates
-- per game hour; farms export a surplus without an additional input chain.
local L=require('src.locations')
local F={item='food_crate',transition=3600,minOutput=.5,cap=1000}
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
 return {id='food',name='Food supplies',description='Station provisions and bulk food freight.',sells={{F.item,1}}}
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
 local eaten=math.min(wanted,have+made)
 local remaining=have+made-eaten
 m.stock[F.item]=remaining>0 and remaining or nil
 local E=require('src.economy')
 E.stat(u,'made',F.item,made);E.consume(u,key,F.item,eaten)
 local record=require('src.stockpile').record(u,key)
 local state=record.food or {output=1};record.food=state
 -- Integrate the supplied part first, then the time spent without food.
 -- Missed meals never accumulate into a hidden resupply debt.
 local short=use>make and math.max(0,dt-have/(use-make)*3600) or 0
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
