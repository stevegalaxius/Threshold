-- Local offline travel: graph edges and elapsed time, never physics bodies.
local L = require('src.locations')
local Fields = require('src.fields')
local G = {}
local pi, cos, sin, sqrt, atan2 = math.pi, math.cos, math.sin, math.sqrt, math.atan2
local function endpoint(id) local k=L.get(id).kind;return k=='moon_gate' or k=='driver' end
local function delta(a, b) return (b - a + pi) % (2 * pi) - pi end

function G.position(graph, id, clock)
 local n = assert(graph.nodes[id], 'unknown travel node ' .. tostring(id))
 return L.position(n.location, clock)
end

function G.interpolate(x,y,xx,yy,progress,incoming,outgoing)
 -- The coarse route goes around the planet instead of cutting across it.
 local r, rr = sqrt(x*x+y*y), sqrt(xx*xx+yy*yy)
 local turn = progress
 -- Finish turning early: the final approach to a fixed gate is radial,
 -- rather than a spiral that reaches the boundary almost sideways.
 if outgoing then
  turn = 1 - (1-progress)^3
 elseif incoming then
  turn = progress^3
 end
 local a = atan2(y,x) + delta(atan2(y,x), atan2(yy,xx))*turn
 r = r + (rr-r)*progress
 return cos(a)*r, sin(a)*r
end

function G.point(graph,edge,progress,clock)
 local x,y=G.position(graph,edge.from,clock)
 local xx,yy=G.position(graph,edge.to,clock)
 return G.interpolate(x,y,xx,yy,progress,endpoint(edge.from),endpoint(edge.to))
end

function G.withSpread(x,y,progress,spread)
 local radius=math.sqrt(x*x+y*y)
 if radius>0 then
  local across=(spread or 0)*math.sin(math.pi*progress)
  x,y=x+x/radius*across,y+y/radius*across
 end
 return x,y
end

-- Connectivity is authored in fields.lua; physical positions never add links.
-- Built graphs are kept per area until its navigation version changes:
-- route planning used to rebuild the area's graph on every call.
local built={}
function G.build(area)
 local f = assert(Fields[area], 'unknown area')
 local g=built[area]
 if g and g.version==f.navigationVersion then return g end
 g=G.fresh(area);built[area]=g
 return g
end
function G.fresh(area)
 local f = assert(Fields[area], 'unknown area')
 local graph = {area=area, version=f.navigationVersion, nodes={}, edges={}, destinations={}, order={}}
 for _,place in ipairs(L.list(area)) do
  graph.nodes[place.id]={location=place.id,links={},owner=place.owner,
   market=place.marketId,danger=place.danger,capacity=place.capacity}
  graph.order[#graph.order+1]=place.id
  graph.destinations[place.id]={place.id}
 end
 -- A station's extra access points (accessOf) are more ways to reach it:
 -- a route to the station may end, or start, at any of them.
 for _,place in ipairs(L.list(area)) do
  if place.accessOf and graph.destinations[place.accessOf] then
   table.insert(graph.destinations[place.accessOf],place.id)
  end
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
function G.transit(from,to,clock)
 local a,b=L.get(from),L.get(to)
 if a.kind=='driver' and b.kind=='driver' and a.area~=b.area then
  return {kind='driver',from=a.area,to=b.area,length=Fields.laneLength(Fields.distance(a.area,b.area,clock or 0))}
 end
 if a.kind~='moon_gate' or b.kind~='moon_gate' or a.destination~=b.area or b.destination~=a.area then return nil end
 local moon=Fields.moons[a.area] and Fields.moons[a.area].parent==b.area and a.area
  or Fields.moons[b.area] and Fields.moons[b.area].parent==a.area and b.area
 if moon then return {from=a.area,to=b.area,moon=moon,length=Fields.moons[moon].gap} end
 local ma,mb=Fields.moons[a.area],Fields.moons[b.area]
 if ma and mb and ma.parent==mb.parent then
  local _,length=Fields.moonLink(a.area,b.area)
  return {from=a.area,to=b.area,moon=a.area,length=length}
 end
end

-- Shared inter-region itinerary. Local legs always use declared connections;
-- moons use paired gates, planets use their existing mass drivers.
-- Planning a route walks every node's line of sight, and the economy asks
-- for every station pair each tick: that burst was a multi-second stall.
-- Answers are reused for a minute of game time (corridors rotate slowly),
-- and each caller gets its own copy to change.
local plans,plansAt={},nil
local plan
function G.itinerary(source,target,clock)
 clock=clock or 0
 if not plansAt or clock<plansAt or clock-plansAt>60 then plans,plansAt={},clock end
 local key=source..'|'..target
 local hit=plans[key]
 if hit==nil then hit=plan(source,target,clock) or false;plans[key]=hit end
 if not hit then return nil end
 local copy={};for i,id in ipairs(hit) do copy[i]=id end
 return copy
end
plan=function(source,target,clock)
 local a,b=L.byId[source],L.byId[target]
 if not a or not b then return nil end
 if source==target then return {source} end
 local function join(left,right)
  if not left or not right then return end
  for _,id in ipairs(right) do left[#left+1]=id end
  return left
 end
 if a.area~=b.area then
  local moon=Fields.moons[a.area]
  local other=Fields.moons[b.area]
  if moon and other and moon.parent==other.parent then
   return join(G.itinerary(source,a.area..'/to_'..b.area,clock),G.itinerary(b.area..'/to_'..a.area,target,clock))
  end
  if moon then
   return join(G.itinerary(source,a.area..'/to_'..moon.parent,clock),G.itinerary(moon.parent..'/to_'..a.area,target,clock))
  end
  moon=Fields.moons[b.area]
  if moon then
   return join(G.itinerary(source,moon.parent..'/to_'..b.area,clock),G.itinerary(b.area..'/to_'..moon.parent,target,clock))
  end
  local from,to=Fields[a.area].driverId,Fields[b.area].driverId
  if not from or not to then return end
  return join(G.itinerary(source,from,clock),G.itinerary(to,target,clock))
 end
 local path=G.route(G.build(a.area),source,target,clock)
 if not path then return end
 local route={source}
 for _,leg in ipairs(path.legs) do route[#route+1]=leg.edge.to end
 return route
end

function G.wreckPoint(w,clock)
 if w.worldPosition then return w.worldPosition.x,w.worldPosition.y end
 return G.point(G.build(w.area),{from=w.from,to=w.to},w.progress,clock)
end

function G.length(graph,edge,clock)
 if endpoint(edge.from) or endpoint(edge.to) then
  -- Integrate speed along the polar curve without sampling NPC positions:
  -- remote simulation only needs a duration, not a flight-path pose.
  local x,y=G.position(graph,edge.from,clock)
  local xx,yy=G.position(graph,edge.to,clock)
  local r,rr=sqrt(x*x+y*y),sqrt(xx*xx+yy*yy)
  local angle=delta(atan2(y,x),atan2(yy,xx))
  local outgoing=endpoint(edge.to)
  local length=0
  for i=1,64 do
   local p=(i-.5)/64
   local turnRate=3*(outgoing and (1-p)^2 or p^2)
   length=length+sqrt((rr-r)^2+((r+(rr-r)*p)*angle*turnRate)^2)/64
  end
  return length
 end
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
 local ar,br=sqrt(ax*ax+ay*ay),sqrt(bx*bx+by*by)
 if (endpoint(edge.from) or endpoint(edge.to)) and math.abs(br-ar)>1 then
  p=(sqrt(x*x+y*y)-ar)/(br-ar)
 elseif math.abs(angle)>.001 then
  p=delta(atan2(ay,ax),atan2(y,x))/angle
 else
  local dx,dy=bx-ax,by-ay
  p=((x-ax)*dx+(y-ay)*dy)/math.max(dx*dx+dy*dy,1)
 end
 return math.max(0,math.min(1,p))
end

-- An external destination joins the corridor at its closest existing node.
-- Evaluate at planning time because the corridor rotates beneath fixed exits.
function G.attachment(graph,id,clock)
 if L.get(id).kind~='moon_gate' then return end
 local x,y=G.position(graph,id,clock)
 local best,distance=nil,math.huge
 for _,edge in ipairs(graph.nodes[id].links) do
  local nx,ny=G.position(graph,edge.to,clock)
  local d=(nx-x)^2+(ny-y)^2
  if d<distance then best,distance=edge.to,d end
 end
 return best
end

-- Line of sight: besides its authored links, a node can fly straight to any
-- other ordinary node whose bearing (where both are now) is within
-- T.directLinkAngle. Flights follow the planet's curve, so they never cross
-- it; gates and mass drivers keep their authored approaches, and ladder
-- anchors never link to each other (the cables run between them).
local function ordinary(id) return not endpoint(id) end
function G.neighbours(graph,id,clock)
 local links=graph.nodes[id].links
 if not ordinary(id) then return links end
 local T=require('src.tuning')
 local f=Fields[graph.area];local ladder={}
 for _,a in ipairs(f.ladderIds or {}) do ladder[a]=true end
 local x,y=G.position(graph,id,clock)
 local result,seen={},{}
 for _,edge in ipairs(links) do result[#result+1]=edge;seen[edge.to]=true end
 for _,other in ipairs(graph.order) do
  if other~=id and not seen[other] and ordinary(other) and not (ladder[id] and ladder[other]) then
   local xx,yy=G.position(graph,other,clock)
   if math.abs(delta(atan2(y,x),atan2(yy,xx)))<=T.directLinkAngle then
    result[#result+1]={from=id,to=other,direct=true}
   end
  end
 end
 return result
end

function G.route(graph,from,to,clock,speed)
 assert(speed==nil or speed>0,'travel speed must be positive')
 local starts, goals=graph.destinations[from],graph.destinations[to]
 if not starts or not goals then return nil,'destination is outside this local graph' end
 local attachments={}
 for _,id in ipairs(graph.order) do
  attachments[id]=G.attachment(graph,id,clock)
 end
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
  for _,edge in ipairs(G.neighbours(graph,best,clock)) do
   -- Gates are endpoints, never shortcuts between corridor nodes.
   if (not attachments[best] or attachments[best]==edge.to)
    and (not attachments[edge.to] or attachments[edge.to]==best)
    and (L.get(edge.to).kind~='moon_gate' or edge.to==to)
    -- the Heaven-Ladder's anchors sit in the planet's pull: only ships
    -- bound for the ladder go there, never as a shortcut across Mars
    and (L.get(edge.to).layout~='ladder_anchor' or goalSet[edge.to]) then
    local nextCost=cost+G.length(graph,edge,clock)/(speed or 600)
    if not dist[edge.to] or nextCost<dist[edge.to] then
     dist[edge.to]=nextCost; prev[edge.to]={edge=edge,duration=nextCost-cost}
    end
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

return G
