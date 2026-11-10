-- Reusable equipment effects. Positioning, claims and timing live in actions.
local A=require('src.npc_actions')
local Ship=require('src.ship')
local Hold=require('src.inventory.hold')
local data=require('src.data')
local O={}
function O.room(r,item)
 if r.ship.hold then return Hold.room(Hold.deserialize(r.ship.hold),item,1e9) end
 local used=0
 for id,n in pairs(r.ship.cargo or {}) do used=used+data.items[id].volume*n end
 return math.max(0,math.floor(((data.hulls[r.ship.hull].hold or 0)-used)/data.items[item].volume))
end
local function add(r,item,n)
 if r.ship.hold then
  local h=Hold.deserialize(r.ship.hold);n=Hold.add(h,item,n)
  r.ship.hold=Hold.serialize(h);r.ship.cargo=Hold.totals(h)
 else
  n=math.min(n,O.room(r,item));r.ship.cargo[item]=(r.ship.cargo[item] or 0)+n
 end
 return n
end
local function collect(ctx,target)
 local r=target.record
 local n=add(ctx.r,r.item,r.count)
 if n<=0 then return 'failed','hold full' end
 r.count=r.count-n;A.pickedUp(ctx,r.item,n)
 if r.count<=0 then A.targets[ctx.r.action.target.provider].remove(ctx,ctx.r.action.target);return 'done' end
 return 'running'
end
A.registerOperation('collect',{
 distance=function(ctx) return ctx.e and Ship.tractorRange(ctx.e)*.5+(ctx.e.halfLength or 0) or 0 end,
 offline=collect,
 online=function(ctx,target)
  if not target.entity then return A.recordOperation(ctx,function()return collect(ctx,target)end) end
  local p=target.entity
  if p.count<=0 then return 'done' end
  p.collector=ctx.e;ctx.e.tractorTarget=p;ctx.e.intent.tractor=true;ctx.e.intent.firePrimary=false
  return 'running'
 end,
 missing=function(ctx,a) return (a.progress or 0)>0 and 'done' or 'failed','target disappeared' end,
})
local function drill(ctx,target,dt)
 local record=target.record
 if record.kind~='rock' then return 'done' end
 local requested=0
 for _,id in pairs(ctx.r.ship.loadout) do
  local m=id and data.modules[id];local w=m and m.weapon
  if w and w.kind=='drill' then requested=requested+(w.powerPerSecond or 0)*dt end
 end
 local energy=A.power(ctx,dt,requested)
 for _,id in pairs(ctx.r.ship.loadout) do
  local m=id and data.modules[id];local w=m and m.weapon
  if w and w.kind=='drill' then
   local seconds=math.min(dt,energy/math.max(.001,w.powerPerSecond or 0))
   energy=energy-seconds*(w.powerPerSecond or 0)
   record.hp=record.hp-seconds*w.damage*(w.rockDamage or 1)
   if seconds>0 then record.drilled=true end
  end
 end
 if record.hp<=0 then
  record.x,record.y,record.vx,record.vy=target.x,target.y,target.vx or 0,target.vy or 0;record.clock=ctx.clock
  record.kind,record.count='loot',record.yield;return 'done'
 end
 return 'running'
end
A.registerOperation('drill',{
 keepDistance=true,
 distance=function(ctx,target) return (target.radius or 0)+(ctx.e and ctx.e.noseX or 60)+25 end,
 offline=drill,
 online=function(ctx,target,dt)
  if not target.entity then return A.recordOperation(ctx,function()return drill(ctx,target,dt)end) end
  local e,rock=ctx.e,target.entity
  if rock.dead or rock.removed or target.record.kind~='rock' then return 'done' end
  local x,y=e.body:getPosition();local angle=e.body:getAngle()
  local diff=(math.atan2(target.y-y,target.x-x)-angle+math.pi)%(2*math.pi)-math.pi
  local hit=ctx.game:raycast(x+math.cos(angle)*e.halfLength,y+math.sin(angle)*e.halfLength,target.x,target.y,e.team)
  e.intent.firePrimary=math.abs(diff)<.18 and (not hit or hit.entity==rock)
  e.intent.targetDist=nil
  return 'running'
 end,
})
require('src.events').on('pickup',function(e,item,n,stack)
 local r=e.alifeRecord
 if r and e.alifeGame then
  A.notifyPickup({game=e.alifeGame,u=e.alifeGame.universe,r=r,e=e,clock=e.alifeGame.universe.clock},item,n,stack)
 end
 local a=r and r.action
 if a and a.kind=='work' then
  a.progress=(a.progress or 0)+n
  local p=e.tractorTarget
  if a.operation=='collect' and p and p.looseId==a.target.id and p.count<=0 then a.completed=true end
 end
end)
return O
