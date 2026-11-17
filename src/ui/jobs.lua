-- The Jobs tab: every piece of work the player can take, in one list.
--   Your jobs      the freight contract and station jobs you hold
--   System jobs    what every station in this system offers (src/quests.lua:
--                  deliveries, rescues, satellite work, ore), this one first
--   Wreck bounty   what this system pays for clearing wrecks, and your tab
--                  with it, collected at any station here (src/wreck_bounty.lua)
--   Freight board  freight shared with NPCs that picks up in this system,
--                  wherever it goes
--                  (src/player_contracts.lua)
-- Rows are drawn and clicked with the Contracts screen's pieces
-- (src/ui/contracts.lua), which stays as a debug view of the same records.
local Board=require('src.player_contracts')
local Bounty=require('src.wreck_bounty')
local Contracts=require('src.ui.contracts')
local L=require('src.locations')
local HUD,Station=require('src.hud'),require('src.ui.station')
local T=require('src.tuning')
local View={scroll=0}
local text,inside=Contracts.text,Contracts.inside
local function name(id) return L.byId[id] and L.byId[id].name or id end
local function areaName(id) local F=require('src.fields')[id];return F and F.name or id end

function View.layout(game)
 local x,y,w,h=Station.body();local u=game.universe;local Q=require('src.quests')
 local here=Board.station(game);local t=Board.active(game)
 local f={x=x,y=y,w=w,h=h,here=here,active=t,rows={}}
 local active,offers=Q.active(u),here and Q.offersInSystem(u,here) or {}
 local sysName=here and areaName(Q.system(here))
 local payer=here and Bounty.payer(L.get(here).area)
 f.payer=payer
 local freight={}
 if here then
  local sys=Q.system(here)
  for _,o in ipairs(Board.list(game)) do if Q.system(o.source)==sys then freight[#freight+1]=o end end
 end
 f.quests,f.questOffers,f.count=#active,#offers,#freight
 local entries={}
 local function head(label) entries[#entries+1]={header=label,h=34} end
 local function note(s) entries[#entries+1]={note=s,h=30} end
 head(('YOUR JOBS · %d of %d held%s'):format(#active,T.questMaxActive,t and ' · 1 freight contract' or ''))
 if t then entries[#entries+1]={activeFreight=t,h=158} end
 for _,q in ipairs(active) do entries[#entries+1]={quest=q,active=true,h=84} end
 if not t and #active==0 then note('Nothing held. Take a job below.') end
 if here then
  head(('SYSTEM JOBS · %d offered in the %s system'):format(#offers,sysName))
  for _,q in ipairs(offers) do entries[#entries+1]={quest=q,h=84} end
  if #offers==0 then note('No station in this system has jobs posted right now.') end
  local areas=payer and Bounty.areas(payer) or {}
  if #areas>0 or payer and Bounty.owed(u,payer)>0 then
   head('WRECK BOUNTY')
   entries[#entries+1]={bounty=areas,h=84}
  end
  head(('FREIGHT BOARD · %d picking up in the %s system · pickups at this station are held for you %ds before NPCs'):format(#freight,sysName,T.playerFirstLookSeconds))
  for _,o in ipairs(freight) do entries[#entries+1]={offer=o,h=104} end
  if #freight==0 then note('No unclaimed freight picks up in this system right now. NPCs use this same board.') end
 else
  note('Dock at a station to see its jobs, wreck bounty and the freight board.')
 end
 -- Bounties you're owed elsewhere, so you know where to collect.
 local elsewhere={}
 for st,n in pairs(Bounty.state(u).owed) do if st~=f.payer and n>0 then elsewhere[#elsewhere+1]=st end end
 table.sort(elsewhere)
 if #elsewhere>0 then
  head('BOUNTIES TO COLLECT ELSEWHERE')
  for _,st in ipairs(elsewhere) do note(('%s system · %s for %d wrecks · from %s'):format(areaName(Q.system(st)),HUD.credits(Bounty.owed(u,st)),Bounty.state(u).cleared[st] or 0,name(st))) end
 end
 local total=0;for _,e in ipairs(entries) do total=total+e.h end
 local top,bottom=y+4,y+h
 View.scroll=math.max(0,math.min(View.scroll,math.max(0,total-(bottom-top))))
 local ry=top-View.scroll
 for _,e in ipairs(entries) do
  if ry>=top and ry+e.h<=bottom then
   if e.activeFreight then
    f.activeRect={x=x,y=ry,w=w,h=146}
    f.advance={x=x+w-190,y=ry+16,w=174,h=34}
    f.cancel={x=x+w-190,y=ry+62,w=174,h=30}
    f.rows[#f.rows+1]={activeFreight=true}
   elseif e.quest then
    local row={quest=e.quest,active=e.active,x=x,y=ry,w=w,h=76,button={x=x+w-190,y=ry+8,w=174,h=30}}
    if e.active then row.abandon={x=x+w-190,y=ry+42,w=174,h=26} end
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
 for _,row in ipairs(f.rows) do
  if row.activeFreight then Contracts.drawActive(game,f,f.active)
  elseif row.quest then Contracts.drawQuest(game,f,row)
  elseif row.offer then Contracts.drawFreight(game,f,row)
  elseif row.bounty then drawBounty(game,f,row)
  elseif row.header then text(f.x+14,row.y+10,f.w-28,row.header,14,HUD.DIM)
  elseif row.note then text(f.x+14,row.y+6,f.w-28,row.note,13,HUD.DIM) end
 end
end
function View.mousepressed(game,x,y,button)
 if button~=1 then return true end
 local f=View.layout(game);local ok,message
 for _,row in ipairs(f.rows) do
  if row.collect and inside(row.collect,x,y) then ok,message=Bounty.collect(game,f.payer) end
 end
 if not message then ok,message=Contracts.click(game,f,x,y) end
 if message then game:toast(message,2.5) end
 return true
end
function View.wheelmoved(game,y) View.scroll=View.scroll-y*104 end
return View
