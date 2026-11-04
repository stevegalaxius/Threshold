return function(game)
 local W,L,E=require('src.world_layout'),require('src.locations'),require('src.world_authoring')
 local data,Shape=require('src.data'),require('src.hullshape')
 local Export=require('src.editor.export')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true;game:loadField('earth')
 local original=W.export()
 local design={id='test_nav_prop',name='Editor buoy',kind='prop',stats={},parts={
  {name='body',shape={-30,-12,30,-12,30,12,-30,12},color={.4,.7,.8},
   lights={{x=0,y=0,kind='strobe',color={1,.7,.2},size=4,rate=1}}},
 }}
 local def=assert(data.defineWreck(Export.wreckDef(design)))
 local ok=game:editWorldLayout(function(world)
  world.defaults.buoyProp=def.id
  world.navigation.earth.buoyProp=def.id
  local first=world.navigation.earth.buoys[1]
  first.prop='hull_plate';first.scale=2;first.heading=.4
 end)
 check(ok,'prop assignment was rejected')
 local ids=require('src.fields').earth.buoyIds
 local first,second=game:locationEntity(ids[1]),game:locationEntity(ids[2])
 check(first.propId=='hull_plate' and second.propId==def.id,'buoy/region prop selection failed')
 check(first.radius==data.wrecks.hull_plate.radius*2 and math.abs(first.body:getAngle()-.4)<.0001,'prop scale/heading was lost')
 check(first.kind=='buoy' and #first.body:getFixtures()==0,'visual prop changed navigation entity physics')
 check(L.get(require('src.fields').mars.buoyIds[1]).prop==def.id,'global buoy prop default was not applied')
 -- Render through the same parts and lights routines as editor-built models.
 -- Replacing the prop definition also updates an already spawned buoy visually.
 design.parts[1].shape={-50,-12,50,-12,50,12,-50,12}
 local latest=assert(data.defineWreck(Export.wreckDef(design)))
 local draw,lights=Shape.draw,Shape.drawLights;local seen,lit=false,false
 Shape.draw=function(model,...)
  if model.id==def.id then seen=model==latest end
  return draw(model,...)
 end
 Shape.drawLights=function(model,...)
  if model.id==def.id then lit=true end
  return lights(model,...)
 end
 local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
 love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear()
 require('src.render').world(game)
 love.graphics.setCanvas();love.graphics.pop();canvas:release()
 Shape.draw,Shape.drawLights=draw,lights
 check(seen and lit,'buoy did not render current prop geometry and editor lights')
 local invalid=game:editWorldLayout(function(world)world.navigation.earth.buoys[1].prop='missing_prop' end)
 check(not invalid and L.get(ids[1]).prop=='hull_plate','invalid prop did not roll back')
 check(E.import(game,original),'failed to restore buoy visuals')
 check(not game:locationEntity(ids[1]).propId,'unassigned buoy did not restore the legacy beacon')
 print(('F2 BUOY PROP TEST PASSED (%d checks)'):format(checks))
end
