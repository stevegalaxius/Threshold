-- Fixed-role duties use the same reservation/task lifecycle as transport.
local Tasks=require('src.tasks')
local G=require('src.travelgraph')
local L=require('src.locations')
local Fields=require('src.fields')
local data=require('src.data')
local Stats=require('src.stats')
local T=require('src.tuning')
local copy=require('src.persistence').copy
local Population=require('src.population')
local Homes=require('src.npc_home')
local S={}
function S.isRole(r) return r and (r.role=='patrol' or r.role=='pirate') end
local function route(source,target,clock)
 if source==target then return {source,source} end
 local path=G.route(G.build(L.get(source).area),source,target,clock)
 if not path then return end
 local result={source}
 for _,leg in ipairs(path.legs) do result[#result+1]=leg.edge.to end
 if #result==1 then result[2]=source end
 return result
end
local function raidLeg(area,from,to)
 local field=Fields[area];local nodes={}
 for _,id in ipairs(field.buoyIds) do nodes[id]=true end
 if #field.buoyIds<=1 then return from==to end
 if not nodes[from] or not nodes[to] then return false end
 -- Use declared connectivity, so reordering buoy definitions changes no duty.
 for _,link in ipairs(field.raidLinks or {}) do
  if link[1]==from and link[2]==to or link[1]==to and link[2]==from then return true end
 end
 return false
end
local Repairs=require('src.npc_repair')
local Supplies=require('src.supplies')
local repairStation=Repairs.supports
local armorMax=Repairs.maximum
local needsRepair=Repairs.needs
local function dockStay(r,node) return Repairs.stay(r,node,T.patrolDockStay) end
for _,kind in ipairs({'patrol','raid'}) do
 local role=kind=='patrol' and 'patrol' or 'pirate'
 Tasks.register(kind,{
  roles={[role]=true},
  eligible=function(u,r,o,node,clock)
   -- A multi-buoy raid should travel, rather than reserve a minute of waiting
   -- at its current buoy. Driver-only regions still have a holding duty.
   if kind=='raid' and not raidLeg(r.area,o.source,o.target) then return false end
   return L.canonical(node)==L.canonical(o.source) and route(node,o.target,clock)~=nil
  end,
  score=function(u,r,o,node,clock)
   return clock-(o.readyAt or 0)-(r.lastDutyTarget==o.target and 10000 or 0)
    +(role=='patrol' and ((needsRepair(r) and repairStation(o.target)) or (Supplies.needs(r) and Supplies.supports(o.target))) and 1000000 or 0)
  end,
  prepare=function(u,r,t)
   t.phase=kind=='patrol' and 'patrolling' or 'raiding'
   if role=='patrol' and L.get(t.target).kind=='station' then
    local visits=(r.patrolStationVisits or ((tonumber(r.id:match('%d+$')) or 0)%T.patrolDockEvery))+1
    r.patrolStationVisits=visits
    local repair=needsRepair(r) and repairStation(t.target)
    local supply=Supplies.needs(r) and Supplies.supports(t.target)
    t.dock=visits%T.patrolDockEvery==0 or repair or supply
    if t.dock then t.duration=dockStay(r,t.target);t.phase=repair and 'repair visit' or supply and 'resupply visit' or 'station docking visit' end
   end
   return true
  end,
  plan=function(t,node,clock) return route(node,t.target,clock) end,
  complete=function(u,r,t,node) if L.canonical(node)~=L.canonical(t.target) then return false end;r.lastDutyTarget=node;return true end,
 })
end
local function raidNodes(f)
 if f.instance or f.transit then return end
 if #f.buoyIds>0 then return f.buoyIds end
 if f.driverId then return {f.driverId} end
end
function S.patrolNodes(area)
 local nodes=L.stations(area,'patrol')
 for _,id in ipairs(Fields[area].buoyIds) do nodes[#nodes+1]=id end
 return nodes
end
local function ensureOffers(u,area,kind,nodes)
 local state=Tasks.state(u);state.navigationDuties=state.navigationDuties or {}
 local signature=table.concat(nodes,'|')..':'..Fields[area].navigationVersion
 local scope=kind..':'..area
 if state.navigationDuties[scope]~=signature then
  local specs={}
  for _,from in ipairs(nodes) do for _,to in ipairs(nodes) do
   if kind=='raid' and raidLeg(area,from,to) or kind=='patrol' and from~=to then
    specs[#specs+1]={kind=kind,source=from,target=to,cooldown=0,
     duration=kind=='raid' and T.pirateLinger or T.patrolInspect}
   end
  end end
  Tasks.sync(u,scope,specs,function(o)
   local source=L.byId[o.source]
   return o.kind==kind and source and source.area==area
  end)
  state.navigationDuties[scope]=signature
 end
 return nodes
end
function S.ensureRaids(u,area)
 local nodes=raidNodes(Fields[area])
 if nodes then return ensureOffers(u,area,'raid',nodes) end
end
function S.ensurePatrols(u,area)
 return ensureOffers(u,area,'patrol',S.patrolNodes(area))
end

local function create(game,area,role,node,clock,start)
 local u=game.universe
 local archetype=role=='patrol' and 'patrol_wisp' or 'pirate_wisp'
 local def=data.enemies[archetype];local hull=data.hulls[def.hull]
 local loadout=copy(def.loadout or hull.loadout)
 local stats=Stats.compute(hull,loadout)
 u.nextNpcId=u.nextNpcId+1
 local r={id='npc/'..u.nextNpcId,home=area,area=area,role=role,archetype=archetype,
  speed=def.ai.cruise,spread=0,route={node,node},index=1,node=node,state='idle',untilTime=clock,
  ship={hull=def.hull,loadout=loadout,cargo=copy(def.cargo),armor=stats.armor}}
 local home
 if role=='pirate' then home=L.station(nil,'pirateBase') else home=L.station(area,'trade') end
 if home then Homes.assign(r,home) end
 u.npcs[r.id]=r
 S.advance(r,clock,u,start)
 return r
end
-- Role-specific work stays here; shared arrival scheduling lives in population.
local function ensureDuty(u,area,role,node,nodes,clock)
 local kind=role=='pirate' and 'raid' or 'patrol'
 local available=false
 for _,offer in pairs(Tasks.state(u).offers) do
  if offer.kind==kind and offer.source==node and offer.state=='available' and (offer.readyAt or 0)<=clock
   and (role~='pirate' or raidLeg(area,node,offer.target)) then available=true;break end
 end
 if not available then
  local target=node
  for _,id in ipairs(nodes) do
   if id~=node and (role~='pirate' or raidLeg(area,node,id)) then target=id;break end
  end
  Tasks.post(u,{kind=kind,source=node,target=target,cooldown=0,
   duration=role=='pirate' and T.pirateLinger or T.patrolInspect})
 end
end
function S.spawnPirate(game,area,nearPlayer) return Population.spawn(game,area,'pirate',nearPlayer) end
function S.pirateCount(u,area) return Population.count(u,area,'pirate') end
function S.updateSpawns(game,clock) return Population.update(game,clock) end

function S.seed(game,start)
 local u=game.universe
 local state=Tasks.state(u);state.securityAreas=state.securityAreas or {}
 for _,area in ipairs(Fields.list) do
  local f=Fields[area]
  if f.alifeSecurity then S.ensurePatrols(u,area);S.ensureRaids(u,area) end
  if f.alifeSecurity and not state.securityAreas[area] then
   state.securityAreas[area]=true
   for _,role in ipairs({'patrol','pirate'}) do
    for i=1,f.alifeSecurity[role] do
     local node=f.buoyIds[(i-1)%#f.buoyIds+1]
     local r=create(game,area,role,node,u.clock,start)
     if r.state=='travel' then
      local elapsed=(r.arrive-r.depart)*(role=='pirate' and .65 or .15+i*.2)
      r.depart,r.arrive=r.depart-elapsed,r.arrive-elapsed
     end
    end
   end
  end
 end
end
function S.shouldDock(r,node)
 return r and r.role=='patrol' and r.task and r.task.kind=='patrol' and r.task.dock and L.canonical(r.task.target)==L.canonical(node)
end
-- Choose a station-local holding point outside its hull and every runway.
function S.inspectionPoint(game,station,e)
 if station.city then
  local x,y=L.inspectionPosition(station.locationId,game.universe.clock)
  local vx,vy=L.inspectionVelocity(station.locationId,game.universe.clock)
  return x,y,vx,vy
 end
 local cached=e.patrolInspection
 if not cached or cached.station~=station then
  local x,y=station.body:getPosition();local angle=math.atan2(y,x)-station.body:getAngle()
  local radius=station.radius+T.patrolStandOff+e.halfLength
  local chosen
  for _,offset in ipairs({0,math.pi/3,-math.pi/3,math.pi*2/3,-math.pi*2/3,math.pi}) do
   local a=angle+offset;local lx,ly=math.cos(a)*radius,math.sin(a)*radius
   local clear=true
   for _,d in ipairs(station.docks or {station.dock}) do
    local c,s=math.cos(d.a or 0),math.sin(d.a or 0)
    local along,across=lx*c+ly*s-(d.xc or 0),-lx*s+ly*c-(d.yc or 0)
    if math.abs(across)<(d.capture or d.hw)+e.halfLength+T.patrolStandOff
     and (along>d.x2-e.halfLength or d.both and along<d.x1+e.halfLength) then clear=false;break end
   end
   if clear then chosen={station=station,x=lx,y=ly};break end
  end
  cached=chosen or {station=station,x=math.cos(angle+math.pi/2)*radius,y=math.sin(angle+math.pi/2)*radius}
  e.patrolInspection=cached
 end
 local x,y=station.body:getWorldPoint(cached.x,cached.y)
 local vx,vy=station.body:getLinearVelocityFromWorldPoint(x,y)
 return x,y,vx,vy
end
function S.arrive(r,node,clock)
 r.state=S.shouldDock(r,node) and 'docked' or 'idle';r.node=node;r.route={node,node};r.index=1
 r.untilTime=clock+(r.task and r.task.duration or T.patrolInspect)
 if r.state=="docked" then Repairs.begin(r,node,clock,T.patrolDockStay) end
 r.offset,r.pose=nil,nil
end
function S.advance(r,clock,u,start)
 if r.state=='dead' or r.state=='escaped' or r.encounter then return end
 if r.role=='pirate' and r.state=='idle' and r.task and r.task.source==r.task.target
  and #Fields[r.area].buoyIds>1 then r.untilTime=math.min(r.untilTime,clock) end
 -- Bound catch-up work without dropping a partially completed duty.
 for _=1,128 do
  if r.state=='travel' then
   if clock<r.arrive then return end
   local at=r.arrive
   if r.index<#r.route then start(r,at,r.index+1)
   else S.arrive(r,r.route[r.index],at) end
  elseif r.state=='idle' or r.state=='docked' then
   if r.state=='docked' then Repairs.advance(r,clock,r.node) end
   if clock<r.untilTime then return end
   local at=r.untilTime
   Tasks.arrive(u,r,r.node,at)
   local task=Tasks.choose(u,r,r.node,at)
   if not task then r.untilTime=clock+10;return end
   r.repairAt=nil
   r.route=assert(Tasks.plan(r,r.node,at));r.index=1
   if task.target==r.node then
    r.untilTime=at+task.duration
   else start(r,at,2) end
  else return end
 end
end
function S.capture(game,e,r,remote)
 local clock=game.universe.clock
 r.index=e.routeIndex or r.index
 if r.state=='travel' then
  local edge={from=r.route[(r.index-2)%#r.route+1],to=r.route[r.index]}
  local graph=G.build(r.area)
  local x,y=e.body:getPosition()
  local p=math.min(.99,G.project(graph,edge,x,y,clock))
  local duration=math.max(.1,G.length(graph,edge,clock)/r.speed)
  r.depart=clock-p*duration;r.arrive=r.depart+duration
  if r.encounter then r.encounter.progress=p end
  r.offset=nil
  if not remote then
   local bx,by=G.point(graph,edge,p,clock)
   r.offset={x=x-bx,y=y-by,progress=p}
  end
 elseif not remote then
  local x,y=e.body:getPosition();local bx,by=L.inspectionPosition(r.node,clock)
  r.offset={x=x-bx,y=y-by}
 end
 r.fleeing=e.fleeing or nil
 r.pose=nil
 if not remote then
  local x,y=e.body:getPosition();local vx,vy=e.body:getLinearVelocity()
  r.pose={x=x,y=y,a=e.body:getAngle(),vx=vx,vy=vy,w=e.body:getAngularVelocity(),clock=clock}
 end
end
-- Civilian A-Life ships pirates hunt; matches offline encounters.lua.
local PREY={trader=true,courier=true,miner=true,salvager=true}
function S.prey(o) return o.npcRole and PREY[o.npcRole] or false end
function S.hostile(game,e,o)
 if not o or o==e or o.kind~='ship' or o.dead or o.removed or o.dockState or o.driverProtected then return false end
 if o==e.aggressor then return true end
 -- patrols answer aggression (as stations do, and as offline does)
 if e.alifeRole=='patrol' then return o.team==2 and o.aggressedAt~=nil and game.time-o.aggressedAt<30 end
 if e.alifeRole=='pirate' then
  return o.team~=2 and (o.isPlayer or o.alifeRole=='patrol' or S.prey(o)) and not require('src.robbery').isSpared(game,e,o)
 end
 return false
end
function S.target(game,e)
 local record=game.universe.npcs[e.alifeId]
 if e.alifeRole=='patrol' and record and Supplies.needs(record,e) then e.combatTarget=nil;e.lock=nil;return nil end
 if game.time<(e.securityThink or 0) then return S.hostile(game,e,e.combatTarget) and e.combatTarget or nil end
 e.securityThink=game.time+T.securityThink
 local x,y=e.body:getPosition()
 local best,bestRank,bestDistance=nil,-1,T.securityRange^2
 for _,o in ipairs(game.entities) do
  if S.hostile(game,e,o) then
   local ox,oy=o.body:getPosition();local d=(ox-x)^2+(oy-y)^2
   local rank=o==e.aggressor and 3 or e.alifeRole=='pirate' and S.prey(o) and 2 or 1
   if d<T.securityRange^2 and (rank>bestRank or rank==bestRank and d<bestDistance) then best,bestRank,bestDistance=o,rank,d end
  end
 end
 e.combatTarget=best;e.lock=best
 local r=game.universe.npcs[e.alifeId]
 if r then r.targetId=best and (best.alifeId or best.isPlayer and 'player') or nil end
 return best
end
function S.updateOnline(game,e,A)
 local r=game.universe.npcs[e.alifeId]
 if r.piracy then return end
 if r.role=='pirate' and r.state=='idle' and r.task and not raidLeg(r.area,r.task.source,r.task.target) then r.untilTime=game.universe.clock end
 if r.state=='idle' and game.universe.clock>=r.untilTime and not r.encounter then
  r.ship.armor=e.armor;r.ship.cargo=copy(e.cargo)
  if e.hold then r.ship.hold=require('src.inventory.hold').serialize(e.hold) end
  S.advance(r,game.universe.clock,game.universe,A.start)
  A.bindRoute(game,e,r)
 end
end
function S.hold(game,e,AI)
 local r=game.universe.npcs[e.alifeId]
 if r.state~='idle' then return false end
 local x,y=e.body:getPosition();local tx,ty=L.position(r.node,game.universe.clock)
 local vx,vy=L.velocity(r.node,game.universe.clock)
 local station=game:locationEntity(r.node)
 if station and station.kind=='station' then
  tx,ty,vx,vy=S.inspectionPoint(game,station,e)
 end
 -- Distinct holding offsets keep ships assigned to the same place from
 -- continually pushing toward the exact same point. These are not graph nodes.
 local seed=tonumber(r.id:match('%d+$')) or e.id
 local angle=seed*2.3999632297
 local spacing=e.halfLength+120
 if not station or station.kind~='station' then
  tx,ty=tx+math.cos(angle)*spacing,ty+math.sin(angle)*spacing
 end
 local dx,dy=tx-x,ty-y;local d=math.sqrt(dx*dx+dy*dy)
 local a=e.body:getAngle()
 AI.navigate(game,e,dx,dy,d>T.aiBoostStopMargin*2 and (e.def.ai.cruise or T.traderCruise) or math.min(150,d*.5),vx,vy,d>T.aiBoostStopMargin*2 and d or nil)
 e.intent.aimX,e.intent.aimY=x+math.cos(a)*300,y+math.sin(a)*300
 return true
end

function S.visit(game,e,stop,A)
 local pr=game.universe.npcs[e.alifeId]
 -- A pirate redeploying reaches the end of its trip at a buoy, not a dock:
 -- finish the trip there (as offline) instead of wrapping the route.
 if pr.piracy and pr.piracy.phase=='redeploy' and e.routeIndex>=#e.route and not pr.worldRecovery then
  A.capture(game,e,false)
  if require('src.piracy').depart(game.universe,pr,game.universe.clock,A.start) then A.bindRoute(game,e,pr) end
  return true
 end
 if game.universe.npcs[e.alifeId].piracy or game.universe.npcs[e.alifeId].worldRecovery then return false end
 if not e.alifeRole or e.routeIndex<#e.route then return false end
 local r=game.universe.npcs[e.alifeId]
 if r.state=='travel' then
  S.arrive(r,stop.locationId,game.universe.clock)
  A.bindRoute(game,e,r)
 end
 return true
end
for _,role in ipairs({'pirate','patrol'}) do
 Population.register(role,{
  target=function(f)
   if role=='pirate' then
    local override=f.navigation and f.navigation.population and f.navigation.population.pirate
    return raidNodes(f) and (override~=nil and override or T.population.pirate.target)
   end
   return f.alifeSecurity and f.alifeSecurity.patrol
  end,
  nodes=function(game,area)
   if role=='pirate' then return S.ensureRaids(game.universe,area) end
   return Fields[area].buoyIds
  end,
  create=function(game,area,node,clock)
   local nodes=role=='pirate' and S.ensureRaids(game.universe,area) or Fields[area].buoyIds
   ensureDuty(game.universe,area,role,node,nodes,clock)
   return create(game,area,role,node,clock,require('src.alife').start)
  end,
 })
end
return S
