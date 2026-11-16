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
 for _,r in pairs(u.satellites) do assert(not Sat.retired[r.kind],'retired satellite kind still in orbit: '..r.id) end
 -- hubs: placed per planet as their own satellite kind
 local hub
 for _,slot in ipairs(Sat.layout('neptune',Fields.neptune)) do if slot.kind=='hub' then hub=Sat.record(u,slot,'neptune');Sat.refuel(u,hub.id,'test') end end
 assert(hub and hub.kind=='hub','Neptune has no hub satellite')
 for _,slot in ipairs(Sat.layout('earth',Fields.earth)) do assert(slot.kind~='hub','Earth should have no hub') end
 Sat.refuel(u,hub.id,'test')
 local F=require('src.reactor_fuel').item()
 assert(require('src.stockpile').count(u,Sat.shelf(hub),F)>0,'hub shelf opens without fuel')
 -- an NPC short of fuel near it flies out, holds on the berth and buys
 do
  local Actions=require('src.npc_actions');local Hold=require('src.inventory.hold')
  local npc
  -- (a ship with a plain cargo list: a grid hold may be packed full)
  for _,r in pairs(u.npcs) do if r.ship and not r.ship.hold and r.state~='dead' and r.state~='escaped' then npc=r;break end end
  local saved=require('src.persistence').copy(npc)
  local hx,hy=Sat.home(u,hub)
  if npc.ship.hold then local h=Hold.deserialize(npc.ship.hold);Hold.take(h,F,Hold.count(h,F));npc.ship.hold=Hold.serialize(h);npc.ship.cargo=Hold.totals(h) else npc.ship.cargo[F]=0 end
  npc.ship.fuelCharge=0;npc.task=nil;npc.action=nil;npc.nextHubAt=nil;npc.service=nil
  npc.state,npc.area='idle','neptune'
  npc.node=Fields.neptune.buoyIds[1] or Fields.neptune.holdingId
  local clock=u.clock
  -- (it goes to whichever hub is nearest: count them all)
  local function served() local n=0;for _,r in pairs(u.satellites) do if r.kind=='hub' then n=n+(r.served or 0) end end;return n end
  local before=served()
  local ctx={u=u,r=npc,clock=clock,game={universe=u}}
  assert(require('src.upkeep').need(npc)=='fuel','drained NPC does not need fuel')
  assert(require('src.sat_jobs').hubVisit(ctx),'NPC short of fuel ignored the hub')
  for _=1,2000 do
   if not npc.action then break end
   clock=clock+5;Actions.step({u=u,r=npc,clock=clock,game={universe=u}})
  end
  assert(served()>before,'hub did not serve the NPC: '..tostring(npc.lastAction and npc.lastAction.status)..' '..tostring(npc.lastAction and npc.lastAction.reason)..' '..tostring(npc.action and npc.action.phase))
  assert((npc.ship.cargo[F] or 0)>0,'NPC left the hub without fuel')
  for k in pairs(npc) do npc[k]=nil end;for k,v in pairs(saved) do npc[k]=v end
 end
 -- a hub's two berths are claimed one each; a third ship finds none free
 do
  local Actions,Jobs=require('src.npc_actions'),require('src.sat_jobs')
  local ships,saved={},{}
  for _,r in pairs(u.npcs) do if #ships<3 and r.ship and r.state~='dead' and r.state~='escaped' then ships[#ships+1]=r;saved[r]=require('src.persistence').copy(r) end end
  local got={}
  for k,r in ipairs(ships) do
   r.task,r.action,r.state,r.area,r.node=nil,nil,'idle','neptune',Fields.neptune.holdingId or (Fields.neptune.buoyIds or {})[1]
   local ctx={u=u,r=r,clock=u.clock,game={universe=u}}
   local spec=Jobs.freeBerth(ctx,hub,'hubservice')
   got[k]=spec and spec.target.berth
   if spec then Actions.request(ctx,spec).fromJob=true;Actions.step(ctx) end
  end
  assert(got[1] and got[2] and got[1]~=got[2],'two ships could not take both hub berths')
  assert(got[3]==nil,'a third ship got a berth on a full hub')
  for _,r in ipairs(ships) do
   if r.action then Actions.cancel({u=u,r=r,clock=u.clock,game={universe=u}},'test') end
   for k in pairs(r) do r[k]=nil end;for k,v in pairs(saved[r]) do r[k]=v end
  end
 end
 -- a hub refuel's canister and restock come out of the trade station's stock
 do
  local Jobs,Tasks,Actions,Stock=require('src.sat_jobs'),require('src.tasks'),require('src.npc_actions'),require('src.stockpile')
  local source,here=Jobs.places('neptune')
  Stock.add(u,source,F,40)
  local shelfBefore=Stock.count(u,Sat.shelf(hub),F)
  for _,i in ipairs({1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20}) do Stock.take(u,Sat.shelf(hub),F,1) end
  local stationBefore=Stock.count(u,source,F)
  hub.fuelAt=u.clock-Sat.fuelLife*0.9;Sat.fuel(u,hub)
  local offer=Jobs.post(u,hub,'satrefuel')
  local npc
  for _,r in pairs(u.npcs) do if r.ship and not r.ship.hold and r.state~='dead' and r.state~='escaped' then npc=r;break end end
  local saved=require('src.persistence').copy(npc)
  local t=require('src.persistence').copy(offer);t.phase='prepare'
  npc.task,npc.action=nil,nil
  assert(Tasks.definitions.satrefuel.prepare(u,npc,t,source,u.clock),'hub refuel job could not load at its station')
  assert(Stock.count(u,source,F)<stationBefore,'the canisters did not come out of the station')
  npc.task=t;npc.state,npc.node,npc.area='idle',here,require('src.locations').get(here).area
  local clock=u.clock
  for _=1,2000 do
   local ctx={u=u,r=npc,clock=clock,game={universe=u}}
   if not npc.action then local spec=Tasks.definitions.satrefuel.nextAction(ctx);if not spec then break end;Actions.request(ctx,spec).fromJob=true end
   Actions.step(ctx);clock=clock+5
  end
  assert(hub.fuel==1,'hub was not refuelled')
  assert(Stock.count(u,Sat.shelf(hub),F)>shelfBefore-20,'hub shelf was not restocked from the hauler')
  for k in pairs(npc) do npc[k]=nil end;for k,v in pairs(saved) do npc[k]=v end
  Jobs.clear(u,hub.id)
 end
 -- a ship never waits on a hub with an empty tank
 do
  local Jobs=require('src.sat_jobs')
  local r;for _,o in pairs(u.npcs) do if o.ship and o.state~='dead' then r=o;break end end
  local saved=require('src.persistence').copy(r)
  r.ship.cargo[F]=0;r.ship.fuelCharge=0
  if r.ship.hold then local Hold=require('src.inventory.hold');local h=Hold.deserialize(r.ship.hold);Hold.take(h,F,Hold.count(h,F));r.ship.hold=Hold.serialize(h);r.ship.cargo=Hold.totals(h) end
  local c=require('src.reactor_fuel').condition(r)
  assert(c=='empty' or c=='stranded','drained ship still has fuel: '..tostring(c))
  assert(not Jobs.holdForHub(r,u.clock),'empty ship held off its station visit for a hub')
  for k in pairs(r) do r[k]=nil end;for k,v in pairs(saved) do r[k]=v end
 end
 hub.fuelAt=u.clock-Sat.fuelLife*2;Sat.fuel(u,hub)
 assert(not Sat.hubWorking(u,hub),'dry hub still works')
 Sat.refuel(u,hub.id,'test')
 -- a hauler takes a refuel job and flies out to the satellite (offline)
 local Tasks=require('src.tasks');local Actions=require('src.npc_actions')
 local npc
 for _,r in pairs(u.npcs or {}) do if r.ship and r.state~='dead' and r.area then npc=r;break end end
 assert(npc,'no NPC for the refuel job')
 local Jobs=require('src.sat_jobs')
 local sat
 for id,r in pairs(u.satellites) do if r.kind~='hub' and not r.lost and Jobs.places(r.field) then sat=r;break end end
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
 for id,r in pairs(u.satellites or {}) do if not r.lost and r.kind~='hub' and r.field~=game.fieldId then sid=id;break end end
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
 -- left dry, its orbit decays and it comes down: lost, with a launch job
 rec.fuelAt=u.clock-Sat.fuelLife-Sat.deorbit;rec.seenAt=nil;u.satCheckAt=nil;Sat.tick(u)
 assert(rec.lost,'neglected satellite never came down')
 -- the same job on the player's station board
 local Q=require('src.quests');Q.state(u).next=0;Q.state(u).offers={};Q.state(u).cooldown={};Q.update(u,u.clock,game)
 local posted
 for _,q in pairs(Q.state(u).offers) do if q.kind=='sat_launch' and q.subject==sid then posted=q end end
 assert(posted,'no launch job on the station board')
 local launch
 for _,o in pairs(require('src.tasks').state(u).offers) do if o.kind=='satlaunch' and o.sat==sid then launch=o end end
 assert(launch,'no launch job posted')
 assert(not require('src.tasks').npcMayClaim(u,launch,u.clock),'haulers can take a new launch job before the player sees it')
 -- once the player holds the launch, haulers leave its board job alone
 local def=require('src.tasks').definitions.satlaunch
 assert(def.eligible(u,{},launch,launch.source),'hauler cannot take an open launch job')
 assert(Q.accept(u,posted.id,u.clock,game),'could not accept the launch job')
 assert(not def.eligible(u,{},launch,launch.source),'hauler took a launch the player holds')
 Q.abandon(u,posted.id,u.clock,game)
 -- and a launch a hauler already took isn't offered to the player
 launch.owner='npc/test'
 Q.state(u).next=0;Q.state(u).offers={};Q.state(u).cooldown={};Q.update(u,u.clock,game)
 for _,q in pairs(Q.state(u).offers) do assert(not (q.kind=='sat_launch' and q.subject==sid),'launch offered while a hauler has it') end
 launch.owner=nil
 assert(Sat.relaunch(u,sid,'test') and not rec.lost,'relaunch failed')
 print('ok  satellites: hubs, fuel, refuel and replacement jobs')

 -- Routing: no route doubles back. Gates used to join only their nearest
 -- node (a trader bound for Triton flew out to Neptune's far buoy first),
 -- stations just over 120 degrees apart went the long way round, and drill
 -- sites, drivers and gates were used as waypoints.
 do
  local G=require('src.travelgraph')
  local function d(a,b) return (b-a+math.pi)%(2*math.pi)-math.pi end
  for _,area in ipairs(Fields.list) do
   local f=Fields[area];local graph=G.build(area)
   for clock=0,1800,300 do
    local function bearing(id) local x,y=G.position(graph,id,clock);return math.atan2(y,x) end
    for _,a in ipairs(f.locations) do for _,b in ipairs(f.locations) do
     if a~=b and a.kind~='mining_site' and b.kind~='mining_site' then
      local r=assert(G.route(graph,a.id,b.id,clock,600),'no route '..a.id..' -> '..b.id)
      local ids={r.start};for _,leg in ipairs(r.legs) do ids[#ids+1]=leg.edge.to end
      local turned=0
      for i=2,#ids do
       local k=L.get(ids[i]).kind
       assert(i==#ids or (k~='moon_gate' and k~='driver' and k~='mining_site') or r.through,'route passes through '..ids[i]..': '..table.concat(ids,' > '))
       turned=turned+math.abs(d(bearing(ids[i-1]),bearing(ids[i])))
      end
      local extra=turned-math.abs(d(bearing(ids[1]),bearing(ids[#ids])))
      assert(extra<.6,('detour of %.2f rad at %d: %s'):format(extra,clock,table.concat(ids,' > ')))
     end
    end end
   end
  end
 end
 -- A ship just out of earth_1 for earth_2 that is sent to earth_4 (back
 -- past earth_1) turns round where it is, instead of flying on to earth_2
 -- and doubling back, and doesn't jump doing it.
 do
  local A,G=require('src.alife'),require('src.travelgraph')
  local r;for _,n in pairs(game.universe.npcs) do if n.ship then r=n;break end end
  local keep=require('src.persistence').copy(r)
  r.state='travel';r.area='earth';r.encounter=nil;r.speed=600
  r.route={'station:earth_1','station:earth_2'};r.index=2
  local span=G.length(G.build('earth'),{from='station:earth_1',to='station:earth_2'},0)/600
  r.depart=-.1*span;r.arrive=r.depart+span
  local x,y=A.trackPoint(r,0)
  assert(A.redirect(r,'station:earth_4',0),'no way to earth_4')
  assert(r.route[r.index]=='station:earth_1','flew on to '..r.route[r.index]..' before turning: '..table.concat(r.route,' > '))
  local xx,yy=A.trackPoint(r,0)
  assert(math.abs(x-xx)+math.abs(y-yy)<1,'ship jumped turning round')
  for k in pairs(r) do r[k]=nil end;for k,v in pairs(keep) do r[k]=v end
 end
 -- A repair stop past the node it was heading for: the ship rejoins its
 -- route at the station instead of coming back to that node first.
 do
  local U,G,Repairs=require('src.upkeep'),require('src.travelgraph'),require('src.npc_repair')
  local r;for _,n in pairs(game.universe.npcs) do if n.ship then r=n;break end end
  local keep=require('src.persistence').copy(r)
  r.state='travel';r.area='earth';r.encounter=nil;r.worldRecovery=nil;r.waitingForHome=nil;r.driverState=nil
  r.service=nil;r.nextServiceAt=nil;r.speed=600
  r.route={'station:earth_1','station:earth_4','earth/trade_buoy_b','station:earth_3'};r.index=2
  local clock=game.universe.clock
  local span=G.length(G.build('earth'),{from='station:earth_1',to='station:earth_4'},clock)/600
  r.depart=clock-.9*span;r.arrive=r.depart+span
  local need,supports=U.need,Repairs.supports
  U.need=function() return 'repair' end;Repairs.supports=function(id) return id=='station:earth_3' end
  local ok=U.plan(r,clock)
  U.need,Repairs.supports=need,supports
  assert(ok and r.service,'no repair visit planned')
  assert(r.route[#r.route]=='station:earth_3' and r.service.saved.index==4,'repair visit doubles back: '..table.concat(r.route,' > '))
  for k in pairs(r) do r[k]=nil end;for k,v in pairs(keep) do r[k]=v end
 end
 print('ok  routing: no detours, turns round when re-tasked, repair stops rejoin')
 -- 6. Jobs: wreck bounties pay whoever clears a ship wreck, ore contracts
 -- go up where drills ship home, and the Jobs tab lays them all out.
 do
  local B=require('src.wreck_bounty')
  local area=game.fieldId;local payer=assert(B.payer(area),'no bounty payer for '..area)
  local credits=u.credits
  -- the player drills a real wreck apart
  local victim
  for _,e in ipairs(game.entities) do if e.kind=='ship' and e.alifeId and not e.dead then victim=e;break end end
  assert(victim,'no NPC ship to wreck')
  local husk=game:spawnHusk(victim,victim.body:getX()+400,victim.body:getY(),0,0,0,0)
  assert(husk.origin,'ship wreck has no origin')
  local pieces=0
  for _,e in ipairs(game.entities) do if e.kind=='husk' and e.origin==husk.origin then pieces=pieces+1;e.dead=true;e.drilled=true;e.lastHitBy=game.player end end
  run(game,.1)
  local owed=B.owed(u,payer)
  assert(owed>0,'clearing a wreck ('..pieces..' pieces) paid no bounty')
  assert(B.state(u).cleared[payer]==1,'a wreck in pieces paid more than once')
  -- an NPC clean-up crew is paid into its own credits
  local npc
  for _,r in pairs(u.npcs) do if r.ship and r.state~='dead' then npc=r;break end end
  local before=npc.credits or 0
  B.cleared(game,npc,{kind='husk',origin={npc='test'},steel=5},area)
  assert((npc.credits or 0)==before+B.rate(5),'NPC was not paid the wreck bounty')
  assert(not B.cleared(game,npc,{kind='husk',steel=5},area),'a derelict paid a bounty')
  assert(B.collect(game,payer) and u.credits==credits+owed,'bounty not collected')
  -- ore contracts: a drill home short of its ore posts one
  local Q=require('src.quests');local Mining=require('src.mining')
  local home,item
  for _,site in pairs(Mining.state(u).sites) do if site.home and site.item then home,item=L.canonical(site.home),site.item;break end end
  assert(home,'no drill sites')
  Stock.take(u,home,item,Stock.count(u,home,item))
  Q.state(u).next=0;Q.state(u).offers={};Q.state(u).cooldown={};Q.state(u).active={};Q.update(u,u.clock,game)
  local ore
  for _,q in pairs(Q.state(u).offers) do if q.kind=='ore_delivery' and q.giver==home then ore=q end end
  assert(ore,'no ore contract at '..home)
  -- the board is per system: every station in it lists the contract
  local sys=Q.system(home)
  for _,area in ipairs(Fields.list) do
   for _,st in ipairs(L.stations(area,'trade')) do
    local listed=false
    for _,q in ipairs(Q.offersInSystem(u,st)) do if q==ore then listed=true end end
    assert(listed==(Q.system(st)==sys and Q.willOffer(u,home)),'ore contract listing wrong at '..st)
   end
  end
  -- the Jobs tab, docked there and in flight
  local Board,View=require('src.player_contracts'),require('src.ui.jobs')
  local station=Board.station;Board.station=function() return home end
  local ok,err=pcall(function() View.draw(game) end)
  Board.station=station
  assert(ok,err)
  View.draw(game)
 end
 -- a freight pickup only bundles freight: a satellite job on the same lane
 -- is a board order too, with no item
 do
  local Tasks=require('src.tasks');local copy=require('src.persistence').copy
  local t
  for _,o in pairs(Tasks.state(u).offers) do if o.kind=='transport' and o.order and o.state=='available' then t=o;break end end
  assert(t,'no freight order on the board')
  local sat=Tasks.post(u,{kind='satrefuel',source=t.source,target=t.target,sat='test',order=true,cooldown=60,cargo={item='deuterium_canister',amount=1}})
  local hull
  for _,n in pairs(u.npcs) do if n.ship and (require('src.data').hulls[n.ship.hull].hold or 0)>0 then hull=n.ship.hull;break end end
  local r={id='npc/test',ship={hull=hull,loadout={},cargo={}},node=t.source}
  local job=copy(t);job.phase=nil
  local ok,err=pcall(Tasks.definitions.transport.prepare,u,r,job,t.source,u.clock)
  Tasks.state(u).offers[sat.id]=nil
  assert(ok,'freight bundling tripped on a satellite job: '..tostring(err))
 end
 print('ok  jobs: wreck bounties, ore contracts and the Jobs tab')
 print('ALL TESTS PASSED')
end
