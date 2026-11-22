--[[
	Crew fatigue and shore leave: the one need NPC crews have beyond their
	ship's (fuel, hull, ammunition). A crew tires while it's out flying and
	rests by taking shore leave at a station, which it pays for. That pay is
	how NPC credits get back to stations (it replaced the docking fee), and
	resting crews eat and drink there (src/station_needs.lua), so a busy
	dock asks for food and water freight.

	  r.fatigue    0..1, where the record stood at r.fatigueAt
	  r.fatigueAt  universe clock r.fatigue was settled at
	  r.rest       { node, from, to, start, stop } while on shore leave
	  r.restSpend  credits spent on shore leave, ever

	Everything is worked out from the clock and the record's state over the
	elapsed time, never per frame, so online and offline give the same
	numbers. F.settle runs wherever the record's state is about to change
	(a leg starts, the ship arrives or docks, upkeep plans), so the state
	in force since r.fatigueAt is the one that applied the whole time.

	How it plays out:
	  underway (travel, transit, holding) tires at T.fatigueRate a minute,
	    T.fatigueTransit times that on an interplanetary crossing; rank
	    sets endurance (src/npc_rank.lua)
	  a fight (F.fought) and lost armor (F.hurt) add a lump
	  docked on ordinary business: neither tires nor rests
	  past F.threshold(r) (ambition moves it) upkeep plans a rest stop
	    (src/upkeep.lua), at the station F.choose picks; the stay, its price
	    and what fatigue is left come from F.begin
	Exempt: wildcats (they rest at their site), squad members (they go
	where their leader goes and rest when it does), and drones.
]]
local T=require('src.tuning')
local L=require('src.locations')
local F={}

local function rank(r) return require('src.npc_rank').get(r) end
local function personality(r) return require('src.personality').ensure(r) end

function F.exempt(r)
 if not r or not r.ship or r.wildcat or r.drone then return true end
 if r.squad then
  local q=require('src.squads').of(require('src.supplies').universe or {},r)
  if q and q.leader~=r.id then return true end
 end
 return false
end

-- The fatigue level past which this captain books shore leave. Ambitious
-- captains push on further, timid ones rest early.
function F.threshold(r)
 local a=personality(r).ambition or .5
 return math.max(.3,math.min(.95,T.fatigueSoft+(a-.5)*T.fatigueAmbitionSpread))
end
function F.hard(r) return T.fatigueHard end

-- Tiring per second in the record's present state.
local function rate(r)
 local s=r.state
 if s=='docked' or s=='dead' or s=='escaped' then return 0 end
 if s~='travel' and s~='transit' and s~='idle' then return 0 end
 local per=T.fatigueRate/60*(rank(r).endurance or 1)
 if r.transit or s=='transit' then per=per*T.fatigueTransit end
 return per
end

local function clamp(x) return math.max(0,math.min(1,x)) end

-- Bring r.fatigue up to `clock`, by the state the record has been in since
-- it was last settled.
function F.settle(r,clock)
 if not r or not clock then return 0 end
 local at=r.fatigueAt
 r.fatigueAt=clock
 if not r.fatigue then
  -- a record from before fatigue (or a new arrival): somewhere between
  -- rested and half tired, by its id, so a loaded fleet doesn't all
  -- want shore leave in the same minute
  local n=0;local id=tostring(r.id or '')
  for i=1,#id do n=(n*31+id:byte(i))%9973 end
  r.fatigue=F.exempt(r) and 0 or (n%1000)/1000*.5
  return r.fatigue
 end
 if not at or clock<=at then return r.fatigue end
 local rest=r.rest
 if rest then
  -- (docked, or just stood down at that dock to decide what's next)
  if (r.state=='docked' or r.state=='idle') and r.node and L.canonical(r.node)==rest.node then
   -- shore leave: straight down to what the stay pays for
   local span=math.max(1e-6,rest.stop-rest.start)
   local p=clamp((clock-rest.start)/span)
   r.fatigue=rest.from+(rest.to-rest.from)*p
   if clock>=rest.stop then r.fatigue=rest.to;r.rest=nil end
   return r.fatigue
  end
  -- off the dock: the rest it got (all of it, unless it left early), then
  -- the time since, by its present state
  local stopped=math.max(at,math.min(clock,rest.stop))
  local p=clamp((stopped-rest.start)/math.max(1e-6,rest.stop-rest.start))
  r.fatigue=rest.from+(rest.to-rest.from)*p;r.rest=nil
  at=stopped
 end
 if F.exempt(r) then return r.fatigue end
 r.fatigue=clamp(r.fatigue+rate(r)*(clock-at))
 return r.fatigue
end
function F.level(r) return r and r.fatigue or 0 end

-- A fight, and armor lost (as a fraction of the hull's), tire the crew.
function F.fought(r,clock)
 if not r or F.exempt(r) then return end
 F.settle(r,clock);r.fatigue=clamp(r.fatigue+T.fatigueFight)
end
function F.hurt(r,clock,fraction)
 if not r or F.exempt(r) or not fraction or fraction<=0 then return end
 F.settle(r,clock);r.fatigue=clamp(r.fatigue+T.fatigueDamage*fraction)
end

-- Does the crew need shore leave now?
function F.needs(r)
 if F.exempt(r) or r.rest then return false end
 return (r.fatigue or 0)>=F.threshold(r)
end
function F.exhausted(r) return not F.exempt(r) and (r.fatigue or 0)>=F.hard(r) end

-- Stations -----------------------------------------------------------------

local function place(id) return id and L.byId[L.canonical(id)] end
function F.serves(id)
 local p=place(id)
 return p~=nil and p.kind=='station' and not p.accessOf
end
local function dark(id)
 local p=place(id)
 return require('src.dark').isDarkNode(L.canonical(id)) or (p and p.uses and p.uses.fence) or false
end
-- What kind of shore leave a station offers: price and how fast it rests.
function F.kind(id)
 local p=place(id)
 if not p then return {price=1,speed=1,name='station'} end
 if p.residential then return {price=T.restResidentialPrice,speed=T.restResidentialSpeed,name='residential'} end
 if dark(id) then return {price=T.restDarkPrice,speed=1,name='dark'} end
 if require('src.accounts').factionRun(id) then return {price=T.restDepotPrice,speed=T.restDepotSpeed,name='depot'} end
 return {price=1,speed=1,name='station'}
end

-- Crews on shore leave, per station: worked out once per clock reading.
local restingCache=setmetatable({},{__mode='k'})
function F.restingAll(u)
 if not u then return {} end
 local c=restingCache[u]
 if c and c.clock==u.clock then return c.counts end
 local counts={}
 for _,r in pairs(u.npcs or {}) do
  local rest=r.rest
  if rest and r.state=='docked' and (u.clock or 0)<rest.stop then counts[rest.node]=(counts[rest.node] or 0)+1 end
 end
 restingCache[u]={clock=u.clock,counts=counts}
 return counts
end
function F.resting(u,id) return F.restingAll(u)[L.canonical(id)] or 0 end

local function cells(r)
 local hull=r and r.ship and r.ship.hull
 if not hull then return 1 end
 return require('src.berth_rent').footprint(hull)
end
-- Credits a minute this record pays for shore leave at station `id`.
function F.rate(u,id,r)
 id=L.canonical(id)
 local k=F.kind(id)
 local base=T.restBaseRate*k.price
 local room=r and r.ship and require('src.dock_room').capacity(id,r.ship.hull) or 4
 if room==math.huge then room=8 end
 local crowd=1+T.restCrowding*math.min(2,F.resting(u,id)/math.max(1,room))
 local size=math.sqrt(math.max(1,cells(r)/4))
 local home=r and r.homeStation and L.canonical(r.homeStation)==id and T.restHomePrice or 1
 return base*crowd*size*home
end
-- Seconds a full rest from `fatigue` takes at `id`.
function F.duration(r,id,fatigue)
 local k=F.kind(id)
 local home=r and r.homeStation and L.canonical(r.homeStation)==L.canonical(id) and T.restHomeSpeed or 1
 return (fatigue or r.fatigue or 0)*T.restSecondsPerFatigue/(k.speed*home)
end
-- What a rest at `id` would cost, the whole of it.
function F.quote(u,r,id)
 return F.rate(u,id,r)*math.max(T.restMinStay,F.duration(r,id))/60
end
-- How a rest stop at `id`, `travel` seconds away, scores (lower is better).
-- Ambitious captains weigh the time lost; others go home if they can.
function F.cost(u,r,id,travel)
 local a=personality(r).ambition or .5
 local cost=F.quote(u,r,id)+travel*T.restTimeValue*(.5+a)
 if r.homeStation and L.canonical(r.homeStation)==L.canonical(id) then cost=cost*(1-T.restHomeLoyalty*(1-a)) end
 return cost
end

-- Shore leave starts: work out the stay, take the pay. Returns seconds.
-- A crew always rests fully; one that can't pay for all of it pays what
-- it can spare (above T.restReserve), and the station takes the loss. (A
-- broke crew that only half rested came straight back for more, and soon
-- half the fleet was asleep.)
function F.begin(u,r,id,at)
 id=L.canonical(id)
 F.settle(r,at)
 local stay=math.max(T.restMinStay,math.min(T.restMaxStay,F.duration(r,id)))
 local price=F.rate(u,id,r)*stay/60
 local paid=math.floor(math.max(0,math.min(price,(r.credits or 0)-T.restReserve)))
 if paid>0 then
  r.credits=(r.credits or 0)-paid;r.restSpend=(r.restSpend or 0)+paid
  require('src.accounts').receive(u,id,paid,'sold','shore_leave')
 end
 local covered=price>0 and math.min(1,paid/price) or 1
 r.rest={node=id,from=r.fatigue or 0,to=0,start=at,stop=at+stay}
 r.restsTaken=(r.restsTaken or 0)+1
 if r.homeStation and L.canonical(r.homeStation)==id and covered>=1 then
  r.homeRests=(r.homeRests or 0)+1
  require('src.npc_rank').experience(r,T.restHomeXp)
 end
 restingCache[u]=nil
 require('src.alife_trace').note(r,at,'upkeep',('shore leave at %s: %ds, %d cr'):format(id,math.floor(stay),paid))
 return stay
end

function F.label(r)
 local rest=r and r.rest
 if not rest then return nil end
 local p=place(rest.node)
 return ('on shore leave at %s'):format(p and p.name or rest.node)
end
return F
