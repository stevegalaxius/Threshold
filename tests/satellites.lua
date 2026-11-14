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
 for _,f in ipairs(e.body:getFixtures()) do
  local pts={f:getShape():getPoints()}
  for k=1,#pts,2 do local wx,wy=e.body:getWorldPoint(pts[k],pts[k+1]);reach=math.max(reach,math.sqrt((wx-x)^2+(wy-y)^2)) end
 end
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
 -- shot to death: breaks into the bus and the panel strips, not nothing
 local target=by2['earth_sat_03'] or select(2,next(by2))
 local count=#game.entities
 target.dead=true
 game:step(1/60)
 local bits=0
 for _,o in ipairs(game.entities) do if o.kind=='husk' and o.group then bits=bits+1 end end
 check(bits>=10,'a destroyed satellite breaks into pieces: '..bits)
 check(Sat.get(u,target.sat).lost,'and is marked lost')
 print(('satellites: %d checks passed'):format(checks))
end
