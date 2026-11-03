return function(game)
 local M,A,T=require('src.mining'),require('src.alife'),require('src.tuning')
 local Save,copy=require('src.save'),require('src.persistence').copy
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local function count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
 game.autosaveOff=true;T.dev.god=true
 local miners=0
 for _,r in pairs(game.universe.npcs) do if M.isMiner(r) then miners=miners+1;check(r.task and r.task.kind=='mine','miner has no autonomous duty') end end
 check(miners==8,'mining population missing or seeded in instance levels')
 local before=game.universe.nextNpcId;A.seed(game)
 check(game.universe.nextNpcId==before,'visiting a region duplicated its miners')
 local area=os.getenv('THRESHOLD_MINING_AREA') or 'ring'
 game:loadField(area);game:captureALife(true)
 local r,second
 for _,record in pairs(game.universe.npcs)do if record.home==area and M.isMiner(record) then r=record;break end end
 assert(r)
 if os.getenv('THRESHOLD_MINING_WORKERS')=='2' then
  for id,record in pairs(game.universe.npcs)do if record.home==area and M.isMiner(record) and id~=r.id then second=record;break end end
 end
 game.universe.npcs={[r.id]=r};if second then game.universe.npcs[second.id]=second end
 game.universe.pirateSpawns={} 
 for i=#game.entities,1,-1 do
  local e=game.entities[i]
  if e~=game.player and (e.kind=='ship' or e.kind=='asteroid' and not e.giant or e.kind=='husk' or e.kind=='container') then game:remove(e) end
 end
 game.sleepers={};game.miningLive={};M.state(game.universe).resources={}
 local site=M.state(game.universe).sites[r.task.target]
 for _,s in pairs(M.state(game.universe).sites)do s.nextAt=game.universe.clock+100000 end
 site.nextAt=game.universe.clock
 local x,y=M.workPoint(site)
 game.player.body:setPosition(x+1800,y);game.player.body:setLinearVelocity(0,0)
 game.miningNext=nil;M.update(game)
 check(count(M.state(game.universe).resources)==T.drillBatch,'drill did not eject its timed batch')
 local physical=0
 for _,e in ipairs(game.entities)do if e.miningId then physical=physical+1 end end
 check(physical==T.drillBatch,'drill batch did not become physical rocks')
 do
  local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
  local cx,cy,zoom=game.camera.x,game.camera.y,game.camera.zoom
  game.camera.x,game.camera.y,game.camera.zoom=x,y,.5
  love.graphics.push('all');love.graphics.setCanvas(canvas)
  require('src.render').world(game)
  love.graphics.setCanvas();love.graphics.pop()
  canvas:newImageData():encode('png','drill-site-'..area..'.png');canvas:release()
  game.camera.x,game.camera.y,game.camera.zoom=cx,cy,zoom
 end
 local e=A.wake(game,r)
 if second then A.wake(game,second) end
 local fired,looted,delivered,shot=false,false,false,false
 for step=1,72000 do
  local ex,ey=e.body:getPosition();game.player.body:setPosition(ex+1800,ey);game.player.body:setLinearVelocity(0,0)
  game:step(1/120);game:frame(1/120,ex+2000,ey)
  if e.dead then error('miner died while working its drill site') end
  for _,weapon in ipairs(e.weapons)do fired=fired or weapon.drillHit~=nil end
  if fired and not shot then
   local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
   local cx,cy,zoom=game.camera.x,game.camera.y,game.camera.zoom
   game.camera.x,game.camera.y,game.camera.zoom=ex,ey,.9
   love.graphics.push('all');love.graphics.setCanvas(canvas)
   require('src.render').world(game)
   love.graphics.setCanvas();love.graphics.pop()
   canvas:newImageData():encode('png','mining-'..area..'.png');canvas:release()
   game.camera.x,game.camera.y,game.camera.zoom=cx,cy,zoom;shot=true
  end
  looted=looted or (e.cargo[site.item] or 0)>0
  local workersDone=not second or r.lastTask and r.lastTask.status=='completed' and second.lastTask and second.lastTask.status=='completed'
  if ((M.state(game.universe).stock[r.base] or {})[site.item] or 0)>=T.minerLoad*(second and 2 or 1) and workersDone then delivered=true;break end
  if step%12000==0 then print('mining progress',step/120,r.task and r.task.phase,e.cargo[site.item] or 0) end
 end
 check(fired,'miner never used its fitted drill on a chunk')
 check(looted,'miner never collected the actual dropped ore')
 check(delivered,'miner did not deliver its cargo and choose another duty within 600 seconds')
 check(r.task and r.task.phase=='mining','miner did not autonomously resume mining after delivery')
 -- Resource records and timer survive saves without entering ordinary area loot twice.
 M.captureResources(game)
 local resources=copy(M.state(game.universe).resources);local nextAt=site.nextAt
 local regular=0;for _,p in ipairs(game.pickups)do if not p.miningId then regular=regular+1 end end
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 check(#saved.areas[game.fieldId].pickups==regular,'mining loot was also stored as ordinary area loot')
 -- Mutate the running objects after saving: loading must restore the saved state.
 for _,live in pairs(game.miningLive)do if live.kind=='rock' then live.object.hp=1 end end
 game:loadState(saved)
 check(count(M.state(game.universe).resources)==count(resources),'save/load lost or duplicated mineral records')
 for id,resource in pairs(resources)do check(M.state(game.universe).resources[id].hp==resource.hp,'live mineral damage overwrote a loaded save') end
 check(M.state(game.universe).sites[site.id].nextAt==nextAt,'save/load reset the drill timer')
 -- Offline work consumes the same finite rocks and loot, without Box2D bodies.
 game:captureALife(true);M.unload(game)
 r=game.universe.npcs[r.id]
 r.state='idle';r.task.phase='mining';r.nextMiningAt=game.universe.clock
 for _,s in pairs(M.state(game.universe).sites)do s.nextAt=game.universe.clock end
 local bodies=game.world:getBodyCount();local initialStock=((M.state(game.universe).stock[r.base] or {})[site.item] or 0)
 for i=1,200 do
  game.universe.clock=game.universe.clock+T.miningOfflineEvery
  M.produce(game,game.universe.clock);M.advance(game,r,game.universe.clock)
 end
 check(game.world:getBodyCount()==bodies,'offline mining created physics bodies')
 local produced,accounted=0,0
 for _,s in pairs(M.state(game.universe).sites)do
  for sequence=1,s.sequence do local _,n=require('src.ore').drop('rock',28+(sequence%4)*5);produced=produced+n end
 end
 for _,stock in pairs(M.state(game.universe).stock)do for _,n in pairs(stock)do accounted=accounted+n end end
 for _,resource in pairs(M.state(game.universe).resources)do accounted=accounted+(resource.kind=='rock' and resource.yield or resource.count) end
 for _,record in pairs(game.universe.npcs)do accounted=accounted+(record.ship.cargo.iron_ore or 0) end
 check(accounted<=produced,'mining created more ore than its finite chunks contained')
 check(((M.state(game.universe).stock[r.base] or {})[site.item] or 0)>initialStock,'offline miner did not complete another mining/delivery duty')
 local totals={}
 for _,resource in pairs(M.state(game.universe).resources)do totals[resource.site]=(totals[resource.site] or 0)+1 end
 for _,n in pairs(totals)do check(n<=T.drillCap,'drill resources exceeded the per-site cap') end
 -- Miners participate in the existing abstract encounter lifecycle near home.
 local miner=copy(r);miner.id='npc/9901';miner.state='travel';miner.task.phase='delivery'
 miner.route={miner.task.target,miner.base};miner.index=2
 miner.depart=game.universe.clock-95;miner.arrive=game.universe.clock+5
 local def=require('src.data').enemies.pirate_wisp
 local pirate={id='npc/9902',role='pirate',state='travel',area=miner.area,
  route=copy(miner.route),index=2,depart=miner.depart,arrive=miner.arrive,
  ship={hull=def.hull,loadout=copy(def.loadout),cargo=copy(def.cargo),armor=120}}
 local fixture={universe={clock=game.universe.clock,npcs={[miner.id]=miner,[pirate.id]=pirate},
  mining=copy(M.state(game.universe)),tasks={offers={},nextId=0}},alifeOnline={}}
 require('src.encounters').update(fixture,game.universe.clock)
 check(miner.encounter~=nil,'pirates ignored a miner returning with ore')
 local beforeFight=Save.encode(fixture.universe.mining.resources)
 M.advance(fixture,miner,game.universe.clock+120)
 check(Save.encode(fixture.universe.mining.resources)==beforeFight,'miner kept abstractly harvesting during a fight')
 print(('MINING TEST PASSED (%d checks)'):format(checks))
end
