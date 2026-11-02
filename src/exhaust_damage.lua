local Engine=require('src.engine_visual')
local Exhaust={}
-- Convex polygon overlap, including contact at the edge.
local function separated(a,b)
 for i=1,#a,2 do
  local j=i+2;if j>#a then j=1 end
  local nx,ny=-(a[j+1]-a[i+1]),a[j]-a[i]
  local amin,amax,bmin,bmax=math.huge,-math.huge,math.huge,-math.huge
  for k=1,#a,2 do local d=a[k]*nx+a[k+1]*ny;amin=math.min(amin,d);amax=math.max(amax,d) end
  for k=1,#b,2 do local d=b[k]*nx+b[k+1]*ny;bmin=math.min(bmin,d);bmax=math.max(bmax,d) end
  if amax<bmin or bmax<amin then return true end
 end
 return false
end
local function overlaps(triangle,fixture)
 local shape,body=fixture:getShape(),fixture:getBody()
 if shape:getType()=='polygon' then
  local polygon={body:getWorldPoints(shape:getPoints())}
  return not separated(triangle,polygon) and not separated(polygon,triangle)
 elseif shape:getType()=='circle' then
  local x,y=body:getWorldPoint(shape:getPoint())
  local radius=shape:getRadius()
  local inside=true;local sign
  for i=1,6,2 do
   local j=i+2;if j>6 then j=1 end
   local ax,ay,bx,by=triangle[i],triangle[i+1],triangle[j],triangle[j+1]
   local dx,dy=bx-ax,by-ay
   local cross=dx*(y-ay)-dy*(x-ax)
   if cross~=0 then
    local s=cross>0
    if sign~=nil and sign~=s then inside=false end
    sign=s
   end
   local t=math.max(0,math.min(1,((x-ax)*dx+(y-ay)*dy)/math.max(dx*dx+dy*dy,1e-12)))
   if (x-ax-t*dx)^2+(y-ay-t*dy)^2<=radius*radius then return true end
  end
  return inside
 end
 return false
end
function Exhaust.update(game,dt)
 for _,source in ipairs(game.entities) do
  if source.kind=='ship' and not source.dead and not source.removed and not source.dockState
   and (source.mainBurn or 0)>.05 and source.body:isActive() then
   for _,nozzle in ipairs(Engine.emitters(source)) do
    local damage=(nozzle.effect.damage or 0)*source.mainBurn*dt
    if damage>0 then
     local x,y,w,length=Engine.geometry(nozzle,source.mainBurn,source.afterburn,game.time,true)
     local triangle={source.body:getWorldPoints(x,y-w,x,y+w,x-length,y)}
     local minx,miny,maxx,maxy=math.huge,math.huge,-math.huge,-math.huge
     for i=1,6,2 do
      minx=math.min(minx,triangle[i]);maxx=math.max(maxx,triangle[i])
      miny=math.min(miny,triangle[i+1]);maxy=math.max(maxy,triangle[i+1])
     end
     local hits={}
     game.world:queryBoundingBox(minx,miny,maxx,maxy,function(fixture)
      local target=fixture:getUserData()
      if target and target~=source and not target.dead and not target.removed and not hits[target]
       and not fixture:isSensor() and overlaps(triangle,fixture) then
       local cx,cy=fixture:getShape():computeMass(1)
       local hx,hy=fixture:getBody():getWorldPoint(cx,cy)
       hits[target]={hx,hy}
      end
      return true
     end)
     -- Apply after the query: normal damage handles immunity, retaliation,
     -- attribution and wreck damage. One hit per entity per engine per step.
     for target,hit in pairs(hits) do game:damage(target,damage,source,'exhaust',hit[1],hit[2]) end
    end
   end
  end
 end
end
return Exhaust
