-- Bounded manufactured/recovered material and shared repair economics.
return function(game)
 local P,S,E=require('src.repair_materials'),require('src.stockpile'),require('src.economy')
 local Save=require('src.save')
 assert(not require('src.data').items.scrap and not require('src.data').items.hull_alloy,'obsolete salvage metals remain')
 assert(not require('src.ore').drop('junk',100),'junk still drops a commodity')
 local key='station:mars_1'
 -- Isolate rolling from the canister press competing for the same ore.
 local u={clock=0,stations={},credits=100000,industry={[key]={press_canisters=0}}}
 local stock=S.stock(u,key,S.shopFor(key,P.item));stock[P.item]=nil
 for _,id in ipairs({'iron_ore','empty_canister'}) do S.take(u,key,id,S.count(u,key,id)) end
 S.add(u,key,'iron_ore',20)
 u.clock=600
 assert(S.count(u,key,P.item)==10 and S.count(u,key,'iron_ore')==0,'steel did not require two ore per plate')
 S.take(u,key,P.item,10);S.add(u,key,P.item,1)
 assert(P.restore(u,key,200,10,4)==40 and S.count(u,key,P.item)==0,'repair did not consume its steel plate')
 u=assert(Save.decode(Save.encode(u)))
 assert(P.restore(u,key,200,30,4)==75 and u.economyStats.used[P.item]==1,'saved plate remainder was lost or double charged')
 assert(P.restore(u,key,200,10,4)==10,'emergency repair did not run at quarter speed')
 assert(E.target(u,key,P.item)>=P.floor,'quiet repair bay lost its minimum steel demand')
 -- Salvage sales enter usable stock, rather than expiring as resale cargo.
 local oldUniverse=game.universe;game.universe=u
 local recovery={id='steel-salvager',ship={hull=game.player.hull.id,loadout=game.player.loadout,cargo={[P.item]=3}},salvageCargo={[P.item]=3}}
 local available=S.count(u,key,P.item)
 require('src.salvager').sell(game,recovery,key,u.clock)
 assert(S.count(u,key,P.item)==available+3 and recovery.ship.cargo[P.item]==0,'salvaged plates did not enter repair stock')
 game.universe=oldUniverse
 -- Exercise the real player repair API and save/load, including partial payment.
 local old=game.universe;game.universe=u
 local p=game.player;local maximum=p.stats.armor
 p.armor=maximum-20
 local st={key=key,locationId=key}
 S.add(u,key,P.item,1)
 local before=u.credits
 assert(game:repairShip(st,p)==20 and p.armor==maximum-20 and u.credits==before,'repair request performed or charged work immediately')
 u.clock=u.clock+2;game:updateRepairs(st)
 assert(p.armor==maximum-12 and u.credits==before-8*game.repairRate(st),'player repair progress or payment was wrong')
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 assert(saved.player.ship.repairOrder and saved.player.ship.repairOrder.remaining==12,'save omitted the pending player repair')
 game:loadState(saved)
 p=game.player;u=game.universe
 u.clock=u.clock+3;game:updateRepairs(st)
 assert(p.armor==maximum and not p.repairOrder and u.credits==before-20*game.repairRate(st),'loaded repair duplicated payment or lost progress')
 assert(not require('src.ship').record(p).repairOrder,'recording an idle ship invented a repair order')
 -- Market timers must not replace manufactured or recovered plates.
 stock=S.stock(u,key,S.shopFor(key,P.item));stock[P.item]=nil
 local shop=S.shopFor(key,P.item);local market=game:stationMarket(st,shop)
 market.next[P.item]=u.clock-10000
 game:shopTick(st,shop,S.shops(st)[shop])
 assert(S.count(u,key,P.item)==0,'market timer created steel plates')
 game.universe=old
 print('STEEL: manufacture, salvage identity, shared repair stock, shortages and saved player repairs passed')
end
