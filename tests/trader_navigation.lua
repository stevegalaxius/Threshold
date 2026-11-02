-- Exercise actual powered movement, not teleporting the NPC between stops.
return function(game)
 local A=require('src.alife')
 local L=require('src.locations')
 local Fields=require('src.fields')
 local T=require('src.tuning')
 local checks=0
 local function check(ok,msg) assert(ok,msg); checks=checks+1 end
 game.autosaveOff=true
 game:loadField('earth')
 local id,r
 for candidate,record in pairs(game.universe.npcs) do
  if record.home=='earth' and record.onRoundTrip then id,r=candidate,record; break end
 end
 local gateId='earth/to_luna'
 local gx,gy=L.position(gateId,0)
 local xx,yy=L.position(gateId,12345)
 check(gx==xx and gy==yy,'moon corridor moves with the clock')
 game:placeMoonGates()
 check(game:moonGateAt(gx,gy).locationId==gateId,'player corridor does not match NPC target')
 -- Retain the actual planet/stations, clear unrelated hazards/populations.
 game:captureALife(true)
 game.universe.npcs={[id]=r}
 for i=#game.entities,1,-1 do
  local e=game.entities[i]
  if e~=game.player and (e.kind=='ship' or e.kind=='asteroid' or e.kind=='container' or e.kind=='husk') then game:remove(e) end
 end
 game.sleepers={}
 -- Prevent the observer from launching a separate trip while following.
 game.updateMoonGates=function(self) self:placeMoonGates() end
 r.area='earth'; r.state='docked'; r.index=1; r.untilTime=game.universe.clock+60
 r.pose,r.offset,r.docking=nil,nil,nil
 local st=game:locationEntity(Fields.earth.stationIds[1])
 game.player.body:setPosition(st.body:getPosition()); game:updateALife(true)
 local e=assert(game.alifeOnline[id])
 game:undockShip(e)
 local initialGap=math.abs((math.atan2(gy,gx)-math.atan2(e.body:getY(),e.body:getX())+math.pi)%(2*math.pi)-math.pi)
 local earlyEdge=false
 local startClock=game.universe.clock
 for i=1,24000 do
  local x,y=e.body:getPosition()
  game.player.body:setPosition(x+4000,y); game.player.body:setLinearVelocity(0,0)
  game:step(1/120)
  if e.dead then error('trader died in navigation-only fixture') end
  if e.alifeEgress then break end
  local gap=math.abs((math.atan2(gy,gx)-math.atan2(y,x)+math.pi)%(2*math.pi)-math.pi)
  if gap>initialGap*.65 and math.sqrt(x*x+y*y)>Fields.earth.radius-1000 then earlyEdge=true end
 end
 check(e.alifeEgress,'powered trader did not reach the stationary exit in 200 seconds')
 check(not earlyEdge,'trader went to the map perimeter before traversing the route')
 local x0,y0=e.body:getPosition()
 -- Chasing/attacking the departing trader must not remove its movement AI.
 game:damage(e,1,game.player,'navigation-test')
 local powered=false
 for _=1,480 do
  local x,y=e.body:getPosition()
  game.player.body:setPosition(x+1200,y); game.player.body:setLinearVelocity(0,0)
  game:step(1/120)
  powered=powered or math.abs(e.intent.thrust)+math.abs(e.intent.strafe)>.01
 end
 local x1,y1=e.body:getPosition()
 check(powered,'departing trader lost its powered steering')
 check(math.sqrt((x1-x0)^2+(y1-y0)^2)>500,'departing trader stalled while being followed')
 check(e.aggressor==game.player,'retaliation state was lost while departing')
 print(('TRADER NAVIGATION TEST PASSED (%d checks; %.1fs physical departure)'):format(checks,game.universe.clock-startClock))
end
