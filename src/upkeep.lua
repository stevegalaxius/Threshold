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

-- Plan a visit if one is due. Only while travelling within a region, and
-- never mid-fight or during a reconciliation.
function U.plan(r,clock,e)
 if r.service or not (r.state=='travel' or r.state=='idle') or not r.area or not r.route or not r.route[r.index] then return false end
 if r.state=='idle' and not r.node then return false end
 if r.encounter or r.worldRecovery or r.waitingForHome or r.driverState then return false end
 if (r.nextServiceAt or 0)>clock then return false end
 local need=U.need(r,e)
 if not need then return false end
 local idle=r.state=='idle'
 local at=idle and r.node or r.route[r.index]
 if L.get(at).area~=r.area then return false end
 -- the leg under way must be a plain in-region one
 local prev=not idle and r.route[r.index-1]
 if not idle and (not prev or L.get(prev).area~=r.area) then return false end
 local g=deps.graph(r.area)
 local best,out,back,station
 for _,id in ipairs(L.stations(r.area)) do
  if serves(need,id) then
   local go=id==L.canonical(at) and {legs={},duration=0} or Graph.route(g,at,id,clock,r.speed)
   local ret=go and (#go.legs==0 and {legs={}} or Graph.route(g,id,at,clock,r.speed))
   if ret and (not best or go.duration<best) then best,out,back,station=go.duration,go,ret,id end
  end
 end
 if not out then r.nextServiceAt=clock+T.npcFuelStopRetry
  require('src.alife_trace').note(r,clock,'upkeep','needs '..need..', no station in '..r.area..' can serve it');return false end
 local route={idle and at or prev,at}
 if idle then route={at} end
 for _,leg in ipairs(out.legs) do route[#route+1]=leg.edge.to end
 for _,leg in ipairs(back.legs) do route[#route+1]=leg.edge.to end
 r.service={station=L.canonical(station),need=need,saved={route=copy(r.route),index=r.index,
  idle=idle or nil,node=idle and r.node or nil,untilTime=idle and r.untilTime or nil}}
 r.route=route
 require('src.alife_trace').note(r,clock,'upkeep','needs '..need..' -> service visit at '..station)
 if not idle then r.index=2   -- the leg under way is kept: same depart, same arrive
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
   if clock<r.arrive then return true end
   local at=r.arrive
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
