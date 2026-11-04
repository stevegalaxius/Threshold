-- Real fitted haulers negotiate geometry and traffic using ordinary intent.
return function(game)
 local AI,Ship,Nav,T=require('src.ai'),require('src.ship'),require('src.local_navigation'),require('src.tuning')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local function scene()
  local g={world=love.physics.newWorld(0,0,true),entities={},time=0,universe={clock=0},idCounter=0}
  function g:nextId()self.idCounter=self.idCounter+1;return self.idCounter end
  return g
 end
 local function ship(g,x,y,a,tx,ty)
  local def=require('src.data').enemies.freighter
  local e=Ship.new(g,{hull=def.hull,enemy=def,cargo=def.cargo,team=3,x=x,y=y,angle=a})
  local stop={kind='buoy',body=love.physics.newBody(g.world,tx,ty,'kinematic')}
  e.route={stop};e.routeIndex=1;g.entities[#g.entities+1]=e
  return e
 end
 local function wall(g,x,y,w,h)
  local body=love.physics.newBody(g.world,x,y,'static')
  local o={kind='structure',body=body,radius=math.sqrt(w*w+h*h)/2}
  local f=love.physics.newFixture(body,love.physics.newRectangleShape(w,h));f:setUserData(o)
  g.entities[#g.entities+1]=o
 end
 local function run(g,ships,seconds,targets)
  local reached={};local boost=false;local collisions=0
  for i=1,seconds*120 do
   g.time=g.time+1/120;g.universe.clock=g.time
   for n,e in ipairs(ships) do
    AI.think(g,e,1/120);boost=boost or e.intent.boost
    Ship.fly(e,1/120)
    local x,y=e.body:getPosition()
    if (x-targets[n][1])^2+(y-targets[n][2])^2<450^2 then reached[n]=true end
   end
   g.world:update(1/120)
   for _,contact in ipairs(g.world:getContacts()) do if contact:isTouching() then collisions=collisions+1 end end
   local done=true;for n in ipairs(ships) do if not reached[n] then done=false end end
   if done then return reached,boost,g.time,collisions end
  end
  return reached,boost,g.time,collisions
 end
 local g=scene();local e=ship(g,-5000,0,0,5000,0)
 wall(g,0,0,100,700)
 local reached,boost,elapsed,hits=run(g,{e},90,{{5000,0}})
 check(reached[1],'hauler remained stuck at a wall')
 check(hits==0,'hauler collided with the wall while navigating around it')
 check(boost,'hauler never used afterburner on its clear approach/departure')
 g.world:destroy()
 -- Escape a concave pocket instead of repeatedly pushing toward its back wall.
 g=scene();e=ship(g,0,500,-math.pi/2,0,-1800)
 wall(g,0,0,800,80);wall(g,-400,500,80,1000);wall(g,400,500,80,1000)
 reached,boost,elapsed,hits=run(g,{e},140,{{0,-1800}})
 check(reached[1],'hauler did not back out and route around a concave obstacle')
 check(hits==0,'hauler scraped its way through the concave obstacle')
 g.world:destroy()
 -- A long wall requires an actual committed detour, beyond short heading probes.
 g=scene();e=ship(g,-2200,0,0,2200,0)
 wall(g,0,0,160,4200)
 local wx,wy,detour=Nav.waypoint(g,e,2200,0)
 check(detour and math.abs(wy)>2100,'planner did not find a route around the long wall')
 local cached=e.detour
 g.time=.4;Nav.waypoint(g,e,2200,0)
 check(e.detour==cached,'planner discarded a committed detour before following it')
 reached,boost,elapsed,hits=run(g,{e},140,{{2200,0}})
 -- The slow freighter may brush the far end of this artificial wall; it
 -- must commit to the detour and arrive, not scrape along the whole face.
 check(reached[1] and hits<120,'hauler failed to follow the long-wall detour safely')
 g.world:destroy()
 -- Opposing slow turn-mode ships must consistently pass, not balance pushes.
 g=scene()
 local a=ship(g,-2200,0,0,2200,0);local b=ship(g,2200,0,math.pi,-2200,0)
 reached,boost,elapsed,hits=run(g,{a,b},120,{{2200,0},{-2200,0}})
 check(reached[1] and reached[2],'opposing haulers formed a permanent clump')
 check(hits==0,'opposing haulers collided while passing')
 g.world:destroy()
 -- Four converging haulers must all make progress through the crossing.
 g=scene()
 local group={ship(g,-2500,0,0,2500,0),ship(g,2500,0,math.pi,-2500,0),
  ship(g,0,-2500,math.pi/2,0,2500),ship(g,0,2500,-math.pi/2,0,-2500)}
 reached,boost,elapsed,hits=run(g,group,160,{{2500,0},{-2500,0},{0,2500},{0,-2500}})
 check(reached[1] and reached[2] and reached[3] and reached[4],'crossing haulers remained in a clump')
 check(hits==0,'crossing haulers collided while avoiding the clump')
 g.world:destroy()
 -- Boost is off when pointing away, braking, or approaching a docking stop.
 g=scene();e=ship(g,0,0,math.pi,10000,0)
 AI.think(g,e,1/120)
 check(not e.intent.boost,'hauler boosted before turning to its route')
 e.body:setAngle(0);e.navigation=nil
 AI.think(g,e,1/120)
 check(e.intent.boost,'aligned hauler did not boost along a clear route')
 e.route[1].body:setPosition(500,0);e.navigation=nil;g.time=g.time+1
 AI.think(g,e,1/120)
 check(not e.intent.boost,'hauler boosted near its destination')
 wall(g,300,0,100,1000);e.route[1].body:setPosition(10000,0);e.navigation=nil;g.time=g.time+1
 AI.think(g,e,1/120)
 check(not e.intent.boost,'hauler boosted into nearby geometry')
 g.world:destroy()
 -- A terrain chain's multiple broad-phase proxies represent ONE fixture.
 -- Count actual clearance sweeps so duplicate expansion cannot return.
 g=scene();e=ship(g,0,0,0,8000,0)
 local points={}
 for i=0,95 do
  local a=i/96*math.pi*2
  points[#points+1]=math.cos(a)*800;points[#points+1]=1000+math.sin(a)*800
 end
 local body=love.physics.newBody(g.world,0,0,'static')
 local fixture=love.physics.newFixture(body,love.physics.newChainShape(true,points))
 fixture:setUserData({kind='planet',body=body})
 local Sweep=require('src.collision_prediction');local sweep=Sweep.sweepCircle;local sweeps=0
 Sweep.sweepCircle=function(...)sweeps=sweeps+1;return sweep(...)end
 local ux,uy,scale=Nav.steer(g,e,1,0,650,0,0,{brake=Nav.brakeAccel(e)})
 Sweep.sweepCircle=sweep
 check(sweeps>0 and sweeps<=96*6,'terrain chain was expanded repeatedly for its broad-phase child proxies: '..sweeps)
 check(ux>.99 and math.abs(uy)<.01 and scale==1,'deduplicating terrain altered the clear course')
 g.world:destroy()
 print(('LOCAL NAVIGATION TEST PASSED (%d checks)'):format(checks))
end
