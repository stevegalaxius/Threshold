-- Continuous collision prediction for the nav computer. Broad radii only
-- reject distant bodies; warnings require a sweep of real collision fixtures.
local C={}
local abs,min,max,sqrt=math.abs,math.min,math.max,math.sqrt
local function dot(x,y,xx,yy) return x*xx+y*yy end
local function project(points,x,y)
 local lo,hi=math.huge,-math.huge
 for i=1,#points,2 do local p=dot(points[i],points[i+1],x,y); lo=min(lo,p); hi=max(hi,p) end
 return lo,hi
end
local function closestEdge(x,y,ax,ay,bx,by)
 local dx,dy=bx-ax,by-ay
 local t=max(0,min(1,dot(x-ax,y-ay,dx,dy)/max(dx*dx+dy*dy,.000001)))
 return ax+dx*t,ay+dy*t
end
local function closest(poly,x,y)
 local best,bx,by=math.huge
 for i=1,#poly,2 do
  local j=i+2; if j>#poly then j=1 end
  local xx,yy=closestEdge(x,y,poly[i],poly[i+1],poly[j],poly[j+1])
  local d=(xx-x)^2+(yy-y)^2
  if d<best then best,bx,by=d,xx,yy end
 end
 return bx,by,best
end
local function pointCircle(x,y,vx,vy,cx,cy,r,ahead)
 local dx,dy=x-cx,y-cy
 local speed=vx*vx+vy*vy
 if speed<.000001 then return end
 local closing=-dot(dx,dy,vx,vy)
 if closing<=0 then return end
 local gap=dx*dx+dy*dy-r*r
 local disc=closing*closing-speed*gap
 if disc<0 then return end
 local t=max(0,(closing-sqrt(disc))/speed)
 if t<=ahead then return t end
end
local function polygonSweep(a,b,vx,vy,ahead)
 local enter,leave=-math.huge,ahead
 for _,poly in ipairs({a,b}) do
  for i=1,#poly,2 do
   local j=i+2; if j>#poly then j=1 end
   local nx,ny=-(poly[j+1]-poly[i+1]),poly[j]-poly[i]
   if nx*nx+ny*ny>.000001 then
    local alo,ahi=project(a,nx,ny); local blo,bhi=project(b,nx,ny)
    local speed=dot(vx,vy,nx,ny)
    if abs(speed)<.000001 then
     if ahi<blo or bhi<alo then return end
    else
     local first,last=(blo-ahi)/speed,(bhi-alo)/speed
     if first>last then first,last=last,first end
     enter,leave=max(enter,first),min(leave,last)
     if enter>leave then return end
    end
   end
  end
 end
 if leave<0 or enter>ahead then return end
 return max(0,enter)
end
-- A circle moving against a convex polygon: sweep edges and rounded vertices.
local function circlePolygon(cx,cy,r,poly,vx,vy,ahead)
 local _,_,d=closest(poly,cx,cy)
 if d<=r*r then return 0 end
 local best
 for i=1,#poly,2 do
  local j=i+2; if j>#poly then j=1 end
  local ax,ay,bx,by=poly[i],poly[i+1],poly[j],poly[j+1]
  local dx,dy=bx-ax,by-ay; local len=sqrt(dx*dx+dy*dy)
  if len>.0001 then
   local nx,ny=-dy/len,dx/len
   local distance=dot(cx-ax,cy-ay,nx,ny); local speed=dot(vx,vy,nx,ny)
   if abs(speed)>.000001 then
    for sign=-1,1,2 do
     local t=(sign*r-distance)/speed
     if t>=0 and t<=ahead then
      local along=dot(cx+vx*t-ax,cy+vy*t-ay,dx/len,dy/len)
      if along>=0 and along<=len and (not best or t<best) then best=t end
     end
    end
   end
  end
  local t=pointCircle(cx,cy,vx,vy,ax,ay,r,ahead)
  if t and (not best or t<best) then best=t end
 end
 return best
end
-- Sweep a clearance circle for local steering. Initial overlap must permit
-- outward motion; reporting every escape direction as blocked causes deadlocks.
function C.sweepCircle(x,y,r,obstacle,vx,vy,ahead)
 if obstacle.minx then
  local xx,yy=x+vx*ahead,y+vy*ahead
  if max(x,xx)+r<obstacle.minx or min(x,xx)-r>obstacle.maxx
   or max(y,yy)+r<obstacle.miny or min(y,yy)-r>obstacle.maxy then return end
 end
 local nx,ny,d,inside
 if obstacle.r then
  nx,ny=x-obstacle.x,y-obstacle.y
  d=nx*nx+ny*ny;inside=d<=(r+obstacle.r)^2
 else
  local bx,by;bx,by,d=closest(obstacle.p,x,y)
  local sign;inside=#obstacle.p>=6
  if inside then
   for i=1,#obstacle.p,2 do
    local j=i+2;if j>#obstacle.p then j=1 end
    local cross=(obstacle.p[j]-obstacle.p[i])*(y-obstacle.p[i+1])-(obstacle.p[j+1]-obstacle.p[i+1])*(x-obstacle.p[i])
    if cross~=0 then
     local s=cross>0;if sign~=nil and s~=sign then inside=false;break end;sign=s
    end
   end
  end
  nx,ny=x-bx,y-by
  if inside then nx,ny=-nx,-ny end
  inside=inside or d<=r*r
 end
 if inside then
  if vx*nx+vy*ny>=0 and vx*vx+vy*vy>.0001 then return end
  return 0
 end
 if obstacle.r then return pointCircle(x,y,vx,vy,obstacle.x,obstacle.y,r+obstacle.r,ahead) end
 return circlePolygon(x,y,r,obstacle.p,vx,vy,ahead)
end

local function primitives(body)
 local shapes={}
 for _,fixture in ipairs(body:getFixtures()) do
  if not fixture:isSensor() then
   local shape=fixture:getShape(); local kind=shape:getType()
   if kind=='circle' then
    local x,y=body:getWorldPoint(shape:getPoint())
    shapes[#shapes+1]={x=x,y=y,r=shape:getRadius()}
   elseif kind=='polygon' or kind=='edge' or kind=='chain' then
    local p={body:getWorldPoints(shape:getPoints())}
    if kind=='chain' then
     for i=1,#p-2,2 do shapes[#shapes+1]={p={p[i],p[i+1],p[i+2],p[i+3]}} end
    else shapes[#shapes+1]={p=p} end
   end
  end
 end
 return shapes
end
local function shift(poly,x,y)
 local p={}; for i=1,#poly,2 do p[i],p[i+1]=poly[i]+x,poly[i+1]+y end
 return p
end
local function bounds(s)
 if s.r then return s.x-s.r,s.y-s.r,s.x+s.r,s.y+s.r end
 local x1,y1,x2,y2=math.huge,math.huge,-math.huge,-math.huge
 for i=1,#s.p,2 do x1,y1,x2,y2=min(x1,s.p[i]),min(y1,s.p[i+1]),max(x2,s.p[i]),max(y2,s.p[i+1]) end
 return x1,y1,x2,y2
end
local function contact(a,b,vx,vy,time)
 if b.r then
  local x,y
  if a.r then x,y=a.x+vx*time,a.y+vy*time
  else x,y=closest(shift(a.p,vx*time,vy*time),b.x,b.y) end
  local dx,dy=x-b.x,y-b.y; local len=max(.00001,sqrt(dx*dx+dy*dy))
  return b.x+dx/len*b.r,b.y+dy/len*b.r
 elseif a.r then return closest(b.p,a.x+vx*time,a.y+vy*time)
 else
  local moved=shift(a.p,vx*time,vy*time)
  local distance,hx,hy=math.huge
  for i=1,#moved,2 do
   local x,y,d=closest(b.p,moved[i],moved[i+1])
   if d<distance then distance,hx,hy=d,x,y end
  end
  for i=1,#b.p,2 do
   local _,_,d=closest(moved,b.p[i],b.p[i+1])
   if d<distance then distance,hx,hy=d,b.p[i],b.p[i+1] end
  end
  return hx,hy
 end
end
local SOLID={asteroid=true,planet=true,station=true,structure=true,ship=true,husk=true,container=true}
function C.threat(game,ship,ahead,range)
 local own=primitives(ship.body)
 local x,y=ship.body:getPosition(); local vx,vy=ship.body:getLinearVelocity()
 local ownRadius=0
 for _,shape in ipairs(own) do
  if shape.r then ownRadius=max(ownRadius,sqrt((shape.x-x)^2+(shape.y-y)^2)+shape.r)
  else for i=1,#shape.p,2 do ownRadius=max(ownRadius,sqrt((shape.p[i]-x)^2+(shape.p[i+1]-y)^2)) end end
 end
 local threat
 for _,o in ipairs(game.entities) do
  if o~=ship and SOLID[o.kind] and not o.dead and not o.removed and not o.gas
   and not (o.drone and o.owner==ship) and o.body and o.body:isActive() then
   local ox,oy=o.body:getWorldPoint(o.cx or 0,o.cy or 0)
   local ovx,ovy=o.body:getLinearVelocity()
   local dx,dy=vx-ovx,vy-ovy; local speed2=dx*dx+dy*dy
   local rx,ry=ox-x,oy-y
   local time=speed2>.0001 and max(0,min(ahead,(rx*dx+ry*dy)/speed2)) or 0
   local reach=max(o.radius or 0,o.halfLength or 20)*1.5+ownRadius
   if speed2>.0001 and (rx-dx*time)^2+(ry-dy*time)^2<=reach*reach then
    local other=primitives(o.body)
    for _,a in ipairs(own) do
     local ax,ay,axx,ayy=bounds(a)
     local sx1,sy1,sx2,sy2=min(ax,ax+dx*ahead),min(ay,ay+dy*ahead),max(axx,axx+dx*ahead),max(ayy,ayy+dy*ahead)
     for _,b in ipairs(other) do
      local bx,by,bxx,byy=bounds(b)
      if sx1<=bxx and sx2>=bx and sy1<=byy and sy2>=by then
       local t
       if a.r and b.r then t=pointCircle(a.x,a.y,dx,dy,b.x,b.y,a.r+b.r,ahead)
       elseif a.r then t=circlePolygon(a.x,a.y,a.r,b.p,dx,dy,ahead)
       elseif b.r then t=circlePolygon(b.x,b.y,b.r,a.p,-dx,-dy,ahead)
       else t=polygonSweep(a.p,b.p,dx,dy,ahead) end
       if t and (not threat or t<threat.time) then
        local hx,hy=contact(a,b,dx,dy,t)
        if not range or (hx-x)^2+(hy-y)^2<=range*range then
         threat={target=o,ship=ship,time=t,vx=dx,vy=dy,hitX=hx,hitY=hy}
        end
       end
      end
     end
    end
   end
  end
 end
 return threat
end
return C
