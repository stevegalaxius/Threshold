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
G.planned=0
local plan
function G.plan(source,target,clock,exact) return plan(source,target,clock,exact) end
-- exact keeps physical endpoints (e.g. a particular home anchor); ordinary
-- trade destinations can still use any access point of the shared station.
-- (each answer keeps for 75 to 105 seconds, a different while for each pair:
-- when they were all dropped together every minute, the next step that
-- asked anything planned the whole map again at once. Now and then the
-- ones nobody has asked for since are swept out.)
local planTurn=0
-- With the background thread (src/worker.lua) an answer past 45 seconds old
-- is still given, and a fresh one asked of the thread to take its place:
-- pairs that are asked about again and again (the economy's, every minute)
-- are then never planned on the main thread after the first time.
local function navigationVersion(id)
 local place=L.byId[id];local f=place and Fields[place.area]
 return f and f.navigationVersion or 0
end
function G.versionOf(source,target) return navigationVersion(source)..':'..navigationVersion(target) end
local staleMap=false
function G.itinerary(source,target,clock,exact)
 clock=clock or 0
 if not plansAt or clock<plansAt then plans,plansAt={},clock end
 if clock-plansAt>300 then
  for k,entry in pairs(plans) do if clock>entry.fresh then plans[k]=nil end end
  plansAt=clock
 end
 local key=source..'|'..target..(exact and '|exact' or '')
 local entry=plans[key]
 if not entry or clock>entry.fresh or clock<entry.at then
  planTurn=(planTurn+7)%31
  entry={at=clock,soft=clock+45,fresh=clock+75+planTurn,path=plan(source,target,clock,exact) or false}
  plans[key]=entry
 elseif clock>entry.soft and not entry.asked and not staleMap then
  local Worker=require('src.worker')
  if Worker.active() then
   entry.asked=true
   local table_=plans
   Worker.ask('route',{source,target,clock,exact or false,G.versionOf(source,target)},function(path)
    -- (the thread's map isn't this one: plan here from now on)
    if path=='stale' then staleMap=true;return end
    if plans~=table_ then return end
    planTurn=(planTurn+7)%31
    plans[key]={at=clock,soft=clock+45,fresh=clock+75+planTurn,path=path}
   end)
  end
 end
 local hit=entry.path
 if not hit then return nil end
 local copy={};for i,id in ipairs(hit) do copy[i]=id end
 return copy
end
plan=function(source,target,clock,exact)
 G.planned=G.planned+1   -- (work done, for whoever is rationing it: src/economy.lua)
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
   return join(G.itinerary(source,a.area..'/to_'..b.area,clock,exact),G.itinerary(b.area..'/to_'..a.area,target,clock,exact))
  end
  if moon then
   return join(G.itinerary(source,a.area..'/to_'..moon.parent,clock,exact),G.itinerary(moon.parent..'/to_'..a.area,target,clock,exact))
  end
  moon=Fields.moons[b.area]
  if moon then
   return join(G.itinerary(source,moon.parent..'/to_'..b.area,clock,exact),G.itinerary(b.area..'/to_'..moon.parent,target,clock,exact))
  end
  -- Extra drivers share the interplanetary connection, but retain separate
  -- approaches and queues. Choose each end by its local travel cost.
  local function driver(area,node,outbound)
   local best,cost
   for _,id in ipairs(Fields[area].driverIds or {}) do
    local path=G.route(G.build(area),outbound and node or id,outbound and id or node,clock,nil,exact)
    if path and (not cost or path.duration<cost) then best,cost=id,path.duration end
   end
   return best
  end
  local from,to=driver(a.area,source,true),driver(b.area,target,false)
  if not from or not to then return end
  return join(G.itinerary(source,from,clock,exact),G.itinerary(to,target,clock,exact))
 end
 local path=G.route(G.build(a.area),source,target,clock,nil,exact)
 if not path then return end
 local route={source}
 for _,leg in ipairs(path.legs) do route[#route+1]=leg.edge.to end
 return route
end

function G.wreckPoint(w,clock)
 if w.worldPosition then return w.worldPosition.x,w.worldPosition.y end
 return G.point(G.build(w.area),{from=w.from,to=w.to},w.progress,clock)
end

local function lengthBetween(x,y,xx,yy,fromEnd,toEnd)
 if fromEnd or toEnd then
  -- Integrate speed along the polar curve without sampling NPC positions:
  -- remote simulation only needs a duration, not a flight-path pose.
  local r,rr=sqrt(x*x+y*y),sqrt(xx*xx+yy*yy)
  local angle=delta(atan2(y,x),atan2(yy,xx))
  local length=0
  for i=1,64 do
   local p=(i-.5)/64
   local turnRate=3*(toEnd and (1-p)^2 or p^2)
   length=length+sqrt((rr-r)^2+((r+(rr-r)*p)*angle*turnRate)^2)/64
  end
  return length
 end
 local r,rr=sqrt(x*x+y*y),sqrt(xx*xx+yy*yy)
 local arc=delta(atan2(y,x),atan2(yy,xx))*(r+rr)/2
 return sqrt((rr-r)^2+arc^2)
end
function G.length(graph,edge,clock)
 local x,y=G.position(graph,edge.from,clock)
 local xx,yy=G.position(graph,edge.to,clock)
 return lengthBetween(x,y,xx,yy,endpoint(edge.from),endpoint(edge.to))
end

-- Where everything in an area is at one instant, worked out once and shared
-- by every route planned there at that instant. A plan asks where each node
-- is for every node it passes, and a burst of plans (the economy's pairs, a
-- trader weighing jobs) all ask at the same clock: placing every node again
-- for each was most of what planning cost. Neighbours, corridor attachments
-- and leg lengths are filled in as they're first asked for.
local function snapshot(graph,clock)
 local s=graph.snap
 if s and s.clock==clock then return s end
 s={clock=clock,x={},y={},angle={},neighbours={},length={}}
 for _,id in ipairs(graph.order) do
  local x,y=G.position(graph,id,clock)
  s.x[id],s.y[id],s.angle[id]=x,y,atan2(y,x)
 end
 if not graph.ends then
  -- (what kind of node each is never changes while the graph stands)
  graph.ends,graph.ladder={},{}
  for _,id in ipairs(graph.order) do graph.ends[id]=endpoint(id) end
  for _,a in ipairs(Fields[graph.area].ladderIds or {}) do graph.ladder[a]=true end
 end
 graph.snap=s
 return s
end
local function legLength(graph,s,edge)
 local from=s.length[edge.from];if not from then from={};s.length[edge.from]=from end
 local n=from[edge.to]
 if not n then
  n=lengthBetween(s.x[edge.from],s.y[edge.from],s.x[edge.to],s.y[edge.to],graph.ends[edge.from],graph.ends[edge.to])
  from[edge.to]=n
 end
 return n
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

-- Line of sight: besides its authored links, a node can fly straight to any
-- other node whose bearing (where both are now) is within T.directLinkAngle.
-- Flights follow the planet's curve, so they never cross it. Gates and mass
-- drivers are endpoints: a ship may leave or arrive by one from any node in
-- sight of it (plus its authored approaches), but never passes through one
-- on the way somewhere else (G.route). Ladder anchors never link to each
-- other (the cables run between them).
-- Endpoints used to join the corridor at only their single nearest node, so
-- every route in or out was forced through that one buoy or station even
-- when it lay behind the ship: it flew out to it and doubled back.
-- (the list is shared between plans at the same instant: read it, don't change it)
function G.neighbours(graph,id,clock)
 local s=snapshot(graph,clock)
 local result=s.neighbours[id]
 if result then return result end
 local links=graph.nodes[id].links
 local T=require('src.tuning')
 local ladder,ends=graph.ladder,graph.ends
 local angle=s.angle[id]
 local seen={}
 result={}
 for _,edge in ipairs(links) do result[#result+1]=edge;seen[edge.to]=true end
 for _,other in ipairs(graph.order) do
  if other~=id and not seen[other] and not (ends[id] and ends[other]) and not (ladder[id] and ladder[other]) then
   if math.abs(delta(angle,s.angle[other]))<=T.directLinkAngle then
    result[#result+1]={from=id,to=other,direct=true}
   end
  end
 end
 s.neighbours[id]=result
 return result
end

function G.route(graph,from,to,clock,speed,exact)
 assert(speed==nil or speed>0,'travel speed must be positive')
 local starts, goals=graph.destinations[from],graph.destinations[to]
 if exact and starts and goals then starts,goals={from},{to} end
 if not starts or not goals then return nil,'destination is outside this local graph' end
 local s=snapshot(graph,clock)
 local ends=graph.ends
 local through=false
 ::search::
 local dist,prev,done={}, {}, {}
 for _,id in ipairs(starts) do dist[id]=0 end
 local goalSet={}; for _,id in ipairs(goals) do goalSet[id]=true end
 local finish
 while true do
  local best, cost=nil,math.huge
  for _,id in ipairs(graph.order) do
   if not done[id] and dist[id] and dist[id]<cost then best,cost=id,dist[id] end
  end
  if not best then
   -- Two opposite buoys and nothing else (Neptune) can only reach each
   -- other round by the mass driver: let an endpoint be passed only then.
   if not through then through=true;goto search end
   return nil,'no route'
  end
  if goalSet[best] then finish=best; break end
  done[best]=true
  for _,edge in ipairs(G.neighbours(graph,best,clock)) do
   -- Gates and drivers are endpoints, never shortcuts between other nodes.
   if (through or not ends[edge.to] or goalSet[edge.to])
    -- the Heaven-Ladder's anchors sit in the planet's pull: only ships
    -- bound for the ladder go there, never as a shortcut across Mars
    and (not L.get(edge.to).radial or goalSet[edge.to]) then
    local nextCost=cost+legLength(graph,s,edge)/(speed or 600)
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
