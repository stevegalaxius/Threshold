-- The News tab (docked and in flight): what the outlets you can read are
-- printing. Docked, that's what the station carries plus your
-- subscriptions; in flight, only your subscriptions. A station run by a
-- paper's owner has that paper's press desk, where you subscribe or
-- cancel. Nothing here is the truth (src/news.lua). Your standing with
-- each outlet is on the Reputation screen. The Messages section is the
-- history of your notifications (src/notify.lua).
local News=require('src.news')
local L=require('src.locations')
local HUD,Station=require('src.hud'),require('src.ui.station')
local lg=love.graphics
local View={scroll=0,buttons={},section='headlines'}
local Notify=require('src.notify')

View.OUTLET_COLOR={gazette={.85,.75,1},signal={1,.45,.4},ledger={.55,.85,1},courier={.95,.85,.45},beltway={1,.6,.25},blacksheet={.7,.7,.7}}

local function here(game)
 local p=game.player;local st=game.state=='docked' and p and p.dockState and p.dockState.station
 if not st then return nil end
 local key=require('src.stockpile').key(st)
 return L.byId[key] and key or nil
end
View.here=here
local function ago(u,t)
 local m=math.floor(math.max(0,(u.clock or 0)-t)/60)
 if m<1 then return 'just now' end
 if m<60 then return m..'m ago' end
 return math.floor(m/60)..'h '..(m%60)..'m ago'
end

function View.draw(game)
 local u=game.universe;local x,y,w,h=Station.body()
 local key=here(game)
 View.buttons={}
 -- the press desk, at a station its paper's owner runs
 local desk=News.desk(key)
 if desk then
  local d=News.outlets[desk];local dh=52
  Station.panel(x,y,w,dh)
  lg.setFont(HUD.font(14));lg.setColor(View.OUTLET_COLOR[desk] or HUD.INK);lg.print(d.name..' press desk',x+16,y+8)
  lg.setFont(HUD.font(12));lg.setColor(HUD.DIM)
  local b={x=x+w-230,y=y+11,w=214,h=30,outlet=desk}
  if News.subscribed(u,desk) then
   lg.print('You subscribe: you read it in flight. '..HUD.credits(News.T.subscribeFee)..' an hour from your credits.',x+16,y+28)
   b.cancel=true;View.buttons[#View.buttons+1]=b;Station.button(b,'Cancel subscription',false,true)
  else
   local ok,why=News.canSubscribe(u,desk,key)
   lg.print(ok and ('Subscribe to read it in flight, anywhere: '..HUD.credits(News.T.subscribeFee)..' an hour, until you cancel or can\'t pay.') or why,x+16,y+28)
   View.buttons[#View.buttons+1]=b;Station.button(b,'Subscribe',false,ok==true)
  end
  y=y+dh+8;h=h-dh-8
 end
 Station.panel(x,y,w,h)
 -- Headlines | Messages
 for i,sec in ipairs({{'headlines','Headlines'},{'messages','Messages'}}) do
  local b={x=x+w-14-(3-i)*128,y=y+10,w=120,h=28,section=sec[1]}
  View.buttons[#View.buttons+1]=b;Station.button(b,sec[2],View.section==sec[1],true)
 end
 if View.section=='messages' then return View.drawMessages(game,x,y,w,h) end
 local feed=News.feed(u,key)
 lg.setFont(HUD.font(16));lg.setColor(HUD.INK)
 lg.print('Headlines',x+16,y+12)
 local names={};for _,o in ipairs(News.reading(u,key)) do names[#names+1]=News.outlets[o].name end
 lg.setFont(HUD.font(12));lg.setColor(HUD.DIM)
 lg.printf('Reading: '..(#names>0 and table.concat(names,', ') or (key and 'nothing' or 'nothing: subscribe at a paper\'s press desk to read it in flight')),x+16,y+36,w-32,'left')
 local rowH=58;local top,bottom=y+64,y+h-8
 View.scroll=math.max(0,math.min(View.scroll,math.max(0,#feed*rowH-(bottom-top))))
 lg.setScissor(x,top,w,bottom-top)
 local ry=top-View.scroll
 for _,st in ipairs(feed) do
  if ry+rowH>=top and ry<=bottom then
   local d=News.outlets[st.outlet];local c=View.OUTLET_COLOR[st.outlet] or HUD.INK
   lg.setColor(1,1,1,.04);lg.rectangle('fill',x+10,ry,w-20,rowH-6,4,4)
   lg.setFont(HUD.font(12));lg.setColor(c);lg.print((d and d.short or st.outlet):upper(),x+18,ry+6)
   lg.setColor(HUD.DIM)
   local tags={ago(u,st.clock)}
   if st.secondhand then tags[#tags+1]='via '..(News.outlets[st.from] and News.outlets[st.from].short or 'wire') end
   if st.subject=='player' then tags[#tags+1]='about you' end
   if st.tip then tags[#tags+1]='private tip' end
   if st.notice then tags[#tags+1]='notice' end
   lg.print(table.concat(tags,'  \194\183  '),x+120,ry+6)
   lg.setFont(HUD.font(15));lg.setColor(st.subject=='player' and HUD.WARN or HUD.INK)
   lg.printf(st.headline or '',x+18,ry+24,w-40,'left')
  end
  ry=ry+rowH
 end
 lg.setScissor()
 if #feed==0 then
  lg.setFont(HUD.font(13));lg.setColor(HUD.DIM)
  lg.printf(#names>0 and 'Nothing in the papers right now.' or 'No news without a paper.',x+16,top+8,w-32,'left')
 end
end

-- Your notifications, newest first.
function View.drawMessages(game,x,y,w,h)
 local u=game.universe;local list=Notify.history(u)
 lg.setFont(HUD.font(16));lg.setColor(HUD.INK);lg.print('Messages',x+16,y+12)
 lg.setFont(HUD.font(12));lg.setColor(HUD.DIM);lg.print('Everything sent straight to you: demands, notices, stories that name you.',x+16,y+36)
 local rowH=62;local top,bottom=y+64,y+h-8
 View.scroll=math.max(0,math.min(View.scroll,math.max(0,#list*rowH-(bottom-top))))
 lg.setScissor(x,top,w,bottom-top)
 local ry=top-View.scroll
 for _,n in ipairs(list) do
  if ry+rowH>=top and ry<=bottom then
   lg.setColor(1,1,1,.04);lg.rectangle('fill',x+10,ry,w-20,rowH-6,4,4)
   Notify.drawIcon(n,x+16,ry+5,rowH-16,1)
   local tx=x+16+rowH-6
   lg.setFont(HUD.font(13));local stamp=Notify.stamp(n.clock)
   lg.setColor(HUD.INK);lg.print(stamp,tx,ry+7)
   lg.setColor(HUD.DIM);lg.print((n.title or '')..'   '..ago(u,n.clock),tx+HUD.font(13):getWidth(stamp)+8,ry+7)
   lg.setFont(HUD.font(15));lg.setColor(HUD.INK);lg.printf(n.text or '',tx,ry+27,w-(tx-x)-20,'left')
  end
  ry=ry+rowH
 end
 lg.setScissor()
 if #list==0 then lg.setFont(HUD.font(13));lg.setColor(HUD.DIM);lg.print('No messages yet.',x+16,top+8) end
end

function View.mousepressed(game,mx,my,button)
 if button~=1 then return true end
 for _,b in ipairs(View.buttons) do
  if mx>=b.x and mx<b.x+b.w and my>=b.y and my<b.y+b.h then
   if b.section then View.section=b.section;View.scroll=0;return true end
   local u=game.universe;local name=News.outlets[b.outlet].name
   if b.cancel then News.cancel(u,b.outlet);game:toast('CANCELLED '..name:upper(),1.6)
   else
    local ok,why=News.subscribe(u,b.outlet,here(game))
    game:toast(ok and ('SUBSCRIBED TO '..name:upper()) or why,1.6)
   end
   return true
  end
 end
 return true
end
function View.wheelmoved(game,y) View.scroll=View.scroll-y*58 end

return View
