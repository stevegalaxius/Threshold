-- One steel plate supplies a batch of armor repairs. The station retains
-- unused material between ships and across online/offline updates.
local L=require('src.locations')
local P={item='steel_plate',points=100,floor=8,emergency=.25}
function P.supports(key)
 local place=L.byId[L.canonical(key)]
 return place and place.kind=='station' and L.stationServices(place.id).repair or false
end
function P.shop()
 return {id='steel',name='Steel plates',description='Manufactured and recovered plates for ship repairs.',sells={{P.item,1}}}
end
function P.available(u,key)
 key=L.canonical(key)
 local S=require('src.stockpile')
 return S.count(u,key,P.item)*P.points+(S.record(u,key).repairMaterial or 0)
end
function P.duration(u,key,missing,rate)
 local normal=math.min(missing,P.available(u,key))
 return normal/rate+(missing-normal)/(rate*P.emergency)
end
function P.restore(u,key,missing,seconds,rate)
 if missing<=1e-7 or seconds<=0 then return 0 end
 key=L.canonical(key)
 local S=require('src.stockpile')
 local record=S.record(u,key)
 local credit=record.repairMaterial or 0
 local funded=math.min(missing,seconds*rate,P.available(u,key))
 local spent=math.max(0,math.ceil((funded-credit-1e-7)/P.points))
 if spent>0 then
  assert(S.take(u,key,P.item,spent),'repair stock changed during restoration')
  require('src.economy').consume(u,key,P.item,spent)
 end
 record.repairMaterial=math.max(0,credit+spent*P.points-funded)
 local emergency=math.min(missing-funded,math.max(0,seconds-funded/rate)*rate*P.emergency)
 return funded+emergency
end
return P
