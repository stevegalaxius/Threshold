-- Satellite repair work on the task board (src/tasks.lua).
--
-- When a satellite fails (Sat.knockOut in src/satellites.lua) its
-- system's trade station posts one "satrepair" order: fly from there to the
-- station nearest the satellite, spend a while on the job, and the satellite
-- is back up. Any hauler can take it; scavenger and industrial tempers lean
-- towards it (src/work_preferences.lua). The order is removed once done.
local Fields,L,G=require('src.fields'),require('src.locations'),require('src.travelgraph')
local Tasks=require('src.tasks')
local copy=require('src.persistence').copy
local J={pay=900,stay=25}

local function root(area) return Fields.moons[area] and Fields.moons[area].parent or area end

-- Where the job starts (the system's trade station) and where it's done (a
-- station in the satellite's own field, else the start).
function J.places(field)
 local source=L.station(root(field),'trade') or L.station(field,'trade')
 local here=L.stations(field)[1]
 return source,here or source
end

function J.post(u,r)
 local source,target=J.places(r.field)
 if not source then return end
 return Tasks.post(u,{kind='satrepair',source=source,target=target,sat=r.id,order=true,cooldown=60})
end

Tasks.register('satrepair',{
 requires={capabilities={'cargo'}},
 docks=function(r,id) return r.task and L.canonical(id)==L.canonical(r.task.target) end,
 stay=function() return J.stay end,
 eligible=function(u,r,o,node)
  local s=u.satellites and u.satellites[o.sat]
  return s and s.broken and not s.lost and L.canonical(node)==L.canonical(o.source) or false
 end,
 feasible=function(u,r,o,node,clock) return o.source==o.target or G.itinerary(o.source,o.target,clock)~=nil end,
 score=function(u,r,o,node,clock) return clock-(o.readyAt or 0) end,
 prepare=function(u,r,t,node,clock)
  t.route=t.source==t.target and {node,node} or G.itinerary(node,t.target,clock)
  if not t.route then return false end
  t.route=copy(t.route);t.phase='repairing satellite'
  return true
 end,
 plan=function(t) return copy(t.route) end,
 complete=function(u,r,t,node)
  if L.canonical(node)~=L.canonical(t.target) then return false end
  if require('src.satellites').fix(u,t.sat,r.id) then r.credits=(r.credits or 0)+J.pay end
  return true
 end,
})
return J
