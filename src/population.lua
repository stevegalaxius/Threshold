-- Shared replenishment: role definitions provide ships/work; this module owns
-- saved arrival timers, population limits and warp placement.
local Fields,L,T=require('src.fields'),require('src.locations'),require('src.tuning')
local P={roles={},order={}}
function P.register(role,definition)
 assert(not P.roles[role],'duplicate population role '..role)
 P.roles[role]=definition;P.order[#P.order+1]=role
end
function P.state(u)
 u.populationSpawns=u.populationSpawns or {}
 -- Carry the existing pirate schedule into the shared representation.
 for area,timer in pairs(u.pirateSpawns or {}) do
  u.populationSpawns[area]=u.populationSpawns[area] or {}
  u.populationSpawns[area].pirate=u.populationSpawns[area].pirate or timer
 end
 u.pirateSpawns=nil
 return u.populationSpawns
end
function P.target(area,role)
 local f,def=Fields[area],P.roles[role]
 if not f or f.instance or f.transit or not def then return 0 end
 return def.target(f,area) or 0
end
-- Traders are free agents: they count where they are, not where they
-- first arrived, so an area its ships have left gets new ones.
function P.where(r) return r.role=='trader' and (r.area or r.home) or r.home end
function P.total(u,role)
 local n=0
 for _,r in pairs(u.npcs or {}) do if r.role==role and r.state~='dead' and r.state~='escaped' then n=n+1 end end
 return n
end
function P.count(u,area,role)
 local n=0
 for _,r in pairs(u.npcs or {}) do
  if P.where(r)==area and r.role==role and r.state~='dead' and r.state~='escaped' then n=n+1 end
 end
 return n
end
local function delay(area,role,sequence)
 local hash=sequence*7919;local key=area..'/'..role
 for i=1,#key do hash=(hash*31+key:byte(i))%2147483647 end
 local config=T.population[role]
 local low,high=math.min(config.minDelay,config.maxDelay),math.max(config.minDelay,config.maxDelay)
 return math.max(1,low+(hash%10001)/10000*(high-low))
end
function P.schedule(game,clock)
 if game.preview then return end
 local state=P.state(game.universe)
 for _,area in ipairs(Fields.list) do
  for _,role in ipairs(P.order) do
   if P.target(area,role)>0 then
    state[area]=state[area] or {}
    if not state[area][role] then state[area][role]={nextAt=clock+delay(area,role,0),sequence=0} end
   end
  end
 end
end
local function clearArrival(game,x,y,margin)
 if not game:isClear(x,y,margin) then return false end
 local clear=true
 -- a mass driver is huge: keep a whole ship's length off its hull
 local m=math.max(300,margin or 0)
 game.world:queryBoundingBox(x-m,y-m,x+m,y+m,function(fixture)
  local e=fixture:getUserData() or fixture:getBody():getUserData()
  if e and e.kind=='driver' and not fixture:isSensor() then clear=false;return false end
  return true
 end)
 return clear
end
local function entryPoint(game)
 local p=game.player
 if not p or p.dead then return end
 local x,y=p.body:getPosition();local w=game.well
 local radius=math.sqrt(x*x+y*y)
 local safe=w and w.radius+math.min(T.surfacePullRange,w.radius*.5)+500 or 500
 local r=math.min(game.arenaRadius-500,math.max(safe,radius+300))
 local bearing=math.atan2(y,x)
 for _=1,20 do
  local a=bearing+(love.math.random()<.5 and -1 or 1)*(900+love.math.random()*500)/math.max(radius,1)
  local px,py=math.cos(a)*r,math.sin(a)*r
  if clearArrival(game,px,py,200) then return px,py end
 end
end
function P.spawn(game,area,role,nearPlayer)
 local def=P.roles[role]
 if P.target(area,role)<=0 then return nil,'No '..role..' population in this region.' end
 local nodes=def.nodes(game,area)
 if not nodes or #nodes==0 then return nil,'No '..role..' navigation route in this region.' end
 local clock=game.universe.clock
 -- warp in near a station or waypoint, not on a mass driver's barrel
 -- (a driver is only a start when nothing else is on the route)
 local anchors={}
 for _,id in ipairs(nodes) do local place=L.byId[id];if not (place and place.kind=='driver') then anchors[#anchors+1]=id end end
 if #anchors==0 then anchors=nodes end
 local node=anchors[love.math.random(#anchors)]
 local x,y
 local localArea=area==game.fieldId and not game.lane and not game.flight
 if nearPlayer and localArea then x,y=entryPoint(game) end
 if x then
  local distance=math.huge
  for _,candidate in ipairs(nodes) do
   local nx,ny=L.position(candidate,clock);local d=(nx-x)^2+(ny-y)^2
   if d<distance then node,distance=candidate,d end
  end
 end
 if localArea and not x then
  local nx,ny=L.position(node,clock)
  for _=1,20 do
   local a=love.math.random()*math.pi*2;local distance=200+love.math.random()*500
   local sx,sy=nx+math.cos(a)*distance,ny+math.sin(a)*distance
   -- never inside the planet (or its pull zone): stations ring it closely
   local w=game.well;local surface=w and w.radius+math.min(T.surfacePullRange,w.radius*.5)+300 or 0
   if sx*sx+sy*sy<(game.arenaRadius-200)^2 and sx*sx+sy*sy>surface*surface and clearArrival(game,sx,sy,150) then x,y=sx,sy;break end
  end
  if not x then return nil,'No clear space for an NPC arrival.' end
 end
 local r=def.create(game,area,node,clock)
 if not r then return nil,'No starting work for '..role..'.' end
 local A=require('src.alife')
 r.spawnedAt=clock;r.warpUntil=clock+T.npcWarpDuration;r.spawnOrigin='warp'
 if x then
  local nx,ny=A.point(r,clock)
  r.offset={x=x-nx,y=y-ny,progress=0}
  local vx,vy=game:flowAt(x,y)
  r.pose={x=x,y=y,a=math.atan2(-y,-x),vx=vx,vy=vy,w=0,clock=clock}
 end
 if localArea and game.player and not game.player.dead then
  local px,py=game.player.body:getPosition()
  local sx,sy=x,y
  if not sx then sx,sy=A.point(r,clock) end
  if (sx-px)^2+(sy-py)^2<T.alifeNear^2 then A.wake(game,r) end
 end
 return r
end
function P.update(game,clock)
 if game.preview then return end
 local u=game.universe;local counts={}
 for _,r in pairs(u.npcs) do
  if r.state~='dead' and r.state~='escaped' then
   local key=P.where(r)..'/'..r.role;counts[key]=(counts[key] or 0)+1
  end
 end
 for _,area in ipairs(Fields.list) do
  local timers=u.populationSpawns and u.populationSpawns[area]
  if timers then
   for _,role in ipairs(P.order) do
    local timer=timers[role]
    if timer and clock>=timer.nextAt then
     timer.sequence=timer.sequence+1;timer.nextAt=clock+delay(area,role,timer.sequence)
     local def=P.roles[role]
     -- a role with a world-wide budget (traders) also stops at that
     if (counts[area..'/'..role] or 0)<P.target(area,role) and (not def.budget or P.total(u,role)<def.budget()) then P.spawn(game,area,role,false) end
    end
   end
  end
 end
end
return P
