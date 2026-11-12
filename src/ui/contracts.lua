local Board=require('src.player_contracts')
local L=require('src.locations')
local HUD,Station=require('src.hud'),require('src.ui.station')
local data=require('src.data')
local T=require('src.tuning')
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
  local u=game.universe;local Q=require('src.quests')
  local entries={}
  local active,offers=Q.active(u),Q.offersAt(u,here)
  out.quests=#active;out.questOffers=#offers
  for _,q in ipairs(active) do entries[#entries+1]={quest=q,active=true,h=84} end
  for _,q in ipairs(offers) do entries[#entries+1]={quest=q,h=84} end
  entries[#entries+1]={header=true,h=36}
  local list=Board.list(game);out.count=#list
  for _,o in ipairs(list) do entries[#entries+1]={offer=o,h=104} end
  local total=0;for _,e in ipairs(entries) do total=total+e.h end
  local bottom=y+h
  View.scroll=math.max(0,math.min(View.scroll,math.max(0,total-(bottom-out.listY))))
  local ry=out.listY-View.scroll
  for _,e in ipairs(entries) do
   if ry>=out.listY and ry+e.h<=bottom then
    if e.offer then
     local q,why=Board.quote(game,e.offer)
     out.rows[#out.rows+1]={offer=e.offer,quote=q,why=why,x=x,y=ry,w=w,h=96,button={x=x+w-190,y=ry+48,w=174,h=32}}
    elseif e.quest then
     local row={quest=e.quest,active=e.active,x=x,y=ry,w=w,h=76,button={x=x+w-190,y=ry+8,w=174,h=30}}
     if e.active then row.abandon={x=x+w-190,y=ry+42,w=174,h=26} end
     out.rows[#out.rows+1]=row
    else out.rows[#out.rows+1]={header=true,y=ry} end
   end
   ry=ry+e.h
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
  local bill=require('src.transport').invoice(t)
  text(r.x+14,r.y+111,r.w-230,('%s on delivery · %.2f m3 · %.2f AU · %s handling included'):format(HUD.credits(bill.total),bill.volume,t.routeAU or 0,HUD.credits(bill.handling)),13)
  local destination=pickup and t.source or t.target
  Station.button(f.advance,pickup and 'Load cargo' or 'Deliver & collect',false,f.here==destination)
  Station.button(f.cancel,pickup and 'Cancel contract' or 'Return & cancel',false,f.here and (pickup or f.here==t.source))
 else
  Station.panel(f.x,f.y,f.w,48)
  text(f.x+14,f.y+14,f.w-28,'No active freight contract. Accept one freight job at a time.',14,HUD.DIM)
 end
 if not f.here then
  text(f.x+14,f.y+(t and 172 or 65),f.w-28,'Dock at any station to browse the global board and handle cargo.',14,HUD.DIM)
  return
 end
 local u=game.universe;local clock=u.clock
 text(f.x+14,f.listY-28,f.w-28,('SHORTAGE DELIVERIES · %d held · %d offered here'):format(f.quests,f.questOffers),14,HUD.DIM)
 for _,row in ipairs(f.rows) do
  if row.header then
   text(f.x+14,row.y+10,f.w-28,('GLOBAL FREIGHT BOARD · %d available · pickups here are held for you %ds before NPCs'):format(f.count,T.playerFirstLookSeconds),14,HUD.DIM)
  elseif row.quest then
   local q=row.quest;Station.panel(row.x,row.y,row.w,row.h)
   local left=q.amount-(q.delivered or 0)
   local title=(row.active and 'DELIVER · ' or 'SHORTAGE · ')..left..' '..item(q.item)..' to '..name(q.giver)
   text(row.x+14,row.y+10,row.w-220,title,14,row.active and HUD.AQUA or HUD.INK)
   local time=row.active and ('due in %dm'):format(math.max(0,math.ceil((q.deadline-clock)/60))) or ('offered for %dm'):format(math.max(0,math.ceil((q.expires-clock)/60)))
   local aboard=game.player.cargo[q.item] or 0
   text(row.x+14,row.y+40,row.w-225,('%s per unit · %s total · %s · %d aboard'):format(HUD.credits(q.unit),HUD.credits(q.unit*left),time,aboard),13,HUD.DIM)
   if row.active then
    Station.button(row.button,'Deliver',false,f.here==q.giver and aboard>0)
    Station.button(row.abandon,'Abandon',false,true)
   else
    Station.button(row.button,'Accept delivery',false,f.quests<T.questMaxActive)
   end
  else
  local o,q=row.offer,row.quote;Station.panel(row.x,row.y,row.w,row.h)
  text(row.x+14,row.y+10,row.w-220,name(o.source)..' to '..name(o.target),14)
  local amount=q and q.amount or o.amount
  local payment=q and q.payment or require('src.transport').payment(o)
  local volume=amount*data.items[o.item].volume
  local details=('%d%s %s · %.2f m3 · %s · %.2f AU'):format(amount,q and amount<o.amount and (' / '..o.amount) or '',item(o.item),volume,HUD.credits(payment),o.routeAU or 0)
  local hold=o.source==f.here and (o.placed or 0)+T.playerFirstLookSeconds-clock
  if hold and hold>0 then details=details..(' · held for you %ds'):format(math.ceil(hold)) end
  text(row.x+14,row.y+53,row.w-225,details,13,HUD.DIM)
  Station.button(row.button,q and 'Accept freight' or 'Unavailable',false,q~=nil and not t)
  if not q then text(row.x+row.w-205,row.y+12,190,row.why,12,HUD.DIM) end
  end
 end
 if f.count==0 and f.quests+f.questOffers==0 then text(f.x+14,f.listY+12,f.w-28,'No unclaimed freight orders right now. NPCs use this same board.',14,HUD.DIM) end
end
function View.mousepressed(game,x,y,button)
 if button~=1 then return true end
 local f=View.layout(game);local ok,message
 if f.active and inside(f.advance,x,y) then ok,message=Board.advance(game)
 elseif f.active and inside(f.cancel,x,y) then ok,message=Board.cancel(game)
 else
  local u=game.universe;local Q=require('src.quests')
  for _,row in ipairs(f.rows) do
   if row.abandon and inside(row.abandon,x,y) then ok,message=Q.abandon(u,row.quest.id,u.clock);break end
   if row.button and inside(row.button,x,y) then
    if row.quest and row.active then ok,message=Q.deliver(game,row.quest.id,f.here)
    elseif row.quest then ok,message=Q.accept(u,row.quest.id,u.clock)
    else ok,message=Board.accept(game,row.offer.id) end
    break
   end
  end
 end
 if message then game:toast(message,2.5) end
 return true
end
function View.wheelmoved(game,y) View.scroll=View.scroll-y*104 end
return View
