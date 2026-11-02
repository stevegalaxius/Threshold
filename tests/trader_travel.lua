return function(game)
 local A,G,Fields,Save=require('src.alife'),require('src.travelgraph'),require('src.fields'),require('src.save')
 local checkCount=0
 local function check(ok,msg) assert(ok,msg); checkCount=checkCount+1 end
 local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
 local function near(a,b) return math.abs(a-b)<.02 end
 game.autosaveOff=true
 local expected=0
 for _,area in ipairs(Fields.list) do expected=expected+(Fields[area].alifeTraders or 0) end
 check(count(game.universe.npcs)==expected,'populations do not exist before visiting their regions')
 local homes,travellers={},0
 for _,r in pairs(game.universe.npcs) do
  homes[r.home]=(homes[r.home] or 0)+1
  if r.onRoundTrip then
   travellers=travellers+1
   for i,to in ipairs(r.route) do
    check(require('src.locations').get(to).kind~='driver','moon itinerary detoured through a mass driver')
    local from=r.route[(i-2)%#r.route+1]
    local a,b=require('src.locations').get(from),require('src.locations').get(to)
    if a.area~=b.area then check(G.transit(from,to)~=nil,'invented inter-region connection')
    else
     local found=false
     for _,edge in ipairs(Fields[a.area].travelLinks) do
      if edge[1]==from and edge[2]==to or edge[1]==to and edge[2]==from then found=true end
     end
     check(found,'itinerary invented a local connection')
    end
   end
  end
 end
 check(travellers>0 and travellers<expected,'missing mix of local and moon traders')
 for _,area in ipairs(Fields.list) do
  check((homes[area] or 0)==(Fields[area].alifeTraders or 0),'wrong population in '..area)
  game:loadField(area)
  for _,e in ipairs(game.entities) do
   if e.kind=='ship' and e.def and e.def.ai.style=='trader' then check(e.alifeId~=nil,'anonymous trader in '..area) end
  end
  check(count(game.universe.npcs)==expected,'region load replenished its population')
 end
 -- Saved itineraries from the driver-detour build are repaired in place.
 local original
 for _,record in pairs(game.universe.npcs) do
  if record.home=='earth' and record.onRoundTrip then original=record; break end
 end
 local probe=require('src.persistence').copy(original)
 local oldRoute={}
 for i,stop in ipairs(probe.route) do
  oldRoute[#oldRoute+1]=stop
  if i==1 or i==#probe.route then oldRoute[#oldRoute+1]=Fields.earth.driverId end
 end
 probe.route,probe.tripRoute=oldRoute,require('src.persistence').copy(oldRoute)
 probe.state,probe.area,probe.index='travel','earth',2
 probe.depart,probe.arrive=game.universe.clock-5,game.universe.clock+10
 probe.offset,probe.pose=nil,nil
 local px0,py0=A.point(probe,game.universe.clock)
 game.universe.npcs['repair-probe']=probe
 A.repairMoonRoutes(game)
 local px1,py1=A.point(probe,game.universe.clock)
 check(near(px0,px1) and near(py0,py1),'saved route repair teleported the trader')
 for _,stop in ipairs(probe.route) do check(require('src.locations').get(stop).kind~='driver','saved route still contains driver detour') end
 probe.state,probe.area,probe.index='transit',nil,3
 probe.transit={from='earth',to='luna',moon='luna',length=Fields.moons.luna.gap}
 probe.depart,probe.arrive=game.universe.clock-3,game.universe.clock+7
 A.repairMoonRoutes(game)
 check(probe.transit.speed==probe.speed,'legacy transit retained fixed highway speed')
 check(near((game.universe.clock-probe.depart)/(probe.arrive-probe.depart),.3),'legacy speed repair changed journey progress')
 game.universe.npcs['repair-probe']=nil
 -- Follow one actual Earth trader all the way to Luna and home.
 local id,r
 for candidate,record in pairs(game.universe.npcs) do
  if record.home=='earth' and record.tripDestination=='luna' then id,r=candidate,record; break end
 end
 check(r~=nil,'no Earth–Luna itinerary')
 r.ship.cargo={scrap=17}; r.ship.armor=r.ship.armor*.6
 local armor=r.ship.armor
 local function advanceUntil(predicate)
  for _=1,30 do
   if predicate() then return end
   game.universe.clock=(r.state=='docked' and r.untilTime or r.arrive)+.01
   A.advance(r,game.universe.clock)
  end
  error('itinerary did not reach expected activity')
 end
 advanceUntil(function() return r.state=='transit' and r.transit.to=='luna' end)
 check(A.point(r,game.universe.clock)==nil,'remote transit has a fabricated map position')
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(saved); r=game.universe.npcs[id]
 check(r.state=='transit' and r.ship.cargo.scrap==17,'transit save/load replaced trader')
 game:loadField('earth')
 game.universe.clock=(r.depart+r.arrive)/2
 game:launchTrip('luna',{bearing=0,length=Fields.moons.luna.gap})
 local p=assert(A.laneSample(game,r,game.universe.clock))
 game.player.body:setPosition(p.x+2000,p.y); game:updateALife(true)
 local e=assert(game.alifeOnline[id],'same-path trader absent from highway')
 check(e.alifeId==id and e.alifeLane and e.cruiseDir==1,'highway ship is not the persistent traveller')
 check(e.cargo.scrap==17 and near(e.armor,armor),'highway materialization lost ship state')
 local instances=0
 for _,entity in ipairs(game.entities) do if entity.alifeId==id then instances=instances+1 end end
 check(instances==1,'highway encounter duplicated trader')
 -- Direction and route matching are based on endpoints, not freighter spawning.
 local from,to=game.trip.from,game.trip.to
 game.trip.from,game.trip.to='mars','phobos'
 check(not A.laneSample(game,r,game.universe.clock),'trader appeared on unrelated highway')
 game.trip.from,game.trip.to=to,from
 check(A.laneDirection(game,r)==-1,'oncoming persistent trader not recognized')
 game.trip.from,game.trip.to=from,to
 e.cargo.scrap=18; e.armor=e.armor*.9; armor=e.armor
 game:step(1/120)
 game.player.body:setPosition(e.body:getX()+30000,e.body:getY()); game:updateALife(true)
 check(not game.alifeOnline[id] and r.state=='transit','highway ship did not fold into its journey')
 check(r.ship.cargo.scrap==18 and near(r.ship.armor,armor),'highway handoff lost damage or cargo')
 game.universe.clock=r.arrive+.01; game:updateALife(true)
 game:arrive(false)
 check(game.fieldId=='luna' and count(game.universe.npcs)==expected,'arrival changed population')
 -- Finish local travel abstractly, then inspect the real ship in its moon dock.
 game:loadField('venus')
 advanceUntil(function() return r.state=='docked' and r.area=='luna' end)
 game:loadField('luna')
 local station=assert(game:locationEntity(r.route[r.index]))
 game.player.body:setPosition(station.body:getPosition()); game:updateALife(true)
 e=assert(game.alifeOnline[id])
 check(e.dockState and e.dockState.station==station,'traveller did not materialize docked at moon')
 game:updateDockedShip(e,(e.dockState.stay or 60)+1)
 check(not e.dockState,'moon docking wait did not lead to departure')
 local gate=e.route[e.routeIndex]
 check(gate.kind=='moon_gate','return itinerary did not lead to existing departure gate')
 e.body:setPosition(gate.body:getPosition())
 local gx,gy=e.body:getPosition(); local radius=math.sqrt(gx*gx+gy*gy)
 local dx,dy=gx/radius,gy/radius
 e.body:setLinearVelocity(dx*600,dy*600)
 game.player.body:setPosition(gx-dx*600,gy-dy*600)
 game.player.body:setLinearVelocity(dx*600,dy*600)
 require('src.ai').think(game,e,1/120)
 check(e.alifeDepart,'existing flight AI did not recognize reaching the gate')
 game:updateALife(true)
 check(game.alifeOnline[id]==e and e.alifeEgress and r.state=='transit' and r.transit.to=='earth','departure must stay visible while starting the same transit record')
 local departingX,departingY=e.body:getPosition()
 game:loadState(assert(Save.decode(Save.encode(game:saveState()))))
 r=game.universe.npcs[id]; e=assert(game.alifeOnline[id],'visible departure lost on reload')
 check(e.alifeEgress and near(e.body:getX(),departingX) and near(e.body:getY(),departingY),'save/load moved a departing ship')
 -- Follow straight after a visible departure: preserve the actual gap and speed,
 -- including the player's ramp before the highway mouth.
 local nx,ny=e.body:getPosition(); local px,py=game.player.body:getPosition()
 local gapX,gapY=nx-px,ny-py
 game:launchTrip('earth',{bearing=math.atan2(py,px),length=Fields.moons.luna.gap})
 local followed=assert(game.alifeOnline[id],'followed trader did not enter the same highway')
 local fx,fy=followed.body:getPosition(); px,py=game.player.body:getPosition()
 check(near(fx-px,gapX) and near(fy-py,gapY),'highway transition jumped the followed trader ahead')
 local vx,vy=followed.body:getLinearVelocity()
 check(near(math.sqrt(vx*vx+vy*vy),600),'highway transition injected a new cruise speed')
 for _=1,30 do game:step(1/120) end
 vx,vy=followed.body:getLinearVelocity()
 check(math.sqrt(vx*vx+vy*vy)<800,'moon highway mouth accelerated traffic artificially')
 local save=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(save); r=game.universe.npcs[id]
 check(r.state=='transit' and r.transit.to=='earth','return transit lost on save/load')
 advanceUntil(function() return r.state=='docked' and r.area=='earth' end)
 game:loadField('earth')
 station=assert(game:locationEntity(r.route[r.index]))
 game.player.body:setPosition(station.body:getPosition()); game:updateALife(true)
 e=assert(game.alifeOnline[id])
 check(e.dockState and e.dockState.station.locationId==Fields.earth.stationIds[1],'same trader did not dock back home')
 check(e.cargo.scrap==18 and near(e.armor,armor),'round trip lost ship state')
 check(count(game.universe.npcs)==expected,'round trip spawned replacement traders')
 print(('TRADER TRAVEL TEST PASSED (%d checks; %d persistent traders, %d moon itineraries)'):format(checkCount,expected,travellers))
end
