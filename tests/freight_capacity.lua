-- Bounded freight integration: reservations, mixed delivery and fleet pressure.
return function(game)
 local S,Tasks,Transport=require('src.stockpile'),require('src.tasks'),require('src.transport')
 local copy=require('src.persistence').copy
 local source,target='station:mars_1','station:earth_1'
 local function set(u,item,n) S.stock(u,source,S.shopFor(source,item))[item]=n end
 local function world()
  local u={clock=0,stations={},npcs={}}
  set(u,'rounds_s',100);set(u,'airburst_s',100)
  return u
 end
 local function trader(id)
  return {id=id,area='mars',home='mars',populationGroup='trader',workProfile='freight_regular',ship={hull='intaki_wisp',cargo={}},credits=0}
 end
 local function post(u,item,n,rate)
  return Tasks.post(u,{kind='transport',source=source,target=target,item=item,amount=n,order=true,stocked=true,placed=0,creditsPerUnit=rate or 2,routeAU=1})
 end
 local unclaimed=world();post(unclaimed,'rounds_s',40)
 assert(Transport.reserved(unclaimed,source,'rounds_s',nil,true)==40,'unclaimed outgoing commitments ignored')
 local def=Tasks.definitions.transport
 -- Volume pricing and one handling allowance survive splits and bundling.
 local function quoted(item,n,au)
  return Transport.quote({kind='transport',source=source,target=target,item=item,amount=n,order=true,stocked=true,routeAU=au},0)
 end
 for au,payment in pairs({[0]=500,[1]=680,[5]=1400}) do
  assert(Transport.payment(quoted('nitrates',120,au))==payment,'30 m3 delivery price is incorrect')
 end
 local whole=quoted('nitrates',120,0);local half=copy(whole);half.amount=60
 assert(Transport.payment(half)*2==Transport.payment(whole),'splitting cargo multiplied the handling fee')
 local upgrade=world();local unbooked=post(upgrade,'nitrates',120,2);unbooked.routeAU=0;unbooked.layoutScope='economy'
 local agreed=post(upgrade,'nitrates',120,2);agreed.routeAU=0;agreed.layoutScope='economy';agreed.state='reserved'
 Transport.refreshOffers(upgrade,100)
 assert(Transport.payment(unbooked)==500 and unbooked.npcClaimAt==130,'unclaimed listings did not receive new rates and listing window')
 assert(Transport.payment(agreed)==240,'repricing changed an accepted contract')
 local bundle=world();set(bundle,'nitrates',120);set(bundle,'steel_plate',120)
 local first=Tasks.post(bundle,quoted('nitrates',60,1))
 local second=Tasks.post(bundle,quoted('steel_plate',60,1))
 first.npcClaimAt=30;second.npcClaimAt=30
 local worker=trader('priced-freight');worker.ship.hull='ferrous_bison';bundle.npcs[worker.id]=worker
 assert(not Tasks.choose(bundle,worker,target,0) and not Tasks.choose(bundle,worker,target,29),'NPC took a job during its public listing window')
 local booked=assert(Tasks.choose(bundle,worker,target,30))
 assert(#booked.manifest==2 and Transport.payment(booked)==680,'bundled orders received multiple handling fees')
 local serialized=assert(require('src.save').decode(require('src.save').encode(booked)))
 assert(Transport.payment(serialized)==680,'saved manifest changed its invoice')
 assert(not def.complete(bundle,worker,booked,source,31) and booked.phase=='delivery')
 assert(def.complete(bundle,worker,booked,target,32) and worker.credits==680,'NPC settlement disagrees with quote')
 assert(def.complete(bundle,worker,booked,target,33) and worker.credits==680,'handling fee paid twice')
 local fees,paid=0,0
 for _,entry in ipairs(require('src.simulation_history').recent(bundle,{kind='freight_delivered'})) do
  fees=fees+entry.result.handling;paid=paid+entry.result.payment
 end
 assert(fees==200 and paid==680,'history disagrees with the shipment invoice')
 -- An old eligible root must not bundle a newly published companion early.
 local delayed=world();local root=post(delayed,'rounds_s',10);local fresh=post(delayed,'airburst_s',10)
 fresh.npcClaimAt=30;local r0=trader('listing-root');delayed.npcs[r0.id]=r0
 assert(#assert(Tasks.choose(delayed,r0,target,0)).manifest==1 and fresh.state=='available','bundling bypassed listing delay')
 local u=world();local a=post(u,'rounds_s',50,2);local b=post(u,'airburst_s',50,4)
 local r=trader('freight-a');u.npcs[r.id]=r
 local t=copy(a);t.assigned=0
 assert(def.prepare(u,r,t,target,0),'remote manifest failed')
 r.task=t
 assert(#t.manifest==2 and Transport.reserved(u,source,'rounds_s')==50,'mixed reservation missing')
 Tasks.clean(u,1)
 assert(b.owner==r.id,'cleanup released manifest companion')
 local competitor=post(u,'rounds_s',100)
 assert(Transport.available(u,source,'rounds_s',competitor.id)==50,'reserved goods promised twice')
 Tasks.release(u,r,'cancelled',1)
 assert(Transport.reserved(u,source,'rounds_s')==0 and b.state=='available','cancel did not free stock')
 Tasks.state(u).offers[competitor.id]=nil
 a.readyAt=0;b.readyAt=0;t=copy(a)
 assert(def.prepare(u,r,t,target,2));r.task=t
 assert(not def.complete(u,r,t,source,3) and t.phase=='delivery','pickup failed')
 assert(S.count(u,source,'rounds_s')==50 and S.count(u,source,'airburst_s')==50,'pickup did not debit each commodity')
 assert(Transport.reserved(u,source,'rounds_s')==0,'loaded goods stayed reserved')
 local before=S.count(u,target,'rounds_s');local beforeAlt=S.count(u,target,'airburst_s')
 assert(def.complete(u,r,t,target,4),'delivery failed')
 assert(r.credits==300,'manifest quotes or payment lost')
 assert(S.count(u,target,'rounds_s')==before+50 and S.count(u,target,'airburst_s')==beforeAlt+50,'mixed delivery lost cargo')
 assert(def.complete(u,r,t,target,5) and r.credits==300,'delivery paid twice')
 local small=world();post(small,'rounds_s',100)
 local large=world();post(large,'rounds_s',100);local o=next(Tasks.state(large).offers);Tasks.state(large).offers[o].amount=10000
 local arb=require('src.arbiter')
 arb.update(small,60);arb.update(large,60)
 assert(large.arbiter.freight.mars.work>small.arbiter.freight.mars.work,'arbiter still counts orders')
 local idle=trader('idle');idle.node=source;idle.ship.fuelCharge=1000;small.npcs.idle=idle;small.arbiter.next=0;arb.update(small,61)
 assert(small.arbiter.freight.mars.shortage==0,'idle capacity ignored')
 local empty=world();arb.update(empty,60)
 assert(not empty.arbiter.extra.mars,'missing production spawned haulers')
 local low=post(empty,'rounds_s',10);low.urgency=0;local urgent=copy(low);urgent.urgency=3
 assert(def.score(empty,idle,urgent,source,60)>def.score(empty,idle,low,source,60),'urgency lost')
 assert(def.score(empty,idle,low,source,3600)>def.score(empty,idle,urgent,source,60),'aging cannot prevent starvation')
 -- Reservation protection uses the same API as repairs, factories and rearming.
 local protected=world();local offer=post(protected,'rounds_s',80)
 offer.state='reserved';offer.owner='reserved-hauler'
 assert(S.count(protected,source,'rounds_s')==100 and S.available(protected,source,'rounds_s')==20)
 assert(not S.take(protected,source,'rounds_s',21),'consumer stole reserved cargo')
 assert(S.take(protected,source,'rounds_s',20) and S.take(protected,source,'rounds_s',80,nil,offer.id),'owner could not load reservation')
 local E=require('src.economy')
 E.shortage(protected,target,'rounds_s',0,100,10)
 protected.tasks.offers={}
 E.shortage(protected,target,'rounds_s',5,100,500)
 assert(E.shortageAge(protected,target,'rounds_s',600)==590,'replacement reset shortage age')
 local Save=require('src.save');protected=assert(Save.decode(Save.encode(protected)))
 assert(E.shortageAge(protected,target,'rounds_s',700)==690,'shortage age lost on save')
 E.shortage(protected,target,'rounds_s',100,100,701)
 assert(E.shortageAge(protected,target,'rounds_s',702)==0,'resupply did not clear shortage')
 idle.ship.fuelCharge=0
 assert(Transport.usable(small,idle,next(Tasks.state(small).offers) and select(2,next(Tasks.state(small).offers)),61)==0,'unfuelled ship credited')
 idle.ship.fuelCharge=1000;idle.workWeights={transport=0}
 assert(Transport.usable(small,idle,select(2,next(Tasks.state(small).offers)),61)==0,'unwilling ship credited')
 idle.workWeights=nil;idle.ship.cargo={steel_plate=10000}
 assert(Transport.usable(small,idle,select(2,next(Tasks.state(small).offers)),61)==0,'full hold credited')
 idle.ship.cargo={};idle.node='missing-station'
 assert(Transport.usable(small,idle,select(2,next(Tasks.state(small).offers)),61)==0,'unreachable pickup credited')
 local original=game.universe
 S.stock(original,target,S.shopFor(target,'rounds_s')).rounds_s=nil
 E.shortage(original,target,'rounds_s',100,100,9)
 E.shortage(original,target,'rounds_s',0,100,10)
 local snapshot=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(snapshot)
 assert(S.record(game.universe,target).shortages.rounds_s==10,'game save/load lost shortage age')
 print('FREIGHT CAPACITY: reservations, mixed manifests, settlement, urgency and workload passed')
end
