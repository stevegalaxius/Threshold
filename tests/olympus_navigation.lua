return function(game)
 local A,L,G,Fields=require('src.alife'),require('src.locations'),require('src.travelgraph'),require('src.fields')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true
 local graph=G.build('jupiter')
 local city='station:013'
 check(#Fields.jupiter.buoyIds==2,'Jupiter needs two orbital trade buoys')
 for _,clock in ipairs({0,500,2000}) do
  for _,place in ipairs(L.list('jupiter')) do
   if place.kind=='driver' or place.kind=='moon_gate' then
    for _,pair in ipairs({{place.id,city},{city,place.id}}) do
     local route=assert(G.route(graph,pair[1],pair[2],clock))
     check(#route.legs>=2,'Olympus approach bypassed the orbital corridor')
     local adjacent=pair[1]==city and route.legs[1].edge.to or route.legs[#route.legs].edge.from
     check(L.get(adjacent).kind=='buoy','city approach did not use a buoy')
    end
   end
  end
 end
 local legacy={id='legacy',state='travel',area='jupiter',home='io',speed=600,spread=0,
  route={'jupiter/to_io',city},index=2,depart=0,arrive=200}
 local prior=game.universe.npcs
 game.universe.npcs={legacy=legacy}
 local oldX,oldY=A.point(legacy,game.universe.clock)
 A.repairApproachRoutes(game)
 local newX,newY=A.point(legacy,game.universe.clock)
 check(math.abs(oldX-newX)+math.abs(oldY-newY)<.01,'repair moved an existing visitor')
 check(L.get(legacy.route[legacy.index]).kind=='buoy','saved visitor still bypasses orbital approach')
 local size=#legacy.route;A.repairApproachRoutes(game)
 check(#legacy.route==size,'repair inserted duplicate buoys')
 game.universe.npcs=prior
 game:loadField('jupiter')
 for _,id in ipairs(Fields.jupiter.buoyIds) do
  local e=assert(game:locationEntity(id),'missing physical buoy')
  local x,y=L.position(id,game.universe.clock)
  check(math.abs(e.body:getX()-x)+math.abs(e.body:getY()-y)<.01,'buoy differs from offline position')
  local gx,gy=game:surfacePullAt(x,y)
  check(gx==0 and gy==0,'buoy is inside the gravity band')
 end
 game:captureALife(true)
 local id,r
 for key,record in pairs(game.universe.npcs) do
  if record.home=='io' and record.onRoundTrip then id,r=key,record;break end
 end
 assert(r,'missing Io visitor')
 game.universe.npcs={[id]=r}
 for i=#game.entities,1,-1 do
  local e=game.entities[i]
  if e~=game.player and (e.kind=='ship' or e.kind=='asteroid' or e.kind=='container' or e.kind=='husk') then game:remove(e) end
 end
 game.sleepers={}
 game.updateMoonGates=function(self) self:placeMoonGates() end
 r.route=assert(A.roundTrip('io','jupiter',game.universe.clock));r.tripRoute=r.route
 local gate='jupiter/to_io'
 for i,node in ipairs(r.route) do if node==gate then r.index=i+1;break end end
 r.area='jupiter';r.state='travel';r.pose=nil;r.offset=nil;r.docking=nil
 r.depart=game.universe.clock
 local leg={from=gate,to=r.route[r.index]}
 r.arrive=r.depart+G.length(graph,leg,r.depart)/r.speed
 local x,y=A.point(r,r.depart)
 game.player.body:setPosition(x+4000,y);game:updateALife(true)
 local e=assert(game.alifeOnline[id])
 local docked=false
 for i=1,72000 do
  x,y=e.body:getPosition()
  game.player.body:setPosition(x+4000,y);game.player.body:setLinearVelocity(0,0)
  game:step(1/120)
  if e.dead then error('Olympus visitor died on approach') end
  if e.dockState and e.dockState.done then docked=true;break end
 end
 check(docked,'visitor did not reach Olympus docking control within 600 seconds')
 game:undockShip(e)
 check(e.dockExit~=nil,'city visitor did not receive supported runway departure')
 for i=1,120 do game:step(1/120) end
 A.capture(game,e,false)
 check(r.cityExit and r.cityExit.t>0,'runway support was not captured for save/load')
 local saved=require('src.persistence').copy(r.cityExit)
 game:remove(e,true)
 e=A.wake(game,r)
 check(e.dockExit and e.dockExit.station.locationId==saved.station and e.dockExit.t==saved.t,
  'runway support was lost when restoring the visitor')
 local departureIndex=e.routeIndex
 local escaped=false
 for i=1,72000 do
  x,y=e.body:getPosition()
  game.player.body:setPosition(x+4000,y);game.player.body:setLinearVelocity(0,0)
  game:step(1/120)
  if e.dead then error('Olympus visitor died leaving the city') end
  if e.routeIndex~=departureIndex then escaped=true;break end
 end
 check(escaped,'visitor did not climb out to the orbital buoy within 600 seconds')
 x,y=e.body:getPosition()
 check(math.sqrt(x*x+y*y)>Fields.jupiter.planetR+require('src.tuning').surfacePullRange,'departing visitor remained in the gravity band')
 print(('OLYMPUS NAVIGATION TEST PASSED (%d checks)'):format(checks))
end
