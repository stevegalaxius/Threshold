--[[
	The simulation arbiter: decides how many of each kind of NPC the world
	should have, from what the world needs right now, instead of a fixed
	count per area. Population (src/population.lua) asks it for targets: it
	spawns arrivals while an area is under its target, and simply doesn't
	replace losses while it's over.

	Traders follow estimated hold-load travel time, grouped by route so mixed
	cargo does not inflate fleet demand. Idle and returning capacity offsets
	the backlog. Targets rise gradually and decay without deleting ships.

	Miners follow ore. Whatever ore buyers wanted that no station could
	supply (u.economyUnmet, src/economy.lua) asks for one more miner per
	A.orePerMiner units at every area whose drills dig that ore, up to
	A.maxExtraMiners, rising and decaying the same way.

	Plain data in u.arbiter; works the same offline.
]]
local L=require('src.locations')
local Tasks=require('src.tasks')
local A={tick=60,maxExtra=12,decay=1/300,orePerMiner=100,maxExtraMiners=12,universe=nil}

function A.state(u) u.arbiter=u.arbiter or {extra={},next=0};return u.arbiter end

function A.update(u,clock)
 A.universe=u
 local s=A.state(u)
 if clock<s.next then return end
 local dt=s.at and clock-s.at or A.tick
 s.next=clock+A.tick;s.at=clock
 local Transport=require('src.transport')
 local data=require('src.data')
 local open,capacity={},{}
 local lanes={};local offers={}
 for _,o in pairs(Tasks.state(u).offers) do
  if o.order and o.state=='available' and (o.readyAt or 0)<=clock then
   local place=L.byId[o.source]
   if place and Transport.available(u,o.source,o.item,o.id)>0 then
    offers[#offers+1]=o
    local area=place.area;local key=o.source..'>'..o.target
    local lane=lanes[key] or {area=area,volume=0,time=Transport.duration(o,nil,clock),age=0};lanes[key]=lane
    lane.volume=lane.volume+o.amount*data.items[o.item].volume
    lane.age=math.max(lane.age,math.max(require('src.economy').shortageAge(u,o.target,o.item,clock),clock-(o.placed or clock)))
   end
  end
 end
 for _,lane in pairs(lanes) do
  -- Same-route commodities share a hold. Aging adds pressure only while
  -- real, sourced cargo is waiting, bounded to twice the estimated work.
  local work=math.max(1/4,lane.volume/30)*lane.time*(1+math.min(1,lane.age/1200))
  open[lane.area]=(open[lane.area] or 0)+work
 end
 for _,r in pairs(u.npcs or {}) do
  if r.populationGroup=='trader' and r.state~='dead' and r.state~='escaped' then
   local task=r.task or r.suspendedTask
   local area=task and L.byId[task.source] and L.byId[task.source].area or r.area or r.home
   if area then
    capacity[area]=capacity[area] or {idle=0,busy=0,idleCapacity=0,busyCapacity=0}
    local c=capacity[area]
    local size=0
    if not task then
     c.present=(c.present or 0)+1
     for _,o in ipairs(offers) do
      if L.byId[o.source].area==area then size=math.max(size,Transport.usable(u,r,o,clock)/30) end
     end
     if size>0 then c.idle=c.idle+1;c.idleCapacity=c.idleCapacity+size end
    elseif task.kind=='transport' then
     c.present=(c.present or 0)+1;c.busy=c.busy+1
     if not r.suspendedTask and not r.service and r.fuelStatus~='stranded' and r.fuelStatus~='empty' and require('src.reactor_fuel').remaining(r.ship)>0 then
      local remaining=Transport.duration(task,task.phase=='pickup' and r.node or nil,clock)
      if r.action and r.action.arriveAt then remaining=math.max(remaining,r.action.arriveAt-clock) end
      if task.phase=='pickup' then remaining=remaining+180 end
      size=(data.hulls[r.ship.hull].hold or 0)/30
      c.busyCapacity=c.busyCapacity+size*math.min(.25,600/(600+remaining)*.25)
     end
    else c.present=(c.present or 0)+1 end
   end
  end
 end
 local areas={}
 for area in pairs(open) do areas[area]=true end
 for area in pairs(s.extra) do areas[area]=true end
 for area in pairs(capacity) do areas[area]=true end
 s.freight={}
 for area in pairs(areas) do
  local c=capacity[area] or {idle=0,busy=0,idleCapacity=0,busyCapacity=0}
  -- Clear a ten-minute backlog with usable idle ships; busy ships receive
  -- conservative credit discounted by their remaining phase. Existing extras count toward the target.
  local have=s.extra[area] or 0
  local shortage=math.max(0,(open[area] or 0)/600-c.idleCapacity-c.busyCapacity)
  local base=require('src.fields')[area].alifeTraders or 0
  local pending=math.max(0,base+have-(c.present or 0))
  local want=math.min(A.maxExtra,shortage>0 and math.max(0,math.ceil(have+shortage-pending)) or math.max(0,have-c.idle*.5))
  if not open[area] then want=0 end
  local v=want>have and math.min(want,have+dt/60) or math.max(want,have-dt*A.decay)
  s.extra[area]=v>0 and v or nil
  s.freight[area]={work=open[area] or 0,idle=c.idle,busy=c.busy,shortage=shortage,target=v}
 end
 -- miners: unmet ore, by the areas that dig each kind
 s.miners=s.miners or {}
 local unmet=u.economyUnmet or {}
 local digs={}
 for _,site in pairs(require('src.jobs').state(u).sites or {}) do
  if site.item then digs[site.area]=digs[site.area] or {};digs[site.area][site.item]=true end
 end
 local mareas={}
 for area in pairs(digs) do mareas[area]=true end
 for area in pairs(s.miners) do mareas[area]=true end
 for area in pairs(mareas) do
  local short=0
  for item in pairs(digs[area] or {}) do short=short+(unmet[item] or 0) end
  local want=math.min(A.maxExtraMiners,math.ceil(short/A.orePerMiner))
  local have=s.miners[area] or 0
  local v=want>=have and want or math.max(want,have-dt*A.decay)
  s.miners[area]=v>0 and v or nil
 end
end
function A.extraMiners(area)
 local u=A.universe;if not u or not u.arbiter or not u.arbiter.miners then return 0 end
 return math.floor(u.arbiter.miners[area] or 0)
end

-- Extra traders this area should have over its base.
function A.extraTraders(area)
 local u=A.universe;if not u or not u.arbiter then return 0 end
 return math.floor(u.arbiter.extra[area] or 0)
end
function A.panel(game,Slab)
 local u=game.universe;local s=A.state(u);local keys={}
 for area in pairs(s.freight or {}) do keys[#keys+1]=area end;table.sort(keys)
 for _,area in ipairs(keys) do
  local f=s.freight[area]
  Slab.Text(('%s: %.1f ship-min waiting | %d usable idle, %d hauling | %.1f extra target'):format(area,f.work/60,f.idle,f.busy,f.target))
 end
 for item,n in pairs(u.economyUnmet or {}) do
  if n>0 then Slab.Text(('No surplus production: %s %.0f'):format(item,n)) end
 end
 for area,timers in pairs(u.populationSpawns or {}) do for group,timer in pairs(timers) do
  if timer.status then Slab.Text(area..' / '..group..': '..timer.status) end
 end end
 local pickup,moving=0,0
 for _,o in pairs(Tasks.state(u).offers) do
  if o.order and o.state~='available' then
   if o.loaded then moving=moving+o.amount else pickup=pickup+o.amount end
  end
 end
 Slab.Text(('Reserved awaiting pickup: %d units | in transit: %d units'):format(pickup,moving))
end

return A
