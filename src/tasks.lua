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
function Tasks.release(u,r,reason,clock)
 local t=r.task
 if not t then return end
 local o=Tasks.state(u).offers[t.id]
 if o and o.owner==r.id then
  o.owner=nil;o.state='available';o.readyAt=clock+(o.cooldown or 120)
 end
 r.lastTask={id=t.id,kind=t.kind,status=reason,clock=clock}
 r.task=nil
end
function Tasks.clean(u,clock)
 for _,o in pairs(Tasks.state(u).offers) do
  local r=o.owner and u.npcs[o.owner]
  if o.owner and (not r or r.state=='dead' or r.state=='escaped' or not r.task or r.task.id~=o.id) then
   o.owner=nil;o.state='available';o.readyAt=clock+(o.cooldown or 120)
  end
 end
end
function Tasks.choose(u,r,station,clock)
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
function Tasks.arrive(u,r,station,clock)
 local t=r.task
 if not t then return end
 local def=assert(Tasks.definitions[t.kind],'unknown saved task kind')
 if def.complete(u,r,t,station,clock) then
  Tasks.release(u,r,'completed',clock)
  return true
 end
end
return Tasks
