-- Shared debug travel: preserve the player's ship and use normal area capture.
local Fields=require('src.fields')
local Locations=require('src.locations')
local Ship=require('src.ship')
local Travel={query='',selected=nil}
function Travel.areas(query)
 local out={};query=(query or ''):lower()
 for _,id in ipairs(Fields.list) do
  local f=Fields[id]
  if not f.transit and (f.name:lower():find(query,1,true) or id:find(query,1,true)) then out[#out+1]=id end
 end
 return out
end
function Travel.go(game,area,place)
 assert(Fields[area] and not Fields[area].transit,'choose a named destination')
 if place then assert(Locations.get(place).area==area,'destination is in another area') end
 local p=game.player
 local record=p and not p.dead and p.body and not p.body:isDestroyed() and Ship.record(p) or nil
 require('src.ui.cargo').close(game)
 game:loadField(area,{player=record})
 game.flight=nil;game.trip=nil
 game.localMap=nil
 if place then
  local target=game:locationEntity(place)
  local x,y=Locations.position(place,game.universe.clock)
  local vx,vy=Locations.velocity(place,game.universe.clock)
  local angle=0
  if target and target.dock then
   x,y=game.dockWorld(target,1,target.dock.x2+target.dock.runway+game.player.halfLength+100,0)
   angle=game.dockAngle(target,1)+math.pi
   vx,vy=target.body:getLinearVelocityFromWorldPoint(x,y)
  else
   local r=math.sqrt(x*x+y*y)
   local offset=game.player.halfLength+300
   if r>0 then x,y=x+x/r*offset,y+y/r*offset else x=x+offset end
  end
  p=game.player;p.body:setPosition(x,y);p.body:setLinearVelocity(vx,vy)
  p.body:setAngle(angle);p.body:setAngularVelocity(0)
  game.camera.x,game.camera.y=x,y
  game:updateALife(true)
 end
 game:toast('DEBUG TELEPORT: '..(place and Locations.get(place).name or Fields[area].name),2)
end
function Travel.panel(game,Slab)
 Slab.Text('Find planet, moon or region')
 if Slab.Input('debug_travel_search',{Text=Travel.query,W=290}) then Travel.query=Slab.GetInputText() end
 Slab.Text('Preserves ship, equipment, cargo and damage.')
 local selected=Travel.selected or game.fieldId
 if Slab.BeginComboBox('debug_travel_area',{Selected=Fields[selected] and Fields[selected].name or 'Choose destination',W=290}) then
  for _,id in ipairs(Travel.areas(Travel.query)) do
   if Slab.TextSelectable(Fields[id].name) then Travel.selected=id end
  end
  Slab.EndComboBox()
 end
 local area=Travel.selected or game.fieldId
 if Fields[area] and not Fields[area].transit then
  Slab.Separator();Slab.Text('Destination: '..Fields[area].name)
  if Slab.Button('Teleport to area spawn',{W=290}) then Travel.go(game,area);return end
 end
end
function Travel.point(game,x,y)
 local p=game.player
 if not p or p.dead or not p.body or p.body:isDestroyed() then return false end
 require('src.ui.cargo').close(game)
 p.dockState=nil;p.dockExit=nil;p.dockCooldown=2
 p.body:setActive(true);p.body:setPosition(x,y)
 p.body:setLinearVelocity(0,0);p.body:setAngularVelocity(0)
 game.state='playing';game.camera.x,game.camera.y=x,y
 game:toast('DEBUG TELEPORT',1)
 return true
end
return Travel
