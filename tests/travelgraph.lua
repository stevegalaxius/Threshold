return function(game)
 local G,L,Fields=require('src.travelgraph'),require('src.locations'),require('src.fields')
 local checks=0
 local function check(ok,msg) assert(ok,msg); checks=checks+1 end
 local bodies,field=game.world:getBodyCount(),game.fieldId
 for _,area in ipairs(Fields.list) do
  local graph=G.build(area,500)
  local places=L.list(area)
  for i=1,#places do
   local from,to=places[i].id,places[i%#places+1].id
   local route=assert(G.route(graph,from,to,500))
   check(route.duration>=0,'negative travel time')
   local p=G.sample(graph,route,0,500)
   local x,y=G.position(graph,route.start,500)
   check(math.abs(x-p.x)+math.abs(y-p.y)<.01,'incorrect start')
   local endClock=500+route.duration+10
   p=G.sample(graph,route,route.duration+10,endClock)
   x,y=G.position(graph,route.finish,endClock)
   check(p.arrived and math.abs(x-p.x)+math.abs(y-p.y)<.01,'missed moving destination')
   for _,leg in ipairs(route.legs) do
    for k=0,10 do
     local xx,yy=G.point(graph,leg.edge,k/10,500)
     check(xx==xx and yy==yy,'nonfinite route')
     if Fields[area].planetR and not Fields[area].gas then
      check(xx*xx+yy*yy>Fields[area].planetR^2,area..': route crosses surface')
     end
    end
   end
  end
 end
 check(game.world:getBodyCount()==bodies and game.fieldId==field,'offline graph loaded physics')
 local graph=G.build('earth',500)
 local ids=Fields.earth.stationIds
 local route=assert(G.route(graph,ids[1],ids[2],500))
 local halfway=G.sample(graph,route,route.duration*.5,500+route.duration*.5)
 check(not halfway.arrived and halfway.vx==halfway.vx,'invalid in-flight sample')
 local Save=require('src.save')
 local decoded=assert(Save.decode(Save.encode(route)))
 check(decoded.finish==route.finish and #decoded.legs==#route.legs,'route not serializable')
 game.universe.clock=500; game:loadField('earth')
 graph=G.build('earth',500)
 local st=assert(game:locationEntity(ids[1]))
 local id=graph.destinations[ids[1]][1]
 local x,y=G.position(graph,id,500)
 local d=st.def.docks[1]
 local xx,yy=game.dockWorld(st,1,d.x2+d.runway*.6,0,d)
 check(math.abs(x-xx)+math.abs(y-yy)<.01,'approach differs from live runway')
 -- Both cloud-city tunnel entrances use exactly the live docking transforms.
 for _,area in ipairs({'jupiter','uranus'}) do
  game:loadField(area)
  local cityId=Fields[area].stationIds[1]
  st=assert(game:locationEntity(cityId)); graph=G.build(area,game.universe.clock)
  for i,side in ipairs({1,-1}) do
   d=st.def.docks[1]
   x,y=G.position(graph,graph.destinations[cityId][i],game.universe.clock)
   xx,yy=game.dockWorld(st,side,d.x2+d.runway*.6,0,d)
   check(math.abs(x-xx)+math.abs(y-yy)<.01,'cloud-city approach mismatch')
  end
 end
 game.travelGraphView=graph
 route=assert(G.route(graph,Fields.uranus.stationIds[1],Fields.uranus.driverId,game.universe.clock))
 game.travelGraphDemo={graph=graph,route=route,started=game.universe.clock}
 G.draw(game,1)
 game.travelGraphView,game.travelGraphDemo=nil,nil
 print(('TRAVEL GRAPH TEST PASSED (%d checks)'):format(checks))
end
