-- The whole test suite: love . --test
-- Four quick checks, about half a minute in total. Add a check here only
-- if it is fast; long soaks belong in a one-off script, not this file.
return function(game)
 local Game=require('src.game')
 local Fields=require('src.fields')
 local Save=require('src.save')
 local Stock=require('src.stockpile')
 local L=require('src.locations')
 local function fresh() local g=Game.new();g.autosaveOff=true;return g end
 local function run(g,seconds) for _=1,math.floor(seconds*60) do g:step(1/60) end end
 local function finite(n) return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge end

 -- 1. Content: every map loads and runs a second without crashing.
 -- This is the check for station, layout and data edits.
 local g=fresh()
 for _,id in ipairs(Fields.list) do
  local ok,err=xpcall(function() g:loadField(id);run(g,1) end,debug.traceback)
  assert(ok,('map %s: %s'):format(id,tostring(err)))
  assert(#g.entities>0,'map '..id..' has no entities')
 end
 print('ok  content: '..#Fields.list..' maps load')

 -- 2. Boot: the starting map runs ten seconds of play with a live player.
 game.autosaveOff=true
 game:loadField(Fields.start)
 run(game,10)
 assert(game.player and not game.player.dead,'player missing or dead after 10s')
 local npcs=0 for _ in pairs(game.universe.npcs or {}) do npcs=npcs+1 end
 assert(npcs>0,'universe has no NPCs')
 print('ok  boot: 10s on '..tostring(Fields.start)..', '..npcs..' NPCs')

 -- 3. Save/load: the player and NPC count survive a round trip.
 local hull=game.player.hull.id
 assert(Save.write('test',game:saveState()),'save failed')
 g=fresh()
 local state=assert(Save.read('test'))
 g:loadState(state)
 Save.delete('test')
 assert(g.player and g.player.hull.id==hull,'player ship changed on load')
 assert(g.fieldId==game.fieldId,'loaded into a different map')
 local after=0 for _ in pairs(g.universe.npcs or {}) do after=after+1 end
 assert(after==npcs,('NPCs %d before save, %d after'):format(npcs,after))
 print('ok  save/load')

 -- 4. Economy: one simulated hour of markets keeps stock sane.
 local u=game.universe
 local Econ=require('src.economy')
 require('src.supplies').universe=u
 local start=u.clock
 for clock=start,start+3600,60 do u.clock=clock;Econ.update(u,clock) end
 local stations=0
 for _,area in ipairs(Fields.list) do
  for _,id in ipairs(L.stations(area,'trade')) do
   stations=stations+1
   for item in pairs(require('src.data').items) do
    local n=Stock.count(u,id,item)
    assert(finite(n) and n>=0,('%s has %s of %s'):format(id,tostring(n),item))
   end
  end
 end
 assert(stations>0,'no trade stations')
 print('ok  economy: 1h across '..stations..' stations')

 -- 5. Satellites: fuel runs down offline, a hauler's refuel job tops it up.
 local Sat=require('src.satellites')
 local sid
 for id,r in pairs(u.satellites or {}) do if not r.lost and r.field~=game.fieldId then sid=id;break end end
 if not sid then
  for id,r in pairs(u.satellites or {}) do if not r.lost then sid=id;break end end
 end
 assert(sid,'no satellite records')
 local rec=u.satellites[sid]
 Sat.refuel(u,sid,'test')
 rec.fuelAt=u.clock-Sat.fuelLife*0.8;u.satCheckAt=nil
 Sat.tick(u)
 assert(rec.fuel>0 and rec.fuel<Sat.refuelAt,'fuel did not drain')
 local job
 for _,o in pairs(require('src.tasks').state(u).offers) do if o.kind=='satrefuel' and o.sat==sid then job=o end end
 assert(job,'no refuel job posted')
 u.satCheckAt=nil;Sat.tick(u)
 local n=0
 for _,o in pairs(require('src.tasks').state(u).offers) do if o.kind=='satrefuel' and o.sat==sid then n=n+1 end end
 assert(n==1,'refuel job posted twice')
 rec.fuelAt=u.clock-Sat.fuelLife;Sat.fuel(u,rec)
 assert(Sat.dry(rec) and rec.dryAt and #Sat.levers(rec).vend==0,'dry satellite still vends')
 assert(Sat.refuel(u,sid,'test') and rec.fuel==1 and not rec.dryAt,'refuel failed')
 Sat.markLost(u,rec)
 -- the same job on the player's station board
 local Q=require('src.quests');Q.state(u).next=0;Q.state(u).offers={};Q.state(u).cooldown={};Q.update(u,u.clock,game)
 local posted
 for _,q in pairs(Q.state(u).offers) do if q.kind=='sat_launch' and q.subject==sid then posted=q end end
 assert(posted,'no launch job on the station board')
 local launch
 for _,o in pairs(require('src.tasks').state(u).offers) do if o.kind=='satlaunch' and o.sat==sid then launch=o end end
 assert(launch,'no launch job posted')
 assert(Sat.relaunch(u,sid,'test') and not rec.lost,'relaunch failed')
 print('ok  satellites: fuel, refuel and replacement jobs')
 print('ALL TESTS PASSED')
end
