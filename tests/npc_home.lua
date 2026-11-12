-- Distributed persistent homes and the shared controller's idle-home policy.
return function(game)
 local H,N,L,G=require('src.npc_home'),require('src.npc'),require('src.locations'),require('src.travelgraph')
 local data=require('src.data');local copy=require('src.persistence').copy
 local Room,Upkeep,Queue=require('src.dock_room'),require('src.upkeep'),require('src.queue')
 local node=require('src.fields').earth.buoyIds[1]
 local function resident(id)
  local hull=data.hulls.intaki_wisp;local stats=require('src.stats').compute(hull,hull.loadout)
  return {id=id,home='earth',area='earth',homePurpose='trade',node=node,route={node,node},index=1,
   state='idle',untilTime=0,speed=600,power=stats.powerCap,
   ship={hull=hull.id,loadout=copy(hull.loadout),cargo={deuterium_canister=30},armor=stats.armor,fuelInitialized=true}}
 end
 local u={clock=0,npcs={}};local counts={}
 for i=1,9 do
  local r=resident('home/'..i);u.npcs[r.id]=r
  local home=assert(H.choose(u,r));counts[home]=(counts[home] or 0)+1
 end
 local stations=L.stations('earth');assert(#stations==3)
 for _,id in ipairs(stations) do assert(counts[id]==3,'home distribution concentrated residents at '..id) end
 local capacity=Room.capacity;Room.capacity=function(id,hull)return id==stations[1] and 0 or capacity(id,hull)end
 local unsuitable=H.choose({clock=0,npcs={}},resident('too-large'))
 Room.capacity=capacity
 assert(unsuitable and unsuitable~=stations[1],'home assignment ignored hull parking suitability')
 for _,r in pairs(u.npcs) do r.homeDistributed=nil;r.homeStation=stations[1] end
 H.seed(u);counts={}
 for _,r in pairs(u.npcs) do counts[r.homeStation]=(counts[r.homeStation] or 0)+1 end
 for _,id in ipairs(stations) do assert(counts[id]==3,'existing homes were not distributed once') end
 local Save=require('src.save');local saved=assert(Save.decode(Save.encode(u)))
 H.seed(saved)
 for id,r in pairs(u.npcs) do assert(saved.npcs[id].homeStation==r.homeStation,'saved home changed on reload') end
 local anchors=require('src.fields').mars.ladderIds
 local exact=assert(G.itinerary(anchors[2],anchors[1],0,true))
 assert(#exact>1 and exact[1]==anchors[2] and exact[#exact]==anchors[1],'home trip silently chose another Ladder anchor')
 local busy=resident('home-busy');busy.stuckSince=0;busy.task={kind='home_test'}
 N.runActions({r=busy,u=u,clock=100})
 assert(busy.stuckSince==nil,'idle timer included time spent doing a job')
 local r=resident('home-idle');r.homeStation=stations[1];r.homeDistributed=true
 u={clock=0,npcs={[r.id]=r}}
 local scene=setmetatable({universe=u,alifeOnline={}},{__index=game})
 local nextJob,complete,service,oldUniverse=N.controller.next,N.controller.complete,Upkeep.plan,Queue.universe
 N.controller.next=function()end;N.controller.complete=function()end;Upkeep.plan=function()return false end;Queue.universe=u
 N.decide(u,r,node,0,scene);u.clock=50;N.decide(u,r,node,50,scene)
 assert(r.state=='idle','NPC returned home before its idle grace period')
 u.clock=60;N.decide(u,r,node,60,scene)
 assert(r.state=='travel' and r.route[#r.route]==r.homeStation,'jobless NPC did not return home after 60 seconds')
 u.clock=120;N.arrive(r,r.homeStation,120,u,scene)
 u.clock=200;N.decide(u,r,r.homeStation,200,scene)
 u.clock=300;N.decide(u,r,r.homeStation,300,scene)
 assert(r.state=='docked' and r.taskStatus=='idle at home','NPC left home to wander without a job')
 local occupants={}
 for i=1,Room.capacity(r.homeStation,r.ship.hull) do
  local id='home-occupant/'..i;occupants[#occupants+1]=id
  u.npcs[id]={id=id,state='docked',node=r.homeStation,ship={hull=r.ship.hull}}
 end
 r.state='idle';r.action=nil;r.untilTime=0;r.nextDecisionAt=nil
 u.clock=400;N.decide(u,r,r.homeStation,400,scene)
 assert(r.state=='idle' and r.waitingHomeBerth,'full home was treated as docked')
 for _,id in ipairs(occupants) do u.npcs[id]=nil end
 u.clock=420;N.decide(u,r,r.homeStation,420,scene)
 assert(r.state=='docked' and not r.waitingHomeBerth,'NPC did not use newly freed home parking')
 N.controller.next=function(c)return {route=G.itinerary(c.node,node,c.clock,true),wait=0}end
 r.action=nil;u.clock=500;N.decide(u,r,r.homeStation,500,scene)
 assert(r.state=='travel' and r.route[#r.route]==node,'parked NPC did not resume available work')
 N.controller.next,N.controller.complete,Upkeep.plan,Queue.universe=nextJob,complete,service,oldUniverse
 print('NPC HOMES: balanced suitable homes, saved assignments, exact anchors, idle returns, parking waits and resumed work passed')
end
