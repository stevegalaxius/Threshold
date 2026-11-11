-- Bounded economic scenarios, not a world soak.
return function(game)
 local C,E,S=require('src.markets'),require('src.economy'),require('src.stockpile')
 local L,F=require('src.locations'),require('src.fields')
 local Tasks,Transport=require('src.tasks'),require('src.transport')
 local Save=require('src.save')
 local plant='station:callisto_2';local farm='station:earth_2'
 local function set(u,key,item,n) local stock=S.stock(u,key,S.shopFor(key,item));stock[item]=n>0 and n or nil end
 -- Both recipes share eighty units/hour, and compete for real input stock.
 local w={clock=0,stations={}}
 S.count(w,plant,'fertilizer');S.count(w,plant,'explosives');set(w,plant,'nitrates',1000)
 w.clock=3600
 assert(S.count(w,plant,'fertilizer')==40 and S.count(w,plant,'explosives')==40,'chemical recipes exceeded or failed to share capacity')
 assert(w.economyStats.used.nitrates==120,'fertilizer/explosives used incorrect nitrate quantities')
 set(w,plant,'nitrates',0);w.clock=7200
 assert(S.count(w,plant,'fertilizer')==40 and S.count(w,plant,'explosives')==40,'factory produced without nitrates')
 local u={clock=0,stations={},npcs={}}
 local farms={'station:earth_2','station:venus_2','station:titan_1'}
 local function supplied()
  for _,id in ipairs(farms) do set(u,id,'fertilizer',1000) end
 end
 supplied();set(u,farm,'fertilizer',0)
 for _,key in ipairs({'station:mars_1','station:mars_2'}) do set(u,key,'explosives',1000) end
 set(u,plant,'nitrates',1000);set(u,'station:titan_2','nitrates',1000)
 E.update(u,0)
 local first=require('src.industry').state(u,plant,'chemicals').mix.make_fertilizer
 assert(first>.5 and first<1,'fertilizer demand did not gradually attract factory time')
 for _=1,20 do u.clock=u.clock+60;E.update(u,u.clock) end
 assert(require('src.industry').state(u,plant,'chemicals').mix.make_fertilizer>.9,'factory did not respond to the fertilizer shortage')
 local fertilizerOrder=false
 for _,o in pairs(Tasks.state(u).offers) do
  if o.item=='fertilizer' and o.target==farm then
   fertilizerOrder=true;assert(o.commodityBuyPrice and o.commoditySellPrice,'chemical freight omitted cargo quotes')
  end
 end
 assert(fertilizerOrder,'factory output did not generate ordinary freight to the hungry farm')
 supplied()
 for _,key in ipairs({'station:mars_1','station:mars_2'}) do set(u,key,'explosives',0) end
 for _=1,22 do
  u.clock=u.clock+60;supplied();E.update(u,u.clock)
  local mix=require('src.industry').state(u,plant,'chemicals').mix
  assert(mix.make_fertilizer+mix.make_explosives<=1.000001,'allocation created extra factory capacity')
 end
 assert(require('src.industry').state(u,plant,'chemicals').mix.make_explosives>.9,'explosives demand failed to pull capacity away from fertilizer')
 -- Incoming reserved supply reduces the shortage premium.
 local empty={clock=0,stations={}};local incoming={clock=0,stations={}}
 set(empty,farm,'fertilizer',0);set(incoming,farm,'fertilizer',0)
 C.update(empty,0,{farm},{})
 C.update(incoming,0,{farm},{[farm..'|fertilizer']=1000})
 assert(C.price(incoming,farm,'fertilizer')<C.price(empty,farm,'fertilizer'),'inbound supply did not reduce scarcity pricing')
 -- Save actual game state: quotes, curves, allocations and production carries.
 local quote=Transport.quote({kind='transport',source=plant,target='station:mars_1',item='explosives',amount=5,stocked=true,order=true,layoutScope=E.scope,placed=u.clock,phase='delivery'},u.clock,u)
 local buy,sell=quote.commodityBuyPrice,quote.commoditySellPrice
 C.state(u).prices[plant].explosives=2
 C.state(u).prices['station:mars_1'].explosives=.5
 Transport.quote(quote,u.clock+1000,u)
 assert(quote.commodityBuyPrice==buy and quote.commoditySellPrice==sell,'moving prices changed an agreed shipment quote')
 local order=Tasks.post(u,quote)
 local old=game.universe;game.universe=u
 local snapshot=assert(Save.decode(Save.encode(game:saveState())))
 assert(snapshot.facilities[plant..'|chemicals'].mix.make_explosives==require('src.industry').state(u,plant,'chemicals').mix.make_explosives,'save lost the factory allocation')
 local i=S.shopFor(plant,'explosives')
 assert(snapshot.stations[plant].shops[i].flowAt==u.clock,'save omitted the chemical production clock')
 game:loadState(snapshot);u=game.universe;order=Tasks.state(u).offers[order.id]
 assert(order.commodityBuyPrice==buy and order.commoditySellPrice==sell,'load changed shipment quotes')
 local carrier={id='chemical-hauler',ship={cargo={explosives=5}},credits=0}
 local before=S.count(u,order.target,'explosives')
 assert(Tasks.definitions.transport.complete(u,carrier,order,order.target,u.clock),'chemical shipment did not deliver')
 Tasks.definitions.transport.complete(u,carrier,order,order.target,u.clock)
 assert(S.count(u,order.target,'explosives')==before+5 and carrier.credits==Transport.payment(order),'commodity values changed freight payment or duplicated settlement')
 -- No customers: throttle down rather than manufacturing phantom demand.
 for _=1,22 do
  u.clock=u.clock+60
  for _,id in ipairs(farms) do set(u,id,'fertilizer',1000) end
  for _,id in ipairs({'station:mars_1','station:mars_2'}) do set(u,id,'explosives',1000) end
  E.update(u,u.clock)
 end
 local mix=require('src.industry').state(u,plant,'chemicals').mix
 assert(mix.make_fertilizer<.001 and mix.make_explosives<.001,'factory kept producing without profitable customers')
 for _,prices in pairs(C.state(u).prices) do for _,v in pairs(prices) do assert(v>=.5 and v<=2,'price escaped its bounds') end end
 game.universe=old
 print('CHEMICAL ECONOMY: shared inputs/capacity, priced demand, switching, freight quotes and save/load passed')
end
