-- Station-local dock geometry shared by the editor preview and runtime.
local D={}
D.fields={'dockHeading','dockX','dockY','dockWidth','dockDepth','dockRunway','dockCapture','dockWall'}
function D.build(part)
 for _,field in ipairs(D.fields) do
  local v=part[field]
  assert(v==nil or type(v)=='number' and v==v and math.abs(v)<math.huge,field..' must be finite')
 end
 for _,field in ipairs({'dockWidth','dockDepth','dockRunway','dockCapture','dockWall'}) do
  assert(part[field]==nil or part[field]>0,field..' must be positive')
 end
 assert((part.dockX==nil)==(part.dockY==nil),'dockX and dockY must be set together')
 local shape=part.shape
 assert(type(shape)=='table' and #shape>=6,'dock needs a polygon')
 local area,cx,cy=0,0,0
 for i=1,#shape,2 do
  local j=i+2;if j>#shape then j=1 end
  local cross=shape[i]*shape[j+1]-shape[j]*shape[i+1]
  area=area+cross;cx=cx+(shape[i]+shape[j])*cross;cy=cy+(shape[i+1]+shape[j+1])*cross
 end
 assert(math.abs(area)>.00001,'dock polygon has zero area')
 cx,cy=cx/(3*area),cy/(3*area)
 local a=part.dockHeading~=nil and math.rad(part.dockHeading)
  or (math.abs(cx)+math.abs(cy)<1 and 0 or math.atan2(cy,cx))
 local c,s=math.cos(a),math.sin(a)
 local x1,x2,y1,y2=math.huge,-math.huge,math.huge,-math.huge
 for i=1,#shape,2 do
  local x,y=shape[i]*c+shape[i+1]*s,-shape[i]*s+shape[i+1]*c
  x1,x2=math.min(x1,x),math.max(x2,x);y1,y2=math.min(y1,y),math.max(y2,y)
 end
 local depth=part.dockDepth or x2-x1
 local yc=(y1+y2)/2
 if part.dockX~=nil then x2=part.dockX*c+part.dockY*s;yc=-part.dockX*s+part.dockY*c end
 x1=x2-depth
 local hw=part.dockWidth and part.dockWidth/2 or (y2-y1)/2
 local d={a=a,yc=yc,x1=x1,x2=x2,hw=hw,wall=part.dockWall or 24,
  runway=part.dockRunway or 600,capture=part.dockCapture or hw*1.3}
 if part.dockBoth then
  d.both=true;d.xc=(x1+x2)/2;d.x1=x1-d.xc;d.x2=x2-d.xc
 end
 return d
end
function D.point(d,x,y,side)
 side=side or 1
 local c,s=math.cos(d.a),math.sin(d.a)
 x,y=x*side+(d.xc or 0),y*side+d.yc
 return x*c-y*s,x*s+y*c
end
return D
