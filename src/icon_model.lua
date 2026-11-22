-- Parametric icon solids. Source parameters stay editable; projected faces
-- support editor picking, while cached depth-tested renders handle overlap.
local M={}
-- Surface response is independent of the artist's base-color override.
M.materials={
 metal={color={.64,.72,.78},ambient=.08,diffuse=.62,specular=2.1,shininess=8,rim=.20,maxLight=.84},
 painted={ambient=.48,diffuse=.30,specular=.03,shininess=8,rim=0},
 recess={color={.12,.17,.20},ambient=.08,diffuse=.24,specular=0,rim=0},
 crystal={color={.32,.67,.78},ambient=.12,diffuse=.58,specular=1.8,shininess=12,rim=1.25,maxLight=.94},
 glass={color={.70,.86,.92},ambient=.22,diffuse=.40,specular=2.4,shininess=16,rim=.9,maxLight=1,opacity=.38},
 emissive={color={.10,.95,.76},ambient=1,diffuse=0,specular=0,rim=0,glow=1},
}
M.shapes={'box','bevel','cylinder','taper','ring','wedge','rock'}
local function normalize(x,y,z)
 local n=math.sqrt(x*x+y*y+z*z);if n<1e-9 then return 0,0,1 end
 return x/n,y/n,z/n
end
local function rotate(p,b)
 local x,y,z=p[1],p[2],p[3]
 for _,axis in ipairs({'rx','ry','rz'}) do
  local a=math.rad(b[axis] or 0);local c,s=math.cos(a),math.sin(a)
  if axis=='rx' then y,z=y*c-z*s,y*s+z*c
  elseif axis=='ry' then x,z=x*c+z*s,-x*s+z*c
  else x,y=x*c-y*s,x*s+y*c end
 end
 return {x+(b.x or 0),y+(b.y or 0),z+(b.z or 0)}
end
local function geometry(b)
 local faces={};local w,d,h=b.w or 1,b.d or 1,b.h or 1
 local function face(points,tag)
  local p={};for _,q in ipairs(points) do p[#p+1]=rotate(q,b) end
  local a,c,e=p[1],p[2],p[3]
  local ux,uy,uz=c[1]-a[1],c[2]-a[2],c[3]-a[3];local vx,vy,vz=e[1]-a[1],e[2]-a[2],e[3]-a[3]
  if (uy*vz-uz*vy)^2+(uz*vx-ux*vz)^2+(ux*vy-uy*vx)^2<1e-12 then return end
  faces[#faces+1]={points=p,tag=tag or 'side'}
 end
 local function p(x,y,z) return {x*w,y*d,z*h} end
 local shape=b.primitive or 'box'
 if shape=='cylinder' or shape=='taper' or shape=='ring' or shape=='rock' then
  local n=shape=='rock' and 7 or 32
  local top=shape=='taper' and (b.taper or .55) or 1
  local inner=math.max(.1,math.min(.9,b.inner or .62))
  local function v(i,z,r)
   local a=i*math.pi*2/n
   if shape=='rock' then r=r*(.8+.16*math.sin(i*7.3+z*2));a=a+.13*math.sin(i*3) end
   return p(.5+math.cos(a)*r*.5,.5+math.sin(a)*r*.5,z)
  end
  for i=0,n-1 do
   face({v(i,0,1),v(i+1,0,1),v(i+1,1,top),v(i,1,top)})
   if shape=='ring' then
    face({v(i,1,inner),v(i+1,1,inner),v(i+1,0,inner),v(i,0,inner)},'inner')
    face({v(i,1,1),v(i+1,1,1),v(i+1,1,inner),v(i,1,inner)},'top')
    face({v(i,0,inner),v(i+1,0,inner),v(i+1,0,1),v(i,0,1)},'bottom')
   elseif shape=='rock' then
    face({v(i,1,top),v(i+1,1,top),p(.42,.45,1.3)},'top')
    face({v(i+1,0,1),v(i,0,1),p(.5,.5,0)},'bottom')
   else
    if not b.open then face({v(i,1,top),v(i+1,1,top),p(.5,.5,1)},'top') end
    face({v(i+1,0,1),v(i,0,1),p(.5,.5,0)},'bottom')
   end
  end
 else
  local corners
  if shape=='bevel' then local c=.16;corners={{c,0},{1-c,0},{1,c},{1,1-c},{1-c,1},{c,1},{0,1-c},{0,c}}
  else corners={{0,0},{1,0},{1,1},{0,1}} end
  local top,bottom={},{}
  for _,q in ipairs(corners) do
   bottom[#bottom+1]=p(q[1],q[2],0)
   top[#top+1]=p(q[1],q[2],shape=='wedge' and q[1] or 1)
  end
  for i=1,#corners do
   local j=i%#corners+1
   face({bottom[i],bottom[j],top[j],top[i]},i==1 and 'front' or 'side')
  end
  if not b.open then face(top,'top') end
  local rev={};for i=#bottom,1,-1 do rev[#rev+1]=bottom[i] end;face(rev,'bottom')
 end
 return faces
end
function M.enabled(boxes) return boxes and #boxes>0 or false end
function M.parts(boxes,bw,bh,paint,view)
 local out={};local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
 for i,b in ipairs(boxes or {}) do
  local material=M.materials[b.material or 'painted'] or M.materials.painted
  local base=require('src.weapon_visual').partColor({color=b.color or material.color,paint=b.paint or 'primary',shade=b.shade,tint=b.tint},paint or {.6,.7,.8})
  if b.light then for j=1,3 do base[j]=base[j]+(1-base[j])*b.light end end
  for _,f in ipairs(geometry(b)) do if not (b.hide and b.hide[f.tag]) then
   local a,c,e=f.points[1],f.points[2],f.points[3]
   local ux,uy,uz=c[1]-a[1],c[2]-a[2],c[3]-a[3]
   local vx,vy,vz=e[1]-a[1],e[2]-a[2],e[3]-a[3]
   local nx,ny,nz=normalize(uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx)
   local diffuse=math.max(0,-nx*.45-ny*.55+nz*.70)
   local contrast=b.contrast or 1
   local brightness=material.ambient+(diffuse-.35)*material.diffuse*contrast+.35*material.diffuse
   -- Explicit face separation for the fixed oblique view: tops read
   -- brightest, fronts at body tone, right-hand sides clearly darker, so
   -- adjoining faces of one solid never merge into a single slab.
   if material.diffuse>0 then
    local shade=.60+.52*math.max(0,nz)+.40*math.max(0,-ny)
    brightness=brightness*(1+(math.min(1.15,shade)-1)*contrast)
   end
   brightness=math.max(.08,math.min(1.4,brightness))
   -- Fixed camera/key light for the icon's oblique projection. Metal has
   -- a broad reflection, paint is matte, and crystal catches grazing light.
   local facing=math.max(0,math.min(1,nx*.264-ny*.836+nz*.479))
   local half=math.max(0,nx*(-.11)-ny*.804+nz*.584)
   local highlight=(material.specular or 0)*half^(material.shininess or 8)
   local rim=(material.rim or 0)*(1-facing)^3
   -- Blend toward a brighter version of the same pigment instead of
   -- adding white and clipping. Reflection strength approaches its limit
   -- smoothly, so neighboring pieces retain their material color.
   local reflection=1-math.exp(-(highlight+rim))
   local ceiling=material.maxLight or 1
   local color={}
   for k=1,3 do
    local body=base[k]*brightness
    local reflected=base[k]*1.2+.04
    color[k]=body*(1-reflection)+reflected*reflection
   end
   -- Push the result away from its own grey so overrides stay vivid after
   -- shading, then scale (not clip) under the material's ceiling so the
   -- hue survives bright faces.
   local sat=b.saturation or (b.color and 1.35 or 1)
   local grey=color[1]*.299+color[2]*.587+color[3]*.114
   for k=1,3 do color[k]=math.max(0,grey+(color[k]-grey)*sat) end
   local top=math.max(color[1],color[2],color[3])
   if top>ceiling then for k=1,3 do color[k]=color[k]*ceiling/top end end
   local shape,depths={},{}
   for _,p in ipairs(f.points) do
    local x,y=p[1]+p[2]*.315,-p[3]*.55-p[2]*.315
    shape[#shape+1]=x;shape[#shape+1]=y;depths[#depths+1]=-.315*p[1]+p[2]-.573*p[3]
    x0,y0,x1,y1=math.min(x0,x),math.min(y0,y),math.max(x1,x),math.max(y1,y)
   end
   out[#out+1]={name=(b.name or b.primitive or 'box')..' '..f.tag,shape=shape,depths=depths,color=color,emissionColor=base,fill=1,
    fromBox=true,box=i,face=f.tag,modelFace=true,opacity=b.opacity or material.opacity,emission=b.glow or material.glow or (b.layer=='glow' and 1 or 0)}
  end end
 end
 if #out==0 then return out,view end
 view=view or {math.min((bw-.5)*2/math.max(x1-x0,.01),(bh-.5)*2/math.max(y1-y0,.01)),(x0+x1)/2,(y0+y1)/2}
 for _,f in ipairs(out) do for k=1,#f.shape,2 do f.shape[k]=(f.shape[k]-view[2])*view[1];f.shape[k+1]=(f.shape[k+1]-view[3])*view[1] end end
 return out,view
end
function M.pick(parts,x,y)
 local selected,nearest
 for index,f in ipairs(parts) do if f.modelFace and not f.hidden and not f.locked then
  for j=2,#f.shape/2-1 do
   local a,b,c=1,j,j+1
   local ax,ay=f.shape[a*2-1],f.shape[a*2];local bx,by=f.shape[b*2-1],f.shape[b*2];local cx,cy=f.shape[c*2-1],f.shape[c*2]
   local den=(by-cy)*(ax-cx)+(cx-bx)*(ay-cy)
   if math.abs(den)>1e-9 then
    local u=((by-cy)*(x-cx)+(cx-bx)*(y-cy))/den
    local v=((cy-ay)*(x-cx)+(ax-cx)*(y-cy))/den;local w=1-u-v
    if u>=0 and v>=0 and w>=0 then
     local d=u*f.depths[a]+v*f.depths[b]+w*f.depths[c]
     if not nearest or d<nearest then selected,nearest=index,d end
    end
   end
  end
 end end
 return selected
end
local cache=setmetatable({},{__mode='k'})
local depthShader,blurShader
local function shaders()
 if depthShader then return end
 depthShader=love.graphics.newShader([[
 #ifdef VERTEX
 attribute float FaceDepth;
 vec4 position(mat4 transform_projection,vec4 p) {vec4 q=transform_projection*p;q.z=FaceDepth*q.w;return q;}
 #endif
 #ifdef PIXEL
 vec4 effect(vec4 c,Image t,vec2 uv,vec2 p) {return c;}
 #endif
 ]])
 blurShader=love.graphics.newShader([[
 extern vec2 stepSize;
 vec4 effect(vec4 c,Image t,vec2 uv,vec2 p) {
  vec4 v=Texel(t,uv)*.227027;
  v+=(Texel(t,uv+stepSize*1.384615)+Texel(t,uv-stepSize*1.384615))*.316216;
  v+=(Texel(t,uv+stepSize*3.230769)+Texel(t,uv-stepSize*3.230769))*.070270;
  return v*c;
 }
 ]])
end
function M.draw(parts,alpha)
 local lg=love.graphics;local key
 for _,p in ipairs(parts) do if p.modelFace then key=p;break end end
 if not key then return end
 -- Render the cache at the exact on-screen pixel density 
 -- and draw it 1:1 with nearest filtering (crisp, no smoothing), instead of one big render squashed by filtering.
 local ax,ay=lg.transformPoint(0,0);local bx,by=lg.transformPoint(1,0)
 local px=math.max(.25,math.floor(math.sqrt((bx-ax)^2+(by-ay)^2)*4+.5)/4)
 local byUnit=cache[key];if not byUnit then byUnit={n=0};cache[key]=byUnit end
 local entry=byUnit[px]
 if not entry then
  if byUnit.n>=4 then for k,v in pairs(byUnit) do if k~='n' then v.solid:release();v.halo:release() end end;byUnit={n=0};cache[key]=byUnit end
  shaders();local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge;local maxDepth=.01
  for _,f in ipairs(parts) do if f.modelFace then for k=1,#f.shape,2 do
   x0,y0,x1,y1=math.min(x0,f.shape[k]),math.min(y0,f.shape[k+1]),math.max(x1,f.shape[k]),math.max(y1,f.shape[k+1])
   maxDepth=math.max(maxDepth,math.abs(f.depths[(k+1)/2]))
  end end end
  local margin=5;local unit=math.min(px,2000/math.max(x1-x0+10,y1-y0+10));local w,h=math.ceil((x1-x0+10)*unit),math.ceil((y1-y0+10)*unit)
  local solid,emission=lg.newCanvas(w,h),lg.newCanvas(w,h)
  local depth=lg.newCanvas(w,h,{format='depth24'});local oldCanvas=lg.getCanvas()
  lg.push('all');lg.origin();lg.setScissor();lg.setBlendMode('alpha');lg.setColor(1,1,1)
  local function render(target,glow)
   lg.setCanvas({target,depthstencil=depth});lg.clear(0,0,0,0,0,1);lg.setDepthMode('less',true);lg.setShader(depthShader)
   local function face(f)
    local vertices={};local c=glow and f.emissionColor or f.color;local v=glow and f.emission or f.fill;local a=f.opacity or 1
    for j=2,#f.shape/2-1 do for _,i in ipairs({1,j,j+1}) do
     vertices[#vertices+1]={(f.shape[i*2-1]-x0+margin)*unit,(f.shape[i*2]-y0+margin)*unit,f.depths[i]/maxDepth*.8,c[1]*v,c[2]*v,c[3]*v,a}
    end end
    local mesh=lg.newMesh({{'VertexPosition','float',2},{'FaceDepth','float',1},{'VertexColor','float',4}},vertices,'triangles','static')
    lg.draw(mesh);mesh:release()
   end
   -- Opaque faces first with depth writes; then see-through faces far to
   -- near, depth-tested but not written, so glass shows what is behind it.
   local clear={}
   for _,f in ipairs(parts) do if f.modelFace then
    if (f.opacity or 1)<1 then clear[#clear+1]=f else face(f) end
   end end
   if not glow and #clear>0 then
    local function mean(f) local s=0;for _,d in ipairs(f.depths) do s=s+d end;return s/#f.depths end
    table.sort(clear,function(a,b) return mean(a)>mean(b) end)
    lg.setDepthMode('less',false)
    for _,f in ipairs(clear) do face(f) end
    lg.setDepthMode('less',true)
   end
  end
  render(solid,false);render(emission,true);lg.setDepthMode();lg.setShader(blurShader)
  local temp,halo=lg.newCanvas(w,h),lg.newCanvas(w,h)
  lg.setCanvas(temp);lg.clear();blurShader:send('stepSize',{2/w,0});lg.draw(emission)
  lg.setCanvas(halo);lg.clear();blurShader:send('stepSize',{0,2/h});lg.draw(temp)
  lg.setCanvas(oldCanvas);lg.pop();depth:release();emission:release();temp:release()
  solid:setFilter('nearest','nearest')
  entry={solid=solid,halo=halo,x=x0-margin,y=y0-margin,scale=1/unit};byUnit[px]=entry;byUnit.n=byUnit.n+1
 end
 lg.push('all');lg.setColor(alpha or 1,alpha or 1,alpha or 1,alpha or 1);lg.setBlendMode('alpha','premultiplied');lg.draw(entry.solid,entry.x,entry.y,0,entry.scale)
 lg.setBlendMode('add','premultiplied');lg.setColor(1,1,1,(alpha or 1)*.85);lg.draw(entry.halo,entry.x,entry.y,0,entry.scale);lg.pop()
end
return M
