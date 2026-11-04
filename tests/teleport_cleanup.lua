return function(game)
 local Fields,Travel=require('src.fields'),require('src.debugtravel')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local function ownedWorld()
  local owned={}
  for _,e in ipairs(game.entities) do
   owned[e.body]=true
   for _,rotor in ipairs(e.rotors or {}) do owned[rotor.body]=true end
  end
  local complete=true
  for _,b in ipairs(game.world:getBodies()) do if not owned[b] then complete=false;break end end
  check(complete,'unowned body remained in the current field')
 end
 game.autosaveOff=true
 require('src.tuning').dev.god=true
 for _=1,#Fields.list*2 do
  local world=game.world
  local bodies=world:getBodies()
  -- Include an unmanaged body: complete unloading must not depend on entity lists.
  local untracked=love.physics.newBody(world,0,0,'static')
  game:nextField()
  check(world:isDestroyed(),'F3 kept the previous physics world alive')
  check(untracked:isDestroyed(),'untracked physics body survived F3')
  local destroyed=true
  for _,body in ipairs(bodies) do if not body:isDestroyed() then destroyed=false;break end end
  check(destroyed,'previous field body survived F3')
  check(not game.flight and not game.trip and not game.arrivalPreview,'F3 retained travel state')
  ownedWorld()
  game:step(1/120)
 end
 game:loadField('saturn')
 check(#game.sleepers>0,'distant debris was not put to sleep during field loading')
 local px,py=game.player.body:getPosition()
 local far=require('src.tuning').sleepFar
 local localDebris=true
 for _,e in ipairs(game.entities) do
  if e.kind=='asteroid' and not e.giant and not e.reentry then
   local x,y=e.body:getPosition()
   if (x-px)^2+(y-py)^2>far*far then localDebris=false;break end
  end
 end
 check(localDebris,'first AI step would still see distant generated debris')
 -- F3 from a prepared highway releases its current, origin and unused arrival worlds.
 game:loadField('earth')
 game:launchTrip('luna',{bearing=0,length=Fields.moons.luna.gap})
 local lane,origin=game.world,game.trip.originScene.world
 game:prepareArrival(false)
 local preview=game.arrivalPreview.game.world
 check(not origin:isDestroyed() and not preview:isDestroyed(),'highway scenes destroyed before unloading')
 game:nextField()
 check(lane:isDestroyed() and origin:isDestroyed() and preview:isDestroyed(),'F3 leaked a highway or preview world')
 check(not game.lane and not game.trip and not game.arrivalPreview,'F3 kept highway state')
 ownedWorld();game:step(1/120)
 -- The alternate flight mode must not resume an old trip after F3.
 game:loadField('earth');game:beginFlight('mars');game:nextField()
 check(not game.flight,'F3 left the old warp flight running')
 local area=game.fieldId
 game:step(1/120)
 check(game.fieldId==area,'old flight replaced the teleported destination')
 -- Ordinary debug travel follows the same full-world cleanup.
 local previous=game.world;Travel.go(game,'earth')
 check(previous:isDestroyed(),'debug teleport did not release its old world')
 print(('TELEPORT CLEANUP TEST PASSED (%d checks)'):format(checks))
end
