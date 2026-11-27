--[[
	Ship scans with a Deep Scanner (computer 'scanner', data/modules.lua):
	hold the cursor on a ship within the scanner's shipRange for its
	scanTime and its hold reads out, including what's packed in the
	containers it carries (depth). Goods illegal in the space you're in
	(src/contraband.lua) are marked. Wrecks and containers still read at
	once, as before (src/hud.lua drawScanTip).
]]
local data=require('src.data')
local Pose=require("src.render_pose")
local S={target=nil,since=0}

-- The ship under the cursor in range, or nil.
local function shipUnder(game,p,sc,mx,my)
 local wx,wy=game.camera:toWorld(mx,my)
 local px,py=Pose.position(p)
 local range=sc.shipRange or sc.radarRange
 for _,e in ipairs(game.entities) do
  if e.kind=='ship' and e~=p and not e.dead and not e.removed and not e.dockState then
   local ex,ey=Pose.position(e)
   local r=(e.hull and e.hull.radius or 30)+20
   if (ex-wx)^2+(ey-wy)^2<r*r and (ex-px)^2+(ey-py)^2<range^2 then return e end
  end
 end
end

-- Lines for the tooltip: { text, warn } ...; nil when nothing to show.
function S.lines(game,mx,my)
 local p=game.player
 local sc=p and not p.dead and game:computer(p,'scanner')
 if not sc then S.target=nil;return end
 local e=shipUnder(game,p,sc,mx,my)
 if e~=S.target then S.target,S.since=e,game.time end
 if not e then return end
 local name=require('src.comms').factionName(game,e)..' '..require('src.comms').nameOf(e)
 local need=sc.scanTime or 0
 local done=game.time-S.since
 if done<need then
  return {{('SCANNING %s  %d%%'):format(name,math.floor(done/need*100))}}
 end
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
