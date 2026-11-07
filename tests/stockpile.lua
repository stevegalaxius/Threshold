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
 print('stockpile: ok')
end
