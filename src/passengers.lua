-- Residential stations and passenger contracts.
--
-- A residential station (place.residential, authored in src/world_layout.lua)
-- does two things, independently of anything else it does:
--
--   * It posts passenger contracts along its authored routes: commutes to
--     workplaces (and back), and visits to other residential stations. How
--     many are open at once is a rule on its population, not a simulation
--     of people: no residents, salaries or schedules are kept.
--   * It stores idle ships whose home it is, inside the station and off its
--     berths. They keep looking for work while stored and leave when a job
--     is worth taking (src/npc.lua).
--
-- A contract is an ordinary offer on the shared task board (src/tasks.lua),
-- kind 'passenger': players take it from the Jobs tab
-- (src/player_contracts.lua), NPCs choose it through their usual work
-- preferences. The party rides one to a climate cell, so climate space
-- decides who may take it; comfort and useful speed decide the fare, which
-- locks when the contract is accepted.
local Tasks=require('src.tasks')
local Fields=require('src.fields')
local L=require('src.locations')
local G=require('src.travelgraph')
local T=require('src.tuning')
local data=require('src.data')
local Transport=require('src.transport')
local P={item='passengers'}

-- Configuration ----------------------------------------------------------------
function P.config(id)
 local place=id and L.byId[L.canonical(id)]
 return place and place.residential
end
function P.stations()
 local out={}
 for id,place in pairs(L.byId) do
  if place.kind=='station' and place.residential and not place.accessOf then out[#out+1]=id end
 end
 table.sort(out)
 return out
end
-- Open contracts this many at once at most: the demand rule.
function P.cap(id)
 local c=P.config(id);if not c then return 0 end
 return math.max(1,math.min(T.passengerMaxOutstanding,math.floor((c.population or 0)/T.passengerResidentsPerContract+.5)))
end
function P.state(u)
 u.passengers=u.passengers or {next={},seed=7919,posted=0,expired=0,delivered=0,fares=0}
 return u.passengers
end
-- Contracts a residential station's demand has out: posted, accepted, or
-- aboard a ship. A delivered or expired one no longer counts.
function P.outstanding(u,home)
 local n=0
 for _,o in pairs(Tasks.state(u).offers) do
  if o.kind=='passenger' and o.home==home then n=n+1 end
 end
 return n
end
function P.offers(u,filter)
 local out={}
 for _,o in pairs(Tasks.state(u).offers) do
  if o.kind=='passenger' and (not filter or filter(o)) then out[#out+1]=o end
 end
 table.sort(out,function(a,b)return a.id<b.id end)
 return out
end

-- Seats, comfort and speed ------------------------------------------------------
-- A ship's climate spaces, best seats first: { cells, comfort }.
function P.seats(ship)
 local hull=ship and data.hulls[ship.hull];if not hull then return {} end
 local out={}
 for _,c in ipairs(hull.compartments or {}) do
  if c.kind=='climate' then out[#out+1]={cells=(c[1] or c.w)*(c[2] or c.h),comfort=c.comfort or T.passengerHoldComfort} end
 end
 for _,id in pairs(ship.loadout or {}) do
  local m=id and data.modules[id]
  if m and m.climate then out[#out+1]={cells=m.hold or 0,comfort=m.comfort or T.passengerPodComfort} end
 end
 table.sort(out,function(a,b)return a.comfort>b.comfort end)
 return out
end
function P.seatCount(ship)
 local n=0;for _,s in ipairs(P.seats(ship)) do n=n+s.cells end
 return n
end
-- The party's average comfort, seated best-first (0..1); nil if it can't sit.
function P.comfort(ship,party)
 local left,sum=party,0
 for _,s in ipairs(P.seats(ship)) do
  local n=math.min(left,s.cells);sum=sum+n*s.comfort;left=left-n
  if left<=0 then break end
 end
 if left>0 or party<=0 then return nil end
 return math.max(0,math.min(1,sum/party))
end
local function routeAU(o,clock)
 if o.routeAU then return o.routeAU end
 local route=Transport.route(o.source,o.target,clock) or {}
 local au=0
 for i=2,#route do
  local a,b=L.byId[route[i-1]],L.byId[route[i]]
  if a.kind=='driver' and b.kind=='driver' and a.area~=b.area then au=au+Fields.distance(a.area,b.area,clock) end
 end
 o.routeAU=math.floor(au*100+.5)/100
 return o.routeAU
end
-- The journey's two parts in game seconds (Transport.duration's estimate):
-- flying under the ship's own power, and riding mass drivers, which take
-- everybody the same time.
local function legs(o)
 local a,b=L.byId[o.source],L.byId[o.target]
 local flown=a and b and a.area==b.area and 120 or 300
 return flown,(o.routeAU or 0)*120
end
-- Speed incentive share (0..1): how much faster than the reference hull
-- this ship cruises (src/npc.lua N.cruise, already capped at +-15%), times
-- the share of the journey that speed can shorten.
function P.speed(o,ship)
 local N=require('src.npc')
 local k=math.max(0,math.min(1,(N.cruise(ship)/T.npcCruise-1)/T.npcCruiseSpread))
 local flown,driven=legs(o)
 return k*flown/math.max(1,flown+driven)
end
-- Expected seconds for this ship: flown legs scale with its cruise.
function P.journey(o,ship)
 local N=require('src.npc')
 local flown,driven=legs(o)
 return flown*T.npcCruise/math.max(1,N.cruise(ship))+driven
end
function P.baseFare(o)
 return (o.party or 0)*(T.passengerFareBase+T.passengerFarePerAU*(o.routeAU or 0))
end
-- What this ship would be paid for the contract: the base fare (party x
-- route) with the comfort premium and speed incentive on top, each bounded.
-- nil if the party can't sit aboard.
function P.fare(o,ship)
 local comfort=P.comfort(ship,o.party or 0)
 if not comfort then return nil end
 local base=P.baseFare(o)
 local comfortShare=T.passengerComfortMax*comfort
 local speedShare=T.passengerSpeedMax*P.speed(o,ship)
 local total=math.floor(base*(1+comfortShare+speedShare)+.5)
 return total,{base=math.floor(base+.5),comfort=comfort,comfortShare=comfortShare,speedShare=speedShare}
end
-- The most any ship could earn (for the offer's conditions line).
function P.maxFare(o) return math.floor(P.baseFare(o)*(1+T.passengerComfortMax+T.passengerSpeedMax)+.5) end
-- Lock the fare on accepting: refitting afterwards changes nothing.
function P.lock(t,ship)
 if t.fare then return t.fare end
 local fare,detail=P.fare(t,ship)
 if not fare then return nil end
 t.fare,t.fareDetail=fare,detail
 return fare
end

-- Generation -------------------------------------------------------------------
local function random(st)
 st.seed=(st.seed*48271)%2147483647
 return st.seed/2147483647
end
local function hash(s)
 local h=0;for i=1,#s do h=(h*31+s:byte(i))%1000003 end
 return h
end
-- Small parties are usual, large ones rare.
local function party(st)
 local x=random(st)
 return math.max(1,math.min(T.passengerMaxParty,1+math.floor(x*x*T.passengerMaxParty)))
end
function P.post(u,home,clock)
 local st=P.state(u);local c=P.config(home)
 local routes={};local total=0
 for _,route in ipairs(c.routes or {}) do
  if L.byId[route.to] and route.to~=home then routes[#routes+1]=route;total=total+(route.weight or 1) end
 end
 if total<=0 then return end
 local pick=random(st)*total;local route=routes[#routes]
 for _,x in ipairs(routes) do pick=pick-(x.weight or 1);if pick<0 then route=x;break end end
 local source,target=home,route.to
 -- commuters going home: the return half of the traffic
 if route.kind=='work' and random(st)<T.passengerReturnShare then source,target=route.to,home end
 if not Transport.route(source,target,clock) then return end
 local n=party(st)
 local o={kind='passenger',source=source,target=target,home=home,purpose=route.kind or 'visit',
  party=n,item=P.item,amount=n,requires={capabilities={'climate'}},
  posted=clock,expires=clock+T.passengerExpiry}
 routeAU(o,clock)
 o=Tasks.post(u,o)
 st.posted=st.posted+1
 return o
end
-- Expire stale offers and post new ones, one station step at a time.
function P.update(u,clock)
 local st=P.state(u)
 for id,o in pairs(Tasks.state(u).offers) do
  if o.kind=='passenger' and o.state=='available' and (o.expires or math.huge)<=clock then
   Tasks.state(u).offers[id]=nil;st.expired=st.expired+1
  end
 end
 for _,id in ipairs(P.stations()) do
  -- (staggered: each station's first post lands at its own point in the interval)
  st.next[id]=st.next[id] or clock+T.passengerInterval*((hash(id)%1000)/1000)
  if clock>=st.next[id] then
   st.next[id]=clock+T.passengerInterval
   if P.outstanding(u,id)<P.cap(id) then P.post(u,id,clock) end
  end
 end
end

-- The task -----------------------------------------------------------------------
local reach,reachAt={},nil
local function reachable(a,b,clock)
 if not reachAt or clock<reachAt or clock-reachAt>600 then reach,reachAt={},clock end
 local key=a..'|'..b
 if reach[key]==nil then reach[key]=Transport.route(a,b,clock)~=nil or a==b end
 return reach[key]
end
local function seated(r) return (r.ship.cargo or {})[P.item] or 0 end
-- Seat the party aboard (in the climate grid; src/inventory/hold.lua).
function P.board(u,r,t)
 if Transport.room(r,P.item,t.party)<t.party then return false end
 Transport.carry(r,P.item,t.party)
 local o=Tasks.state(u).offers[t.id];if o then o.loaded=true end
 t.phase='delivery'
 return true
end
local function disembark(r,n)
 n=math.min(n,seated(r))
 if n>0 then Transport.carry(r,P.item,-n) end
end
Tasks.register('passenger',{
 requires={capabilities={'climate'}},
 plan=function(t,station,clock)
  if t.phase=='pickup' then return G.itinerary(station,t.source,clock) end
  return Transport.route(station,t.target,clock)
 end,
 eligible=function(u,r,o,station,clock)
  -- work elsewhere means flying there empty first, as for freight
  if station~=o.source and (r.task or not L.byId[station]) then return false end
  if not (L.byId[o.source] and L.byId[o.target]) then return false end
  return Transport.room(r,P.item,o.party)>=o.party and P.comfort(r.ship,o.party)~=nil
 end,
 feasible=function(u,r,o,station,clock)
  return (station==o.source or reachable(station,o.source,clock)) and reachable(o.source,o.target,clock)
 end,
 score=function(u,r,o,station,clock)
  -- credits per second of the whole job, the run to the pickup included
  local fare=P.fare(o,r.ship) or 0
  local seconds=P.journey(o,r.ship)+(station~=o.source and 180 or 0)
  local p=require('src.personality').ensure(r)
  return fare/math.max(1,seconds)*100*(0.5+(p.ambition or .5))
 end,
 prepare=function(u,r,t,station,clock)
  if not P.lock(t,r.ship) then return false end
  if Transport.room(r,P.item,t.party)<t.party then return false end
  t.phase='pickup'
  if station==t.source then return P.board(u,r,t) end
  return true
 end,
 complete=function(u,r,t,station,clock)
  if t.settled then return true end
  if t.phase=='pickup' then
   if station~=t.source then return false end
   if not P.board(u,r,t) then Tasks.release(u,r,'no seats for the party',clock) end
   return false
  end
  if station~=t.target then return false end
  if seated(r)<t.party then Tasks.release(u,r,'passengers missing',clock);return false end
  disembark(r,t.party)
  local fare=t.fare or P.lock(t,r.ship) or 0
  r.credits=(r.credits or 0)+fare
  r.passengerEarnings=(r.passengerEarnings or 0)+fare
  r.lastDestination=station;r.lastOrigin=t.source
  local st=P.state(u);st.delivered=st.delivered+1;st.fares=st.fares+fare
  require('src.simulation_history').note(u,'passengers_delivered',clock,L.byId[station].area,{r.id},
   {taskId=t.id,source=t.source,target=t.target,home=t.home,party=t.party,routeAU=t.routeAU,fare=fare,detail=t.fareDetail},station)
  Tasks.state(u).offers[t.id]=nil
  t.settled=true
  return true
 end,
 -- A contract given up with the party aboard ends there: they get off,
 -- unpaid, and the demand it held is free again.
 release=function(u,r,t,reason,clock)
  if t.phase~='delivery' then return end
  if r.ship then disembark(r,t.party) end
  Tasks.state(u).offers[t.id]=nil
 end,
})

-- Why an NPC can't take this contract (nil if it can), for the inspector.
function P.whyNot(u,r,o,station)
 local Work,Access=require('src.work_preferences'),require('src.npc_access')
 if not r.ship then return 'no ship' end
 if (Work.weight(r,'passenger') or 0)<=0 then return 'work profile '..tostring(r.workProfile)..' takes no passengers' end
 local caps=Access.capabilities(r)
 if not caps.climate then return 'no climate hold' end
 if not Access.eligible(r,o,caps) then return 'not allowed on this route' end
 local seats=P.seatCount(r.ship)
 if seats<o.party then return ('party of %d, only %d climate seats'):format(o.party,seats) end
 if Transport.room(r,P.item,o.party)<o.party then return 'climate hold not empty enough' end
 if r.task then return 'busy with '..r.task.kind end
 if o.state~='available' then return 'already taken' end
 station=station or r.node or r.station
 if station and station~=o.source and not L.byId[station] then return 'not at a station' end
 return nil
end

-- Resident storage ---------------------------------------------------------------
function P.residents(u,id)
 local list={}
 for _,r in pairs(u.npcs or {}) do
  if r.resident==id and r.state~='dead' and r.state~='escaped' then list[#list+1]=r end
 end
 table.sort(list,function(a,b)return a.id<b.id end)
 return list
end
function P.storage(id) local c=P.config(id);return c and c.storage or 0 end
function P.vacancy(u,id) return math.max(0,P.storage(id)-#P.residents(u,id)) end
-- Seconds until a stored ship next looks for work, spread by id.
function P.retry(r) return T.residentRetry*(.75+.5*(hash(tostring(r.id))%1000)/1000) end
-- Store an idle ship at its residential home (offline only: a ship on screen
-- stays in its berth). True if it is stored now.
function P.store(u,r,node,online)
 if r.resident==node then return true end
 if online or r.task or not P.config(node) or r.homeStation~=node then return false end
 if P.vacancy(u,node)<=0 then return false end
 r.resident=node;r.departWaitSince=nil
 r.state='docked';r.node=node;r.waitingHomeBerth=nil
 r.taskStatus='stored at home'
 require('src.alife_trace').note(r,u.clock or 0,'npc','stored at residential home '..node)
 return true
end
-- A stored ship with a reserved job leaves when a berth is free to leave
-- from. False keeps it stored: still waiting, or the job given back.
function P.depart(u,r,node,at)
 if require('src.dock_room').room(u,r,node) then
  r.resident=nil;r.departWaitSince=nil
  require('src.alife_trace').note(r,at,'npc','leaving residential storage for '..tostring(r.task and r.task.kind))
  return true
 end
 r.departWaitSince=r.departWaitSince or at
 if at-r.departWaitSince>=T.residentDepartWait then
  r.departWaitSince=nil
  Tasks.release(u,r,'no berth to depart from',at)
  r.taskStatus='stored at home'
 else
  r.taskStatus='waiting to depart'
 end
 return false
end
-- Passenger-side state for debug views.
function P.status(r)
 if r.resident then return r.departWaitSince and 'waiting to depart' or 'stored at home' end
 local t=r.task
 if t and t.kind=='passenger' then
  return t.phase=='delivery' and ('carrying %d passengers'):format(t.party or 0) or 'travelling to pickup'
 end
end
return P
