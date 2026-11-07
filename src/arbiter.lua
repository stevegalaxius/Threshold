--[[
	The simulation arbiter: decides how many of each kind of NPC the world
	should have, from what the world needs right now, instead of a fixed
	count per area. Population (src/population.lua) asks it for targets: it
	spawns arrivals while an area is under its target, and simply doesn't
	replace losses while it's over.

	Traders follow haul work. Every A.tick seconds it counts the station
	orders (src/economy.lua) nobody has taken, by the area the cargo starts
	in, and wants one more trader there for every A.ordersPerTrader of them
	(up to A.maxExtra over the area's authored base). The want rises at once
	and decays slowly, so a burst of orders doesn't spawn and strand a fleet.

	Plain data in u.arbiter; works the same offline.
]]
local L=require('src.locations')
local Tasks=require('src.tasks')
local A={tick=60,ordersPerTrader=3,maxExtra=12,decay=1/600,universe=nil}

function A.state(u) u.arbiter=u.arbiter or {extra={},next=0};return u.arbiter end

function A.update(u,clock)
 A.universe=u
 local s=A.state(u)
 if clock<s.next then return end
 local dt=s.at and clock-s.at or A.tick
 s.next=clock+A.tick;s.at=clock
 local open={}
 for _,o in pairs(Tasks.state(u).offers) do
  if o.order and o.state=='available' then
   local place=L.byId[o.source]
   if place then open[place.area]=(open[place.area] or 0)+1 end
  end
 end
 local areas={}
 for area in pairs(open) do areas[area]=true end
 for area in pairs(s.extra) do areas[area]=true end
 for area in pairs(areas) do
  local want=math.min(A.maxExtra,math.ceil((open[area] or 0)/A.ordersPerTrader))
  local have=s.extra[area] or 0
  -- rise at once, fall slowly
  local v=want>=have and want or math.max(want,have-dt*A.decay)
  s.extra[area]=v>0 and v or nil
 end
end

-- Extra traders this area should have over its base.
function A.extraTraders(area)
 local u=A.universe;if not u or not u.arbiter then return 0 end
 return math.floor(u.arbiter.extra[area] or 0)
end
return A
