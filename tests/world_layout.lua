-- Change the world definition, then exercise the ordinary consumers unchanged.
return function(game)
 local W,L,F=require('src.world_layout'),require('src.locations'),require('src.fields')
 local G,H,A=require('src.travelgraph'),require('src.npc_home'),require('src.alife')
 local Tasks,Transport,S=require('src.tasks'),require('src.transport'),require('src.security')
 local Save,copy=require('src.save'),require('src.persistence').copy
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local oldStations,oldNav=W.stations.earth,W.navigation.earth
 local home=L.station('earth','trade');local base=L.station(nil,'pirateBase')
 local u={clock=0,nextNpcId=0,npcs={}}
 Transport.seed(u)
 local trader=A.createTrader({universe=u},'earth',1);trader.taskWorker=true
 trader.ship.cargo={};trader.ship.hold=nil
 local duty=assert(Tasks.choose(u,trader,home,0))
 local taskId=duty.id;local amount=trader.ship.cargo.scrap
 -- A third station, four navigation buoys, a different model, reordered ports.
 W.stations.earth={copy(oldStations[2]),copy(oldStations[1]),
  {id='layout_test_port',name='Layout test port',layout='shipyard_1',marketId=home,phase=1.4,uses={mining=true}}}
 W.navigation.earth={buoys=4}
 local bodies=game.world:getBodyCount()
 L.rebuild('earth')
 check(game.world:getBodyCount()==bodies,'catalogue rebuild constructed physics')
 check(#F.earth.stationIds==3 and #F.earth.buoyIds==4,'world definition did not produce the configured nodes')
 check(L.station('earth','trade')==home and H.get(trader)==home,'reordering ports changed home selection')
 local added='earth/layout_test_port';local graph=G.build('earth')
 for _,from in ipairs(F.earth.stationIds) do for _,to in ipairs(F.earth.buoyIds) do
  check(G.route(graph,from,to,0)~=nil,'new station/buoy is not reachable')
 end end
 check(Transport.route(home,'mars/station_alpha',0)~=nil,'expanded layout broke interplanetary travel')
 local circuit={};for _,id in ipairs(F.earth.traderRoute) do circuit[id]=true end
 check(circuit[added],'new trading station omitted from local circuit')
 local live=L.spawnStation(game,added)
 check(live.def==L.stationDefinition(added) and live.def.id=='shipyard_1','physical model differs from shared definition')
 check(game.stationServices(live).repair==L.stationServices(added).repair,'physical/offline services differ')
 check(game.marketDefinition(live)==game.marketDefinition(game:locationEntity(home)),'configured market catalogue did not follow station definition')
 game:remove(live)
 -- Reconcile a saved board: existing work/cargo stays reserved; new ports get work.
 Transport.seed(u)
 check(trader.task.id==taskId and u.tasks.offers[taskId].owner==trader.id,'world change discarded a reservation')
 check(trader.ship.cargo.scrap==amount,'world reconciliation loaded a manifest twice')
 local inbound,outbound=false,false
 for _,o in pairs(u.tasks.offers) do
  inbound=inbound or o.target==added;outbound=outbound or o.source==added
 end
 check(inbound and outbound,'new port did not receive dispatch work in both directions')
 S.ensurePatrols(u,'earth');S.ensureRaids(u,'earth')
 local visit=false;local raids=0
 for _,o in pairs(u.tasks.offers) do
  visit=visit or o.kind=='patrol' and o.target==added
  if o.kind=='raid' and L.get(o.source).area=='earth' then
   raids=raids+1
   local path=assert(G.route(graph,o.source,o.target,0))
   check(#path.legs>0,'pirate duty did not move between buoys')
  end
 end
 check(visit and raids==8,'patrols/raids did not adapt to expanded topology')
 -- Membership is saved on each ship. A home may be outside its hunting region.
 H.assign(trader,added)
 local pirate=copy(trader);pirate.id='home-pirate';pirate.role='pirate';pirate.homeStation=nil;pirate.tradeHome=nil
 u.npcs[pirate.id]=pirate;check(H.get(pirate)==base,'pirate home was assigned to its hunting port')
 local dead=copy(trader);dead.id='dead-resident';dead.state='dead';u.npcs[dead.id]=dead
 local residents=H.residents(u,added)
 check(#residents==1 and residents[1].id==trader.id,'resident roster included visitors/dead ships')
 local saved=assert(Save.decode(Save.encode(u)))
 check(saved.npcs[trader.id].homeStation==added,'save lost home station')
 -- Reordering buoys with explicit bearings must not change their connectivity.
 local links={};for _,pair in ipairs(F.earth.raidLinks) do links[pair[1]..'>'..pair[2]]=true end
 local specs={}
 for i,id in ipairs(F.earth.buoyIds) do specs[i]={id=id:match('[^/]+$'),phase=L.get(id).motion.phase} end
 W.navigation.earth={buoys={specs[3],specs[1],specs[4],specs[2]}}
 L.rebuild('earth')
 check(H.get(saved.npcs[trader.id])==added,'saved home followed buoy/port ordering')
 for _,pair in ipairs(F.earth.raidLinks) do check(links[pair[1]..'>'..pair[2]],'buoy array order changed perimeter duties') end
 W.stations.earth[3].motion={type='fixed',x=26000,y=6000};L.rebuild('earth')
 local edges={}
 for _,pair in ipairs(F.earth.travelLinks) do edges[pair[1]..'>'..pair[2]]=true;edges[pair[2]..'>'..pair[1]]=true end
 local found=false
 for i,id in ipairs(F.earth.traderRoute) do
  found=found or id==added
  check(edges[id..'>'..F.earth.traderRoute[i%#F.earth.traderRoute+1]],'local trading circuit skips a connection at a stationary spur')
 end
 check(found,'stationary trading port was omitted from local circuit')
 -- Restore authoring, not any test-generated tasks, to the running game.
 W.stations.earth,W.navigation.earth=oldStations,oldNav;L.rebuild('earth')
 for _,r in pairs(game.universe.npcs) do
  local station=H.get(r)
  check(station and L.get(station).kind=='station','persistent NPC has no valid home station')
 end
 print(('MODULAR WORLD / NPC HOMES TEST PASSED (%d checks)'):format(checks))
end
