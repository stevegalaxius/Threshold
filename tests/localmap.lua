return function(game)
 local Map=require('src.ui.localmap')
 local Fields=require('src.fields')
 local Graph=require('src.travelgraph')
 local checks=0
 local function check(ok,msg) assert(ok,msg); checks=checks+1 end
 local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
 local function draw(name)
  love.graphics.setCanvas(canvas); love.graphics.clear()
  Map.draw(game)
  love.graphics.setCanvas()
  if name then canvas:newImageData():encode('png',name) end
 end
 game.autosaveOff=true
 for _,area in ipairs(Fields.list) do
  game:loadField(area)
  local cx,cy,zoom=game.camera.x,game.camera.y,game.camera.zoom
  check(Map.keypressed(game,'m') and Map.isOpen(game),'M did not open map')
  local w,h=love.graphics.getDimensions()
  for _,p in ipairs(Map.places(game)) do
   local x,y=Map.toScreen(game,p.x,p.y)
   check(x>=24 and x<=w-304 and y>=88 and y<=h-66,area..': destination not in fitted view')
   local xx,yy=Map.toWorld(game,x,y)
   check(math.abs(xx-p.x)+math.abs(yy-p.y)<.01,'map transform not reversible')
  end
  draw(area=='earth' and 'local-map-earth.png' or nil)
  local x,y=Map.toScreen(game,game.player.body:getPosition())
  check(x>=24 and x<=w-304 and y>=88 and y<=h-66,'player not fitted')
  Map.keypressed(game,'p')
  local px,py=game.player.body:getPosition()
  check(game.localMap.x==px and game.localMap.y==py,'center on player failed')
  Map.keypressed(game,'home')
  love.mouse.setPosition(300,250)
  local wx,wy=Map.toWorld(game,300,250)
  Map.wheelmoved(game,2)
  local xx,yy=Map.toWorld(game,300,250)
  check(math.abs(wx-xx)+math.abs(wy-yy)<.01,'zoom did not preserve cursor anchor')
  check(Map.keypressed(game,'q'),'map leaked flight shortcut')
  check(game.camera.x==cx and game.camera.y==cy and game.camera.zoom==zoom,'map modified flight camera')
  check(Map.keypressed(game,'escape') and not Map.isOpen(game),'Escape did not close map')
 end
 game:loadField('jupiter'); Map.open(game)
 local graph=Graph.build('jupiter',game.universe.clock)
 game.travelGraphView=graph
 local route=assert(Graph.route(graph,Fields.jupiter.stationIds[1],Fields.jupiter.driverId,game.universe.clock))
 Map.fit(game); draw('local-map-graph.png')
 local first=Map.places(game)[1]
 local w=love.graphics.getWidth()
 Map.mousepressed(game,w-250,105,1)
 check(game.localMap.selected==first.id,'list selection failed')
 Map.mousepressed(game,100,200,2)
 love.mouse.setPosition(120,220); Map.update(game)
 check(game.localMap.drag~=nil,'drag not started')
 Map.mousereleased(game)
 check(not game.localMap.drag,'drag not released')
 game:loadField('earth'); Map.update(game)
 check(game.localMap.area=='earth','map did not follow region transition')
 -- The transit lane uses its own endpoints and curved highway, not planet coordinates.
 game:launchTrip('mars')
 Map.update(game)
 check(#Map.places(game)==2,'lane exits missing')
 draw('local-map-transit.png')
 Map.keypressed(game,'m')
 print(('LOCAL MAP TEST PASSED (%d checks); images: %s'):format(checks,love.filesystem.getSaveDirectory()))
end
