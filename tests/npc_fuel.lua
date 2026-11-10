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
  if r.populationGroup=='trader' and r.home=='earth' then template=copy(r);break end
 end
 assert(template,'no trader for lifecycle fixture')
 local r=template;r.id='npc/880001';r.state='docked';r.area='earth';r.taskWorker=true
 r.task=nil;r.nextTaskAt=nil;r.encounter=nil;r.piracy=nil;r.worldRecovery=nil
 r.service=nil;r.serviced=nil;r.nextServiceAt=nil;r.distress=nil;r.nextDistressAt=nil
 r.driverState=nil;r.pose=nil;r.offset=nil;r.fuelStatus=nil;r.fuelObservedAt=nil
 r.ship.hold=nil;r.ship.cargo={[F.item()]=40};r.ship.fuelCharge=0;r.ship.fuelInitialized=true
 local s=require('src.stats').compute(require('src.data').hulls[r.ship.hull],r.ship.loadout)
 r.power=s.powerCap
 local u={clock=0,npcs={[r.id]=r}}
 local source=L.stations('earth','trade')[1]
 -- one ordinary haul on the board (nothing is authored by default any more)
 Tasks.post(u,{kind='transport',source=source,target=L.stations('mars','trade')[1],item='scrap',amount=5})
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
 check(r.service and r.service.need=='fuel','empty-fuel courier did not divert to a supply stop')
 route=Save.encode(r.route) -- the detour is the itinerary while stranded
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
 Ship.addCargo(live,F.item(),40)
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
 local idle=copy(r);idle.id='npc/880002';idle.task={kind='mine'};idle.state='idle';idle.untilTime=1
 idle.task={id='interrupted-mine',kind='mine',phase='mining'}
 idle.ship.cargo={};idle.ship.hold=nil;idle.ship.fuelCharge=0;idle.power=0
 idle.fuelStatus=nil;idle.fuelObservedAt=nil;idle.fuelClock=0
 local iu={npcs={[idle.id]=idle},clock=0}
 F.observe(iu,idle,0);A.advance(idle,10,iu)
 check(idle.untilTime==11 and idle.task.id=='interrupted-mine','stranded idle timer completed a duty')
 idle.ship.cargo[F.item()]=8;F.observe(iu,idle,10)
 check(idle.fuelClock==10 and idle.task.id=='interrupted-mine','miner caught up work from its stranded interval')
 -- External transport still carries an unpowered ship; it is not ship thrust.
 local transit=copy(r);transit.state='transit';transit.transit={kind='driver'}
 check(not F.needsPropulsion(transit),'fuel status blocked an externally powered transit')

 -- Low fuel diverts a plain-route trader to a supply station, then resumes.
 local Supplies=require('src.supplies')
 local home=L.station('earth','trade')
 local loop=assert(A.roundTrip('earth','luna',0,home),'no earth-luna round trip fixture')
 local first
 for i=2,#loop do
  local ok=L.get(loop[i]).area=='earth' and L.get(loop[i]).kind~='station'
  for k=i,#loop do
   local p=L.get(loop[k]);if p.area~='earth' then break end
   if p.kind=='station' then ok=false end
  end
  if ok then first=i;break end
 end
 assert(first,'no outbound station-free leg for fuel detour fixture')
 local d=copy(template);d.id='npc/880003';d.taskWorker=nil;d.task=nil;d.onRoundTrip=true
 d.tripDestination='luna';d.home='earth';d.tradeHome=home;d.worldRecovery=nil;d.encounter=nil;d.piracy=nil;d.area='earth'
 d.route=copy(loop);d.index=first;d.state='travel';d.depart=0;d.arrive=1;d.fuelClock=0
 d.fuelStatus=nil;d.service=nil;d.nextServiceAt=nil
 d.ship.hold=nil;d.ship.cargo={};d.ship.fuelCharge=s.powerOut*T.reactorFuelReserveSeconds*T.npcAmmoThreshold*.9;d.ship.fuelInitialized=true;d.power=s.powerCap
 local du={clock=0,npcs={[d.id]=d}}
 F.observe(du,d,0)
 local original=Save.encode(d.route)
 A.advance(d,0,du)
 check(d.service and Supplies.supports(d.service.station),'low-fuel trader did not plan a supply stop')
 local docked=false
 for step=1,4000 do
  A.advance(d,step,du)
  if d.state=='docked' and d.service and L.canonical(d.route[d.index])==d.service.station then docked=true;break end
 end
 check(docked,'low-fuel trader never docked at its supply stop')
 local clock=d.untilTime+1;A.advance(d,clock,du)
 check(F.condition(d)=='normal' and not (d.service and not d.serviced) and d.state=='travel','supply stop did not refuel and release the trader')
 for step=1,4000 do
  if not d.service then break end
  A.advance(d,clock+step,du)
 end
 check(not d.service and Save.encode(d.route)==original,'trader did not rejoin its original itinerary after refueling')

 -- The traffic monitor reports a ship stranded mid-transit, not an overdue arrival.
 local lost=copy(r);lost.id='npc/880004';lost.state='transit';lost.area=nil;lost.encounter=nil
 lost.transit={kind='moon',from='earth',to='luna',length=1000,speed=100};lost.depart=0;lost.arrive=1
 lost.ship.cargo={};lost.ship.hold=nil;lost.ship.fuelCharge=0;lost.power=0;lost.fuelStatus=nil
 game.universe.npcs[lost.id]=lost;F.observe(game.universe,lost,game.universe.clock)
 local view=require('src.ui.npc_traffic').snapshot(game,true)
 local row=view.npcs[lost.id]
 check(row and row.stranded and row.phase=='stranded in transit' and row.eta==nil,'monitor did not show a stranded transit')
 check(view.stranded>=1 and view.overdue==0,'stranded transit counted as an overdue arrival')
 game.universe.npcs[lost.id]=nil

 -- A stranded offline ship is drawn where its next update will leave it.
 local drift=copy(d);drift.id='npc/880005';drift.state='travel';drift.service=nil
 drift.index=first;drift.route=copy(loop);drift.depart=0;drift.arrive=1000;drift.fuelClock=0
 drift.ship.cargo={};drift.ship.fuelCharge=0;drift.power=0;drift.fuelStatus=nil
 local dv={clock=0,npcs={[drift.id]=drift}}
 A.advance(drift,0,dv)
 local snap=0
 for i=1,10 do
  local c=i*2;local x,y=A.point(drift,c);A.advance(drift,c,dv);local x2,y2=A.point(drift,c)
  snap=math.max(snap,math.sqrt((x-x2)^2+(y-y2)^2))
 end
 check(drift.fuelStatus=='stranded' and snap<1e-6,'stranded offline ship jittered on the map')

 drift.taskStatus='withdrawing after combat';drift.retreatUntil=1
 F.observe(dv,drift,30)
 check(drift.taskStatus==nil and F.activity(drift):match('out of fuel'),'stale combat withdrawal hid the fuel emergency')
 print(('NPC FUEL LIFECYCLE TEST PASSED (%d checks)'):format(checks))
end
