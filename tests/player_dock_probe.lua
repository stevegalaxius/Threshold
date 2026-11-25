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
   if p.dockState and p.dockState.done then game:undock() for _=1,300 do game:step(1/60) end end
   -- and onto an exterior berth: stop just off a free pad
   local b=game:freeBerth(st,p)
   local pose=b and (game:berthPose(st,b,p.hull.id) or st.def.berths[b])
   if pose then
    p.dockState=nil;p.dockCooldown=0;p.body:setActive(true);game.state='playing'
    local h=math.rad(pose.heading or 0)
    local bx,by=st.body:getWorldPoint(pose.x+math.cos(h)*(p.halfLength+120),pose.y+math.sin(h)*(p.halfLength+120))
    p.body:setPosition(bx,by);p.body:setLinearVelocity(st.body:getLinearVelocityFromWorldPoint(bx,by))
    local ph={}
    for i=1,60*15 do
     p.intent.thrust,p.intent.strafe,p.intent.boost=0,0,false
     game:step(1/60)
     local x=p.dockState and p.dockState.phase or 'none'
     if ph[#ph]~=x then ph[#ph+1]=x end
     if p.dockState and p.dockState.done then break end
    end
    print(('%s berth %d: %s'):format(tostring(st.locationId),b,table.concat(ph,'>')))
    if p.dockState and p.dockState.done then game:undock() for _=1,300 do game:step(1/60) end end
   else print(tostring(st.locationId)..': no free berth for the player') end
  end
 end
end
