return function(game)
 local S,A,Fields,Save=require('src.security'),require('src.alife'),require('src.fields'),require('src.save')
 local T=require('src.tuning')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true
 game:loadField('earth')
 local timer=assert(game.universe.populationSpawns.earth.pirate)
 check(timer.nextAt>game.universe.clock,'arrival timer was not initialized')
 local id=game.universe.nextNpcId
 local count=S.pirateCount(game.universe,'earth')
 -- One due check creates one replacement, regardless of the elapsed gap.
 timer.nextAt=game.universe.clock
 S.updateSpawns(game,game.universe.clock)
 check(game.universe.nextNpcId>id and S.pirateCount(game.universe,'earth')==count+1,'due pirate arrival did not create a persistent actor')
 local after=game.universe.nextNpcId
 S.updateSpawns(game,game.universe.clock)
 check(game.universe.nextNpcId==after,'repeated sync duplicated an arrival')
 timer.nextAt=game.universe.clock
 S.updateSpawns(game,game.universe.clock)
 check(game.universe.nextNpcId==after,'automatic arrival exceeded region cap')
 -- Dead/escaped actors leave room; a new identity replaces them.
 local dead
 for _,r in pairs(game.universe.npcs) do if r.role=='pirate' and r.home=='earth' and r.state~='dead' then dead=r;break end end
 dead.state='dead';timer.nextAt=game.universe.clock
 S.updateSpawns(game,game.universe.clock)
 check(dead.state=='dead' and game.universe.nextNpcId>after,'arrival resurrected a dead identity or failed to replace it')
 check(S.pirateCount(game.universe,'earth')==T.population.pirate.target,'replacement missed population cap')
 -- Manual warp-in intentionally bypasses the automatic cap for debugging.
 local p=game.player
 local node=Fields.earth.buoyIds[1]
 p.body:setPosition(require('src.locations').position(node,game.universe.clock))
 local manual=assert(S.spawnPirate(game,'earth',true))
 local e=assert(game.alifeOnline[manual.id],'debug pirate did not materialize near the player')
 check(manual.role=='pirate' and e.alifeRole=='pirate' and manual.task and manual.task.kind=='raid','debug spawn bypassed A-Life duties')
 local effect
 for _,fx in ipairs(game.effects) do if fx.kind=='warp_in' then effect=fx end end
 check(effect and effect.life==T.npcWarpDuration,'warp-in visual was not emitted')
 check(S.pirateCount(game.universe,'earth')>T.population.pirate.target,'manual spawn was blocked by the automatic cap')
 -- Remote arrivals remain records; no remote path sampling or bodies.
 game.universe.populationSpawns.luna.pirate.nextAt=game.universe.clock-1000000
 local bodies=game.world:getBodyCount();local point=require('src.travelgraph').point
 require('src.travelgraph').point=function(g,...)
  assert(g.area=='earth','remote pirate arrival sampled a physical flight path')
  return point(g,...)
 end
 S.updateSpawns(game,game.universe.clock)
 require('src.travelgraph').point=point
 check(S.pirateCount(game.universe,'luna')==1,'moon arrival did not establish pirate traffic')
 check(game.world:getBodyCount()==bodies,'remote arrival created a local physics body')
 -- Driver-only regions also support raid duties without new graph nodes.
 local remote=assert(S.spawnPirate(game,'uranus',false))
 check(remote.node==Fields.uranus.driverId and remote.task.kind=='raid','driver-only region has no valid pirate duty')
 -- Mining moons use ordinary trade buoys for navigation and pirate duties.
 local L,G=require('src.locations'),require('src.travelgraph')
 for _,area in ipairs({'phobos','deimos'}) do
  check(#Fields[area].buoyIds==4,area..': missing trade buoys')
  for _,id in ipairs(Fields[area].buoyIds) do
   check(G.route(G.build(area),area..'/strip_mine',id,game.universe.clock)~=nil,area..': mine disconnected from its buoy')
   check(G.route(G.build(area),area..'/to_mars',id,game.universe.clock)~=nil,area..': transit endpoint disconnected from its buoy')
  end
  check(game.universe.populationSpawns[area].pirate~=nil,area..': pirate arrivals not scheduled')
  local pirate=assert(S.spawnPirate(game,area,false))
  check(pirate.task and pirate.task.kind=='raid',area..': pirate did not choose a raid duty')
  check(pirate.state=='travel' and pirate.task.source~=pirate.task.target,area..': pirate chose to wait at its starting buoy')
  local graph=G.build(area)
  for i,id in ipairs(Fields[area].buoyIds) do
   local nextId=Fields[area].buoyIds[i%4+1];local connected=false
   for _,edge in ipairs(graph.nodes[id].links) do if edge.to==nextId then connected=true end end
   check(connected,area..': buoy ring has a missing connection')
  end
 end
 local unsupported,err=S.spawnPirate(game,'station',false)
 check(not unsupported and err,'instance map accepted an automatic A-Life pirate')
 -- Timers and arrivals survive save/load without extra load-triggered spawns.
 local nextAt=timer.nextAt
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(saved)
 check(game.universe.populationSpawns.earth.pirate.nextAt==nextAt,'save/load reset the arrival timer')
 check(game.universe.npcs[manual.id] and game.universe.nextNpcId==saved.nextNpcId,'save/load lost or duplicated incoming pirates')
 -- Inspect the legacy factory gate for every authored region.
 local spawn=game.spawnEnemy;local clear=game.isClear;local calls=0
 game.spawnEnemy=function()calls=calls+1 end
 game.isClear=function()return true end
 local field=game.field;local arena=game.arenaRadius
 for _,area in ipairs(Fields.list) do
  game.field=Fields[area];game.arenaRadius=game.field.radius or 10000
  local before=calls
  game:spawnFieldEnemies()
  if game.field.instance then check(calls>before,area..': instance lost legacy pilots')
  else check(calls==before,area..': legacy pilots still spawn in a named region') end
 end
 game.field=field;game.arenaRadius=arena;game.spawnEnemy=spawn;game.isClear=clear
 -- Render the real warp effect to catch graphics-state or draw errors.
 local Render=require('src.render')
 local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
 game.camera.x,game.camera.y=effect.x,effect.y;game.camera.zoom=.7
 game:addEffect({kind='warp_in',x=effect.x,y=effect.y,r=140,t=.5,life=T.npcWarpDuration})
 love.graphics.setCanvas(canvas);Render.world(game);love.graphics.setCanvas()
 canvas:newImageData():encode('png','pirate-warp-in.png')
 for _,area in ipairs({'phobos','deimos'}) do
  game:loadField(area)
  for _,id in ipairs(Fields[area].buoyIds) do
   local buoy=game:locationEntity(id)
   check(buoy and buoy.kind=='buoy',area..': logical buoy has no physical representation')
   local x,y=L.position(id,game.universe.clock);local bx,by=buoy.body:getPosition()
   check((x-bx)^2+(y-by)^2<1,area..': buoy does not match its navigation position')
  end
  local pirate=assert(S.spawnPirate(game,area,true))
  local actor=assert(game.alifeOnline[pirate.id],area..': debug pirate did not materialize')
  require('src.ai').think(game,actor,1/120)
  check(actor.alifeRole=='pirate' and pirate.task.kind=='raid',area..': debug pirate bypassed shared role system')
  -- Exercise real powered travel, not just creation of a valid task record.
  for id,other in pairs(game.alifeOnline) do
   if id~=pirate.id then game:remove(other,true);game.alifeOnline[id]=nil end
  end
  game.universe.npcs={[pirate.id]=pirate};game.universe.populationSpawns={}
  for i=#game.entities,1,-1 do
   local object=game.entities[i]
   if object.kind=='asteroid' and not object.giant or object.kind=='container' or object.kind=='husk' then game:remove(object,true) end
   if object.kind=='station' then object.weapons={} end
  end
  game.sleepers={};game.projectiles={};game.contacts={}
  actor.aggressor,actor.combatTarget=nil,nil
  local target=S.target;S.target=function() return nil end
  local sx,sy=actor.body:getPosition();local moved=false
  for _=1,90*120 do
   local ax,ay=actor.body:getPosition()
   game.player.body:setPosition(ax+2000,ay);game.player.body:setLinearVelocity(0,0)
   game:step(1/120)
   assert(not actor.body:isDestroyed(),area..': pirate removed at '..ax..','..ay..' state '..pirate.state..' dead '..tostring(actor.dead)..' time '..game.universe.clock)
   moved=moved or (ax-sx)^2+(ay-sy)^2>1500^2
   if pirate.lastTask and pirate.lastTask.status=='completed' then break end
  end
  S.target=target
  check(moved and pirate.lastTask and pirate.lastTask.status=='completed',area..': pirate failed to travel around its buoy route and finish a duty')

 end
 print(('PIRATE SPAWN TEST PASSED (%d checks)'):format(checks))
end
