-- Shared replenishment: population templates provide starting ships; this module owns
-- saved arrival timers, population limits and warp placement.
local Fields,L,T=require('src.fields'),require('src.locations'),require('src.tuning')
local P={templates={},order={}}
function P.register(role,definition)
 assert(not P.templates[role],'duplicate population template '..role)
 P.templates[role]=definition;P.order[#P.order+1]=role
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
function P.target(area,role,u)
 local f,def=Fields[area],P.templates[role]
 -- targets that follow stock (pirate berths) read the universe being run
 if u then P.universe=u end
 if not f or f.instance or f.transit or not def then return 0 end
 return def.target(f,area) or 0
end
-- Traders are free agents: they count where they are, not where they
-- first arrived, so an area its ships have left gets new ones.
function P.where(r)
 local def=P.templates[r.populationGroup]
 if def and def.where then return def.where(r) end
 return r.mobile and (r.area or r.home) or r.home
end
function P.total(u,role)
 local n=0
 for _,r in pairs(u.npcs or {}) do if r.populationGroup==role and r.state~='dead' and r.state~='escaped' then n=n+1 end end
 return n
end
function P.count(u,area,role)
 local n=0
 for _,r in pairs(u.npcs or {}) do
  if P.where(r)==area and r.populationGroup==role and r.state~='dead' and r.state~='escaped' then n=n+1 end
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
   if P.target(area,role,game.universe)>0 or P.templates[role].launches then
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
-- The ways into an area: its moon-gate corridors and mass drivers. A new
-- ship arrives through one of them, from the map's edge, never out of thin
-- air beside a station.
function P.entries(area)
 local gates,drivers={},{}
 for _,place in ipairs(Fields[area] and Fields[area].locations or {}) do
  if place.kind=='moon_gate' then gates[#gates+1]=place.id
  elseif place.kind=='driver' then drivers[#drivers+1]=place.id end
 end
 return gates,drivers
end
-- Put a freshly made record on an inbound leg: from an entry point to
-- wherever its first decision put it (S), then on with its work. Offline
-- that is an ordinary travel leg; online it flies in over the edge.
local function arriveFromEdge(game,r,area,clock)
 if r.state=='transit' or r.state=='dead' or not r.route then return false,'state '..tostring(r.state) end
 local G=require('src.travelgraph')
 local A=require('src.alife')
 local S
 -- where its own first leg starts (index 1 on a looped route is heading for
 -- route[1] from the far end, so start it there)
 if r.state=='travel' then S=r.route[r.index-1] or r.route[r.index] else S=r.node or r.route[r.index] end
 if not S or L.get(S).area~=area then return false,'start '..tostring(S)..' not in '..area end
 local gates,drivers=P.entries(area)
 local pool=#gates>0 and gates or drivers
 if #pool==0 then return false end
 local entry=pool[love.math.random(#pool)]
 local driver=L.get(entry).kind=='driver'
 local path
 if entry==S then
  -- starting right at a corridor's mouth is already the map edge
  if not driver then r.arrivedFrom=entry;return true end
  path={entry,entry}   -- at a driver: still come in off its lane
 else path=G.live(entry,S,clock) end
 if not path or #path<2 then return false,'no route '..entry..' -> '..S end
 if driver then
  -- a driver's gun sits inside the map: come in off its lane instead,
  -- over the edge from another planet's bearing (alife start(), driverArrival)
  local origins={}
  for _,other in ipairs(Fields.list) do
   local f=Fields[other]
   if other~=area and Fields.orbits[other] and f and f.driverId then origins[#origins+1]=f.driverId end
  end
  if #origins==0 then return false end
  table.insert(path,1,origins[love.math.random(#origins)])
 end
 r.route=path;r.node=nil;r.untilTime=nil;r.nextDecisionAt=nil
 r.service=nil;r.action=nil;r.dockedAt=nil
 r.state=driver and 'transit' or 'travel'
 A.start(r,clock,driver and 3 or 2)
 r.arrivedFrom=entry
 return true
end
P.arriveFromEdge=arriveFromEdge
function P.spawn(game,area,role,nearPlayer)
 local def=P.templates[role]
 if P.target(area,role,game.universe)<=0 then return nil,'No '..role..' population in this region.' end
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
 if localArea and not x and #(select(1,P.entries(area)))+#(select(2,P.entries(area)))==0 then
  -- A-Life is persistent: a new ship arrives out of the player's sight,
  -- at a station or waypoint off-screen, never in front of them
  local pl=game.player
  local px,py
  if pl and not pl.dead and pl.body and not pl.body:isDestroyed() then px,py=pl.body:getPosition() end
  local hidden=(game.viewReach and game:viewReach() or 3000)+1500
  local nx,ny
  for _=1,20 do
   node=anchors[love.math.random(#anchors)]
   nx,ny=L.position(node,clock)
   if not px or (nx-px)^2+(ny-py)^2>(hidden+700)^2 then break end
   nx=nil
  end
  if not nx then return nil,'Every arrival point is in view.' end
  for _=1,20 do
   local a=love.math.random()*math.pi*2;local distance=200+love.math.random()*500
   local sx,sy=nx+math.cos(a)*distance,ny+math.sin(a)*distance
   -- never inside the planet (or its pull zone): stations ring it closely
   local w=game.well;local surface=w and w.radius+math.min(T.surfacePullRange,w.radius*.5)+300 or 0
   if sx*sx+sy*sy<(game.arenaRadius-200)^2 and sx*sx+sy*sy>surface*surface and clearArrival(game,sx,sy,150) then x,y=sx,sy;break end
  end
  if not x then return nil,'No clear space for an NPC arrival.' end
 end
 local Rank=require('src.npc_rank')
 local policy=Rank.policy(require('src.npc_templates').purchase(role),Rank.roll())
 local Supply=require('src.npc_ship_supply')
 local ship,acquisition=Supply.acquire(game.universe,area,policy)
 -- a poor rank that can afford nothing arrives as proficient instead
 if not ship and policy.rank=='rookie' then policy=Rank.policy(require('src.npc_templates').purchase(role),'proficient');ship,acquisition=Supply.acquire(game.universe,area,policy) end
 if not ship then return nil,'No suitable manufactured hull within acquisition budget.' end
 game.arrivalShip=ship
 local r=def.create(game,area,node,clock)
 game.arrivalShip=nil
 if not r then return nil,'No starting work for '..role..'.' end
 Supply.complete(game.universe,r,acquisition,policy)
 if def.provision then def.provision(game,r) else require('src.supplies').provision(r) end
 local A=require('src.alife')
 r.spawnedAt=clock
 local edge,why=false,'debug arrival'
 if def.launches then
  -- bought and fitted at a station: it undocks from there, no arrival leg
  r.spawnOrigin='launch';x=nil
 else
  if not x then edge,why=arriveFromEdge(game,r,area,clock) end
  if edge then r.spawnOrigin='edge'
  else r.warpUntil=clock+T.npcWarpDuration;r.spawnOrigin='warp';r.arrivalSkip=why end
 end
 -- a ship whose first move already took it out of the area (into a lane,
 -- state 'transit') has no point here: no arrival pose, nothing to wake
 local here=A.point(r,clock)~=nil
 if x and here then
  local nx,ny=A.point(r,clock)
  r.offset={x=x-nx,y=y-ny,progress=0}
  local vx,vy=game:flowAt(x,y)
  r.pose={x=x,y=y,a=math.atan2(-y,-x),vx=vx,vy=vy,w=0,clock=clock}
 end
 if here and localArea and game.player and not game.player.dead then
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
  if r.populationGroup and r.state~='dead' and r.state~='escaped' then
   local key=P.where(r)..'/'..r.populationGroup;counts[key]=(counts[key] or 0)+1
  end
 end
 for _,area in ipairs(Fields.list) do
  local timers=u.populationSpawns and u.populationSpawns[area]
  if timers then
   for _,role in ipairs(P.order) do
    local timer=timers[role]
    if timer and clock>=timer.nextAt then
     timer.sequence=timer.sequence+1;timer.nextAt=clock+delay(area,role,timer.sequence)
     local def=P.templates[role]
     -- a role with a world-wide budget (traders) also stops at that
     if (counts[area..'/'..role] or 0)<P.target(area,role,u) and (not def.budget or P.total(u,role)<def.budget()) then
      local spawned,reason=P.spawn(game,area,role,false);timer.status=spawned and nil or reason
      if spawned then counts[area..'/'..role]=(counts[area..'/'..role] or 0)+1 end
     end
    end
   end
  end
 end
end
return P
