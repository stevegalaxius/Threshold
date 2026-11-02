-- Player-facing regional map. Its camera is independent of the flight camera.
local Fields = require('src.fields')
local Locations = require('src.locations')
local HUD = require('src.hud')
local Graph = require('src.travelgraph')
local Map = {}
local lg = love.graphics
local colors = {
 station={.55,.92,1}, buoy={.5,.65,.75}, driver={1,.75,.3},
 moon_gate={.7,.65,1}, ship={.65,.75,.8}, husk={.65,.65,.65}, container={.7,.85,.45}
}

function Map.isOpen(game) return game.localMap ~= nil end
local function viewport()
 local w,h=lg.getDimensions()
 return {x=24,y=88,w=w-328,h=h-154},w,h
end
local function playerPos(game)
 if game.player and not game.player.dead and game.player.body and not game.player.body:isDestroyed() then return game.player.body:getPosition() end
 return 0,0
end
function Map.places(game)
 local result={}
 if game.lane and game.trip then
  for _,exit in ipairs({{-game.lane.half,game.trip.from},{game.lane.half,game.trip.to}}) do
   local x,y=game:fromLane(exit[1],0)
   result[#result+1]={id=exit[2],name=Fields[exit[2]].name,kind='moon_gate',x=x,y=y}
  end
 elseif not game.flight then
  for _,place in ipairs(Locations.list(game.fieldId)) do
   local x,y=Locations.position(place.id,game.universe.clock)
   result[#result+1]={id=place.id,name=place.name,kind=place.kind,x=x,y=y}
  end
 end
 return result
end
function Map.fit(game)
 local m=game.localMap
 local f=Fields[game.fieldId]
 local r=not game.lane and not game.flight and (f.radius or 5000) or 1000
 local x1,y1,x2,y2=-r,-r,r,r
 local function include(x,y)
  x1,y1,x2,y2=math.min(x1,x),math.min(y1,y),math.max(x2,x),math.max(y2,y)
 end
 include(playerPos(game))
 for _,p in ipairs(Map.places(game)) do include(p.x,p.y) end
 if game.lane then
  for i=0,64 do include(game:fromLane(-game.lane.half+game.lane.half*2*i/64,0)) end
 end
 if game.travelGraphView and game.travelGraphView.area==game.fieldId and not game.lane then
  for _,id in ipairs(game.travelGraphView.order) do include(Graph.position(game.travelGraphView,id,game.universe.clock)) end
 end
 local v=viewport()
 m.x,m.y=(x1+x2)/2,(y1+y2)/2
 m.base=math.min(v.w/(x2-x1+1000),v.h/(y2-y1+1000))*.86
 m.zoom=1; m.drag=nil
 m.width,m.height=lg.getDimensions()
end
function Map.open(game)
 game.localMap={area=game.fieldId,lane=game.lane}
 Map.fit(game)
end
function Map.update(game)
 local m=game.localMap
 if not m then return end
 if m.area~=game.fieldId or m.lane~=game.lane then Map.open(game); m=game.localMap end
 local w,h=lg.getDimensions()
 if m.width~=w or m.height~=h then Map.fit(game) end
 if m.drag then
  local x,y=love.mouse.getPosition()
  m.x=m.drag.cx-(x-m.drag.x)/(m.base*m.zoom)
  m.y=m.drag.cy-(y-m.drag.y)/(m.base*m.zoom)
 end
end
function Map.toScreen(game,x,y)
 local v=viewport(); local m=game.localMap; local s=m.base*m.zoom
 return v.x+v.w/2+(x-m.x)*s,v.y+v.h/2+(y-m.y)*s
end
function Map.toWorld(game,x,y)
 local v=viewport(); local m=game.localMap; local s=m.base*m.zoom
 return m.x+(x-v.x-v.w/2)/s,m.y+(y-v.y-v.h/2)/s
end
local function destinations() return require('src.debugtravel').areas() end
local function destinationRows()
 return math.max(1,math.min(10,math.floor((lg.getHeight()-100)/24)))
end
local function drawDestinationDropdown(game)
 local m=game.localMap
 HUD.panel(24,52,280,26)
 lg.setFont(HUD.font(12));lg.setColor(HUD.AQUA)
 lg.print('Teleport to map...',32,59)
 lg.print(m.destinationOpen and '^' or 'v',284,59)
 if not m.destinationOpen then return end
 local list=destinations();local rows=math.min(destinationRows(),#list)
 local offset=m.destinationOffset or 0
 HUD.panel(24,80,280,rows*24+22)
 local mx,my=love.mouse.getPosition()
 for row=1,rows do
  local id=list[offset+row];local y=80+(row-1)*24
  if mx>=24 and mx<=304 and my>=y and my<y+24 then
   lg.setColor(.15,.28,.33);lg.rectangle('fill',26,y+1,276,23)
  end
  lg.setColor(id==game.fieldId and HUD.AQUA or HUD.INK)
  lg.print(Fields[id].name,32,y+5)
 end
 lg.setColor(HUD.DIM);lg.print('Scroll for more destinations',32,80+rows*24+3)
end
function Map.keypressed(game,key)
 if key=='m' then
  if Map.isOpen(game) then game.localMap=nil else Map.open(game) end
  return true
 end
 if not Map.isOpen(game) then return false end
 if key=='escape' then
  if game.localMap.destinationOpen then game.localMap.destinationOpen=false else game.localMap=nil end

 elseif key=='home' then Map.fit(game)
 elseif key=='p' then game.localMap.x,game.localMap.y=playerPos(game)
 elseif key=='f1' then return false end
 return true
end
local function inside(v,x,y) return x>=v.x and y>=v.y and x<=v.x+v.w and y<=v.y+v.h end
function Map.wheelmoved(game,y)
 if not Map.isOpen(game) then return false end
 if game.localMap.destinationOpen then
  local m=game.localMap
  m.destinationOffset=math.max(0,math.min(math.max(0,#destinations()-destinationRows()),math.floor((m.destinationOffset or 0)-y)))
  return true
 end
 local mx,my=love.mouse.getPosition()
 if inside(viewport(),mx,my) then
  local x,y0=Map.toWorld(game,mx,my)
  local m=game.localMap
  m.zoom=math.max(.5,math.min(64,m.zoom*1.2^y))
  local xx,yy=Map.toWorld(game,mx,my)
  m.x,m.y=m.x+x-xx,m.y+y0-yy
 end
 return true
end
function Map.mousepressed(game,x,y,button)
 if not Map.isOpen(game) then return false end
 local v,w=viewport(); local m=game.localMap
 if button==1 and x>=24 and x<=304 and y>=52 and y<=78 then
  m.destinationOpen=not m.destinationOpen;m.drag=nil;return true
 end
 if m.destinationOpen then
  if button==1 and x>=24 and x<=304 and y>=80 and y<80+destinationRows()*24 then
   local row=math.floor((y-80)/24)+1
   local id=destinations()[(m.destinationOffset or 0)+row]
   if id then require('src.debugtravel').go(game,id);Map.open(game);return true end
  end
  m.destinationOpen=false
  return true
 end
 if button==1 then
  if x>w-100 and y<65 then game.localMap=nil; return true end
  for i,p in ipairs(Map.places(game)) do
   local sx,sy=Map.toScreen(game,p.x,p.y)
   if (inside(v,x,y) and (x-sx)^2+(y-sy)^2<14^2)
    or (x>=w-282 and y>=98+(i-1)*38 and y<98+i*38) then
    m.selected=p.id; return true
   end
  end
 end
 if button==2 and inside(v,x,y) then
  require('src.debugtravel').point(game,Map.toWorld(game,x,y))
  m.drag=nil
  return true
 end
 if inside(v,x,y) and button==1 then m.drag={x=x,y=y,cx=m.x,cy=m.y} end
 return true
end
function Map.mousereleased(game)
 if not Map.isOpen(game) then return false end
 game.localMap.drag=nil; return true
end

function Map.draw(game)
 if not Map.isOpen(game) then return end
 local v,w,h=viewport(); local m=game.localMap
 local f=Fields[game.fieldId]; local clock=game.universe.clock
 local scale=m.base*m.zoom
 lg.push('all'); lg.origin()
 lg.setColor(.015,.035,.055,.98); lg.rectangle('fill',0,0,w,h)
 lg.setFont(HUD.font(20)); lg.setColor(HUD.AQUA)
 local name=game.lane and (Fields[game.trip.from].name..' / '..Fields[game.trip.to].name) or f.name
 lg.print('LOCAL MAP  /  '..name,24,22)
 lg.setFont(HUD.font(12)); lg.setColor(HUD.DIM)
 lg.print('M / Esc  close',w-110,30)
 lg.print('Drag to pan   /   Wheel to zoom   /   Home fit region   /   P center on ship',24,h-33)
 lg.print('Live map',w-90,h-33)
 lg.print('Debug: right-click map to teleport',320,60)
 lg.setColor(.3,.55,.65,.3); lg.rectangle('line',v.x,v.y,v.w,v.h)
 lg.setScissor(v.x,v.y,v.w,v.h)
 local cx,cy=Map.toScreen(game,0,0)
 if not game.lane and not game.flight then
  if f.radius then
   lg.setColor(.3,.55,.65,.25); lg.circle('line',cx,cy,f.radius*scale,128)
  end
  if f.planetR then
   lg.setColor(.09,.16,.2); lg.circle('fill',cx,cy,f.planetR*scale,128)
   lg.setColor(.35,.55,.65,.6); lg.circle('line',cx,cy,f.planetR*scale,128)
   lg.setColor(HUD.DIM); lg.printf(f.name,cx-100,cy-7,200,'center')
  end
 else
  if game.lane then
   local points={}
   for i=0,96 do
    local x,y=game:fromLane(-game.lane.half+game.lane.half*2*i/96,0)
    x,y=Map.toScreen(game,x,y); points[#points+1]=x; points[#points+1]=y
   end
   lg.setColor(.3,.6,.7,.5); lg.line(points)
  end
 end
 -- Show currently loaded contacts; no invented offline NPC positions.
 for _,e in ipairs(game.entities) do
  if colors[e.kind] and (e.kind=='husk' or e.kind=='container' or e.kind=='ship') and e~=game.player and not e.dead and not e.removed then
   local x,y=Map.toScreen(game,e.body:getPosition())
   lg.setColor(colors[e.kind]); lg.circle('line',x,y,2)
  end
 end
 if game.lane then
  for id,r in pairs(game.universe.npcs or {}) do
   if not (game.alifeOnline or {})[id] then
    local p=require('src.alife').laneSample(game,r,clock)
    if p then
     local x,y=Map.toScreen(game,p.x,p.y)
     lg.setColor(.65,.75,.8); lg.circle('line',x,y,2)
    end
   end
  end
 end
 if not game.lane and not game.flight then
  for id,r in pairs(game.universe.npcs or {}) do
   if r.area==game.fieldId and r.state~='dead' and r.state~='escaped' and r.state~='transit' and not (game.alifeOnline or {})[id] then
    local x,y=Map.toScreen(game,require('src.alife').point(r,clock))
    lg.setColor(.65,.75,.8); lg.circle('line',x,y,2)
   end
  end
 end
 if not game.lane and not game.flight then
  lg.push(); lg.translate(v.x+v.w/2,v.y+v.h/2); lg.scale(scale); lg.translate(-m.x,-m.y)
  Graph.draw(game,1/scale)
  lg.pop()
 end
 for i,p in ipairs(Map.places(game)) do
  local x,y=Map.toScreen(game,p.x,p.y)
  lg.setColor(colors[p.kind] or HUD.AQUA)
  if p.kind=='station' then lg.rectangle('line',x-4,y-4,8,8)
  elseif p.kind=='moon_gate' then lg.polygon('line',x,y-6,x+6,y,x,y+6,x-6,y)
  else lg.circle('line',x,y,4) end
  lg.print(tostring(i),x+7,y-14)
  if m.selected==p.id then
   lg.setColor(1,.85,.4); lg.circle('line',x,y,12)
   lg.print(p.name,x+16,y+4)
  end
 end
 local px,py=playerPos(game); local x,y=Map.toScreen(game,px,py)
 local alive=game.player and not game.player.dead and game.player.body and not game.player.body:isDestroyed()
 local a=alive and game.player.body:getAngle() or 0
 if alive then
 lg.push(); lg.translate(x,y); lg.rotate(a); lg.setColor(1,.9,.45)
 lg.polygon('fill',9,0,-6,-5,-3,0,-6,5); lg.pop()
 lg.setColor(1,.9,.45); lg.print('YOU',x+11,y+8)
 end
 -- A meaningful scale in world units, not an invented distance conversion.
 local units=10^math.floor(math.log(120/scale)/math.log(10))
 if units*scale<45 then units=units*5 end
 lg.setColor(HUD.DIM); lg.line(v.x+16,v.y+v.h-22,v.x+16+units*scale,v.y+v.h-22)
 lg.print(('%g world units'):format(units),v.x+16,v.y+v.h-42)
 lg.setScissor()
 lg.setColor(HUD.AQUA); lg.print('LOCATIONS',w-280,74)
 for i,p in ipairs(Map.places(game)) do
  local yy=98+(i-1)*38
  if m.selected==p.id then lg.setColor(.1,.2,.25); lg.rectangle('fill',w-288,yy-3,270,36) end
  lg.setColor(colors[p.kind] or HUD.AQUA)
  lg.printf(i..'  '..p.name,w-280,yy,260)
  if m.selected==p.id then
   local distance=math.sqrt((p.x-px)^2+(p.y-py)^2)
   lg.setColor(HUD.DIM)
   lg.printf(p.name..('\nDistance: %.0f world units'):format(distance),w-280,h-130,250)
  end
 end
 lg.setColor(HUD.DIM); lg.print('Nearby: ships / wrecks / cargo',w-280,h-65)
 drawDestinationDropdown(game)
 lg.pop()
end
return Map
