--[[
	The simulation arbiter: how many haulers and miners each area keeps.

	The fleet is a fixed size (T.fleet), not sized to demand: a fleet that
	grew with the freight backlog fed itself (more haulers burn more fuel,
	which needs more ore and canisters, which is more freight) and swung
	between ~170 and ~350 ships as tuning moved the economy across the line.
	Population (src/population.lua) spawns arrivals while an area is under
	its share and doesn't replace losses while it's over.

	  haulers  T.fleet.hauler shared over the trade areas in proportion to
	           their authored base (alifeTraders); an area never gets less
	           than its base
	  miners   T.fleet.miner shared over the mining areas by drill count,
	           never less than T.minersPerArea

	A.update still reads the freight board each minute for the debug panel
	(work waiting against idle and busy ships), but it sets no targets.
	Plain data in u.arbiter; works the same offline.
]]
local L=require('src.locations')
local Tasks=require('src.tasks')
local A={tick=60,universe=nil}

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
  if o.kind=='transport' and o.order and o.state=='available' and (o.readyAt or 0)<=clock then
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
  if r.populationGroup=='hauler' and r.state~='dead' and r.state~='escaped' then
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
 for area in pairs(capacity) do areas[area]=true end
 s.freight={}
 for area in pairs(areas) do
  local c=capacity[area] or {idle=0,busy=0,idleCapacity=0,busyCapacity=0}
  local shortage=math.max(0,(open[area] or 0)/600-c.idleCapacity-c.busyCapacity)
  s.freight[area]={work=open[area] or 0,idle=c.idle,busy=c.busy,shortage=shortage,target=A.extraTraders(area)}
 end
end
-- Shares of a fixed total by weight, whole ships, largest remainders first
-- (ties by area id), never under each area's floor.
local function share(total,weights,floors)
 local sum=0;local list={}
 for area,w in pairs(weights) do sum=sum+w;list[#list+1]=area end
 table.sort(list)
 local out,rest,given={},{},0
 for _,area in ipairs(list) do
  local exact=sum>0 and total*weights[area]/sum or 0
  out[area]=math.floor(exact);given=given+out[area];rest[#rest+1]={area=area,f=exact-out[area]}
 end
 table.sort(rest,function(a,b) return a.f>b.f or a.f==b.f and a.area<b.area end)
 for i=1,math.max(0,total-given) do local e=rest[(i-1)%math.max(1,#rest)+1];if e then out[e.area]=out[e.area]+1 end end
 for _,area in ipairs(list) do out[area]=math.max(out[area],floors[area] or 0) end
 return out
end
local plan
local function fleet()
 local T=require('src.tuning')
 if plan and plan.hauler==T.fleet.hauler and plan.miner==T.fleet.miner then return plan end
 local Fields=require('src.fields')
 local hw,hf,mw,mf={},{},{},{}
 for _,area in ipairs(Fields.list) do
  local f=Fields[area]
  if not f.instance and not f.transit then
   if L.station(area,'trade') and (f.alifeTraders or 0)>0 then hw[area]=f.alifeTraders;hf[area]=f.alifeTraders end
   if #(f.drillIds or {})>0 and L.station(area,'mining') then mw[area]=#f.drillIds;mf[area]=T.minersPerArea end
  end
 end
 plan={hauler=T.fleet.hauler,miner=T.fleet.miner,haulers=share(T.fleet.hauler,hw,hf),miners=share(T.fleet.miner,mw,mf),bases=hf}
 return plan
end
-- Miners an area keeps over T.minersPerArea.
function A.extraMiners(area)
 local n=fleet().miners[area];if not n then return 0 end
 return math.max(0,n-require('src.tuning').minersPerArea)
end
-- Haulers an area keeps over its authored base.
function A.extraTraders(area)
 local p=fleet();local n=p.haulers[area];if not n then return 0 end
 return math.max(0,n-(p.bases[area] or 0))
end
function A.panel(game,Slab)
 local u=game.universe;local s=A.state(u);local keys={}
 for area in pairs(s.freight or {}) do keys[#keys+1]=area end;table.sort(keys)
 for _,area in ipairs(keys) do
  local f=s.freight[area]
  Slab.Text(('%s: %.1f ship-min waiting | %d usable idle, %d hauling | %d extra (fixed)'):format(area,f.work/60,f.idle,f.busy,f.target))
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
