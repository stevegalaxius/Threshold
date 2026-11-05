return function(game)
 local A=require('src.alife');local J=require('src.jobs');local Save=require('src.save')
 -- The observer must survive while following the hauler through terrain.
 require('src.tuning').dev.god=true
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 game:loadField('phobos')
 for _,area in ipairs({'phobos','deimos'}) do
  game:loadField(area)
  local st=game:locationEntity(require('src.locations').station(area,'mining'))
  check(st and st.surfaceMine,'missing surface mine')
  check(st.body:getAngularVelocity()==0,'mine rotates independently of terrain')
  -- Dock layouts may have several horizontal or angled doors. Check the
  -- actual outward corridor rather than requiring the old negative angle.
  local d=st.dock;local x,y=game.dockWorld(st,1,d.x2+100,0,d)
  local a=game.dockAngle(st,1,d);local clear=true
  game.world:rayCast(x,y,x+math.cos(a)*(d.runway+300),y+math.sin(a)*(d.runway+300),function(fixture)
   local e=fixture:getUserData()
   if e and e.kind=='planet' then clear=false end
   return 1
  end)
  check(clear,'mine docking corridor points into the terrain')
 end
 game:loadField('venus');game:captureALife(true)
 local u=game.universe
 local Tasks,L=require('src.tasks'),require('src.locations')
 local traders={}
 for _,r in pairs(u.npcs) do if r.role=='trader' and r.home=='mars' then traders[#traders+1]=r end end
 table.sort(traders,function(a,b)return a.id<b.id end)
 check(#traders>0,'no Mars traders')
 for _,r in ipairs(traders) do check(r.taskWorker,'Mars trader is not on the task board') end
 local ore=0
 for _,o in pairs(Tasks.state(u).offers) do if o.kind=='transport' and o.item=='iron_ore' then ore=ore+1;check(o.mine and L.get(o.source).area==o.mine,'ore job does not start at its mine') end end
 check(ore>0,'no ore jobs posted')
 -- Drain a mine: its ore jobs stop being eligible.
 local mine=J.mines[1];J.stock(u,L.station(mine,'mining')).iron_ore=0
 local probe=require('src.persistence').copy(traders[1]);probe.id='ore-probe';probe.task=nil;probe.ship.cargo={};probe.ship.hold=nil
 local mineStation=L.stations(mine,'trade')[1]
 local picked=Tasks.choose(u,probe,mineStation,u.clock)
 check(not picked or picked.item~='iron_ore','empty mine handed out ore')
 if picked then Tasks.release(u,probe,'test',u.clock) end
 J.stock(u,L.station(mine,'mining')).iron_ore=20;probe.task=nil
 for id,o in pairs(Tasks.state(u).offers) do if o.source==mineStation and o.item~='iron_ore' then o.readyAt=math.huge end end
 picked=assert(Tasks.choose(u,probe,mineStation,u.clock),'stocked mine offered no ore job')
 check(picked.item=='iron_ore' and probe.ship.cargo.iron_ore==10,'ore pickup did not load cargo')
 check(J.available(u,mineStation,J.item)==10,'ore pickup did not draw down mine stock')
 local encoded=Save.encode(game:saveState());local state=assert(Save.decode(encoded))
 check(state.mining and state.mining.stock[mineStation],'save lost mine stock')
 Tasks.release(u,probe,'test',u.clock)
 local r=traders[1]
 -- Exercise physical tractor docking and job pickup on both actual mines.
 for _,area in ipairs({'phobos','deimos'}) do
  game:loadField(area);game:captureALife(true)
  -- Isolate this docking/hauling fixture from newly spawned populations and
  -- live drill ejecta; their own suites exercise those systems.
  u.populationSpawns={}
  for _,site in pairs(require('src.mining').state(u).sites) do site.nextAt=u.clock+1000000 end
  u.npcs={[r.id]=r};r.state='travel';r.area=area;r.home='mars'
  r.tradeHome='station:mars_1'
  r.route=A.roundTrip('mars',area,u.clock,r.tradeHome)
  for i,id in ipairs(r.route) do if id==require('src.locations').station(area,'mining') then r.index=i;break end end
  r.task=nil;r.taskWorker=true;r.onRoundTrip=nil;r.tripDestination=nil
  J.stock(u,L.station(area,'mining')).iron_ore=20
  for _,o in pairs(Tasks.state(u).offers) do if o.source==L.stations(area,'trade')[1] and o.item~='iron_ore' then o.readyAt=math.huge end end
  -- Keep the dock/exit fixture on its authored route rather than a random
  -- population spread offset; formation spacing is tested separately.
  r.depart=u.clock;r.arrive=u.clock+100;r.pose=nil;r.offset=nil;r.spread=0
  r.ship.cargo={[require('src.reactor_fuel').item()]=8};r.ship.hold=nil;r.ship.fuelCharge=0;r.ship.fuelInitialized=true;r.power=nil
  local st=game:locationEntity(require('src.locations').station(area,'mining'))
  local x,y=game.dockWorld(st,1,st.dock.x2+st.dock.runway+600,300)
  r.pose={x=x,y=y,a=st.dock.a+math.pi,vx=0,vy=0,w=0,clock=u.clock}
  local e=A.wake(game,r)
  check(not e.dockState and not game:inTractorZone(st,e.body:getPosition()),area..': approach test started inside capture')
  game.player.body:setPosition(x+3000,y)
  require('src.ai').think(game,e,1/120)
  check(e.intent.thrust==e.intent.thrust,area..': mining approach produced invalid steering')
  -- Fly into the real capture zone; do not force a tractor lock.
  for i=#game.entities,1,-1 do
   local other=game.entities[i]
   if other.kind=='asteroid' or other.kind=='ship' and other~=e and other~=game.player then game:remove(other) end
  end
  game.sleepers={}
  for _=1,12000 do
   game:step(1/120)
   if e.dockState and e.dockState.done then break end
  end
  check(not e.dead and e.dockState and e.dockState.done,area..': tractor docking failed')
  game:updateDockedShip(e,100)
  check(not e.dockState and r.task and r.task.item=='iron_ore',area..': ore pickup failed to launch')
  check(e.cargo.iron_ore==10 and r.ship.cargo.iron_ore==10,area..': physical cargo differs from job')
  game.updateMoonGates=function(self) self:placeMoonGates() end
  for _=1,24000 do
   local x,y=e.body:getPosition()
   game.player.body:setPosition(x+3000,y)
   game.player.body:setLinearVelocity(0,0)
   game:step(1/120)
   if e.alifeEgress or e.dead then break end
  end
  check(e.alifeEgress and not e.dead,area..': loaded trader failed to depart')
  local x,y=e.body:getPosition()
  local vx,vy=e.body:getLinearVelocity()
  check((vx*x+vy*y)/math.sqrt((vx*vx+vy*vy)*(x*x+y*y))>.9,
   area..': loaded trader reached the exit sideways')
 end
 print(('MARS JOBS TEST PASSED (%d checks)'):format(checks))
end
