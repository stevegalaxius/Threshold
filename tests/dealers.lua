-- Dealer lots: limited specific ships, timed restock, manufacturer frames.
return function(game)
 local D,S,data=require('src.dealers'),require('src.stockpile'),require('src.data')
 local u={clock=0,stations={},npcs={},credits=10^7}
 local hub='station:venus_1'
 local lots=D.lots(u,hub)
 assert(#lots==math.ceil(6*0.6),'dealer did not open part-stocked: '..#lots)
 for _,lot in ipairs(lots) do
  local h=data.hulls[lot.hull];assert(h and lot.price>0 and lot.paint and lot.loadout,'bad lot')
 end
 local first=lots[1].id
 assert(D.take(u,hub,first) and not D.find(u,hub,first),'sold ship stayed on the lot')
 u.clock=8*3600*20
 assert(#D.lots(u,hub)==6,'restock overfilled or stalled: '..#D.lots(u,hub))
 local used=D.lots(u,'station:ring_1')
 for _,lot in ipairs(used) do
  assert(lot.trim=='stripped','used lot rolled a trim it does not sell')
  assert(lot.price<data.hulls[lot.hull].price,'used stripped ship not discounted')
 end
 -- manufacturer: lot only grows from hull frames
 local works='station:mars_1'
 local s=D.state(u,works)
 local before=#s.lots
 S.stock(u,works,S.shopFor(works,D.FRAME))[D.FRAME]=0
 s.lots={};D.state(u,works)
 assert(#s.lots==0,'manufacturer made ships without frames')
 S.stock(u,works,S.shopFor(works,D.FRAME))[D.FRAME]=2
 D.state(u,works)
 assert(#s.lots>=1,'manufacturer did not roll out a ship from frames')
 local Save=require('src.save');u=assert(Save.decode(Save.encode(u)))
 assert(u.dealers[works],'lot not saved')
 for _,shop in ipairs(S.shops(works)) do assert(not S.lists(shop,D.FRAME),'hull frames got a storefront') end
 print('DEALERS: limited lots, restock, trims, manufacturer frames and saving passed ('..before..' opening at the works)')
end
