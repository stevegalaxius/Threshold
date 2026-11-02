return function(game)
 local Ship,T=require('src.ship'),require('src.tuning')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local god=T.dev.god;T.dev.god=false
 game.autosaveOff=true;game:loadField('earth')
 local g=assert(game:findDriver())
 local p=game.player;p.dockState=nil
 local function place(e,lx,ly)
  local x,y=game:driverBreech(g)
  local c,s=math.cos(g.angle),math.sin(g.angle)
  e.body:setPosition(x+c*lx-s*ly,y+s*lx+c*ly)
  e.body:setLinearVelocity(g.body:getLinearVelocity());e.driverCooldown=nil
 end
 place(p,-200,0)
 check(game:requestDriver(p,g),'player tractor capture failed')
 check(p.driverProtected and g.driverShip==p,'tractor capture did not protect/occupy')
 local lg=love.graphics;local canvas=lg.newCanvas(256,256)
 local x,y=p.body:getPosition()
 lg.push('all');lg.setCanvas(canvas);lg.clear(.02,.035,.06,1);lg.origin();lg.translate(128-x,128-y)
 require('src.render').ship(game,p)
 lg.setCanvas();lg.pop()
 local image=canvas:newImageData()
 local r,gc,b,alpha=image:getPixel(188,128)
 check(alpha>0 and b>r,'captured ship did not get the blue transit glow')
 image:encode('png','driver-protected-glow.png')

 local armor=p.armor
 for _,cause in ipairs({'gun','laser','missile','exhaust'}) do game:damage(p,100,game:findDriver(),cause) end
 check(p.armor==armor,'tractor capture allowed enemy fire damage')
 local vx0,vy0=p.body:getLinearVelocity()
 local px,py=p.body:getPosition()
 game:explode(px-10,py,100,100,1000,{team=2},p,'missile')
 local vx1,vy1=p.body:getLinearVelocity()
 check(vx0==vx1 and vy0==vy1,'enemy blast knocked a captured ship out of its beam')
 local other=Ship.new(game,{hull='halcyon_wisp'})
 place(other,-200,0)
 check(not game:requestDriver(other,g,'mars'),'driver captured two ships at once')
 place(p,200,0);game:updateDriverTractor(p,1/120)
 check(not p.driverProtected and not g.driverShip,'lost tractor left permanent protection/occupancy')
 place(p,-50,0);game:requestDriver(p,g);game:updateDriverTractor(p,1/120)
 check(game.driverMenu and p.driverProtected,'held player lost protection')
 game:closeDriverMenu()
 check(not p.driverProtected and not g.driverShip,'cancel menu did not clear shield')
 local before=p.armor;game:damage(p,1,g,'laser')
 check(p.armor==before-1,'cancelled tractor left permanent invulnerability')
 place(p,-50,0);game:requestDriver(p,g);game:updateDriverTractor(p,1/120)
 check(game:fireDriver('mars') and p.launch and p.driverProtected,'player launch lost tractor protection')
 p.launch.t=T.driverAlign+.1;g.aimLeft=0;game:updateDriverLaunch(p,1/120)
 check(p.launch.ghost and p.mainBurn==1,'player did not use the shared firing animation')
 p.launch=nil;game:closeDriverMenu()
 for _,f in ipairs(p.body:getFixtures()) do f:setSensor(false) end

 place(other,-50,0);game:requestDriver(other,g,'mars');game:updateDriverTractor(other,1/120)
 check(other.launch and not game.driverMenu,'NPC did not auto-select its task destination')
 -- The same launch controller performs hold, alignment, firing and coast.
 other.launch.t=0;g.aimLeft=0
 game:updateDriverLaunch(other,1/120)
 check(not other.launch.ghost,'NPC bypassed alignment')
 other.launch.t=T.driverAlign+.1;game:updateDriverLaunch(other,1/120)
 check(other.launch.ghost and other.mainBurn==1,'NPC did not fire down the barrel')
 local vx,vy=other.body:getLinearVelocity()
 check(math.sqrt(vx*vx+vy*vy)>0,'NPC launch did not accelerate')
 armor=other.armor;game:damage(other,100,p,'laser')
 check(other.armor==armor,'firing NPC lost protection')
 other.launch.t=T.driverAlign+T.driverFire+T.driverCoast
 game:updateDriverLaunch(other,1/120)
 check(other.alifeDepart and not other.launch and not g.driverShip,'NPC did not complete shared launch')
 check(not game.pendingFlight,'NPC launch hijacked player travel')
 other.body:destroy()
 T.dev.god=god
 print(('DRIVER LAUNCH TEST PASSED (%d checks)'):format(checks))
end
