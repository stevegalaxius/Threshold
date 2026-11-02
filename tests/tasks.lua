return function(game)
 local Tasks,Transport=require('src.tasks'),require('src.transport')
 local A,Save=require('src.alife'),require('src.save')
 local Fields=require('src.fields')
 local copy=require('src.persistence').copy
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true
 local worker
 for _,r in pairs(game.universe.npcs) do
  if r.home=='earth' and r.taskWorker then worker=copy(r);break end
 end
 check(worker~=nil,'no transport worker selected from existing Earth population')
 local u={npcs={[worker.id]=worker},clock=0}
 Transport.seed(u)
 worker.ship.hold=nil;worker.ship.cargo={}
 local source=Fields.earth.stationIds[1]
 local task=assert(Tasks.choose(u,worker,source,0))
 check(task.kind=='transport' and task.phase=='delivery','worker did not choose delivery task')
 check(worker.ship.cargo.scrap==5,'manifest not loaded')
 local offer=u.tasks.offers[task.id]
 check(offer.owner==worker.id and offer.state=='reserved','assignment did not reserve work')
 check(Tasks.choose(u,worker,source,1)==task and worker.ship.cargo.scrap==5,'repeated assignment duplicated cargo')
 local competitor=copy(worker);competitor.id='competing-trader';competitor.task=nil
 competitor.ship.cargo={};u.npcs[competitor.id]=competitor
 local competing=assert(Tasks.choose(u,competitor,source,0))
 check(competing.id~=task.id and offer.owner==worker.id,'two workers reserved the same task')
 Tasks.release(u,competitor,'cancelled',1)
 check(not u.tasks.offers[competing.id].owner,'cancellation did not release reservation')
 local patrol=copy(worker);patrol.id='patrol-test';patrol.role='patrol';patrol.task=nil
 u.npcs[patrol.id]=patrol
 check(not Tasks.choose(u,patrol,source,0),'patrol selected trader work')
 Tasks.register('test_patrol',{
  roles={patrol=true},
  eligible=function(_,_,o,station)return station==o.source end,
  complete=function(_,_,t,station)return station==t.target end
 })
 local patrolOffer=Tasks.post(u,{kind='test_patrol',source=source,target='patrol-point'})
 check(Tasks.choose(u,patrol,source,0).id==patrolOffer.id,'non-trader role could not choose work')
 check(Tasks.arrive(u,patrol,'patrol-point',1) and not patrol.task,'non-trader lifecycle failed')
 local route=assert(Tasks.plan(worker,source,0))
 local driverLeg=false
 for i=2,#route do
  if require('src.locations').get(route[i-1]).area~=require('src.locations').get(route[i]).area then
   driverLeg=require('src.travelgraph').transit(route[i-1],route[i],0).kind=='driver'
  end
 end
 check(driverLeg,'transport route did not use mass drivers')
 worker.route=route;worker.index=2;worker.area='earth';worker.state='travel'
 worker.depart=0;worker.arrive=10;worker.pose=nil;worker.offset=nil
 local completed=false
 for _=1,20 do
  local clock=(worker.state=='docked' and worker.untilTime or worker.arrive)+.01
  A.advance(worker,clock,u)
  check(worker.role=='trader','task changed fixed archetype')
  if worker.lastTask and worker.lastTask.status=='completed' then completed=true;break end
 end
 check(completed,'offline transport never completed')
 check(u.tasks.delivered[task.target]==5,'delivery not recorded')
 check(worker.task and worker.task.id~=task.id,'worker did not choose its next task')
 check(worker.ship.cargo.scrap==5,'delivery/new pickup duplicated cargo')
 local restored=assert(Save.decode(Save.encode(u)))
 check(restored.npcs[worker.id].task.id==worker.task.id,'save lost active task')
 check(restored.tasks.offers[worker.task.id].owner==worker.id,'save lost reservation')
 worker.state='dead';Tasks.clean(u,10000)
 check(not u.tasks.offers[worker.task.id].owner,'dead worker retained reservation')
 local full=copy(worker);full.id='full-trader';full.state='docked';full.task=nil
 full.ship.cargo={scrap=100000};full.ship.hold=nil;u.npcs[full.id]=full
 check(not Tasks.choose(u,full,source,10000),'full trader accepted cargo work')
 check(full.taskStatus=='waiting for work','idle worker did not report waiting state')
 -- Persistent game snapshots contain the board, not just individual NPC tasks.
 game.universe.tasks=copy(restored.tasks)
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 check(saved.tasks and saved.tasks.nextId==restored.tasks.nextId,'game save omitted task board')
 -- Exercise powered travel to the real mass driver, not only timer jumps.
 game:loadField('earth');game:captureALife(true)
 local physical=copy(worker);physical.id='physical-task-worker'
 physical.state='docked';physical.area='earth';physical.home='earth'
 physical.task=nil;physical.lastTask=nil;physical.ship.cargo={};physical.ship.hold=nil
 physical.route=copy(Fields.earth.traderRoute);physical.index=1
 physical.untilTime=game.universe.clock+60
 physical.pose=nil;physical.offset=nil;physical.docking=nil
 game.universe.npcs={[physical.id]=physical};game.universe.tasks=nil
 Transport.seed(game.universe)
 for i=#game.entities,1,-1 do
  local e=game.entities[i]
  if e~=game.player and (e.kind=='ship' or e.kind=='asteroid' or e.kind=='container' or e.kind=='husk') then game:remove(e) end
 end
 game.sleepers={}
 local st=game:locationEntity(source)
 game.player.body:setPosition(st.body:getPosition());game:updateALife(true)
 local e=assert(game.alifeOnline[physical.id])
 check(game:traderCanDepart(e,st),'online worker could not select a dispatch')
 local taskId=physical.task.id
 require('src.ship').layoutHold(e)
 game:undockShip(e)
 local tractorSeen,launchSeen,fireSeen=false,false,false
 local launchRestored=false
 for _=1,36000 do
  local x,y=e.body:getPosition()
  game.player.body:setPosition(x+3000,y);game.player.body:setLinearVelocity(0,0)
  game:step(1/120)
  tractorSeen=tractorSeen or e.driverTractor~=nil
  launchSeen=launchSeen or e.launch~=nil
  fireSeen=fireSeen or e.launch and e.launch.ghost or false
  if e.launch and e.launch.ghost and not launchRestored then
   local launchSave=assert(Save.decode(Save.encode(game:saveState())))
   check(launchSave.npcs[physical.id].driverState.phase=='launch','save omitted active driver animation')
   game:loadState(launchSave)
   physical=game.universe.npcs[physical.id];e=assert(game.alifeOnline[physical.id])
   check(e.launch and e.launch.ghost and e.driverProtected,'save/load lost launch phase or shield')
   launchRestored=true
  end
  if e.alifeEgress or e.dead then break end
 end
 check(not e.dead and e.alifeEgress,'powered worker failed to reach mass driver')
 check(tractorSeen and launchSeen and fireSeen,'NPC skipped tractor, alignment or firing animation')
 check(physical.state=='transit' and physical.transit.kind=='driver','driver did not start interplanetary transit')
 check(physical.task.id==taskId and e.cargo.scrap==5,'driver launch lost task cargo')
 local snapshot=assert(Save.decode(Save.encode(game:saveState())))
 check(snapshot.npcs[physical.id].task.id==taskId,'in-flight save lost task')
 game:loadState(snapshot)
 physical=assert(game.universe.npcs[physical.id])
 check(physical.task.id==taskId and game.universe.tasks.offers[taskId].owner==physical.id,
  'loadState lost task or ownership')
 -- Continue the same worker remotely to destination, then observe real docking.
 game:captureALife(true)
 local destination=physical.task.target
 A.advance(physical,physical.arrive+.01,game.universe)
 local area=require('src.locations').get(destination).area
 game:loadField(area);game:captureALife(true)
 physical=game.universe.npcs[physical.id]
 for i=#game.entities,1,-1 do
  local other=game.entities[i]
  if other~=game.player and (other.kind=='ship' or other.kind=='asteroid' or other.kind=='container' or other.kind=='husk') then game:remove(other) end
 end
 game.sleepers={}
 -- Place the observer near the destination; the NPC starts on its real inbound leg.
 local px,py=A.point(physical,game.universe.clock)
 game.player.body:setPosition(px+3000,py);game:updateALife(true)
 e=assert(game.alifeOnline[physical.id])
 for _=1,48000 do
  local x,y=e.body:getPosition()
  game.player.body:setPosition(x+3000,y);game.player.body:setLinearVelocity(0,0)
  game:step(1/120)
  if physical.lastTask and physical.lastTask.id==taskId or e.dead then break end
 end
 check(not e.dead and physical.lastTask and physical.lastTask.status=='completed','online worker did not dock and deliver')
 check(physical.task and physical.task.id~=taskId,'online worker did not choose new work')
 print(('TASK TEST PASSED (%d checks)'):format(checks))
end
