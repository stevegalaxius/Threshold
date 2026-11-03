-- Station presentation only. Inventory grids and item interaction remain shared
-- with the in-space screen.
local HUD=require('src.hud')
local S={}
function S.workspace(width,height,count,equipment)
 local gap,margin=12,16
 local available=width-margin*2-gap*(count-1)
 local weights={}
 if count==3 then weights=equipment and {.24,.38,.38} or {.35,.30,.35}
 else for i=1,count do weights[i]=1/count end end
 local panels={};local x=margin
 for i=1,count do
  local w=i==count and width-margin-x or math.floor(available*weights[i])
  panels[i]={x=x,y=112,w=w,h=height-168};x=x+w+gap
 end
 return panels
end
function S.panel(x,y,w,h)
 local lg=love.graphics
 lg.setColor(.025,.045,.06,.97);lg.rectangle('fill',x,y,w,h)
 lg.setColor(HUD.AQUA[1],HUD.AQUA[2],HUD.AQUA[3],.42)
 lg.setLineWidth(1);lg.rectangle('line',x+.5,y+.5,w-1,h-1)
 lg.setColor(HUD.AQUA[1],HUD.AQUA[2],HUD.AQUA[3],.10)
 lg.line(x,y+42,x+w,y+42)
end
function S.button(r,label,selected,enabled)
 local lg=love.graphics
 lg.setColor(HUD.AQUA[1],HUD.AQUA[2],HUD.AQUA[3],selected and .18 or .05)
 lg.rectangle('fill',r.x,r.y,r.w,r.h)
 lg.setColor(selected and {.95,.75,.25} or {HUD.AQUA[1],HUD.AQUA[2],HUD.AQUA[3],.35})
 lg.rectangle('line',r.x+.5,r.y+.5,r.w-1,r.h-1)
 lg.setColor(enabled==false and HUD.DIM or HUD.INK);lg.printf(label,r.x,r.y+(r.h-14)/2,r.w,'center')
end
return S
