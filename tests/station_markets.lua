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
 do
  local game=require('src.game').new()
  game:loadField('venus')
  local station
  for _,e in ipairs(game.entities) do if e.kind=='station' and e.key=='station:venus_3' then station=e;break end end
  assert(station,'missing manufacturing station')
  game:dockInstantly(game.player,station)
  game.state='docked'
  local Cargo=require('src.ui.cargo')
  local Hangar=require('src.ui.hangar')
  local Yard=require('src.ui.shipyard')
  local Stall=require('src.ui.stall')
  local function click(r) assert(r);Cargo.mousepressed(game,r.x+r.w/2,r.y+r.h/2,1,{}) end
  game.universe.credits=1000000
  assert(Cargo.setTab(game,'shipyard'))
  Cargo.draw(game)
  local Paint=require('src.paint')
  local view=assert(Yard.layout(game))
  for _,row in ipairs(view.rows) do
   if #Paint.pool(require('src.data').hulls[row.id])>1 then click(row);break end
  end
  view=Yard.layout(game)
  assert(#view.paints>1,'manufacturer has no paint choices to exercise')
  local chosen=view.paints[2].name
  click(view.paints[2])
  assert(Yard.layout(game).lot.paint==chosen,'paint click did not update preview')
  Cargo.draw(game)
  click(view.buy)
  local order=assert(Yard.layout(game).order)
  assert(order.paint==chosen,'ship order lost selected paint')
  click(view.paints[1])
  assert(Yard.layout(game).lot.paint==chosen,'paid paint changed after ordering')
  click(view.buy)
  assert(not Yard.layout(game).order)
  click(view.buy)
  order=assert(Yard.layout(game).order)
  Dealers.output(game.universe,station.key,order.hull,1)
  local completed=assert(Dealers.find(game.universe,station,order.lot))
  assert(completed.paint==chosen,'manufactured lot lost ordered paint')
  click(view.buy)
  assert(Hangar.sel==completed and Cargo.tab=='hangar')
  Cargo.draw(game)
  click(Hangar.layout(game).sell)
  assert(Hangar.sel~=completed and Hangar.sel.color.name==chosen,'collected ship lost ordered paint')
  assert(Cargo.setTab(game,'hangar'))
  Cargo.draw(game)
  local hangar=Hangar.layout(game)
  local lot
  for _,entry in ipairs(hangar.ships) do if entry.dealer then lot=entry;break end end
  assert(lot,'no parked dealer ship')
  click(lot)
  assert(Hangar.sel==lot.owner and Cargo.tab=='hangar')
  Cargo.draw(game)
  click(Hangar.layout(game).sell)
  assert(Hangar.sel~=lot.owner and Cargo.tab=='hangar')
  assert(Cargo.setTab(game,'stall'))
  local pane
  for _,r in ipairs(Stall.layout(game).panes) do if r.id=='orders' then pane=r end end
  click(pane)
  Cargo.draw(game)
  click(Stall.layout(game).shipsTab)
  Cargo.draw(game)
  assert(Stall.layout(game).shipRows)
  click(Stall.layout(game).goodsTab)
  Cargo.draw(game)
  assert(Stall.layout(game).picks)
  Cargo.setTab(game,'cargo')
  Stall.pane='stall'
 end
 print('ok  station markets: local Venus dealer, residential shops, Heaven-Ladder commute')
end
