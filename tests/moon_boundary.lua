return function(game)
 local Fields,T=require('src.fields'),require('src.tuning')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true;game:loadField('earth')
 game:launchTrip('luna',{bearing=0,length=Fields.moons.luna.gap})
 local edge=game:laneBoundary()
 local sides={};local farRock
 for _,e in ipairs(game.entities) do
  if e.lane=='hazard' then
   local s,n=game:toLane(e.body:getPosition())
   check(math.abs(s)<=game.lane.half-3000.01,'hazards obstruct a handoff mouth')
   check(math.abs(n)<=edge+T.laneHazardDepth+.01,'rock outside authored hazard band')
   if math.abs(n)>edge then sides[n>0 and 1 or -1]=true;farRock=e end
  end
 end
 check(sides[1] and sides[-1],'no rocks beyond both lateral edges')
 local count=#game.entities
 local p=game.player
 p.runup=nil;p.laneCarry=nil
 -- Keep force checks independent of the asteroid field and NPC steering.
 local body=love.physics.newBody(game.world,0,0,'dynamic')
 love.physics.newFixture(body,love.physics.newCircleShape(10),1):setSensor(true)
 local probe={kind='ship',body=body};game.entities={probe}
 for _,side in ipairs({-1,1}) do
  local x,y=game:fromLane(0,side*(edge+800))
  body:setPosition(x,y);body:setLinearVelocity(0,0)
  game:updateLane(1/120)
  game.world:update(1/120)
  local _,_,phi=game:toLane(x,y)
  local vx,vy=body:getLinearVelocity()
  local lateral=-math.sin(phi)*vx+math.cos(phi)*vy
  check(lateral*side<0,'moon lateral edge does not push inward')
  check(not probe.laneBuff,'moon trip gained the interplanetary lane buff')
  local xx,yy=body:getPosition()
  check(math.sqrt((xx-x)^2+(yy-y)^2)<10,'soft edge teleported or snapped ship')
 end
 local x,y=game:fromLane(0,edge-100)
 body:setPosition(x,y);body:setLinearVelocity(0,0)
 game:updateLane(1/120);game.world:update(1/120)
 local vx,vy=body:getLinearVelocity()
 check(vx*vx+vy*vy<.001,'boundary pushes ships inside the free-flight envelope')
 game.entities={farRock}
 farRock.body:setLinearVelocity(0,0)
 game:updateLane(1/120);game.world:update(1/120)
 vx,vy=farRock.body:getLinearVelocity()
 check(vx*vx+vy*vy<.001,'soft edge swept hazard rocks back onto the route')
 check(#game.entities==1,'boundary update spawned debris dynamically')
 body:destroy()
 print(('MOON BOUNDARY TEST PASSED (%d checks; %d original entities)'):format(checks,count))
end
