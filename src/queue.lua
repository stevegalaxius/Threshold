-- Queues at chokepoints: a mass driver an NPC is about to fire from, and a
-- station dock it is about to dock at. One beam serves one ship at a time
-- (a station serves as many at once as it has docks), so a ship arriving
-- while it's busy waits its turn in a numbered holding spot lined up behind
-- the approach, instead of piling onto the breech or the runway.
--
-- Turns are booked when the leg towards the chokepoint starts, from the time
-- the ship will get there: universe.queues[node] is a list of bookings
-- {start, finish, id}. The record keeps its own: r.queue = {key, ready,
-- service}. Offline, the ship finishes its leg at r.arrive and then waits
-- until r.queue.ready. Live approaches instead admit ships by actual
-- availability and arrival order, including when their ETA bookings expired.
local L=require('src.locations')
local T=require('src.tuning')
local Q={universe=nil,docks={}}
local liveQueues=setmetatable({},{__mode='k'})
function Q.invalidate(game) liveQueues[game]=nil end
local function liveCache(game)
 local cache=liveQueues[game]
 if not cache or cache.clock~=game.universe.clock then
  cache={clock=game.universe.clock,lines={},ships={}}
  for _,e in ipairs(game.entities) do
   if e.kind=='ship' then cache.ships[#cache.ships+1]=e end
  end
  liveQueues[game]=cache
 end
 return cache
end

local function state()
 local u=Q.universe;if not u then return nil end
 u.queues=u.queues or {}
 return u.queues
end

-- The chokepoint the leg ending at route[index] leads into, if any:
-- returns its key, kind and how many it serves at once.
function Q.chokepoint(r,index)
 local id=r.route and r.route[index];local place=id and L.byId[id]
 if not place then return end
 if place.kind=='driver' then
  local nextId=r.route[index+1]
  -- a service visit's route ends back at the driver the role was heading
  -- for: what comes after it is in the route the visit saved
  local saved=not nextId and r.service and r.service.saved
  if saved and saved.route and saved.route[saved.index]==id then nextId=saved.route[saved.index+1] end
  local nextPlace=nextId and L.byId[nextId]
  if nextPlace and nextPlace.area~=place.area then return id,'driver',1 end
  return
 end
 if place.kind=='station' and require('src.npc').docksAt(r,id) then
  local key=L.canonical(id)
  if Q.docks[key] then return key,'dock',Q.docks[key] end
  -- one at a time per dock; a station with access points (the Heaven-
  -- Ladder's anchors) has its docks spread across them
  local docks=0
  for other,p in pairs(L.byId) do
   if (other==key or p.accessOf==key) and p.kind=='station' then
    local ok,def=pcall(L.stationDefinition,other)
    docks=docks+(ok and def and def.docks and #def.docks or 1)
   end
  end
  Q.docks[key]=math.max(1,docks)
  return key,'dock',Q.docks[key]
 end
end

-- Book the earliest turn at `key` at or after `at` while fewer than
-- `capacity` other bookings overlap it. Returns its start.
local function book(key,id,at,service,capacity)
 local qs=state();if not qs then return at end
 local list=qs[key] or {};qs[key]=list
 -- forget finished turns, and this ship's own old booking
 for i=#list,1,-1 do local b=list[i];if b.finish<at-600 or b.id==id then table.remove(list,i) end end
 local candidates={at}
 for _,b in ipairs(list) do if b.finish>at then candidates[#candidates+1]=b.finish end end
 table.sort(candidates)
 for _,t in ipairs(candidates) do
  local busy=0
  for _,b in ipairs(list) do if b.start<t+service and b.finish>t then busy=busy+1 end end
  if busy<capacity then
   list[#list+1]={start=t,finish=t+service,id=id}
   return t
  end
 end
 return at
end

-- A leg has just started towards route[r.index] arriving at r.arrive: book
-- its turn if that's a chokepoint. (Clears any old booking otherwise.)
function Q.leg(r)
 local key,kind,capacity=Q.chokepoint(r,r.index)
 if not key then r.queue=nil;return end
 local service=T.queueService[kind]
 local ready=book(key,r.id,r.arrive,service,capacity)
 r.queue={key=key,kind=kind,ready=ready,at=r.arrive,service=service,capacity=capacity}
end

-- Something outside the line (the player) has the chokepoint: nobody's turn
-- comes while it does. Every turn not yet started slides back by dt, and the
-- ships holding those turns with it, so they stay in line where they are.
function Q.hold(key,dt,clock)
 local qs=state();local list=qs and qs[key]
 if not list then return end
 local npcs=Q.universe.npcs or {}
 for _,b in ipairs(list) do
  if b.finish>clock then
   if b.start<clock then b.start=clock end
   b.start,b.finish=b.start+dt,b.finish+dt
   local r=npcs[b.id]
   if r and r.queue and r.queue.key==key then r.queue.ready=b.start end
  end
 end
end

-- When the ship's turn comes: the end of its leg, or later if it's queued.
function Q.due(r)
 local q=r.queue
 return q and q.ready>r.arrive and q.ready or r.arrive
end

-- Still waiting for its turn at the chokepoint its route is on.
function Q.waiting(r,clock,game)
 local e=game and game.alifeOnline and game.alifeOnline[r.id]
 if e and r.queue then
  return not not Q.holding(game,e,e.route and e.route[e.routeIndex or 1])
 end
 local q=r.queue
 -- (a turn that came free on time is no wait at all)
 return q and q.ready>(q.at or 0)+.5 and r.route and r.route[r.index] and L.canonical(r.route[r.index])==q.key and clock<q.ready
end

-- Live docks serve the ships actually nearby, not future reservations.
-- Keep arrival order for each runway; another runway can admit independently.
function Q.dockBusy(game,st,dock,e)
 for _,other in ipairs(liveCache(game).ships) do
  if other~=e and other.kind=='ship' and not other.dead and not other.removed then
   local ds=other.dockState
   local exit=other.dockExit
   if ds and ds.station==st and (ds.dock or st.dock)==dock and not ds.done
    or exit and exit.station==st and exit.dock==dock then return true end
  end
 end
 return false
end

local function liveLine(game,e,stop)
 local AI=require('src.ai')
 local driver=stop.kind=='driver' and stop.driver
 local dock=not driver and AI.approachDock(e,stop)
 local kind=driver and 'driver' or 'dock'
 local clock=game.universe.clock
 local cache=liveCache(game)
 local resource=driver or dock
 local line=cache.lines[resource]
 if not line then
  line={};cache.lines[resource]=line
  for id,other in pairs(game.alifeOnline or {}) do
   local r=game.universe.npcs[id];local q=r and r.queue
   local target=other.route and other.route[other.routeIndex or 1]
   if q and q.kind==kind and q.key==L.canonical(stop.locationId)
    and not other.dead and not other.removed and not other.dockState and not other.dockExit
    and not other.driverTractor and not other.launch
    and (target==stop or driver and target and target.driver==driver) then
    local sx,sy=AI.stopPoint(target,other);local x,y=other.body:getPosition()
    local reach=T.queueStart+T.queueGap*4
    if (x-sx)^2+(y-sy)^2<=reach^2 then
     q.entered=q.entered or clock
     if driver or AI.approachDock(other,stop)==dock then line[#line+1]={e=other,at=q.entered,id=id} end
    else q.entered=nil end
   end
  end
  table.sort(line,function(a,b) return a.at<b.at or a.at==b.at and a.id<b.id end)
 end
 local occupant=driver and driver.driverShip
 local busy=driver and occupant and occupant~=e and not occupant.dead and not occupant.removed
 if not driver then busy=Q.dockBusy(game,stop,dock,e) end
 local place=0
 for _,candidate in ipairs(line) do
  local other=candidate.e
  -- Capture or removal can happen after the line was built this tick.
  if not other.dead and not other.removed and not other.dockState and not other.dockExit
   and not other.driverTractor and not other.launch then
   place=place+1
   if other==e then return busy or place>1,place end
  end
 end
 return false,1
end

-- Online: is the live ship e holding for its turn at route stop `stop`?
function Q.holding(game,e,stop)
 local r=e.alifeId and game.universe.npcs[e.alifeId]
 local q=r and r.queue
 if q and stop and (q.kind=='dock' and stop.dock or q.kind=='driver' and stop.driver)
  and stop.locationId and L.canonical(stop.locationId)==q.key then
  local waiting,place=liveLine(game,e,stop)
  return waiting and r or nil,place
 end
 -- No booking for this dock (it expired, or the visit never booked one):
 -- while another ship is in its beam or coming out of it, wait off the
 -- runway rather than flying on into the door and the hull round it.
 if r and stop and stop.dock and not (q and q.kind=='dock') and not e.dockState then
  local AI=require('src.ai')
  local dock=AI.approachDock(e,stop)
  if Q.dockBusy(game,stop,dock,e) then
   local sx,sy=AI.stopPoint(stop,e);local x,y=e.body:getPosition()
   if (x-sx)^2+(y-sy)^2<=(T.queueStart+T.queueGap*4)^2 then return r,1 end
  end
 end
 return q and q.ready>(q.at or 0)+.5 and stop and stop.locationId and L.canonical(stop.locationId)==q.key and game.universe.clock<q.ready and r or nil
end

-- Its place in line: 1 is next in, 2 behind that, and so on.
function Q.place(r,clock,game)
 local e=game and game.alifeOnline and game.alifeOnline[r.id]
 if e and r.queue then
  local _,place=Q.holding(game,e,e.route and e.route[e.routeIndex or 1]);return place or 1
 end
 local q=r.queue;if not q then return 1 end
 local qs=state();local list=qs and qs[q.key] or {}
 local ahead=0
 local npcs=Q.universe and Q.universe.npcs or {}
 for _,b in ipairs(list) do
  local o=npcs[b.id]
  -- only ships actually still lined up here count as ahead
  if b.id~=r.id and b.start<q.ready and b.finish>clock and o and o.queue and o.queue.key==q.key then ahead=ahead+1 end
 end
 return math.floor(ahead/(q.capacity or 1))+1
end

-- Where it holds: back along the way it came, T.queueStart from the
-- chokepoint for the first in line and T.queueGap further for each behind.
function Q.holdPoint(r,clock,index,place)
 index=index or r.index
 local id=r.route[index]
 local x,y=L.position(id,clock)
 local from=r.route[index-1]
 local fx,fy
 if from and L.byId[from] and L.byId[from].area==L.byId[id].area then fx,fy=L.position(from,clock) end
 local dx,dy
 if fx and (fx-x)^2+(fy-y)^2>1 then dx,dy=fx-x,fy-y else dx,dy=x,y end -- else: straight out from the planet
 local d=math.sqrt(dx*dx+dy*dy);if d<1 then dx,dy,d=1,0,1 end
 local back=T.queueStart+T.queueGap*((place or Q.place(r,clock))-1)
 return x+dx/d*back,y+dy/d*back
end

function Q.label(r,clock,game)
 if not Q.waiting(r,clock,game) then return end
 local n=Q.place(r,clock,game)
 local suffix=n==1 and 'st' or n==2 and 'nd' or n==3 and 'rd' or 'th'
 local place=L.byId[r.route[r.index]]
 local text=('queued %d%s for %s'):format(n,suffix,place and place.name or r.route[r.index])
 local live=game and game.alifeOnline and game.alifeOnline[r.id]
 return live and text or text..(' (%.0fs)'):format(r.queue.ready-clock)
end
return Q
