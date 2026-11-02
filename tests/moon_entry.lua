return function(game)
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local function near(a,b)return math.abs(a-b)<.001 end
 game.autosaveOff=true
 for _,area in ipairs({'earth','deimos'}) do
  game:loadField(area)
  local gate=assert(game.moonGates[1])
  local p=game.player;p.dockState=nil;game.state='playing'
  local c,s=math.cos(gate.a),math.sin(gate.a)
  p.body:setPosition(c*(game.arenaRadius-100),s*(game.arenaRadius-100))
  p.body:setLinearVelocity(c*700-s*140,s*700+c*140)
  p.body:setAngle(gate.a+.7);p.body:setAngularVelocity(.4)
  p.intent.thrust=.6;p.intent.strafe=.3;p.intent.boost=true;p.intent.firePrimary=true
  local x,y=p.body:getPosition()
  p.intent.aimX,p.intent.aimY=x+200,y-300
  p.power=42;p.spool=.6;p.mainBurn=.6
  p.weapons[1].aim=.12;p.weapons[1].cooldown=.37;p.weapons[1].firing=true
  game.camera.x,game.camera.y=x+80,y-50;game.camera.zoom=.63
  game:updateMoonGates(1/120)
  check(not game.lane and not p.departure,'moon exit took control before crossing map edge')
  x,y=c*(game.arenaRadius+1),s*(game.arenaRadius+1)
  p.body:setPosition(x,y);p.intent.aimX,p.intent.aimY=x+200,y-300
  local vx,vy=p.body:getLinearVelocity();local angle=p.body:getAngle()
  local sx,sy=game.camera:toScreen(x,y)
  local aimSX,aimSY=game.camera:toScreen(p.intent.aimX,p.intent.aimY)
  local originWorld=game.world
  game:updateMoonGates(1/120)
  p=game.player
  check(game.trip and game.trip.moon and game.trip.to==gate.to,'crossing did not enter moon transit immediately')
  check(game.trip.originScene.world==originWorld,'entry rebuilt origin scenery')
  local xx,yy=game.camera:toScreen(p.body:getPosition())
  check(near(xx,sx) and near(yy,sy),'moon entry jumped the ship on screen')
  local vxx,vyy=p.body:getLinearVelocity()
  check(near(vx,vxx) and near(vy,vyy),'moon entry redirected or replaced velocity')
  check(near(p.body:getAngle(),angle) and near(p.body:getAngularVelocity(),.4),'moon entry forced alignment or removed spin')
  check(p.intent.thrust==.6 and p.intent.strafe==.3 and p.intent.boost and p.intent.firePrimary,'entry cleared player inputs')
  xx,yy=game.camera:toScreen(p.intent.aimX,p.intent.aimY)
  check(near(xx,aimSX) and near(yy,aimSY),'aim target jumped during coordinate handoff')
  check(p.power==42 and p.spool==.6 and p.mainBurn==.6,'entry reset capacitor or engine spool')
  check(p.weapons[1].aim==.12 and p.weapons[1].cooldown==.37 and p.weapons[1].firing,'entry reset weapon aim or firing cadence')
  check(game.camera.zoom==.63 and not game.cineZoom and not game.flash,'entry forced zoom or flashed screen')
  check(not p.departure and not p.runup and not p.launch,'moon entry created a scripted controller')
  for _,f in ipairs(p.body:getFixtures()) do check(not f:isSensor(),'entry ghosted ship collisions') end
  local intent={thrust=-1,strafe=-.4,boost=false,firePrimary=false,fireSecondary=false,fireAux=false,
   aimX=p.intent.aimX,aimY=p.intent.aimY}
  game:setPlayerIntent(intent);game:step(1/120)
  check(game.player.intent.thrust==-1 and game.player.intent.strafe==-.4,'player could not change course immediately after entry')

 end
 print(('MOON ENTRY TEST PASSED (%d checks)'):format(checks))
end
