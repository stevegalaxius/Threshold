return function(game)
 local Travel=require('src.debugtravel')
 local Map=require('src.ui.localmap')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true
 check(Travel.areas('deimos')[1]=='deimos','moon search failed')
 check(#Travel.areas('no such destination')==0,'search ignored filter')
 for _,id in ipairs(Travel.areas()) do check(not require('src.fields')[id].transit,'anonymous highway offered as destination') end
 local hull=game.player.hull.id
 local armor=game.player.armor*.8;game.player.armor=armor
 local credits,clock=game.universe.credits,game.universe.clock
 Travel.go(game,'phobos','station:phobos_1')
 check(game.fieldId=='phobos' and game.player.hull.id==hull,'teleport replaced ship')
 check(game.player.armor==armor,'teleport repaired ship')
 local mine=game:locationEntity('station:phobos_1')
 local lx,ly=game.dockLocal(mine,1,game.player.body:getPosition())
 check(lx>mine.dock.x2+mine.dock.runway and math.abs(ly)<.1,'station teleport not on clear approach')
 check(game.universe.clock==clock and game.universe.credits==credits,'teleport charged fare or advanced time')
 Map.open(game)
 local sx,sy=Map.toScreen(game,2000,3000)
 Map.mousepressed(game,sx,sy,2)
 local px,py=game.player.body:getPosition()
 check(math.abs(px-2000)<.01 and math.abs(py-3000)<.01,'right-click did not teleport to map point')
 Map.draw(game)
 Map.mousepressed(game,40,60,1)
 check(game.localMap.destinationOpen,'map destination dropdown did not open')
 local index
 for i,id in ipairs(Travel.areas()) do if id=='deimos' then index=i;break end end
 Map.draw(game)
 Map.mousepressed(game,40,80+(index-1)*24+12,1)
 check(game.fieldId=='deimos' and Map.isOpen(game),'dropdown did not teleport and retain map')
 check(game.player.hull.id==hull and game.player.armor==armor,'dropdown replaced or repaired ship')
 game.player.dead=true;game.player.removed=true;game.player.body:destroy()
 Map.draw(game)
 check(not Travel.point(game,100,100),'teleported a destroyed player body')
 game.player=nil
 game:loadField('earth');game:launchTrip('luna',{bearing=0,length=30000})
 Travel.go(game,'deimos','station:deimos_1')
 check(game.fieldId=='deimos' and not game.trip and not game.lane and not game.flight,'teleport did not exit transit')
 game:step(1/120)
 print(('DEBUG TRAVEL TEST PASSED (%d checks)'):format(checks))
end
