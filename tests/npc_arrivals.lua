-- New NPCs arrive through a way in (a moon-gate corridor, or off a mass
-- driver's lane) and fly inward, rather than warping in beside a station.
return function(game)
 local P,L,A,Fields,T=require('src.population'),require('src.locations'),require('src.alife'),require('src.fields'),require('src.tuning')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local u=game.universe
 local cases={{'belt','trader'},{'belt','pirate'},{'shoals','miner'},{'shoals','pirate'},{'shoals','trader'},{'earth','patrol'},{'mars','trader'},{'uranus','pirate'},{'titania','trader'},{'venus','trader'},{'mercury','trader'}}
 for _,c in ipairs(cases) do
  local area,role=c[1],c[2]
  if P.target(area,role)>0 then
   local r,why=P.spawn(game,area,role,false)
   -- (a ship whose first move already took it to another area, e.g. to a
   -- home berth elsewhere, has nothing to fly in to here)
   if r and r.spawnOrigin~='edge' and tostring(r.arrivalSkip):match('not in') then
    print('arrival: '..area..' '..role..' left at once: '..r.arrivalSkip)
   elseif r then
    check(r.spawnOrigin=='edge',('%s %s did not arrive from the edge (%s: %s)'):format(area,role,tostring(r.spawnOrigin),tostring(r.arrivalSkip)))
    local from=L.get(r.arrivedFrom)
    check(from and (from.kind=='moon_gate' or from.kind=='driver') and from.area==area,area..' '..role..' arrived from '..tostring(r.arrivedFrom))
    check((r.state=='travel' or r.arrivedFrom==(r.node or r.route[r.index])) and A.point(r,u.clock)~=nil,area..' '..role..' has no inbound position')
    local x,y=A.point(r,u.clock)
    local R=Fields[area].radius or 10000
    check(x*x+y*y>(R*.6)^2,('%s %s starts %.0f px from the centre of a %.0f map'):format(area,role,math.sqrt(x*x+y*y),R))
    -- offline it keeps going: after its leg it is somewhere else, still alive
    for t=1,60 do u.clock=u.clock+30;A.advance(r,u.clock,u,game) end
    check(r.state~='dead',area..' '..role..' died on arrival')
    print(('arrival: %s %s via %s (%s) -> now %s at %s'):format(area,role,from.id,from.kind,r.state,tostring(r.node or r.route[r.index])))
   else print('arrival: no spawn',area,role,why) end
  end
 end
 check(checks>10,'too few arrivals were tested')
 -- online: in the player's own area the arrival is a real ship near the edge
 game:loadField('shoals')
 if not game.player then game:spawnPlayer(game.playerHull) end
 game.player.body:setPosition(0,0)
 local r,why=P.spawn(game,'shoals','miner',false)
 if r and r.spawnOrigin=='edge' then
  local gx,gy=L.position(r.arrivedFrom,u.clock)
  local R=Fields.shoals.radius
  game.player.body:setPosition(gx*.8,gy*.8) -- near the gate it came through
  game.alifeNext=0;game:updateALife()
  local e=game.alifeOnline and game.alifeOnline[r.id] or A.wake(game,r)
  check(e,'an arrival beside the player did not come online')
  local x,y=e.body:getPosition()
  check(x*x+y*y>(R*.6)^2,('online arrival woke %.0f px from the centre'):format(math.sqrt(x*x+y*y)))
  print(('arrival: online miner woke %.0f px out of %.0f, through %s'):format(math.sqrt(x*x+y*y),R,r.arrivedFrom))
 end
 print(('NPC ARRIVALS TEST PASSED (%d checks)'):format(checks))
end
