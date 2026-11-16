-- Satellite repair work on the task board (src/tasks.lua).
--
-- When a satellite fails (Sat.knockOut in src/satellites.lua) its
-- system's trade station posts one "satrepair" order: fly from there to the
-- station nearest the satellite, spend a while on the job, and the satellite
-- is back up. A destroyed satellite posts "satlaunch" the same way, and
-- finishing it puts a replacement in its slot (free for now). Any hauler can take it; scavenger and industrial tempers lean
-- towards it (src/work_preferences.lua). The order is removed once done.
local Fields,L,G=require('src.fields'),require('src.locations'),require('src.travelgraph')
local Tasks=require('src.tasks')
local copy=require('src.persistence').copy
local J={pay=900,stay=25}
-- What each job hands the hauler to carry out to the satellite: the same
-- item the player's version of the quest uses (src/sat_quests.lua).
J.cargo={satrepair='patch_kit',satlaunch='satellite_package'}

local function root(area) return Fields.moons[area] and Fields.moons[area].parent or area end

-- Where the job starts (the system's trade station) and where it's done (a
-- station in the satellite's own field, else the start).
function J.places(field)
 local source=L.station(root(field),'trade') or L.station(field,'trade')
 local here=L.stations(field)[1]
 return source,here or source
end

function J.post(u,r,kind)
 local source,target=J.places(r.field)
 if not source then return end
 kind=kind or 'satrepair'
 -- cargo, not item/amount: the poster provides it, so it reserves no station stock
 return Tasks.post(u,{kind=kind,source=source,target=target,sat=r.id,order=true,cooldown=60,
  cargo={item=J.cargo[kind],amount=1}})
end

-- satrepair: fix a failed satellite. satlaunch: replace a destroyed one.
local function wanted(kind,s)
 if kind=='satlaunch' then return s.lost end
 return s.broken and not s.lost
end
for _,kind in ipairs({'satrepair','satlaunch'}) do
Tasks.register(kind,{
 requires={capabilities={'cargo'}},
 docks=function(r,id) return r.task and L.canonical(id)==L.canonical(r.task.target) end,
 stay=function() return J.stay end,
 eligible=function(u,r,o,node)
  local s=u.satellites and u.satellites[o.sat]
  return s and wanted(kind,s) and L.canonical(node)==L.canonical(o.source) or false
 end,
 feasible=function(u,r,o,node,clock)
  local c=o.cargo or {item=J.cargo[kind],amount=1}
  if require('src.npc_operations').room(r,c.item)<c.amount then return false end
  return o.source==o.target or G.itinerary(o.source,o.target,clock)~=nil
 end,
 score=function(u,r,o,node,clock) return clock-(o.readyAt or 0) end,
 prepare=function(u,r,t,node,clock)
  t.route=t.source==t.target and {node,node} or G.itinerary(node,t.target,clock)
  if not t.route then return false end
  t.route=copy(t.route);t.phase=kind=='satlaunch' and 'launching satellite' or 'repairing satellite'
  -- take the job's cargo aboard at the station that posted it
  t.cargo=t.cargo or {item=J.cargo[kind],amount=1}
  require('src.transport').carry(r,t.cargo.item,t.cargo.amount);t.cargoAboard=true
  return true
 end,
 plan=function(t) return copy(t.route) end,
 complete=function(u,r,t,node)
  if L.canonical(node)~=L.canonical(t.target) then return false end
  local Sat=require('src.satellites')
  -- the cargo is spent on the satellite (or, if it's already fixed, kept)
  local s=u.satellites and u.satellites[t.sat]
  if t.cargoAboard and s and wanted(kind,s) then
   require('src.transport').carry(r,t.cargo.item,-t.cargo.amount);t.cargoAboard=nil
  end
  local ok=kind=='satlaunch' and Sat.relaunch(u,t.sat,r.id) or kind=='satrepair' and Sat.fix(u,t.sat,r.id)
  if ok then r.credits=(r.credits or 0)+J.pay end
  return true
 end,
})
end
-- The job is done (by anyone): drop the NPC orders for it nobody has taken.
function J.clear(u,id)
 local offers=Tasks.state(u).offers
 for oid,o in pairs(offers) do
  if o.sat==id and o.state=='available' then offers[oid]=nil end
 end
end
return J
