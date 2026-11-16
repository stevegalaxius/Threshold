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
 Sat.ensureHubs(u)
 for _,r in pairs(u.satellites) do assert(not Sat.retired[r.kind],'retired satellite kind still in orbit: '..r.id) end
 -- every trade buoy is a hub, and a ship passing one is served from it
 local hubNode,hub
 for _,area in ipairs(Fields.list) do
  for _,loc in ipairs(Fields[area].buoyIds or {}) do hubNode=hubNode or loc;assert(Sat.hubAt(u,loc),'no hub at '..loc) end
 end
 assert(hubNode,'no trade buoys')
 hub=Sat.hubAt(u,hubNode);Sat.refuel(u,hub.id,'test')
 -- a working hub is an upkeep stop with its own shelf; a dry one isn't
 require('src.supplies').universe=u
 local F=require('src.reactor_fuel').item()
 assert(require('src.supplies').supports(hubNode),'working hub is not a service stop')
 local listed=false;for _,id in ipairs(require('src.upkeep').stops(require('src.locations').get(hubNode).area)) do if id==hubNode then listed=true end end
 assert(listed,'hub missing from upkeep stops')
 assert(require('src.stockpile').count(u,hubNode,F)>0,'hub shelf opens without fuel')
 hub.fuelAt=u.clock-Sat.fuelLife*2;Sat.fuel(u,hub)
 assert(not require('src.supplies').supports(hubNode),'dry hub still serves')
 Sat.refuel(u,hub.id,'test')
 -- a hauler takes a refuel job and flies out to the satellite (offline)
 local Tasks=require('src.tasks');local Actions=require('src.npc_actions')
 local npc
 for _,r in pairs(u.npcs or {}) do if r.ship and r.state~='dead' and r.area then npc=r;break end end
 assert(npc,'no NPC for the refuel job')
 local Jobs=require('src.sat_jobs')
 local sat
 for id,r in pairs(u.satellites) do if not r.hub and not r.lost and Jobs.places(r.field) then sat=r;break end end
 sat.fuelAt=u.clock-Sat.fuelLife*0.9;Sat.fuel(u,sat)
 local offer=Jobs.post(u,sat,'satrefuel')
 local _,here=Jobs.places(sat.field)
 local savedTask,savedState,savedNode,savedAction=npc.task,npc.state,npc.node,npc.action
 npc.action=nil;npc.task={kind='satrefuel',id=offer.id,sat=sat.id,source=offer.source,target=here,cargo={item='deuterium_canister',amount=1}}
 npc.state,npc.node,npc.area='idle',here,require('src.locations').get(here).area
 local def=Tasks.definitions.satrefuel
 local clock=u.clock
 for _=1,400 do
  local ctx={u=u,r=npc,clock=clock,game={universe=u}}
  if not npc.action then local spec=def.nextAction(ctx);if not spec then break end;Actions.request(ctx,spec).fromJob=true end
  Actions.step(ctx);clock=clock+5
 end
 assert(npc.task.serviced and sat.fuel==1,'hauler did not refuel the satellite out at its berth')
 assert(npc.lastAction and npc.lastAction.operation=='satservice' and npc.lastAction.status=='done','refuel was not a work action at the satellite')
 npc.task,npc.state,npc.node,npc.action=savedTask,savedState,savedNode,savedAction
 Jobs.clear(u,sat.id)
 local sid
 for id,r in pairs(u.satellites or {}) do if not r.lost and not r.hub and r.field~=game.fieldId then sid=id;break end end
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
 print('ok  satellites: hubs, fuel, refuel and replacement jobs')
 print('ALL TESTS PASSED')
end
