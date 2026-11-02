-- Local offline travel: graph edges and elapsed time, never physics bodies.
local L = require('src.locations')
local Fields = require('src.fields')
local G = {}
local pi, cos, sin, sqrt, atan2 = math.pi, math.cos, math.sin, math.sqrt, math.atan2
local function delta(a, b) return (b - a + pi) % (2 * pi) - pi end

function G.position(graph, id, clock)
 local n = assert(graph.nodes[id], 'unknown travel node ' .. tostring(id))
 return L.position(n.location, clock)
end

function G.point(graph, edge, progress, clock)
 local x, y = G.position(graph, edge.from, clock)
 local xx, yy = G.position(graph, edge.to, clock)
 -- The coarse route goes around the planet instead of cutting across it.
 local r, rr = sqrt(x*x+y*y), sqrt(xx*xx+yy*yy)
 local a = atan2(y,x) + delta(atan2(y,x), atan2(yy,xx))*progress
 r = r + (rr-r)*progress
 return cos(a)*r, sin(a)*r
end

-- Connectivity is authored in fields.lua; physical positions never add links.
function G.build(area)
 local f = assert(Fields[area], 'unknown area')
 local graph = {area=area, nodes={}, edges={}, destinations={}, order={}}
 for _,place in ipairs(L.list(area)) do
  graph.nodes[place.id]={location=place.id,links={},owner=place.owner,
   market=place.marketId,danger=place.danger,capacity=place.capacity}
  graph.order[#graph.order+1]=place.id
  graph.destinations[place.id]={place.id}
 end
 for _,pair in ipairs(f.travelLinks or {}) do
  local a,b=pair[1],pair[2]
  assert(graph.nodes[a] and graph.nodes[b], 'travel link has unknown endpoint')
  graph.edges[#graph.edges+1]={from=a,to=b}
  table.insert(graph.nodes[a].links,{from=a,to=b})
  table.insert(graph.nodes[b].links,{from=b,to=a})
 end
 return graph
end

-- Existing region connections: the two authored ends of a moon highway.
function G.transit(from,to)
 local a,b=L.get(from),L.get(to)
 if a.kind~='moon_gate' or b.kind~='moon_gate' or a.destination~=b.area or b.destination~=a.area then return nil end
 local moon=Fields.moons[a.area] and Fields.moons[a.area].parent==b.area and a.area
  or Fields.moons[b.area] and Fields.moons[b.area].parent==a.area and b.area
 if moon then return {from=a.area,to=b.area,moon=moon,length=Fields.moons[moon].gap} end
end

function G.length(graph,edge,clock)
 local x,y=G.position(graph,edge.from,clock)
 local xx,yy=G.position(graph,edge.to,clock)
 local r,rr=sqrt(x*x+y*y),sqrt(xx*xx+yy*yy)
 local arc=delta(atan2(y,x),atan2(yy,xx))*(r+rr)/2
 return sqrt((rr-r)^2+arc^2)
end

-- Recover progress on the ship's existing journey, without changing topology.
function G.project(graph,edge,x,y,clock)
 local ax,ay=G.position(graph,edge.from,clock)
 local bx,by=G.position(graph,edge.to,clock)
 local angle=delta(atan2(ay,ax),atan2(by,bx))
 local p
 if math.abs(angle)>.001 then
  p=delta(atan2(ay,ax),atan2(y,x))/angle
 else
  local dx,dy=bx-ax,by-ay
  p=((x-ax)*dx+(y-ay)*dy)/math.max(dx*dx+dy*dy,1)
 end
 return math.max(0,math.min(1,p))
end

function G.route(graph,from,to,clock,speed)
 assert(speed==nil or speed>0,'travel speed must be positive')
 local starts, goals=graph.destinations[from],graph.destinations[to]
 if not starts or not goals then return nil,'destination is outside this local graph' end
 local dist,prev,done={}, {}, {}
 for _,id in ipairs(starts) do dist[id]=0 end
 local goalSet={}; for _,id in ipairs(goals) do goalSet[id]=true end
 local finish
 while true do
  local best, cost=nil,math.huge
  for _,id in ipairs(graph.order) do
   if not done[id] and dist[id] and dist[id]<cost then best,cost=id,dist[id] end
  end
  if not best then return nil,'no route' end
  if goalSet[best] then finish=best; break end
  done[best]=true
  for _,edge in ipairs(graph.nodes[best].links) do
   local nextCost=cost+G.length(graph,edge,clock)/(speed or 600)
   if not dist[edge.to] or nextCost<dist[edge.to] then
    dist[edge.to]=nextCost; prev[edge.to]={edge=edge,duration=nextCost-cost}
   end
  end
 end
 local legs,at={},finish
 while prev[at] do table.insert(legs,1,prev[at]); at=prev[at].edge.from end
 return {from=from,to=to,start=at,finish=finish,legs=legs,duration=dist[finish],plannedAt=clock}
end

local function samplePoint(graph,route,elapsed,clock)
 elapsed=math.max(0,elapsed)
 for _,leg in ipairs(route.legs) do
  if elapsed<leg.duration then
   local p=elapsed/leg.duration
   local x,y=G.point(graph,leg.edge,p,clock)
   return x,y,false,leg.edge,p
  end
  elapsed=elapsed-leg.duration
 end
 local x,y=G.position(graph,route.finish,clock)
 return x,y,true,nil,1
end

function G.sample(graph,route,elapsed,clock)
 local x,y,arrived,edge,p=samplePoint(graph,route,elapsed,clock)
 local xx,yy=samplePoint(graph,route,elapsed+.02,clock+.02)
 local vx,vy=(xx-x)/.02,(yy-y)/.02
 return {x=x,y=y,heading=atan2(vy,vx),vx=vx,vy=vy,arrived=arrived,edge=edge,progress=p}
end

-- Developer-only overlay of declared links and real NPC state.
function G.draw(game,px)
 local view=game.travelGraphView
 if not view or view.area~=game.fieldId then return end
 local lg,clock=love.graphics,game.universe.clock
 local function drawEdge(e)
  local points={}
  for i=0,24 do local x,y=G.point(view,e,i/24,clock); points[#points+1]=x; points[#points+1]=y end
  lg.line(points)
 end
 lg.push('all'); lg.setLineWidth(px)
 lg.setColor(.2,.6,.8,.35)
 for _,e in ipairs(view.edges) do drawEdge(e) end
 -- Inspect the actual trader records, including bodies managed by existing AI.
 local A=require('src.alife')
 for id,r in pairs(game.universe.npcs or {}) do
  if r.area==game.fieldId and r.state~='dead' and r.state~='escaped' and r.state~='transit' then
   local e=game.alifeOnline and game.alifeOnline[id]
   local x,y
   if e then x,y=e.body:getPosition() else x,y=A.point(r,clock) end
   lg.setColor(e and .4 or 1,e and 1 or .75,.3,1)
   lg.circle('fill',x,y,4*px)
   lg.push(); lg.translate(x+8*px,y+5*px); lg.scale(px)
   lg.print(id..' '..(e and 'online' or r.state)..' -> '..L.get(r.route[e and e.routeIndex or r.index]).name,0,0)
   lg.pop()
  end
 end
 lg.setColor(.5,.85,1,.8)
 for _,id in ipairs(view.order) do local x,y=G.position(view,id,clock); lg.circle('line',x,y,3*px) end
 lg.pop()
end
return G
