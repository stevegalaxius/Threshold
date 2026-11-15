-- Satellites: owned, persistent props in a planet's orbit (src/satellites.lua).
-- Checks a planet gets its seeded set, that only the bus collides, that they
-- are saved with the area and come back with the same ids, that quest levers
-- persist, and that a destroyed one stays gone.
return function(game)
 local Sat,data=require('src.satellites'),require('src.data')
 local Game=require('src.game')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local u=game.universe
 for _,id in ipairs({'sat_passive','sat_fuel_buoy','sat_vendor'}) do check(data.wrecks[id] and data.wrecks[id].kind=='satellite','design '..id..' loads as a satellite') end
 -- the Shipyard round-trips a satellite: its own kind, panels stay sensors
 local Export=require('src.editor.export')
 local src=Export.source(Export.fromWreck('sat_passive'))
 check(src:find('\nsatellite {',1,true) and src:find('sensor = true',1,true),'the Shipyard saves satellites as satellite { } with sensor panels')
 game:loadField('earth')
 local function sats()
  local by,n={},0
  for _,e in ipairs(game.entities) do if e.sat and not e.removed and not e.dead then by[e.sat]=e;n=n+1 end end
  return by,n
 end
 local by,n=sats()
 check(n>=12 and n<=20,'earth has 12-20 satellites: '..n)
 check(#Sat.inField(u,'earth')==n,'one record per satellite')
 local kinds={}
 for _,r in ipairs(Sat.inField(u,'earth')) do kinds[r.kind]=(kinds[r.kind] or 0)+1 end
 check((kinds.passive or 0)>(kinds.fuel or 0)+(kinds.vendor or 0),'mostly passive')
 -- only the bus collides: every fixture sits inside the bus box
 local e=by['earth_sat_01']
 check(e,'stable ids')
 local x,y=e.body:getPosition()
 local reach=0
 for _,f in ipairs(e.body:getFixtures()) do if not f:isSensor() then
  local pts={f:getShape():getPoints()}
  for k=1,#pts,2 do local wx,wy=e.body:getWorldPoint(pts[k],pts[k+1]);reach=math.max(reach,math.sqrt((wx-x)^2+(wy-y)^2)) end
 end end
 check(reach<180,'panels and truss do not collide (fixture reach '..math.floor(reach)..')')
 check(e.body:getMass()>200,'the bus is heavy: '..e.body:getMass())
 -- levers
 local r=Sat.get(u,'earth_sat_01')
 local L=Sat.levers(r)
 check(L.dock==Sat.kinds[r.kind].dock,'kind sets the defaults')
 check(Sat.allow(u,'earth_sat_01',{dock='player',actions={'quest'}}),'a quest can open a satellite')
 check(Sat.levers(r).dock=='player' and Sat.levers(r).actions[1]=='quest','and the override applies')
 -- move one, leave, come back: same place, same ids
 e.body:setPosition(x+500,y)
 local victim=by['earth_sat_02']
 game:remove(victim)
 game:loadField('mars')
 local _,mn=sats()
 check(mn>=12,'mars has its own: '..mn)
 game:loadField('earth')
 local by2,n2=sats()
 check(by2['earth_sat_01'],'satellite came back')
 local x2=by2['earth_sat_01'].body:getPosition()
 check(math.abs(x2-x)>100,'it stayed where it was pushed, give or take orbit')
 check(not by2['earth_sat_02'] and Sat.get(u,'earth_sat_02').lost,'a destroyed satellite stays gone')
 check(n2==n-1,'no duplicates on return: '..n2)
 check(Sat.levers(Sat.get(u,'earth_sat_01')).dock=='player','quest override survives')
 Sat.revoke(u,'earth_sat_01')
 check(Sat.levers(Sat.get(u,'earth_sat_01')).dock==Sat.kinds[r.kind].dock,'revoke restores the kind')
 -- a working satellite takes hits as a whole; knocked out, it's a wreck
 local target=by2['earth_sat_03'] or select(2,next(by2))
 local parts=#target.pieces
 game:damage(target,50,nil,'gun')
 check(#target.pieces==parts and target.sat and not target.dead,'a working satellite loses no parts to fire')
 local tid=target.sat
 game:damage(target,1e6,nil,'gun')
 check(not target.sat and not target.dead and Sat.get(u,tid).lost,'knocked out, it becomes a plain wreck and is marked lost')
 local piece
 for _,pc in ipairs(target.pieces) do if pc.part.name=='panel' then piece=pc break end end
 local before=#game.entities
 game:breakOff(target,piece)
 check(#game.entities==before+1,'and then breaks apart like any wreck')
 -- docking: a closed satellite refuses; a fuel buoy beams you to a berth
 -- and docks you with only its services
 game:loadField('earth')
 local by3=sats()
 local closed,buoy
 for id,o in pairs(by3) do
  local rr=Sat.get(u,id)
  if rr.kind=='passive' and not rr.dock then closed=closed or o end
  if rr.kind=='fuel' then buoy=buoy or o end
 end
 check(closed and buoy,'earth has a closed passive sat and a fuel buoy')
 local p=game.player
 local bx,by=buoy.body:getPosition()
 p.body:setPosition(bx+300,by+300);p.body:setLinearVelocity(buoy.body:getLinearVelocity())
 check(not Sat.request(game,closed) and not p.dockState,'a closed satellite refuses')
 check(Sat.request(game,buoy) and p.dockState and p.dockState.phase=='tractor','a fuel buoy takes you in on the tractor beam')
 for _=1,600 do game:step(1/60);if game.state=='docked' then break end end
 check(game.state=='docked' and p.dockState.done,'and docks you at its berth')
 local st=p.dockState.station
 local svc=Game.stationServices(st)
 local ks={} for k in pairs(svc) do ks[#ks+1]=k end
 check(svc.market and not svc.shipyard and not svc.hangar,'with only its own services: '..table.concat(ks,','))
 local shops=Game.marketShops(st)
 check(#shops==1 and shops[1].sells[1][1]=='deuterium_canister','and a bare fuel shelf')
 for _=1,30 do game:step(1/60) end
 local px,py=p.body:getPosition();local nx,ny=buoy.body:getPosition()
 check(math.sqrt((px-nx)^2+(py-ny)^2)<buoy.radius,'it holds you at the berth')
 game:undock()
 check(game.state=='playing' and not p.dockState and not buoy.satHeld,'launch leaves the berth')
 -- a quest opens a closed one
 Sat.allow(u,closed.sat,{dock='player',actions={'vend'}})
 check(Sat.request(game,closed),'a quest-opened satellite lets you in')
 p.dockState=nil;closed.satHeld=nil
 -- satellite records go into the save file
 local Save=require('src.save')
 local state=assert(Save.decode(Save.encode(game:saveState())))
 check(state.satellites and state.satellites[closed.sat] and state.satellites[closed.sat].dock=='player','satellite records are saved')
 print(('satellites: %d checks passed'):format(checks))
end
