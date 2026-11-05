return function(game)
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function near(a,b)return math.abs(a-b)<.01 end
 game.autosaveOff=true
 game:loadField('earth')
 local st=game:locationEntity('station:earth_1')
 local p=game.player
 st.def.hangar={w=1,h=1}
 -- A real fitted freighter can use a pad smaller than its hull, while
 -- the marker's authored dimensions remain intact.
 local Ship,T=require('src.ship'),require('src.tuning')
 local freighter=Ship.new(game,{hull='ferrous_freighter',x=0,y=0,angle=0})
 local original,entities=st.def.berths,game.entities
 local pad=freighter.halfLength/2
 st.def.berths={{x=st.radius+freighter.halfLength+200,y=0,heading=0,size=pad}};game.entities={}
 check(freighter.halfLength>pad and game:freeBerth(st,freighter)==1,'freighter still rejected by the original pad size limit')
 check(st.def.berths[1].size==pad,'larger berth capacity changed the authored marker size')
 st.def.berths[1].size=game.shipDimensions(freighter.hull.id)/(2*T.berthShipScale)-1
 check(not game:freeBerth(st,freighter),'ship exceeded the enlarged berth capacity')
 st.def.berths,game.entities=original,entities
 freighter.body:destroy()
 local d=st.docks[2] or st.dock
 st.body:setAngle(.7)
 local wx,wy=game.dockWorld(st,1,d.x2+p.halfLength+40,0,d)
 local x,y=st.body:getLocalPoint(wx,wy)
 local outward=math.deg(d.a or 0)
 local c,s=math.cos(d.a or 0),math.sin(d.a or 0)
 st.def.berths={
  {x=x+c*4000,y=y+s*4000,heading=outward,size=2000},
  {x=x+c*300-s*400,y=y+s*300+c*400,heading=outward,size=2000},
  {x=x+c*300-s*20,y=y+s*300+c*20,heading=outward,size=2000},
  {x=x,y=y,heading=0,size=0},
 }
 game:stationRecord(st).moorings=nil;st.parkingClearance=nil
 p.body:setPosition(wx,wy)
 local occupied={dockState={station=st,berth=3}}
 table.insert(game.entities,occupied)
 check(game:freeBerth(st,p)==2,'did not choose nearest free berth that fits')
 table.remove(game.entities)
 check(game:freeBerth(st,p)==3,'did not choose closer berth when available')
 -- Check the real tractor-to-taxi handoff uses the nearest eligible berth.
 table.insert(game.entities,occupied)
 game:beginDocking(p,st,1,d)
 p.body:setLinearVelocity(0,0)
 game:updateDockedShip(p,1/120)
 check(p.dockState.phase=='taxi' and p.dockState.berth==2,'physical docking chose first berth')
 table.remove(game.entities)
 game:updateDockedShip(p,10)
 check(p.dockState.done,'taxi did not finish docking')
 local function atBerth(index)
  local ship=game.player
  local b=st.def.berths[index]
  local xx,yy=st.body:getWorldPoint(b.x,b.y)
  local px,py=ship.body:getPosition()
  check(ship.dockState.berth==index and near(px,xx) and near(py,yy),'ship moved away from berth')
  check(near((ship.body:getAngle()-st.body:getAngle()-math.rad(b.heading)+math.pi)%(2*math.pi)-math.pi,0),'berth heading was reset')
  check(not ship.body:isActive(),'docked ship became active')
 end
 atBerth(2)
 local rec=assert(game:addToHangar(st,'halcyon_wisp'))
 local index
 for i,r in ipairs(game:hangar(st)) do if r==rec then index=i end end
 check(game:flyFromHangar(index),'ship switch failed')
 check(game.player~=p and p.removed,'ship switch did not replace player')
 check(game.player.dockState.station==st and game.player.dockState.dock==d,'ship switch lost dock entrance')
 atBerth(1)
 -- Retain the same exterior placement across a save/load as well.
 local Save=require('src.save')
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 check(saved.player.at.berth==1 and saved.player.at.dockIndex~=nil,'save dropped berth or dock')
 game:loadState(saved)
 st=game:locationEntity('station:earth_1')
 atBerth(1)
 -- Re-enable interior storage and remove exterior capacity. A small ship
 -- can still use the interior rather than an invalid reserved berth.
 st.def.hangar=nil
 for _,b in ipairs(st.def.berths) do b.size=0 end
 check(game:flyFromHangar(index),'small ship could not move to free interior storage')
 check(game.player.bay and not game.player.dockState.berth,'small ship ignored interior allocation')
 local px,py=game.player.body:getPosition()
 game:updateDockedShip(game.player,1/120)
 local xx,yy=game.player.body:getPosition()
 check(near(px,xx) and near(py,yy),'interior placement jumped on the next frame')
 -- Oversized vessels with no usable pad must never be pulled through
 -- a corridor they cannot fit. Exercise the real tractor handoff.
 local big=game.player
 local dock=st.dock
 local oldWidth=dock.hw;dock.hw=1
 st.def.hangar={w=1,h=1}
 for _,b in ipairs(st.def.berths) do b.size=0 end
 -- Even stale saved overflow slots must not become invisible parking.
 local record=game:stationRecord(st)
 record.moorings[#st.def.berths+1]={x=100000,y=0,heading=0,length=600,width=240}
 check(#game:stationMoorings(st)==#st.def.berths,'stale overflow parking survived')
 check(not game:fitsDock(big,dock),'narrow dock incorrectly accepts a wide hull')
 big.dockState=nil;big.bay=nil;big.parkingMooring=nil;big.body:setActive(true)
 local ax,ay=game.dockWorld(st,1,dock.x2+big.halfLength+40,0,dock)
 big.body:setPosition(ax,ay);big.body:setLinearVelocity(st.body:getLinearVelocityFromWorldPoint(ax,ay))
 game:beginDocking(big,st,1,dock)
 game:updateDockedShip(big,1/120)
 local bx,by=big.body:getPosition()
 check(not big.dockState and big.body:isActive(),'ship with no suitable berth was parked at an invented position')
 check(near(ax,bx) and near(ay,by),'failed docking launched the ship away')
 -- Re-enable one real berth and exercise the same physical handoff.
 st.def.berths[2].size=2000
 game:beginDocking(big,st,1,dock);big.body:setLinearVelocity(0,0)
 game:updateDockedShip(big,1/120)
 check(big.dockState and big.dockState.phase=='taxi' and big.dockState.berth==2,'ship did not taxi to the available placed berth')
 game:updateDockedShip(big,10);atBerth(2)
 game:undockShip(big)
 check(not big.dockState and big.body:isActive(),'berthed ship could not undock')
 dock.hw=oldWidth
 -- All arriving ships use grid capacity, including physical and restored NPCs.
 game:captureALife(true)
 local w,h=game.hangarFootprint('halcyon_wisp')
 st.def.hangar={w=w,h=h};game:stationRecord(st).hangar={}
 for i,berth in ipairs(st.def.berths) do berth.size=i<=3 and 2000 or 0 end
 local function npc(hull)
  local e=Ship.new(game,{hull=hull,team=3})
  table.insert(game.entities,e);return e
 end
 local small=npc('halcyon_wisp')
 check(game:dockInstantly(small,st) and small.bay and not small.dockState.berth,
  'small NPC ignored a free hangar-grid slot')
 local second=npc('halcyon_wisp')
 check(game:dockInstantly(second,st) and second.dockState.berth and not second.bay,
  'second NPC reused occupied hangar cells')
 game:undockShip(small)
 check(not small.bay and game:hangarFit(st,'halcyon_wisp'),'NPC departure did not release its grid reservation')
 check(game:dockInstantly(game.player,st) and game.player.bay and not game.player.dockState.berth,
  'player did not follow the same grid-fit rule')
 for _,door in ipairs(st.docks or {st.dock}) do door.hw=2000 end
 local large=npc('ferrous_freighter')
 check(game:fitsDock(large,st.dock) and not game:hangarFit(st,large.hull.id),
  'large-ship fixture must fit the door but exceed the grid')
 check(game:dockInstantly(large,st) and large.dockState.berth and not large.bay,
  'door width bypassed the large ship grid limit')
 game:undockShip(game.player)
 local arriving=npc('halcyon_wisp')
 local dx,dy=game.dockWorld(st,1,st.dock.x2+arriving.halfLength+40,0,st.dock)
 arriving.body:setPosition(dx,dy);arriving.body:setLinearVelocity(0,0)
 game:beginDocking(arriving,st,1,st.dock);game:updateDockedShip(arriving,1/120)
 check(arriving.dockState.phase=='pull' and arriving.bay and not arriving.dockState.berth,
  'physical NPC arrival preferred an exterior berth over a free grid slot')
 game:updateDockedShip(arriving,10)
 local full=npc('halcyon_wisp')
 check(game:dockInstantly(full,st) and full.dockState.berth and not full.bay,
  'full hangar did not fall back to an exterior slot')
 local refused=npc('halcyon_wisp')
 check(not game:dockInstantly(refused,st) and not refused.dockState and not refused.bay,
  'full station admitted a ship without a real parking slot')
 -- Restoring an NPC must not overwrite an exterior fallback with its old
 -- interior pose when the grid is now occupied.
 game:undockShip(full)
 local record
 for _,r in pairs(game.universe.npcs) do if r.role=='trader' and r.home=='earth' then record=r;break end end
 assert(record)
 local A=require('src.alife')
 record.state='docked';record.area='earth';record.route={st.locationId,st.locationId};record.index=1
 record.untilTime=game.universe.clock+60;record.taskWorker=nil;record.task=nil
 record.encounter=nil;record.piracy=nil;record.worldRecovery=nil;record.waitingForHome=nil;record.driverState=nil
 record.ship.hull='halcyon_wisp';record.ship.loadout=require('src.data').hulls.halcyon_wisp.loadout
 record.ship.hold=nil;record.ship.cargo={};record.ship.fuelInitialized=true;record.ship.fuelCharge=100;record.power=60
 local ix,iy=game.dockWorld(st,1,(st.dock.x1+st.dock.x2)/2,0,st.dock)
 record.pose={x=ix,y=iy,a=0,vx=0,vy=0,w=0,clock=game.universe.clock}
 record.docking={phase='done',done=true,t=0,stay=60,side=1,dockIndex=1}
 local restored=A.wake(game,record)
 check(restored.dockState and restored.dockState.berth and not restored.bay,
  'saved NPC interior state overwrote its valid exterior fallback')
 local berth=st.def.berths[restored.dockState.berth]
 local ex,ey=st.body:getWorldPoint(berth.x,berth.y)
 local rx,ry=restored.body:getPosition()
 check(near(ex,rx) and near(ey,ry),'restored NPC kept its old interior pose on an exterior berth')
 -- A moored ship carrying a stale bay must not take invisible interior cells.
 local list=game:hangar(st);local saved={}
 for i,r in ipairs(list) do saved[i]=r end
 for i=#list,1,-1 do list[i]=nil end
 local ghost={hull=game.player.hull.id,loadout=game.player.loadout,bay={x=0,y=0,rot=false},mooring=1}
 list[1]=ghost
 local cells=0;for _,c in pairs(game:hangarGrid(st).cells) do if c.owner==ghost then cells=cells+1 end end
 check(cells==0,'moored ship blocked interior hangar cells')
 for i=#list,1,-1 do list[i]=nil end
 for i,r in ipairs(saved) do list[i]=r end
 print(('BERTH TEST PASSED (%d checks)'):format(checks))
end
