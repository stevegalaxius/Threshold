return function(game)
 local pirateBase=require('src.locations').station(nil,'pirateBase')
 local A,P,AI=require('src.alife'),require('src.piracy'),require('src.ai')
 local T,L=require('src.tuning'),require('src.locations')
 local Save=require('src.save');local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true;game:loadField('earth');game:captureALife(true)
 local r
 for _,npc in pairs(game.universe.npcs) do if npc.role=='pirate' and npc.area=='earth' then r=npc;break end end
 assert(r)
 for _,area in ipairs({'phobos','deimos'}) do
  local home=require('src.fields')[area].stationIds[1]
  local out,back=P.route(home,pirateBase,game.universe.clock),P.route(pirateBase,home,game.universe.clock)
  check(out and back and out[#out]==pirateBase and back[#back]==home,'pirate base routing failed for '..area)
  for _,path in ipairs({out,back}) do for i=2,#path do
   if L.get(path[i-1]).area~=L.get(path[i]).area then check(require('src.travelgraph').transit(path[i-1],path[i],game.universe.clock)~=nil,'invented inter-region pirate route') end
  end end
 end
 local identity,hull=r.id,r.ship.hull
 local e=A.wake(game,r);check(e~=nil,'pirate did not materialize')
 game.pickups={}
 local x,y=e.body:getPosition();game:spawnPickup(x,y,'scrap',3)
 local pickup=game.pickups[1]
 P.think(game,e,1/60,AI)
 check(e.tractorTarget==pickup and pickup.collector==e,'pirate did not claim real exposed cargo')
 local before=e.cargo.scrap or 0
 check(require('src.tractor').pull(game,e,pickup,1/60),'tractor did not consume real cargo')
 check(e.cargo.scrap==before+3 and pickup.count==0,'pickup cargo did not transfer exactly once')
 check(r.stolenCargo.scrap==3,'stolen cargo ledger missing')
 game.pickups={};game.universe.clock=r.lootUntil+1
 P.think(game,e,1/60,AI)
 check(r.piracy and r.piracy.phase=='escape' and r.route[#r.route]==pirateBase,'loaded pirate did not plan its escape to Milliways')
 check(r.id==identity and r.ship.hull==hull,'piracy replaced the existing NPC')
 A.detach(game,e)
 -- The same route crosses driver lanes without remote physics.
 for _=1,80 do
  if r.state=='docked' then break end
  A.advance(r,r.arrive,game.universe,game)
 end
 check(r.state=='docked' and r.route[r.index]==pirateBase,'remote pirate never reached Milliways: '..r.state..' '..r.index..' '..tostring(r.encounter))
 check(not game.universe.piracy,'cargo unloaded before arrival/rest')
 A.advance(r,r.untilTime,game.universe,game)
 check(game.universe.piracy.stashes[pirateBase].scrap==3,'stolen cargo not deposited in persistent stash')
 check(not r.ship.cargo.scrap or r.ship.cargo.scrap==before,'unload removed unrelated cargo or left stolen cargo aboard')
 check(r.piracy.phase=='redeploy','pirate did not redeploy after unloading')
 P.unload(game.universe,r)
 check(game.universe.piracy.stashes[pirateBase].scrap==3,'repeated unload duplicated loot')
 local state=assert(Save.decode(Save.encode(game:saveState())))
 check(state.piracy.stashes[pirateBase].scrap==3 and state.npcs[identity].piracy.phase=='redeploy','save lost stash or return duty')
 for _=1,80 do
  if not r.piracy then break end
  A.advance(r,r.state=='docked' and r.untilTime or r.arrive,game.universe,game)
 end
 check(not r.piracy and not r.taskWorker and r.area=='earth','pirate did not resume its existing raid role at home')
 game:loadState(state)
 check(game.universe.piracy.stashes[pirateBase].scrap==3,'load lost pirate stash')
 -- Exercise the real physical station clamp and departure handoff too.
 game:captureALife(true)
 r=game.universe.npcs[identity]
 r.piracy={phase='escape',origin='station:007'};r.taskWorker=true
 r.ship.hold=nil;r.ship.cargo.scrap=2;r.stolenCargo={scrap=2}
 r.area='pluto';r.state='docked';r.route={pirateBase,pirateBase};r.index=2
 r.untilTime=game.universe.clock+30;r.encounter=nil
 game:loadField('pluto')
 local physical=game.alifeOnline[identity] or A.wake(game,r)
 check(physical.dockState and physical.dockState.station.locationId==pirateBase,'physical pirate did not dock at Milliways')
 physical.dockState.t=1000
 game:updateDockedShip(physical,1/60)
 check(not physical.dockState and r.piracy.phase=='redeploy','physical unloading did not release pirate onto return route')
 check((physical.cargo.scrap or 0)==0 and game.universe.piracy.stashes[pirateBase].scrap==5,'physical unloading lost or duplicated cargo')
 require('tests.pirate_containers')(game)
 require('tests.offline_loot')(game)
 print(('PIRACY TEST PASSED (%d checks)'):format(checks))
end
