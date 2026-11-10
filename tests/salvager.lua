return function(game)
 require('tests.saved_tasks')()
 local S,A,Tasks=require('src.salvager'),require('src.alife'),require('src.tasks')
 local O,L,G=require('src.offline_loot'),require('src.locations'),require('src.travelgraph')
 local Hold,Ship,AI=require('src.inventory.hold'),require('src.ship'),require('src.ai')
 local Fuel,T,Population=require('src.reactor_fuel'),require('src.tuning'),require('src.population')
 local Save,copy=require('src.save'),require('src.persistence').copy
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true
 local r
 for _,record in pairs(game.universe.npcs) do if record.populationGroup=='salvager' and record.home=='earth' then r=record;break end end
 assert(r,'no initial Earth salvager')
 -- This fixture exercises salvage execution; mixed work selection is covered
 -- by stockpile.lua. Pin the usual work rather than assuming every selection.
 local function onlySalvage(r)
  r.workWeights={salvage=1,transport=0,mine=0,patrol=0}
  if not r.task or r.task.kind~='salvage' then
   local t=r.task
   if t and t.kind=='transport' and t.phase=='delivery' then
    r.ship.cargo[t.item]=math.max(0,(r.ship.cargo[t.item] or 0)-t.amount)
   end
   Tasks.release(game.universe,r,'fixture work',game.universe.clock)
   r.ship.hold=nil;r.state='docked'
   game.universe.clock=game.universe.clock+3 -- allow the shared decision budget to advance
   require('src.npc').decide(game.universe,r,L.station('earth','trade'),game.universe.clock,game)
  end
 end
 onlySalvage(r)
 check(r.task and r.task.kind=='salvage' and game.universe.tasks.offers[r.task.id].owner==r.id,'salvager has no reserved board job')
 local id=r.id;local population=game.universe.nextNpcId
 S.seed(game)
 check(game.universe.nextNpcId==population,'loading board duties duplicated the population')
 local allowed={};for _,area in ipairs(S.system('earth')) do allowed[area]=true end
 for _,node in ipairs(r.route) do check(allowed[L.get(node).area],'salvager left its planet/moon system') end
 -- Two independent workers cannot reserve the same board assignment or pickup.
 local competitor=S.create(game,'earth',L.station('earth','trade'),game.universe.clock)
 onlySalvage(competitor)
 check(competitor.task.id~=r.task.id,'two salvagers reserved one board job')
 game:loadField('venus');game:captureALife(true)
 local u=game.universe;u.npcs={[id]=r,[competitor.id]=competitor};u.populationSpawns={}
 r.ship.hold=nil;r.ship.cargo={[Fuel.item()]=20};r.ship.fuelCharge=0;r.ship.fuelInitialized=true
 r.lootCheckAt=nil;r.action=nil;r.salvageReturn=nil;r.salvageUntil=nil
 r.area='earth';r.state='travel';r.index=2;r.depart=u.clock;r.arrive=u.clock+100;r.pose=nil;r.offset=nil;r.encounter=nil
 local x,y=A.point(r,u.clock)
 u.areas.earth={capturedAt=u.clock,objects={}}
 local Loose=require('src.loose')
 local ground={id='test/991',area='earth',kind='loot',item='water_ice',count=4,x=x,y=y,vx=0,vy=0,spin=0,clock=u.clock}
 Loose.records(u)[ground.id]=ground
 competitor.area='earth';competitor.state='travel';competitor.route=copy(r.route);competitor.index=r.index
 competitor.depart=r.depart;competitor.arrive=r.arrive;competitor.offset=nil;competitor.pose=nil;competitor.lootCheckAt=nil;competitor.action=nil
 check(O.update(game,r,u.clock),'remote salvager did not approach a real saved pickup')
 check(not O.update(game,competitor,u.clock),'remote competitors claimed the same source')
 local collectedAt=u.clock+2
 check(O.update(game,r,collectedAt) and r.ship.cargo.water_ice==4 and r.salvageCargo.water_ice==4,'remote pickup did not transfer finite cargo')
 check(not Loose.records(u)[ground.id],'remote collection left duplicate ground cargo')
 local taskId=r.task.id
 Tasks.release(u,competitor,'fixture ended',u.clock)
 for _,o in pairs(u.tasks.offers) do if not o.owner then o.readyAt=0 end end
 u.npcs[competitor.id]=nil
 u.clock=collectedAt+T.salvagerCollectTime+1
 A.advance(r,u.clock,u,game)
 check(r.salvageReturn and r.task.phase=='selling','loaded salvager did not return to a local market')
 local target=r.salvageGoal
 check(L.get(target).area=='earth','salvager returned to a nonlocal station')
 local market=game:stationMarket({key=target,locationId=target},1);market.hold=game.newShelf()
 local credits=u.credits
 for _=1,20 do
  u.clock=(r.state=='docked' and r.untilTime or r.arrive)+.01
  A.advance(r,u.clock,u,game)
  if r.lastTask and r.lastTask.id==taskId then break end
 end
 check(r.lastTask and r.lastTask.status=='completed','remote sale did not finish its board job')
 check((r.ship.cargo.water_ice or 0)==0 and Hold.count(market.hold,'water_ice')==4,'sold cargo was not moved onto the resale shelf')
 check(r.credits==game.sellPrice({id='water_ice',n=4}) and u.credits==credits,'sale credited the wrong wallet or price')
 local earned=r.credits
 check(S.sell(game,r,target)==0 and r.credits==earned,'repeated unloading duplicated income')
 check((r.ship.cargo[Fuel.item()] or 0)>0 and (r.salvageSales[Fuel.item()] or 0)==0,'salvager sold its own supplies')
 check(r.task and L.get(r.task.target).area=='luna','next board job did not visit a moon')
 for _,node in ipairs(r.route) do check(allowed[L.get(node).area],'moon trip escaped its home system') end
 -- Physical pickup: fly toward an out-of-range item, then exercise the real beam.
 game:loadField('earth');game:captureALife(true);u=game.universe
 r=u.npcs[id];Tasks.release(u,r,'local fixture',u.clock)
 r.salvageVisit=0;r.salvageReturn=nil;r.salvageGoal=target;r.area='earth';r.state='docked';r.lootCheckAt=nil
 r.ship.cargo={[Fuel.item()]=20};r.ship.hold=nil;r.ship.fuelCharge=0;r.power=100
 for _,o in pairs(u.tasks.offers) do if not o.owner then o.readyAt=0 end end
 check(S.depart(game,r,target,u.clock),'local board offered no new collection job')
 A.start(r,u.clock,2)
 local e=A.wake(game,r);game.pickups={}
 local px,py=e.body:getPosition()
 game:spawnPickup(px+e.halfLength+1500,py,'salvage_kit',1)
 local pickup=game.pickups[#game.pickups]
 AI.think(game,e,1/120)
 check(r.action and r.action.operation=='collect' and r.action.target.id==pickup.looseId and not e.intent.tractor and (e.intent.thrust~=0 or e.intent.strafe~=0),'salvager did not physically pursue a distant item')
 check((e.cargo.salvage_kit or 0)==0,'pursuit copied a distant item into cargo')
 pickup.x,pickup.y=px,py
 -- Let the next scheduled movement plan observe the relocated fixture.
 u.clock=u.clock+T.npcControlInterval;game.time=game.time+T.npcControlInterval
 AI.think(game,e,1/120);game:updatePickups(1/120)
 check(e.cargo.salvage_kit==1 and r.salvageCargo.salvage_kit==1 and #game.pickups==0,'beam pickup did not conserve the item')
 local carrying=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(carrying);u=game.universe;r=u.npcs[id]
 e=game.alifeOnline[id] or A.wake(game,r)
 check(r.salvageCargo.salvage_kit==1 and e.cargo.salvage_kit==1,'save/load lost recovered cargo or its sale manifest')
 check(Population.count(u,'earth','salvager')==1,'saved salvager was duplicated')
 A.capture(game,e,false);check(S.returnRecord(game,r),'physical collector had no local return route');A.bindRoute(game,e,r)
 local station=game:locationEntity(r.salvageGoal)
 game:dockInstantly(e,station)
 local shelf=game:stationMarket(station,1).hold;local before=Hold.count(shelf,'salvage_kit')
 local wallet=u.credits;local income=r.credits
 check(game:traderCanDepart(e,station),'docked salvager did not sell and choose another job')
 check((e.cargo.salvage_kit or 0)==0 and Hold.count(shelf,'salvage_kit')==before+1,'physical sale did not move the actual item to station resale')
 check(r.credits==income+game.sellPrice({id='salvage_kit',n=1}) and u.credits==wallet,'physical sale used the player wallet')
 game:traderUndocked(e,station)
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 check(saved.salvage.seeded.earth and saved.npcs[id].credits==r.credits,'save omitted salvager lifecycle or earnings')
 check(saved.tasks.offers[r.task.id].owner==id,'save omitted the next reserved salvage job')
 r.state='dead';Tasks.clean(u,u.clock)
 check(not u.tasks.offers[r.task.id].owner,'dead salvager retained a board reservation')
 require('tests.offline_loot')(game)
 print(('SALVAGER TEST PASSED (%d checks)'):format(checks))
end
