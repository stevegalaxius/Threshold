-- Patrol/raid tasks, scoped police authority, and shared combat policy.
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
local NPC=require('src.npc')
local Combat=require("src.combat")
local Access=require('src.npc_access')
local Aggression=require("src.aggression")
local S={}
local policeWanted
local function route(source,target,clock)
 if source==target then return {source,source} end
 local path=G.route(G.build(L.get(source).area),source,target,clock)
 if not path then return end
 local result={source}
 for _,leg in ipairs(path.legs) do result[#result+1]=leg.edge.to end
 if #result==1 then result[2]=source end
 return result
end
-- A raid leg runs from a buoy to one of the two buoys nearest it round the
-- planet, judged from where they are now (buoys orbit at different speeds).
local function nearestBuoys(area,from,clock)
 local field=Fields[area];local list={}
 local x,y=L.position(from,clock or 0);local a=math.atan2(y,x)
 for _,id in ipairs(field.buoyIds) do
  if id~=from then
   local xx,yy=L.position(id,clock or 0)
   local d=math.abs((math.atan2(yy,xx)-a+math.pi)%(2*math.pi)-math.pi)
   list[#list+1]={id,d}
  end
 end
 table.sort(list,function(p,q) return p[2]==q[2] and p[1]<q[1] or p[2]<q[2] end)
 local result={}
 for i=1,math.min(2,#list) do result[i]=list[i][1] end
 return result
end
S.nearestBuoys=nearestBuoys
local function raidLeg(area,from,to,clock)
 local field=Fields[area];local nodes={}
 for _,id in ipairs(field.buoyIds) do nodes[id]=true end
 if #field.buoyIds<=1 then return from==to end
 if not nodes[from] or not nodes[to] or from==to then return false end
 for _,id in ipairs(nearestBuoys(area,from,clock)) do if id==to then return true end end
 return false
end
local Repairs=require('src.npc_repair')
local Supplies=require('src.supplies')
local repairStation=Repairs.supports
local armorMax=Repairs.maximum
local needsRepair=Repairs.needs
local function dockStay(r,node) return Repairs.stay(r,node,T.patrolDockStay) end
for _,kind in ipairs({'patrol','raid'}) do
 Tasks.register(kind,{
  requires={capabilities={'armed'}},
  docks=function(r,id) return kind=='patrol' and r.task.dock and L.canonical(id)==L.canonical(r.task.target) end,
  stay=function(r) return r.task.duration or T.patrolInspect end,
  localPickup=true,
  eligible=function(u,r,o,node,clock)
   -- A multi-buoy raid should travel, rather than reserve a minute of waiting
   -- at its current buoy. Driver-only regions still have a holding duty.
   if kind=='raid' and not raidLeg(r.area,o.source,o.target,clock) then return false end
   return (not o.jurisdiction or o.jurisdiction==r.area) and L.canonical(node)==L.canonical(o.source)
  end,
  feasible=function(u,r,o,node,clock) return route(node,o.target,clock)~=nil end,
  score=function(u,r,o,node,clock)
   return clock-(o.readyAt or 0)-(r.lastDutyTarget==o.target and 10000 or 0)
    +(kind=='patrol' and ((needsRepair(r) and repairStation(o.target)) or (Supplies.needs(r) and Supplies.supports(o.target))) and 1000000 or 0)
  end,
  prepare=function(u,r,t)
   t.phase=kind=='patrol' and 'patrolling' or 'raiding'
   if kind=='patrol' and L.get(t.target).kind=='station' then
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
   if kind=='raid' and (from~=to or #nodes==1) or kind=='patrol' and from~=to then
    specs[#specs+1]={kind=kind,source=from,target=to,cooldown=0,
     duration=kind=='raid' and T.pirateLinger or T.patrolInspect,
     issuer=kind=='patrol' and Access.owner(area) or nil,jurisdiction=area,
     requires=kind=='patrol' and {authorization='police'} or nil}
   end
  end end
  Tasks.sync(u,scope,specs)
  state.navigationDuties[scope]=signature
 end
 return nodes
end
function S.ensureRaids(u,area)
 local nodes=raidNodes(Fields[area])
 if nodes then return ensureOffers(u,area,'raid',nodes) end
end
function S.ensurePatrols(u,area)
 if not Access.owner(area) then return {} end
 return ensureOffers(u,area,'patrol',S.patrolNodes(area))
end

local function create(game,area,role,node,clock,start)
 local u=game.universe
 local profile=require('src.npc_profile').forJob(require('src.npc_templates')[role].job)
 local def=data.npcProfiles[profile];local hull=data.hulls[def.hull]
 local loadout=copy(def.loadout or hull.loadout)
 local stats=Stats.compute(hull,loadout)
 u.nextNpcId=u.nextNpcId+1
 local r={id='npc/'..u.nextNpcId,home=area,area=area,aiProfile=profile,
  spread=0,route={node,node},index=1,node=node,state='idle',untilTime=clock,
  ship={hull=def.hull,loadout=loadout,cargo=copy(def.cargo or {}),armor=stats.armor}}
 if game.arrivalShip then r.ship=copy(game.arrivalShip) end
 r.speed=NPC.cruise(r.ship)
 require('src.npc_templates').apply(r,role,area)
 require('src.personality').ensure(r)
 Homes.choose(u,r)
 u.npcs[r.id]=r
 -- police serve in their system's battlegroup (src/squads.lua)
 if role=='patrol' then require('src.squads').enlist(game,r,true) end
 NPC.advance(r,clock,u,game)
 return r
end
-- Role-specific work stays here; shared arrival scheduling lives in population.
local function ensureDuty(u,area,role,node,nodes,clock)
 local kind=role=='pirate' and 'raid' or 'patrol'
 local available=false
 for _,offer in pairs(Tasks.state(u).offers) do
  if offer.kind==kind and offer.source==node and offer.state=='available' and (offer.readyAt or 0)<=clock
   and (role~='pirate' or raidLeg(area,node,offer.target,clock)) then available=true;break end
 end
 if not available then
  local target=node
  for _,id in ipairs(nodes) do
   if id~=node and (role~='pirate' or raidLeg(area,node,id,clock)) then target=id;break end
  end
  Tasks.post(u,{kind=kind,source=node,target=target,cooldown=0,
   duration=role=='pirate' and T.pirateLinger or T.patrolInspect,
   issuer=kind=='patrol' and Access.owner(area) or nil,jurisdiction=area,
   requires=kind=='patrol' and {authorization='police'} or nil})
 end
end
-- A raider bought at a dark base: homed there, then sent out to hunt.
function S.launchPirate(game,area,base,clock)
 local u=game.universe
 local r=create(game,area,'pirate',base,clock,require('src.alife').start)
 Homes.assign(r,base)
 local hunt=S.huntingGround(u,base,clock)
 if hunt then require('src.piracy').deploy(game,r,base,hunt) end
 return r
end
function S.spawnPirate(game,area,nearPlayer) return Population.spawn(game,area,'pirate',nearPlayer) end
function S.pirateCount(u,area) return Population.count(u,area,'pirate') end
function S.updateSpawns(game,clock) return Population.update(game,clock) end

-- Police per system: a flagship plus every squad slot of its battlegroup.
policeWanted=function(u,area)
 local owner=Access.owner(area)
 if not owner or not Fields[area].alifeSecurity then return 0 end
 local n=require('src.squads').desired(u,'police',area,owner)
 -- a leaderless faction fields fewer police for good (src/worldstate.lua);
 -- the ships it has serve on, and losses aren't replaced past the new number
 if u.worldstate then n=math.floor(n*require('src.worldstate').mul(u,'patrols','faction:'..owner)+.5) end
 return n
end
S.policeWanted=policeWanted
function S.seed(game,start)
 local u=game.universe
 local state=Tasks.state(u);state.securityAreas=state.securityAreas or {}
 for _,area in ipairs(Fields.list) do
  local f=Fields[area]
  if f.alifeSecurity then S.ensurePatrols(u,area);S.ensureRaids(u,area) end
  if f.alifeSecurity and not state.securityAreas[area] then
   state.securityAreas[area]=true
   for _,role in ipairs({'patrol','pirate'}) do
    local count=role=='patrol' and policeWanted(u,area) or f.alifeSecurity[role]
    for i=1,count do
     local node=f.buoyIds[(i-1)%#f.buoyIds+1]
     -- the same choice of hull and fit an arrival makes (src/npc_ship_supply.lua)
     local Supply=require('src.npc_ship_supply')
     local ship,policy=Supply.seed(u,area,role)
     game.arrivalShip=ship
     local r=create(game,area,role,node,u.clock,start)
     game.arrivalShip=nil
     Supply.settle(r,policy)
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
 return r and r.task and r.task.kind=='patrol' and r.task.dock and L.canonical(r.task.target)==L.canonical(node)
end
-- Choose a station-local holding point outside its hull and every runway.
-- lane (optional): which side a ship passing through takes, 1 the outer
-- side (away from the planet), -1 the inner. Traffic going opposite ways
-- round the track gets opposite sides, so it never meets head on at one point.
local LANE_OUTER={0,math.pi/3,-math.pi/3,math.pi*2/3,-math.pi*2/3,math.pi}
local LANE_INNER={math.pi,math.pi*2/3,-math.pi*2/3,math.pi/3,-math.pi/3,0}
function S.inspectionPoint(game,station,e,lane)
 if station.city then
  local x,y=L.inspectionPosition(station.locationId,game.universe.clock)
  local vx,vy=L.inspectionVelocity(station.locationId,game.universe.clock)
  return x,y,vx,vy
 end
 local cached=e.patrolInspection
 if not cached or cached.station~=station or cached.lane~=lane then
  local x,y=station.body:getPosition();local angle=math.atan2(y,x)-station.body:getAngle()
  local radius=station.radius+T.patrolStandOff+e.halfLength
  local chosen
  for _,offset in ipairs(lane==-1 and LANE_INNER or LANE_OUTER) do
   local a=angle+offset;local lx,ly=math.cos(a)*radius,math.sin(a)*radius
   local clear=true
   for _,d in ipairs(station.docks or {station.dock}) do
    local c,s=math.cos(d.a or 0),math.sin(d.a or 0)
    local along,across=lx*c+ly*s-(d.xc or 0),-lx*s+ly*c-(d.yc or 0)
    if math.abs(across)<(d.capture or d.hw)+e.halfLength+T.patrolStandOff
     and (along>d.x2-e.halfLength or d.both and along<d.x1+e.halfLength) then clear=false;break end
   end
   if clear then chosen={station=station,lane=lane,x=lx,y=ly};break end
  end
  cached=chosen or {station=station,lane=lane,x=math.cos(angle+math.pi/2)*radius,y=math.sin(angle+math.pi/2)*radius}
  e.patrolInspection=cached
 end
 local x,y=station.body:getWorldPoint(cached.x,cached.y)
 local vx,vy=station.body:getLinearVelocityFromWorldPoint(x,y)
 return x,y,vx,vy
end
-- Work execution hooks; all selection, commitment and movement use NPC.
local Piracy=require('src.piracy')
Tasks.definitions.raid.nextAction=Piracy.nextAction
Tasks.definitions.raid.pickedUp=require('src.scavenge').pickedUp
Tasks.definitions.raid.before=function(c)
 Piracy.before(c)
 if not c.r.task or c.r.task.kind~='raid' then return end
 local r=c.r
 if r.state=='idle' and r.task.source==r.task.target and #Fields[r.area].buoyIds>1 then
  r.untilTime=math.min(r.untilTime or c.clock,c.clock)
 end
end
-- Combat policy comes from current work and scoped authority, never identity.
function S.prey(o) return o.alifeRecord and Access.civilian(o.alifeRecord) or false end
-- A fresh interception requires faction hostility. A raid report can bring
-- help to its victim while the attack is still in progress.
function S.intercepts(u,patrol,target,area)
 if not target or patrol==target or not Access.defending(patrol,area) then return false end
 local Rep=require('src.reputation')
 local grant=Access.policeGrant(patrol,area)
 local owner=Rep.ofArea(area) or grant and grant.issuer
 local faction=Rep.crewFaction(target)
 if faction and (faction==owner or Rep.stance(owner,faction,u)=='friendly') then return false end
 return Rep.hostileToCrew(u,owner,target)
end

function S.reportedRaid(u,attacker,victim,area,clock)
 local entry=attacker and victim and Aggression.find(u,attacker.id,victim.id,area,clock)
 return entry and entry.reportedAt~=nil or false
end

function S.reportRaid(game,attacker,victim,entry)
 if not entry or entry.dispatched or entry.lastAt<(entry.nextDispatchAt or 0) then return end
 if not attacker or not victim or not Access.civilian(victim)
  or not (Access.raiding(attacker) or attacker.wildcat or attacker.piracy) then return end
 local area=victim.area
 if not area or attacker.area~=area or entry.area~=area then return end
 local clock=entry.lastAt
 entry.reportedAt=entry.reportedAt or clock
 entry.nextDispatchAt=clock+T.offlineCombatTick
 entry.dispatched=require('src.squads').civilianDistress(game,victim,clock,entry.node)
end

function S.hostile(game,e,o)
 if not o or o==e or o.kind~='ship' or o.dead or o.removed or o.dockState or o.driverProtected or o.unpiloted or o.podHidden
  or Combat.allied(game.universe,e,o) then return false end
 if o==e.aggressor then return true end
 local r=e.alifeRecord
 local actor=Combat.controller(o)
 local other=actor.alifeRecord
 -- whoever shoots a squadmate or the flagship answers to the whole group
 if r and (r.squad or r.battlegroup) and require('src.squads').attackedAlly(game,e,o) then return true end
 local grant=Access.policeGrant(r,game.fieldId)
 if grant and actor.isPlayer then
  local Rep=require('src.reputation')
  local u=game.universe
  return Rep.hostile(Rep.goodwill(u,r)+Rep.standing(u,grant.issuer)-Rep.heat(u,r.node))
 end
 if Access.defending(r,game.fieldId) then
  -- Defenders use the same relationship that crews plan around.
  if S.intercepts(game.universe,r,other,game.fieldId) then return true end
  local victim=o.aiFightTarget or actor.aiFightTarget
  if not victim or victim.dead or victim.removed or victim.dockState or victim.fleeing
   or actor.fleeing then return false end
  if S.reportedRaid(game.universe,other,Combat.controller(victim).alifeRecord,game.fieldId,game.universe.clock) then return true end
  local lastAttack=o.aggressedAt or actor.aggressedAt
  return Combat.sceneEnemy(o) and lastAttack~=nil and game.time-lastAttack<30
 end
 if Access.raiding(r) then
  return not Access.raiding(other) and (actor.isPlayer or other~=nil)
   and not require('src.robbery').isSpared(game,e,o)
 end
 return false
end
function S.target(game,e)
 local record=game.universe.npcs[e.alifeId]
 if game.time<(e.securityThink or 0) then return S.hostile(game,e,e.combatTarget) and e.combatTarget or nil end
 e.securityThink=game.time+T.securityThink
 -- a squad ship shoots at what its leader shoots at
 local shared=require('src.squads').sharedTarget(game,e,S.hostile)
 if shared then
  e.combatTarget=shared;e.lock=shared
  if record then record.targetId=shared.alifeId or shared.isPlayer and 'player' or nil end
  return shared
 end
 local x,y=e.body:getPosition()
 local best,bestRank,bestDistance=nil,-1,T.securityRange^2
 for _,o in ipairs(game.entities) do
  if S.hostile(game,e,o) then
   local ox,oy=o.body:getPosition();local d=(ox-x)^2+(oy-y)^2
   local rank=o==e.aggressor and 3 or Access.raiding(record) and S.prey(o) and 2 or 1
   -- prey carrying what the raider's home station is short of comes first
   if rank==2 and o.alifeRecord and require('src.piracy').wants(game.universe,require('src.piracy').home(record),o.alifeRecord) then rank=2.5 end
   if d<T.securityRange^2 and (rank>bestRank or rank==bestRank and d<bestDistance) then best,bestRank,bestDistance=o,rank,d end
  end
 end
 -- Evaluate a new NPC opponent once per target scan, using the same odds
 -- and station support as offline combat. Retaliation is never filtered.
 if best and record and Access.raiding(record) and best~=e.aggressor and best~=e.combatTarget then
  local other=best.alifeId and game.universe.npcs[best.alifeId]
  if other then
   local E=require('src.encounters')
   record.ship.armor=e.armor;other.ship.armor=best.armor
   local _,guns=E.coveringStation(record,other,game.universe.clock)
   if E.odds(record,other,guns*T.offlineStationAccuracy)<require('src.personality').engageOdds(record) then best=nil end
  end
 end
 e.combatTarget=best;e.lock=best
 local r=game.universe.npcs[e.alifeId]
 if r then r.targetId=best and (best.alifeId or best.isPlayer and 'player') or nil end
 return best
end
function S.visit(game,e,stop,A)
 local r=game.universe.npcs[e.alifeId]
 if r.worldRecovery then return false end
 -- carrying loot home: dock at the base like any station visit
 if r.piracy and r.piracy.phase~='redeploy' then return false end
 -- Only the end of the route is a stop; everything before it is passed.
 if e.routeIndex<#e.route then return false end
 if r.state=='travel' then NPC.holdOnline(game,e,stop.locationId) end
 return true
end
-- Pirates are not a quota on the white map. Each dark station with a
-- shipyard keeps berths: as many raiders as its own fuel stock can send out
-- (T.pirateBerths). New pirates are bought, fitted and fuelled there, from
-- that region's lots and shelves (npc_ship_supply, Supplies.refill), and fly
-- out to the hunting grounds with the most prey for the fewest raiders. So a
-- base that fences a lot of fuel launches more; one starved of it stops.
local function fuelFor()
 local def=data.npcProfiles.raider
 local need=Supplies.targets({aiProfile=def.id,ship={hull=def.hull,loadout=def.loadout or data.hulls[def.hull].loadout}})
 return math.max(1,need[require('src.reactor_fuel').item()] or 1)
end
function S.berths(u,station)
 local place=L.byId[station]
 if not place or place.kind~='station' or not (place.uses and place.uses.pirateBase) then return 0 end
 if not L.stationServices(station).shipyard then return 0 end
 local fuel=require('src.stockpile').available(u,station,require('src.reactor_fuel').item())
 return math.min(T.pirateBerths.max,math.floor(fuel/(fuelFor()*T.pirateBerths.fuelReserves)))
end
function S.bases(area)
 local list={}
 for _,id in ipairs(L.stations(area,'pirateBase')) do list[#list+1]=id end
 table.sort(list)
 return list
end
-- Where a new raider hunts: a white region with raid duties it can reach,
-- scored by prey per raider already there, nearer first.
function S.huntingGround(u,from,clock)
 local prey,raiders={},{}
 for _,o in pairs(u.npcs or {}) do
  if o.state~='dead' and o.state~='escaped' and o.area then
   local job=require('src.npc_templates').job(o)
   if job=='raider' then raiders[o.area]=(raiders[o.area] or 0)+1
   elseif job=='hauler' or job=='miner' then
    -- a ship carrying what this base is short of counts extra
    local w=require('src.piracy').wants(u,from,o) and 1+T.raidShortageBias*4 or 1
    prey[o.area]=(prey[o.area] or 0)+w
   end
  end
 end
 local Dark=require('src.dark');local origin=L.get(from).area
 local best,score
 for _,area in ipairs(Fields.list) do
  local f=Fields[area]
  if f.alifeSecurity and raidNodes(f) and not Dark.isHaven(area) then
   local rally=L.rally(area,from,clock)
   if rally and G.itinerary(from,rally,clock,true) then
    local root=function(a) local m=Fields.moons[a];return m and m.parent or a end
    local d=Fields.orbits[root(origin)] and Fields.orbits[root(area)] and Fields.distance(root(origin),root(area),clock) or 0
    local value=((prey[area] or 0)+1)/((raiders[area] or 0)+1)/(1+d)
    if not score or value>score or value==score and area<best then best,score=area,value end
   end
  end
 end
 return best
end
for _,role in ipairs({'pirate','patrol'}) do
 Population.register(role,{
  target=function(f,area)
   if role=='pirate' then
    local u=Population.universe;if not u then return 0 end
    local n=0
    for _,id in ipairs(S.bases(area)) do n=n+S.berths(u,id) end
    return n
   end
   local u=Population.universe;if not u then return Access.owner(area) and f.alifeSecurity and f.alifeSecurity.patrol end
   return policeWanted(u,area)
  end,
  -- a raider belongs to the base that launched it, wherever it hunts
  where=role=='pirate' and function(r) local home=r.homeStation and L.byId[r.homeStation];return home and home.area or r.home end or nil,
  launches=role=='pirate' or nil,
  nodes=function(game,area)
   if role=='pirate' then
    -- the base with the most free berths launches next
    local best,free
    for _,id in ipairs(S.bases(area)) do
     local n=S.berths(game.universe,id)-#Homes.residents(game.universe,id)
     if n>0 and (not free or n>free) then best,free=id,n end
    end
    return best and {best} or {}
   end
   return Fields[area].buoyIds
  end,
  create=function(game,area,node,clock)
   if role=='pirate' then return S.launchPirate(game,area,node,clock) end
   local nodes=Fields[area].buoyIds
   ensureDuty(game.universe,area,role,node,nodes,clock)
   return create(game,area,role,node,clock,require('src.alife').start)
  end,
  -- fuel and ammunition come off the launching base's own shelves
  provision=role=='pirate' and function(game,r) return Supplies.refill(r,r.homeStation,game.universe) end or nil,
 })
end
-- squad tasks must be registered before a save's tasks are resolved
require('src.squads')
return S
