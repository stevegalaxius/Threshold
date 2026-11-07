-- Shop stockpiles: NPC logistics and the market shelf share one count per shop.
return function(game)
 local Stock,J=require('src.stockpile'),require('src.jobs')
 local Hold=require('src.inventory.hold')
 local u=game.universe
 local node='station:mars_3'
 local st={key=node,locationId=node}
 local i=Stock.shopFor(node,'iron_ore')
 local start=J.available(u,node,'iron_ore')
 assert(start>0,'Heaven-Ladder starts with ore on its shelf')
 J.deliver(u,node,'iron_ore',7)
 local shelf=game:stationMarket(st,i).hold
 assert(Hold.count(shelf,'iron_ore')==start+7,'NPC delivery shows on the shelf')
 assert(J.take(u,node,'iron_ore',start+7),'NPC pickup takes shop stock')
 game:stationMarket(st,i)
 assert(Hold.count(shelf,'iron_ore')==0,'pickup empties the shelf')
 assert(not J.take(u,node,'iron_ore',1),'no stock, no pickup')
 local shops=#Stock.shops(st)
 assert(Stock.stock(u,st,shops)==nil,'supplies shop has no stockpile')
 -- commodities: Mars presses ore into canisters, gas giants fill them, Venus uses them
 local L=require('src.locations')
 local mars=L.stations('mars','trade')[1];local jup=L.stations('jupiter','trade')[1];local ven=L.stations('venus','trade')[1]
 u.clock=u.clock or 0
 J.available(u,mars,'iron_ore');J.available(u,jup,'empty_canister');J.available(u,ven,'hydrogen_canister')
 local e0=J.available(u,mars,'empty_canister')
 J.deliver(u,mars,'iron_ore',30)
 J.deliver(u,jup,'empty_canister',30)
 J.deliver(u,ven,'hydrogen_canister',30)
 local ore=J.available(u,mars,'iron_ore')
 u.clock=u.clock+3600
 local made=J.available(u,mars,'empty_canister')-e0
 assert(made>0 and J.available(u,mars,'iron_ore')==ore-made,'Mars makes canisters from ore')
 assert(J.available(u,jup,'hydrogen_canister')>0 and J.available(u,jup,'empty_canister')<30,'Jupiter fills empties')
 assert(J.available(u,ven,'hydrogen_canister')<30,'Venus uses hydrogen')
 u.clock=u.clock+36000
 assert(J.available(u,jup,'empty_canister')==0,'no empties, no hydrogen')
 local h=J.available(u,jup,'hydrogen_canister');u.clock=u.clock+3600
 assert(J.available(u,jup,'hydrogen_canister')==h,'hydrogen stops without empties')
 local hauls=0
 local Transport,Tasks=require('src.transport'),require('src.tasks')
 Transport.seed(u)
 for _,o in pairs(Tasks.state(u).offers) do if o.item=='hydrogen_canister' or o.item=='empty_canister' then hauls=hauls+1 end end
 assert(hauls>0,'commodity hauls are posted')
 print(('stockpile: ok (Mars made %d canisters in an hour; %d commodity hauls)'):format(made,hauls))
end
