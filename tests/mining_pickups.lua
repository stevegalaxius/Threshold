-- Ore starts outside beam range, then outside the materialization band.
-- Both must be navigation destinations, independent of an active tractor lock.
return function(game)
 local M,A,Ship,T=require('src.mining'),require('src.alife'),require('src.ship'),require('src.tuning')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true;T.dev.god=true
 game:loadField('ring');game:captureALife(true);M.unload(game)
 local r
 for _,record in pairs(game.universe.npcs)do if M.isMiner(record) and record.home=='ring' then r=record;break end end
 assert(r)
 game.universe.npcs={[r.id]=r};game.universe.pirateSpawns={}
 for i=#game.entities,1,-1 do
  local object=game.entities[i]
  if object~=game.player and (object.kind=='ship' or object.kind=='asteroid' and not object.giant or object.kind=='husk' or object.kind=='container') then game:remove(object) end
 end
 game.sleepers={};local state=M.state(game.universe);state.resources={}
 for _,site in pairs(state.sites)do site.nextAt=game.universe.clock+100000 end
 local site=state.sites[r.task.target]
 local x,y=M.point(game,r,game.universe.clock)
 r.pose={x=x,y=y,a=site.angle,vx=0,vy=0,w=0,clock=game.universe.clock}
 game.player.body:setPosition(x+1800,y)
 local e=A.wake(game,r)
 local function resource(id,px,py)
  local key=site.id..'/test/'..id
  state.resources[key]={id=key,site=site.id,area='ring',kind='loot',item=site.item,count=3,
   x=px,y=py,vx=0,vy=0,clock=game.universe.clock}
  return key
 end
 local function collect(seconds)
  for _=1,seconds*120 do
   local ex,ey=e.body:getPosition()
   game.player.body:setPosition(ex+1800,ey);game.player.body:setLinearVelocity(0,0)
   game:step(1/120)
   assert(not e.dead,'miner died while approaching ore')
   if (e.cargo[site.item] or 0)>=3 then return true end
  end
  return false
 end
 local nearby=resource('outside-beam',x+math.cos(site.angle)*1200,y+math.sin(site.angle)*1200)
 M.materialize(game)
 check(game.miningLive[nearby]~=nil,'outside-beam fixture did not create a pickup')
 check(Ship.distanceTo(e,game.miningLive[nearby].object.x,game.miningLive[nearby].object.y)>Ship.tractorRange(e)*1.3,
  'fixture started in tractor range')
 check(collect(45),'miner abandoned ore outside tractor range and returned to its waiting node')
 M.captureResources(game)
 check(not state.resources[nearby],'collected ore remained available for another miner')
 -- Reset the physical worker for a second goal, retaining the same mining duty.
 M.unload(game);e.cargo={};Ship.updateMass(e)
 e.body:setPosition(x,y);e.body:setLinearVelocity(0,0);e.body:setAngularVelocity(0)
 e.miningScan=0;e.navigation=nil;e.miningPickup=nil;e.miningResource=nil;e.tractorTarget=nil
 game.player.body:setPosition(x+1800,y)
 local far=resource('outside-physics',x-math.sin(site.angle)*9000,y+math.cos(site.angle)*9000)
 M.materialize(game)
 check(not game.miningLive[far],'far fixture was already inside a physics wake band')
 check(collect(90),'miner waited at its node instead of seeking saved ore outside the physics band')
 M.captureResources(game)
 check(not state.resources[far],'far ore was collected more than once')
 print(('MINING PICKUP TEST PASSED (%d checks)'):format(checks))
end
