--[[
	Squads and battlegroups: NPCs that work as a group.

	A squad is a saved record of ships that move and fight together. Its
	leader chooses the work and the members follow: they go wherever the
	leader goes, dock where it docks and hold where it holds. When the
	leader dies the highest-ranked member takes over. A squad that has lost
	half its ships, or is badly hurt, goes home to regroup: it repairs there
	while new recruits join it.

	A battlegroup is a set of squads plus a flagship (a large hull) in one
	planet system. The flagship patrols the planet on its own; the squads
	sweep the planet and its moons on their own. When the flagship comes
	under attack, the group calls the nearest free squads to it. A squad
	losing a fight calls one other squad for backup the same way.

	  u.squads = { nextId, squads = { [id] = squad }, groups = { [id] = group } }
	  squad = { id, kind, group, faction, size, leader, members = {ids},
	            goal = 'patrol' | 'respond' | 'regroup', respond = {node, untilT},
	            beat (sweep position), regroups }
	  group = { id, kind, faction, system, flagship, flagshipDue, sizes = {n...},
	            callUntil }
	  record: r.squad = squad id, r.battlegroup = group id, r.flagship = true

	Everything here is generic: a kind's profile (Squads.profiles) says how
	big its squads are, what its flagship flies and where it sweeps. Police
	are the first kind; pirates and mining crews only need a profile.
]]
local L=require('src.locations')
local Fields=require('src.fields')
local T=require('src.tuning')
local Tasks=require('src.tasks')
local G=require('src.travelgraph')
local data=require('src.data')
local Trace=require('src.alife_trace')
local S={profiles={}}

local function alive(r) return r and r.state~='dead' and r.state~='escaped' end
local function hash(s,salt)
 local n=salt or 17
 for i=1,#s do n=(n*31+s:byte(i))%2147483647 end
 for _=1,3 do n=(n*48271)%2147483647 end
 return n
end

function S.state(u)
 u.squads=u.squads or {nextId=0,squads={},groups={}}
 return u.squads
end
function S.get(u,id) return id and S.state(u).squads[id] end
function S.group(u,id) return id and S.state(u).groups[id] end
function S.of(u,r) return r and S.get(u,r.squad) end
function S.isLeader(u,r) local q=S.of(u,r);return q~=nil and q.leader==r.id end
function S.members(u,q)
 local out={}
 for _,id in ipairs(q.members) do local m=u.npcs[id];if alive(m) then out[#out+1]=m end end
 return out
end
local function armorFraction(r)
 local max=require('src.npc_repair').maximum(r)
 return max>0 and (r.ship.armor or 0)/max or 1
end
-- Do a and b fight on the same side as one group (squadmates, or a squad
-- and its battlegroup's flagship)?
function S.allied(u,a,b)
 if not a or not b or a==b or not u.squads then return false end
 if a.squad and a.squad==b.squad then return true end
 return a.battlegroup~=nil and a.battlegroup==b.battlegroup
end
-- How many of r's allies are in its area right now.
function S.alliesHere(u,r)
 if not r or not (r.squad or r.battlegroup) or not u.squads then return 0 end
 local n=0
 for _,o in pairs(u.npcs) do
  if o~=r and alive(o) and o.area==r.area and S.allied(u,r,o) then n=n+1 end
 end
 return n
end

-- Profiles ---------------------------------------------------------------------
-- profile = {
--   sizes = {min, max}          squad size, rolled once per squad slot
--   squads(area) -> n           how many squads a system keeps
--   flagshipHull(faction) -> hull id or nil
--   sweep(group, squad) -> list of nodes the squad leader works through
--   authorize(r, group)         grants the ship needs to work the whole system
-- }
function S.profile(kind,def) S.profiles[kind]=def end

-- The planet a map belongs to (a moon's parent, or itself).
function S.system(area)
 local m=Fields.moons[area]
 return m and m.parent or area
end
-- The places in a system a squad may work: the planet and the moons its
-- faction holds (or nobody holds). Dark grids are never on a police beat.
function S.systemAreas(system,faction)
 local Access=require('src.npc_access')
 local areas={system}
 for _,moon in ipairs(Fields.moonsOf(system)) do
  local m=Fields.moons[moon]
  if Fields[moon] and not m.dark and not require('src.dark').isDarkArea(moon) then
   local owner=Access.owner(moon)
   if owner==nil or owner==faction then areas[#areas+1]=moon end
  end
 end
 return areas
end
-- A node to visit in an area: a patrol station, else any station, else a
-- buoy, else its holding point. (Several so squads don't stack up.)
local function areaNodes(area)
 local f=Fields[area];local out={}
 for _,id in ipairs(L.stations(area,'patrol')) do out[#out+1]=id end
 if #out==0 then for _,id in ipairs(L.stations(area)) do out[#out+1]=id end end
 for _,id in ipairs(f.buoyIds or {}) do out[#out+1]=id end
 if #out==0 and f.holdingId then out[1]=f.holdingId end
 return out
end

S.profile('police',{
 sizes={1,4},
 squads=function(area) local f=Fields[area];return math.max(2,f.alifeSecurity and f.alifeSecurity.patrol or 2) end,
 -- the heaviest hull in the faction's own service fleet
 flagshipHull=function(faction)
  local fleets=require('src.npc_templates').patrol.purchase.fleets or {}
  local best,armor
  for _,id in ipairs(fleets[faction or ''] or {}) do
   local h=data.hulls[id]
   if h and (not armor or (h.armor or 0)>armor) then best,armor=id,h.armor or 0 end
  end
  return best
 end,
 -- planet node, moon node, planet node, next moon node ... each squad
 -- starts on a different moon so they spread round the system
 sweep=function(group,q)
  local areas=S.systemAreas(group.system,group.faction)
  local planet=areaNodes(group.system)
  local beat={}
  local n=tonumber((q.id or ''):match('%d+$')) or 0
  if #areas==1 then
   for i=1,#planet do beat[#beat+1]=planet[(i+n-1)%#planet+1] end
   return beat
  end
  for i=2,#areas do
   local moon=areaNodes(areas[(i+n-2)%(#areas-1)+2])
   if #planet>0 then beat[#beat+1]=planet[(i+n)%#planet+1] end
   if #moon>0 then beat[#beat+1]=moon[(n%#moon)+1] end
  end
  return beat
 end,
 authorize=function(r,group)
  r.authorizations=r.authorizations or {}
  for _,area in ipairs(S.systemAreas(group.system,group.faction)) do
   if not require('src.npc_access').authorized(r,'police',group.faction,area) then
    r.authorizations[#r.authorizations+1]={kind='police',issuer=group.faction,jurisdiction=area}
   end
  end
 end,
})

-- Groups -----------------------------------------------------------------------
function S.ensureGroup(u,kind,system,faction)
 local state=S.state(u)
 local id='bg/'..kind..'/'..system
 local g=state.groups[id]
 if g then return g end
 local profile=S.profiles[kind]
 g={id=id,kind=kind,system=system,faction=faction,sizes={},squads={}}
 for i=1,profile.squads(system) do
  local lo,hi=profile.sizes[1],profile.sizes[2]
  g.sizes[i]=lo+hash(id..'/'..i)%(hi-lo+1)
 end
 state.groups[id]=g
 return g
end
-- How many ships a group wants: its flagship plus every squad slot.
function S.desired(u,kind,system,faction)
 if not faction then return 0 end
 local g=S.ensureGroup(u,kind,system,faction)
 local n=S.profiles[kind].flagshipHull(faction) and 1 or 0
 for _,size in ipairs(g.sizes) do n=n+size end
 return n
end
local function newSquad(u,g,slot)
 local state=S.state(u)
 state.nextId=state.nextId+1
 local q={id='squad/'..state.nextId,kind=g.kind,group=g.id,faction=g.faction,slot=slot,
  size=g.sizes[slot] or g.sizes[#g.sizes] or 2,members={},goal='patrol',beat=0,regroups=0}
 state.squads[q.id]=q
 g.squads[#g.squads+1]=q.id
 return q
end
-- Give a freshly built ship the flagship's hull.
local function refit(u,r,hull,area)
 local Supply=require('src.npc_ship_supply')
 -- a faction with a military yard needs a finished one on its lot
 local owner=require('src.npc_access').owner(area)
 if require('src.dealers').serviceYard(owner) then
  local ship=Supply.fromYard(u,owner,{hulls={hull}})
  if not ship then return false end
  r.ship=ship
  return true
 end
 local policy={};for k,v in pairs(require('src.npc_templates').patrol.purchase) do policy[k]=v end
 policy.hulls={hull};policy.budget=math.huge;policy.fleets=nil
 local ship=Supply.generated(u,policy,nil,area)
 if not ship then return false end
 r.ship=ship
 return true
end
-- The squad's members fly at the pace of its slowest ship.
local function pace(u,q)
 local slow
 for _,m in ipairs(S.members(u,q)) do
  m.ownSpeed=m.ownSpeed or m.speed
  if not slow or m.ownSpeed<slow then slow=m.ownSpeed end
 end
 local leader=u.npcs[q.leader]
 for _,m in ipairs(S.members(u,q)) do
  m.speed=slow or m.speed
  -- one lane for the whole squad, so they fly it side by side
  if leader and m~=leader and leader.spread then m.spread=leader.spread+((#m.id%3)-1)*120 end
 end
end
function S.join(u,q,r)
 for _,id in ipairs(q.members) do if id==r.id then return end end
 q.members[#q.members+1]=r.id
 r.squad=q.id;r.battlegroup=q.group
 if not q.leader or not alive(u.npcs[q.leader]) then q.leader=r.id end
 pace(u,q)
end
function S.leave(u,r)
 local q=S.of(u,r)
 if q then
  for i,id in ipairs(q.members) do if id==r.id then table.remove(q.members,i);break end end
  if q.leader==r.id then q.leader=nil end
 end
 r.squad=nil
end

-- Put a ship into its system's battlegroup: as the flagship if there is
-- none (fresh ships only: an existing one isn't rebuilt), else into the
-- squad that most needs it, else a new squad.
function S.enlist(game,r,fresh)
 local u=game.universe or game
 local kind=r.populationGroup=='patrol' and 'police' or r.squadKind
 local profile=kind and S.profiles[kind]
 if not profile or not alive(r) then return end
 local system=S.system(r.home or r.area)
 local faction=require('src.npc_access').owner(system)
 if not faction then return end
 local g=S.ensureGroup(u,kind,system,faction)
 r.battlegroup=g.id
 profile.authorize(r,g)
 local clock=u.clock or 0
 local hull=profile.flagshipHull(faction)
 if fresh and hull and not alive(u.npcs[g.flagship or '']) and clock>=(g.flagshipDue or 0) then
  if refit(u,r,hull,system) then
   g.flagship=r.id;r.flagship=true;r.label=(r.label or 'Police')..' Flagship'
   Trace.note(r,clock,'squad','took command of '..g.id..' as flagship ('..hull..')')
   return
  end
 end
 -- the slot furthest below strength, then any slot with no squad at all
 local best,gap
 local used={}
 for _,id in ipairs(g.squads) do
  local q=S.get(u,id)
  if q then
   used[q.slot or 0]=true
   local missing=q.size-#S.members(u,q)
   if missing>0 and (not gap or missing>gap) then best,gap=q,missing end
  end
 end
 if not best then
  for slot=1,#g.sizes do if not used[slot] then best=newSquad(u,g,slot);break end end
 end
 if not best then
  -- every squad is full: the smallest takes the extra ship
  for _,id in ipairs(g.squads) do
   local q=S.get(u,id)
   if q and (not best or #q.members<#best.members) then best=q end
  end
 end
 best=best or newSquad(u,g,1)
 S.join(u,best,r)
 Trace.note(r,clock,'squad','joined '..best.id..(best.leader==r.id and ' as leader' or ''))
 return best
end

-- Tasks ------------------------------------------------------------------------
-- These are never on the board: the squad hands them out.
local function route(node,target,clock)
 if L.canonical(node)==L.canonical(target) then return {node,node} end
 return G.live(node,target,clock)
end
local function squadTask(kind,docking)
 return {
  docks=function(r,id) return r.task.dock and L.canonical(id)==L.canonical(r.task.target) end,
  stay=function(r) return r.task.duration or T.patrolInspect end,
  eligible=function() return false end,
  plan=function(t,node,clock) return route(node,t.target,clock) end,
  complete=function(u,r,t,node) return L.canonical(node)==L.canonical(t.target) end,
 }
end
Tasks.register('squad_sweep',squadTask('squad_sweep'))
Tasks.register('squad_follow',squadTask('squad_follow'))
Tasks.register('squad_respond',squadTask('squad_respond'))
Tasks.register('squad_regroup',squadTask('squad_regroup'))

local function give(u,r,kind,target,clock,dock,duration,phase)
 u.squads.taskSerial=(u.squads.taskSerial or 0)+1
 r.task={id='squad-task/'..u.squads.taskSerial,kind=kind,target=target,source=r.node,
  dock=dock and L.get(target).kind=='station' or false,duration=duration,phase=phase,assigned=clock}
 r.taskWorker=true;r.taskStatus=phase
 return r.task
end
-- A leader's next stop on its beat. Docks now and then (or when it needs
-- repair or supplies) like any patrol.
local function nextSweep(u,r,q,g,node,clock)
 local profile=S.profiles[q.kind]
 local beat=profile.sweep(g,q)
 if #beat==0 then return end
 local Repairs=require('src.npc_repair');local Supplies=require('src.supplies')
 for _=1,#beat do
  q.beat=(q.beat or 0)%#beat+1
  local target=beat[q.beat]
  if L.canonical(target)~=L.canonical(node) and route(node,target,clock) then
   local station=L.get(target).kind=='station'
   local dock=false
   if station then
    q.stationVisits=(q.stationVisits or 0)+1
    dock=q.stationVisits%T.patrolDockEvery==0 or (Repairs.needs(r) and Repairs.supports(target))
     or (Supplies.needs(r) and Supplies.supports(target))
   end
   local t=give(u,r,'squad_sweep',target,clock,dock,dock and Repairs.stay(r,target,T.patrolDockStay) or T.squadSweepHold,
    'sweeping '..L.get(target).area)
   return t
  end
 end
end
local function planFor(u,r,node,clock)
 local t=r.task
 local path=route(node,t.target,clock)
 if not path then Tasks.release(u,r,'no route',clock);return {wait=5} end
 return {route=path,wait=t.duration,dock=t.dock}
end
-- What the leader works on: the squad's goal first, then the beat.
local function leaderPlan(u,r,q,node,clock)
 local g=S.group(u,q.group)
 if q.goal=='respond' and q.respond then
  if clock<q.respond.untilT then
   give(u,r,'squad_respond',q.respond.node,clock,false,math.min(T.squadRespondHold,q.respond.untilT-clock),'answering a call to '..L.get(q.respond.node).area)
   return planFor(u,r,node,clock)
  end
  q.goal='patrol';q.respond=nil
 end
 if q.goal=='regroup' then
  local home=require('src.npc_home').get(r,u)
  if home and L.get(home).kind=='station' then
   if L.canonical(node)==L.canonical(home) and (q.regroupAt or 0)>0 and clock>=q.regroupAt then
    -- back to strength, or waited long enough: back on the beat
    if #S.members(u,q)>=math.ceil(q.size/2) or q.regroups>=T.squadRegroupTries then q.goal='patrol';q.regroups=0
    else q.regroups=q.regroups+1;q.regroupAt=clock+T.squadRegroupStay end
   end
   if q.goal=='regroup' then
    q.regroupAt=q.regroupAt and q.regroupAt>clock and q.regroupAt or clock+T.squadRegroupStay
    give(u,r,'squad_regroup',home,clock,true,T.squadRegroupStay,'regrouping at '..home)
    return planFor(u,r,node,clock)
   end
  else q.goal='patrol' end
 end
 if not g then return end
 if nextSweep(u,r,q,g,node,clock) then return planFor(u,r,node,clock) end
end
-- Members: go where the leader is going, do what it does there.
local function memberPlan(u,r,q,node,clock)
 local leader=u.npcs[q.leader]
 if not alive(leader) then return {wait=2} end
 local target,dock,stay
 if leader.state=='travel' or leader.state=='transit' then
  target=leader.route and leader.route[#leader.route]
  dock=leader.task and leader.task.dock
  stay=leader.task and leader.task.duration or T.patrolInspect
 else
  target=leader.node or (leader.route and leader.route[leader.index])
  dock=leader.state=='docked'
  stay=math.max(2,require('src.npc').readyAt(leader)-clock)
 end
 if not target then return {wait=2} end
 if L.canonical(target)==L.canonical(node) then
  -- already with the leader: wait for it to move
  if dock and r.state~='docked' and L.get(node).kind=='station' then
   give(u,r,'squad_follow',target,clock,true,stay,'with squad leader')
   return {route={node,node},wait=stay,dock=true}
  end
  r.taskStatus='holding with squad leader'
  return {wait=math.min(5,stay)}
 end
 give(u,r,'squad_follow',target,clock,dock,stay,'following squad leader')
 return planFor(u,r,node,clock)
end
-- The NPC controller asks this before the task board. A plan, or nil to
-- use the board as usual (flagships and loners).
function S.plan(c)
 local u,r=c.u,c.r
 if not r.squad or not u.squads then return end
 local q=S.of(u,r)
 if not q then r.squad=nil;return end
 local node=L.canonical(c.node)
 if q.leader==r.id then return leaderPlan(u,r,q,node,c.clock) end
 return memberPlan(u,r,q,node,c.clock)
end

-- Calls for help -------------------------------------------------------------
-- Send up to `count` free squads of group g to `node`. Squads already in
-- the node's area answer first.
function S.call(game,g,node,clock,reason,count,except)
 local u=game.universe
 local area=L.get(node).area
 local free={}
 for _,id in ipairs(g.squads) do
  local q=S.get(u,id);local leader=q and u.npcs[q.leader]
  if q and q~=except and q.goal=='patrol' and alive(leader) and #S.members(u,q)>0 then
   free[#free+1]={q=q,here=leader.area==area and 0 or 1}
  end
 end
 table.sort(free,function(a,b) return a.here<b.here or a.here==b.here and a.q.id<b.q.id end)
 local sent=0
 for i=1,math.min(count or T.squadRespondCount,#free) do
  local q=free[i].q
  q.goal='respond';q.respond={node=node,untilT=clock+T.squadRespondTime,reason=reason}
  sent=sent+1
  for _,m in ipairs(S.members(u,q)) do
   Trace.note(m,clock,'squad','called to '..node..': '..reason)
   -- drop the current leg: decide again now (a docked ship leaves when
   -- its live counterpart is let go; a moving one turns round)
   if m.task and m.task.kind:match('^squad_') then Tasks.release(u,m,'called away',clock) end
   if m.state=='idle' or m.state=='docked' then m.untilTime=math.min(m.untilTime or clock,clock);m.nextDecisionAt=nil
   elseif m.state=='travel' and m.id==q.leader then
    if require('src.npc').travel(game,m,node,clock) then
     give(u,m,'squad_respond',node,clock,false,T.squadRespondHold,'answering a call to '..area)
    end
   end
  end
 end
 return sent
end
local function underAttack(game,r)
 if r.encounter then return true end
 local e=game.alifeOnline and game.alifeOnline[r.id]
 return e and e.aggressor and not e.aggressor.dead and e.lastHitTime and game.time-e.lastHitTime<T.squadHitMemory or false
end
local function whereIs(r) return r.node or (r.route and r.route[r.index]) end

-- Upkeep ----------------------------------------------------------------------
-- Runs with the A-Life tick: enlists unassigned ships (older saves too),
-- drops the dead, re-elects leaders, starts regroups and answers calls.
function S.update(game,clock)
 local u=game.universe
 if clock<(u.squadsNext or 0) then return end
 u.squadsNext=clock+T.squadTick
 local state=S.state(u)
 -- ships with no squad yet (and ones saved before squads existed)
 local ids={}
 for id,r in pairs(u.npcs) do
  if alive(r) and r.populationGroup=='patrol' and not r.squad and not r.flagship then ids[#ids+1]=id end
 end
 table.sort(ids)
 for _,id in ipairs(ids) do S.enlist(game,u.npcs[id],false) end
 local gids={};for id in pairs(state.groups) do gids[#gids+1]=id end;table.sort(gids)
 for _,gid in ipairs(gids) do
  local g=state.groups[gid]
  local flag=u.npcs[g.flagship or '']
  if g.flagship and not alive(flag) then
   g.flagship=nil;g.flagshipDue=clock+T.flagshipRebuild
  end
  -- the flagship calls when it is attacked
  if alive(flag) and underAttack(game,flag) and clock>=(g.callUntil or 0) then
   local node=whereIs(flag)
   if node and S.call(game,g,node,clock,'flagship under attack')>0 then
    g.callUntil=clock+T.squadRespondTime*.5
    Trace.note(flag,clock,'squad','called for help at '..node)
   end
  end
  local keep={}
  for _,qid in ipairs(g.squads) do
   local q=state.squads[qid]
   if q then
    local live=S.members(u,q)
    local list={};for _,m in ipairs(live) do list[#list+1]=m.id end
    q.members=list
    if #live==0 then state.squads[qid]=nil
    else
     keep[#keep+1]=qid
     -- a new leader: the most experienced member left
     if not alive(u.npcs[q.leader or '']) or u.npcs[q.leader].squad~=q.id then
      table.sort(live,function(a,b) return (a.rankXp or 0)>(b.rankXp or 0) or (a.rankXp or 0)==(b.rankXp or 0) and a.id<b.id end)
      q.leader=live[1].id
      Trace.note(live[1],clock,'squad','took over '..q.id)
      pace(u,q)
     end
     local leader=u.npcs[q.leader]
     local hurt=armorFraction(leader)<T.squadRegroupArmor
     if q.goal~='regroup' and (#live<math.ceil(q.size/2) or hurt) and not leader.encounter then
      q.goal='regroup';q.respond=nil;q.regroupAt=nil
      Trace.note(leader,clock,'squad','regrouping '..q.id..' ('..#live..'/'..q.size..(hurt and ', hurt' or '')..')')
     end
     -- a squad losing a fight asks for backup
     if q.goal=='patrol' or q.goal=='respond' then
      for _,m in ipairs(live) do
       if underAttack(game,m) and armorFraction(m)<.6 and clock>=(q.callUntil or 0) then
        local node=whereIs(m)
        if node and S.call(game,g,node,clock,q.id..' needs backup',1,q)>0 then q.callUntil=clock+T.squadRespondTime*.5 end
        break
       end
      end
     end
     if q.goal=='respond' and q.respond and clock>=q.respond.untilT then q.goal='patrol';q.respond=nil end
    end
   end
  end
  g.squads=keep
 end
end

-- Onscreen: a squad ship takes its leader's target, and anyone who shoots
-- an ally of its own group is fair game.
function S.sharedTarget(game,e,hostile)
 local u=game.universe;local r=e.alifeRecord or u.npcs[e.alifeId or '']
 local q=r and S.of(u,r)
 if not q then return end
 local online=game.alifeOnline or {}
 local leader=online[q.leader or '']
 if leader and leader~=e and leader.combatTarget and hostile(game,e,leader.combatTarget) then return leader.combatTarget end
end
function S.attackedAlly(game,e,o)
 local u=game.universe;local r=e.alifeRecord or u.npcs[e.alifeId or '']
 if not r or not (r.squad or r.battlegroup) or not u.squads then return false end
 local online=game.alifeOnline or {}
 for id,other in pairs(online) do
  if other~=e and other.aggressor==o and other.lastHitTime and game.time-other.lastHitTime<T.squadHitMemory
   and S.allied(u,r,u.npcs[id]) then return true end
 end
 return false
end
return S
