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
 local idle=trader('idle');small.npcs.idle=idle;small.arbiter.next=0;arb.update(small,61)
 assert(small.arbiter.freight.mars.shortage==0,'idle capacity ignored')
 local empty=world();arb.update(empty,60)
 assert(not empty.arbiter.extra.mars,'missing production spawned haulers')
 local low=post(empty,'rounds_s',10);low.urgency=0;local urgent=copy(low);urgent.urgency=3
 assert(def.score(empty,idle,urgent,source,60)>def.score(empty,idle,low,source,60),'urgency lost')
 assert(def.score(empty,idle,low,source,3600)>def.score(empty,idle,urgent,source,60),'aging cannot prevent starvation')
 print('FREIGHT CAPACITY: reservations, mixed manifests, settlement, urgency and workload passed')
end
