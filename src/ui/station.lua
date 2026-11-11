-- Station controls use the existing player inventory presentation.
local HUD=require('src.hud')
local S={}
-- Largest inventory cell, in px (grids shrink below this only to fit the screen).
S.CELL=45
-- One frame for every station tab (and the in-flight inventory), so the
-- header and tab row never move when the tab changes.
function S.frameW()
 return math.min(love.graphics.getWidth()-48,1400)
end
function S.frame()
 local w=S.frameW()
 return math.floor((love.graphics.getWidth()-w)/2),w
end
-- Two ledgers stack at the top: the header (where you are, credits, tabs)
-- and the status ledger under it. Both use ledgerText for their two lines.
S.HEADER_Y,S.HEADER_H=12,88
S.STATUS_Y,S.STATUS_H=108,52
S.BODY_Y=172
-- A ledger's two lines: a title, and a dimmer line under it.
function S.ledgerText(x,y,title,sub,warn)
 local lg=love.graphics
 lg.setFont(HUD.font(16));lg.setColor(warn and HUD.WARN or HUD.INK);lg.print(title or '',x+14,y+9)
 lg.setFont(HUD.font(12));lg.setColor(HUD.DIM);lg.print(sub or '',x+14,y+30)
end
-- The body every tab draws in: under the two ledgers, down to the screen edge.
function S.body()
 local x,w=S.frame()
 local y=S.BODY_Y
 return x,y,w,math.max(320,love.graphics.getHeight()-y-16)
end
-- The status ledger, under the header, the same on every tab.
function S.footer(title,details,warn)
 local x,w=S.frame()
 S.panel(x,S.STATUS_Y,w,S.STATUS_H)
 S.ledgerText(x,S.STATUS_Y,title,details,warn)
end
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
