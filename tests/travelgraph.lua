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
 check(#graph.order==6 and #graph.edges==9,'Earth should contain six actual places and nine declared links')
 local route=assert(G.route(graph,Fields.earth.stationIds[1],Fields.earth.stationIds[2],500))
 check(#route.legs==2,'station journey did not use existing buoy itinerary')
 -- Choose the node nearest the destination, even when exiting earlier would
 -- minimize the old end-to-end cost. Check both directions as the nodes orbit.
 local seenAttachments={}
 for clock=0,20000,100 do
  local home,gate=Fields.earth.stationIds[1],'earth/to_luna'
  local gx,gy=L.position(gate,clock)
  local nearest,distance=nil,math.huge
  for _,id in ipairs(Fields.earth.traderRoute) do
   local x,y=L.position(id,clock)
   local d=(x-gx)^2+(y-gy)^2
   if d<distance then nearest,distance=id,d end
  end
  seenAttachments[nearest]=true
  local trip=assert(G.route(graph,home,gate,clock))
  check(trip.legs[#trip.legs].edge.from==nearest,'departure left network before nearest destination node')
  local back=assert(G.route(graph,gate,home,clock))
  check(back.legs[1].edge.to==nearest,'arrival did not join nearest network node')
 end
 local attachments=0
 for _ in pairs(seenAttachments) do attachments=attachments+1 end
 check(attachments==4,'attachment did not follow rotating stations and buoys')
 -- Every fixed exit should have a radial final approach at different phases,
 -- including small moons where the station can be opposite the gate.
 for _,area in ipairs(Fields.list) do
  local g=G.build(area)
  for _,edge in ipairs(g.edges) do
   if L.get(edge.to).kind=='moon_gate' or L.get(edge.from).kind=='moon_gate' then
    local e=L.get(edge.to).kind=='moon_gate' and edge or {from=edge.to,to=edge.from}
    for _,clock in ipairs({0,500,5000,20000}) do
     local x,y=G.point(g,e,.999,clock)
     local gx,gy=G.point(g,e,1,clock)
     local dx,dy=gx-x,gy-y
     local dot=(dx*gx+dy*gy)/math.sqrt((dx*dx+dy*dy)*(gx*gx+gy*gy))
     check(dot>.999,area..': gate approach is not radial')
     for _,p in ipairs({.1,.5,.9}) do
      x,y=G.point(g,e,p,clock)
      check(math.abs(G.project(g,e,x,y,clock)-p)<.001,area..': gate projection lost progress')
     end
    end
   end
  end
 end
 local Save=require('src.save')
 local decoded=assert(Save.decode(Save.encode(route)))
 check(decoded.finish==route.finish and #decoded.legs==#route.legs,'route not serializable')
 print(('TRAVEL GRAPH TEST PASSED (%d checks)'):format(checks))
end
