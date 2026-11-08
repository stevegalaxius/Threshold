-- The Reputation tab of the in-flight inventory (Tab): your standing with
-- each faction, as a bar from -100 to 100 with its tier.
local HUD=require('src.hud')
local Rep=require('src.reputation')
local lg=love.graphics
local R={}

local TIER_COLOR={hostile={1,.35,.3},wary={1,.7,.3},neutral={.75,.78,.8},friendly={.45,1,.55},trusted={.4,.85,1}}

function R.draw(game,f)
 local rows=Rep.summary(game.universe)
 local h=70+#rows*44+40
 HUD.panel(f.x,f.y,f.w,h)
 lg.setFont(HUD.font(16));lg.setColor(HUD.INK);lg.print('Reputation',f.x+16,f.y+12)
 lg.setFont(HUD.font(12));lg.setColor(HUD.DIM)
 lg.print('What each faction thinks of you. Only what their people see counts, and it fades with time.',f.x+16,f.y+36)
 local y=f.y+66;local bx=f.x+230;local bw=f.w-230-140
 local minor=false
 for _,r in ipairs(rows) do
  if not r.major and not minor then
   minor=true;lg.setFont(HUD.font(12));lg.setColor(HUD.DIM);lg.print('Secondary',f.x+16,y);y=y+20
  end
  lg.setFont(HUD.font(14));lg.setColor(HUD.INK);lg.print(r.name,f.x+16,y+4)
  lg.setColor(1,1,1,.08);lg.rectangle('fill',bx,y+6,bw,12,3,3)
  local c=TIER_COLOR[Rep.tier(r.value).id];local mid=bx+bw/2;local w=bw/2*math.abs(r.value)/100
  lg.setColor(c[1],c[2],c[3],.85)
  if r.value>=0 then lg.rectangle('fill',mid,y+6,w,12) else lg.rectangle('fill',mid-w,y+6,w,12) end
  lg.setColor(1,1,1,.4);lg.rectangle('fill',mid-1,y+3,2,18)
  lg.setColor(c);lg.printf(('%s  %+d'):format(r.tier,math.floor(r.value+.5)),bx+bw+10,y+4,120,'left')
  y=y+44
 end
end

return R
