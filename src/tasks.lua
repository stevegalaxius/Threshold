-- Role-neutral task board. Definitions execute code; saves contain plain records.
local copy=require('src.persistence').copy
local Work=require('src.work_preferences')
local Access=require('src.npc_access')
local Locations=require('src.locations')
local Fields=require('src.fields')
-- transport offers whose pickup maps to no system still go on the board
local UNMAPPED='_unmapped'
local rejectedFreight=setmetatable({},{__mode="k"})
local function pickupSystem(node)
 local place=Locations.byId[node]
 local area=place and place.area
 local moon=area and Fields.moons[area]
 return moon and moon.parent or area
end
local Tasks={definitions={},feasibleTries=4}
function Tasks.register(kind,definition)
 assert(not Tasks.definitions[kind],'duplicate task kind')
 Tasks.definitions[kind]=definition
end
function Tasks.state(u)
 u.tasks=u.tasks or {offers={},nextId=0}
 return u.tasks
end
-- Derived from the authoritative board. Keep reserved offers indexed so a
-- release is visible immediately, and compact deleted entries during cleanup.
local searchIndexes=setmetatable({},{__mode='k'})
local function indexOffer(index,o,id)
 if o.kind=='transport' then
  local system=pickupSystem(o.source) or UNMAPPED
  local freight=index.freight
  if not freight[system] then freight[system]={} end
  freight[system][id]=o
  return
 end
 local kinds=index.kinds
 local def=Tasks.definitions[o.kind]
 if def and def.localPickup and o.source then
  local station=Locations.canonical(o.source)
  kinds=index.byStation[station]
  if not kinds then kinds={};index.byStation[station]=kinds end
 end
 local bucket=kinds[o.kind]
 if not bucket then bucket={};kinds[o.kind]=bucket end
 bucket[id]=o
end
local function buildSearchIndex(offers)
 local index={kinds={},freight={},byStation={}}
 for id,o in pairs(offers) do indexOffer(index,o,id) end
 searchIndexes[offers]=index
 return index
end
-- Index only live offers. Some callers delete a completed offer directly,
-- so consumers must check the authoritative table before using a result.
function Tasks.offersOfKind(u,kind)
 local offers=Tasks.state(u).offers
 local index=searchIndexes[offers] or buildSearchIndex(offers)
 return index.kinds[kind] or {},offers
end

function Tasks.post(u,offer)
 assert(Tasks.definitions[offer.kind],'unknown task kind')
 local state=Tasks.state(u)
 state.nextId=state.nextId+1
 local o=copy(offer);o.id='task/'..state.nextId;o.state='available'
 state.offers[o.id]=o
 local index=searchIndexes[state.offers]
 if index then indexOffer(index,o,o.id) end
 local Transport=package.loaded['src.transport'];if Transport then Transport.rescan() end
 return o
end
-- Reconcile generated world duties without replacing reservations or reposting
-- completed work. Custom offers outside this scope are left alone.
function Tasks.sync(u,scope,specs,legacy)
 local state=Tasks.state(u);local desired,existing={},{}
 local function key(o)return o.kind..'|'..o.source..'|'..o.target..'|'..(o.item or '') end
 for _,o in ipairs(specs) do desired[key(o)]=o end
 for id,o in pairs(state.offers) do
  if o.layoutScope==scope or (not o.layoutScope and legacy and legacy(o)) then
   local k=key(o);o.layoutScope=scope
   if desired[k] then existing[k]=true
   elseif o.state=='available' then state.offers[id]=nil end
  end
 end
 -- Preserve authoring order, which is also the stable task-ID tie breaker.
 for _,spec in ipairs(specs) do
  if not existing[key(spec)] then
   local offer=copy(spec);offer.layoutScope=scope;Tasks.post(u,offer);existing[key(spec)]=true
  end
 end
end

function Tasks.release(u,r,reason,clock)
 require('src.npc_actions').cancel({u=u,r=r,clock=clock},reason)
 local t=r.task or r.suspendedTask
 if not t then
  if r.agenda and (r.state=='dead' or r.state=='escaped') then require('src.npc_agenda').dropAll(u,r,reason,clock) end
  return
 end
 local o=Tasks.state(u).offers[t.id]
 for _,line in ipairs(t.manifest or {}) do
  local extra=Tasks.state(u).offers[line.id]
  if extra and extra.owner==r.id then extra.owner=nil;extra.state='available';extra.manifestRoot=nil;extra.loaded=nil;extra.readyAt=clock+(extra.cooldown or 120);if t.phase=='delivery' then Tasks.state(u).offers[line.id]=nil end end
 end
 if o and o.owner==r.id then
  o.owner=nil;o.manifestRoot=nil;o.loaded=nil;o.state='available';o.readyAt=clock+(o.cooldown or 120)
 end
 local def=Tasks.definitions[t.kind]
 if def and def.release then def.release(u,r,t,reason,clock) end
 r.lastTask={id=t.id,kind=t.kind,status=reason,clock=clock}
 r.task=nil;r.suspendedTask=nil;r.suspendedTaskStatus=nil
 -- the ship is gone: so is every job it held; otherwise the next one it
 -- carries becomes the active job
 local Agenda=require('src.npc_agenda')
 if r.state=='dead' or r.state=='escaped' then Agenda.dropAll(u,r,reason,clock)
 else Agenda.promote(u,r,r.node or r.station,clock) end
end
-- Saves may outlive a task implementation (or be opened on another branch).
-- Keep its phase, cargo and reservation intact until that implementation returns.
function Tasks.resolve(u,r)
 if r.state=='dead' or r.state=='escaped' then return false end
 local t=r.task or r.suspendedTask
 if not t then return true end
 if not Tasks.definitions[t.kind] then
  if r.task then
   r.suspendedTaskStatus=r.taskStatus;r.suspendedTask=r.task;r.task=nil
  end
  r.taskStatus='waiting for task support: '..tostring(t.kind)
  return false
 end
 if not r.task then
  local offer=Tasks.state(u).offers[t.id]
  if offer and offer.owner and offer.owner~=r.id then return false end
  r.task=t;r.suspendedTask=nil;r.taskStatus=r.suspendedTaskStatus;r.suspendedTaskStatus=nil
  if offer then offer.owner=r.id;offer.state='reserved' end
 end
 return true
end
function Tasks.clean(u,clock)
 for _,r in pairs(u.npcs or {}) do Tasks.resolve(u,r) end
 local offers=Tasks.state(u).offers
 for _,o in pairs(offers) do
  local r=o.owner=='player' and Tasks.state(u).player or o.owner and (u.npcs or {})[o.owner]
  if o.owner and (not r or r.state=='dead' or r.state=='escaped' or not require('src.npc_agenda').holds(r,o.manifestRoot or o.id)) then
   if o.loaded then offers[o.id]=nil
   else
    o.owner=nil;o.manifestRoot=nil;o.state='available';o.readyAt=clock+(o.cooldown or 120)
    if o.kind=='ship_delivery' and not o.playerDelivery then o.parking=nil end
   end
  end
 end
 if searchIndexes[offers] then buildSearchIndex(offers) end
end
-- Orders placed at the station the player is docked at are held for the
-- player for T.playerFirstLookSeconds before NPCs may reserve them.
function Tasks.npcMayClaim(u,o,clock)
 if (o.npcClaimAt or 0)>clock then return false end
 local here=u.playerDocked
 if o.order and here and o.source==here and clock<(o.placed or 0)+require('src.tuning').playerFirstLookSeconds then return false end
 return true
end
local function available(u,offers,id,o,clock)
 return offers[id]==o and o.state=='available' and (o.readyAt or 0)<=clock and Tasks.npcMayClaim(u,o,clock)
end

-- Freight is ranked once per board refresh, not once per ship. Each system
-- keeps its best few orders by a ship-independent need-and-value score; a
-- hauler reads its own system's list and the head of every other system's,
-- then scores those few for itself (src/transport.lua score). The cost of a
-- search no longer grows with the board, and every hauler still sees the
-- most pressing work anywhere.
local freightCaches=setmetatable({},{__mode='k'})
local function baseFreightScore(o,clock)
 return (o.order and 1000000 or 0)+(o.urgency or o.priority or 0)*10000+math.max(0,clock-(o.placed or clock))*100
  +(o.creditsPerUnit or 0)*(o.amount or 0)/(1+(o.routeAU or 0))
end
local function freightCache(u,offers,index,clock)
 local T=require('src.tuning')
 local cache=freightCaches[offers]
 if cache and cache.index==index and clock>=cache.at and clock-cache.at<T.freightCacheSeconds then return cache end
 cache={at=clock,index=index,lists={}}
 for system,bucket in pairs(index.freight) do
  local list={}
  for id,o in pairs(bucket) do
   if available(u,offers,id,o,clock) then list[#list+1]={id=id,o=o,score=baseFreightScore(o,clock)} end
  end
  table.sort(list,function(a,b) return a.score>b.score or a.score==b.score and a.id<b.id end)
  for i=#list,T.freightCacheLocal+1,-1 do list[i]=nil end
  cache.lists[system]=list
 end
 freightCaches[offers]=cache
 return cache
end
local function freightShortlist(u,r,station,clock,offers,index,capabilities)
 local T=require('src.tuning')
 local system=pickupSystem(station) or UNMAPPED
 local shortlist={}
 local rejected=rejectedFreight[r]
 if not rejected or clock<rejected.at or clock-rejected.at>=30 then
  rejected={at=clock};rejectedFreight[r]=rejected
 end
 for area,list in pairs(freightCache(u,offers,index,clock).lists) do
  local limit=area==system and T.freightCacheLocal or T.freightCacheRemote
  local n=0
  for _,entry in ipairs(list) do
   if n>=limit then break end
   local id,o=entry.id,entry.o
   if not rejected[id] and available(u,offers,id,o,clock) and Access.eligible(r,o,capabilities,u) then
    n=n+1;shortlist[#shortlist+1]={id=id,o=o}
   end
  end
 end
 return shortlist
end

function Tasks.choose(u,r,station,clock)
 if not Tasks.resolve(u,r) then return end
 if r.task then return r.task end
 -- an exhausted crew takes nothing new until it has had shore leave
 if require('src.crew_fatigue').exhausted(r) then r.taskStatus='needs shore leave';return end
 local list,ranks={},{}
 local capabilities=Access.capabilities(r)
 local offers=Tasks.state(u).offers
 local index=searchIndexes[offers] or buildSearchIndex(offers)
 local Transport=require('src.transport');local opened=Transport.beginScan(u,true)
 local freight=Tasks.definitions.transport
 if freight and Access.eligible(r,freight,capabilities) and (Work.weight(r,'transport') or 1)>0 then
  for _,entry in ipairs(freightShortlist(u,r,station,clock,offers,index,capabilities)) do
   local o=entry.o
   if freight.eligible(u,r,o,station,clock) then
    if ranks.transport==nil then ranks.transport=Work.rank(r,'transport') end
    list[#list+1]={o=o,preference=ranks.transport,risk=Access.jobRisk(r,station,o,u),v=freight.score(u,r,o,station,clock)}
   else rejectedFreight[r][entry.id]=true end
  end
 end
 local function collect(kinds)
  if not kinds then return end
  for kind,bucket in pairs(kinds) do
   local def=Tasks.definitions[kind]
   if def and Access.eligible(r,def,capabilities) and (Work.weight(r,kind) or 1)>0 then
    for id,o in pairs(bucket) do
     if available(u,offers,id,o,clock)
      and Access.eligible(r,o,capabilities,u) and def.eligible(u,r,o,station,clock) then
      if ranks[kind]==nil then ranks[kind]=Work.rank(r,kind) end
      list[#list+1]={o=o,preference=ranks[kind],risk=Access.jobRisk(r,station,o,u),v=def.score and def.score(u,r,o,station,clock) or 0}
     end
    end
   end
  end
 end
 collect(index.kinds)
 collect(index.byStation[Locations.canonical(station)])
 if opened then Transport.endScan() end
 table.sort(list,function(a,b)
  if a.preference~=b.preference then return a.preference>b.preference end
  if a.risk~=b.risk then return a.risk<b.risk end
  return a.v>b.v or a.v==b.v and a.o.id<b.o.id
 end)
 -- Within the same four-check budget, try the leading offer of each kind
 -- before another of the same kind. A blocked preferred route must not hide
 -- otherwise usable work. Category order is still the saved preference race.
 local groups,order={},{}
 for _,candidate in ipairs(list) do
  local kind=candidate.o.kind
  if not groups[kind] then groups[kind]={};order[#order+1]=kind end
  groups[kind][#groups[kind]+1]=candidate.o
 end
 local best,tries=nil,0
 for depth=1,Tasks.feasibleTries do
  for _,kind in ipairs(order) do
   local o=groups[kind][depth]
   if o then
    tries=tries+1
    local def=Tasks.definitions[kind]
    if not def.feasible or def.feasible(u,r,o,station,clock) then best=o;break end
    if kind=='transport' then rejectedFreight[r][o.id]=true end
    if tries>=Tasks.feasibleTries then break end
   end
  end
  if best or tries>=Tasks.feasibleTries then break end
 end
 if not best then r.taskStatus='waiting for work';return end
 local t=copy(best);t.phase='prepare';t.assigned=clock;t.state=nil
 -- Prepare may reject a task (e.g. a full grid hold). Never reserve failed work.
 local def=Tasks.definitions[t.kind]
 if def.prepare and not def.prepare(u,r,t,station,clock) then
  if t.kind=='transport' then rejectedFreight[r][best.id]=true end
  return
 end
 rejectedFreight[r]=nil
 best.owner=r.id;best.state='reserved'
 r.jobsStarted=(r.jobsStarted or 0)+1
 r.task=t;r.taskStatus=nil
 return t
end
function Tasks.plan(r,station,clock)
 local t=r.task
 local def=t and Tasks.definitions[t.kind]
 return def and def.plan and def.plan(t,station,clock)
end
-- Optional scene context lets completion use the normal station-market API.
function Tasks.arrive(u,r,station,clock,game)
 if not Tasks.resolve(u,r) or not Access.canStop(r,station,u) then return false end
 require('src.npc_agenda').arrive(u,r,station,clock,game)
 local t=r.task
 if not t then return end
 local def=Tasks.definitions[t.kind]
 if t.phase=='pickup' and not Access.canStop(r,t.target,u) then
  Tasks.release(u,r,'docking access denied',clock)
  return false
 end
 if def.complete(u,r,t,station,clock,game) then
  Tasks.release(u,r,'completed',clock)
  -- a one-off order is filled; standing work goes back on the board
  local o=Tasks.state(u).offers[t.id]
  if o and o.order and not require('src.npc_agenda').holds(r,t.id) then Tasks.state(u).offers[t.id]=nil end
  return true
 end
end
return Tasks
