-- love . --playerdock : put the player out on each Earth station's runway and fly it at the door
return function(game)
 game.autosaveOff=true
 game:loadField(require('src.fields').start)
 for _=1,60 do game:step(1/60) end
 local p=game.player
 for _,st in ipairs(game.entities) do
  if st.kind=='station' and st.dock and not st.city and not st.sat then
   local d=st.dock
   p.dockState=nil;p.dockCooldown=0;p.body:setActive(true);game.state='playing'
   local x,y=game.dockWorld(st,1,d.x2+d.runway*0.9,0,d)
   p.body:setPosition(x,y);p.body:setAngle(game.dockAngle(st,1,d)+math.pi)
   p.body:setLinearVelocity(st.body:getLinearVelocityFromWorldPoint(x,y));p.body:setAngularVelocity(0)
   local phases,busy={},false
   for i=1,60*30 do
    p.intent.thrust,p.intent.strafe,p.intent.boost=0,0,false
    busy=busy or require('src.queue').dockBusy(game,st,d,p)
    game:step(1/60)
    local ph=p.dockState and p.dockState.phase or 'none'
    if phases[#phases]~=ph then phases[#phases+1]=ph end
    if p.dockState and p.dockState.done then break end
   end
   print(('%s: %s busy=%s'):format(tostring(st.locationId),table.concat(phases,'>'),tostring(busy)))
   if p.dockState and p.dockState.done then game:undock() for _=1,120 do game:step(1/60) end end
  end
 end
end
