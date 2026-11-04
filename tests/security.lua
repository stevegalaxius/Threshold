return function(game)
 require("tests.npc_repair")(game)
 local A,S,E=require('src.alife'),require('src.security'),require('src.encounters')
 local Tasks,L,G,Fields=require('src.tasks'),require('src.locations'),require('src.travelgraph'),require('src.fields')
 local Save,copy,AI,T=require('src.save'),require('src.persistence').copy,require('src.ai'),require('src.tuning')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function near(a,b)return math.abs(a-b)<.02 end
 game.autosaveOff=true
 local expected=0
 for _,area in ipairs(Fields.list) do
  local f=Fields[area]
  if f.alifeSecurity then expected=expected+f.alifeSecurity.patrol+f.alifeSecurity.pirate end
 end
 local n=0
 local patrol,pirate,trader
 for _,r in pairs(game.universe.npcs) do
  if S.isRole(r) then
   n=n+1
   check(r.task and r.task.kind==(r.role=='patrol' and 'patrol' or 'raid'),'role did not autonomously select its own duty')
   check(not r.taskWorker,'security role was assigned transport dispatch logic')
   for i=2,#r.route do
    local valid=false
    for _,link in ipairs(Fields[r.area].travelLinks) do
     if link[1]==r.route[i-1] and link[2]==r.route[i] or link[2]==r.route[i-1] and link[1]==r.route[i] then valid=true end
    end
    check(valid or r.route[i-1]==r.route[i],'security task invented a navigation edge')
   end
  end
  if r.home=='earth' then
   if r.role=='patrol' then patrol=copy(r) elseif r.role=='pirate' then pirate=copy(r)
   elseif r.role=='trader' and not r.onRoundTrip then trader=copy(r) end
  end
 end
 check(n==expected and n>0,'security population did not seed once across planets')
 local count=game.universe.nextNpcId;A.seed(game)
 check(game.universe.nextNpcId==count,'repeated load replenished patrols or pirates')
 -- Duties reserve separately from transport and complete at actual waypoints.
 local duty=copy(patrol);local u=copy(game.universe);u.npcs[duty.id]=duty
 duty.state='travel';duty.index=#duty.route;duty.arrive=10;duty.encounter=nil
 S.advance(duty,10,u,A.start)
 check((duty.state=='idle' or duty.state=='docked') and duty.node==duty.task.target,'patrol did not inspect its destination')
 local taskId=duty.task.id
 S.advance(duty,duty.untilTime,u,A.start)
 check(duty.lastTask and duty.lastTask.id==taskId and duty.lastTask.status=='completed','completed patrol duty remained reserved')
 check(duty.task and duty.task.id~=taskId,'patrol did not choose its next duty')
 check(duty.role=='patrol','task choice changed fixed archetype')
 -- Isolate actual online combatants from unrelated scenery/traffic.
 game:captureALife(true)
 for i=#game.entities,1,-1 do
  local e=game.entities[i]
  if e~=game.player and (e.kind=='ship' or e.kind=='asteroid' or e.kind=='container' or e.kind=='husk') then game:remove(e) end
 end
 game.sleepers={}
 game.universe.npcs={[patrol.id]=patrol,[pirate.id]=pirate,[trader.id]=trader}
 local clock=game.universe.clock
 local node=Fields.earth.buoyIds[1]
 local x,y=L.position(node,clock)
 for _,r in ipairs({patrol,pirate}) do
  r.state='idle';r.area='earth';r.node=node;r.route={node,node};r.index=1;r.untilTime=clock+1000
  r.pose=nil;r.offset=nil;r.encounter=nil
 end
 -- The trader remains on a valid journey; use exact physical poses here.
 trader.state='travel';trader.area='earth';trader.encounter=nil
 game.player.body:setPosition(x+3000,y)
 local pe=A.wake(game,patrol);local re=A.wake(game,pirate);local te=A.wake(game,trader)
 pe.body:setPosition(x,y);re.body:setPosition(x+1000,y);te.body:setPosition(x+1700,y)
 game.player.body:setPosition(x+500,y+1000)
 check(S.target(game,pe)==re,'patrol did not choose the pirate')
 check(S.target(game,re)==te,'pirate did not prefer actual cargo traffic')
 check(not S.hostile(pe,te) and not S.hostile(pe,game.player),'patrol treated peaceful traffic as hostile')
 AI.think(game,pe,1/120);AI.think(game,re,1/120)
 check(pe.intent.targetDist and re.intent.targetDist,'online roles did not use real combat steering')
 local fired=false
 for _=1,480 do
  game:step(1/120)
  fired=fired or pe.intent.firePrimary or re.intent.firePrimary
  if re.dead or pe.dead then break end
 end
 check(fired,'online roles never fired their fitted weapons')
 -- Friendly patrols defend themselves if the player attacks them.
 pe.dead=false;pe.armor=pe.stats.armor
 game:damage(pe,1,game.player,'test')
 pe.securityThink=nil
 check(S.target(game,pe)==game.player,'patrol ignored an actual attacker')
 pe.aggressor=nil;pe.combatTarget=nil;pe.securityThink=nil
 -- Exact body/cargo/role/duty restoration after saving while online.
 local armor=pe.armor
 local px,py=pe.body:getPosition()
 game.player.body:setPosition(px+3000,py)
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(saved)
 pe=assert(game.alifeOnline[patrol.id]);patrol=game.universe.npcs[patrol.id]
 check(pe.alifeRole=='patrol' and near(pe.armor,armor),'save/load lost patrol identity or damage')
 check(patrol.task and patrol.task.kind=='patrol','save/load lost the selected duty')
 check(near(pe.body:getX(),px) and near(pe.body:getY(),py),'saving a duty teleported its ship')
 -- A patrol without a threat goes back to powered route navigation.
 for id,e in pairs(game.alifeOnline) do if id~=patrol.id then game:remove(e);game.alifeOnline[id]=nil end end
 pe.aggressor=nil;pe.combatTarget=nil;pe.securityThink=nil
 patrol.state='travel';patrol.route={Fields.earth.buoyIds[1],Fields.earth.stationIds[1]};patrol.index=2
 A.bindRoute(game,pe,patrol);pe.body:setLinearVelocity(0,0)
 AI.think(game,pe,1/120)
 check(math.abs(pe.intent.thrust)+math.abs(pe.intent.strafe)>0,'patrol did not resume navigation after combat')
 -- Pure remote dice fights: no flight-path sampling or remote Box2D bodies.
 game:captureALife(true)
 pirate=copy(pirate);trader=copy(trader)
 pirate.id='npc/9001';trader.id='npc/9002'
 local edge={Fields.earth.buoyIds[1],Fields.earth.stationIds[1]}
 for _,r in ipairs({pirate,trader}) do
  r.state='travel';r.area='earth';r.route=copy(edge);r.index=2;r.depart=0;r.arrive=1000;r.encounter=nil;r.retreatUntil=nil;r.offset=nil;r.pose=nil
  r.ship.armor=require('src.stats').compute(require('src.data').hulls[r.ship.hull],r.ship.loadout).armor
 end
 local remote={npcs={[pirate.id]=pirate,[trader.id]=trader},clock=500,tasks={offers={},nextId=0}}
 local fixture={universe=remote,alifeOnline={}}
 local bodies=game.world:getBodyCount();local point=G.point
 G.point=function()error('remote fight sampled a physical path')end
 E.update(fixture,500)
 check(pirate.encounter and trader.encounter,'same-segment traffic never encountered the pirate')
 local ammo=pirate.ship.cargo.rounds_s
 local hp=trader.ship.armor
 E.update(fixture,504)
 check(trader.ship.armor<hp and pirate.ship.cargo.rounds_s<ammo,'offline exchange failed to damage hull or consume ammo')
 check(game.world:getBodyCount()==bodies,'offline combat created physics bodies')
 local after=trader.ship.armor;E.update(fixture,504)
 check(trader.ship.armor==after,'forced sync applied a combat round twice')
 -- Save a fight and prove its next roll is reproducible.
 local twin=assert(Save.decode(Save.encode(remote)))
 E.update(fixture,508);E.update({universe=twin,alifeOnline={}},508)
 check(near(trader.ship.armor,twin.npcs[trader.id].ship.armor),'save/load changed an encounter roll')
 -- Online/mixed encounters must never take abstract damage.
 local onlineHP=trader.ship.armor
 fixture.alifeOnline[pirate.id]={}
 E.update(fixture,512)
 check(trader.ship.armor==onlineHP,'offline dice damaged a ship fighting a live counterpart')
 fixture.alifeOnline={}
 G.point=point
 -- Approaching an abstract fight brings in its actual counterpart and
 -- releases both graph duties to ordinary physical AI.
 local handPirate,handTrader=copy(pirate),copy(trader)
 handPirate.id,handTrader.id='npc/9101','npc/9102'
 for _,r in ipairs({handPirate,handTrader}) do
  r.state='travel';r.encounter=nil;r.offset=nil;r.pose=nil
  r.depart=game.universe.clock-500;r.arrive=game.universe.clock+500
 end
 local population=game.universe.npcs
 game.universe.npcs={[handPirate.id]=handPirate,[handTrader.id]=handTrader}
 E.begin(handPirate,handTrader,game.universe.clock)
 local hx,hy=A.point(handPirate,game.universe.clock)
 game.player.body:setPosition(hx+1000,hy)
 local livePirate=A.wake(game,handPirate)
 E.syncOnline(game)
 local liveTrader=game.alifeOnline[handTrader.id]
 check(liveTrader and liveTrader.aggressor==livePirate,'approaching fight did not hand both participants to physical AI')
 check(not handPirate.encounter and not handTrader.encounter,'physical takeover left graph duties frozen')
 game:captureALife(true);game.universe.npcs=population
 -- Deterministic lethal fixture produces one persistent salvage record.
 pirate.ship.armor=10000;pirate.ship.cargo.rounds_s=1000
 trader.ship.armor=.001;trader.ship.cargo={}
 for _,r in ipairs({pirate,trader}) do r.state='travel';r.encounter=nil;r.retreatUntil=nil end
 remote.alifeWrecks={};remote.encounterNext=516
 E.begin(pirate,trader,512);E.update(fixture,516)
 check(trader.state=='dead' and remote.alifeWrecks[trader.id],'offline death did not leave a wreck record')
 E.update(fixture,520)
 local wrecks=0;for _ in pairs(remote.alifeWrecks) do wrecks=wrecks+1 end
 check(wrecks==1,'dead record generated repeated wrecks')
 G.point=point
 -- Pending remote salvage survives save/load, materializes once, then uses
 -- ordinary area persistence instead of respawning on a later visit.
 game.universe.npcs=remote.npcs;game.universe.alifeWrecks=remote.alifeWrecks
 local w=remote.alifeWrecks[trader.id]
 x,y=G.point(G.build('earth'),{from=w.from,to=w.to},w.progress,game.universe.clock)
 game.player.body:setPosition(x+1000,y)
 local before=0;for _,e in ipairs(game.entities) do if e.kind=='husk' then before=before+1 end end
 E.materialize(game,x+1000,y,game.universe.clock)
 local afterWreck=0;for _,e in ipairs(game.entities) do if e.kind=='husk' then afterWreck=afterWreck+1 end end
 check(afterWreck==before+1 and not next(game.universe.alifeWrecks),'salvage failed to materialize once near the player')
 E.materialize(game,x+1000,y,game.universe.clock)
 local again=0;for _,e in ipairs(game.entities) do if e.kind=='husk' then again=again+1 end end
 check(again==afterWreck,'pending salvage materialized twice')
 local final=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(final)
 local restored=0;for _,e in ipairs(game.entities) do if e.kind=='husk' then restored=restored+1 end end
 check(restored==afterWreck,'materialized wreck was lost or duplicated in a save')
 require('tests.patrol_docking')(game)
 print(('SECURITY A-LIFE TEST PASSED (%d checks; %d persistent security NPCs)'):format(checks,expected))
end
