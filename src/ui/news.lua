-- The News tab (docked and in flight): what the outlets you can read are
-- printing. Docked, that's what the station carries plus your
-- subscriptions; in flight, only your subscriptions. A station run by a
-- paper's owner has that paper's press desk, where you subscribe or
-- cancel. Nothing here is the truth (src/news.lua). Your standing with
-- each outlet is on the Reputation screen. Headlines are what the outlets
-- push; the Ticker is each one's market feed, where the rest is buried.
-- The Messages section is the history of your notifications
-- (src/notify.lua).
local News=require('src.news')
local L=require('src.locations')
local HUD,Station=require('src.hud'),require('src.ui.station')
local lg=love.graphics
local View={scroll=0,hscroll=0,buttons={},section='news'}
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
 -- News | Messages
 for i,sec in ipairs({{'news','News'},{'messages','Messages'}}) do
  local b={x=x+w-14-(3-i)*128,y=y+10,w=120,h=28,section=sec[1]}
  View.buttons[#View.buttons+1]=b;Station.button(b,sec[2],View.section==sec[1],true)
 end
 if View.section=='messages' then return View.drawMessages(game,x,y,w,h) end
 local names={};for _,o in ipairs(News.reading(u,key)) do names[#names+1]=News.outlets[o].short end
 lg.setFont(HUD.font(12));lg.setColor(HUD.DIM)
 lg.print('Reading: '..(#names>0 and table.concat(names,', ') or (key and 'nothing' or 'nothing (subscribe at a press desk to read in flight)')),x+16,y+16)
 local top=y+48;local ch=h-56
 local lw=math.floor((w-36)*.44)
 View.drawHeadlines(game,x+12,top,lw,ch,key)
 View.drawTicker(game,x+24+lw,top,w-36-lw,ch,key)
 View.drawTip()
end

-- One line of text cut to fit, with an ellipsis.
local function fit(font,text,width)
 if font:getWidth(text)<=width then return text end
 local n=#text
 while n>0 and font:getWidth(text:sub(1,n)..'...')>width do n=n-1 end
 -- don't cut a UTF-8 character in half
 while n>0 and text:byte(n+1) and text:byte(n+1)>=128 and text:byte(n+1)<192 do n=n-1 end
 return text:sub(1,n)..'...'
end
local function hit(r,mx,my) return mx>=r.x and mx<r.x+r.w and my>=r.y and my<r.y+r.h end

-- Headlines: what the outlets push, one line each, newest first.
function View.drawHeadlines(game,x,y,w,h,key)
 local u=game.universe;local feed=News.feed(u,key)
 lg.setFont(HUD.font(15));lg.setColor(HUD.INK);lg.print('Headlines',x+4,y)
 local rowH=40;local top,bottom=y+26,y+h
 View.hscroll=math.max(0,math.min(View.hscroll or 0,math.max(0,#feed*rowH-(bottom-top))))
 View.headArea={x=x,y=top,w=w,h=bottom-top}
 local mx,my=love.mouse.getPosition()
 lg.setScissor(x,top,w,bottom-top)
 local ry=top-View.hscroll
 for _,st in ipairs(feed) do
  if ry+rowH>=top and ry<=bottom then
   local d=News.outlets[st.outlet];local c=View.OUTLET_COLOR[st.outlet] or HUD.INK
   lg.setColor(1,1,1,.04);lg.rectangle('fill',x,ry,w,rowH-4,4,4)
   lg.setFont(HUD.font(11));lg.setColor(c)
   local tag=(d and d.short or st.outlet):upper()
   lg.print(tag,x+8,ry+3)
   local tags={ago(u,st.clock)}
   if st.secondhand then tags[#tags+1]='via '..(News.outlets[st.from] and News.outlets[st.from].short or 'wire') end
   if st.subject=='player' then tags[#tags+1]='about you' end
   if st.tip then tags[#tags+1]='private tip' end
   if st.notice then tags[#tags+1]='notice' end
   lg.setColor(HUD.DIM);lg.print(table.concat(tags,'  \194\183  '),x+16+HUD.font(11):getWidth(tag),ry+3)
   local f=HUD.font(14);lg.setFont(f)
   lg.setColor(st.subject=='player' and HUD.WARN or HUD.INK)
   local text=News.headline(st)
   lg.print(fit(f,text,w-16),x+8,ry+18)
   if f:getWidth(text)>w-16 and hit({x=x,y=ry,w=w,h=rowH-4},mx,my) and my>=top and my<bottom then
    View.tip={text,(d and d.name or st.outlet)..', '..ago(u,st.clock)}
   end
  end
  ry=ry+rowH
 end
 lg.setScissor()
 if #feed==0 then
  lg.setFont(HUD.font(13));lg.setColor(HUD.DIM)
  lg.printf(#News.reading(u,key)==0 and 'No news without a paper.' or 'Nothing in the papers right now.',x+4,top+8,w-8,'left')
 end
end

-- The ticker, merged across the outlets you read: one row per good and
-- station, every outlet's claim on it side by side (where they disagree
-- is the interesting part), goods in your hold first, then the biggest
-- moves. Wire lines (another outlet's figures, passed on late) dimmed.
local WARM,COOL={1,.62,.35},{.5,.75,1}
function View.tickerRows(game,key)
 local u=game.universe;local rows,by={},{}
 for _,o in ipairs(News.reading(u,key)) do
  for _,line in ipairs(News.tickerLines(u,o)) do
   local k=line.key..'|'..line.item
   local r=by[k]
   if not r then r={key=line.key,item=line.item,claims={},clock=0,dev=0};by[k]=r;rows[#rows+1]=r end
   r.claims[#r.claims+1]={o=o,line=line}
   r.clock=math.max(r.clock,line.clock or 0)
   if math.abs(line.reported-1)>math.abs(r.dev) then r.dev=line.reported-1 end
  end
 end
 local p=game.player;local cargo=p and p.cargo or {}
 for _,r in ipairs(rows) do
  r.held=(cargo[r.item] or 0)
  -- first-hand claims before wire ones
  table.sort(r.claims,function(a,b) if (a.line.wire~=nil)~=(b.line.wire~=nil) then return a.line.wire==nil end return a.o<b.o end)
 end
 table.sort(rows,function(a,b)
  if (a.held>0)~=(b.held>0) then return a.held>0 end
  if math.abs(a.dev)~=math.abs(b.dev) then return math.abs(a.dev)>math.abs(b.dev) end
  return a.key..a.item<b.key..b.item end)
 return rows
end
function View.drawTicker(game,x,y,w,h,key)
 local u=game.universe;local data=require('src.data')
 lg.setFont(HUD.font(15));lg.setColor(HUD.INK);lg.print('Ticker',x+4,y)
 lg.setFont(HUD.font(11));lg.setColor(HUD.DIM);lg.printf('claimed prices, your cargo first',x,y+4,w-4,'right')
 local rows=View.tickerRows(game,key)
 local rowH=24;local top,bottom=y+26,y+h
 View.scroll=math.max(0,math.min(View.scroll,math.max(0,#rows*rowH-(bottom-top))))
 View.tickArea={x=x,y=top,w=w,h=bottom-top}
 local mx,my=love.mouse.getPosition()
 lg.setScissor(x,top,w,bottom-top)
 local ry=top-View.scroll
 local f=HUD.font(13);local fs=HUD.font(11)
 local goodW=math.floor(w*.24);local placeW=math.floor(w*.26)
 for i,r in ipairs(rows) do
  if ry+rowH>=top and ry<=bottom then
   local hover=hit({x=x,y=ry,w=w,h=rowH},mx,my) and my>=top and my<bottom
   if r.held>0 then lg.setColor(1,1,1,.07) elseif i%2==0 then lg.setColor(1,1,1,.025) else lg.setColor(0,0,0,0) end
   lg.rectangle('fill',x,ry,w,rowH-2,3,3)
   if hover then lg.setColor(1,1,1,.06);lg.rectangle('fill',x,ry,w,rowH-2,3,3) end
   local up=r.dev>=0;local col=up and WARM or COOL
   lg.setColor(col)
   local ax,ay=x+12,ry+11
   if up then lg.polygon('fill',ax-5,ay+4,ax+5,ay+4,ax,ay-5) else lg.polygon('fill',ax-5,ay-4,ax+5,ay-4,ax,ay+5) end
   lg.setFont(f)
   local d=data.items[r.item];local name=d and d.name or r.item
   lg.setColor(r.held>0 and HUD.WARN or HUD.INK)
   lg.print(fit(f,name,goodW-8),x+24,ry+4)
   lg.setColor(HUD.DIM)
   local place=L.byId[r.key] and L.byId[r.key].name or r.key
   lg.print(fit(f,place,placeW-8),x+24+goodW,ry+4)
   -- each outlet's claim: TAG price
   local cx=x+24+goodW+placeW;local list=d and d.price or 0
   for _,c in ipairs(r.claims) do
    local od=News.outlets[c.o];local oc=View.OUTLET_COLOR[c.o] or HUD.INK
    local a=c.line.wire and .5 or 1
    local tag=(od and od.short or c.o):upper():sub(1,4)
    lg.setFont(fs);lg.setColor(oc[1],oc[2],oc[3],a);lg.print(tag,cx,ry+6)
    cx=cx+fs:getWidth(tag)+4
    local price=list>0 and tostring(math.floor(list*c.line.reported+.5)) or ('%+d%%'):format(math.floor((c.line.reported-1)*100+.5))
    lg.setFont(f);local cc=c.line.reported>=1 and WARM or COOL;lg.setColor(cc[1],cc[2],cc[3],a);lg.print(price,cx,ry+4)
    cx=cx+f:getWidth(price)+12
    if cx>x+w-60 then break end
   end
   lg.setFont(fs);lg.setColor(HUD.DIM);lg.printf(ago(u,r.clock),x,ry+6,w-6,'right')
   if hover then
    local t={name..' at '..place,list>0 and ('List price '..list..' cr') or nil}
    if r.held>0 then t[#t+1]='In your hold: '..r.held end
    for _,c in ipairs(r.claims) do
     local od=News.outlets[c.o]
     t[#t+1]=('%s: %s%s, %s'):format(od and od.name or c.o,
      list>0 and (math.floor(list*c.line.reported+.5)..' cr ') or '',
      ('(%+d%%)'):format(math.floor((c.line.reported-1)*100+.5)),
      c.line.wire and ('via '..(News.outlets[c.line.wire] and News.outlets[c.line.wire].name or c.line.wire)..', '..ago(u,c.line.clock)) or ago(u,c.line.clock))
    end
    local out={} for _,v in ipairs(t) do if v then out[#out+1]=v end end
    View.tip=out
   end
  end
  ry=ry+rowH
 end
 lg.setScissor()
 if #rows==0 then lg.setFont(HUD.font(13));lg.setColor(HUD.DIM);lg.printf('Nothing on the ticker.',x+4,top+8,w-8,'left') end
end

-- The hover tooltip, drawn last, beside the mouse.
function View.drawTip()
 local t=View.tip;View.tip=nil
 if not t or #t==0 then return end
 local f=HUD.font(12);local w=0
 for _,line in ipairs(t) do w=math.max(w,f:getWidth(line)) end
 w=math.min(w+16,520);local h=#t*16+10
 local mx,my=love.mouse.getPosition()
 local sw,sh=lg.getDimensions()
 local x=math.min(mx+16,sw-w-8);local y=math.min(my+12,sh-h-8)
 lg.setColor(0,0,0,.88);lg.rectangle('fill',x,y,w,h,4,4)
 lg.setColor(HUD.DIM);lg.rectangle('line',x,y,w,h,4,4)
 lg.setFont(f)
 for i,line in ipairs(t) do lg.setColor(i==1 and HUD.INK or HUD.DIM);lg.print(fit(f,line,w-16),x+8,y+5+(i-1)*16) end
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
   if b.section then View.section=b.section;View.scroll=0;View.hscroll=0;return true end
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
function View.wheelmoved(game,y)
 local mx,my=love.mouse.getPosition()
 local a=View.headArea
 if View.section=='news' and a and mx>=a.x and mx<a.x+a.w and my>=a.y and my<a.y+a.h then View.hscroll=(View.hscroll or 0)-y*40
 else View.scroll=View.scroll-y*(View.section=='news' and 24 or 62) end
end

return View
