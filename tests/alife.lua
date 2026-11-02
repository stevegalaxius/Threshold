return function(game)
 local A=require('src.alife')
 local G=require('src.travelgraph')
 local L=require('src.locations')
 local Save=require('src.save')
 local checks=0
 local function check(ok,msg) assert(ok,msg); checks=checks+1 end
 local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
 local function near(a,b) return math.abs(a-b)<.02 end
 game.autosaveOff=true; game:loadField('earth')
 check(count(game.universe.npcs)==3,'existing Earth population not seeded exactly once')
 local graph=G.build('earth')
 check(#graph.order==6 and #graph.edges==6,'invented graph nodes or connections')
 -- Capture the actual records and declared topology on the player map.
 game.travelGraphView=graph
 local Map=require('src.ui.localmap'); Map.open(game)
 local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
 love.graphics.setCanvas(canvas); love.graphics.clear(); Map.draw(game); love.graphics.setCanvas()
 canvas:newImageData():encode('png','alife-earth-records.png')
 game.localMap,game.travelGraphView=nil,nil
 local id,r=next(game.universe.npcs)
 local x,y=A.point(r,game.universe.clock)
 game.player.body:setPosition(x,y); game:updateALife(true)
 local e=assert(game.alifeOnline[id],'nearby record did not become physical')
 check(e.route[e.routeIndex].locationId==r.route[r.index],'existing AI received wrong destination')
 e.armor=e.stats.armor*.47; e.cargo={scrap=7}
 local armor=e.armor
 e.body:setPosition(x+70,y+30)
 local target=r.route[r.index]
 game.player.body:setPosition(0,0); game:updateALife(true)
 check(not game.alifeOnline[id] and e.body:isDestroyed(),'far ship still has physics')
 local xx,yy=A.point(r,game.universe.clock)
 check(near(xx,x+70) and near(yy,y+30),'offline handoff changed physical position')
 check(r.route[r.index]==target,'offline handoff changed journey')
 check(#G.build('earth').edges==6,'handoff created graph edges')
 -- Hysteresis: a record at 7500 stays offline, an online body there stays online.
 game.player.body:setPosition(xx+7500,yy); game:updateALife(true)
 check(not game.alifeOnline[id],'offline ship woke outside inner threshold')
 game.player.body:setPosition(xx+6900,yy); game:updateALife(true)
 e=assert(game.alifeOnline[id])
 check(near(e.armor,armor) and e.cargo.scrap==7,'ship damage or cargo changed across wake')
 game.player.body:setPosition(xx+7500,yy); game:updateALife(true)
 check(game.alifeOnline[id]==e,'online ship culled within hysteresis band')
 -- Exact save/load while online, including the actual AI journey.
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(saved); e=assert(game.alifeOnline[id])
 check(e.alifeId==id and e.cargo.scrap==7 and near(e.armor,armor),'save/load replaced trader')
 check(e.route[e.routeIndex].locationId==target,'save/load lost AI route')
 -- Departing a region clears physical sampling state; remote work is timers only.
 game:loadField('venus')
 r=game.universe.npcs[id]
 check(not next(game.alifeOnline),'remote trader has a body')
 check(not r.pose and not r.offset and not r.docking,'remote record retained physical sampling state')
 local oldPoint=G.point
 G.point=function() error('remote simulation sampled a flight path') end
 game.universe.clock=r.arrive+.1
 game:updateALife(true)
 check(r.state==(L.get(target).kind=='station' and 'docked' or 'travel'),'remote arrival did not advance activity')
 if r.state=='docked' then
  game.universe.clock=r.untilTime+.1; game:updateALife(true)
  check(r.state=='travel' and r.route[r.index]~=target,'remote docked trader never departed')
 end
 G.point=oldPoint
 local encoded=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(encoded); game:loadField('earth')
 check(count(game.universe.npcs)==3,'return spawned duplicate population')
 r=assert(game.universe.npcs[id])
 check(r.ship.cargo.scrap==7 and near(r.ship.armor,armor),'remote journey lost ship state')
 x,y=A.point(r,game.universe.clock); game.player.body:setPosition(x,y); game:updateALife(true)
 e=assert(game.alifeOnline[id]); check(e.alifeId==id,'return did not restore same identity')
 -- Preserve docking state and remaining wait when a docked NPC saves/loads.
 local stationId=require('src.fields').earth.stationIds[1]
 local st=game:locationEntity(stationId)
 for i,destination in ipairs(r.route) do if destination==stationId then e.routeIndex=i end end
 game:dockInstantly(e,st); e.dockState.stay=50; e.dockState.t=17
 game.player.body:setPosition(st.body:getPosition())
 game:loadState(assert(Save.decode(Save.encode(game:saveState()))))
 e=assert(game.alifeOnline[id])
 check(e.dockState and e.dockState.station.locationId==stationId and e.dockState.t==17,'docked state lost on save/load')
 check(e.dockState.stay==50,'dock wait reset on save/load')
 -- Death removes the live representation permanently, while normal reap makes salvage.
 e.dead=true; game:reap(); game:updateALife(true)
 check(game.universe.npcs[id].state=='dead','dead NPC remained active')
 game:loadField('venus'); game:loadField('earth')
 check(count(game.universe.npcs)==3 and not game.alifeOnline[id],'dead trader respawned')
 -- Arrival previews must never instantiate or register a second copy of a trader.
 local Game=require('src.game')
 local preview=Game.new({field='earth',universe=game.universe,preview=true})
 check(not next(preview.alifeOnline or {}),'preview owns physical traders')
 preview.world:destroy()
 -- Exercise the real AI and a retained-world moon turnaround.
 game:loadField('venus')
 local liveId,live
 for candidate,record in pairs(game.universe.npcs) do
  if record.state~='dead' then liveId,live=candidate,record; break end
 end
 if live.state=='docked' then game.universe.clock=live.untilTime+.1 end
 game:updateALife(true)
 game:loadField('earth')
 x,y=A.point(live,game.universe.clock)
 game.player.body:setPosition(x+3000,y); game:updateALife(true)
 local ship=assert(game.alifeOnline[liveId])
 local AI=require('src.ai'); local think=AI.think; local calls=0
 AI.think=function(g,entity,dt)
  if entity==ship then calls=calls+1 end
  return think(g,entity,dt)
 end
 for _=1,12 do game:step(1/120) end
 AI.think=think
 check(calls==12,'online trader bypassed the existing flight AI')
 game:launchTrip('luna',{bearing=0,length=require('src.fields').moons.luna.gap})
 check(not next(game.trip.originScene.alifeOnline),'retained origin kept live NPC ownership')
 game.universe.clock=game.universe.clock+30
 game:updateALife(true)
 game:arrive(true)
 check(game.fieldId=='earth' and count(game.universe.npcs)==3,'turnaround regenerated traders')
 local instances={}
 for _,entity in ipairs(game.entities) do
  if entity.alifeId then
   check(not instances[entity.alifeId],'duplicate trader after scene adoption')
   instances[entity.alifeId]=true
  end
 end
 -- A death discovered by the offline sync must still reach normal wreck creation.
 live=game.universe.npcs[liveId]
 if live.state=='docked' then
  game:captureALife(true); game.universe.clock=live.untilTime+.1; A.advance(live,game.universe.clock)
 end
 x,y=A.point(live,game.universe.clock)
 game.player.body:setPosition(x+3000,y); game:updateALife(true)
 ship=assert(game.alifeOnline[liveId])
 local wrecks=0
 for _,entity in ipairs(game.entities) do if entity.kind=='husk' then wrecks=wrecks+1 end end
 ship.dead=true; game:updateALife(true); game:reap()
 local after=0
 for _,entity in ipairs(game.entities) do if entity.kind=='husk' then after=after+1 end end
 check(after==wrecks+1,'offline sync consumed death without creating salvage')
 print(('A-LIFE TEST PASSED (%d checks)'):format(checks))
end
