return function(game)
 local P,A,Fields,Save=require('src.population'),require('src.alife'),require('src.fields'),require('src.save')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local cases={{role='pirate',area='earth'},{role='trader',area='earth'},
  {role='patrol',area='earth'},{role='miner',area='phobos'}}
 game.autosaveOff=true
 game:captureALife(true)
 local u=game.universe;local clock=u.clock
 for _,area in ipairs(Fields.list) do
  for _,role in ipairs(P.order) do
   local timers=u.populationSpawns[area]
   if P.target(area,role)>0 then
    check(timers and timers[role] and timers[role].nextAt>clock,area..'/'..role..': missing delayed arrival')
   elseif Fields[area].instance then
    check(not timers or not timers[role],area..': instance has an A-Life population timer')
   end
  end
 end
 -- Seeding and visiting are independent of replenishment; timers stay saved.
 local nextId=u.nextNpcId;local earthTimer=u.populationSpawns.earth.trader
 local nextAt=earthTimer.nextAt
 A.seed(game)
 check(u.nextNpcId==nextId and earthTimer.nextAt==nextAt,'seed replenished population or reset timers')
 -- Freeze unrelated arrival checks so each role can be exercised separately.
 for _,timers in pairs(u.populationSpawns) do for _,timer in pairs(timers) do timer.nextAt=clock+1000000 end end
 local G=require('src.travelgraph');local point=G.point
 G.point=function()error('remote arrival sampled a physical travel path')end
 local bodies=game.world:getBodyCount()
 game.fieldId='station' -- All four cases are remote, with the existing world unstepped.
 for _,case in ipairs(cases) do
  local area,role=case.area,case.role;local target=P.target(area,role)
  local before=P.count(u,area,role)
  if before<target then assert(P.spawn(game,area,role,false)) end
  before=P.count(u,area,role)
  local victim
  for _,r in pairs(u.npcs) do if r.home==area and r.role==role and r.state~='dead' then victim=r;break end end
  assert(victim);victim.state='dead'
  local oldId=victim.id
  local timer=u.populationSpawns[area][role]
  nextId=u.nextNpcId
  -- A future timer cannot refill a vacancy merely because update was called.
  P.update(game,clock)
  check(u.nextNpcId==nextId,role..': replacement arrived before its timer')
  timer.nextAt=clock-1000000
  P.update(game,clock)
  check(u.nextNpcId==nextId+1 and P.count(u,area,role)==before,role..': missing single replacement')
  local replacement=u.npcs['npc/'..u.nextNpcId]
  check(replacement.id~=oldId and victim.state=='dead',role..': resurrected an old identity')
  check(replacement.role==role and replacement.spawnOrigin=='warp' and replacement.warpUntil>clock,role..': replacement bypassed shared warp arrival')
  check(replacement.route and #replacement.route>=2 and replacement.ship.hull,role..': missing fitted ship or route')
  if role~='trader' then check(replacement.task and replacement.task.kind==({miner='mine',patrol='patrol',pirate='raid'})[role],role..': missing starting job') end
  P.update(game,clock)
  check(u.nextNpcId==nextId+1,role..': repeated sync duplicated arrival')
  timer.nextAt=clock
  P.update(game,clock)
  check(u.nextNpcId==nextId+1,role..': exceeded home population target')
  -- Living ships away from home still count, including interplanetary travel.
  local previousArea,previousState=replacement.area,replacement.state
  replacement.area='venus';replacement.state='transit';timer.nextAt=clock
  P.update(game,clock)
  check(u.nextNpcId==nextId+1,role..': travelling ship was replaced at home')
  replacement.area,replacement.state=previousArea,previousState
 end
 G.point=point
 check(game.world:getBodyCount()==bodies,'remote replenishment created physics bodies')
 game.fieldId='earth'
 -- Old pirate saves retain their schedule when adding the other role timers.
 local legacy={pirateSpawns={earth={nextAt=1234,sequence=7}}}
 P.state(legacy)
 check(legacy.populationSpawns.earth.pirate.nextAt==1234 and legacy.populationSpawns.earth.pirate.sequence==7,'legacy pirate arrival timer was reset')
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(saved);u=game.universe
 for _,case in ipairs(cases) do
  local expected=saved.populationSpawns[case.area][case.role]
  local actual=u.populationSpawns[case.area][case.role]
  check(actual.nextAt==expected.nextAt and actual.sequence==expected.sequence,case.role..': arrival schedule did not survive save/load')
 end
 -- Manual arrivals use the same ships/jobs and the existing local warp visual.
 for _,case in ipairs(cases) do
  game:loadField(case.area)
  local before=P.count(game.universe,case.area,case.role)
  local r=assert(P.spawn(game,case.area,case.role,true))
  local e=assert(game.alifeOnline[r.id],case.role..': local warp did not materialize')
  check(P.count(game.universe,case.area,case.role)==before+1,case.role..': debug arrival was capped')
  local x,y=e.body:getPosition();local effect=false
  for _,fx in ipairs(game.effects) do if fx.kind=='warp_in' and (fx.x-x)^2+(fx.y-y)^2<1 then effect=true end end
  check(effect,case.role..': local arrival lost its warp effect')
  if case.role=='miner' then check(r.task and r.task.kind=='mine','debug miner could not obtain work beyond the normal population cap') end
  local isClear=game.isClear;game.isClear=function()return false end
  nextId=game.universe.nextNpcId
  local failed=P.spawn(game,case.area,case.role,true)
  game.isClear=isClear
  check(not failed and game.universe.nextNpcId==nextId,case.role..': failed placement left a partial NPC')
 end
 for _,role in ipairs(P.order) do check(not P.spawn(game,'station',role,false),'instance accepted persistent '..role) end
 print(('POPULATION TEST PASSED (%d checks)'):format(checks))
end
