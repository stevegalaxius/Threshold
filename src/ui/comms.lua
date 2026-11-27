--[[
	The comms window: a small floating panel (the inventory popup's frame
	and buttons, src/ui/station.lua) for the player's open conversation
	(src/comms.lua).

	An NPC never opens it on you. A hail shows as a notice and a chip at the
	top of the screen with its countdown; C (or a click on the chip) opens
	the window, and C or the x closes it again while the timer runs. The
	game keeps running and the flight keys keep working while it's up: only
	clicks on the window itself are its own.
]]
local HUD=require('src.hud')
local Station=require('src.ui.station')
local Comms=require('src.comms')
local UI={openId=nil,rects=nil}

UI.W,UI.PAD,UI.BUTTON_H=400,14,30

local function current() return Comms.playerChannel() end
function UI.isOpen(game)
 local ch=current()
 return ch~=nil and UI.openId==ch.id and game.state~='docked'
end
function UI.toggle(game)
 local ch=current()
 if not ch then return false end
 UI.openId=UI.openId~=ch.id and ch.id or nil
 return true
end

local function wrap(font,text,w)
 local _,lines=font:getWrap(text,w)
 return lines
end

-- The window's layout: frame, close box, text lines, option buttons.
local function layout(game,ch)
 local lg=love.graphics
 local W,H=lg.getWidth(),lg.getHeight()
 local w=math.min(UI.W,W-32)
 local x=W-w-24
 local inner=w-UI.PAD*2
 local body=HUD.font(13)
 local lines={}
 local node=Comms.node(ch)
 local shown=0
 for i=#ch.log,1,-1 do                 -- the latest few exchanges
  local entry=ch.log[i]
  local text=entry.who=='listener' and ('> '..entry.text) or entry.text
  local wrapped=wrap(body,text,inner)
  for j=#wrapped,1,-1 do table.insert(lines,1,{text=wrapped[j],you=entry.who=='listener',latest=i==#ch.log}) end
  shown=shown+1
  if shown>=3 then break end
 end
 local options=Comms.options(ch)
 local h=UI.PAD+40+#lines*17+10+#options*(UI.BUTTON_H+6)+UI.PAD
 local y=math.max(300,math.floor(H*.42))   -- under the help panel
 if y+h>H-16 then y=math.max(16,H-16-h) end
 local L={x=x,y=y,w=w,h=h,lines=lines,options={},close={x=x+w-30,y=y+8,w=22,h=22}}
 local by=y+UI.PAD+40+#lines*17+10
 for i,o in ipairs(options) do
  L.options[i]={x=x+UI.PAD,y=by,w=inner,h=UI.BUTTON_H,label=o.label,enabled=o.enabled,index=i}
  by=by+UI.BUTTON_H+6
 end
 return L
end

local function inside(r,x,y) return r and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h end

-- The chip shown while a hail waits and the window is closed.
local function chipRect(game)
 local W=love.graphics.getWidth()
 local w=360
 return {x=math.floor((W-w)/2),y=110,w=w,h=34}
end

function UI.blocksMouse(game)
 local ch=current()
 if not ch or game.state=='docked' then return false end
 local mx,my=love.mouse.getPosition()
 if UI.isOpen(game) then return inside(layout(game,ch),mx,my) end
 return inside(chipRect(game),mx,my)
end
-- The cursor shows while the window is up, so the buttons can be clicked.
function UI.wantsCursor(game) return UI.isOpen(game) end

function UI.keypressed(game,key)
 if key=='c' and game.state~='docked' then return UI.toggle(game) end
 if key=='escape' and UI.isOpen(game) then UI.openId=nil;return true end
 return false
end

function UI.mousepressed(game,mx,my,button)
 local ch=current()
 if not ch or game.state=='docked' or button~=1 then return false end
 if not UI.isOpen(game) then
  if inside(chipRect(game),mx,my) then UI.openId=ch.id;return true end
  return false
 end
 local L=layout(game,ch)
 if inside(L.close,mx,my) then UI.openId=nil;return true end
 for _,r in ipairs(L.options) do
  if inside(r,mx,my) then
   if r.enabled then Comms.choose(ch,r.index) end
   return true
  end
 end
 return inside(L,mx,my)
end

local function timer(ch)
 local left=Comms.remaining(ch)
 return left and ('%ds'):format(math.ceil(left)) or ''
end

local function drawChip(game,ch)
 local lg=love.graphics
 local r=chipRect(game)
 HUD.panel(r.x,r.y,r.w,r.h)
 local pulse=.6+.4*math.abs(math.sin(game.time*3))
 lg.setFont(HUD.font(13))
 lg.setColor(HUD.AQUA[1],HUD.AQUA[2],HUD.AQUA[3],pulse)
 lg.print('HAIL',r.x+12,r.y+9)
 lg.setColor(HUD.INK)
 local who=Comms.factionName(game,ch.speaker)..' '..Comms.nameOf(ch.speaker)
 lg.printf(who..'   [C] answer',r.x+56,r.y+9,r.w-110,'left')
 lg.setColor(HUD.WARN)
 lg.printf(timer(ch),r.x,r.y+9,r.w-12,'right')
end

function UI.draw(game)
 local ch=current()
 if not ch or game.state=='docked' then return end
 if not UI.isOpen(game) then return drawChip(game,ch) end
 local lg=love.graphics
 local L=layout(game,ch)
 Station.panel(L.x,L.y,L.w,L.h)
 local other=ch.speaker.isPlayer and ch.listener or ch.speaker
 Station.ledgerText(L.x,L.y,Comms.factionName(game,other)..' \194\183 '..Comms.nameOf(other),'Comms channel open')
 lg.setFont(HUD.font(16));lg.setColor(HUD.WARN)
 lg.printf(timer(ch),L.x,L.y+9,L.w-44,'right')
 -- a countdown bar under the header
 local left=Comms.remaining(ch)
 if left and ch.enteredAt and ch.deadline then
  local span=math.max(.001,ch.deadline-ch.enteredAt)
  lg.setColor(HUD.AQUA[1],HUD.AQUA[2],HUD.AQUA[3],.5)
  lg.rectangle('fill',L.x+UI.PAD,L.y+48,(L.w-UI.PAD*2)*left/span,2)
 end
 Station.button(L.close,'x')
 lg.setFont(HUD.font(13))
 local y=L.y+UI.PAD+40
 for _,line in ipairs(L.lines) do
  lg.setColor(line.you and HUD.DIM or (line.latest and HUD.INK or HUD.DIM))
  lg.print(line.text,L.x+UI.PAD,y)
  y=y+17
 end
 lg.setFont(HUD.font(13))
 local mx,my=love.mouse.getPosition()
 for _,r in ipairs(L.options) do Station.button(r,r.label,inside(r,mx,my) and r.enabled,r.enabled) end
end

return UI
