-- Patrols reach every Heaven-Ladder anchor's inspection point. The anchors
-- sit inside the planet's surface-pull band, which the trade AI used to
-- climb out of while the stop sat below, so the ship hovered just short.
return function(game)
 local A,L,Fields=require('src.alife'),require('src.locations'),require('src.fields')
 local copy=require('src.persistence').copy
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true
 game:loadField('mars');game:captureALife(true)
 local template
 for _,record in pairs(game.universe.npcs) do if record.home=='mars' and record.role=='patrol' then template=copy(record);break end end
 assert(template,'missing Mars patrol')
 local buoys=Fields.mars.buoyIds
 for k,node in ipairs(Fields.mars.ladderIds) do
  for i=#game.entities,1,-1 do
   local e=game.entities[i]
   if e.kind=='ship' or e.kind=='asteroid' or e.kind=='container' or e.kind=='husk' then game:remove(e,true) end
  end
  local r=copy(template)
  game.sleepers={};game.alifeOnline={};game.universe.npcs={[r.id]=r};game.universe.populationSpawns={}
  local from=buoys[(k-1)%#buoys+1]
  r.area='mars';r.state='travel';r.route={from,node};r.index=2;r.node=nil
  r.encounter=nil;r.offset=nil;r.pose=nil
  r.depart=game.universe.clock;r.arrive=r.depart+60
  -- keep the player parked outside the ring, near enough to keep it awake
  game:spawnPlayer();local nx,ny=L.position(node,game.universe.clock)
  game.player.body:setPosition(nx*1.6,ny*1.6)
  local e=A.wake(game,r)
  local arrived=false
  for _=1,120*90 do
   game.player.body:setLinearVelocity(0,0)
   game:step(1/120)
   assert(not e.dead,'patrol died approaching ladder anchor '..k)
   if r.state=='idle' and r.node==node then arrived=true;break end
  end
  check(arrived,'patrol hovered short of Heaven-Ladder anchor '..k)
  if not e.removed then game:remove(e,true) end
 end
 print(('LADDER PATROL TEST PASSED (%d checks)'):format(checks))
end
