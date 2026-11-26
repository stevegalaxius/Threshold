-- The Jobs tab: every piece of work the player can take, in four panes
-- picked with the buttons along the top (each shows how many it holds):
--   Your jobs      the freight or passenger contract and requests you
--                  hold, and bounties you're owed at other stations
--   Requests       work the stations of this system post for you alone
--                  (src/quests.lua: rescues, satellite and site work, ore), and a
--                  residential station's passenger demand
--   Freight        freight shared with NPCs that picks up in this system,
--                  wherever it goes (src/player_contracts.lua)
--   Bounties       this system's wreck bounty and your tab with it
--                  (src/wreck_bounty.lua), and wildcat sites it has put a
--                  price on (src/wildcats.lua)
-- Rows are drawn and clicked by src/ui/job_rows.lua. A row half off the
-- bottom is drawn clipped rather than dropped.
local Board=require('src.player_contracts')
local Bounty=require('src.wreck_bounty')
local Rows=require('src.ui.job_rows')
local L=require('src.locations')
local HUD,Station=require('src.hud'),require('src.ui.station')
local T=require('src.tuning')
local View={scroll=0,pane=nil}
local text,inside=Rows.text,Rows.inside
local function name(id) return L.byId[id] and L.byId[id].name or id end
local function areaName(id) local F=require('src.fields')[id];return F and F.name or id end

-- The four panes' entries, in order.
local PANES={{id='yours',label='Your jobs'},{id='station',label='Requests'},{id='freight',label='Freight'},{id='bounties',label='Bounties'}}
local function entries(game,f)
 local u=game.universe;local Q=require('src.quests')
 local here,t=f.here,f.active
 local out={yours={},station={},freight={},bounties={}}
 local count={yours=0,station=0,freight=0,bounties=0}
 local function head(pane,label) local e=out[pane];e[#e+1]={header=label,h=34} end
 local function note(pane,s) local e=out[pane];e[#e+1]={note=s,h=30} end
 local function add(pane,entry) local e=out[pane];e[#e+1]=entry;count[pane]=count[pane]+1 end
 local active,offers=Q.active(u),here and Q.offersInSystem(u,here) or {}
 local sysName=here and areaName(Q.system(here))
 f.quests,f.questOffers=#active,#offers
 -- Your jobs
 head('yours',('%d of %d requests held · %s'):format(#active,T.questMaxActive,t and 'one freight contract' or 'no freight contract'))
 local loss=Board.lossNotice(game)
 if loss then add('yours',{note=loss,h=30}) end
 if t then add('yours',{activeFreight=t,h=t.kind=='transport' and t.phase=='delivery' and 199 or 158}) end
 for _,q in ipairs(active) do add('yours',{quest=q,active=true,h=120}) end
 if not t and #active==0 then note('yours','Nothing held. Take a request or a freight contract from the other panes.') end
 local elsewhere={}
 for st,n in pairs(Bounty.state(u).owed) do if st~=f.payer and n>0 then elsewhere[#elsewhere+1]=st end end
 table.sort(elsewhere)
 if #elsewhere>0 then
  head('yours','BOUNTIES TO COLLECT ELSEWHERE')
  for _,st in ipairs(elsewhere) do note('yours',('%s system · %s for %d wrecks, %d wildcats · from %s'):format(areaName(Q.system(st)),HUD.credits(Bounty.owed(u,st)),Bounty.state(u).cleared[st] or 0,(Bounty.state(u).heads or {})[st] or 0,name(st))) end
 end
 if not here then
  for _,pane in ipairs({'station','freight','bounties'}) do note(pane,'Dock at a station to see what its system offers.') end
  return out,count
 end
 -- Requests
 head('station',('%d posted across the %s system'):format(#offers,sysName))
 for _,q in ipairs(offers) do add('station',{quest=q,h=100}) end
 if #offers==0 then note('station','No station in this system has a request posted right now.') end
 local P=require('src.passengers');local c=P.config(here)
 if c then
  head('station',('RESIDENTIAL · %s · population about %d · home to %d of %d ships'):format(name(here),c.population or 0,#P.residents(u,here),c.homes or 0))
  local dest={}
  for _,route in ipairs(c.routes or {}) do dest[#dest+1]=name(route.to)..(route.kind=='work' and ' (work)' or ' (visit)') end
  note('station','Passengers travel to '..table.concat(dest,', '))
  local open=P.offers(u,function(o)return o.home==here end)
  local avail=0;for _,o in ipairs(open) do if o.state=='available' then avail=avail+1 end end
  note('station',('%d passenger contracts out (at most %d) · %d open: find them under Freight'):format(#open,P.cap(here,u),avail))
 end
 -- Notables staying here (src/notables.lua)
 do
  local NB=require('src.notables');local here_=require('src.locations').canonical(here)
  local present={}
  for _,n in ipairs(require('data.notables').cast) do
   local p=NB.person(u,n.id)
   if p.status=='alive' and not p.trip and p.at==here_ then present[#present+1]=('%s, %s'):format(n.name,n.office) end
  end
  if #present>0 then head('station','NOTABLES HERE');for _,line in ipairs(present) do note('station',line) end end
 end
 -- Freight
 local sys=Q.system(here)
 local freight={}
 for _,o in ipairs(Board.list(game)) do if Q.system(o.source)==sys then freight[#freight+1]=o end end
 f.count=#freight
 head('freight',('%d picking up in the %s system · pickups here are held for you %ds before NPCs take them'):format(#freight,sysName,T.playerFirstLookSeconds))
 for _,o in ipairs(freight) do add('freight',{offer=o,h=104}) end
 if #freight==0 then note('freight','No unclaimed freight picks up in this system right now. NPCs use this same board.') end
 -- Bounties
 local payer=f.payer
 local areas=payer and Bounty.areas(payer) or {}
 if #areas>0 or payer and Bounty.owed(u,payer)>0 then
  head('bounties','WRECK BOUNTY')
  add('bounties',{bounty=areas,h=84})
 end
 local W=require('src.wildcats')
 local posted={}
 for _,inst in pairs(require('src.sites').list(u)) do
  if inst.bounty and not inst.done and Q.system(inst.bounty.station)==sys then posted[#posted+1]=inst end
 end
 table.sort(posted,function(a,b) return a.id<b.id end)
 if #posted>0 then
  head('bounties',('SITE BOUNTIES · %d in the %s system · paid per wildcat to whoever lands the last hit'):format(#posted,sysName))
  for _,inst in ipairs(posted) do
   local crew=W.crew(u,inst.id);local each=crew[1] and W.perHead(crew[1]) or T.bountyPerHead
   count.bounties=count.bounties+1
   note('bounties',('%s off %s · %d wildcat%s left · about %s each · on the mass driver · %d hunter%s inside'):format(require('src.sites').name(inst),areaName(inst.home),#crew,#crew==1 and '' or 's',HUD.credits(each),#W.hunters(u,inst.id),#W.hunters(u,inst.id)==1 and '' or 's'))
  end
 end
 if #out.bounties==0 then note('bounties','No bounties posted in this system.') end
 return out,count
end

function View.layout(game)
 local x,y,w,h=Station.body()
 local here=Board.station(game);local t=Board.active(game)
 local f={x=x,y=y,w=w,h=h,here=here,active=t,rows={}}
 f.payer=here and Bounty.payer(L.get(here).area)
 local lists,count=entries(game,f)
 -- the pane: as picked, or your jobs when you hold any, else the first with something in it
 if not View.pane then
  View.pane='freight'
  for _,p in ipairs(PANES) do if count[p.id]>0 then View.pane=p.id;break end end
 end
 f.panes={}
 for i,p in ipairs(PANES) do
  f.panes[i]={id=p.id,label=('%s (%d)'):format(p.label,count[p.id]),x=x+(i-1)*178,y=y,w=170,h=32}
 end
 local list=lists[View.pane]
 local total=0;for _,e in ipairs(list) do total=total+e.h end
 local top,bottom=y+44,y+h
 f.top,f.bottom=top,bottom
 View.scroll=math.max(0,math.min(View.scroll,math.max(0,total-(bottom-top))))
 local ry=top-View.scroll
 for _,e in ipairs(list) do
  if ry+e.h>top and ry<bottom then
   if e.activeFreight then
    f.activeRect={x=x,y=ry,w=w,h=e.h-12}
    f.advance={x=x+w-190,y=ry+46,w=174,h=34}
    f.cancel={x=x+w-190,y=ry+88,w=174,h=30}
    if e.h>158 then
     f.returnFreight={x=x+14,y=ry+146,w=174,h=28}
     f.transferFreight={x=x+198,y=ry+146,w=174,h=28}
    end
    f.rows[#f.rows+1]={activeFreight=true}
   elseif e.quest then
    local row={quest=e.quest,active=e.active,x=x,y=ry,w=w,h=e.active and 112 or 92,button={x=x+w-190,y=ry+44,w=174,h=30}}
    if e.active then row.abandon={x=x+w-190,y=ry+80,w=174,h=24} end
    f.rows[#f.rows+1]=row
   elseif e.offer then
    local q,why=Board.quote(game,e.offer)
    f.rows[#f.rows+1]={offer=e.offer,quote=q,why=why,x=x,y=ry,w=w,h=96,button={x=x+w-190,y=ry+48,w=174,h=32}}
   elseif e.bounty then
    f.rows[#f.rows+1]={bounty=e.bounty,x=x,y=ry,w=w,h=76,collect={x=x+w-190,y=ry+22,w=174,h=32}}
   else
    f.rows[#f.rows+1]={header=e.header,note=e.note,y=ry}
   end
  end
  ry=ry+e.h
 end
 return f
end

local function drawBounty(game,f,row)
 local u=game.universe;Station.panel(row.x,row.y,row.w,row.h)
 local names={};for _,a in ipairs(row.bounty) do names[#names+1]=areaName(a) end
 local owed=Bounty.owed(u,f.payer)
 if #names>0 then
  text(row.x+14,row.y+10,row.w-220,('%s pays for every ship wreck cleared in %s'):format(name(f.payer),table.concat(names,', ')),14)
  text(row.x+14,row.y+40,row.w-225,('from %s a wreck, more for bigger hulls · about %d wrecks out there now · drill or shoot them apart, anyone can claim it · collect at any station here'):format(HUD.credits(Bounty.rate(0)),Bounty.count(game,f.payer)),13,HUD.DIM)
 else
  text(row.x+14,row.y+10,row.w-220,'Bounty owed to you here',14)
 end
 Station.button(row.collect,owed>0 and ('Collect '..HUD.credits(owed)) or 'Nothing owed',false,owed>0)
end

function View.draw(game)
 local f=View.layout(game)
 for _,p in ipairs(f.panes) do Station.button(p,p.label,View.pane==p.id,true) end
 love.graphics.setScissor(f.x,f.top,f.w+2,f.bottom-f.top)
 for _,row in ipairs(f.rows) do
  if row.activeFreight then Rows.drawActive(game,f,f.active)
  elseif row.quest then Rows.drawQuest(game,f,row)
  elseif row.offer then Rows.drawFreight(game,f,row)
  elseif row.bounty then drawBounty(game,f,row)
  elseif row.header then text(f.x+14,row.y+10,f.w-28,row.header,14,HUD.DIM)
  elseif row.note then text(f.x+14,row.y+6,f.w-28,row.note,13,HUD.DIM) end
 end
 love.graphics.setScissor()
end
function View.mousepressed(game,x,y,button)
 if button~=1 then return true end
 local f=View.layout(game);local ok,message
 for _,p in ipairs(f.panes) do if inside(p,x,y) then View.pane=p.id;View.scroll=0;return true end end
 -- (the part of the list scrolled out of view can't be clicked)
 if y<f.top or y>=f.bottom then return true end
 for _,row in ipairs(f.rows) do
  if row.collect and inside(row.collect,x,y) then ok,message=Bounty.collect(game,f.payer) end
 end
 if not message then ok,message=Rows.click(game,f,x,y) end
 if message then game:toast(message,2.5) end
 return true
end
function View.wheelmoved(game,y) View.scroll=View.scroll-y*104 end
return View
