-- Slow planning and fast actuation share one controller. No physics is skipped.
local T=require('src.tuning')
local Nav=require('src.local_navigation')
local S={}
local function phase(e)
 local id=tonumber(tostring(e.alifeId or e.id or 0):match('%d+$')) or 0
 return id*.61803398875%1
end
local function deadline(e,now,interval,previous)
 if previous then return now+interval end
 return now+interval-(now-phase(e)*interval)%interval
end
local function driver(e)
 local stop=e.route and e.route[e.routeIndex or 1]
 return stop and stop.driver
end
local function invalid(target)
 return target and (target.dead or target.removed or target.dockState or target.driverProtected)
end
local function actuate(game,e,dt,AI)
 local control=e.aiVelocity
 if control then
  if control.combat then AI.driveCombatVelocity(e,control.x,control.y,control.throttle)
  else AI.driveVelocity(e,control.x,control.y,control.mx,control.my,control.throttle) end
 end
 local boost=e.aiBoostPlan
 if boost then Nav.boost(e,boost.x,boost.y,boost.want,boost.distance,boost.clear,boost.danger,boost.allow) end
 local target=e.aiAimTarget
 if target and not invalid(target) then
  local x,y=e.body:getPosition();local vx,vy=e.body:getLinearVelocity()
  local tx,ty=target.body:getPosition();local tvx,tvy=target.body:getLinearVelocity()
  local dx,dy=tx-x,ty-y;local distance=math.sqrt(dx*dx+dy*dy)
  local ai=e.def.ai;local slot=e.weapons[1]
  local speed=slot and slot.ammo and require('src.data').items[slot.ammo].shot.speed or 3000
  local lead=distance/speed*ai.accuracy
  local it=e.intent
  it.aimX=tx+(tvx-vx)*lead+(e.aiAimJitter and e.jitterX or 0)
  it.aimY=ty+(tvy-vy)*lead+(e.aiAimJitter and e.jitterY or 0)
  it.targetDist=distance
  local on,off=ai.burstOn or 1,ai.burstOff or 1.4
  e.burstClock=((e.burstClock or 0)+dt)%(on+off)
  local a=e.body:getAngle();local ax,ay=it.aimX-x,it.aimY-y
  local length=math.max(.001,math.sqrt(ax*ax+ay*ay))
  local facing=e.aiAimTrade or e.hull.mount=='turret' or (math.cos(a)*ax+math.sin(a)*ay)/length>.95
  local fire=(not e.aiAimTrade or distance<ai.range) and e.burstClock<on and facing
  it.firePrimary=fire
  if not e.aiAimTrade then it.fireSecondary,it.fireTertiary=fire,fire end
  if require('src.robbery').pending(e) then it.firePrimary,it.fireSecondary,it.fireTertiary=false,false,false end
 end
end
function S.update(game,e,dt,AI,plan)
 local now=game.universe.clock
 local r=e.alifeId and game.universe.npcs[e.alifeId]
 local g=driver(e)
 local urgent=not e.aiNextPlan or e.aiRoute~=e.route or e.aiRouteIndex~=e.routeIndex
  or e.aiTask~=(r and r.task) or e.aiAction~=(r and r.action)
  or e.aiHit~=e.lastHitTime and not e.combatTarget and not e.aggressor
  or e.aiAggressor~=e.aggressor or e.aiFuel~=e.fuelStatus
  or e.aiAsked~=e.asked or invalid(e.combatTarget) or invalid(e.aiAimTarget)
  or e.aiDriver~=g or e.aiDriverShip~=(g and g.driverShip)
  or r and r.action and (r.action.completed or r.action.failure)
 if not urgent and now<e.aiNextPlan then actuate(game,e,dt,AI);return end
 e.aiDecision=urgent or not e.aiNextDecision or now>=e.aiNextDecision
 if e.aiDecision then
  e.aiNextDecision=deadline(e,now,T.npcDecisionInterval,e.aiNextDecision)
  if urgent then e.securityThink=0 end
 end
 local elapsed=e.aiLastPlan and math.max(dt,now-e.aiLastPlan) or dt
 local previousAction=r and r.action
 e.aiControlDT=dt
 e.aiVelocity,e.aiBoostPlan,e.aiAimTarget=nil,nil,nil
 e.aiAimJitter,e.aiAimTrade,e.aiApproach,e.aiCombat=nil,nil,nil,nil
 plan(game,e,elapsed)
 r=e.alifeId and game.universe.npcs[e.alifeId]
 g=driver(e)
 local action=r and r.action
 local working=action and (action.kind=='work' or action.kind=='approach')
 local danger=e.navigation and e.navigation.danger or 0
 local interval=(e.aiCombat or e.combatTarget or e.aggressor or e.asked or e.drone) and T.npcCombatInterval
  or (working or e.aiApproach or danger>.7) and T.npcControlInterval or T.npcCruiseInterval
 e.aiNextPlan=deadline(e,now,interval,e.aiNextPlan);e.aiLastPlan=now
 e.aiRoute,e.aiRouteIndex,e.aiTask,e.aiAction=e.route,e.routeIndex,r and r.task,r and r.action
 e.aiHit,e.aiAggressor,e.aiFuel,e.aiAsked=e.lastHitTime,e.aggressor,e.fuelStatus,e.asked
 e.aiDriver,e.aiDriverShip=g,g and g.driverShip
 if previousAction and r and not r.action then
  -- Completing a hold/work action opens the next decision immediately.
  e.aiNextPlan,e.aiNextDecision=nil,nil
 end
end
return S
