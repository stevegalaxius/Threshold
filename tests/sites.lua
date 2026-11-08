-- Sites: instanced pockets off a mass driver, joined by acceleration gates.
return function(game)
 local Sites,Fields,data=require('src.sites'),require('src.fields'),require('src.data')
 local Hold=require('src.inventory.hold')
 local checks=0
 local function check(ok,msg) assert(ok,msg);checks=checks+1 end
 local u=game.universe
 game:loadField('saturn')
 local inst=Sites.spawn(u,'iron_vault',{home='saturn'})
 check(Fields[Sites.fieldId(inst.id,4)],'every pocket becomes a field')
 check(Fields[Sites.fieldId(inst.id,1)].instance,'pockets are instances')
 check(#Sites.visible(u)==1,'a spawned site shows on the orrery')
 local x,y=Sites.position(inst,u.clock);check(x==x and y==y,'a site has a place by its planet')
 local hidden=Sites.spawn(u,'dark_dock')
 check(#Sites.visible(u)==1,'a hidden site stays off the orrery')
 hidden.discovered=true;check(#Sites.visible(u)==2,'until it is discovered')
 -- in through the driver
 check(game:enterSite(inst.id),'a driver can fire you into a site')
 check(game.fieldId==Sites.fieldId(inst.id,1) and inst.from=='saturn','you arrive in pocket 1 and it remembers where from')
 local gates,enemies={},0
 for _,e in ipairs(game.entities) do
  if e.kind=='gate' then gates[e.to]=e end
  if e.siteEnemy then enemies=enemies+1 end
 end
 check(enemies==5,'pocket enemies are spawned: '..enemies)
 check(gates[2] and gates.exit,'pocket 1 has its gate on and an automatic way home')
 check(not game:gateOpen(gates[2]),'a clear gate is locked while hostiles remain')
 check(game:gateOpen(gates.exit),'the way home is always open')
 game:clearEnemies();game:updateSites(0.1)
 check(inst.pockets[1].cleared and game:gateOpen(gates[2]),'clearing the pocket opens its gate')
 -- fly into the gate and it charges, then fires you on
 game.player.body:setPosition(gates[2].body:getPosition())
 for _=1,20 do game:updateSites(0.1) if game.fieldId~=Sites.fieldId(inst.id,1) then break end end
 check(game.fieldId==Sites.fieldId(inst.id,2),'the gate fires you to the next pocket')
 game:clearEnemies();game:updateSites(0.1)
 game:loadField(Sites.fieldId(inst.id,3),{player=require('src.ship').record(game.player)})
 local vault
 for _,e in ipairs(game.entities) do if e.kind=='gate' and e.to==4 then vault=e end end
 check(vault and not game:gateOpen(vault),'the vault gate wants its key')
 Hold.fill(game.player.hold,{vault_key=1},{random=love.math.random})
 check(game:gateOpen(vault),'carrying the key opens it')
 -- a save keeps the site and where you are in it
 local state=game:saveState()
 check(state.sites[inst.id] and state.field==Sites.fieldId(inst.id,3),'saves hold the sites and the pocket you are in')
 for n=1,4 do Fields[Sites.fieldId(inst.id,n)]=nil end
 game:loadState(state)
 check(game.fieldId==Sites.fieldId(inst.id,3),'loading puts you back in the pocket')
 check(u~=game.universe and game.universe.sites[inst.id].pockets[1].cleared,'and remembers what was cleared')
 u=game.universe;inst=u.sites[inst.id]
 game:loadField(Sites.fieldId(inst.id,1),{player=require('src.ship').record(game.player)})
 local e2=0;for _,e in ipairs(game.entities) do if e.siteEnemy then e2=e2+1 end end
 check(e2==0,'a cleared pocket stays clear')
 -- out through the last gate: home, and the site is done
 game:loadField(Sites.fieldId(inst.id,4),{player=require('src.ship').record(game.player)})
 local out;for _,e in ipairs(game.entities) do if e.kind=='gate' and e.to=='exit' then out=e end end
 game:throughGate(out)
 check(game.fieldId=='saturn','the exit gate sends you back out of the driver you came from')
 check(not u.sites[inst.id] and not Fields[Sites.fieldId(inst.id,1)],'a finished site closes')
 -- a station site you can dock at
 local dock=u.sites[hidden.id]
 game:enterSite(dock.id)
 local st;for _,e in ipairs(game.entities) do if e.kind=='station' then st=e end end
 check(st and st.dock and st.name=='Unlisted dock','a station site has a dockable station')
 game:dockInstantly(game.player,st,{})
 check(game.player.dockState,'and you can dock there')
 -- expiry
 local meet=Sites.spawn(u,'quiet_meet')
 u.clock=u.clock+10000;Sites.prune(u,game.fieldId)
 check(not u.sites[meet.id],'an expired site closes')
 check(u.sites[dock.id],'but not the one you are in')
 -- the orrery's diamonds and a pocket's gates draw
 game:loadField('saturn',{player=require('src.ship').record(game.player)})
 local drv=game:findDriver();check(drv,'saturn has a driver')
 game.driverMenu={driver=drv};love.mouse.setPosition(0,0)
 require('src.ui.orrery').draw(game);game.driverMenu=nil
 game:enterSite(dock.id);require('src.render').world(game);require('src.hud').draw(game)
 -- the driver fires you into a site after the run down the barrel
 game:loadField('saturn',{player=require('src.ship').record(game.player)})
 game.driverMenu={driver=game:findDriver()};u.credits=10000
 check(game:fireDriverToSite(dock.id),'paying a site fare starts the launch')
 for _=1,4000 do game:step(1/120) if Sites.of(game.fieldId) then break end end
 check(Sites.of(game.fieldId)==dock.id,'and the launch ends in the site')
 -- every template builds
 for _,id in ipairs(data.list.sites) do
  local s=Sites.spawn(u,id)
  for n=1,#data.sites[id].pockets do game:loadField(Sites.fieldId(s.id,n),{player=require('src.ship').record(game.player)}) end
  checks=checks+1
 end
 print(('sites test: %d checks passed'):format(checks))
end
