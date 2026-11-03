-- Shared pickup transport and cargo accounting for player and NPC beams.
local Ship=require('src.ship')
local data=require('src.data')
local events=require('src.events')
local Tractor={}
function Tractor.pull(game,ship,pickup,dt)
 if not ship or ship.dead or ship.removed or ship.dockState or not ship.body or ship.body:isDestroyed() then return false end
 local edge=Ship.distanceTo(ship,pickup.x,pickup.y)
 if edge>Ship.tractorRange(ship)*1.3 then ship.tractorTarget=nil;return false end
 local x,y=ship.body:getPosition();local vx,vy=ship.body:getLinearVelocity()
 local dx,dy=x-pickup.x,y-pickup.y;local d=math.max(1,math.sqrt(dx*dx+dy*dy))
 local want=math.min(600,d*4);local blend=math.min(1,dt*8)
 pickup.vx=pickup.vx+(vx+dx/d*want-pickup.vx)*blend
 pickup.vy=pickup.vy+(vy+dy/d*want-pickup.vy)*blend
 if edge<12 then
  local n=Ship.addCargo(ship,pickup.item,pickup.count)
  if n>0 then
   pickup.count=pickup.count-n
   if ship.isPlayer then game:toast(('+%d %s'):format(n,data.items[pickup.item].name),1.4,'pickup') end
   events.emit('pickup',ship,pickup.item,n)
  end
  if pickup.count>0 then
   if ship.isPlayer then game:toast('HOLD FULL',1.2) end
   pickup.vx,pickup.vy=vx-dx/d*160,vy-dy/d*160
  end
  ship.tractorTarget=nil
 end
 return pickup.count<=0
end
return Tractor
