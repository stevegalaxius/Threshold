-- Fixed-role duties use the same reservation/task lifecycle as transport.
local Tasks=require('src.tasks')
local G=require('src.travelgraph')
local L=require('src.locations')
local Fields=require('src.fields')
local data=require('src.data')
local Stats=require('src.stats')
local T=require('src.tuning')
local copy=require('src.persistence').copy
local S={}
function S.isRole(r) return r and (r.role=='patrol' or r.role=='pirate') end
local function route(source,target,clock)
 if source==target then return {source,source} end
 local path=G.route(G.build(L.get(source).area),source,target,clock)
 if not path then return end
 local result={source}
 for _,leg in ipairs(path.legs) do result[#result+1]=leg.edge.to end
 return result
end
for _,kind in ipairs({'patrol','raid'}) do
 local role=kind=='patrol' and 'patrol' or 'pirate'
 Tasks.register(kind,{
  roles={[role]=true},
  eligible=function(u,r,o,node,clock) return node==o.source and route(node,o.target,clock)~=nil end,
  score=function(u,r,o,node,clock)
   return clock-(o.readyAt or 0)-(r.lastDutyTarget==o.target and 10000 or 0)
  end,
  prepare=function(u,r,t) t.phase=kind=='patrol' and 'patrolling' or 'raiding';return true end,
  plan=function(t,node,clock) return route(node,t.target,clock) end,
  complete=function(u,r,t,node) if node~=t.target then return false end;r.lastDutyTarget=node;return true end,
 })
end
function S.seed(game,start)
 local u=game.universe
 local state=Tasks.state(u);state.securityAreas=state.securityAreas or {}
 for _,area in ipairs(Fields.list) do
  local f=Fields[area]
  if f.alifeSecurity and not state.securityAreas[area] then
   state.securityAreas[area]=true
   local nodes=f.traderRoute or f.buoyIds
   -- Patrols inspect existing stations/buoys. Pirates rally at buoys, away
   -- from station clamps; relocation still follows declared connections.
   for _,from in ipairs(nodes) do
    for _,to in ipairs(nodes) do
     if from~=to then Tasks.post(u,{kind='patrol',source=from,target=to,cooldown=0,duration=T.patrolInspect}) end
    end
   end
   for _,from in ipairs(f.buoyIds) do
    for _,to in ipairs(f.buoyIds) do
     Tasks.post(u,{kind='raid',source=from,target=to,cooldown=0,duration=T.pirateLinger})
    end
   end
   for _,role in ipairs({'patrol','pirate'}) do
    for i=1,f.alifeSecurity[role] do
     local archetype=role=='patrol' and 'patrol_wisp' or 'pirate_wisp'
     local def=data.enemies[archetype];local hull=data.hulls[def.hull]
     local loadout=copy(def.loadout or hull.loadout)
     local stats=Stats.compute(hull,loadout)
     u.nextNpcId=u.nextNpcId+1
     local node=f.buoyIds[(i-1)%#f.buoyIds+1]
     local r={id='npc/'..u.nextNpcId,home=area,area=area,role=role,archetype=archetype,
      speed=def.ai.cruise,spread=0,route={node,node},index=1,node=node,state='idle',untilTime=u.clock,
      ship={hull=def.hull,loadout=loadout,cargo=copy(def.cargo),armor=stats.armor,color=copy(def.color)}}
     u.npcs[r.id]=r
     S.advance(r,u.clock,u,start)
     if r.state=='travel' then
      local elapsed=(r.arrive-r.depart)*(role=='pirate' and .65 or .15+i*.2)
      r.depart,r.arrive=r.depart-elapsed,r.arrive-elapsed
     end
    end
   end
  end
 end
end
function S.arrive(r,node,clock)
 r.state='idle';r.node=node;r.route={node,node};r.index=1
 r.untilTime=clock+(r.task and r.task.duration or T.patrolInspect)
 r.offset,r.pose=nil,nil
end
function S.advance(r,clock,u,start)
 if r.state=='dead' or r.state=='escaped' or r.encounter then return end
 -- Bound catch-up work without dropping a partially completed duty.
 for _=1,128 do
  if r.state=='travel' then
   if clock<r.arrive then return end
   local at=r.arrive
   if r.index<#r.route then start(r,at,r.index+1)
   else S.arrive(r,r.route[r.index],at) end
  elseif r.state=='idle' then
   if clock<r.untilTime then return end
   local at=r.untilTime
   Tasks.arrive(u,r,r.node,at)
   local task=Tasks.choose(u,r,r.node,at)
   if not task then r.untilTime=clock+10;return end
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
  local x,y=e.body:getPosition();local bx,by=L.position(r.node,clock)
  r.offset={x=x-bx,y=y-by}
 end
 r.fleeing=e.fleeing or nil
 r.pose=nil
 if not remote then
  local x,y=e.body:getPosition();local vx,vy=e.body:getLinearVelocity()
  r.pose={x=x,y=y,a=e.body:getAngle(),vx=vx,vy=vy,w=e.body:getAngularVelocity(),clock=clock}
 end
end
function S.hostile(e,o)
 if not o or o==e or o.kind~='ship' or o.dead or o.removed or o.dockState or o.driverProtected then return false end
 if o==e.aggressor then return true end
 if e.alifeRole=='patrol' then return o.team==2 end
 if e.alifeRole=='pirate' then
  return o.team~=2 and (o.isPlayer or o.alifeRole=='patrol' or o.def and o.def.ai.style=='trader')
 end
 return false
end
function S.target(game,e)
 if game.time<(e.securityThink or 0) then return S.hostile(e,e.combatTarget) and e.combatTarget or nil end
 e.securityThink=game.time+T.securityThink
 local x,y=e.body:getPosition()
 local best,bestRank,bestDistance=nil,-1,T.securityRange^2
 for _,o in ipairs(game.entities) do
  if S.hostile(e,o) then
   local ox,oy=o.body:getPosition();local d=(ox-x)^2+(oy-y)^2
   local rank=o==e.aggressor and 3 or e.alifeRole=='pirate' and o.def and o.def.ai.style=='trader' and 2 or 1
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
 if r.state=='idle' and game.universe.clock>=r.untilTime and not r.encounter then
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
  tx,ty=AI.stopPoint(station)
  vx,vy=station.body:getLinearVelocityFromWorldPoint(tx,ty)
 end
 local dx,dy=tx-x,ty-y;local d=math.sqrt(dx*dx+dy*dy)
 local k=d>0 and math.min(150,d*.5)/d or 0
 local a=e.body:getAngle()
 AI.driveVelocity(e,vx+dx*k,vy+dy*k,math.cos(a),math.sin(a),e.def.ai.throttle)
 e.intent.aimX,e.intent.aimY=x+math.cos(a)*300,y+math.sin(a)*300
 return true
end

function S.visit(game,e,stop,A)
 if not e.alifeRole or e.routeIndex<#e.route then return false end
 local r=game.universe.npcs[e.alifeId]
 if r.state=='travel' then
  S.arrive(r,stop.locationId,game.universe.clock)
  A.bindRoute(game,e,r)
 end
 return true
end
return S
