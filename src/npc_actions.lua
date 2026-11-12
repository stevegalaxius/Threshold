-- Shared execution. Saved actions contain data; registries contain functions.
-- Jobs request actions, target providers resolve world objects, and operations
-- apply equipment effects. Neither jobs nor operations steer or advance routes.
local T=require('src.tuning')
local Trace=require('src.alife_trace')
local A={definitions={},targets={},operations={}}
local function register(registry,name,definition)
 assert(not registry[name],'duplicate NPC action extension: '..name)
 registry[name]=definition
end
function A.register(name,definition) assert(type(definition.update)=='function','action needs update');register(A.definitions,name,definition) end
function A.registerTarget(name,definition) assert(type(definition.resolve)=='function','target needs resolve');register(A.targets,name,definition) end
function A.registerOperation(name,definition) assert(type(definition.online)=='function' and type(definition.offline)=='function','operation needs online and offline effects');register(A.operations,name,definition) end
local function key(spec)
 local t=spec.target or {}
 return spec.key or table.concat({spec.kind,spec.operation or '',t.provider or '',t.source or '',tostring(t.id or '')},'/')
end
function A.resolve(ctx,action)
 local target=action.target
 local provider=target and A.targets[target.provider]
 return provider and provider.resolve(ctx,target) or nil
end
function A.available(ctx,target)
 local owner=target.record and target.record.actionOwner
 if not owner or owner==ctx.r.id then return true end
 local r=ctx.u.npcs and ctx.u.npcs[owner]
 return not r or r.state=='dead' or r.state=='escaped' or not r.action or r.action.pausedAt~=nil or r.action.key~=target.record.actionKey
end
local function release(ctx,action)
 local target=A.resolve(ctx,action)
 if target and target.record and target.record.actionOwner==ctx.r.id then target.record.actionOwner=nil;target.record.actionKey=nil end
 if ctx.e then
  ctx.e.tractorTarget=nil;ctx.e.intent.tractor=false;ctx.e.intent.firePrimary=false
  ctx.e.recoveryAim=nil
  if ctx.e.recoveryWeapon then
   ctx.e.intent.fireSecondary,ctx.e.intent.fireTertiary=false,false
   ctx.e.recoveryWeapon,ctx.e.recoveryTarget=nil,nil
  end
 end
end
-- Offline, a work or approach move (out to a wreck, loot, a rock) goes
-- round the planet, not through it. It used to be a straight line from
-- where the ship was to the target: for a target on the far side of Mars
-- that ran through the rock, the ship was drawn there and woke there,
-- inside the planet, and died. It now follows the arc round the planet,
-- easing its altitude from one end to the other, and never dips into the
-- planet or its pull band.
local function planetOf(r)
 local f=r and require('src.fields')[r.area or '']
 local R=f and f.planetR
 if not R or R<=0 then return nil end
 return R+math.min(T.surfacePullRange,R*.5)+500
end
local function wrap(a) return (a+math.pi)%(2*math.pi)-math.pi end
local function arcPoint(r,ox,oy,gx,gy,p)
 local safe=planetOf(r)
 if not safe then return ox+(gx-ox)*p,oy+(gy-oy)*p end
 local r0,r1=math.sqrt(ox*ox+oy*oy),math.sqrt(gx*gx+gy*gy)
 -- a target down in the band (a surface site) is still reached
 local floor=math.min(safe,r0,r1)
 local x,y=ox+(gx-ox)*p,oy+(gy-oy)*p
 -- the straight line is fine while it stays clear of the planet
 local minR=math.huge
 local dx,dy=gx-ox,gy-oy;local len2=dx*dx+dy*dy
 if len2>1 then
  local t=math.max(0,math.min(1,-(ox*dx+oy*dy)/len2))
  minR=math.sqrt((ox+dx*t)^2+(oy+dy*t)^2)
 end
 if minR>=floor then return x,y end
 local a0,a1=math.atan2(oy,ox),math.atan2(gy,gx)
 local a=a0+wrap(a1-a0)*p
 local rad=math.max(floor,r0+(r1-r0)*p)
 return math.cos(a)*rad,math.sin(a)*rad
end
A.arcPoint=arcPoint
-- Loose cargo and wrecks drift down through a planet's pull band toward the
-- surface. A hauler sent after them is dragged into the rock with them, so
-- anything below the safe altitude is not worth fetching (surface-mining
-- moons excepted: their ground is meant to be worked).
function A.sinking(r,x,y)
 local f=r and require('src.fields')[r.area or '']
 if not f or f.surfaceMine then return false end
 local safe=planetOf(r)
 return safe and x*x+y*y<safe*safe or false
end
-- How far that move really is (round the planet when it has to go round).
function A.arcLength(r,ox,oy,gx,gy)
 local n,len=16,0
 local px,py=ox,oy
 for i=1,n do local x,y=arcPoint(r,ox,oy,gx,gy,i/n);len=len+math.sqrt((x-px)^2+(y-py)^2);px,py=x,y end
 return len
end
function A.position(r,clock)
 local a=r.action
 if not a or a.pausedAt then return end
 if a.rebase then return a.rebase.x,a.rebase.y end
 if not a.origin or not a.goal then return end
 local p=math.max(0,math.min(1,(clock-a.started)/math.max(.001,(a.arriveAt or a.started)-a.started)))
 return arcPoint(r,a.origin.x,a.origin.y,a.goal.x,a.goal.y,p)
end
function A.actorPosition(ctx)
 if ctx.e then return ctx.e.body:getPosition() end
 return require('src.alife').point(ctx.r,ctx.clock)
end
local function preserve(ctx,x,y)
 if not x or not ctx.r.route then return end
 local r=ctx.r;r.offset=nil
 local bx,by=require('src.alife').point(r,ctx.clock)
 if bx then r.offset={x=x-bx,y=y-by,progress=math.max(0,math.min(1,(ctx.clock-(r.depart or ctx.clock))/math.max(.01,(r.arrive or ctx.clock)-(r.depart or ctx.clock))))} end
end
local function finish(ctx,status,reason)
 local r,a=ctx.r,ctx.r.action;if not a then return end
 local x,y=A.position(r,ctx.clock)
 if ctx.e then x,y=ctx.e.body:getPosition() end
 release(ctx,a)
 local def=A.definitions[a.kind]
 r.action=nil
 preserve(ctx,x,y)
 if (a.kind=='work' or a.kind=='approach') and r.state=='travel' then require('src.queue').leg(r) end
 r.lastAction={kind=a.kind,operation=a.operation,target=require('src.persistence').copy(a.target),status=status,reason=reason,clock=ctx.clock}
 Trace.note(r,ctx.clock,'action',a.kind..(a.operation and ':'..a.operation or '')..' '..status..(reason and ': '..reason or ''))
 if def and def.finish then def.finish(ctx,a,status,reason) end
 local task=r.task and require('src.tasks').definitions[r.task.kind]
 if task and task.actionEnded then task.actionEnded(ctx,a,status,reason) end
end
function A.cancel(ctx,reason) finish(ctx,'cancelled',reason) end
function A.complete(ctx) finish(ctx,'done') end
function A.pause(ctx,reason)
 local a=ctx.r.action;if not a or a.pausedAt then return end
 local x,y=A.position(ctx.r,ctx.clock)
 if ctx.e then x,y=ctx.e.body:getPosition() end
 release(ctx,a);a.pausedAt=ctx.clock;a.pauseReason=reason;a.rebase=nil
 preserve(ctx,x,y)
end
function A.request(ctx,spec)
 assert(A.definitions[spec.kind],'unknown NPC action '..tostring(spec.kind))
 if spec.operation then assert(A.operations[spec.operation],'unknown NPC operation '..spec.operation) end
 if spec.target then assert(A.targets[spec.target.provider],'unknown NPC target provider '..tostring(spec.target.provider)) end
 local job=ctx.r.task and (ctx.r.task.id or ctx.r.task.kind)
 local current=ctx.r.action
 if current and current.key==key(spec) and current.job==job then return current end
 local x,y
 if A.definitions[spec.kind].positioning and not ctx.e then x,y=A.actorPosition(ctx) end
 if current then A.cancel(ctx,'replanned') end
 local a=require('src.persistence').copy(spec)
 a.key=key(spec);a.job=job;a.started=ctx.clock;a.lastClock=ctx.clock
 if x then a.rebase={x=x,y=y} end
 ctx.r.action=a
 local def=A.definitions[a.kind]
 if def.start then def.start(ctx,a) end
 return a
end
-- Engine-side effects can finish an action before its next update (e.g. a
-- drilled body becomes a new loose record during physics reaping).
function A.targetResult(u,record,success,reason)
 local r=record.actionOwner and u.npcs[record.actionOwner]
 local a=r and r.action
 if a and a.target and a.target.id==record.id then
  if success then a.completed=true else a.failure=reason or 'target destroyed' end
 end
end
function A.step(ctx)
 local a=ctx.r.action;if not a then return false end
 if a.job~=(ctx.r.task and (ctx.r.task.id or ctx.r.task.kind)) then A.cancel(ctx,'job changed');return false end
 if a.pausedAt then
  a.pausedAt,a.pauseReason=nil,nil;a.origin,a.goal,a.arriveAt=nil,nil,nil
  a.started=ctx.clock;a.lastClock=ctx.clock;a.lastWork=ctx.clock
 end
 local mode=ctx.e and 'online' or 'offline'
 if a.mode and a.mode~=mode and A.definitions[a.kind].positioning then
  local x,y=A.actorPosition(ctx)
  a.rebase=x and {x=x,y=y} or nil;a.origin,a.goal,a.arriveAt=nil,nil,nil
  a.started=ctx.clock;a.lastClock=ctx.clock;a.lastWork=ctx.clock
 end
 a.mode=mode
 if a.completed then finish(ctx,'done');return true end
 if a.failure then finish(ctx,'failed',a.failure);return true end
 local elapsed=math.max(0,ctx.clock-a.lastClock);a.lastClock=ctx.clock
 local def=A.definitions[a.kind]
 local status,reason=def.update(ctx,a,elapsed)
 assert(status=='running' or status=='done' or status=='failed' or status=='delegate','NPC action returned an invalid status: '..tostring(status))
 if status=='done' or status=='failed' then finish(ctx,status,reason) end
 return status~='delegate'
end
-- One approach/hold controller, used by every interaction and idle action.
function A.move(ctx,target,stand,keepDistance)
 local e,AI=ctx.e,ctx.AI
 local x,y=e.body:getPosition();local dx,dy=target.x-x,target.y-y
 local d=math.sqrt(dx*dx+dy*dy);local ux,uy=dx/math.max(1,d),dy/math.max(1,d)
 if not keepDistance and d<=stand+25 then
  local vx,vy=e.body:getLinearVelocity()
  AI.driveVelocity(e,vx,vy,ux,uy,e.def.ai.throttle)
  e.intent.aimX,e.intent.aimY=target.x,target.y
  return true
 end
 local Nav=require('src.local_navigation')
 local gx,gy=target.x-ux*stand,target.y-uy*stand
 local wx,wy=Nav.waypoint(ctx.game,e,gx,gy,{ignore=target.entity,cx=target.x,cy=target.y,stand=stand})
 local rx,ry=wx-x,wy-y;local leg=math.max(.001,math.sqrt(rx*rx+ry*ry))
 local want=math.min(require('src.npc').liveCruise(e),leg*.8,math.sqrt(2*Nav.brakeAccel(e)*leg))
 local mx,my,scale=Nav.steer(ctx.game,e,rx/leg,ry/leg,want,target.vx or 0,target.vy or 0,
  {ignore=target.entity,brake=Nav.brakeAccel(e),distance=leg})
 AI.driveVelocity(e,(target.vx or 0)+mx*want*scale,(target.vy or 0)+my*want*scale,mx,my,e.def.ai.throttle)
 e.intent.aimX,e.intent.aimY=target.x,target.y
 return d<=stand+25
end
local function freezeRoute(r,elapsed)
 if r.state=='travel' then r.depart=r.depart+elapsed;r.arrive=r.arrive+elapsed
 elseif r.state=='idle' then r.untilTime=(r.untilTime or 0)+elapsed end
end
local function interaction(ctx,a,elapsed,approachOnly)
 local target=A.resolve(ctx,a)
 if not target then
  local op=a.operation and A.operations[a.operation]
  if op and op.missing then return op.missing(ctx,a) end
  return 'failed','target disappeared'
 end
 if target.done then return 'done' end
 if not A.available(ctx,target) then return 'failed','target claimed' end
 local provider=a.target and a.target.provider
 local policy=provider and A.targets[provider]
 if policy and policy.safe then
  if not policy.safe(ctx,target) then return 'failed','target inside the mined body' end
 elseif (provider=='loot' or provider=='resource') and A.sinking(ctx.r,target.x,target.y) then return 'failed','target sinking into the planet' end
 if target.record then target.record.actionOwner=ctx.r.id;target.record.actionKey=a.key end
 local op=a.operation and A.operations[a.operation]
 local stand=a.distance or (op and op.distance and op.distance(ctx,target)) or 0
 if ctx.r.state=='docked' and not (op and op.allowDocked) then return 'failed','undock before approaching a work target' end
 if ctx.e then
  freezeRoute(ctx.r,elapsed)
  local keep=a.keepDistance or op and op.keepDistance
  if type(keep)=='function' then keep=keep(ctx,target) end
  local near=ctx.r.state=='docked' and op.allowDocked or A.move(ctx,target,stand,keep)
  -- Standoff is a steering goal, not an equipment gate. Moving targets and
  -- orbital drag can leave a persistent position error inside usable range.
  if op and op.inRange and not approachOnly then near=op.inRange(ctx,target,a) end
  a.phase=near and 'working' or 'approaching'
  if not near then return 'running' end
  if approachOnly then return 'done' end
  local dt=math.min(ctx.dt or elapsed,op.maxStep or 12)
  return op.online(ctx,target,dt,a)
 end
 if not a.origin then
  local x,y=A.actorPosition(ctx);if not x then return 'failed','no position' end
  a.rebase=nil
  a.origin={x=x,y=y};a.started=ctx.clock
  local d=A.arcLength(ctx.r,x,y,target.x,target.y)
  a.arriveAt=ctx.clock+math.max(1,(d-stand)/math.max(1,ctx.r.speed))
 end
 local dx,dy=target.x-a.origin.x,target.y-a.origin.y
 local d=math.max(1,math.sqrt(dx*dx+dy*dy))
 a.goal={x=target.x-dx/d*stand,y=target.y-dy/d*stand}
 freezeRoute(ctx.r,elapsed)
 if ctx.clock<a.arriveAt then a.phase='approaching';return 'running' end
 a.phase='working'
 if approachOnly then return 'done' end
 local dt=math.min(math.max(0,ctx.clock-(a.lastWork or a.arriveAt)),op.maxStep or 12)
 a.lastWork=ctx.clock
 return op.offline(ctx,target,dt,a)
end
A.register('approach',{positioning=true,update=function(ctx,a,dt) return interaction(ctx,a,dt,true) end})
A.register('work',{positioning=true,update=function(ctx,a,dt) return interaction(ctx,a,dt,false) end})
A.registerTarget('location',{resolve=function(ctx,t)
 local L=require('src.locations');if not L.byId[t.id] then return end
 local x,y=L.inspectionPosition(t.id,ctx.clock);local vx,vy=L.velocity(t.id,ctx.clock)
 local station=L.get(t.id).kind=='station'
 if station and ctx.e and ctx.game.locationEntity then
  local body=ctx.game:locationEntity(t.id)
  if body then x,y,vx,vy=require('src.security').inspectionPoint(ctx.game,body,ctx.e) end
 end
 return {x=x,y=y,vx=vx,vy=vy,station=station}
end})
A.register('hold',{update=function(ctx,a)
 if not a.fromJob then a.untilTime=require('src.npc').readyAt(ctx.r) end
 if ctx.clock>=(a.untilTime or math.huge) then return 'done' end
 if ctx.e then
  local target=A.resolve(ctx,a);if not target then return 'failed','location disappeared' end
  local phase=(tonumber(ctx.r.id:match('%d+$')) or 1)*2.3999632297
  local spacing=(ctx.e.halfLength or 60)+120
  if not target.station then target.x,target.y=target.x+math.cos(phase)*spacing,target.y+math.sin(phase)*spacing end
  A.move(ctx,target,0,true)
 end
 return 'running'
end})
local function startRoute(ctx,a)
 assert(a.target and a.target.provider=='location','route action requires a location target')
 if not require('src.npc').beginRoute(ctx,a) then a.failure='no route' end
end
local function route(ctx)
 if ctx.e then ctx.AI.trade(ctx.game,ctx.e,ctx.dt);return 'running' end
 return 'delegate' -- common NPC route/dock lifecycle advances the graph
end
A.register('travel',{route=true,start=startRoute,update=route})
A.register('dock',{route=true,start=startRoute,update=route})
-- Equipment effects report transfers; the active job decides what to track.
function A.notifyPickup(ctx,item,n,stack)
 local work=ctx.r.task and require('src.tasks').definitions[ctx.r.task.kind]
 if work and work.pickedUp then work.pickedUp(ctx,item,n,stack) end
end
function A.pickedUp(ctx,item,n,stack)
 if ctx.e then require('src.events').emit('pickup',ctx.e,item,n,stack)
 else A.notifyPickup(ctx,item,n,stack) end
end
-- Remote operations spend only their extra equipment load; ordinary upkeep
-- and movement are already charged by the common fuel update.
function A.power(ctx,dt,requested)
 return require('src.reactor_fuel').withRecord(ctx.r,function(e,stats)
  -- The common fuel update has already generated power for this interval.
  -- Work spends that capacitor; it cannot run a second reactor timestep.
  local delivered=math.min(math.max(0,requested),e.power or 0)
  e.power=math.max(0,(e.power or 0)-delivered)
  return delivered
 end)
end
-- An online actor may work an authoritative record outside the physics band.
-- Synchronize its inventory once around the same record operation.
function A.recordOperation(ctx,fn)
 if not ctx.e then return fn() end
 local e,r=ctx.e,ctx.r;local Hold=require('src.inventory.hold')
 r.ship.cargo=require('src.persistence').copy(e.cargo)
 r.ship.hold=e.hold and Hold.serialize(e.hold);r.ship.fuelCharge=e.fuelCharge;r.power=e.power
 local status,reason=fn()
 e.cargo=require('src.persistence').copy(r.ship.cargo)
 if r.ship.hold then e.hold=Hold.deserialize(r.ship.hold) end
 e.fuelCharge=r.ship.fuelCharge;e.power=r.power
 require('src.ship').updateMass(e)
 return status,reason
end
return A
