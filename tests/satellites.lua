-- Satellites: owned, persistent props in a planet's orbit (src/satellites.lua).
-- Checks a planet gets its seeded set, that only the bus collides, that they
-- are saved with the area and come back with the same ids, that quest levers
-- persist, and that a destroyed one stays gone.
return function(game)
 local Sat,data=require('src.satellites'),require('src.data')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local u=game.universe
 for _,id in ipairs({'sat_passive','sat_fuel_buoy','sat_vendor'}) do check(data.wrecks[id] and data.wrecks[id].kind=='prop','design '..id..' loads as a prop') end
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
 -- panels are shot off like a ship's parts
 local target=by2['earth_sat_03'] or select(2,next(by2))
 local sensors=0
 for _,f in ipairs(target.body:getFixtures()) do if f:isSensor() then sensors=sensors+1 end end
 check(sensors>0,'panels are shootable sensors')
 local piece
 for _,pc in ipairs(target.pieces) do if pc.part.name=='panel' then piece=pc break end end
 check(piece and not piece.core,'a panel strip can break off')
 local before=#game.entities
 game:breakOff(target,piece)
 check(#game.entities==before+1,'and flies off as its own wreck')
 target.dead=true
 game:step(1/60)
 check(Sat.get(u,target.sat).lost,'a destroyed satellite is marked lost')
 -- docking: a closed satellite refuses, a fuel buoy locks you on and vends
 game:loadField('earth')
 local by3=sats()
 local closed,buoy
 for id,o in pairs(by3) do
  local rr=Sat.get(u,id)
  if rr.kind=='passive' and not rr.dock then closed=closed or o end
  if rr.kind=='fuel' then buoy=buoy or o end
 end
 check(closed and buoy,'earth has a closed passive sat and a fuel buoy')
 check(not Sat.request(game,closed) and not game.satLock,'a closed satellite refuses the lock')
 check(Sat.request(game,buoy) and game.satLock and game.satLock.e==buoy,'a fuel buoy locks you on')
 local rows=Sat.menu(game)
 check(rows[1].kind=='vend' and rows[1].item=='deuterium_canister','it vends fuel')
 u.credits=1000
 local had=game.player.cargo.deuterium_canister or 0
 Sat.choose(game,rows[1])
 check((game.player.cargo.deuterium_canister or 0)==had+1 and u.credits==1000-rows[1].price,'buying takes credits and fills the hold')
 local bx,by=buoy.body:getPosition()
 for _=1,60 do game:step(1/60) end
 local px,py=game.player.body:getPosition()
 local nx,ny=buoy.body:getPosition()
 check(math.sqrt((px-nx)^2+(py-ny)^2)<buoy.radius,'the lock holds you beside it')
 Sat.release(game)
 check(not game.satLock and not buoy.satHeld,'and lets go')
 -- quests open a closed one and get the uplink
 local cid=closed.sat
 Sat.allow(u,cid,{dock='player',actions={'quest'}})
 local said
 Sat.onQuest(cid,function(g,rr) said=rr.id;return 'Next leg: Mars' end)
 check(Sat.request(game,closed),'a quest-opened satellite lets you in')
 local q=Sat.menu(game)
 check(q[1].kind=='quest','and offers the uplink')
 Sat.choose(game,q[1])
 check(said==cid and game.satLock.note=='Next leg: Mars','the quest hook fires')
 Sat.release(game)
 print(('satellites: %d checks passed'):format(checks))
end
