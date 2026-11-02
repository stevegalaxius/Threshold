return function(game)
 local Fields=require('src.fields')
 local Render=require('src.render')
 local Save=require('src.save')
 local T=require('src.tuning')
 local checks=0
 local function check(ok,msg) assert(ok,msg); checks=checks+1 end
 game.autosaveOff=true; T.dev.god=true
 game:loadField('earth')
 game.player.body:setPosition(game.arenaRadius-100,0)
 game.player.body:setLinearVelocity(800,0)
 game:launchTrip('luna',{bearing=0,length=Fields.moons.luna.gap})
 local origin=game.trip.originScene
 local retained=origin.world
 local station=assert(origin:locationEntity(Fields.earth.stationIds[1]))
 local stationBody=station.body
 local originalX,originalY=stationBody:getPosition()
 local originalAngle=stationBody:getAngle()
 local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
 local x,y=game:fromLane(0,-T.laneWidth/4)
 local function render()
  love.graphics.setCanvas(canvas); Render.world(game); love.graphics.setCanvas()
  love.graphics.flushBatch()
  love.graphics.present()
 end
 local function rss()
  local file=io.open('/proc/self/status','r')
  if not file then return 0 end
  local data=file:read('*a'); file:close()
  return tonumber(data:match('VmRSS:%s+(%d+)')) or 0
 end
 local initial=rss()
 local idleSeconds=tonumber(os.getenv('THRESHOLD_IDLE_SECONDS')) or 600
 for i=1,idleSeconds*120 do
  game.player.body:setPosition(x,y); game.player.body:setLinearVelocity(0,0)
  game:setPlayerIntent(require('src.ship').emptyIntent())
  game:step(1/120)
  if i%2==0 then game:frame(1/60,x+1000,y) end
  if i%12==0 then render() end
  if i%(60*120)==0 then
   collectgarbage('collect')
   print(('idle %ds: RSS %.0f MiB, bodies %d'):format(i/120,rss()/1024,game.world:getBodyCount()))
  end
 end
 check(game.lane and game.fieldId=='lane','idle changed player region')
 check(station.body==stationBody,'preview retained a rendering proxy as a physics body')
 local fx,fy=stationBody:getPosition()
 check(fx==originalX and fy==originalY and stationBody:getAngle()==originalAngle,
  'preview rendering moved a paused physics body')
 local restore=require('src.preview').begin(origin)
 local shownX,shownY=station.body:getPosition()
 local expectedX,expectedY=require('src.locations').position(station.locationId,game.universe.clock)
 check(math.abs(shownX-expectedX)+math.abs(shownY-expectedY)<.001,'preview stopped following the location clock')
 restore()
 -- Cache both the onward world and the retained origin before returning.
 game:prepareArrival(false); render()
 game:prepareArrival(true); render()
 local sx,sy=game:fromLane(-game.lane.half-300,-T.laneWidth/4)
 game.player.body:setPosition(sx,sy)
 local heading=game:laneHeading(-game.lane.half)
 game.player.body:setLinearVelocity(-math.cos(heading)*800,-math.sin(heading)*800)
 game:updateLane(1/120)
 check(game.pendingArrive=='back','idle highway cannot turn back')
 game:step(1/120)

 check(game.fieldId=='earth' and game.world==retained,'return did not adopt retained Earth')
 for i=1,600 do
  game:step(1/120)
  if i%2==0 then game:frame(1/60) end
  if i%12==0 then render() end
 end
 check(not game.world:isDestroyed(),'adopted Earth world destroyed')
 check(Save.decode(Save.encode(game:saveState()))~=nil,'idle return cannot save')
 print(('HIGHWAY IDLE TEST PASSED (%d checks; RSS %.0f -> %.0f MiB)'):format(checks,initial/1024,rss()/1024))
end
