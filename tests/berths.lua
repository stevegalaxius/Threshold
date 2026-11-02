return function(game)
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function near(a,b)return math.abs(a-b)<.01 end
 game.autosaveOff=true
 game:loadField('earth')
 local st=game:locationEntity('earth/orbital_one')
 local p=game.player
 local d=st.docks[2] or st.dock
 st.body:setAngle(.7)
 local wx,wy=game.dockWorld(st,1,d.x2+p.halfLength+40,0,d)
 local x,y=st.body:getLocalPoint(wx,wy)
 st.def.berths={
  {x=x-4000,y=y,heading=10,size=2000},
  {x=x+20,y=y+400,heading=70,size=2000},
  {x=x,y=y+20,heading=120,size=2000},
  {x=x,y=y,heading=0,size=0},
 }
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
 atBerth(2)
 -- Retain the same exterior placement across a save/load as well.
 local Save=require('src.save')
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 check(saved.player.at.berth==2 and saved.player.at.dockIndex~=nil,'save dropped berth or dock')
 game:loadState(saved)
 st=game:locationEntity('earth/orbital_one')
 atBerth(2)
 -- A replacement must still fit: use the nearest available larger berth,
 -- and the interior if every exterior berth is unsuitable.
 st.def.berths[2].size=0;st.def.berths[3].size=0
 check(game:flyFromHangar(index),'second switch failed')
 atBerth(1)
 st.def.berths[1].size=0
 check(game:flyFromHangar(index),'interior fallback switch failed')
 check(not game.player.dockState.berth,'oversized replacement was parked on an unsuitable berth')
 local px,py=game.player.body:getPosition()
 game:updateDockedShip(game.player,1/120)
 local xx,yy=game.player.body:getPosition()
 check(near(px,xx) and near(py,yy),'interior placement jumped on the next frame')
 print(('BERTH TEST PASSED (%d checks)'):format(checks))
end
