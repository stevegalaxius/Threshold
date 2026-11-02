return function(game)
 local G,L,Fields=require('src.travelgraph'),require('src.locations'),require('src.fields')
 local checks=0
 local function check(ok,msg) assert(ok,msg); checks=checks+1 end
 local bodies,field=game.world:getBodyCount(),game.fieldId
 for _,area in ipairs(Fields.list) do
  local graph=G.build(area)
  check(#graph.order==#L.list(area),area..': graph invented places')
  check(#graph.edges==#Fields[area].travelLinks,area..': graph invented connections')
  for _,id in ipairs(graph.order) do check(L.byId[id]~=nil,'synthetic node') end
  local seen={}
  for _,edge in ipairs(graph.edges) do
   local key=edge.from<edge.to and edge.from..'>'..edge.to or edge.to..'>'..edge.from
   check(not seen[key],'duplicate connection'); seen[key]=true
   local route=assert(G.route(graph,edge.from,edge.to,500))
   local p=G.sample(graph,route,0,500)
   local x,y=L.position(edge.from,500)
   check(math.abs(x-p.x)+math.abs(y-p.y)<.01,'incorrect start')
   local endClock=500+route.duration+10
   p=G.sample(graph,route,route.duration+10,endClock)
   x,y=L.position(edge.to,endClock)
   check(p.arrived and math.abs(x-p.x)+math.abs(y-p.y)<.01,'missed moving location')
   x,y=G.point(graph,edge,.37,500)
   check(math.abs(G.project(graph,edge,x,y,500)-.37)<.001,'could not recover existing journey progress')
  end
  local later=G.build(area)
  check(#later.edges==#graph.edges,'positions changed connectivity')
 end
 check(game.world:getBodyCount()==bodies and game.fieldId==field,'offline graph loaded physics')
 local graph=G.build('earth')
 check(#graph.order==6 and #graph.edges==8,'Earth should contain six actual places and eight declared links')
 local route=assert(G.route(graph,Fields.earth.stationIds[1],Fields.earth.stationIds[2],500))
 check(#route.legs==2,'station journey did not use existing buoy itinerary')
 -- Both direct departures and buoy routes must win in appropriate orbital
 -- configurations; adding links that the planner never uses fixes nothing.
 local viaBuoy,direct=false,false
 for clock=0,20000,100 do
  local home,gate=Fields.earth.stationIds[1],'earth/to_luna'
  local trip=assert(G.route(graph,home,gate,clock))
  local baseline=G.length(graph,{from=home,to=gate},clock)/600
  check(trip.duration<=baseline+.001,'buoy routing made the trip longer')
  if #trip.legs==1 then direct=true else
   for _,leg in ipairs(trip.legs) do
    if L.get(leg.edge.to).kind=='buoy' then viaBuoy=true end
   end
  end
 end
 check(viaBuoy,'moon routing never uses trade buoys')
 check(direct,'moon routing forces unnecessary buoy detours')
 local Save=require('src.save')
 local decoded=assert(Save.decode(Save.encode(route)))
 check(decoded.finish==route.finish and #decoded.legs==#route.legs,'route not serializable')
 print(('TRAVEL GRAPH TEST PASSED (%d checks)'):format(checks))
end
