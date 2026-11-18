--[[
	Notifications: messages to the player, PDA style. Each one shows on
	the left of the HUD in flight for a few seconds (icon, time, title, a
	line of info), and is kept in a history the News tab shows.

	    Notify.post(u, { icon = 'rounds_s', title = 'Pirate demand',
	                     text = 'Jettison 12 cargo or be fired upon',
	                     kind = 'robbery', key = 'robbery:npc/12' })

	  icon   an item id, drawn with the item icons (src/icons.lua); none
	         or unknown draws the kind's letter in a box
	  kind   what sort of message it is, for the history and the default icon
	  key    optional: a post with the same key updates the one already
	         showing (and its history entry) instead of stacking a new one
	  life   seconds on screen (default T.life)

	History is saved (u.notifications.history, newest last, capped); what's
	on screen is not (Notify.live).
]]
local Notify={live={}}

Notify.T={life=8,fade=.6,keep=120,maxLive=5}

-- Default icons per kind, when a post names none. Item ids.
Notify.ICONS={
 robbery='rounds_s',
 news='electronics',
 subscription='electronics',
 police='patch_kit',
}

function Notify.state(u)
 u.notifications=u.notifications or {history={},nextId=0}
 return u.notifications
end

function Notify.post(u,n)
 local s=Notify.state(u)
 n.clock=u.clock or 0
 n.icon=n.icon or Notify.ICONS[n.kind]
 -- an update to one already showing
 if n.key then
  for _,l in ipairs(Notify.live) do
   if l.n.key==n.key then
    for k,v in pairs(n) do l.n[k]=v end
    l.t=0;l.life=n.life or Notify.T.life
    return l.n
   end
  end
 end
 s.nextId=s.nextId+1;n.id=s.nextId
 s.history[#s.history+1]=n
 while #s.history>Notify.T.keep do table.remove(s.history,1) end
 table.insert(Notify.live,{n=n,t=0,life=n.life or Notify.T.life})
 while #Notify.live>Notify.T.maxLive do table.remove(Notify.live,1) end
 return n
end

-- Newest first.
function Notify.history(u)
 local h=Notify.state(u).history;local out={}
 for i=#h,1,-1 do out[#out+1]=h[i] end
 return out
end

function Notify.update(dt)
 for i=#Notify.live,1,-1 do
  local l=Notify.live[i];l.t=l.t+dt
  if l.t>=l.life then table.remove(Notify.live,i) end
 end
end
-- A new universe (load, new game): nothing left on screen.
function Notify.clear() Notify.live={} end

-- The universe clock as a time of day, HH:MM.
function Notify.stamp(clock)
 local m=math.floor((clock or 0)/60)
 return ('%02d:%02d'):format(math.floor(m/60)%24,m%60)
end

---------------------------------------------------------------- drawing

-- One notification's icon box, shared by the HUD and the News tab.
function Notify.drawIcon(n,x,y,size,alpha)
 local lg=love.graphics;local HUD=require('src.hud')
 lg.setColor(1,1,1,.06*alpha);lg.rectangle('fill',x,y,size,size,4,4)
 lg.setColor(HUD.DIM[1],HUD.DIM[2],HUD.DIM[3],.6*alpha);lg.rectangle('line',x,y,size,size,4,4)
 local ok=n.icon and require('src.data').items[n.icon] and require('src.icons').drawInRect(n.icon,x,y,size,size,nil,alpha,5)
 if not ok then
  lg.setFont(HUD.font(math.floor(size*.45)));lg.setColor(HUD.AQUA[1],HUD.AQUA[2],HUD.AQUA[3],alpha)
  lg.printf(((n.kind or '?'):sub(1,1)):upper(),x,y+size*.25,size,'center')
 end
end

-- The live stack, on the left of the screen above the status panel,
-- newest at the bottom.
function Notify.draw(game,bottom)
 if #Notify.live==0 then return end
 local lg=love.graphics;local HUD=require('src.hud')
 local w=380;local rowH=58;local x=16
 local y=bottom-#Notify.live*(rowH+6)
 for _,l in ipairs(Notify.live) do
  local n=l.n
  local a=math.min(1,l.t/.15,(l.life-l.t)/Notify.T.fade)
  lg.setColor(0,0,0,.45*a);lg.rectangle('fill',x,y,w,rowH,6,6)
  Notify.drawIcon(n,x+6,y+6,rowH-12,a)
  local tx=x+rowH+4
  lg.setFont(HUD.font(13))
  local stamp=Notify.stamp(n.clock)
  lg.setColor(HUD.INK[1],HUD.INK[2],HUD.INK[3],a);lg.print(stamp,tx,y+8)
  lg.setColor(HUD.DIM[1],HUD.DIM[2],HUD.DIM[3],a);lg.print(n.title or '',tx+HUD.font(13):getWidth(stamp)+8,y+8)
  lg.setFont(HUD.font(14));lg.setColor(HUD.INK[1],HUD.INK[2],HUD.INK[3],a)
  lg.printf(n.text or '',tx,y+28,w-(tx-x)-8,'left')
  y=y+rowH+6
 end
end

return Notify
