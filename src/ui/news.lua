-- The News tab (docked and in flight): what the outlets you can read are
-- printing, and what each outlet thinks of you. Nothing here is the truth
-- (src/news.lua).
local News=require('src.news')
local L=require('src.locations')
local HUD,Station=require('src.hud'),require('src.ui.station')
local lg=love.graphics
local View={scroll=0,buttons={}}

local MOOD_COLOR={hostile={1,.45,.35},neutral={.75,.78,.8},friendly={.45,1,.55}}
local OUTLET_COLOR={gazette={.85,.75,1},signal={1,.45,.4},ledger={.55,.85,1},courier={.95,.85,.45},beltway={1,.6,.25},blacksheet={.7,.7,.7}}

local function here(game)
 local p=game.player;local st=game.state=='docked' and p and p.dockState and p.dockState.station
 if not st then return nil end
 local key=require('src.stockpile').key(st)
 return L.byId[key] and key or nil
end
local function ago(u,t)
 local m=math.floor(math.max(0,(u.clock or 0)-t)/60)
 if m<1 then return 'just now' end
 if m<60 then return m..'m ago' end
 return math.floor(m/60)..'h '..(m%60)..'m ago'
end
local function inside(r,x,y) return x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+r.h end

function View.draw(game)
 local u=game.universe;local x,y,w,h=Station.body()
 local key=here(game)
 local sideW=math.min(380,math.floor(w*.34));local fw=w-sideW-12
 View.buttons={}
 -- the feed
 local feed=News.feed(u,key)
 Station.panel(x,y,fw,h)
 lg.setFont(HUD.font(16));lg.setColor(HUD.INK)
 local names={};for _,o in ipairs(News.reading(u,key)) do names[#names+1]=News.outlets[o].name end
 lg.print('Headlines',x+16,y+12)
 lg.setFont(HUD.font(12));lg.setColor(HUD.DIM)
 local src=key and ('Carried here: ') or ('Received at your last dock: ')
 lg.printf(src..(#names>0 and table.concat(names,', ') or 'nothing yet'),x+16,y+36,fw-32,'left')
 local rowH=58;local top,bottom=y+64,y+h-8
 View.scroll=math.max(0,math.min(View.scroll,math.max(0,#feed*rowH-(bottom-top))))
 lg.setScissor(x,top,fw,bottom-top)
 local ry=top-View.scroll
 for _,st in ipairs(feed) do
  if ry+rowH>=top and ry<=bottom then
   local d=News.outlets[st.outlet];local c=OUTLET_COLOR[st.outlet] or HUD.INK
   lg.setColor(1,1,1,.04);lg.rectangle('fill',x+10,ry,fw-20,rowH-6,4,4)
   lg.setFont(HUD.font(12));lg.setColor(c);lg.print((d and d.short or st.outlet):upper(),x+18,ry+6)
   lg.setColor(HUD.DIM)
   local tags={ago(u,st.clock)}
   if st.secondhand then tags[#tags+1]='via '..(News.outlets[st.from] and News.outlets[st.from].short or 'wire') end
   if st.subject=='player' then tags[#tags+1]='about you' end
   if st.tip then tags[#tags+1]='private tip' end
   lg.print(table.concat(tags,'  \194\183  '),x+110,ry+6)
   lg.setFont(HUD.font(15));lg.setColor(st.subject=='player' and HUD.WARN or HUD.INK)
   lg.printf(st.headline or '',x+18,ry+24,fw-40,'left')
  end
  ry=ry+rowH
 end
 lg.setScissor()
 if #feed==0 then
  lg.setFont(HUD.font(13));lg.setColor(HUD.DIM)
  lg.printf(key and 'Nothing in the papers right now.' or 'Dock somewhere to catch up on the news.',x+16,top+8,fw-32,'left')
 end
 -- the outlets
 local sx=x+fw+12
 local oh=40+#News.order*48
 Station.panel(sx,y,sideW,oh)
 lg.setFont(HUD.font(16));lg.setColor(HUD.INK);lg.print('Outlets',sx+16,y+12)
 local oy=y+40
 for _,o in ipairs(News.order) do
  local d=News.outlets[o];local v=News.standing(u,o);local mood=News.mood(u,o)
  lg.setFont(HUD.font(13));lg.setColor(OUTLET_COLOR[o] or HUD.INK);lg.print(d.name,sx+16,oy+2)
  lg.setFont(HUD.font(12));lg.setColor(MOOD_COLOR[mood]);lg.print(('%s  %+d'):format(mood,math.floor(v+.5)),sx+16,oy+20)
  local sub=News.subscribed(u,o)
  if sub then
   lg.setColor(HUD.DIM);lg.printf('subscribed',sx+sideW-150,oy+10,134,'right')
  elseif key then
   local b={x=sx+sideW-150,y=oy+6,w=134,h=28,outlet=o}
   View.buttons[#View.buttons+1]=b
   Station.button(b,'Subscribe '..HUD.credits(News.T.subscribeCost),false,(u.credits or 0)>=News.T.subscribeCost)
  end
  oy=oy+48
 end
end

function View.mousepressed(game,mx,my,button)
 if button~=1 then return true end
 for _,b in ipairs(View.buttons) do
  if inside(b,mx,my) then
   local ok,why=News.subscribe(game.universe,b.outlet)
   game:toast(ok and ('SUBSCRIBED TO '..News.outlets[b.outlet].name:upper()) or why,1.6)
   return true
  end
 end
 return true
end
function View.wheelmoved(game,y) View.scroll=View.scroll-y*58 end

return View
