-- Bounded handoff checks: observing a station must not accelerate its jobs.
return function(game)
 local A,N,Tasks=require('src.alife'),require('src.npc'),require('src.tasks')
 local L,Fields=require('src.locations'),require('src.fields')
 local copy=require('src.persistence').copy
 game:loadField('earth');game:captureALife(true)
 local u=game.universe;local template
 for _,r in pairs(u.npcs) do if r.populationGroup=='trader' then template=copy(r);break end end
 assert(template)
 u.npcs={};u.clock=1000;Tasks.state(u).offers={}
 require('src.supplies').universe=u
 local node=L.station('earth','trade');local station=game:locationEntity(node)
 local function record(id,untilTime)
  local r=copy(template);r.id=id;r.area='earth';r.state='docked';r.node=node
  r.route={node,node};r.index=1;r.untilTime=untilTime
  r.task,r.action,r.service,r.encounter,r.worldRecovery=nil,nil,nil,nil,nil
  r.pose,r.offset,r.docking,r.transit,r.driverState=nil,nil,nil,nil,nil
  r.waitingForHome,r.nextTaskAt,r.stuckSince=nil,nil,nil
  r.nextServiceAt=u.clock+1e6;r.fuelClock=u.clock
  r.ship=require('src.ship').record(game.player);r.ship.hold=nil
  r.ship.cargo={[require('src.reactor_fuel').item()]=30}
  r.ship.armor=require('src.npc_repair').maximum(r)
  r.workWeights={transport=1,salvage=0,patrol=0,raid=0,mine=0}
  u.npcs[id]=r
  return r
 end
 local ships={}
 for i=1,3 do
  local r=record('handoff/'..i,1005);r.nextDecisionAt=1010+i*3
  ships[i]=A.wake(game,r)
  assert(ships[i].dockState,'fixture needs three small-ship parking places')
 end
 local targets={L.stations('earth','trade')[2],L.stations('luna','trade')[1],L.stations('luna','trade')[2]}
 require('src.jobs').deliver(u,node,'water_ice',30)
 for _,target in ipairs(targets) do Tasks.post(u,{kind='transport',source=node,target=target,item='water_ice',amount=1,stocked=true}) end
 u.clock=1006
 for _,e in ipairs(ships) do
  local r=u.npcs[e.alifeId]
  assert(not N.departOnline(game,e,station),'waking let a trader search before its saved decision time')
  assert(not r.task,'early departure query claimed a freight job')
 end
 for i,e in ipairs(ships) do
  u.clock=1010+i*3
  assert(N.departOnline(game,e,station),'ready trader did not take available freight')
  game:undockShip(e)
 end
 -- Failed live searches use the same saved retry interval as remote ships.
 Tasks.state(u).offers={};u.clock=1100
 local r=record('handoff/waiting',1100);local e=A.wake(game,r)
 assert(e.dockState)
 assert(not N.departOnline(game,e,station),'empty board produced a departure')
 local due=r.nextDecisionAt
 assert(due and due>u.clock,'failed search has no persistent retry deadline')
 local choose=Tasks.choose;local calls=0
 Tasks.choose=function(...)calls=calls+1;return choose(...)end
 u.clock=1101;N.departOnline(game,e,station);A.capture(game,e,false)
 local remote=copy(r);N.advance(remote,u.clock,u,game)
 Tasks.choose=choose
 assert(calls==0 and r.nextDecisionAt==due and remote.nextDecisionAt==due,'online polling or capture bypassed the offline retry deadline')
 local restored=assert(require('src.save').decode(require('src.save').encode(r)))
 assert(restored.nextDecisionAt==due,'save/load lost the decision deadline')
 -- A service visit has the same dwell and completion clock in both modes.
 local T=require('src.tuning')
 r.task={id='handoff/service',kind='salvage'}
 r.service={station=node,need='fuel'}
 local visit=copy(r);require('src.npc_repair').begin(visit,node,u.clock,T.alifeStay,u)
 game:finishDocking(e,e.dockState,station)
 assert(r.untilTime==visit.untilTime,'live service dwell used the interrupted job duration')
 local Upkeep=require('src.upkeep')
 assert(not Upkeep.canDepart(game,e,r),'service completed before its saved deadline')
 local now=u.clock;u.clock=r.untilTime
 assert(Upkeep.canDepart(game,e,r),'live service added an extra timeout after the offline completion time')
 u.clock=now;r.service=nil;r.task=nil;r.nextDecisionAt=due
 -- Repairing continues through job-search waits, just as it does live.
 local repairing=copy(r);repairing.ship.armor=20;repairing.repairAt=1101;repairing.untilTime=1100
 require('src.npc_repair').advance(repairing,1102,'station:mars_1',u)
 assert(repairing.ship.armor>20,'offline repairs stopped at the minimum dwell deadline while the ship was still parked')
 -- Idle records stay idle across capture rather than becoming a new trip.
 r.state='idle';r.node=Fields.earth.buoyIds[1];r.route={r.node,r.node};r.index=1
 e.dockState=nil;e.routeIndex=1;A.bindRoute(game,e,r)
 local untilTime=r.untilTime
 A.capture(game,e,false)
 assert(r.state=='idle' and r.untilTime==untilTime,'capture converted an idle wait into travel')
 -- Work and its claim survive waking; returning offline retains the approach.
 local Actions=require('src.npc_actions')
 local x,y=e.body:getPosition();u.clock=1200
 r.untilTime=1300;r.nextDecisionAt=nil;r.nextServiceAt=1e9
 local resource={id='handoff/loot',area='earth',kind='loot',item='water_ice',count=3,x=x+2000,y=y,clock=u.clock,vx=0,vy=0}
 require('src.loose').records(u)[resource.id]=resource
 local action=Actions.request({game=game,u=u,r=r,clock=u.clock},
  {kind='work',operation='collect',target={provider='resource',id=resource.id,expected='loot'}})
 action.fromJob=true;action.progress=2
 A.capture(game,e,true);game:remove(e,true);game.alifeOnline[r.id]=nil
 e=A.wake(game,r)
 assert(r.action==action and action.progress==2,'waking cancelled the active work or lost progress')
 local ctx={game=game,u=u,r=r,e=e,clock=u.clock,dt=.1,AI=require('src.ai')}
 Actions.step(ctx)
 assert(resource.actionOwner==r.id,'waking lost the work claim')
 u.clock=u.clock+1;A.capture(game,e,true);game:remove(e,true);game.alifeOnline[r.id]=nil
 Actions.step({game=game,u=u,r=r,clock=u.clock})
 assert(r.action and r.action.phase=='approaching' and resource.count==3,'going offline completed a distant approach immediately')
 print('NPC HANDOFF: staggered departures, shared waits, repairs, saved timing and work continuity passed')
end
