return function(game)
 local Fields,T=require('src.fields'),require('src.tuning')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true;game:loadField('earth')
 game:launchTrip('luna',{bearing=0,length=Fields.moons.luna.gap})
 local originals=game.entities
 local edge=game:laneBoundary()
 local sides={};local farRock
 local distantSides={}
 local w,h=love.graphics.getDimensions()
 local view=math.sqrt(w*w+h*h)/math.min(T.minZoom,T.cineZoom)
 for _,e in ipairs(game.entities) do
  if e.lane=='hazard' then
   local s,n=game:toLane(e.body:getPosition())
   check(math.abs(s)<=game.lane.half-3000.01,'hazards obstruct a handoff mouth')
   check(math.abs(n)<=edge+game.lane.hazardDepth+.01,'rock outside authored hazard band')
   if math.abs(n)>edge then sides[n>0 and 1 or -1]=true;farRock=e end
   if math.abs(n)>edge+T.edgeSoft+view then distantSides[n>0 and 1 or -1]=true end
  end
 end
 check(sides[1] and sides[-1],'no rocks beyond both lateral edges')
 check(distantSides[1] and distantSides[-1],'debris ends within the widest player view')
 check(game.lane.hazardDepth>=T.edgeSoft+view*2,'hazard field does not extend beyond the view')
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
 -- Going further out must not store a stronger return kick.
 local function response(over,speed,tangent)
  local x,y=game:fromLane(0,edge+over)
  local _,_,phi=game:toLane(x,y)
  local nx,ny=-math.sin(phi),math.cos(phi)
  local tx,ty=math.cos(phi),math.sin(phi)
  body:setPosition(x,y);body:setLinearVelocity(nx*speed+tx*tangent,ny*speed+ty*tangent)
  game:updateLane(1/120);game.world:update(1/120)
  local vx,vy=body:getLinearVelocity()
  return vx*nx+vy*ny,vx*tx+vy*ty
 end
 local nearSpeed=response(800,0,0)
 local farSpeed=response(12000,0,0)
 check(math.abs(nearSpeed-farSpeed)<.01,'deeper excursion creates a stronger rubber-band return')
 check(math.abs(farSpeed)<1,'stationary ship receives a violent inward kick')
 local returning=response(12000,-200,0)
 check(returning>-201 and returning<=-200,'boundary violently accelerates an already-returning ship')
 local outward,tangent=response(12000,1000,300)
 check(outward>900 and outward<1000,'outward braking reverses or fails to slow the ship')
 check(math.abs(tangent-300)<.01,'lateral boundary changes travel along the route')
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
 game.entities=originals
 local Render=require('src.render')
 local lg=love.graphics
 for _,sample in ipairs({{name='near-edge',offset=T.edgeSoft},{name='beyond-view',offset=T.edgeSoft+view}}) do
  local x,y=game:fromLane(0,edge+sample.offset)
  p.body:setPosition(x,y);p.body:setLinearVelocity(0,0)
  game.camera.x,game.camera.y,game.camera.zoom=x,y,math.min(T.minZoom,T.cineZoom)
  local canvas=lg.newCanvas(lg.getDimensions())
  lg.setCanvas(canvas);Render.world(game);lg.setCanvas()
  canvas:newImageData():encode('png','moon-hazards-'..sample.name..'.png')
 end
 print(('MOON BOUNDARY TEST PASSED (%d checks; %d original entities)'):format(checks,count))
end
