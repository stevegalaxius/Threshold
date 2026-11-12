local Board=require('src.player_contracts')
local L=require('src.locations')
local HUD,Station=require('src.hud'),require('src.ui.station')
local data=require('src.data')
local View={scroll=0}
local lg=love.graphics
local function name(id) return L.byId[id] and L.byId[id].name or id end
local function item(id) return data.items[id] and data.items[id].name or id end
local function text(x,y,w,s,size,color)
 lg.setFont(HUD.font(size or 14));lg.setColor(color or HUD.INK);lg.printf(s,x,y,w)
end
local function inside(r,x,y) return x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h end
function View.layout(game)
 local x,y,w,h=Station.body();local t=Board.active(game);local here=Board.station(game)
 local out={x=x,y=y,w=w,h=h,active=t,here=here,rows={}}
 local top=y+12
 if t then
  out.activeRect={x=x,y=top,w=w,h=146}
  out.advance={x=x+w-190,y=top+16,w=174,h=34}
  out.cancel={x=x+w-190,y=top+62,w=174,h=30}
  top=top+158
 else
  top=top+48
 end
 out.listY=top+38
 if here then
  local list=Board.list(game);out.count=#list
  local height=104;local bottom=y+h
  View.scroll=math.max(0,math.min(View.scroll,math.max(0,#list*height-(bottom-out.listY))))
  for i,o in ipairs(list) do
   local ry=out.listY+(i-1)*height-View.scroll
   if ry>=out.listY and ry+height<=bottom then
    local q,why=Board.quote(game,o)
    out.rows[#out.rows+1]={offer=o,quote=q,why=why,x=x,y=ry,w=w,h=96,
     button={x=x+w-190,y=ry+48,w=174,h=32}}
   end
  end
 end
 return out
end
function View.draw(game)
 local f=View.layout(game);local t=f.active
 if t then
  local r=f.activeRect;Station.panel(r.x,r.y,r.w,r.h)
  text(r.x+14,r.y+12,r.w-220,'ACTIVE CONTRACT · '..t.amount..' '..item(t.item),16,HUD.AQUA)
  text(r.x+14,r.y+40,r.w-230,name(t.source)..' to '..name(t.target),13)
  local pickup=t.phase=='pickup'
  local detail=pickup and 'Collect the reserved cargo at the pickup station.' or 'Deliver the cargo aboard your current ship to the destination.'
  if not pickup and (game.player.cargo[t.item] or 0)<t.amount then detail='Cargo missing: replace it before delivery or return.' end
  text(r.x+14,r.y+83,r.w-230,detail,13,HUD.DIM)
  text(r.x+14,r.y+111,r.w-230,HUD.credits(require('src.transport').payment(t))..' on delivery · '..('%.2f AU'):format(t.routeAU or 0),13)
  local destination=pickup and t.source or t.target
  Station.button(f.advance,pickup and 'Load cargo' or 'Deliver & collect',false,f.here==destination)
  Station.button(f.cancel,pickup and 'Cancel contract' or 'Return & cancel',false,f.here and (pickup or f.here==t.source))
 else
  Station.panel(f.x,f.y,f.w,48)
  text(f.x+14,f.y+14,f.w-28,'No active contract. Accept one freight job at a time.',14,HUD.DIM)
 end
 if not f.here then
  text(f.x+14,f.y+(t and 172 or 65),f.w-28,'Dock at any station to browse the global board and handle cargo.',14,HUD.DIM)
  return
 end
 text(f.x+14,f.listY-28,f.w-28,('GLOBAL FREIGHT BOARD · %d available · pickups here shown first'):format(f.count),14,HUD.DIM)
 for _,row in ipairs(f.rows) do
  local o,q=row.offer,row.quote;Station.panel(row.x,row.y,row.w,row.h)
  text(row.x+14,row.y+10,row.w-220,name(o.source)..' to '..name(o.target),14)
  local amount=q and q.amount or o.amount
  local payment=q and q.payment or require('src.transport').payment(o)
  local details=('%d%s %s · %s · %.2f AU'):format(amount,q and amount<o.amount and (' / '..o.amount) or '',item(o.item),HUD.credits(payment),o.routeAU or 0)
  text(row.x+14,row.y+53,row.w-225,details,13,HUD.DIM)
  Station.button(row.button,q and 'Accept freight' or 'Unavailable',false,q~=nil and not t)
  if not q then text(row.x+row.w-205,row.y+12,190,row.why,12,HUD.DIM) end
 end
 if f.count==0 then text(f.x+14,f.listY+12,f.w-28,'No unclaimed freight orders right now. NPCs use this same board.',14,HUD.DIM) end
end
function View.mousepressed(game,x,y,button)
 if button~=1 then return true end
 local f=View.layout(game);local ok,message
 if f.active and inside(f.advance,x,y) then ok,message=Board.advance(game)
 elseif f.active and inside(f.cancel,x,y) then ok,message=Board.cancel(game)
 else
  for _,row in ipairs(f.rows) do if inside(row.button,x,y) then ok,message=Board.accept(game,row.offer.id);break end end
 end
 if message then game:toast(message,2.5) end
 return true
end
function View.wheelmoved(game,y) View.scroll=View.scroll-y*104 end
return View
