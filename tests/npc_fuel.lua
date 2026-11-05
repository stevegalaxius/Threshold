-- Shared fuel lifecycle; controlled records, no long emergent-world runs.
return function(game)
 local F,A,T=require('src.reactor_fuel'),require('src.alife'),require('src.tuning')
 local Tasks,Transport,L=require('src.tasks'),require('src.transport'),require('src.locations')
 local Save,copy=require('src.save'),require('src.persistence').copy
 local Ship,AI=require('src.ship'),require('src.ai')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local function transitions(u,to)
  local n=0
  for _,e in ipairs(u.simulationHistory and u.simulationHistory.entries or {}) do
   if e.kind=='fuel_condition_changed' and (not to or e.result.to==to) then n=n+1 end
  end
  return n
 end
 game:captureALife(true)
 local template
 for _,r in pairs(game.universe.npcs) do
  if r.role=='trader' and r.home=='earth' then template=copy(r);break end
 end
 assert(template,'no trader for lifecycle fixture')
 local r=template;r.id='npc/880001';r.state='docked';r.area='earth';r.taskWorker=true
 r.task=nil;r.nextTaskAt=nil;r.encounter=nil;r.piracy=nil;r.worldRecovery=nil
 r.driverState=nil;r.pose=nil;r.offset=nil;r.fuelStatus=nil;r.fuelObservedAt=nil
 r.ship.hold=nil;r.ship.cargo={[F.item()]=8};r.ship.fuelCharge=0;r.ship.fuelInitialized=true
 local s=require('src.stats').compute(require('src.data').hulls[r.ship.hull],r.ship.loadout)
 r.power=s.powerCap
 local u={clock=0,npcs={[r.id]=r}}
 Transport.seed(u)
 local source=L.stations('earth','trade')[1]
 -- Pick a normal delivery through the real reservation API.
 local task=assert(Tasks.choose(u,r,source,0));local taskId=task.id
 r.route=assert(Tasks.plan(r,source,0));r.index=2;r.state='travel';r.depart=0;r.arrive=100;r.fuelClock=0
 local route=Save.encode(r.route);local cargo=r.ship.cargo.scrap
 check(F.observe(u,r,0)=='normal' and transitions(u)==0,'healthy NPC emitted a spurious fuel event')
 r.ship.cargo[F.item()]=0;r.ship.fuelCharge=1
 check(F.observe(u,r,0)=='low' and transitions(u,'low')==1,'low reserve was not detected')
 r.ship.fuelCharge=0;r.power=10
 check(F.observe(u,r,0)=='empty' and transitions(u,'empty')==1,'fuel empty ignored remaining capacitor')
 A.advance(r,.1,u)
 check(r.task.id==taskId and r.state=='travel' and r.fuelStatus=='empty','empty fuel cancelled a powered duty')
 r.power=0
 A.advance(r,1,u)
 check(r.fuelStatus=='stranded' and transitions(u,'stranded')==1,'depletion did not record one stranding')
 local progress=(1-r.depart)/(r.arrive-r.depart)
 A.advance(r,2,u);A.advance(r,3,u)
 check(math.abs((3-r.depart)/(r.arrive-r.depart)-progress)<1e-6,'stranded record advanced along its route')
 check(r.task.id==taskId and Save.encode(r.route)==route and r.ship.cargo.scrap==cargo,'stranding replaced duty, route or cargo')
 check(u.tasks.offers[taskId].owner==r.id and require('src.population').count(u,'earth','trader')==1,'stranded NPC lost ownership or population identity')
 check(transitions(u,'stranded')==1,'repeated offline updates duplicated the stranding')
 -- Materialize, serialize through the real game save, and reload while stranded.
 game.universe.npcs=u.npcs;game.universe.tasks=u.tasks;game.universe.simulationHistory=u.simulationHistory
 game.universe.clock=3
 local live=A.wake(game,r)
 check(live.fuelStatus=='stranded' and transitions(game.universe,'stranded')==1,'wake changed or repeated the condition')
 local snap=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(snap)
 r=game.universe.npcs[r.id]
 live=game.alifeOnline[r.id] or A.wake(game,r)
 check(r.fuelStatus=='stranded' and r.task.id==taskId and transitions(game.universe,'stranded')==1,'load lost the interrupted duty or repeated history')
 local before=Save.encode(r.task)
 AI.think(game,live,1/120)
 check(Save.encode(r.task)==before and live.intent.thrust==0 and live.intent.strafe==0,'stranded online AI changed duty or tried to fly')
 local monitor=require('src.ui.npc_traffic').snapshot(game,true)
 check(monitor.npcs[r.id] and monitor.npcs[r.id].status==F.label(r),'traffic monitor hid the stranded condition')
 -- A cargo transfer restores the very same ship and duty, not a replacement.
 Ship.addCargo(live,F.item(),8)
 local events=transitions(game.universe)
 check(F.observe(game.universe,r,3,live)=='normal','fuel transfer did not clear stranding')
 F.observe(game.universe,r,3,live)
 check(transitions(game.universe)==events+1,'recovery was not recorded exactly once')
 AI.think(game,live,1/120)
 check(live.intent.thrust~=0 or live.intent.strafe~=0,'refueled ship did not resume its route')
 check(r.task.id==taskId and live.cargo.scrap==cargo,'recovery discarded the interrupted shipment')
 Ship.fly(live,1/120);game:captureALife(true)
 local clock=game.universe.clock+1
 A.advance(r,clock,game.universe)
 check(r.fuelStatus=='normal' and r.task.id==taskId and transitions(game.universe,'stranded')==1,'returning offline re-stranded or replaced a recovered NPC')
 -- Idle timers and mining work must not finish during a fuel outage.
 local idle=copy(r);idle.id='npc/880002';idle.role='miner';idle.state='idle';idle.untilTime=1
 idle.task={id='interrupted-mine',kind='mine',phase='mining'}
 idle.ship.cargo={};idle.ship.hold=nil;idle.ship.fuelCharge=0;idle.power=0
 idle.fuelStatus=nil;idle.fuelObservedAt=nil;idle.fuelClock=0
 local iu={npcs={[idle.id]=idle},clock=0}
 F.observe(iu,idle,0);A.advance(idle,10,iu)
 check(idle.untilTime==11 and idle.task.id=='interrupted-mine','stranded idle timer completed a duty')
 idle.ship.cargo[F.item()]=8;F.observe(iu,idle,10)
 check(idle.fuelClock==10 and idle.nextMiningAt==10+T.miningOfflineEvery,'miner caught up work from its stranded interval')
 -- External transport still carries an unpowered ship; it is not ship thrust.
 local transit=copy(r);transit.state='transit';transit.transit={kind='driver'}
 check(not F.needsPropulsion(transit),'fuel status blocked an externally powered transit')
 print(('NPC FUEL LIFECYCLE TEST PASSED (%d checks)'):format(checks))
end
