-- An NPC's agenda: the jobs it holds beyond the one it is flying now.
--
-- r.task is still the active job (every controller, the inspector and the
-- save read it). r.agenda holds more jobs the ship has already taken and
-- loaded: cargo for other drop-offs riding in the same hold. When the active
-- job ends, the nearest agenda job becomes the active one, so a hauler
-- leaving a pickup can carry several orders to several stations and only
-- reads the board again once its hold is empty.
--
-- Agenda jobs are always loaded (phase 'delivery'), so they never need a
-- pickup leg of their own; a stop where the ship docks for any reason
-- settles every agenda job bound there.
local L=require('src.locations')
local T=require('src.tuning')
local copy=require('src.persistence').copy
local A={}
local function Tasks() return require('src.tasks') end

function A.list(r) return r.agenda or {} end
function A.count(r) return (r.task and 1 or 0)+#(r.agenda or {}) end
-- Does this record hold the job (a board offer's root id)?
function A.holds(r,id)
 local t=r.task or r.suspendedTask
 if t and t.id==id then return true end
 for _,a in ipairs(r.agenda or {}) do if a.id==id then return true end end
 return false
end
-- How many jobs a ship may hold at once: bigger holds and more ambitious
-- captains take more.
function A.limit(r)
 local data=require('src.data')
 local hull=r.ship and data.hulls[r.ship.hull]
 local hold=hull and hull.hold or 0
 local n=1+math.floor(hold/T.agendaHoldPerJob)
 local p=require('src.personality').ensure(r)
 if (p.ambition or .5)>.65 then n=n+1 elseif (p.ambition or .5)<.3 then n=n-1 end
 -- a tired crew takes on less (src/crew_fatigue.lua)
 local Fatigue=require('src.crew_fatigue')
 if Fatigue.exhausted(r) then return 1 elseif not Fatigue.exempt(r) and (r.fatigue or 0)>=Fatigue.threshold(r) then n=n-1 end
 return math.max(1,math.min(T.agendaMaxJobs,n))
end

-- Free a job's board offers (the root and its manifest lines). Loaded
-- cargo can't go back on a shelf: its orders leave the board.
local function free(u,r,t,clock)
 local offers=Tasks().state(u).offers
 for _,line in ipairs(t.manifest or {t}) do
  local o=offers[line.id]
  if o and o.owner==r.id then
   if t.phase=='delivery' or o.loaded then offers[line.id]=nil
   else o.owner=nil;o.state='available';o.manifestRoot=nil;o.readyAt=clock+(o.cooldown or 120) end
  end
 end
end
function A.drop(u,r,t,reason,clock)
 for i,a in ipairs(r.agenda or {}) do if a==t then table.remove(r.agenda,i);break end end
 free(u,r,t,clock)
 local def=Tasks().definitions[t.kind]
 if def and def.release then def.release(u,r,t,reason,clock) end
 r.lastTask={id=t.id,kind=t.kind,status=reason,clock=clock}
 if r.agenda and #r.agenda==0 then r.agenda=nil end
end
function A.dropAll(u,r,reason,clock)
 while r.agenda and r.agenda[1] do A.drop(u,r,r.agenda[1],reason,clock) end
end

-- The active job ended: the agenda job nearest from here goes next.
function A.promote(u,r,station,clock)
 if r.task or not r.agenda or #r.agenda==0 then return end
 local Transport=require('src.transport')
 local best,bestLen
 for i,a in ipairs(r.agenda) do
  local route=station and Transport.route(station,a.target,clock)
  local len=station==a.target and 0 or route and #route or math.huge
  if not best or len<bestLen then best,bestLen=i,len end
 end
 local t=table.remove(r.agenda,best)
 if #r.agenda==0 then r.agenda=nil end
 r.task=t;r.taskStatus=nil;t.route=nil
 local o=Tasks().state(u).offers[t.id]
 if o then o.owner=r.id;o.state='reserved' end
 return t
end

-- Docked at a station: settle every agenda job bound here.
function A.arrive(u,r,station,clock,game)
 if not r.agenda then return end
 local Tk=Tasks()
 local i=1
 while r.agenda and r.agenda[i] do
  local t=r.agenda[i]
  local def=Tk.definitions[t.kind]
  if def and t.target==station then
   if def.complete(u,r,t,station,clock,game) then
    A.drop(u,r,t,'completed',clock)
    local o=Tk.state(u).offers[t.id]
    if o and o.order then Tk.state(u).offers[t.id]=nil end
   else i=i+1 end
  else i=i+1 end
 end
end

-- Is this drop-off on the way: in the area of a stop the ship already
-- has, or on the active job's route?
-- (every area the active route crosses counts: a drop-off at a system the
-- ship flies through anyway costs only the local leg)
local function onTheWay(r,target)
 local p=L.byId[target];if not p then return false end
 local function stop(id) local s=L.byId[L.canonical(id)];return s and s.area==p.area end
 if r.task and stop(r.task.target) then return true end
 for _,a in ipairs(r.agenda or {}) do if stop(a.target) then return true end end
 for _,id in ipairs(r.task and r.task.route or {}) do if stop(id) then return true end end
 return false
end

-- The usual job check, except a ship already flying a load doesn't wait
-- for a full run's worth of freight: the hold is going anyway.
function A.eligible(def,u,r,o,station,clock)
 r.agendaFilling=true
 local ok,result=pcall(def.eligible,u,r,o,station,clock)
 r.agendaFilling=nil
 if not ok then error(result,0) end
 return result
end
-- Loaded and about to leave: fill spare hold with more jobs from this
-- pickup whose drop-offs are on the way. Each one is prepared (and loaded)
-- through the job's own definition, so manifests, quotes and stock checks
-- are the usual ones.
function A.extend(u,r,station,clock)
 if r.player or not r.task or r.task.phase~='delivery' or r.task.kind~='transport' then return 0 end
 if r.suspendedTask or r.service then return 0 end
 local key=station..'@'..math.floor(clock)
 if r.agendaScan==key then return 0 end
 r.agendaScan=key
 local Tk=Tasks()
 local def=Tk.definitions.transport
 local Access=require('src.npc_access')
 local capabilities=Access.capabilities(r)
 if not Access.eligible(r,def,capabilities) then return 0 end
 local added=0
 for _=1,A.limit(r)-A.count(r) do
  local list={}
  for _,o in pairs(Tk.state(u).offers) do
   if o.kind=='transport' and o.state=='available' and o.source==station and o.item
    and (o.readyAt or 0)<=clock and Tk.npcMayClaim(u,o,clock)
    and onTheWay(r,o.target) and Access.eligible(r,o,capabilities)
    and A.eligible(def,u,r,o,station,clock) then
    list[#list+1]={o=o,v=def.score(u,r,o,station,clock)}
   end
  end
  table.sort(list,function(a,b) return a.v>b.v or a.v==b.v and a.o.id<b.o.id end)
  local took
  for i=1,math.min(#list,Tk.feasibleTries) do
   local o=list[i].o
   if def.feasible(u,r,o,station,clock) then
    local t=copy(o);t.phase='prepare';t.assigned=clock;t.state=nil
    if def.prepare(u,r,t,station,clock) and t.phase=='delivery' then
     o.owner=r.id;o.state='reserved'
     r.agenda=r.agenda or {};r.agenda[#r.agenda+1]=t
     r.jobsStarted=(r.jobsStarted or 0)+1
     added=added+1;took=true;break
    end
   end
  end
  if not took then break end
 end
 if added>0 then require('src.alife_trace').note(r,clock,'agenda',('holding %d jobs, loaded at %s'):format(A.count(r),station)) end
 return added
end
return A
