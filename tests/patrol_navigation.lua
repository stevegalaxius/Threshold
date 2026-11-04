return function(game)
 local A,L,Fields=require('src.alife'),require('src.locations'),require('src.fields')
 local copy=require('src.persistence').copy
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true
 game:loadField('jupiter');game:captureALife(true)
 local r
 for _,record in pairs(game.universe.npcs) do if record.home=='jupiter' and record.role=='patrol' then r=copy(record);break end end
 assert(r,'missing Jupiter patrol')
 for i=#game.entities,1,-1 do
  local e=game.entities[i]
  if e~=game.player and (e.kind=='ship' or e.kind=='asteroid' or e.kind=='container' or e.kind=='husk') then game:remove(e) end
 end
 game.sleepers={};game.universe.npcs={[r.id]=r};game.universe.populationSpawns={}
 game.updateMoonGates=function(self) self:placeMoonGates() end
 local city='station:jupiter_1';local buoy=Fields.jupiter.buoyIds[1]
 r.route={buoy,city};r.index=2;r.state='travel';r.area='jupiter';r.node=nil;r.encounter=nil;r.offset=nil;r.pose=nil
 r.depart=game.universe.clock;r.arrive=r.depart+300
 local x,y=L.position(city,game.universe.clock)
 local safe=Fields.jupiter.planetR+require('src.tuning').surfacePullRange+1000
 local angle=math.atan2(y,x)+.08
 x,y=math.cos(angle)*safe,math.sin(angle)*safe
 local vx,vy=game:flowAt(x,y)
 r.pose={x=x,y=y,a=angle+math.pi/2,vx=vx,vy=vy,w=0,clock=game.universe.clock}
 local ix,iy=L.inspectionPosition(city,game.universe.clock)
 check(math.sqrt(ix*ix+iy*iy)>Fields.jupiter.planetR+require('src.tuning').surfacePullRange,
  'inspection point is inside the gravity band')
 game.player.body:setPosition(r.pose.x+4000,r.pose.y)
 local e=A.wake(game,r)
 local arrived=false
 for i=1,72000 do
  x,y=e.body:getPosition();game.player.body:setPosition(x+4000,y);game.player.body:setLinearVelocity(0,0)
  game:step(1/120)
  assert(not e.dead,'patrol died visiting Olympus')
  if r.state=='idle' then arrived=true;break end
 end
 check(arrived,'patrol looped above Olympus without beginning its inspection')
 check(not e.dockState,'patrol inspection entered docking control')
 A.capture(game,e,false)
 local savedX,savedY=e.body:getPosition()
 local sampleX,sampleY=A.point(r,game.universe.clock)
 check((savedX-sampleX)^2+(savedY-sampleY)^2<.01,'capturing the inspection changed its sampled position')
 game:remove(e,true);e=A.wake(game,r)
 x,y=e.body:getPosition()
 check((x-savedX)^2+(y-savedY)^2<.01,'restoring the inspection moved the patrol')
 -- A remote inspection has no saved physical pose or local correction.
 game:remove(e,true);r.pose=nil;r.offset=nil
 e=A.wake(game,r)
 ix,iy=L.inspectionPosition(city,game.universe.clock);x,y=e.body:getPosition()
 check((x-ix)^2+(y-iy)^2<.01,'remote inspection materialized inside the city instead of above it')
 r.untilTime=game.universe.clock+50
 for i=1,5400 do
  x,y=e.body:getPosition();game.player.body:setPosition(x+4000,y);game.player.body:setLinearVelocity(0,0)
  game:step(1/120)
  assert(not e.dead and not e.dockState,'patrol died or docked during its inspection')
 end
 x,y=e.body:getPosition();ix,iy=L.inspectionPosition(city,game.universe.clock)
 check((x-ix)^2+(y-iy)^2<700^2,'patrol left its safe inspection position while waiting')
 -- Use an actual task transition out of the city rather than manually teleporting.
 local Tasks=require('src.tasks')
 Tasks.release(game.universe,r,'test fixture',game.universe.clock)
 Tasks.post(game.universe,{kind='patrol',source=city,target=buoy,cooldown=0,duration=10})
 r.untilTime=game.universe.clock
 require('src.security').updateOnline(game,e,A)
 check(r.state=='travel' and r.task and r.task.target==buoy,'patrol did not select its next duty')
 local departed=false
 for i=1,72000 do
  x,y=e.body:getPosition();game.player.body:setPosition(x+4000,y);game.player.body:setLinearVelocity(0,0)
  game:step(1/120)
  assert(not e.dead,'patrol died leaving its inspection position')
  if r.state=='idle' and r.node==buoy then departed=true;break end
 end
 check(departed,'patrol did not leave Olympus for its next buoy inspection')
 print(('PATROL NAVIGATION TEST PASSED (%d checks)'):format(checks))
end
