-- Local offline travel: graph edges and elapsed time, never physics bodies.
local L = require('src.locations')
local Fields = require('src.fields')
local Stations = require('src.stations')
local data = require('src.data')
local G = {}
local pi, cos, sin, sqrt, atan2 = math.pi, math.cos, math.sin, math.sqrt, math.atan2
local function delta(a, b) return (b - a + pi) % (2 * pi) - pi end

function G.position(graph, id, clock)
 local n = assert(graph.nodes[id], 'unknown travel node ' .. tostring(id))
 if not n.location then return n.x, n.y end
 local x, y = L.position(n.location, clock)
 local a = L.heading(n.location, clock)
 return x + cos(a) * (n.x or 0) - sin(a) * (n.y or 0),
        y + sin(a) * (n.x or 0) + cos(a) * (n.y or 0)
end

function G.point(graph, edge, progress, clock)
 local x, y = G.position(graph, edge.from, clock)
 local xx, yy = G.position(graph, edge.to, clock)
 if edge.straight then return x + (xx-x)*progress, y + (yy-y)*progress end
 -- The coarse route goes around the planet instead of cutting across it.
 local r, rr = sqrt(x*x+y*y), sqrt(xx*xx+yy*yy)
 local a = atan2(y,x) + delta(atan2(y,x), atan2(yy,xx))*progress
 r = r + (rr-r)*progress
 return cos(a)*r, sin(a)*r
end

local function layout(place)
 local s = assert(place.layout, 'station needs travel layout: ' .. place.id)
 local id = s.city and Stations.cityId(s.city) or Stations.ringId(s.radius, s.tube)
 if not data.stations[id] then
  assert(data.defineStation(s.city and Stations.city(s.city) or Stations.ring(s.radius,s.tube)))
 end
 return data.stations[id]
end

function G.build(area, clock)
 local f = assert(Fields[area], 'unknown area')
 local graph = {area=area, nodes={}, edges={}, destinations={}, order={}}
 local function node(id, n)
  graph.nodes[id] = n; graph.order[#graph.order+1] = id; n.links = {}
  return id
 end
 local function link(a,b,straight)
  for _, pair in ipairs({{a,b},{b,a}}) do
   local e = {from=pair[1],to=pair[2],straight=straight or false}
   graph.edges[#graph.edges+1] = e
   table.insert(graph.nodes[pair[1]].links,e)
  end
 end
 local attachments = {}
 for _, place in ipairs(L.list(area)) do
  local targets = {}; graph.destinations[place.id] = targets
  if place.kind == 'station' then
   local def = layout(place)
   for i,d in ipairs(def.docks) do
    for _, side in ipairs(d.both and {1,-1} or {1}) do
     local prefix = place.id .. '@' .. i .. ':' .. side
     local function dockNode(suffix, distance)
      local x, y = distance*side+(d.xc or 0), d.yc or 0
      return node(prefix..suffix, {location=place.id,
       x=x*cos(d.a)-y*sin(d.a), y=x*sin(d.a)+y*cos(d.a)})
     end
     local extent = d.x2+d.runway
     for _, part in ipairs(def.parts) do
      for k=1,#part.shape,2 do
       local x = part.shape[k]*cos(d.a)+part.shape[k+1]*sin(d.a)
       extent = math.max(extent,(x-(d.xc or 0))*side+600)
      end
     end
     local approach = dockNode(':approach',d.x2+d.runway*.6)
     local staging = dockNode(':staging',extent)
     targets[#targets+1] = approach
     attachments[#attachments+1] = staging
     link(approach,staging,true)
    end
   end
  else
   node(place.id,{location=place.id})
   targets[1]=place.id; attachments[#attachments+1]=place.id
  end
 end
 if #attachments==0 then return graph end
 local radius = math.max((f.planetR or 0)+2500,f.stationTrack or 5000)
 local ring={}
 for i=1,16 do
  local a=(i-1)*2*pi/16
  ring[i]=node(area..'/nav_'..i,{x=cos(a)*radius,y=sin(a)*radius})
 end
 for i=1,16 do link(ring[i],ring[i%16+1]) end
 for _, id in ipairs(attachments) do
  local x,y=G.position(graph,id,clock)
  local near={}
  for _, rid in ipairs(ring) do
   local xx,yy=G.position(graph,rid,clock)
   near[#near+1]={id=rid,d=(xx-x)^2+(yy-y)^2}
  end
  table.sort(near,function(a,b) return a.d<b.d end)
  link(id,near[1].id); link(id,near[2].id)
 end
 return graph
end

local function length(graph,edge,clock)
 local x,y=G.point(graph,edge,0,clock)
 local total=0
 for i=1,24 do
  local xx,yy=G.point(graph,edge,i/24,clock)
  total=total+sqrt((xx-x)^2+(yy-y)^2); x,y=xx,yy
 end
 return total
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
   local nextCost=cost+length(graph,edge,clock)/(speed or 600)
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

-- Developer-only visualization; the marker is not an NPC or a physics body.
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
 local demo=game.travelGraphDemo
 if demo and demo.graph==view then
  lg.setColor(1,.75,.2,.9); lg.setLineWidth(2*px)
  for _,leg in ipairs(demo.route.legs) do drawEdge(leg.edge) end
  local p=G.sample(view,demo.route,clock-demo.started,clock)
  lg.circle('fill',p.x,p.y,5*px)
  lg.line(p.x,p.y,p.x+cos(p.heading)*22*px,p.y+sin(p.heading)*22*px)
 end
 lg.setColor(.5,.85,1,.8)
 for _,id in ipairs(view.order) do local x,y=G.position(view,id,clock); lg.circle('line',x,y,3*px) end
 lg.pop()
end
return G
