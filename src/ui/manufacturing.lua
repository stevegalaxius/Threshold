local Dealers=require('src.dealers')
local Station=require('src.ui.station')
local HUD=require('src.hud')
local data=require('src.data')
local View={}

local function rows(game)
 local st=game.player.dockState.station
 local state,def=Dealers.state(game.universe,st)
 local x,y,w,h=Station.body()
 local order=state.playerOrder
 local rows={}
 for i,id in ipairs(def.hulls) do
  local hull=data.hulls[id]
  local price=Dealers.price(hull,hull.loadout,def.markup)
  rows[i]={x=x+16,y=y+65+(i-1)*42,w=w-32,h=32,hull=hull,price=price}
 end
 return st,order,rows,x,y,w,h
end

local function inside(r,x,y)
 return x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h
end

function View.draw(game,mx,my)
 local _,order,entries,x,y,w,h=rows(game)
 local lg=love.graphics
 Station.panel(x,y,w,h)
 lg.setFont(HUD.font(20))
 lg.setColor(HUD.INK)
 lg.print('Manufacturing orders',x+16,y+12)
 lg.setFont(HUD.font(14))
 lg.setColor(HUD.DIM)
 local status='Order a stock-fit ship and collect it here when assembly finishes.'
 if order then
  status=data.hulls[order.hull].name..(order.lot and ' is ready to collect in Hangar.' or ' is in the assembly queue.')
 end
 lg.print(status,x+16,y+40)
 for _,row in ipairs(entries) do
  local ordered=order and order.hull==row.hull.id
  local label=ordered and (order.lot and 'Ready to collect' or 'Cancel and refund') or 'Order '..row.hull.name..'  ·  '..HUD.credits(row.price)
  local enabled=ordered or not order and game.universe.credits>=row.price
  Station.button(row,label,inside(row,mx,my),enabled)
 end
end

function View.mousepressed(game,mx,my,button)
 if button~=1 then return end
 local st,order,entries=rows(game)
 for _,row in ipairs(entries) do
  if inside(row,mx,my) then
   if order and order.hull==row.hull.id and order.lot then return 'collect',order.lot end
   if order and order.hull==row.hull.id then
    local ok,why=Dealers.cancelShipOrder(game.universe,st)
    game:toast(ok and 'BUILD CANCELED. FUNDS RETURNED' or why,1.5)
   else
    local ok,why=Dealers.orderShip(game.universe,st,row.hull.id)
    game:toast(ok and 'BUILD ORDER PLACED' or why,1.5)
   end
   return
  end
 end
end

return View
