return function(game)
 local T=require('src.tuning')
 local checks=0
 local function check(ok,msg) assert(ok,msg); checks=checks+1 end
 game.autosaveOff=true
 local p=game.player
 local slot
 for i,s in ipairs(p.hull.slots) do if s.family=='computer' then slot=i; break end end
 assert(slot,'test ship needs a computer slot')
 p.loadout[slot]='nav_computer'
 -- Check cost in the populated game field before switching to isolated cases.
 local started=love.timer.getTime()
 p.body:setLinearVelocity(1000,0)
 for _=1,60 do game:updateComputers(1/60) end
 print(('nav computer: %.2f ms/update in populated field'):format((love.timer.getTime()-started)/60*1000))
 p.body:setPosition(0,0); p.body:setLinearVelocity(100,0)
 game.entities={p}
 local hazard=game:spawnAsteroid(180,0,20,'rock')
 hazard.body:setLinearVelocity(0,0)
 game:updateComputers(.2)
 check(p.navThreat and p.navThreat.target==hazard and p.navWarn>.9,'imminent danger did not show')
 p.body:setLinearVelocity(-5,0)
 game:updateComputers(1/120)
 check(not p.navThreat and p.navWarn==0,'warning lingered after reversing away')
 p.body:setLinearVelocity(100,0)
 local reach=hazard.radius+p.halfLength*.8
 hazard.body:setPosition(reach+100*(T.navLookahead+.1),0)
 game:updateComputers(.2)
 check(not p.navThreat,'warning shown outside immediate lookahead')
 hazard.body:setPosition(180,200)
 game:updateComputers(.2)
 check(not p.navThreat,'near miss reported as danger')
 hazard.body:setPosition(180,0)
 p.body:setLinearVelocity(0,0)
 game:updateComputers(.2)
 check(not p.navThreat,'stationary relative motion kept the warning alive')
 -- An incoming object is still dangerous while you are stopped or backing away.
 p.body:setLinearVelocity(-5,0); hazard.body:setLinearVelocity(-200,0)
 game:updateComputers(.2)
 check(p.navThreat and p.navThreat.vx>0,'incoming hazard used backwards absolute ship velocity')
 local line=love.graphics.line; local lines={}
 love.graphics.line=function(x,y,xx,yy) lines[#lines+1]={x,y,xx,yy} end
 game:drawComputers(1)
 love.graphics.line=line
 check(#lines>0 and lines[1][3]>=lines[1][1],'warning line points away from incoming hazard')
 hazard.body:setLinearVelocity(200,0)
 game:updateComputers(1/120)
 check(not p.navThreat and p.navWarn==0,'departing hazard retained its warning')
 hazard.body:setLinearVelocity(-200,0)
 game:updateComputers(.2)
 p.loadout[slot]=false
 game:updateComputers(1/120)
 check(not p.navThreat and p.navWarn==0,'removed computer left a stale warning')
 p.loadout[slot]='nav_computer'
 p.dockState={}
 game:updateComputers(.2)
 check(not p.navThreat,'docking kept a collision warning')
 p.dockState=nil
 p.catching=true
 game:updateComputers(.2)
 check(not p.navThreat,'catching kept a collision warning')
 p.catching=nil
 p.body:setLinearVelocity(300,0); hazard.body:setPosition(400,0); hazard.body:setLinearVelocity(0,0)
 local nearer=game:spawnAsteroid(180,0,20,'rock'); nearer.body:setLinearVelocity(0,0)
 game:updateComputers(.2)
 check(p.navThreat.target==nearer,'warning picked an arbitrary hazard over the earliest collision')
 local function warningStyle()
  local width,color=love.graphics.setLineWidth,love.graphics.setColor
  local largest,red=0,false
  love.graphics.setLineWidth=function(w) largest=math.max(largest,w); width(w) end
  love.graphics.setColor=function(r,g,b,a)
   if type(r)=='number' and r>.9 and g<.3 then red=true end
   color(r,g,b,a)
  end
  game:drawComputers(1)
  love.graphics.setLineWidth,love.graphics.setColor=width,color
  return largest,red
 end
 -- The impact X is only shown in the final half second, on a real fixture.
 game:remove(hazard)
 nearer.body:setPosition(300,0)
 p.body:setLinearVelocity(300,0)
 game:updateComputers(.2)
 check(p.navThreat and p.navThreat.time>.5,'impact X appeared too early')
 local cautionWidth,cautionRed=warningStyle()
 nearer.body:setPosition(130,0)
 game:updateComputers(.2)
 check(p.navThreat.time<=.5 and p.navThreat.hitX~=nil,'imminent impact did not get an X')
 local urgentWidth,urgentRed=warningStyle()
 check(urgentWidth>cautionWidth and urgentRed and not cautionRed,'imminent danger was not visually stronger than caution')
 local cam=game.camera
 cam.x,cam.y,cam.zoom=0,0,1.6
 local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
 love.graphics.setCanvas(canvas); require('src.render').world(game); love.graphics.setCanvas()
 canvas:newImageData():encode('png','nav-danger-imminent.png')
 local hitX,hitY=p.navThreat.hitX,p.navThreat.hitY
 local onSurface=false
 for _,f in ipairs(nearer.body:getFixtures()) do
  for _,delta in ipairs({{.01,0},{-.01,0},{0,.01},{0,-.01}}) do
   onSurface=onSurface or f:testPoint(hitX+delta[1],hitY+delta[2])
  end
 end
 check(hitX>100 and hitX<150 and onSurface,'impact marker missed the actual obstacle surface')
 local drawn={}
 love.graphics.line=function(x,y,xx,yy) drawn[#drawn+1]={x,y,xx,yy} end
 game:drawComputers(1)
 love.graphics.line=line
 check(#drawn==12,'impact marker was not drawn as an X after the ten path dashes')
 local a,b=drawn[11],drawn[12]
 check(math.abs((a[1]+a[3])/2-hitX)<.01 and math.abs((b[2]+b[4])/2-hitY)<.01,'X was not centered at impact')
 p.body:setLinearVelocity(-300,0)
 game:updateComputers(1/120)
 check(not p.navThreat and p.navWarn==0,'impact X survived steering clear')
 -- Real-shape regressions: nearby objects and hollow station bounds must
 -- not warn unless the moving hull will actually touch a fixture.
 local prediction=require('src.collision_prediction')
 local body=love.physics.newBody(game.world,0,0,'dynamic')
 love.physics.newFixture(body,love.physics.newRectangleShape(160,10),1)
 local thin={body=body,kind='ship',halfLength=80,hull={radius=5}}
 body:setLinearVelocity(300,0)
 local function obstacle(shape,x,y,radius,kind)
  local b=love.physics.newBody(game.world,x,y,'static')
  love.physics.newFixture(b,shape)
  return {body=b,kind=kind or 'asteroid',radius=radius}
 end
 local miss=obstacle(love.physics.newRectangleShape(10,10),200,30,100)
 game.entities={thin,miss}
 check(not prediction.threat(game,thin,2),'near miss triggered from its oversized bounding circle')
 miss.body:setPosition(200,0)
 local threat=assert(prediction.threat(game,thin,2))
 check(math.abs(threat.time-115/300)<.001,'swept hull did not predict real first contact')
 body:setAngle(math.pi/2)
 check(prediction.threat(game,thin,2).time>threat.time,'prediction ignored ship orientation')
 body:setAngle(0)
 local planet=obstacle(love.physics.newCircleShape(50),300,0,50,'planet')
 game.entities={thin,planet}
 check(math.abs(prediction.threat(game,thin,2).time-170/300)<.001,'circle surface timing incorrect')
 planet.body:setPosition(300,65)
 check(not prediction.threat(game,thin,2),'near miss beside curved surface warned')
 local wall=obstacle(love.physics.newChainShape(false,200,-100,200,100),0,0,300,'planet')
 game.entities={thin,wall}
 check(math.abs(prediction.threat(game,thin,2).time-.4)<.001,'chain boundary contact missed')
 local station=obstacle(love.physics.newRectangleShape(20,440),210,0,300,'station')
 -- Put four walls around an empty hub in a single body's actual fixtures.
 station.body:setPosition(0,0)
 for _,f in ipairs(station.body:getFixtures()) do f:destroy() end
 for _,rect in ipairs({{210,0,20,440},{-210,0,20,440},{0,210,400,20},{0,-210,400,20}}) do
  love.physics.newFixture(station.body,love.physics.newRectangleShape(rect[1],rect[2],rect[3],rect[4]))
 end
 game.entities={thin,station}; body:setLinearVelocity(20,0)
 check(not prediction.threat(game,thin,2),'empty station hub warned because of the station radius')
 body:setLinearVelocity(100,0)
 check(math.abs(prediction.threat(game,thin,2).time-1.2)<.001,'actual station wall was not detected from inside hub')
 -- A small obstacle between center/side rays still hits the actual hull.
 for _,f in ipairs(body:getFixtures()) do f:destroy() end
 love.physics.newFixture(body,love.physics.newRectangleShape(40,40),1)
 miss.body:setPosition(100,10)
 game.entities={thin,miss}; body:setLinearVelocity(300,0)
 check(prediction.threat(game,thin,2)~=nil,'thin glancing contact fell between sampled rays')
 for _,f in ipairs(miss.body:getFixtures()) do f:setSensor(true) end
 check(not prediction.threat(game,thin,2),'noncolliding sensor reported as danger')
 print(('NAV COMPUTER TEST PASSED (%d checks)'):format(checks))
end
