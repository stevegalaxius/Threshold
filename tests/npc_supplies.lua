return function(game)
 local S,L,A=require('src.supplies'),require('src.locations'),require('src.alife')
 local Hold,Ship,Tasks=require('src.inventory.hold'),require('src.ship'),require('src.tasks')
 local Fields,data,Save=require('src.fields'),require('src.data'),require('src.save')
 local copy=require('src.persistence').copy;local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true;game:loadField('earth');game:captureALife(true)
 local original=game:saveState();local u=game.universe
 local st=game:locationEntity(L.station('earth','trade'));local index,shop
 for _,area in ipairs(Fields.list) do for _,place in ipairs(L.list(area)) do
  if place.kind=='station' then check(S.supports(place.id),'current station lacks Supplies: '..place.id) end
 end end
 for i,vendor in ipairs(game.marketShops(st)) do if vendor.id=='supplies' then index,shop=i,vendor end end
 check(index and shop.name=='Supplies','Supplies missing from existing shop selector')
 local shelf=game:stationMarket(st,index)
 for _,entry in ipairs(shop.sells) do check(Hold.count(shelf.hold,entry[1])>0,'Supplies shelf omitted '..entry[1]) end
 local cap=data.items.rounds_s.stack
 Hold.take(shelf.hold,'rounds_s',100000);shelf.next.rounds_s=u.clock+100000
 game:shopTick(st,index,shop)
 check(Hold.count(shelf.hold,'rounds_s')==cap,'Supplies waits for finite restock')
 Hold.take(shelf.hold,'rounds_s',cap);game:shopTick(st,index,shop,{rounds_s=cap})
 check(Hold.count(shelf.hold,'rounds_s')==0,'staged stock was duplicated')
 game:shopTick(st,index,shop)
 check(Hold.count(shelf.hold,'rounds_s')==cap,'returned stock availability failed')
 -- Player purchases use ordinary prices and the existing grid settlement.
 game:setShop(st,index);game.player.hold=Hold.new({{key='hold',w=8,h=4}});game.player.cargo={};Ship.updateMass(game.player)
 u.credits=10000
 local trade=Hold.new({{key='offer',w=8,h=4}})
 Hold.take(shelf.hold,'rounds_s',5);Hold.placeStack(trade,{id='rounds_s',n=5,owner='station'})
 check(game:completeTrade(st,trade),'Supplies could not settle a normal grid purchase')
 check(game.player.cargo.rounds_s==5 and game:credits()==10000-data.items.rounds_s.price*5,'player purchase bypassed normal inventory or pricing')
 local credits=game:credits();local template
 for _,r in pairs(u.npcs) do if r.role=='patrol' then template=copy(r);break end end
 assert(template)
 -- Supply targets derive from fitted weapons and archetype reserves for all roles.
 for _,role in ipairs({'trader','courier','miner','patrol','pirate'}) do
  local r=copy(template);r.role=role;r.ship.hold=nil;r.ship.cargo={rounds_s=1,scrap=2}
  local target=S.targets(r).rounds_s
  check(target==400 and S.needs(r),role..' did not detect its low fitted-weapon ammo')
  S.refill(r,st.locationId)
  check(r.ship.cargo.rounds_s==target and r.ship.cargo.scrap==2,role..' resupply lost cargo or missed its reserve')
  check(S.refill(r,st.locationId)==0,role..' repeated supply created extra ammo')
 end
 local miner
 for _,r in pairs(u.npcs) do if r.role=='miner' then miner=r;break end end
 check(miner and not next(S.targets(miner)) and not S.needs(miner),'power-only drills demand ammunition')
 local custom=copy(template);custom.ship.hold=nil;custom.ship.cargo={rounds_s=0};custom.ammoReserve={rounds_s=20}
 S.refill(custom,st.locationId);check(custom.ship.cargo.rounds_s==20,'explicit variant reserve was ignored')
 -- Fresh ammo must not become stolen cargo when topping up a pirate hold.
 local r=copy(template);r.role='pirate';r.homeStation=st.locationId
 local h=Hold.new({{key='cargo',w=12,h=8}});local inner=Hold.new({{key='inner',w=2,h=2}});Hold.add(inner,'scrap',2)
 check(Hold.placeStack(h,{id='cargo_container',n=1,inner=inner}),'container fixture did not fit')
 Hold.placeStack(h,{id='rounds_s',n=2,stolen=true})
 r.ship.hold=Hold.serialize(h);r.ship.cargo=Hold.totals(h);r.stolenCargo={rounds_s=2}
 r.piracy={phase='escape',base=st.locationId,origin=Fields.earth.buoyIds[1]}
 S.refill(r,st.locationId)
 local supplied=Hold.deserialize(r.ship.hold);local marked,contents
 for _,g in ipairs(supplied.grids) do for _,stack in ipairs(g.stacks) do
  if stack.stolen then marked=stack.n end
  if stack.inner then contents=Hold.count(stack.inner,'scrap') end
 end end
 check(marked==2 and contents==2,'resupply changed provenance or a loaded container')
 require('src.piracy').depart(u,r,u.clock,A.start)
 check(u.piracy.stashes[st.locationId].rounds_s==2 and r.ship.cargo.rounds_s==400,'pirate restocking manufactured stolen cargo or left it under-supplied')
 -- A full hold does not discard freight to make room for ammo.
 r=copy(template);r.ship.hold=Hold.serialize(Hold.new({{key='tiny',w=1,h=1}}))
 local tiny=Hold.deserialize(r.ship.hold);Hold.add(tiny,'salvage_kit',1);r.ship.hold=Hold.serialize(tiny);r.ship.cargo=Hold.totals(tiny)
 check(not S.needs(r) and S.refill(r,st.locationId)==0 and r.ship.cargo.salvage_kit==1,'resupply displaced freight from a full hold')
 -- Low ammo makes an otherwise healthy patrol choose a docking visit.
 r=copy(template);r.ship.hold=nil;r.ship.cargo={rounds_s=1};r.patrolStationVisits=0
 local duty={kind='patrol',source=Fields.earth.buoyIds[1],target=st.locationId,duration=10}
 Tasks.definitions.patrol.prepare(u,r,duty)
 check(duty.dock and duty.phase=='resupply visit','low ammo did not trigger patrol docking')
 -- Ordinary offline dock arrivals receive the same supply service.
 local civilian=copy(template);civilian.role='trader';civilian.home='earth';civilian.area='earth'
 civilian.ship.hold=nil;civilian.ship.cargo={rounds_s=0};civilian.task=nil;civilian.taskWorker=nil;civilian.onRoundTrip=nil
 civilian.encounter=nil;civilian.route={Fields.earth.buoyIds[1],st.locationId};civilian.index=2;civilian.state='travel';civilian.arrive=u.clock
 A.advance(civilian,u.clock,u,game)
 check(civilian.state=='docked' and civilian.ship.cargo.rounds_s==400,'offline civilian dock stop did not replenish ammo')
 -- A healthy, empty pirate returns to its haven and resumes its raid loop armed.
 local pirate
 for _,record in pairs(u.npcs) do if record.role=='pirate' and record.home=='earth' then pirate=copy(record);break end end
 assert(pirate);pirate.id='supply-return-pirate';pirate.encounter=nil;pirate.task=nil;pirate.piracy=nil
 pirate.ship.hold=nil;pirate.ship.cargo={};pirate.stolenCargo={};pirate.state='idle'
 pirate.node=Fields.earth.buoyIds[1];pirate.route={pirate.node,pirate.node};pirate.index=1;u.npcs[pirate.id]=pirate
 A.advance(pirate,u.clock,u,game)
 check(pirate.piracy and pirate.piracy.phase=='escape','empty pirate did not seek supplies')
 for _=1,80 do
  if pirate.piracy and pirate.piracy.phase=='redeploy' then break end
  A.advance(pirate,pirate.state=='docked' and pirate.untilTime or pirate.arrive,u,game)
 end
 check(pirate.ship.cargo.rounds_s==300 and pirate.piracy.phase=='redeploy','pirate did not replenish before redeployment')
 -- An armed mining variant interrupts mining and retains its empty-load job.
 local worker=copy(miner);worker.id='supply-return-miner';worker.encounter=nil;worker.savedOnline=nil
 worker.ship.loadout[1]='rk7_autocannon';worker.ship.hold=nil;worker.ship.cargo={}
 worker.task.phase='mining';worker.state='idle';local job=worker.task.id
 local Mining=require('src.mining');Mining.advance(game,worker,u.clock)
 check(worker.repairReturn and worker.task.phase=='delivery','armed miner did not return for supplies')
 Mining.advance(game,worker,worker.arrive);Mining.advance(game,worker,worker.untilTime)
 check(worker.ship.cargo.rounds_m>0 and worker.task.id==job and worker.task.phase=='mining','armed miner failed to resupply and resume its reserved job')
 -- Physical resupply only occurs after docking finishes, updates mass and saves.
 r=copy(template);r.id='supplies-physical';r.home='earth';r.area='earth';r.task=nil;r.encounter=nil;r.piracy=nil
 r.worldRecovery=nil;r.ship.hold=nil;r.ship.cargo={rounds_s=1,scrap=2}
 r.state='docked';r.node=st.locationId;r.route={st.locationId,st.locationId};r.index=2;r.untilTime=u.clock+30;r.pose=nil;r.docking=nil
 u.npcs[r.id]=r
 local e=A.wake(game,r);check(e.dockState~=nil,'supply fixture did not dock')
 e.dockState.done=false;S.online(game,e)
 check(e.cargo.rounds_s==1,'tractor approach supplied ammunition')
 e.dockState.done=true;local mass=e.body:getMass();S.online(game,e)
 check(e.cargo.rounds_s==400 and e.body:getMass()>mass and r.ship.cargo.rounds_s==400,'physical supply failed to update ammo, saved record or mass')
 local state=assert(Save.decode(Save.encode(game:saveState())));game:loadState(state)
 r=game.universe.npcs[r.id];e=game.alifeOnline[r.id] or A.wake(game,r)
 S.online(game,e);check(e.cargo.rounds_s==400,'reload supplied the same stop twice')
 check(game:credits()==credits,'NPC resupply charged player credits')
 game:loadState(original)
 print(('NPC SUPPLIES / MARKET VENDOR TEST PASSED (%d checks)'):format(checks))
end
