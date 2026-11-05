-- Role-neutral task board. Definitions execute code; saves contain plain records.
local copy=require('src.persistence').copy
local Tasks={definitions={}}
function Tasks.register(kind,definition)
 assert(not Tasks.definitions[kind],'duplicate task kind')
 Tasks.definitions[kind]=definition
end
function Tasks.state(u)
 u.tasks=u.tasks or {offers={},nextId=0}
 return u.tasks
end
function Tasks.post(u,offer)
 assert(Tasks.definitions[offer.kind],'unknown task kind')
 local state=Tasks.state(u)
 state.nextId=state.nextId+1
 local o=copy(offer);o.id='task/'..state.nextId;o.state='available'
 state.offers[o.id]=o
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
 local t=r.task or r.suspendedTask
 if not t then return end
 local o=Tasks.state(u).offers[t.id]
 if o and o.owner==r.id then
  o.owner=nil;o.state='available';o.readyAt=clock+(o.cooldown or 120)
 end
 r.lastTask={id=t.id,kind=t.kind,status=reason,clock=clock}
 r.task=nil;r.suspendedTask=nil;r.suspendedTaskStatus=nil
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
 for _,o in pairs(Tasks.state(u).offers) do
  local r=o.owner and u.npcs[o.owner]
  local task=r and (r.task or r.suspendedTask)
  if o.owner and (not r or r.state=='dead' or r.state=='escaped' or not task or task.id~=o.id) then
   o.owner=nil;o.state='available';o.readyAt=clock+(o.cooldown or 120)
  end
 end
end
function Tasks.choose(u,r,station,clock)
 if not Tasks.resolve(u,r) then return end
 if r.task then return r.task end
 Tasks.clean(u,clock)
 local best,score
 for _,o in pairs(Tasks.state(u).offers) do
  local def=Tasks.definitions[o.kind]
  if o.state=='available' and (o.readyAt or 0)<=clock and def and def.roles[r.role]
   and def.eligible(u,r,o,station,clock) then
   local value=def.score and def.score(u,r,o,station,clock) or 0
   if not best or value>score or value==score and o.id<best.id then best,score=o,value end
  end
 end
 if not best then r.taskStatus='waiting for work';return end
 local t=copy(best);t.phase='prepare';t.assigned=clock;t.state=nil
 -- Prepare may reject a task (e.g. a full grid hold). Never reserve failed work.
 local def=Tasks.definitions[t.kind]
 if def.prepare and not def.prepare(u,r,t,station,clock) then return end
 best.owner=r.id;best.state='reserved'
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
 if not Tasks.resolve(u,r) then return false end
 local t=r.task
 if not t then return end
 local def=Tasks.definitions[t.kind]
 if def.complete(u,r,t,station,clock,game) then
  Tasks.release(u,r,'completed',clock)
  return true
 end
end
return Tasks
