-- A-Life debug overlay for the local map (M), shared with the F6 suite.
-- One selection: pick an NPC in F6 or click it on the map, and both follow.
local L=require('src.locations')
local Graph=require('src.travelgraph')
local Trace=require('src.alife_trace')
local O={state={selected=nil,overlay=false,labels='all'}}
local lg=love.graphics

function O.select(id,game) O.state.selected=id;if id and game and game.localMap then game.localMap.selected=nil end end
function O.selected() return O.state.selected end
function O.toggleOverlay() O.state.overlay=not O.state.overlay end
local LABELS={'all','problems','selected'}
function O.cycleLabels()
 for i,m in ipairs(LABELS) do if m==O.state.labels then O.state.labels=LABELS[i%#LABELS+1];return end end
 O.state.labels='selected'
end

-- One colour per kind of trouble, so problems stand out at a glance.
function O.color(game,r,e)
 if r.fuelStatus=='stranded' then return {1,.3,.3} end
 if r.encounter or e and (e.combatTarget or e.aggressor) then return {1,.6,.2} end
 if e and (e.asked or e.request) or r.distress then return {1,.4,.9} end
 if r.service then return {1,.9,.3} end
 if r.fuelStatus=='low' or r.fuelStatus=='empty' then return {1,.75,.5} end
 if e then return {.4,1,.5} end
 return {.75,.82,.88}
end
local function problem(game,r,e)
 return r.fuelStatus=='stranded' or r.fuelStatus=='empty' or r.encounter or r.service or r.distress or e and (e.asked or e.request)
end

-- Every NPC that is in this map right now: {id,r,e,x,y} in world units.
function O.npcs(game)
 local out,clock=game.universe and game.universe.npcs and {} ,game.universe.clock
 if not out then return {} end
 local A=require('src.alife')
 for id,r in pairs(game.universe.npcs) do
  if r.state~='dead' and r.state~='escaped' then
   local e=game.alifeOnline and game.alifeOnline[id]
   if e and (e.dead or e.removed or not e.body or e.body:isDestroyed()) then e=nil end
   local x,y
   if e then x,y=e.body:getPosition()
   elseif game.lane then local p=A.laneSample(game,r,clock);if p then x,y=p.x,p.y end
   elseif not game.flight and r.area==game.fieldId and r.state~='transit' then x,y=A.point(r,clock) end
   if x then out[#out+1]={id=id,r=r,e=e,x=x,y=y} end
  end
 end
 return out
end

-- The NPC under a screen point, if any.
function O.pick(game,toScreen,sx,sy,radius)
 local best,bd=nil,(radius or 10)^2
 for _,n in ipairs(O.npcs(game)) do
  local x,y=toScreen(game,n.x,n.y);local d=(x-sx)^2+(y-sy)^2
  if d<bd then best,bd=n.id,d end
 end
 return best
end

-- Draw in screen space. toScreen(game,x,y) maps world to screen.
function O.draw(game,toScreen,font)
 local st,clock=O.state,game.universe.clock
 lg.push('all')
 -- screen space: the world pass leaves its zoom-scaled line width behind
 lg.setLineWidth(1)
 -- simulation connections
 local view=st.overlay and not game.lane and not game.flight and Graph.build(game.fieldId)
 if view then
  lg.setColor(.2,.6,.8,.35)
  for _,edge in ipairs(view.edges) do
   local pts={}
   for i=0,24 do local x,y=toScreen(game,Graph.point(view,edge,i/24,clock));pts[#pts+1]=x;pts[#pts+1]=y end
   lg.line(pts)
  end
  lg.setColor(.5,.85,1,.8)
  for _,id in ipairs(view.order) do local x,y=toScreen(game,Graph.position(view,id,clock));lg.circle('line',x,y,3) end
 end
 local list=O.npcs(game);local sel
 for _,n in ipairs(list) do
  local x,y=toScreen(game,n.x,n.y)
  local c=O.color(game,n.r,n.e)
  lg.setColor(c);lg.circle(n.e and 'fill' or 'line',x,y,n.e and 3 or 3.5)
  if n.id==st.selected then sel={n=n,x=x,y=y} end
  local label=st.overlay and (st.labels=='all' or st.labels=='problems' and problem(game,n.r,n.e))
  if label and n.id~=st.selected then
   if font then lg.setFont(font) end
   -- the old N overlay's readout: who, what's driving it, what it's doing
   lg.setColor(c[1],c[2],c[3],.85);lg.print(n.id..' '..(n.r.role or '')..'  '..Trace.controller(game,n.r,n.e),x+6,y-6)
   local status=require('src.reactor_fuel').activity(n.r)
   if status then lg.setColor(c[1],c[2],c[3],.6);lg.print(status,x+6,y+7) end
  end
 end
 if sel then
  local n,r,e=sel.n,sel.n.r,sel.n.e
  -- its itinerary through this map
  if r.route and not game.lane then
   local pts={sel.x,sel.y}
   for i=0,#r.route-1 do
    local id=r.route[((r.index or 1)-1+i)%#r.route+1]
    local place=L.byId[id]
    if not place or place.area~=game.fieldId then break end
    local x,y=toScreen(game,L.position(id,clock));pts[#pts+1]=x;pts[#pts+1]=y
   end
   if #pts>=4 then lg.setColor(1,.85,.4,.6);lg.line(pts) end
  end
  -- who it is dealing with
  local req=e and (e.asked or e.request)
  local other=req and (req.asker==e and req.giver or req.asker)
  if other and other.body and not other.body:isDestroyed() then
   local ox,oy=toScreen(game,other.body:getPosition())
   lg.setColor(1,.4,.9,.8);lg.line(sel.x,sel.y,ox,oy)
  end
  lg.setColor(1,.85,.4);lg.circle('line',sel.x,sel.y,10)
  if font then lg.setFont(font) end
  lg.print(n.id..'  '..(r.role or '')..'  '..Trace.controller(game,r,e),sel.x+14,sel.y-8)
  local status=require('src.reactor_fuel').activity(r)
  if status then lg.setColor(1,.85,.4,.8);lg.print(status,sel.x+14,sel.y+6) end
 end
 lg.pop()
end
return O
