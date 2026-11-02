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
 Travel.go(game,'phobos','phobos/strip_mine')
 check(game.fieldId=='phobos' and game.player.hull.id==hull,'teleport replaced ship')
 check(game.player.armor==armor,'teleport repaired ship')
 local mine=game:locationEntity('phobos/strip_mine')
 local lx,ly=game.dockLocal(mine,1,game.player.body:getPosition())
 check(lx>mine.dock.x2+mine.dock.runway and math.abs(ly)<.1,'station teleport not on clear approach')
 check(game.universe.clock==clock and game.universe.credits==credits,'teleport charged fare or advanced time')
 Map.open(game);Map.keypressed(game,'tab')
 check(game.localMap.world,'world destination view did not open')
 Map.draw(game)
 Map.mousepressed(game,40,62,1)
 check(not game.localMap.world,'map back button failed')
 game:loadField('earth');game:launchTrip('luna',{bearing=0,length=30000})
 Travel.go(game,'deimos','deimos/strip_mine')
 check(game.fieldId=='deimos' and not game.trip and not game.lane and not game.flight,'teleport did not exit transit')
 game:step(1/120)
 print(('DEBUG TRAVEL TEST PASSED (%d checks)'):format(checks))
end
