-- One focused scenario: affiliation, authority and equipment are independent.
return function(game)
 local data=require('src.data')
 local copy=require('src.persistence').copy
 local L=require('src.locations')
 local Tasks=require('src.tasks')
 local Access=require('src.npc_access')
 local Templates=require('src.npc_templates')
 local Stats=require('src.stats')
 local def=data.enemies.patrol_wisp
 local loadout=copy(def.loadout or data.hulls[def.hull].loadout)
 local officer={id='npc/work/officer',area='earth',home='earth',state='idle',
  ship={hull=def.hull,loadout=loadout,cargo=copy(def.cargo or {}),armor=Stats.compute(data.hulls[def.hull],loadout).armor}}
 Templates.apply(officer,'patrol','earth');officer.workWeights={patrol=1,transport=0,salvage=0,mine=0}
 local civilian=copy(officer);civilian.id='npc/work/freelancer';civilian.authorizations={}
 local u={clock=0,npcs={[officer.id]=officer,[civilian.id]=civilian},stations={}}
 local source=L.station('earth','trade');local target=require('src.fields').earth.buoyIds[1]
 local police=Tasks.post(u,{kind='patrol',source=source,target=target,issuer='estates',jurisdiction='earth',requires={authorization='police'}})
 assert(not Tasks.choose(u,civilian,source,0) and police.state=='available','affiliation and preference do not grant police authority')
 assert(not Access.authorized(officer,'police','zhuhai','earth') and not Access.authorized(officer,'police','estates','mars'),'authority must match issuer and jurisdiction')
 assert(Tasks.choose(u,officer,source,0).id==police.id,'authorized police can reserve the faction duty')
 officer.task={kind='transport'}
 assert(Access.police(officer,'earth') and not Access.police(officer,'mars'),'authority survives other work but does not travel to another jurisdiction')
 require('src.reputation').addStanding(u,'estates',-80)
 officer.affiliation='jove' -- authority comes from the issuer, not affiliation
 local policeShip={alifeRecord=officer}
 local player={kind='ship',isPlayer=true}
 local Security=require('src.security')
 assert(Security.hostile({universe=u,fieldId='earth',time=0},policeShip,player),'authorized police remain on call while hauling freight')
 assert(not Security.hostile({universe=u,fieldId='mars',time=0},policeShip,player),'visiting police have no authority outside their jurisdiction')
 local freelance=Tasks.post(u,{kind='patrol',source=source,target=target,issuer='private_customer',jurisdiction='earth'})
 assert(Tasks.choose(u,civilian,source,0).id==freelance.id,'freelance patrol work needs no police grant')
 assert(Tasks.plan(civilian,source,0) and Tasks.arrive(u,civilian,target,0,game),'freelance patrol uses the ordinary task execution path')
 -- Preferences cannot make an unequipped ship eligible to mine.
 assert(not Access.eligible(civilian,Tasks.definitions.mine,Access.capabilities(civilian)),'mining requires an actual drill')
 -- Mining is an active job, not a permanent controller. Finish one finite
 -- load, then use the same ship to accept freight from the receiving stock.
 do
  local M,NPC=require('src.mining'),require('src.npc')
  local Fuel,T=require('src.reactor_fuel'),require('src.tuning')
  local siteId=require('src.fields').phobos.drillIds[1]
  local home=L.get(siteId).motion.home
  local spec=require('src.fields').miningSources('phobos')[1]
  local def=data.enemies.miner_packhorse
  local loadout=copy(def.loadout)
  local r={id='npc/work/mining',area='phobos',home='phobos',node=home,state='idle',route={home,home},index=1,speed=600,
   ship={hull=def.hull,loadout=loadout,cargo={[Fuel.item()]=30,iron_ore=5},fuelInitialized=true,fuelCharge=T.reactorFuelEnergy,
    armor=Stats.compute(data.hulls[def.hull],loadout).armor}}
  Templates.apply(r,'miner','phobos');r.homeStation=home;r.workWeights={mine=1,transport=0,salvage=0,patrol=0}
  local w={clock=1,npcs={[r.id]=r},stations={}}
  local scene=setmetatable({universe=w},{__index=game})
  local supplies=require('src.supplies');local original=supplies.universe;supplies.universe=w
  local state=M.state(w)
  state.sites[siteId]={id=siteId,area='phobos',home=home,x=spec.x,y=spec.y,radius=spec.radius,angle=0,item='iron_ore'}
  Tasks.post(w,{kind='mine',source=home,target=siteId,item='iron_ore',area='phobos'})
  assert(NPC.decide(w,r,home,w.clock,scene) and M.active(r),'common controller accepts equipped mining work')
  local x,y=L.position(siteId,0)
  state.resources.test={id='test',site=siteId,area='phobos',kind='rock',item='iron_ore',hp=1,yield=T.minerLoad,radius=1,x=x,y=y,vx=0,vy=0,clock=0}
  w.clock=r.arrive;NPC.advance(r,w.clock,w,scene)
  w.clock=r.action.arriveAt+1;NPC.advance(r,w.clock,w,scene)
  assert(state.resources.test.kind=='loot','shared work action drills the actual resource')
  w.clock=w.clock+1;NPC.advance(r,w.clock,w,scene)
  w.clock=r.action.arriveAt+1;NPC.advance(r,w.clock,w,scene)
  w.clock=w.clock+1;NPC.advance(r,w.clock,w,scene)
  assert(r.task.phase=='delivery' and not state.resources.test,'mining collects the actual finite resource and returns it')
  w.clock=r.arrive;NPC.advance(r,w.clock,w,scene)
  r.workWeights={mine=0,transport=1,salvage=0,patrol=0}
  Tasks.post(w,{kind='transport',source=home,target=L.station('mars','trade'),item='iron_ore',amount=2,stocked=true,order=true})
  w.clock=r.untilTime+1;NPC.advance(r,w.clock,w,scene)
  assert(r.task and r.task.kind=='transport' and not M.active(r) and r.ship.cargo.iron_ore==7,'mining retains personal cargo and the same controller selects freight')
  supplies.universe=original
 end
 -- Fencing is a continuation task in the same controller, not another AI.
 do
  local r=copy(officer);r.id='npc/work/return';r.state='idle';r.area='earth';r.home='earth'
  Templates.apply(r,'pirate','earth')
  local NPC,P=require('src.npc'),require('src.piracy')
  local node=require('src.fields').earth.buoyIds[1]
  r.node=node;r.route={node,node};r.index=1;r.speed=600;r.task={id='fixture',kind='raid'}
  r.ship.cargo.water_ice=3;r.stolenCargo={water_ice=3};r.ship.hold=nil
  r.homeStation=L.station(nil,'pirateBase')
  local w={clock=0,npcs={[r.id]=r},stations={}}
  local scene=setmetatable({universe=w},{__index=game})
  local supplies=require('src.supplies');local original=supplies.universe;supplies.universe=w
  assert(P.returnRecord(scene,r) and r.task.kind=='fence','loot return is an active task')
  for _=1,#r.route+1 do
   w.clock=r.arrive;NPC.advance(r,w.clock,w,scene)
   if r.state=='docked' then break end
  end
  assert(r.state=='docked' and r.node==r.homeStation,'shared travel reaches the fencing station')
  w.clock=r.untilTime+1;NPC.advance(r,w.clock,w,scene)
  assert(w.piracy.stashes[r.homeStation].water_ice==3 and not r.ship.cargo.water_ice,'the common controller unloads stolen cargo once')
  supplies.universe=original
 end
 print('npc work: authority and freelance patrol ok')
end
