-- Offline docking room: how many ships of a hull a station can actually
-- take (its berths that are big enough, plus its interior hangar if the
-- hull fits the doorway), and whether one more can dock now. Offline
-- records used to dock wherever their job sent them, however many: a
-- station that can take one freighter was "docked" by five, and on waking
-- they had nowhere to go but the dock entrance, inside each other.
local L,T,data=require('src.locations'),require('src.tuning'),require('src.data')
local R={}
local cache={}

local function dimensions(hull)
 local x1,y1,x2,y2=0,0,0,0
 for i=1,#hull.shape,2 do
  x1,y1=math.min(x1,hull.shape[i]),math.min(y1,hull.shape[i+1])
  x2,y2=math.max(x2,hull.shape[i]),math.max(y2,hull.shape[i+1])
 end
 return x2-x1,y2-y1
end

-- Ships of `hullId` station `id` can hold at once.
function R.capacity(id,hullId)
 local key=id..'|'..tostring(hullId)
 if cache[key] then return cache[key] end
 local hull=data.hulls[hullId]
 local ok,def=pcall(L.stationDefinition,id)
 if not hull or not ok or not def then cache[key]=math.huge;return math.huge end
 local length,width=dimensions(hull)
 local n=0
 for _,b in ipairs(def.berths or {}) do
  local bl=b.maxLength or b.size*T.berthShipScale*2
  local bw=b.maxWidth or b.size*T.berthShipScale*1.1
  if length<=bl and width<=bw then n=n+1 end
 end
 local doorway=false
 for _,d in ipairs(def.docks or {def.dock}) do if d and width/2+10<=(d.hw or 0) then doorway=true end end
 if doorway then
  local Game=require('src.game')
  local w,h=Game.hangarFootprint(hullId,false)
  local hw,hh=(def.hangar and def.hangar.w) or T.hangarW,(def.hangar and def.hangar.h) or T.hangarH
  local fit=math.max(math.floor(hw/w)*math.floor(hh/h),math.floor(hw/h)*math.floor(hh/w))
  n=n+math.max(0,fit)
 end
 cache[key]=n
 return n
end

-- Records docked at station `id` now (other than `except`), by hull.
local function docked(u,id,except)
 local key=id;local byHull={};local total=0
 for _,o in pairs(u.npcs or {}) do
  if o~=except and o.state=='docked' then
   local at=o.node or (o.route and o.route[o.index])
   if at and L.byId[at] and at==key then
    local h=o.ship and o.ship.hull or '?'
    byHull[h]=(byHull[h] or 0)+1;total=total+1
   end
  end
 end
 return total,byHull
end

-- Can record r dock at station `id` now? Every docked ship takes a place;
-- r's hull must also have a place of its own size left.
function R.room(u,r,id)
 if not (u and r and r.ship and r.ship.hull) then return true end
 local total,byHull=docked(u,id,r)
 local mine=R.capacity(id,r.ship.hull)
 if mine==math.huge then return true end
 -- the station's places, counted for the smallest hull docked or ours
 local places=mine
 for h in pairs(byHull) do places=math.max(places,R.capacity(id,h)) end
 return total<places and (byHull[r.ship.hull] or 0)<mine
end
return R
