-- Render an unloaded area's clock-based poses without moving its Box2D bodies.
-- Repeated setTransform calls on an unstepped world accumulate broad-phase
-- work; after a long highway stay the first real step can crash natively.
local L=require('src.locations')
local P=require('src.persistence')
local Preview={}
local Body={}; Body.__index=Body
function Body:getPosition() return self.x,self.y end
function Body:getX() return self.x end
function Body:getY() return self.y end
function Body:getAngle() return self.a end
function Body:getLinearVelocity() return self.vx,self.vy end
function Body:getAngularVelocity() return self.spin end
function Body:getWorldVector(x,y)
 local c,s=math.cos(self.a),math.sin(self.a)
 return x*c-y*s,x*s+y*c
end
function Body:getWorldPoint(x,y)
 local xx,yy=self:getWorldVector(x,y)
 return self.x+xx,self.y+yy
end
function Body:getLocalPoint(x,y)
 local c,s=math.cos(self.a),math.sin(self.a)
 x,y=x-self.x,y-self.y
 return x*c+y*s,-x*s+y*c
end
function Body:getLinearVelocityFromWorldPoint(x,y)
 return self.vx-self.spin*(y-self.y),self.vy+self.spin*(x-self.x)
end

function Preview.begin(game)
 local originals,pickups={},{}
 local poses=P.previewPositions(game)
 local clock=game.universe.clock
 for _,e in ipairs(game.entities) do
  if not e.removed then
   local pose
   if e.locationId then
    local x,y=L.position(e.locationId,clock)
    local vx,vy=L.velocity(e.locationId,clock)
    pose={x=x,y=y,a=L.heading(e.locationId,clock),vx=vx,vy=vy,spin=L.get(e.locationId).spin or 0}
   elseif poses.objects[e.persistenceId] then
    local p=poses.objects[e.persistenceId]
    pose={x=p.x,y=p.y,a=e.body:getAngle(),vx=p.vx,vy=p.vy,spin=p.spin or 0}
   end
   if pose then
    originals[#originals+1]={entity=e,body=e.body}
    e.body=setmetatable(pose,Body)
   end
  end
 end
 for _,p in ipairs(game.pickups) do
  local pose=poses.pickups[p.persistenceId]
  if pose then
   pickups[#pickups+1]={p=p,x=p.x,y=p.y,vx=p.vx,vy=p.vy}
   p.x,p.y,p.vx,p.vy=pose.x,pose.y,pose.vx,pose.vy
  end
 end
 return function()
  for _,entry in ipairs(originals) do entry.entity.body=entry.body end
  for _,entry in ipairs(pickups) do
   entry.p.x,entry.p.y,entry.p.vx,entry.p.vy=entry.x,entry.y,entry.vx,entry.vy
  end
 end
end
return Preview
