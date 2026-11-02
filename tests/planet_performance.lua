-- Diagnostic timings depend on hardware; compare the same build/view settings.
return function(game)
 local Render=require('src.render')
 require('src.tuning').dev.god=true;game.autosaveOff=true
 local timer=love.timer.getTime
 local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
 for _,area in ipairs({'earth','jupiter','saturn'}) do
  love.math.setRandomSeed(157)
  game:loadField(area)
  local R=game.field.planetR
  for _,view in ipairs({'station','rings'}) do
   local x,y=game.field.spawn[1],game.field.spawn[2]
   if view=='rings' then x,y=0,-(R+(game.field.radius-R)*.3) end
   game.player.body:setPosition(x,y);game.player.body:setLinearVelocity(0,0)
   for _=1,120 do game:step(1/120) end
   game.camera.x,game.camera.y=x,y;game.camera.zoom=.5
   collectgarbage('collect')
   local wakeTime=0
   local original=game.updateSleepers
   game.updateSleepers=function(self,...)
    local start=timer();original(self,...);wakeTime=wakeTime+timer()-start
   end
   local start=timer()
   for _=1,1200 do game:step(1/120) end
   local update=(timer()-start)/1200*1000
   game.updateSleepers=original
   local poses=0;local position=game.sleeperPos
   game.sleeperPos=function(self,...) poses=poses+1;return position(self,...) end
   -- Warm meshes and GPU work before measuring repeated draw submission.
   for _=1,10 do love.graphics.setCanvas(canvas);Render.world(game);love.graphics.setCanvas();love.graphics.flushBatch() end
   poses=0;start=timer()
   for _=1,120 do
    love.graphics.setCanvas(canvas);Render.world(game);love.graphics.setCanvas();love.graphics.flushBatch()
   end
   local draw=(timer()-start)/120*1000
   game.sleeperPos=position
   print(('%s %s: %d bodies, %d sleeping; step %.3fms (sleep %.3fms), draw-submit %.3fms; %d sleeper poses/draw'):format(
    area,view,game.world:getBodyCount(),#game.sleepers,update,wakeTime/1200*1000,draw,poses/120))
  end
 end
end
