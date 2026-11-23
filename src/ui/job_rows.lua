-- The Jobs screen's rows (src/ui/jobs.lua): your active freight or
-- passenger contract, a station job, a freight or passenger offer, and
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
local function inside(r,x,y) return x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h end
local function purpose(o) return o.purpose=='work' and 'commute' or 'visit' end
local function drawPassengerActive(game,f,t)
 local r=f.activeRect;Station.panel(r.x,r.y,r.w,r.h)
 text(r.x+14,r.y+12,r.w-220,('ACTIVE PASSENGER CONTRACT · party of %d (%s)'):format(t.party,purpose(t)),16,HUD.AQUA)
 text(r.x+14,r.y+40,r.w-230,name(t.source)..' to '..name(t.target),13)
 local pickup=t.phase=='pickup'
 local detail=pickup and 'Collect the party at the pickup station: they need '..t.party..' free climate seats.' or 'Fly the party to the destination aboard your current ship.'
 if not pickup and (game.player.cargo.passengers or 0)<t.party then detail='Passengers missing.' end
 text(r.x+14,r.y+83,r.w-230,detail,13,HUD.DIM)
 local d=t.fareDetail or {}
 text(r.x+14,r.y+111,r.w-230,('%s locked on acceptance · base %s · comfort +%d%% · speed +%d%% · %.2f AU'):format(HUD.credits(t.fare or 0),HUD.credits(d.base or 0),math.floor((d.comfortShare or 0)*100+.5),math.floor((d.speedShare or 0)*100+.5),t.routeAU or 0),13)
 local destination=pickup and t.source or t.target
 Station.button(f.advance,pickup and 'Board party' or 'Drop off & collect',false,f.here==destination)
 Station.button(f.cancel,'Cancel contract',false,f.here~=nil)
end
function View.drawActive(game,f,t)
 if t.kind=='passenger' then return drawPassengerActive(game,f,t) end
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
end
function View.drawQuest(game,f,row)
 local u=game.universe;local clock=u.clock
 local q=row.quest;Station.panel(row.x,row.y,row.w,row.h)
 local left=q.amount-(q.delivered or 0)
 local rescue=q.kind=='rescue'
 local site=q.title~=nil
 local ore=q.kind=='ore_delivery'
 local title=ore and ((row.active and 'MINE · ' or 'ORE · ')..left..' '..item(q.item)..' mined for '..name(q.giver)) or site and ((row.active and 'JOB · ' or '')..q.title) or rescue and ((row.active and 'RESCUE · ' or 'STRANDED SHIP · ')..'bring fuel to the '..(q.name or 'ship')..' in '..q.area)
  or (row.active and 'DELIVER · ' or 'SHORTAGE · ')..left..' '..item(q.item)..' to '..name(q.giver)
 text(row.x+14,row.y+10,row.w-220,title,14,row.active and HUD.AQUA or HUD.INK)
 local time=row.active and ('due in %dm'):format(math.max(0,math.ceil((q.deadline-clock)/60))) or ('offered for %dm'):format(math.max(0,math.ceil((q.expires-clock)/60)))
 local aboard=game.player.cargo[q.item] or 0
 local who=name(q.giver)..' · '..require('src.reputation').tierName(require('src.quests').attitude(u,q.giver))
 if site then
  text(row.x+14,row.y+40,row.w-225,('%s · %s · %s · %s'):format(HUD.credits(q.unit),q.detail or '',time,who),13,HUD.DIM)
 elseif rescue then
  text(row.x+14,row.y+40,row.w-225,('%s on rescue · needs about %d %s · %s · %d aboard · %s'):format(HUD.credits(q.unit*q.amount),q.amount,item(q.item),time,aboard,who),13,HUD.DIM)
 else
  text(row.x+14,row.y+40,row.w-225,('%s per unit · %s total · %s · %d aboard · %s'):format(HUD.credits(q.unit),HUD.credits(q.unit*left),time,aboard,who),13,HUD.DIM)
 end
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
  Station.button(row.button,site and 'Accept job' or q.kind=='rescue' and 'Accept rescue' or 'Accept delivery',false,f.quests<T.questMaxActive)
 end
end
local function drawPassenger(game,f,row)
 local clock=game.universe.clock
 local o,q=row.offer,row.quote;Station.panel(row.x,row.y,row.w,row.h)
 local P=require('src.passengers')
 text(row.x+14,row.y+10,row.w-220,('PASSENGERS · %s to %s · party of %d (%s)'):format(name(o.source),name(o.target),o.party,purpose(o)),14)
 local yours=q and ('%s for your ship (comfort +%d%%, speed +%d%%)'):format(HUD.credits(q.payment),math.floor(q.detail.comfortShare*100+.5),math.floor(q.detail.speedShare*100+.5)) or row.why
 text(row.x+14,row.y+34,row.w-225,('Needs %d climate seats · base %s, up to %s with comfort and speed · %.2f AU · withdrawn in %dm'):format(o.party,HUD.credits(math.floor(P.baseFare(o)+.5)),HUD.credits(P.maxFare(o)),o.routeAU or 0,math.max(0,math.ceil(((o.expires or clock)-clock)/60))),13,HUD.DIM)
 text(row.x+14,row.y+58,row.w-225,yours..' · the fare locks when you accept',13,q and HUD.INK or HUD.DIM)
 Station.button(row.button,q and 'Accept passengers' or 'Unavailable',false,q~=nil and not f.active)
end
function View.drawFreight(game,f,row)
 if row.offer.kind=='passenger' then return drawPassenger(game,f,row) end
 local clock=game.universe.clock
 local o,q=row.offer,row.quote;Station.panel(row.x,row.y,row.w,row.h)
 text(row.x+14,row.y+10,row.w-220,name(o.source)..' to '..name(o.target),14)
 local amount=q and q.amount or o.amount
 local payment=q and q.payment or require('src.transport').payment(o)
 local volume=amount*data.items[o.item].volume
 local details=('%d%s %s · %.2f m3 · %s · %.2f AU'):format(amount,q and amount<o.amount and (' / '..o.amount) or '',item(o.item),volume,HUD.credits(payment),o.routeAU or 0)
 local hold=o.source==f.here and (o.placed or 0)+T.playerFirstLookSeconds-clock
 if hold and hold>0 then details=details..(' · held for you %ds'):format(math.ceil(hold)) end
 text(row.x+14,row.y+53,row.w-225,details,13,HUD.DIM)
 Station.button(row.button,q and 'Accept freight' or 'Unavailable',false,q~=nil and not f.active)
 if not q and row.why then text(row.x+14,row.y+73,row.w-225,row.why,13,HUD.WARN)
 elseif q and f.active then text(row.x+14,row.y+73,row.w-225,'Finish your active contract first: one freight contract at a time.',13,HUD.DIM) end
end
-- A click on the active contract or a quest/freight row; nil if it hit none.
function View.click(game,f,x,y)
 if f.active and f.advance and inside(f.advance,x,y) then return Board.advance(game) end
 if f.active and f.cancel and inside(f.cancel,x,y) then return Board.cancel(game) end
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
