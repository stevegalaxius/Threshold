--[[
	Ship scans with a Deep Scanner (computer 'scanner', data/modules.lua):
	every ship within the scanner's shipRange is scanned at once, each
	finishing after scanTime in range; leave range and that ship's scan is
	dropped. Hover a scanned ship and its hold reads out, including what's packed in the
	containers it carries (depth). Goods illegal in the space you're in
	(src/contraband.lua) are marked. Wrecks and containers still read at
	once, as before (src/hud.lua drawScanTip).
]]
local data=require('src.data')
local Pose=require("src.render_pose")
local S={since=setmetatable({},{__mode='k'})}   -- ship -> when its scan started

local function inRange(p,e,range)
 if e==p or e.kind~='ship' or e.dead or e.removed or e.dockState then return false end
 local ex,ey=e.body:getPosition();local px,py=p.body:getPosition()
 return (ex-px)^2+(ey-py)^2<range^2
end

-- Each step: start scans on ships coming into range, drop those leaving it.
function S.update(game)
 local p=game.player
 local sc=p and not p.dead and not p.dockState and game:computer(p,'scanner')
 if not sc then S.since=setmetatable({},{__mode='k'});return end
 local range=sc.shipRange or sc.radarRange
 for _,e in ipairs(game.entities) do
  if e.kind=='ship' and e~=p then
   if inRange(p,e,range) then S.since[e]=S.since[e] or game.time else S.since[e]=nil end
  end
 end
 for e in pairs(S.since) do if e.dead or e.removed then S.since[e]=nil end end
end
-- 0..1: how far a ship's scan has got (nil: not being scanned).
function S.progress(game,e)
 local p=game.player;local sc=p and game:computer(p,'scanner')
 local t=sc and S.since[e]
 if not t then return nil end
 local need=sc.scanTime or 0
 return need<=0 and 1 or math.min(1,(game.time-t)/need)
end

-- The scanned (or scanning) ship under the cursor, or nil.
local function shipUnder(game,mx,my)
 local wx,wy=game.camera:toWorld(mx,my)
 for e in pairs(S.since) do
  local ex,ey=Pose.position(e)
  local r=(e.hull and e.hull.radius or 30)+20
  if (ex-wx)^2+(ey-wy)^2<r*r then return e end
 end
end

-- Lines for the tooltip: { text, warn } ...; nil when nothing to show.
function S.lines(game,mx,my)
 local p=game.player
 local sc=p and not p.dead and game:computer(p,'scanner')
 if not sc then return end
 local e=shipUnder(game,mx,my)
 if not e then return end
 local name=require('src.comms').factionName(game,e)..' '..require('src.comms').nameOf(e)
 local done=S.progress(game,e) or 0
 if done<1 then return {{('SCANNING %s  %d%%'):format(name,math.floor(done*100))}} end
 local C=require('src.contraband')
 local owner=require('src.reputation').ofArea(game.fieldId)
 local open,packed=C.contents(e)
 local out={{'SCAN: '..name}}
 local rows={}
 for id,n in pairs(open) do if n>0 then rows[#rows+1]={id=id,n=n} end end
 if sc.depth then for id,n in pairs(packed) do if n>0 then rows[#rows+1]={id=id,n=n,packed=true} end end end
 table.sort(rows,function(a,b) if a.id~=b.id then return a.id<b.id end return not a.packed and b.packed end)
 if #rows==0 then out[#out+1]={'hold empty'} end
 for i,r in ipairs(rows) do
  if i>10 then out[#out+1]={('+%d more'):format(#rows-10)};break end
  local item=data.items[r.id]
  local bad=C.illegal(game.universe,owner,r.id)
  out[#out+1]={('%s  x%d%s%s'):format(item and item.name or r.id,r.n,r.packed and '  (in container)' or '',bad and '  ILLEGAL HERE' or ''),bad}
 end
 return out
end

return S
