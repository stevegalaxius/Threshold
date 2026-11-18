-- The Reputation tab of the in-flight inventory (Tab): your standing with
-- each faction, as a bar from -100 to 100 with its tier, and with each
-- news outlet (src/news.lua).
local HUD=require('src.hud')
local Rep=require('src.reputation')
local News=require('src.news')
local lg=love.graphics
local R={}

local TIER_COLOR={hostile={1,.35,.3},wary={1,.7,.3},neutral={.75,.78,.8},friendly={.45,1,.55},trusted={.4,.85,1}}
local MOOD_COLOR={hostile={1,.35,.3},neutral={.75,.78,.8},friendly={.45,1,.55}}

local function bar(bx,y,bw,value,c)
 lg.setColor(1,1,1,.08);lg.rectangle('fill',bx,y+6,bw,12,3,3)
 local mid=bx+bw/2;local w=bw/2*math.min(100,math.abs(value))/100
 lg.setColor(c[1],c[2],c[3],.85)
 if value>=0 then lg.rectangle('fill',mid,y+6,w,12) else lg.rectangle('fill',mid-w,y+6,w,12) end
 lg.setColor(1,1,1,.4);lg.rectangle('fill',mid-1,y+3,2,18)
end

function R.draw(game,f)
 local u=game.universe
 local rows=Rep.summary(u)
 local h=70+#rows*44+40
 HUD.panel(f.x,f.y,f.w,h)
 lg.setFont(HUD.font(16));lg.setColor(HUD.INK);lg.print('Reputation',f.x+16,f.y+12)
 lg.setFont(HUD.font(12));lg.setColor(HUD.DIM)
 lg.print('What each faction thinks of you: what their people saw, plus what their papers told them. Both fade with time.',f.x+16,f.y+36)
 local y=f.y+66;local bx=f.x+230;local bw=f.w-230-200
 local minor=false
 for _,r in ipairs(rows) do
  if not r.major and not minor then
   minor=true;lg.setFont(HUD.font(12));lg.setColor(HUD.DIM);lg.print('Secondary',f.x+16,y);y=y+20
  end
  lg.setFont(HUD.font(14));lg.setColor(HUD.INK);lg.print(r.name,f.x+16,y+4)
  local c=TIER_COLOR[Rep.tier(r.value).id]
  bar(bx,y,bw,r.value,c)
  lg.setColor(c);lg.printf(('%s  %+d'):format(r.tier,math.floor(r.value+.5)),bx+bw+10,y+4,180,'left')
  if math.abs(r.reported or 0)>=.5 then
   lg.setFont(HUD.font(11));lg.setColor(HUD.DIM)
   lg.print(('%+d from the news'):format(math.floor(r.reported+.5)),bx+bw+10,y+22)
  end
  y=y+44
 end
 -- the outlets
 local oy=f.y+h+12
 local oh=70+#News.order*44
 HUD.panel(f.x,oy,f.w,oh)
 lg.setFont(HUD.font(16));lg.setColor(HUD.INK);lg.print('News outlets',f.x+16,oy+12)
 lg.setFont(HUD.font(12));lg.setColor(HUD.DIM)
 lg.print('How useful each paper finds you. Friends flatter you and pass you tips; enemies name you and smear you.',f.x+16,oy+36)
 y=oy+66
 local OC=require('src.ui.news').OUTLET_COLOR
 for _,o in ipairs(News.order) do
  local d=News.outlets[o];local v=News.standing(u,o);local mood=News.mood(u,o)
  lg.setFont(HUD.font(14));lg.setColor(OC[o] or HUD.INK);lg.print(d.name,f.x+16,y+4)
  local c=MOOD_COLOR[mood]
  bar(bx,y,bw,v,c)
  lg.setColor(c);lg.printf(('%s  %+d'):format(mood:sub(1,1):upper()..mood:sub(2),math.floor(v+.5)),bx+bw+10,y+4,80,'left')
  if News.subscribed(u,o) then lg.setFont(HUD.font(12));lg.setColor(HUD.DIM);lg.printf('subscribed',f.x+f.w-110,y+6,96,'right') end
  y=y+44
 end
end

function R.mousepressed(game,mx,my,button) return true end

return R
