-- Local detours and steering preserve authored graph routes and destinations.
local Sweep=require('src.collision_prediction')
local T=require('src.tuning')
local Nav={}
local pi,cos,sin,sqrt,abs,min,max=math.pi,math.cos,math.sin,math.sqrt,math.abs,math.min,math.max
local ANGLES={0,.35,-.35,.7,-.7,1.1,-1.1,pi/2,-pi/2,2.2,-2.2,2.65,-2.65,pi}
local function wrap(a)return (a+pi)%(2*pi)-pi end
-- All nearby NPCs can query the same fixture. Reuse world geometry until
-- its transform or velocity changes; weak keys release destroyed fixtures.
local fixtureGeometry=setmetatable({},{__mode='k'})
local function geometryFor(fixture,body,state)
 local x,y,angle,vx,vy,loose=state.x,state.y,state.angle,state.vx,state.vy,state.loose
 local old=fixtureGeometry[fixture]
 if old and old.x==x and old.y==y and old.angle==angle and old.vx==vx and old.vy==vy and old.loose==loose then return old.shapes end
 local result={};local shape=fixture:getShape();local kind=shape:getType()
 if kind=='circle' then
  local cx,cy=body:getWorldPoint(shape:getPoint())
  result[1]={x=cx,y=cy,r=shape:getRadius(),vx=vx,vy=vy,loose=loose}
 elseif kind=='polygon' or kind=='edge' or kind=='chain' then
  local points={body:getWorldPoints(shape:getPoints())}
  if kind=='chain' then
   for i=1,#points-2,2 do result[#result+1]={p={points[i],points[i+1],points[i+2],points[i+3]},vx=vx,vy=vy,loose=loose} end
  else result[1]={p=points,vx=vx,vy=vy,loose=loose} end
 end
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
 fixtureGeometry[fixture]={x=x,y=y,angle=angle,vx=vx,vy=vy,loose=loose,shapes=result}
 return result
end
local function obstacles(game,e,reach,ignore,allowSurface,staticOnly)
 local x,y=e.body:getPosition();local result={};local seen={};local bodies={}
 game.world:queryBoundingBox(x-reach,y-reach,x+reach,y+reach,function(fixture)
  -- Box2D reports a chain fixture once per overlapping child edge. Expanding
  -- the whole chain for every callback makes terrain avoidance quadratic.
  if seen[fixture] then return true end
  seen[fixture]=true
  local body=fixture:getBody();local o=fixture:getUserData() or body:getUserData()
  local state=bodies[body]
  if not state then
   local bx,by=body:getPosition();local vx,vy=body:getLinearVelocity()
   state={x=bx,y=by,angle=body:getAngle(),vx=vx,vy=vy,loose=body:getType()=='dynamic' or nil}
   bodies[body]=state
  end
  if (not staticOnly or not state.loose) and body~=e.body and o~=ignore and not fixture:isSensor() and not (o and (o.dead or o.removed))
   and not (allowSurface and o and o.kind=='planet') then
   for _,primitive in ipairs(geometryFor(fixture,body,state)) do result[#result+1]=primitive end
  end
  return true
 end)
 -- Gas giants have no fixture, but transit traffic should stay above the clouds.
 local w=game.well
 if w and w.gas and not allowSurface then
  local r=w.radius+T.surfacePullRange
  result[#result+1]={x=w.x,y=w.y,r=r,vx=0,vy=0,virtual=true,minx=w.x-r,maxx=w.x+r,miny=w.y-r,maxy=w.y+r}
 end
 return result
end
-- Commit to a detour around scenery instead of repeatedly aiming into it.
-- Dynamic traffic still uses the predictive steering below.
function Nav.waypoint(game,e,gx,gy,options)
 options=options or {}
 local x,y=e.body:getPosition();local now=game.time or 0
 local old=e.detour
 local function distance(ax,ay,bx,by)return sqrt((ax-bx)^2+(ay-by)^2) end
 if old and old.ignore==options.ignore and old.surface==options.allowSurface
  and distance(gx,gy,old.gx,old.gy)<180 and now<old.expires then
  while old.index<#old.path and distance(x,y,old.path[old.index][1],old.path[old.index][2])<120 do old.index=old.index+1 end
  local point=old.path[old.index]
  return point[1],point[2],old.index<#old.path
 end
 local requestedX,requestedY=gx,gy
 local direct=distance(x,y,gx,gy)
 local radius=max(e.halfLength,e.hull.radius)+T.aiClearance
 local padding=max(1400,min(5000,direct*.6))
 local geometry=obstacles(game,e,min(24000,direct+padding),options.ignore,options.allowSurface,true)
 local function clear(ax,ay,bx,by)
  local loX,hiX=min(ax,bx)-radius,max(ax,bx)+radius
  local loY,hiY=min(ay,by)-radius,max(ay,by)+radius
  for _,o in ipairs(geometry) do
   if o.maxx>=loX and o.minx<=hiX and o.maxy>=loY and o.miny<=hiY
    and Sweep.sweepCircle(ax,ay,radius,o,bx-ax,by-ay,1) then return false end
  end
  return true
 end
 local function save(path,ttl)
  e.detour={gx=requestedX,gy=requestedY,ignore=options.ignore,surface=options.allowSurface,
   path=path,index=1,expires=now+ttl}
  return path[1][1],path[1][2],#path>1
 end
 -- A near-side mining standoff can fall inside the parent asteroid.
 -- Find an accessible point on the same working ring before planning.
 if not clear(gx,gy,gx,gy) and options.stand then
  local best
  for i=0,23 do
   local angle=i*pi/12
   local px,py=options.cx+cos(angle)*options.stand,options.cy+sin(angle)*options.stand
   local cost=distance(x,y,px,py)
   if (not best or cost<best) and clear(px,py,px,py) then gx,gy,best=px,py,cost end
  end
 end
 if clear(x,y,gx,gy) then return save({{gx,gy}},.8) end
 if not clear(gx,gy,gx,gy) then return save({{gx,gy}},2) end
 local step=max(180,radius*2,(direct+padding*2)/36)
 local minx,miny=min(x,gx)-padding,min(y,gy)-padding
 local nx=math.ceil((math.abs(gx-x)+padding*2)/step)
 local ny=math.ceil((math.abs(gy-y)+padding*2)/step)
 local function heuristic(px,py)return distance(px,py,gx,gy) end
 local start={x=x,y=y,cost=0};start.score=direct
 local open={start};local nodes={};local finish
 local directions={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}
 for _=1,1600 do
  if #open==0 then break end
  local best=1
  for i=2,#open do if open[i].score<open[best].score then best=i end end
  local current=table.remove(open,best);current.closed=true
  if heuristic(current.x,current.y)<step*2 and clear(current.x,current.y,gx,gy) then finish=current;break end
  local ix=math.floor((current.x-minx)/step+.5)
  local iy=math.floor((current.y-miny)/step+.5)
  for _,v in ipairs(directions) do
   local cx,cy=ix+v[1],iy+v[2]
   if cx>=0 and cx<=nx and cy>=0 and cy<=ny then
    local key=cx+cy*(nx+1);local node=nodes[key]
    if not node or not node.closed then
     local px,py=minx+cx*step,miny+cy*step
     local cost=current.cost+distance(current.x,current.y,px,py)
     if (not node or cost<node.cost) and clear(current.x,current.y,px,py) then
      if not node then node={x=px,y=py};nodes[key]=node;open[#open+1]=node end
      node.cost,node.score,node.parent=cost,cost+heuristic(px,py),current
     end
    end
   end
  end
 end
 if not finish then return save({{gx,gy}},2) end
 local reverse={{gx,gy}}
 while finish.parent do reverse[#reverse+1]={finish.x,finish.y};finish=finish.parent end
 local path={};local ax,ay=x,y;local i=#reverse
 while i>=1 do
  local nextIndex=i
  for j=1,i do if clear(ax,ay,reverse[j][1],reverse[j][2]) then nextIndex=j;break end end
  local point=reverse[nextIndex];path[#path+1]=point;ax,ay=point[1],point[2];i=nextIndex-1
 end
 return save(path,8)
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
 -- Something loose already overlapping this one (two ships woken on the
 -- same spot, or the wreck of one) blocks every heading at time 0, which
 -- left the ship crawling at the minimum speed for ever, drifting off with
 -- the current. The collision pushes them apart; steering ignores it meanwhile.
 for i=#geometry,1,-1 do
  local o=geometry[i]
  if o.loose and x+radius>=o.minx and x-radius<=o.maxx and y+radius>=o.miny and y-radius<=o.maxy
   and Sweep.sweepCircle(x,y,radius,o,0,0,1)==0 then table.remove(geometry,i) end
 end
 local spine=e.spine or {0,0}
 local offsets={spine[1],0,spine[2]}
 -- Reject an obstacle against the swept bounds of the entire spine before
 -- running the three exact circle sweeps. This only skips impossible hits.
 local minx,maxx=x+min(c*spine[1],0,c*spine[2])-radius,x+max(c*spine[1],0,c*spine[2])+radius
 local miny,maxy=y+min(s*spine[1],0,s*spine[2])-radius,y+max(s*spine[1],0,s*spine[2])+radius
 local function freeTime(dx,dy,ahead,physicalOnly)
  ahead=ahead or horizon
  local time=ahead
  for _,o in ipairs(geometry) do
   if not physicalOnly or not o.virtual then
    local rx,ry=dx-o.vx,dy-o.vy
    if maxx+max(0,rx*time)>=o.minx-1e-6 and minx+min(0,rx*time)<=o.maxx+1e-6
     and maxy+max(0,ry*time)>=o.miny-1e-6 and miny+min(0,ry*time)<=o.maxy+1e-6 then
     for _,offset in ipairs(offsets) do
      local hit=Sweep.sweepCircle(x+c*offset,y+s*offset,radius,o,rx,ry,time)
      if hit and hit<time then time=hit;if time==0 then return 0 end end
     end
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
 -- Ships waking together must not all redo avoidance on the same tick.
 -- Give each one a stable phase, keeping the existing maximum refresh age.
 local interval=T.aiSteerEvery
 local id=tonumber(tostring(e.alifeId or e.id or 0):match('%d+$')) or 0
 local phase=(id*.61803398875%1)*interval
 local now=game.time or 0
 best.untilTime=old and now+interval or now+interval-(now-phase)%interval
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
 local plan=e.aiBoostPlan or {};e.aiBoostPlan=plan
 plan.x,plan.y,plan.want,plan.distance,plan.clear,plan.danger,plan.allow=dx,dy,want,distance,clear,danger,allow
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
