return function(game)
 local W,L,F=require('src.world_layout'),require('src.locations'),require('src.fields')
 local G,H,A=require('src.travelgraph'),require('src.npc_home'),require('src.alife')
 local E,Tasks,Hold=require('src.world_authoring'),require('src.tasks'),require('src.inventory.hold')
 local Save,copy=require('src.save'),require('src.persistence').copy
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true;game:loadField('earth');game:captureALife(true)
 local original=game:saveState();local definition=W.export()
 local primary=L.station('earth','trade');local secondary
 for _,id in ipairs(L.stations('earth','trade')) do if id~=primary then secondary=id end end
 local templates={}
 for _,r in pairs(game.universe.npcs) do
  if not templates[r.role] then templates[r.role]=copy(r) end
 end
 -- One operation adds a port, its construction, navigation and dispatch work.
 local ok,port=game:editWorldLayout(function(world)
  return world.addStation('earth',{name='Test port',position={x=26000,y=6000},layout='shipyard_1'})
 end)
 check(ok and port and not port:find('earth',1,true),'station identity was derived from its placement')
 local st=assert(game:locationEntity(port));local model=st.def.id;local market=game.marketDefinition(st)
 check(market~=nil and G.itinerary(primary,port,0),'new port lacks market or network access')
 check(require('src.data').markets['Hub Station']==nil,'market still has a display-name identity alias')
 Hold.add(game:stationRecord(st).storage,'scrap',3)
 game:dockInstantly(game.player,st)
 -- Moving a docked station between regions retains its key, cargo and shop.
 ok=game:editWorldLayout(function(world)world.moveStation(port,'mars',{x=15000,y=7000}) end)
 check(ok and game.fieldId=='mars' and L.get(port).area=='mars','cross-region placement did not move the station')
 st=assert(game:locationEntity(port))
 check(st.def.id==model and game.marketDefinition(st)==market,'move changed layout/catalogue identity')
 check(game.player.dockState.station.locationId==port and Hold.count(game:stationRecord(st).storage,'scrap')==3,'move lost docking or station storage')
 ok=game:editWorldLayout(function(world)world.find(port).name='Renamed port' end)
 check(ok and game:locationEntity(port).name=='Renamed port' and game.marketDefinition(game:locationEntity(port))==market,'rename changed station services')
 -- Invalid edits roll back without altering the loaded world.
 local count=#L.stations('mars')
 local rejected=game:editWorldLayout(function(world)world.addStation('mars',{name='Broken',layout='missing_layout'}) end)
 check(not rejected and #L.stations('mars')==count and game.player.dockState.station.locationId==port,'invalid edit was not rolled back')
 rejected=game:editWorldLayout(function(world)world.addStation('mars',{name='Invalid position',position={x=0/0,y=100}}) end)
 check(not rejected and #L.stations('mars')==count,'invalid position was not rolled back')
 -- Removing a neighbour must not change a surviving station's authored spin.
 local secondarySpin=L.get(secondary).spin
 ok=game:editWorldLayout(function(world)world.setStationEnabled(primary,false) end)
 check(ok and L.get(secondary).spin==secondarySpin,'removing a neighbouring port changed station rotation')
 ok=game:editWorldLayout(function(world)world.setStationEnabled(primary,true) end)
 check(ok and L.get(secondary).spin==secondarySpin,'restoring a neighbouring port changed station rotation')
 -- Two loaded deliveries: remove one's destination and the other's source.
 game:captureALife(true);local u=game.universe;u.npcs={};u.tasks.offers={}
 local function delivery(id,source,target)
  local r=copy(templates.trader);r.id=id;r.role='trader';r.home='earth';r.area='earth';r.taskWorker=true
  r.task=nil;r.job=nil;r.encounter=nil;r.piracy=nil;r.offlineLoot=nil;r.ship.hold=nil;r.ship.cargo={}
  r.homeStation=secondary;r.tradeHome=nil;r.state='travel';r.route=assert(G.itinerary(source,target,u.clock));r.index=2
  r.depart=u.clock;r.arrive=u.clock+100;r.pose=nil;r.offset=nil;r.docking=nil
  Tasks.post(u,{kind='transport',source=source,target=target,item='scrap',amount=5})
  u.npcs[id]=r;assert(Tasks.choose(u,r,source,u.clock))
  return r
 end
 local marsHome=L.station('mars','trade')
 local cancel=delivery('edit-cancelled-delivery',marsHome,secondary)
 local cancelId=cancel.id
 local keep=delivery('edit-loaded-delivery',secondary,marsHome);local keepId,keepTask=keep.id,keep.task.id
 local patrol=copy(templates.patrol);patrol.id='edit-patrol';patrol.home='earth';patrol.area='earth'
 patrol.homeStation=secondary;patrol.encounter=nil;patrol.task=nil;patrol.route={secondary,secondary};patrol.index=1;patrol.state='idle';patrol.untilTime=u.clock+10
 u.npcs[patrol.id]=patrol
 -- Preserve a real player-owned item at the station we remove.
 u.stations[secondary]=game:stationRecord({key=secondary});Hold.add(u.stations[secondary].storage,'salvage_kit',1)
 local hulls={};for id,r in pairs(u.npcs) do hulls[id]=r.ship.hull end
 ok=game:editWorldLayout(function(world)world.removeStation(secondary) end)
 u=game.universe;cancel=u.npcs[cancelId];keep=u.npcs[keepId];patrol=u.npcs[patrol.id]
 check(ok and not L.byId[secondary],'removed port remains in catalogue')
 check(cancel.homeStation==primary and patrol.homeStation==primary,'residents did not acquire a surviving home')
 check(not cancel.task and cancel.ship.cargo.scrap==5 and cancel.worldRecovery,'cancelled destination lost its cargo or recovery route')
 check(keep.task.id==keepTask and keep.ship.cargo.scrap==5 and keep.worldRecovery.target==marsHome,'removing a loaded delivery source cancelled or duplicated its manifest')
 check(Hold.count(u.stations[secondary].storage,'salvage_kit')==1,'removed station inventory was discarded')
 for id,r in pairs(u.npcs) do
  check(r.ship.hull==hulls[id],'world edit replaced an NPC hull')
  for _,node in ipairs(r.route) do check(L.byId[node],'NPC still routes through removed port') end
 end
 -- A recovery follows the ordinary network and returns to normal job selection.
 game:captureALife(true);keep=u.npcs[keepId]
 for _=1,80 do
  if keep.lastTask and keep.lastTask.id==keepTask and keep.lastTask.status=='completed' then break end
  local clock=keep.state=='docked' and keep.untilTime or keep.arrive
  A.advance(keep,clock+.01,u,game)
 end
 check(keep.lastTask and keep.lastTask.id==keepTask and keep.lastTask.status=='completed','rerouted loaded delivery never completed')
 check(not keep.worldRecovery,'completed delivery stayed in recovery mode')
 -- Physical recovery departures use the same station docking code for fighters
 -- and haulers, and rebind their ordinary routes after the completed stop.
 game:loadField('earth');game:captureALife(true);u=game.universe
 for _,role in ipairs({'patrol','trader'}) do
  local r=copy(templates[role]);r.id='physical-edit-'..role;r.role=role;r.home='earth';r.area='earth'
  r.homeStation=primary;r.task=nil;r.taskWorker=nil;r.piracy=nil;r.encounter=nil;r.tripDestination=nil;r.onRoundTrip=nil;r.tripRoute=nil
  r.state='docked';r.route={primary,primary};r.index=2;r.node=primary;r.untilTime=u.clock+1
  r.worldRecovery={target=primary};r.pose=nil;r.docking=nil;u.npcs[r.id]=r
  local e=A.wake(game,r)
  check(e.taskWorker,'recovery does not enable shared driver navigation')
  u.clock=u.clock+2;game:updateDockedShip(e,2)
  check(not e.dockState and not r.worldRecovery and r.state=='travel','physical '..role..' failed to resume after recovery docking')
  check(role~='patrol' or r.task and r.task.kind=='patrol','recovered patrol did not select its ordinary duty')
  check(#e.route==#r.route and not e.worldDeparture,'physical route was not rebound after recovery')
 end
 game:captureALife(true)

 -- Mine home removal reassigns its jobs without deleting the mineral field.
 local mineHome=L.station('phobos','mining');local miner=copy(templates.miner)
 for _,r in pairs(original.npcs) do if r.role=='miner' and r.home=='phobos' then miner=copy(r);break end end
 miner.id='edit-miner';miner.encounter=nil;miner.homeStation=mineHome;miner.base=mineHome
 miner.ship.cargo.iron_ore=2;u.npcs[miner.id]=miner
 local resources=copy(u.mining.resources)
 local replacement
 ok,replacement=game:editWorldLayout(function(world)
  local id=world.addStation('phobos',{name='Replacement mine port',position={x=0,y=-4500},layout='ring_900_120'})
  world.removeStation(mineHome);return id
 end)
 u=game.universe;miner=u.npcs[miner.id]
 check(ok and miner.homeStation==replacement and miner.base==replacement,'miner home was not reassigned')
 check(miner.ship.cargo.iron_ore==2 and miner.worldRecovery,'miner lost cargo or lacks a return route')
 for _=1,80 do
  if not miner.worldRecovery then break end
  A.advance(miner,(miner.state=='docked' and miner.untilTime or miner.arrive)+.01,u,game)
 end
 check(not miner.worldRecovery and miner.task and miner.task.phase=='mining','reassigned miner never resumed its mining duty')
 for id in pairs(resources) do check(u.mining.resources[id],'station removal deleted a mineral resource') end
 for _,id in ipairs(F.phobos.drillIds) do check(u.mining.sites[id].home==replacement,'mine jobs retain removed source') end
 -- With no home station available, pirates wait safely and retain their loot.
 local pirate=copy(templates.pirate);pirate.id='edit-pirate';pirate.encounter=nil;pirate.task=nil;pirate.piracy=nil
 pirate.area='earth';pirate.home='earth';pirate.homeStation=L.station(nil,'pirateBase')
 pirate.route={F.earth.buoyIds[1],F.earth.buoyIds[2]};pirate.index=2;pirate.state='travel';pirate.depart=u.clock;pirate.arrive=u.clock+100
 pirate.ship.hold=nil;pirate.ship.cargo={scrap=3};pirate.stolenCargo={scrap=3};u.npcs[pirate.id]=pirate
 local oldBase=pirate.homeStation
 ok=game:editWorldLayout(function(world)world.removeStation(oldBase) end)
 u=game.universe;pirate=u.npcs[pirate.id]
 check(ok and pirate.waitingForHome and pirate.ship.cargo.scrap==3,'homeless pirate crashed or lost loot')
 local newBase
 ok,newBase=game:editWorldLayout(function(world)return world.addStation('pluto',{name='New haven',uses={pirateBase=true},position={x=20000,y=8000}}) end)
 u=game.universe;pirate=u.npcs[pirate.id]
 check(ok and pirate.homeStation==newBase and pirate.worldRecovery.target==newBase and not pirate.waitingForHome,'new haven did not recover waiting pirate')
 check(pirate.stolenCargo.scrap==3,'home reassignment lost stolen provenance')
 for _=1,80 do
  if not pirate.worldRecovery then break end
  A.advance(pirate,(pirate.state=='docked' and pirate.untilTime or pirate.arrive)+.01,u,game)
 end
 check(not pirate.worldRecovery and u.piracy.stashes[newBase].scrap==3,'reassigned pirate did not deliver loot to its new base')
 -- Save migration remaps station identity references, never display names.
 local legacy={stations={['earth/orbital_one']={marker=9}},npcs={test={homeStation='earth/orbital_one',route={'earth/orbital_one'}}}}
 local migrated=require('src.world_migration').ids(legacy)
 check(migrated.stations[primary].marker==9 and migrated.npcs.test.homeStation==primary,'legacy station references failed migration')
 check(legacy.npcs.test.homeStation=='earth/orbital_one','migration mutated its input')
 -- Temporarily disabled ports keep their identity and stored inventory.
 ok=game:editWorldLayout(function(world)world.setStationEnabled(port,false) end)
 check(ok and not L.byId[port] and game.universe.stations[port],'disabled station was not removed safely')
 ok=game:editWorldLayout(function(world)world.setStationEnabled(port,true) end)
 check(ok and L.byId[port] and Hold.count(game.universe.stations[port].storage,'scrap')==3,'re-enabled port lost its saved inventory')
 -- An offline ship stays at its existing polar-route pose when an endpoint moves.
 game:captureALife(true);local moving=copy(templates.trader);moving.id='edit-moving-endpoint'
 moving.role='trader';moving.home='earth';moving.area='earth';moving.homeStation=primary;moving.task=nil;moving.taskWorker=nil
 moving.tripRoute=nil;moving.onRoundTrip=nil;moving.tripDestination=nil;moving.encounter=nil;moving.pose=nil;moving.offset=nil
 moving.route={primary,F.earth.buoyIds[1]};moving.index=2;moving.state='travel'
 moving.depart=game.universe.clock-10;moving.arrive=game.universe.clock+10
 game.universe.npcs[moving.id]=moving
 local oldX,oldY=A.point(moving,game.universe.clock)
 ok=game:editWorldLayout(function(world)world.moveStation(primary,'earth',{x=14000,y=18000}) end)
 moving=game.universe.npcs[moving.id]
 local body=game.alifeOnline[moving.id];local newX,newY
 if body then newX,newY=body.body:getPosition() else newX,newY=A.point(moving,game.universe.clock) end
 check(ok and math.abs(newX-oldX)+math.abs(newY-oldY)<.01,('moved pose %.3f,%.3f -> %.3f,%.3f / %s / %s'):format(oldX,oldY,newX,newY,tostring(moving.state),tostring(moving.worldRecovery)))
 -- The special adapter remains explicit but can be removed without dangling
 -- its access points in the shared network or spawning the old geometry.
 local ladder=W.specials.heavenLadder.id
 ok=game:editWorldLayout(function(world)world.removeStation(ladder) end)
 game:loadField('mars')
 check(ok and not L.byId[ladder] and not game.ladder,'disabled special station still spawned its adapter')
 for _,id in ipairs(W.specials.heavenLadder.access) do check(not L.byId[id],'disabled ladder retained an access node') end
 -- Export/import retains the assigned IDs and placements.
 local exported=W.export();check(E.import(game,exported),'exported authoring cannot be imported')
 check(L.get(port).area=='mars' and W.find(port).name=='Renamed port','export/import changed station identity')
 check(E.import(game,definition),'failed to restore original world definition')
 game:loadState(original)
 print(('STATION AUTHORING / REMOVAL TEST PASSED (%d checks)'):format(checks))
end
