-- Teleporting into view must wake existing records without a forced refresh.
return function(game)
 local A=require('src.alife');local copy=require('src.persistence').copy
 local Fuel=require('src.reactor_fuel');local L=require('src.locations')
 game:loadField('earth');game:captureALife(true)
 local records={}
 local node=require('src.fields').earth.buoyIds[1]
 local x,y=L.position(node,game.universe.clock)
 for _,group in ipairs({'patrol','trader'}) do
  local template
  for _,r in pairs(game.universe.npcs) do
   if r.home=='earth' and r.populationGroup==group then template=r;break end
  end
  assert(template,'missing activation fixture: '..group)
  local r=copy(template)
  r.id='activation/'..group;r.area='earth';r.state='idle';r.node=node
  r.route={node,node};r.index=1;r.untilTime=game.universe.clock+600
  r.task=nil;r.service=nil;r.action=nil;r.encounter=nil;r.offset=nil
  r.pose=nil;r.savedOnline=nil;r.driverArrival=nil;r.transit=nil
  r.ship.cargo[Fuel.item()]=30;r.ship.fuelCharge=2500
  r.ship.armor=require('src.npc_repair').maximum(r)
  records[r.id]=r
 end
 game.universe.npcs=records;game.universe.populationSpawns={}
 game.universe.economyNext=math.huge;game.universe.encounterNext=math.huge
 game.player.body:setPosition(x+500,y)
 game.camera.x=x+500;game.camera.y=y;game.camera.zoom=.7
 game.alifeNext=0
 local sx,sy=game.camera:toScreen(x,y)
 local width,height=love.graphics.getDimensions()
 assert(sx>=0 and sx<=width and sy>=0 and sy<=height,'activation fixtures must be on-screen')
 game:updateALife()
 for id in pairs(records) do
  assert(game.alifeOnline[id],'visible nearby NPC stayed offline: '..id)
 end
 print('NPC ACTIVATION: visible police and hauler woke without force')
end
