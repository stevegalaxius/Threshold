-- A bounded economic loop: consumption, shortages, freight and recovery.
return function(game)
 local Food,Stock,E=require('src.food'),require('src.stockpile'),require('src.economy')
 local L,Tasks=require('src.locations'),require('src.tasks')
 local Save=require('src.save')
 local key='station:mars_1'
 local u={clock=0,stations={}}
 local function food(n)
  local stock=Stock.stock(u,key,Stock.shopFor(key,Food.item));stock[Food.item]=n
 end
 local use=Food.rates(key)
 assert(Food.status(u,key).hours==4,'new station lacks its opening reserve')
 u.clock=3600
 assert(Stock.count(u,key,Food.item)==use*3,'station did not consume food')
 food(use/2)
 assert(Food.status(u,key).condition=='Rationing','low reserve has no warning')
 food(0);u.clock=u.clock+3600
 assert(Food.status(u,key).output==.5,'empty station did not reduce industry')
 local target=E.target(u,key,Food.item)
 u.clock=u.clock+36000
 assert(Food.status(u,key).stock==0 and E.target(u,key,Food.item)>=use*2 and target>=use*2,
  'starvation erased food demand or accrued negative inventory')
 -- Real recipe output is reduced, while inputs remain available.
 Stock.add(u,key,'iron_ore',10000)
 local before=Stock.count(u,key,'empty_canister')
 u.clock=u.clock+600
 assert(Stock.count(u,key,'empty_canister')-before==100,'shortage did not halve canister production')
 -- A normal transport completion feeds the same stock, once.
 local r={id='food-hauler',ship={cargo={[Food.item]=use*3}}}
 local t={id='food-shipment',source='station:earth_2',target=key,item=Food.item,amount=use*3,stocked=true,phase='delivery'}
 local complete=Tasks.definitions.transport.complete
 assert(complete(u,r,t,key,u.clock) and Food.status(u,key).stock==use*3,'food freight did not reach the reserve')
 complete(u,r,t,key,u.clock)
 assert(Food.status(u,key).stock==use*3 and Food.output(u,key)==.5,'delivery duplicated stock or instantly cleared the penalty')
 -- State persists; recovery does not require a loaded scene or an NPC.
 u=assert(Save.decode(Save.encode(u)));u.clock=u.clock+1800
 assert(Food.status(u,key).output==.75,'saved shortage did not recover gradually')
 u.clock=u.clock+1800
 assert(Food.status(u,key).output==1,'food delivery did not restore industry')
 local farm='station:earth_2';local initial=Stock.count(u,farm,Food.item)
 local eat,make=Food.rates(farm)
 local used=(u.economyStats.used or {})[Food.item] or 0
 u.clock=u.clock+3600
 assert(Stock.count(u,farm,Food.item)==initial+make-eat,'farm failed to produce and eat separately')
 assert(u.economyStats.used[Food.item]-used==eat,'farm consumption was hidden by net production')
 -- Fertilizer is real cargo: an empty farm stops and keeps ordering it.
 local farmWorld={clock=0,stations={}}
 local farmStock=Stock.stock(farmWorld,farm,Stock.shopFor(farm,Food.item))
 farmStock[Food.item]=nil;farmStock[Food.fertilizer]=nil
 farmWorld.clock=3600
 assert(Food.status(farmWorld,farm).stock==0 and Food.output(farmWorld,farm)==.5,'farm made food without fertilizer')
 assert(E.target(farmWorld,farm,Food.fertilizer)==make/Food.yield*E.hours,'empty farm lost fertilizer demand')
 local shipment={id='fertilizer-shipment',source='station:belt_1',target=farm,item=Food.fertilizer,amount=1,stocked=true,phase='delivery'}
 local carrier={id='fertilizer-hauler',ship={cargo={[Food.fertilizer]=1}}}
 assert(complete(farmWorld,carrier,shipment,farm,farmWorld.clock),'fertilizer freight failed')
 farmWorld.clock=farmWorld.clock+30
 Food.status(farmWorld,farm)
 local batch=math.floor(make*30/3600)
 assert(farmWorld.economyStats.made[Food.item]==batch and Stock.count(farmWorld,farm,Food.fertilizer)==0,'farm did not use delivered fertilizer')
 farmWorld=assert(Save.decode(Save.encode(farmWorld)));farmWorld.clock=farmWorld.clock+30
 Food.status(farmWorld,farm)
 assert(farmWorld.economyStats.made[Food.item]==batch*2,'save/load lost the fertilizer remaining in the crop batch')
 farmWorld.clock=farmWorld.clock+3600
 Food.status(farmWorld,farm)
 assert(farmWorld.economyStats.made[Food.item]==20,'one fertilizer made more or less than twenty food crates')
 -- Fertilizer makers use the ordinary recipe/input mechanism.
 local sourceWorld={clock=0,stations={}}
 local source='station:belt_1'
 Stock.count(sourceWorld,source,Food.fertilizer)
 -- Isolate the fertilizer recipe from the fuel recipe sharing this input.
 for _,item in ipairs({'iron_ore','empty_canister','water_ice'}) do
  Stock.take(sourceWorld,source,item,Stock.count(sourceWorld,source,item))
 end
 Stock.add(sourceWorld,source,'water_ice',10)
 sourceWorld.clock=900
 assert(Stock.count(sourceWorld,source,Food.fertilizer)==10 and Stock.count(sourceWorld,source,'water_ice')==0,'fertilizer did not consume its production input')
 local reserve=Stock.count(sourceWorld,farm,Food.fertilizer)
 Stock.take(sourceWorld,farm,Food.fertilizer,reserve)
 E.update(sourceWorld,sourceWorld.clock)
 local fertilizerOrder=false
 for _,o in pairs(Tasks.state(sourceWorld).offers) do
  if o.item==Food.fertilizer and o.target==farm then fertilizerOrder=true end
 end
 assert(fertilizerOrder,'farm did not order fertilizer through ordinary freight')
 -- Saturn's moon plants produce directly; Ceres alone processes ice.
 for _,source in ipairs({'station:enceladus_1','station:titan_2'}) do
  local moon={clock=0,stations={}}
  Stock.count(moon,source,Food.fertilizer)
  moon.clock=3600
  assert(Stock.count(moon,source,Food.fertilizer)==40,'Saturn moon plant required an input or failed to produce fertilizer')
 end
 local ladder='station:mars_3'
 local opening=Stock.count(u,ladder,Food.item)
 u.clock=u.clock+3600
 local demand=Food.rates(ladder)
 assert(Stock.count(u,ladder,Food.item)==opening-demand,'non-trade station did not consume food')
 assert(Stock.count(u,'access:mars_3_2',Food.item)==opening-demand,'Ladder anchors did not share one reserve')
 local have=Stock.count(u,ladder,Food.item)
 Stock.take(u,ladder,Food.item,have)
 E.update(u,u.clock)
 local ordered=false
 for _,o in pairs(Tasks.state(u).offers) do
  if o.item==Food.item and o.target==ladder then ordered=true end
 end
 assert(ordered,'hungry non-trade station did not receive a normal food freight order')
 -- Opening the market must not replace a missed food shipment with restock.
 local old=game.universe;game.universe=u
 local shop=Stock.shopFor(key,Food.item);local st={key=key,locationId=key}
 local market=game:stationMarket(st,shop)
 food(0);market.next[Food.item]=u.clock-10000
 game:shopTick(st,shop,Stock.shops(st)[shop])
 assert(Stock.count(u,key,Food.item)==0,'market timer conjured food during a shortage')
 market.next[Food.fertilizer]=u.clock-10000
 game:shopTick(st,shop,Stock.shops(st)[shop])
 assert(Stock.count(u,key,Food.fertilizer)==0,'market timer conjured fertilizer')
 game.universe=old
 print('FOOD: consumption, shortage, production, freight, persistence and recovery passed')
end
