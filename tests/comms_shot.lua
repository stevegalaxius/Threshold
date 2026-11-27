return function(game)
 local Comms=require('src.comms');local UI=require('src.ui.comms')
 for _=1,120 do game:step(1/60) end
 local p=game.player
 require('src.inventory.hold').add(p.hold,'fentanyl',3);p.cargo=require('src.inventory.hold').totals(p.hold)
 game.universe.credits=5000
 local police={kind='ship',def={name='Patrol Cutter'},cargo={}}
 local ch=require('src.contraband').inspect(game,police,p,'estates')
 ch.speaker.alifeRecord=nil
 game:frame(1/60)
 local function shot(name)
  local c=love.graphics.newCanvas()
  love.graphics.setCanvas(c);love.graphics.clear(0,0,0,1)
  require('src.render').world(game)
  require('src.hud').draw(game,0,0,false)
  UI.draw(game)
  love.graphics.setCanvas()
  c:newImageData():encode('png',name)
  print('saved',love.filesystem.getSaveDirectory()..'/'..name)
 end
 shot('comms_chip.png')
 UI.openId=ch.id
 shot('comms_hail.png')
 math.random=function() return 0 end
 Comms.choose(ch,1)
 shot('comms_caught.png')
end
