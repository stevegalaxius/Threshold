-- Transfer real container stacks without flattening their nested inventory.
local Ship=require('src.ship')
local Hold=require('src.inventory.hold')
local Grid=require('src.inventory.grid')
local events=require('src.events')
local T=require('src.tuning')
local Loot={}
local function fits(ship,stack)
 return ship.hold and Hold.placeStack(Hold.clone(ship.hold),{id=stack.id,n=1,inner=stack.inner})
end
local function canTake(ship,hold)
 for _,g in ipairs(hold.grids) do for _,s in ipairs(g.stacks) do
  if s.inner or s.wear~=nil then
   if fits(ship,s) or s.inner and canTake(ship,s.inner) then return true end
  elseif Ship.canFit(ship,s.id,s.n)>0 then return true end
 end end
 return false
end
function Loot.canTake(ship,box)
 if not box or box.dead or box.removed then return false end
 if fits(ship,{id=box.item,inner=box.hold}) then return true end
 return canTake(ship,box.hold)
end
local function takeStack(ship,hold)
 for _,g in ipairs(hold.grids) do for _,s in ipairs(g.stacks) do
  if s.inner or s.wear~=nil then
   local moved={};for key,value in pairs(s) do moved[key]=value end
   if ship.hold and Hold.placeStack(ship.hold,moved) then
    Grid.remove(g,s);ship.cargo=Hold.totals(ship.hold);Ship.updateMass(ship)
    events.emit('pickup',ship,moved.id,moved.n,moved)
    return s.n
   end
   if s.inner then local n=takeStack(ship,s.inner);if n>0 then return n end end
  else
   local n=Ship.addCargo(ship,s.id,s.n)
   if n>0 then
    s.n=s.n-n;if s.n==0 then Grid.remove(g,s) end
    events.emit('pickup',ship,s.id,n)
    return n
   end
  end
 end end
 return 0
end
function Loot.transfer(game,ship,box)
 if not ship or ship.dead or ship.removed or ship.dockState or box.dead or box.removed then return 0 end
 Ship.ensureGridHold(ship)
 -- The container and its internal hold move together when the hull can carry it.
 local ok,stack=Ship.stowContainer(ship,box)
 if ok then
  game:remove(box)
  events.emit('pickup',ship,box.item,1,stack)
  return 1
 end
 local n=takeStack(ship,box.hold)
 if n>0 then
  box.loot=Hold.totals(box.hold)
  game:containerMass(box)
 end
 return n
end
function Loot.pull(game,ship,box,dt)
 if not ship or ship.dead or ship.removed or ship.dockState or not box or box.dead or box.removed or not box.body or box.body:isDestroyed() then return 0 end
 Ship.ensureGridHold(ship)
 local x,y=ship.body:getPosition();local bx,by=box.body:getPosition()
 local edge=Ship.distanceTo(ship,bx,by)-box.radius
 if edge>Ship.tractorRange(ship) then return 0 end
 if fits(ship,{id=box.item,inner=box.hold}) and edge>10 then
  local vx,vy=ship.body:getLinearVelocity();local cvx,cvy=box.body:getLinearVelocity()
  local dx,dy=x-bx,y-by;local d=math.max(1,math.sqrt(dx*dx+dy*dy));local speed=math.min(300,d*3)
  local mass=box.body:getMass();local fx,fy=(vx+dx/d*speed-cvx)*mass*4,(vy+dy/d*speed-cvy)*mass*4
  local force=math.sqrt(fx*fx+fy*fy);local cap=T.lootHoldAccel*ship.body:getMass()*Ship.tractorPower(ship)
  if force>cap then fx,fy=fx/force*cap,fy/force*cap end
  box.body:applyForce(fx,fy);ship.body:applyForce(-fx,-fy)
  return 0
 end
 if game.time<(ship.lootTransferAt or 0) then return 0 end
 ship.lootTransferAt=game.time+.25
 return Loot.transfer(game,ship,box)
end
return Loot
