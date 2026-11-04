-- Station controls use the existing player inventory presentation.
local HUD=require('src.hud')
local S={}
-- Use the same frames and button treatment as the player inventory.
function S.panel(x,y,w,h)
 HUD.panel(x,y,w,h)
end
function S.button(r,label,selected,enabled)
 local lg=love.graphics
 lg.setColor(HUD.AQUA[1],HUD.AQUA[2],HUD.AQUA[3],selected and .35 or .15)
 lg.rectangle('fill',r.x,r.y,r.w,r.h,5,5)
 lg.setColor(enabled==false and HUD.DIM or HUD.INK)
 lg.printf(label,r.x,r.y+(r.h-14)/2,r.w,'center')
end
return S
