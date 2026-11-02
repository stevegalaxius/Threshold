-- Local steering only: authored graph routes and destinations stay unchanged.
local Sweep=require('src.collision_prediction')
local T=require('src.tuning')
local Nav={}
local pi,cos,sin,sqrt,abs,min,max=math.pi,math.cos,math.sin,math.sqrt,math.abs,math.min,math.max
local ANGLES={0,.35,-.35,.7,-.7,1.1,-1.1,pi/2,-pi/2,2.2,-2.2,2.65,-2.65,pi}
local function wrap(a)return (a+pi)%(2*pi)-pi end
local function obstacles(game,e,reach,ignore,allowSurface)
 local x,y=e.body:getPosition();local result={}
 game.world:queryBoundingBox(x-reach,y-reach,x+reach,y+reach,function(fixture)
  local body=fixture:getBody();local o=fixture:getUserData() or body:getUserData()
  if body~=e.body and o~=ignore and not fixture:isSensor() and not (o and (o.dead or o.removed))
   and not (allowSurface and o and o.kind=='planet') then
   local shape=fixture:getShape();local kind=shape:getType()
   local vx,vy=body:getLinearVelocity()
   if kind=='circle' then
    local cx,cy=body:getWorldPoint(shape:getPoint())
    result[#result+1]={x=cx,y=cy,r=shape:getRadius(),vx=vx,vy=vy}
   elseif kind=='polygon' or kind=='edge' or kind=='chain' then
    local points={body:getWorldPoints(shape:getPoints())}
    if kind=='chain' then
     for i=1,#points-2,2 do result[#result+1]={p={points[i],points[i+1],points[i+2],points[i+3]},vx=vx,vy=vy} end
    else result[#result+1]={p=points,vx=vx,vy=vy} end
   end
  end
  return true
 end)
 -- Gas giants have no fixture, but transit traffic should stay above the clouds.
 local w=game.well
 if w and w.gas and not allowSurface then result[#result+1]={x=w.x,y=w.y,r=w.radius+T.surfacePullRange,vx=0,vy=0,virtual=true} end
 for _,o in ipairs(result) do
  if o.r then o.minx,o.miny,o.maxx,o.maxy=o.x-o.r,o.y-o.r,o.x+o.r,o.y+o.r
  else
   o.minx,o.miny,o.maxx,o.maxy=math.huge,math.huge,-math.huge,-math.huge
   for i=1,#o.p,2 do
    o.minx,o.maxx=min(o.minx,o.p[i]),max(o.maxx,o.p[i])
    o.miny,o.maxy=min(o.miny,o.p[i+1]),max(o.maxy,o.p[i+1])
   end
  end
 end
 return result
end
function Nav.steer(game,e,ux,uy,want,flowX,flowY,options)
 options=options or {};flowX,flowY=flowX or 0,flowY or 0
 local length=sqrt(ux*ux+uy*uy)
 if length<.0001 then return 0,0,1,0 end
 ux,uy=ux/length,uy/length
 local goal=math.atan2(uy,ux)
 local old=e.navigation
 if old and old.untilTime>(game.time or 0) and old.ignore==options.ignore and old.surface==options.allowSurface
  and abs(wrap(goal-old.goal))<.2 and abs(want-old.want)<100
  and abs((options.distance or 0)-(old.distance or 0))<500 then
  return cos(old.heading),sin(old.heading),old.scale,old.danger,old.clear
 end
 local x,y=e.body:getPosition();local vx,vy=e.body:getLinearVelocity()
 local speed=sqrt((vx-flowX)^2+(vy-flowY)^2)
 local brake=max(1,options.brake or 100)
 local horizon=min(10,max(2,options.horizon or 4.5)+speed/brake*.4)
 local reach=min(18000,(max(want,speed)+sqrt(vx*vx+vy*vy)+400)*horizon+e.halfLength)
 local geometry=obstacles(game,e,reach,options.ignore,options.allowSurface)
 local a=e.body:getAngle();local c,s=cos(a),sin(a)
 local radius=e.hull.radius+T.aiClearance
 local spine=e.spine or {0,0}
 local offsets={spine[1],0,spine[2]}
 local function freeTime(dx,dy,ahead,physicalOnly)
  ahead=ahead or horizon
  local time=ahead
  for _,o in ipairs(geometry) do
   if not physicalOnly or not o.virtual then
   for _,offset in ipairs(offsets) do
    local hit=Sweep.sweepCircle(x+c*offset,y+s*offset,radius,o,dx-o.vx,dy-o.vy,time)
    if hit and hit<time then time=hit;if time==0 then return 0 end end
   end
   end
  end
  return time
 end
 local current=freeTime(vx,vy,nil,true)
 local best,bestScore
 local side=old and old.side or 1
 for _,turn in ipairs(ANGLES) do
  local heading=goal+turn
  local preference=old and -.3*abs(wrap(heading-old.heading)) or 0
  if turn*side>0 then preference=preference+.12 end
  -- Skip a sweep only when even a fully clear path cannot beat the leader.
  -- This preserves heading hysteresis without testing every angle in open space.
  if not best or 4+2*cos(turn)+preference>bestScore then
   local dx,dy=cos(heading),sin(heading)
   local ahead=options.distance and min(horizon,max(.25,options.distance/max(1,want))) or horizon
   local time=freeTime(flowX+dx*want,flowY+dy*want,ahead)
   local fraction=time/ahead
   local clear=time>=ahead
   local score=(clear and 4+2*cos(turn) or -3+3*fraction+.5*cos(turn))+preference
   if not best or score>bestScore then
    best,bestScore={heading=heading,clear=clear,fraction=fraction,
     side=abs(turn)>.1 and (turn>0 and 1 or -1) or side},score
   end
  end
 end
 best.goal=goal;best.want=want;best.distance=options.distance;best.ignore=options.ignore;best.surface=options.allowSurface
 best.danger=1-current/horizon
 best.scale=best.clear and 1 or max(.15,min(.65,best.fraction*.8))
 if best.danger>.7 and speed>100 then best.scale=min(best.scale,.5) end
 best.untilTime=(game.time or 0)+T.aiSteerEvery
 e.navigation=best
 return cos(best.heading),sin(best.heading),best.scale,best.danger,best.clear
end
function Nav.brakeAccel(e)
 local s=e.stats
 local side=e.hull.helm~='turn' and s.sideThrust*T.sideScale or 0
 local force=max(s.retroThrust*T.sideScale,side,s.thrust*.5)*T.FORCE_PER_KN*T.thrustScale
 local buff=e.laneBuff and 1+(T.laneThrust-1)*e.laneBuff or 1
 return max(1,force*buff/e.body:getMass())
end

-- Boost only into a clear corridor, with the nose aligned and stopping room.
function Nav.boost(e,dx,dy,want,distance,clear,danger,allow)
 local it=e.intent
 if not allow or not clear or danger>.15 or e.stats.thrust<=0 or it.thrust<.5 then e.aiBoost=false;it.boost=false;return end
 local a=e.body:getAngle();local facing=cos(a)*dx+sin(a)*dy
 local vx,vy=e.body:getLinearVelocity()
 local speed=(vx-(e.flowX or 0))*dx+(vy-(e.flowY or 0))*dy
 local brake=Nav.brakeAccel(e)
 local stopping=max(0,speed)^2/(2*max(1,brake))
 local threshold=e.aiBoost and .98 or .8
 e.aiBoost=facing>.97 and distance>stopping+T.aiBoostStopMargin and speed<want*threshold
 it.boost=e.aiBoost
end
return Nav
