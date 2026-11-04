return function(game)
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function near(a,b)return math.abs(a-b)<.01 end
 game.autosaveOff=true
 game:loadField('earth')
 local st=game:locationEntity('station:007')
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
 st=game:locationEntity('station:007')
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
 print(('BERTH TEST PASSED (%d checks)'):format(checks))
end
