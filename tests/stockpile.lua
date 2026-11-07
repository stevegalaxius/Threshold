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
 local Tasks=require('src.tasks')
 -- stations short of a good order it (src/economy.lua)
 u.economyNext=nil;require('src.economy').update(u,u.clock)
 for _,o in pairs(Tasks.state(u).offers) do if o.order and (o.item=='hydrogen_canister' or o.item=='empty_canister') then hauls=hauls+1 end end
 assert(hauls>0,'commodity orders are posted')
 -- an idle trader flies empty to work elsewhere, loads there, then delivers
 local copy=require('src.persistence').copy
 local template
 for _,r in pairs(u.npcs or {}) do if r.role=='trader' and r.taskWorker and r.home~='mars' then template=copy(r);break end end
 assert(template,'no trader fixture')
 do
  local r=template;r.id='npc/990001';r.task=nil;r.ship.hold=nil;r.ship.cargo={}
  local w={clock=u.clock,npcs={[r.id]=r},stations=u.stations,mining=u.mining}
  Tasks.post(w,{kind='transport',source=jup,target=ven,item='hydrogen_canister',amount=10,stocked=true,cap=60})
  J.deliver(w,jup,'hydrogen_canister',20)
  local t=Tasks.choose(w,r,ven,w.clock)
  assert(t and t.phase=='pickup','trader takes remote work as a pickup')
  local route=Tasks.plan(r,ven,w.clock);assert(route and route[#route]==jup,'pickup route ends at the source')
  local before=J.available(w,jup,'hydrogen_canister')
  Tasks.arrive(w,r,jup,w.clock)
  assert(r.task.phase=='delivery' and J.available(w,jup,'hydrogen_canister')==before-10,'loads at the source')
  local leg=Tasks.plan(r,jup,w.clock);assert(leg and leg[#leg]==ven,'then heads for the target')
  assert(Tasks.arrive(w,r,ven,w.clock),'and delivers')
 end
 print(('stockpile: ok (Mars made %d canisters in an hour; %d commodity hauls)'):format(made,hauls))
end
