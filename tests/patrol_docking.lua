return function(game)
 local S,A,Tasks=require('src.security'),require('src.alife'),require('src.tasks')
 local Fields,T,Save=require('src.fields'),require('src.tuning'),require('src.save')
 local copy=require('src.persistence').copy
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true;game:loadField('earth');game:captureALife(true)
 local u=game.universe;local r
 for _,record in pairs(u.npcs) do if record.role=='patrol' and record.home=='earth' then r=record;break end end
 r=r or assert(require('src.population').spawn(game,'earth','patrol',false))
 local st=game:locationEntity('station:earth_1');local buoy=Fields.earth.buoyIds[1]
 local max=require('src.stats').compute(require('src.data').hulls[r.ship.hull],r.ship.loadout).armor
 local prepare=Tasks.definitions.patrol.prepare
 r.ship.armor=max;r.patrolStationVisits=0
 for i=1,T.patrolDockEvery do
  local task={kind='patrol',target=st.locationId,source=buoy,duration=T.patrolInspect}
  prepare(u,r,task)
  check(not not task.dock==(i==T.patrolDockEvery),'healthy patrol docking cadence wrong')
 end
 r.ship.armor=max*.5;r.patrolStationVisits=0;r.task=nil
 u.tasks.offers={}
 Tasks.post(u,{kind='patrol',source=buoy,target=st.locationId,cooldown=0,duration=T.patrolInspect})
 Tasks.post(u,{kind='patrol',source=st.locationId,target=buoy,cooldown=0,duration=T.patrolInspect})
 r.state='idle';r.area='earth';r.node=buoy;r.route={buoy,buoy};r.index=1;r.untilTime=u.clock;r.encounter=nil
 S.advance(r,u.clock,u,A.start)
 check(r.task.dock and r.task.phase=='repair visit','damaged patrol did not prioritize a repair stop')
 local offline=copy(r);local remote=copy(u);remote.npcs[offline.id]=offline
 S.advance(offline,offline.arrive,remote,A.start)
 check(offline.state=='docked','offline docking duty did not reach berth state')
 local arrival=offline.untilTime-offline.task.duration
 S.advance(offline,arrival+2,remote,A.start)
 check(math.abs(offline.ship.armor-(max*.5+T.npcRepairPerSecond*2))<.01,'offline docking did not repair over elapsed time')
 S.advance(offline,offline.untilTime,remote,A.start)
 check(offline.ship.armor==max and offline.state=='travel','offline patrol did not repair and resume patrol')
 local e=A.wake(game,r)
 check(e.route[#e.route].kind=='station' and e.route[#e.route].dock,'planned dock was still an inspection waypoint')
 local d=st.dock;local x,y=game.dockWorld(st,1,d.x2+e.halfLength+40,0,d)
 e.body:setPosition(x,y);e.body:setLinearVelocity(st.body:getLinearVelocityFromWorldPoint(x,y))
 game:beginDocking(e,st,1,d);game:updateDockedShip(e,1/120);game:updateDockedShip(e,10)
 check(e.dockState.done,'patrol did not complete physical docking')
 local credits=game:credits();local before=e.armor
 u.clock=u.clock+2;game:updateDockedShip(e,2)
 check(math.abs(e.armor-before-T.npcRepairPerSecond*2)<.01,'physical patrol did not repair over time')
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 check(saved.npcs[r.id].repairAt==u.clock,'save lost patrol repair progress')
 local id=r.id;game:loadState(saved);u=game.universe;r=u.npcs[id];e=game.alifeOnline[id] or A.wake(game,r)
 check(e.dockState and e.dockState.done,'load lost the patrol docking stop')
 local hp=e.armor;local services=e.dockState.station.def.services
 e.dockState.station.def.services={};u.clock=u.clock+1;game:updateDockedShip(e,1)
 check(e.armor==hp,'station without repair service healed patrol')
 e.dockState.station.def.services=services
 u.clock=u.clock+100;game:updateDockedShip(e,100)
 check(e.armor==max and not e.dockState and r.state=='travel','repaired patrol did not depart onto its next duty')
 check(game:credits()==credits,'NPC repairs charged player credits')
 -- Passing inspections are placed outside the hull and dock runways.
 st=game:locationEntity('station:earth_1');r.task.dock=false
 r.route={buoy,st.locationId};r.index=2;r.state='travel';A.bindRoute(game,e,r)
 check(e.route[2].kind=='waypoint','non-docking visit became a docking stop')
 local px,py=S.inspectionPoint(game,st,e);local sx,sy=st.body:getPosition()
 check((px-sx)^2+(py-sy)^2>st.radius^2,'inspection point is inside station hull')
 for _,dock in ipairs(st.docks or {st.dock}) do
  local lx,ly=game.dockLocal(st,1,px,py,dock)
  check(math.abs(ly)>=(dock.capture or dock.hw)+e.halfLength or lx<dock.x2,'inspection point blocks a runway')
 end
 print(('PATROL DOCKING TEST PASSED (%d checks)'):format(checks))
end
