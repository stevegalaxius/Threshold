-- Upkeep: the one needs layer every persistent NPC runs before its role.
--
-- Roles (trader, courier, patrol, pirate, salvager, miner, and whatever comes
-- next) only describe their duties. Upkeep watches the needs every ship has
-- (reactor fuel, hull, ammunition) and, when one is due, takes the ship over
-- with a service visit: out to the nearest station in the region that can
-- serve it, dock, refit, and back to the node the role was heading to. Then it
-- hands the untouched role state back as if the ship had just arrived there.
-- Roles never see the visit, and the visit never looks at roles.
--
-- The record's r.service is the only state: { station, need, saved = {route,
-- index} }. Offline (U.advance) and online (alife.lua's hooks) both read it.
local T=require('src.tuning')
local L=require('src.locations')
local Graph=require('src.travelgraph')
local Fuel=require('src.reactor_fuel')
local Repairs=require('src.npc_repair')
local Supplies=require('src.supplies')
local copy=require('src.persistence').copy
local U={}
local deps={}
-- alife.lua passes its travel primitives (start, graph) once at load.
function U.install(d) for k,v in pairs(d) do deps[k]=v end end

-- The most pressing need, or nil. e: the live entity, when online.
function U.need(r,e)
 local fuel=Fuel.condition(r,e)
 if fuel~='normal' and fuel~='stranded' then return 'fuel' end
 if Repairs.needs(r,e and e.armor,e and e.stats.armor) then return 'repair' end
 if Supplies.needs(r,e) then return 'supplies' end
 return nil
end
local function serves(need,station)
 if need=='repair' then return Repairs.supports(station) end
 return Supplies.supports(station)
end
U.serves=serves

function U.active(r) return r and r.service~=nil end
function U.isStation(r,id) return r.service~=nil and L.canonical(id)==r.service.station end

-- Regions next door: this region's moons and the planet it orbits. A region
-- with no station of its own (Neptune) services at one of these.
local function neighbours(area)
 local Fields=require('src.fields');local out={}
 if Fields.moons[area] then out[#out+1]=Fields.moons[area].parent end
 for moon,m in pairs(Fields.moons) do if m.parent==area then out[#out+1]=moon end end
 table.sort(out)
 return out
end
-- The nearest serving station in a neighbouring region, by the in-region
-- time to the gate that leads there, and the node lists out and back.
-- Returns station, {out=,back=,duration=} or nil.
function U.neighbourStop(area,at,clock,ok,speed)
 local g=deps.graph(area)
 local best,station,trip
 for _,other in ipairs(neighbours(area)) do
  for _,id in ipairs(L.stations(other)) do
   if ok(id) then
    local go=Graph.itinerary(at,id,clock);local ret=go and Graph.itinerary(id,at,clock)
    if ret then
     -- in-region part: up to the first node outside this region
     local exit=at
     for _,n in ipairs(go) do if L.get(n).area~=area then break end exit=n end
     local leg=exit==at and {duration=0} or Graph.route(g,at,exit,clock,speed or 700)
     local d=leg and leg.duration or math.huge
     if not best or d<best then best,station,trip=d,id,{out=go,back=ret,duration=d} end
    end
   end
  end
 end
 return station,trip
end

-- Fuel by route: the fixed "low" mark can be less than the trip to the
-- nearest fuel stop in a big region (the gas giants), so also go when what's
-- left wouldn't cover the rest of this leg plus that trip, with a margin.
-- Never when the tank is already as full as a refill would make it.
function U.shortOfFuel(r,e,g,at,clock)
 local ship=e or r.ship
 local hull=e and e.hull or require('src.data').hulls[ship.hull]
 if not hull then return false end
 local s=e and e.stats or require('src.stats').compute(hull,ship.loadout)
 if (s.powerOut or 0)<=0 then return false end
 local have=Fuel.remaining(ship)
 local full=(Supplies.targets(r,e)[Fuel.item()] or 0)*T.reactorFuelEnergy
 if have>=full then return false end
 local best
 for _,id in ipairs(L.stations(r.area)) do
  if Supplies.supports(id) then
   local go=id==L.canonical(at) and {duration=0} or Graph.route(g,at,id,clock,r.speed)
   if go and (not best or go.duration<best) then best=go.duration end
  end
 end
 if not best then
  local _,trip=U.neighbourStop(r.area,at,clock,Supplies.supports,r.speed)
  if not trip then return false end
  -- the far side of the gate is unknown here: count the gate trip twice
  best=trip.duration*2
 end
 local leg=r.state=='travel' and math.max(0,(r.arrive or clock)-clock) or 0
 local burn=math.min(s.powerOut,math.max(0,s.powerDraw)*T.idleDrain+math.max(1,s.powerNet*(1-T.thrustRecharge)))
 return have<burn*((leg+best)*T.npcFuelRangeMargin+T.npcFuelRangeSlack)
end

-- Plan a visit if one is due. Only while travelling within a region, and
-- never mid-fight or during a reconciliation.
function U.plan(r,clock,e)
 if r.service or not (r.state=='travel' or r.state=='idle') or not r.area or not r.route or not r.route[r.index] then return false end
 if r.state=='idle' and not r.node then return false end
 if r.encounter or r.worldRecovery or r.waitingForHome or r.driverState then return false end
 if (r.nextServiceAt or 0)>clock then return false end
 local idle=r.state=='idle'
 local at=idle and r.node or r.route[r.index]
 if L.get(at).area~=r.area then return false end
 -- the leg under way must be a plain in-region one
 local prev=not idle and r.route[r.index-1]
 if not idle and (not prev or L.get(prev).area~=r.area) then return false end
 local g=deps.graph(r.area)
 local need=U.need(r,e)
 if not need and (r.fuelRangeCheckAt or 0)<=clock then
  r.fuelRangeCheckAt=clock+T.npcFuelRangeCheck
  if U.shortOfFuel(r,e,g,at,clock) then need='fuel' end
 end
 if not need then return false end
 local best,out,back,station
 for _,id in ipairs(L.stations(r.area)) do
  if serves(need,id) then
   local go=id==L.canonical(at) and {legs={},duration=0} or Graph.route(g,at,id,clock,r.speed)
   local ret=go and (#go.legs==0 and {legs={}} or Graph.route(g,id,at,clock,r.speed))
   if ret and (not best or go.duration<best) then best,out,back,station=go.duration,go,ret,id end
  end
 end
 local trip -- node lists out and back, for a stop in a neighbouring region
 if not out then
  station,trip=U.neighbourStop(r.area,at,clock,function(id) return serves(need,id) end,r.speed)
  if not station then r.nextServiceAt=clock+T.npcFuelStopRetry
   require('src.alife_trace').note(r,clock,'upkeep','needs '..need..', no station in or next to '..r.area..' can serve it');return false end
 end
 local route={idle and at or prev,at}
 if idle then route={at} end
 -- Heading out of the region (into a mass driver or a moon gate): the
 -- crossing is no place to turn round. Offline that put the ship's leg to
 -- the station starting at the driver itself, so it woke inside the gun.
 -- It turns round where it is instead, back by the node it left, and the
 -- visit's last leg brings it to the crossing again.
 local nextStop=not idle and r.route[r.index+1]
 local crossing=not idle and (L.get(at).kind=='driver' or L.get(at).kind=='moon_gate' or nextStop and L.get(nextStop).area~=r.area)
 if crossing and not trip then
  local go=L.canonical(prev)==station and {legs={}} or Graph.route(g,prev,station,clock,r.speed)
  local ret=go and Graph.route(g,station,at,clock,r.speed)
  if go and ret then out,back=go,ret;route={at,prev} else crossing=false end
 elseif crossing then crossing=false end
 if trip then
  for i=2,#trip.out do route[#route+1]=trip.out[i] end
  for i=2,#trip.back do route[#route+1]=trip.back[i] end
 else
  for _,leg in ipairs(out.legs) do route[#route+1]=leg.edge.to end
  for _,leg in ipairs(back.legs) do route[#route+1]=leg.edge.to end
 end
 -- where the ship is now, on the leg it's leaving (before the route changes)
 local here
 if crossing then
  here={}
  if e and e.body and not e.body:isDestroyed() then here.x,here.y=e.body:getPosition()
  else here.x,here.y=require('src.alife').trackPoint(r,clock) end
 end
 r.service={station=L.canonical(station),need=need,saved={route=copy(r.route),index=r.index,
  idle=idle or nil,node=idle and r.node or nil,untilTime=idle and r.untilTime or nil}}
 r.route=route
 require('src.alife_trace').note(r,clock,'upkeep','needs '..need..' -> service visit at '..station)
 if crossing then
  -- the leg under way becomes crossing -> the node it left, picked up at the
  -- ship's present spot (online, the live ship just flies to the new stop)
  local A=require('src.alife')
  local x,y=here.x,here.y
  r.index=2
  local leg={from=at,to=prev}
  local duration=math.max(.1,Graph.length(g,leg,clock)/r.speed)
  local p=math.min(.99,Graph.project(g,leg,x,y,clock))
  r.depart=clock-p*duration;r.arrive=r.depart+duration
  local bx,by=A.journeyPoint(r,p,clock)
  r.offset={x=x-bx,y=y-by,progress=p};r.pose=nil
  require('src.queue').leg(r)
 elseif not idle then r.index=2;require('src.queue').leg(r)   -- the leg under way is kept: same depart, same arrive; it books the service dock
 elseif #route==1 then r.index=1;r.state='docked';Repairs.begin(r,at,clock,T.alifeStay)
 else r.index=1;deps.start(r,clock,2) end
 return true
end

-- Back at the node the role was heading to: restore its route as though the
-- ship had just arrived there at `at`.
function U.finish(r,at)
 local s=r.service;if not s then return end
 r.route=s.saved.route;r.index=s.saved.index;r.service=nil
 require('src.alife_trace').note(r,at,'upkeep','service done at '..s.station..(U.need(r) and (', still needs '..U.need(r)) or '')..' -> back to role')
 if s.saved.idle then
  r.state='idle';r.node=s.saved.node;r.untilTime=math.max(s.saved.untilTime or at,at)
 else r.state='travel';r.depart=at;r.arrive=at end
 if U.need(r) then r.nextServiceAt=at+T.npcFuelStopRetry end
end

-- Offline: advance an active visit through elapsed events. Returns true when
-- upkeep owned this update (the role must not run).
function U.advance(r,clock,u)
 if not r.service then return false end
 if r.encounter then return true end
 for _=1,64 do
  if r.state=='travel' or r.state=='transit' then
   local at=require('src.queue').due(r)
   if clock<at then return true end
   r.offset,r.pose=nil,nil
   if U.isStation(r,r.route[r.index]) and not r.serviced then
    r.state='docked';r.node=r.route[r.index];Repairs.begin(r,r.node,at,T.alifeStay)
   elseif r.index>=#r.route then
    r.serviced=nil;U.finish(r,at);return false
   else deps.start(r,at,r.index+1) end
  elseif r.state=='docked' then
   Repairs.advance(r,clock,r.node)
   Fuel.observe(u,r,clock)
   if clock<r.untilTime then return true end
   r.serviced=true
   if r.index>=#r.route then r.serviced=nil;U.finish(r,r.untilTime);return false end
   deps.start(r,r.untilTime,r.index+1)
  else return true end
 end
 return true
end

-- Online: called when the live ship has just passed route stop `passed`.
-- Returns true when the role's route has been handed back.
function U.passed(r,passed)
 if not r.service or passed<#r.route then return false end
 r.serviced=nil
 U.finish(r,0)
 return true
end

-- Online dock at the service station: leave once the need is met (or the
-- station has done what it can).
function U.canDepart(game,e,r)
 e.serviceDockedAt=e.serviceDockedAt or game.time
 return not U.need(r,e) or game.time-e.serviceDockedAt>T.alifeStay
end

function U.label(r)
 local s=r.service;if not s then return nil end
 local place=L.byId[s.station]
 local what=s.need=='fuel' and 'refuel' or s.need=='repair' and 'repair' or 'resupply'
 return ('heading to %s at %s'):format(what,place and place.name or s.station)
end
return U
