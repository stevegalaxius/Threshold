-- The Jobs screen's rows (src/ui/jobs.lua): your active freight or
-- passenger contract, a request, a freight or passenger offer, and
-- what a click on one of them does. (It was once its own Contracts screen.)
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
-- Right-aligned text, for the reward in a row's title band.
local function right(x,y,w,s,size,color)
 lg.setFont(HUD.font(size or 14));lg.setColor(color or HUD.INK);lg.printf(s,x,y,w,'right')
end
local GOOD={.4,1,.55}
local function systemName(id)
 local sys=require('src.quests').system(id)
 local F=sys and require('src.fields')[sys]
 return F and F.name or sys or '?'
end
-- How far a run goes: in-system, or the AU and the system it ends in.
local function reach(o)
 local Q=require('src.quests')
 if Q.system(o.source)==Q.system(o.target) then return 'in-system' end
 return ('%.1f AU to the %s system'):format(o.routeAU or 0,systemName(o.target))
end
local function from(f,id) return id==f.here and 'from here' or 'from '..name(id) end
local function m3(v) return v>=10 and ('%d m3'):format(math.floor(v+.5)) or ('%.1f m3'):format(v) end
local function minutes(s) s=math.max(0,math.ceil(s));return s>=60 and ('%dm'):format(math.ceil(s/60)) or ('%ds'):format(s) end
local function inside(r,x,y) return x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h end
local function purpose(o) return o.purpose=='vip' and 'VIP' or o.purpose=='work' and 'commute' or 'visit' end
local function who(o) return o.notable and ('VIP: %s'):format(o.vipName or 'a notable') or ('Party of %d'):format(o.party) end
local function drawPassengerActive(game,f,t)
 local r=f.activeRect;Station.panel(r.x,r.y,r.w,r.h)
 local pickup=t.phase=='pickup'
 text(r.x+14,r.y+10,r.w-230,('YOUR CONTRACT · %s to %s'):format(who(t),name(t.target)),15,HUD.AQUA)
 right(r.x+14,r.y+10,r.w-28,HUD.credits(t.fare or 0),16,HUD.AQUA)
 text(r.x+14,r.y+48,r.w-230,('%s · %s · %s'):format(from(f,t.source),reach(t),purpose(t)),13)
 local detail=pickup and ('Next: board the party at %s (%d free climate seats).'):format(name(t.source),t.party) or ('Next: fly them to %s and drop them off.'):format(name(t.target))
 if not pickup and (game.player.cargo[t.item or 'passengers'] or 0)<t.party then detail='Passengers missing.' end
 if t.notable and not pickup then detail=detail..' Eject them in space to space them.' end
 if t.lapsed then detail='Overdue: the next station you dock at will take them off your ship.'
 elseif t.deadline then detail=detail..(' Due in %s.'):format(minutes(t.deadline-game.universe.clock)) end
 text(r.x+14,r.y+76,r.w-230,detail,14,HUD.INK)
 text(r.x+14,r.y+108,r.w-230,'The fare was locked when you accepted.',13,HUD.DIM)
 local destination=pickup and t.source or t.target
 Station.button(f.advance,pickup and 'Board party' or 'Drop off & collect',false,f.here==destination)
 Station.button(f.cancel,'Cancel contract',false,f.here~=nil)
end
function View.drawActive(game,f,t)
 if t.kind=='passenger' then return drawPassengerActive(game,f,t) end
 local r=f.activeRect;Station.panel(r.x,r.y,r.w,r.h)
 local pickup=t.phase=='pickup'
 local bill=require('src.transport').invoice(t)
 text(r.x+14,r.y+10,r.w-230,('YOUR CONTRACT · %d \195\151 %s to %s'):format(t.amount,item(t.item),name(t.target)),15,HUD.AQUA)
 right(r.x+14,r.y+10,r.w-28,HUD.credits(bill.total),16,HUD.AQUA)
 text(r.x+14,r.y+48,r.w-230,('%s · %s · %s'):format(from(f,t.source),reach(t),m3(bill.volume)),13)
 local detail=pickup and ('Next: load the cargo at %s.'):format(name(t.source)) or ('Next: deliver it to %s.'):format(name(t.target))
 local missing=Board.cargoMissing(game)
 local aboard=(game.player.cargo[t.item] or 0)>0
 local partial=missing and aboard
 if missing then
  detail=partial and 'Some cargo is missing. Recover or replace it, deliver what remains, or report the loss.'
   or 'Cargo missing. Recover or replace it, or report the loss.'
 end
 if t.recoveryStop then detail='Recovery stop · '..name(t.recoveryStop)..'. Dock there to unload.' end
 text(r.x+14,r.y+76,r.w-230,detail,14,HUD.INK)
 text(r.x+14,r.y+108,r.w-230,missing and 'Reporting loss ends the contract without payment and reduces standing.'
  or 'Paid on delivery. Cancelling after pickup means returning the cargo.',13,HUD.DIM)
 local destination=pickup and t.source or t.recoveryStop or t.target
 Station.button(f.advance,pickup and 'Load cargo' or t.recoveryStop and 'Unload freight' or partial and 'Deliver partial' or 'Deliver & collect',false,
  f.here==destination and (not missing or aboard))
 Station.button(f.cancel,missing and 'Report loss' or pickup and 'Cancel contract' or 'Return & cancel',false,
  f.here and (missing or pickup or f.here==(t.originalSource or t.source)))
 if f.returnFreight then
  Station.button(f.returnFreight,t.recoveryStop and 'Resume delivery' or 'Return to origin',false,t.recoveryStop~=nil or aboard)
  if not t.recoveryStop then Station.button(f.transferFreight,'Transfer freight',false,aboard) end
 end
end
function View.drawQuest(game,f,row)
 local u=game.universe;local clock=u.clock
 local q=row.quest;Station.panel(row.x,row.y,row.w,row.h)
 local left=q.amount-(q.delivered or 0)
 local rescue=q.kind=='rescue'
 local site=q.title~=nil
 local ore=q.kind=='ore_delivery'
 local crisis=q.kind=='drug_crisis' or q.kind=='lounge_supply'
 local title,reward,detail
 local aboard=game.player.cargo[q.item] or 0
 if ore then
  title=('Mine %d \195\151 %s for %s'):format(left,item(q.item),name(q.giver))
  reward=HUD.credits(q.unit*left)
  detail=('%s each · %d aboard'):format(HUD.credits(q.unit),aboard)
 elseif crisis then
  title=((q.kind=='lounge_supply' and 'Lounge supply' or 'Crisis supply')..': %d \195\151 %s for %s'):format(left,item(q.item),name(q.giver))
  reward=HUD.credits(q.unit*left)
  detail=('%s · %s each · %d aboard'):format(q.why or 'they need it now',HUD.credits(q.unit),aboard)
 elseif site then
  title=q.title;reward=HUD.credits(q.unit);detail=q.detail or ''
 elseif rescue then
  title=('Rescue: bring fuel to the %s in %s'):format(q.name or 'ship',q.area)
  reward=HUD.credits(q.unit*q.amount)
  detail=('needs about %d %s · %d aboard'):format(q.amount,item(q.item),aboard)
 else
  title=('Deliver %d \195\151 %s to %s'):format(left,item(q.item),name(q.giver))
  reward=HUD.credits(q.unit*left);detail=('%d aboard'):format(aboard)
 end
 if row.active then title='YOURS · '..title end
 text(row.x+14,row.y+10,row.w-230,title,15,row.active and HUD.AQUA or HUD.INK)
 right(row.x+14,row.y+10,row.w-28,reward,16,HUD.AQUA)
 local time=row.active and ('due in %s'):format(minutes(q.deadline-clock)) or ('open for %s'):format(minutes(q.expires-clock))
 local who=('posted by %s (%s)'):format(name(q.giver),require('src.reputation').tierName(require('src.quests').attitude(u,q.giver)))
 text(row.x+14,row.y+46,row.w-225,detail~='' and (detail..' · '..time) or time,13)
 text(row.x+14,row.y+64,row.w-225,who,12,HUD.DIM)
 if row.active and site then
  Station.button(row.button,'Use '..item(q.item)..' on site',false,false)
  Station.button(row.abandon,'Abandon',false,true)
 elseif row.active and rescue then
  Station.button(row.button,'Eject fuel beside it',false,false)
  Station.button(row.abandon,'Abandon',false,true)
 elseif row.active then
  Station.button(row.button,'Deliver',false,f.here==q.giver and aboard>0)
  Station.button(row.abandon,'Abandon',false,true)
 else
  Station.button(row.button,q.kind=='rescue' and 'Accept rescue' or 'Accept job',false,f.quests<T.questMaxActive)
 end
end
-- An offer's last line: why you can't take it, or what to know before you do.
local function footer(row,f,ok,note)
 if f.active then text(row.x+14,row.y+70,row.w-225,'Finish your current contract first: one at a time.',13,HUD.DIM)
 elseif not row.quote and row.why then text(row.x+14,row.y+70,row.w-225,row.why,13,HUD.WARN)
 elseif note then text(row.x+14,row.y+70,row.w-225,note[1],13,note[2] or HUD.DIM) end
end
local function drawPassenger(game,f,row)
 local clock=game.universe.clock
 local o,q=row.offer,row.quote;Station.panel(row.x,row.y,row.w,row.h)
 local P=require('src.passengers')
 text(row.x+14,row.y+10,row.w-230,('%s to %s'):format(who(o),name(o.target)),15,o.notable and HUD.AQUA or nil)
 right(row.x+14,row.y+10,row.w-28,q and HUD.credits(q.payment) or ('up to '..HUD.credits(P.maxFare(o))),16,HUD.AQUA)
 text(row.x+14,row.y+46,row.w-225,('%s · %s · %s · needs %d climate seats · open for %s'):format(from(f,o.source),reach(o),purpose(o),o.party,minutes((o.expires or clock)-clock)),13)
 local note=q and {('Your ship earns base %s +%d%% comfort +%d%% speed. The fare locks when you accept.'):format(HUD.credits(math.floor(P.baseFare(o)+.5)),math.floor(q.detail.comfortShare*100+.5),math.floor(q.detail.speedShare*100+.5))}
 footer(row,f,q,note)
 Station.button(row.button,q and 'Accept passengers' or 'Unavailable',false,q~=nil and not f.active)
end
function View.drawFreight(game,f,row)
 if row.offer.kind=='passenger' then return drawPassenger(game,f,row) end
 local clock=game.universe.clock
 local o,q=row.offer,row.quote;Station.panel(row.x,row.y,row.w,row.h)
 local amount=q and q.amount or o.amount
 local payment=q and q.payment or require('src.transport').payment(o)
 local volume=amount*data.items[o.item].volume
 text(row.x+14,row.y+10,row.w-230,('%d \195\151 %s to %s'):format(amount,item(o.item),name(o.target)),15)
 right(row.x+14,row.y+10,row.w-28,HUD.credits(payment),16,HUD.AQUA)
 local route=('%s · %s · %s'):format(from(f,o.source),reach(o),m3(volume))
 if o.relay then route='Transferred freight · '..route end
 text(row.x+14,row.y+46,row.w-225,route,13)
 local note
 if q and amount<o.amount then
  note={q.limit=='stock' and ('Only %d of the %d ordered are in stock; the rest stays on the board.'):format(amount,o.amount)
   or q.limit=='standing' and ('Your standing covers %d of the %d ordered; the rest stays on the board.'):format(amount,o.amount)
   or ('Your hold takes %d of the %d ordered; the rest stays on the board.'):format(amount,o.amount)}
 end
 footer(row,f,q,note)
 Station.button(row.button,q and 'Accept freight' or 'Unavailable',false,q~=nil and not f.active)
end
-- A click on the active contract or a quest/freight row; nil if it hit none.
function View.click(game,f,x,y)
 if f.returnFreight and inside(f.returnFreight,x,y) then
  return Board.chooseRecovery(game,f.active.recoveryStop and 'resume' or 'return')
 end
 if f.transferFreight and not f.active.recoveryStop and inside(f.transferFreight,x,y) then
  return Board.chooseRecovery(game,'transfer')
 end
 if f.active and f.advance and inside(f.advance,x,y) then
  if not Board.cargoMissing(game) or (game.player.cargo[f.active.item] or 0)>0 then return Board.advance(game) end
 end
 if f.active and f.cancel and inside(f.cancel,x,y) then
  if Board.cargoMissing(game) then return Board.reportLoss(game) end
  return Board.cancel(game)
 end
 local u=game.universe;local Q=require('src.quests')
 for _,row in ipairs(f.rows) do
  if row.abandon and inside(row.abandon,x,y) then return Q.abandon(u,row.quest.id,u.clock,game) end
  if row.button and inside(row.button,x,y) then
   if row.quest and row.active then if require('src.quests').deliveries[row.quest.kind] then return Q.deliver(game,row.quest.id,f.here) end;return nil
   elseif row.quest then return Q.accept(u,row.quest.id,u.clock,game)
   elseif row.offer then return Board.accept(game,row.offer.id) end
  end
 end
end
View.text,View.inside=text,inside
return View
