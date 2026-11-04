-- One controlled supply chain, with no long flight or physics benchmark.
return function(game)
 local Jobs,M,Tasks,A=require('src.jobs'),require('src.mining'),require('src.tasks'),require('src.alife')
 local Transport,L,Save=require('src.transport'),require('src.locations'),require('src.save')
 local copy=require('src.persistence').copy
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local worker
 for _,r in pairs(game.universe.npcs) do if r.home=='mars' and r.role=='trader' then worker=copy(r);break end end
 assert(worker,'no Mars hauler')
 local function hauler(id)
  local r=copy(worker);r.id=id;r.task=nil;r.taskWorker=true;r.ship.cargo={};r.ship.hold=nil
  r.state='docked';return r
 end
 for _,moon in ipairs(Jobs.mines) do
  local mine=assert(L.station(moon,'mining'))
  local u={npcs={},clock=0,jobs={mines={[moon]={stock=80,clock=0}}}}
  local r=hauler('ore-hauler');u.npcs[r.id]=r
  Transport.seed(u)
  check(not Tasks.choose(u,r,mine,100000),'elapsed time or legacy stock created cargo')
  check(r.taskStatus=='waiting for work','empty strip mine did not leave hauler waiting')
  local miner
  for _,record in pairs(game.universe.npcs) do if record.role=='miner' and record.home==moon then miner=copy(record);break end end
  assert(miner and miner.base==mine,'miner is not based at strip mine')
  miner.id='ore-miner';miner.ship.cargo={iron_ore=12};miner.ship.hold=nil
  u.npcs[miner.id]=miner
  -- Complete the miner's existing duty at its actual strip-mine destination.
  check(Tasks.arrive(u,miner,mine,0),'miner did not unload at strip mine')
  check(Jobs.available(u,mine,Jobs.item)==12 and not miner.ship.cargo.iron_ore,'miner deposit did not conserve ore')
  local t=assert(Tasks.choose(u,r,mine,0))
  check(t.item=='iron_ore' and t.mine==moon and L.get(t.target).area=='mars','hauler chose wrong ore route')
  check(r.ship.cargo.iron_ore==10 and Jobs.available(u,mine,Jobs.item)==2,'pickup did not remove actual stock')
  check(Tasks.choose(u,r,mine,1)==t and Jobs.available(u,mine,Jobs.item)==2,'retry loaded ore twice')
  local other=hauler('ore-competitor');u.npcs[other.id]=other
  check(not Tasks.choose(u,other,mine,1),'competing hauler over-reserved finite stock')
  -- Save a loaded ship, then complete its real offline itinerary to Mars.
  local restored=assert(Save.decode(Save.encode(u)));r=restored.npcs[r.id]
  check(restored.tasks.offers[t.id].owner==r.id and r.ship.cargo.iron_ore==10,'save lost manifest or reservation')
  r.route=assert(Tasks.plan(r,mine,0));r.index=2;r.area=moon;r.depart=0;r.arrive=1;r.state='travel'
  r.encounter=nil;r.piracy=nil;r.offlineLoot=nil;r.worldRecovery=nil;r.pose=nil;r.offset=nil
  for _=1,20 do
   local clock=(r.state=='docked' and r.untilTime or r.arrive)+.01
   A.advance(r,clock,restored)
   if r.lastTask and r.lastTask.id==t.id then break end
  end
  check(r.lastTask and r.lastTask.id==t.id and r.lastTask.status=='completed','offline hauler failed to deliver to Mars')
  check(Jobs.available(restored,t.target,Jobs.item)==10 and (r.ship.cargo.iron_ore or 0)==0,('Mars did not retain delivered ore: stock=%s cargo=%s target=%s'):format(Jobs.available(restored,t.target,Jobs.item),tostring(r.ship.cargo.iron_ore),t.target))
  check(Jobs.available(restored,mine,Jobs.item)+Jobs.available(restored,t.target,Jobs.item)==12,'ore was created or lost in transit')
  check(not Tasks.arrive(restored,r,t.target,restored.clock),'repeated arrival delivered the same shipment twice')
  -- Another loaded shipment lost to a dead hauler must not refill the source.
  Jobs.deliver(u,mine,Jobs.item,8)
  local lost=assert(Tasks.choose(u,other,mine,1));other.state='dead';Tasks.clean(u,2)
  check(Jobs.available(u,mine,Jobs.item)==0 and not u.tasks.delivered,'lost shipment refunded ore or credited Mars')
  check(not u.tasks.offers[lost.id].owner,'death retained the hauling reservation')
 end
 -- Physical dockside handoff: unload, then wait without retaining a second copy.
 game:captureALife(true)
 local r=hauler('physical-ore-hauler');local mine=L.station('phobos','mining')
 local target=L.stations('mars','trade')[1]
 game:loadField('mars');game:captureALife(true)
 local u=game.universe;u.npcs={[r.id]=r};u.tasks=nil
 Transport.seed(u)
 Jobs.stock(u,mine).iron_ore=10
 local t=assert(Tasks.choose(u,r,mine,u.clock))
 target=t.target
 r.area='mars';r.route={target,target};r.index=1;r.node=target;r.untilTime=u.clock+60
 local e=A.wake(game,r);local station=game:locationEntity(target)
 game:dockInstantly(e,station)
 local before=Jobs.available(u,target,Jobs.item)
 -- All outgoing work is temporarily unavailable, so completing delivery waits.
 for _,o in pairs(u.tasks.offers) do if o.id~=t.id then o.readyAt=math.huge end end
 check(not game:traderCanDepart(e,station),'fixture should wait after unloading')
 check((e.cargo.iron_ore or 0)==0 and (r.ship.cargo.iron_ore or 0)==0,'waiting physical ship retained delivered ore')
 check(Jobs.available(u,target,Jobs.item)==before+10,'physical delivery did not stock Mars')
 u.clock=u.clock+11
 check(not game:traderCanDepart(e,station) and Jobs.available(u,target,Jobs.item)==before+10,'waiting dock retry duplicated delivery')
 local snapshot=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(snapshot)
 check(Jobs.available(game.universe,target,Jobs.item)==before+10,'game save/load lost station stock')
 -- Pre-existing placeholder manifests finish without becoming a new ore source.
 local legacy={npcs={},clock=0};Transport.seed(legacy)
 local old=hauler('legacy-hauler');legacy.npcs[old.id]=old
 local offer=Tasks.post(legacy,{kind='transport',source=mine,target=target,item='martian_ore',amount=10,mine='phobos'})
 old.task=copy(offer);old.ship.cargo.martian_ore=10;offer.owner=old.id;offer.state='reserved'
 Transport.seed(legacy)
 check(old.ship.cargo.martian_ore==10 and old.task.id==offer.id,'reconciliation discarded legacy cargo')
 check(Tasks.arrive(legacy,old,target,0) and Jobs.available(legacy,target,'martian_ore')==10,'legacy cargo was lost at delivery')
 check(not Tasks.definitions.transport.eligible(legacy,old,offer,mine,1000),'legacy placeholder ore could be issued again')
 local oldReturn=Tasks.post(legacy,{kind='transport',source=mine,target=target,item='scrap',amount=5})
 check(not Tasks.definitions.transport.eligible(legacy,old,oldReturn,mine,1000),'retired return manifest generated cargo at an empty strip mine')
 print(('ORE LOGISTICS TEST PASSED (%d checks)'):format(checks))
end
