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
 for _,r in pairs(u.npcs or {}) do if r.populationGroup=='trader' and r.taskWorker and r.home~='mars' then template=copy(r);break end end
 assert(template,'no trader fixture')
 do
  local r=template;r.id='npc/990001';r.task=nil;r.ship.hold=nil;r.ship.cargo={}
  local w={clock=u.clock,npcs={[r.id]=r},stations=u.stations,mining=u.mining}
  local Transport=require('src.transport')
  local T=require('src.tuning')
  local quote=Transport.quote({source=jup,target=ven,amount=10},w.clock)
  local au=math.floor(require('src.fields').distance('jupiter','venus',w.clock)*100+.5)/100
  assert(quote.routeAU==au and quote.creditsPerUnit==math.floor((T.freightCreditsPerUnit+au*T.freightCreditsPerAU)*100+.5)/100,'freight price follows quoted route AU')
  local localQuote=Transport.quote({source=mars,target=node,amount=10},w.clock)
  assert(localQuote.routeAU==0 and localQuote.creditsPerUnit==T.freightCreditsPerUnit,'local freight uses the base rate')
  local legacy=Transport.quote({source=jup,target=ven,amount=10,creditsPerUnit=2},w.clock)
  assert(legacy.creditsPerUnit==2,'existing flat-rate contracts retain their price')
  local rate=quote.creditsPerUnit
  local paid=math.floor(6*rate+1e-7)
  local credits=r.credits or 0
  local earnings=r.freightEarnings or 0
  Tasks.post(w,{kind='transport',source=jup,target=ven,item='hydrogen_canister',amount=10,stocked=true,order=true,creditsPerUnit=rate,routeAU=au})
  Tasks.post(w,{kind='transport',source=jup,target=ven,item='hydrogen_canister',amount=5,stocked=true,order=true,creditsPerUnit=rate,routeAU=au})
  J.deliver(w,jup,'hydrogen_canister',20)
  local t=Tasks.choose(w,r,ven,w.clock)
  assert(t and t.phase=='pickup','trader takes remote work as a pickup')
  local route=Tasks.plan(r,ven,w.clock);assert(route and route[#route]==jup,'pickup route ends at the source')
  assert(t.amount==15 and (r.credits or 0)==credits,'matching orders merge without pickup payment')
  -- Another visitor takes stock while this trader is flying to the pickup.
  J.take(w,jup,'hydrogen_canister',J.available(w,jup,'hydrogen_canister')-6)
  local before=J.available(w,jup,'hydrogen_canister')
  Tasks.arrive(w,r,jup,w.clock)
  assert(r.task.phase=='delivery' and J.available(w,jup,'hydrogen_canister')==before-6 and t.amount==6,'loads only the remaining stock')
  local leg=Tasks.plan(r,jup,w.clock);assert(leg and leg[#leg]==ven,'then heads for the target')
  assert((r.credits or 0)==credits,'loading does not pay')
  local Save=require('src.save')
  r.task=assert(Save.decode(Save.encode(r.task)))
  Transport.quote(r.task,w.clock+100000)
  assert(r.task.creditsPerUnit==rate and r.task.routeAU==au,'saved shipment retains its quote as planets move')
  local task=r.task;local stock=J.available(w,ven,task.item)
  assert(Tasks.arrive(w,r,ven,w.clock),'and delivers')
  assert(r.credits==credits+paid and r.freightEarnings==earnings+paid,'pays for actual delivered quantity')
  assert(J.available(w,ven,task.item)==stock+6,'destination receives the load')
  Tasks.definitions.transport.complete(w,r,task,ven,w.clock)
  assert(r.credits==credits+paid and J.available(w,ven,task.item)==stock+6,'repeated completion changes nothing')
  local history=require('src.simulation_history').recent(w,{kind='freight_delivered'})
  assert(#history==1 and history[1].result.payment==paid and history[1].result.routeAU==au,'one delivery outcome records the payment')
  -- A later shipment loses cargo: no payout and the order is released.
  J.deliver(w,jup,'hydrogen_canister',10)
  local offer=Tasks.post(w,{kind='transport',source=jup,target=ven,item='hydrogen_canister',amount=10,stocked=true,order=true})
  local lost=assert(Tasks.choose(w,r,jup,w.clock))
  r.ship.cargo[lost.item]=lost.amount-1
  assert(not Tasks.arrive(w,r,ven,w.clock) and not r.task,'lost cargo fails delivery')
  assert(offer.state=='available' and r.credits==credits+paid and J.available(w,ven,lost.item)==stock+6,'failed delivery pays nothing and moves no stock')
 end
 -- Personality changes choices without adding more job/route evaluations.
 do
  local P=require('src.personality')
  local Save=require('src.save')
  local r=P.ensure({id='npc/personality',role='trader'})
  local restored=assert(Save.decode(Save.encode(r)))
  P.ensure(restored)
  assert(restored.ambition==r.ambition and restored.aggression==r.aggression,'saved personality remains stable')
  local low={id='npc/cautious',role='trader',ambition=0,aggression=0}
  local high={id='npc/ambitious',role='trader',ambition=1,aggression=1}
  local near={source=ven,target=jup,order=true,amount=10,creditsPerUnit=2,routeAU=0}
  local far={source=jup,target=ven,order=true,amount=10,creditsPerUnit=20,routeAU=18}
  local score=Tasks.definitions.transport.score
  assert(score(u,low,near,ven,u.clock)>score(u,low,far,ven,u.clock),'low ambition prefers nearby work')
  assert(score(u,high,far,ven,u.clock)>score(u,high,near,ven,u.clock),'high ambition pursues the richer remote run')
  local E=require('src.encounters')
  assert(P.engageOdds(low)>P.engageOdds(high) and E.breakPoint(low)>E.breakPoint(high),'aggression lowers engagement and surrender thresholds')
 end
 -- Both identities execute both jobs through the same civilian controller.
 do
  local NPC=require('src.npc')
  local Scavenge=require('src.scavenge')
  for _,role in ipairs({'trader','salvager'}) do
   local r=copy(template);r.id='npc/mixed/'..role;r.populationGroup=role;r.home='venus'
   r.task=nil;r.workProfile=nil;r.ship.hold=nil;r.ship.cargo={}
   r.workWeights={transport=1,salvage=0}
   local w={clock=u.clock,npcs={[r.id]=r},stations={}}
   local scene=setmetatable({universe=w},{__index=game})
   J.deliver(w,jup,'hydrogen_canister',10)
   Tasks.post(w,{kind='transport',source=jup,target=ven,item='hydrogen_canister',amount=10,stocked=true,order=true})
   local t=assert(Tasks.choose(w,r,jup,w.clock))
   local started=r.jobsStarted
   assert(Tasks.choose(w,r,jup,w.clock)==t and r.jobsStarted==started,'accepted work is not reconsidered')
   assert(NPC.docksAt(r,ven) and not Scavenge.profile(r),'freight uses shared docking and cannot scavenge')
   assert(Tasks.arrive(w,r,ven,w.clock,scene),'either identity can deliver freight')
   r.workWeights={transport=0,salvage=0};started=r.jobsStarted
   assert(not Tasks.choose(w,r,ven,w.clock) and r.jobsStarted==started,'idle retries do not advance the preference cycle')
   r.workWeights={transport=0,salvage=1}
   Tasks.post(w,{kind='salvage',source=ven,target=ven,system='venus',cooldown=30})
   assert(Tasks.choose(w,r,ven,w.clock),'either identity can accept salvage')
   assert(NPC.docksAt(r,ven) and Scavenge.profile(r).clears,'active salvage job supplies collection and docking')
   r.ship.cargo.scrap=1;Scavenge.took(r,'scrap',1,w.clock)
   local credits=r.credits or 0
   assert(Tasks.arrive(w,r,ven,w.clock,scene),'salvage completes through the same task path')
   assert(r.credits>credits and r.ship.cargo.scrap==0 and not r.salvageReturn and not Scavenge.profile(r),'salvage is sold and collection state ends with the job')
   assert(r.populationGroup==role,'taking other work does not replace the NPC identity')
  end
 end
 print(('stockpile: ok (Mars made %d canisters in an hour; %d commodity hauls)'):format(made,hauls))
end
