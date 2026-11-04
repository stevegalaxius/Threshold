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
 local traders={}
 for _,r in pairs(u.npcs) do if r.role=='trader' and r.home=='mars' then traders[#traders+1]=r end end
 table.sort(traders,function(a,b)return a.id<b.id end)
 for _,r in ipairs(traders) do A.advance(r,100,u) end
 local active,waiting=0,0
 for _,r in ipairs(traders) do if r.job then active=active+1 else waiting=waiting+1 end end
 check(active==4 and waiting==5,'reservations failed to limit mine traffic')
 local r=traders[1]
 for _=1,50 do
  local t=(r.state=='docked' and r.untilTime or r.arrive)+.01
  A.advance(r,t,u)
  if (u.jobs.delivered[r.tradeHome] or 0)>0 then break end
 end
 check((u.jobs.delivered[r.tradeHome] or 0)>0,'ore never reached Mars')
 check((r.ship.cargo.martian_ore or 0)==0,'delivery did not unload cargo')
 local encoded=Save.encode(game:saveState());local state=assert(Save.decode(encoded))
 check(state.jobs and state.jobs.delivered[r.tradeHome]>0,'save lost mine economy')
 local dead=traders[2];dead.state='dead'
 J.state(u,10000)
 for _,m in pairs(u.jobs.mines) do check(not m.reservations[dead.id],'dead trader held reservation') end
 -- Exercise physical tractor docking and job pickup on both actual mines.
 for _,area in ipairs({'phobos','deimos'}) do
  game:loadField(area);game:captureALife(true)
  -- Isolate this docking/hauling fixture from newly spawned populations and
  -- live drill ejecta; their own suites exercise those systems.
  u.populationSpawns={}
  for _,site in pairs(require('src.mining').state(u).sites) do site.nextAt=u.clock+1000000 end
  u.npcs={[r.id]=r};r.state='travel';r.area=area;r.home='mars'
  r.tradeHome='station:mars_1';r.tripDestination=area;r.onRoundTrip=true
  r.route=A.roundTrip('mars',area,u.clock,r.tradeHome)
  for i,id in ipairs(r.route) do if id==require('src.locations').station(area,'mining') then r.index=i;break end end
  r.job={mine=area,home=r.tradeHome,amount=10,phase='pickup'}
  u.jobs.mines[area].stock=20;u.jobs.mines[area].reservations[r.id]=10
  r.depart=u.clock;r.arrive=u.clock+100;r.pose=nil;r.offset=nil
  r.ship.cargo={}
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
  check(not e.dockState and r.job.phase=='delivery',area..': pickup failed to launch')
  check(e.cargo.martian_ore==10 and r.ship.cargo.martian_ore==10,area..': physical cargo differs from job')
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
