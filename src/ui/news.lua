-- The News tab (docked and in flight): what the outlets you can read are
-- printing. Docked, that's what the station carries; in flight, what's
-- carried in the system you're in. Nothing here
-- is the truth (src/news.lua). Your standing with each outlet is on the
-- Reputation screen.
local News=require('src.news')
local L=require('src.locations')
local HUD,Station=require('src.hud'),require('src.ui.station')
local lg=love.graphics
local View={scroll=0}

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
 local key,area=here(game),game.fieldId
 local feed=News.feed(u,key,area)
 Station.panel(x,y,w,h)
 lg.setFont(HUD.font(16));lg.setColor(HUD.INK)
 lg.print('Headlines',x+16,y+12)
 local names={};for _,o in ipairs(News.reading(u,key,area)) do names[#names+1]=News.outlets[o].name end
 lg.setFont(HUD.font(12));lg.setColor(HUD.DIM)
 lg.printf('Reading: '..(#names>0 and table.concat(names,', ') or 'nothing'),x+16,y+36,w-32,'left')
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
   lg.print(table.concat(tags,'  \194\183  '),x+120,ry+6)
   lg.setFont(HUD.font(15));lg.setColor(st.subject=='player' and HUD.WARN or HUD.INK)
   lg.printf(st.headline or '',x+18,ry+24,w-40,'left')
  end
  ry=ry+rowH
 end
 lg.setScissor()
 if #feed==0 then
  lg.setFont(HUD.font(13));lg.setColor(HUD.DIM)
  lg.printf('Nothing in the papers right now.',x+16,top+8,w-32,'left')
 end
end

function View.mousepressed(game,mx,my,button) return true end
function View.wheelmoved(game,y) View.scroll=View.scroll-y*58 end

return View
