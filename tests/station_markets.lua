-- Content wiring: named dealers stay local and Mars's workforce can commute.
return function()
 local L,Stock,Dealers=require('src.locations'),require('src.stockpile'),require('src.dealers')
 local Services=require('src.station_services')
 assert(not require('src.data').markets[require('src.world_layout').defaults.marketId].dealer,
  'default market must not grant a named dealership')
 for id,place in pairs(L.byId) do
  if place.kind=='station' and not place.accessOf then
   local market=Stock.definition(id)
   assert(not market or market.id~='market:venus_1' or id=='station:venus_1','Venus market inherited by '..id)
  end
 end
 assert(Dealers.def('station:venus_3').name=='Angelmaschinenwerft Atelier','Venus lost its dealer')
 assert(Services.get(nil,L.get('station:venus_3')).shipyard,'Venus dealer has no Shipyard tab')
 for _,id in ipairs({'station:venus_1','station:luna_3','station:mars_5'}) do
  assert(not Dealers.def(id),'residential station has a dealership: '..id)
  assert(Stock.definition(id).id=='market:'..id:sub(9),'residential station lacks its own market')
 end
 local home,work='station:mars_5','station:mars_3'
 local found=false
 for _,route in ipairs(require('src.passengers').config(home).routes) do
  if route.to==work and route.kind=='work' and route.weight>0 then found=true end
 end
 assert(found,'Hakka Tulou has no Heaven-Ladder commute')
 local Transport=require('src.transport')
 assert(Transport.route(home,work,0),'Heaven-Ladder commute has no outbound route')
 assert(Transport.route(work,home,0),'Heaven-Ladder commute has no return route')
 print('ok  station markets: local Venus dealer, residential shops, Heaven-Ladder commute')
end
