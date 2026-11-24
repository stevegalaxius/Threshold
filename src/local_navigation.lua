-- Local detours and steering preserve authored graph routes and destinations.
local Sweep=require('src.collision_prediction')
local T=require('src.tuning')
local Nav={}
local pi,cos,sin,sqrt,abs,min,max=math.pi,math.cos,math.sin,math.sqrt,math.abs,math.min,math.max
local ANGLES={0,.35,-.35,.7,-.7,1.1,-1.1,pi/2,-pi/2,2.2,-2.2,2.65,-2.65,pi}
local function wrap(a)return (a+pi)%(2*pi)-pi end
-- All nearby NPCs can query the same fixture. Reuse world geometry until
-- its transform or velocity changes; weak keys release destroyed fixtures.
-- (kept per body, and held there: a fixture handle nobody else keeps is
-- collected between steps, and a table keyed weakly by fixture alone forgot
-- every outline as soon as it was made. The body's entry goes with the body.)
local bodyGeometry=setmetatable({},{__mode='k'})
-- A fixture's outline in its body's frame never changes, so it is read from
-- the physics once. Each time the body has moved the world outline is worked
-- out from that here, into the same tables: a turning station is hundreds
-- of fixtures, and asking the physics for each one's world points afresh
-- (and making new tables for them) every step a ship came near was the
-- larger part of a steering plan.
local function localShape(fixture)
 local shape=fixture:getShape();local kind=shape:getType()
 if kind=='circle' then
  local cx,cy=shape:getPoint()
  return {circle=true,x=cx,y=cy,r=shape:getRadius()}
 elseif kind=='polygon' or kind=='edge' or kind=='chain' then
  return {chain=kind=='chain',points={shape:getPoints()}}
 end
 return {}
end
local function bound(o)
 if o.r then o.minx,o.miny,o.maxx,o.maxy=o.x-o.r,o.y-o.r,o.x+o.r,o.y+o.r
 else
  local p=o.p
  local minx,miny,maxx,maxy=math.huge,math.huge,-math.huge,-math.huge
  for i=1,#p,2 do
   local px,py=p[i],p[i+1]
   if px<minx then minx=px end
   if px>maxx then maxx=px end
   if py<miny then miny=py end
   if py>maxy then maxy=py end
  end
  o.minx,o.miny,o.maxx,o.maxy=minx,miny,maxx,maxy
 end
end
local function geometryFor(fixture,body,state)
 local x,y,angle,vx,vy,loose=state.x,state.y,state.angle,state.vx,state.vy,state.loose
 local store=state.store
 if not store then
  store=bodyGeometry[body];if not store then store={n=0,fixtures={}};bodyGeometry[body]=store end
  state.store=store
 end
 local old=store.fixtures[fixture]
 if old and old.x==x and old.y==y and old.angle==angle and old.vx==vx and old.vy==vy and old.loose==loose then return old.shapes end
 if not old then old={shape=localShape(fixture)};store.fixtures[fixture]=old;store.n=store.n+1 end
 local shape=old.shape
 local c,s=state.cos,state.sin
 if not c then c,s=cos(angle),sin(angle);state.cos,state.sin=c,s end
 local result=old.shapes
 if shape.circle then
  local o=result and result[1]
  if not o then o={r=shape.r};result={o} end
  o.x,o.y=x+shape.x*c-shape.y*s,y+shape.x*s+shape.y*c
  o.vx,o.vy,o.loose=vx,vy,loose
  bound(o)
 elseif shape.points then
  local points=shape.points
  if shape.chain then
   -- one segment per link
   if not result then
    result={}
    for i=1,#points-2,2 do result[#result+1]={p={0,0,0,0}} end
   end
   local k=0
   for i=1,#points-2,2 do
    k=k+1
    local o=result[k];local p=o.p
    p[1],p[2]=x+points[i]*c-points[i+1]*s,y+points[i]*s+points[i+1]*c
    p[3],p[4]=x+points[i+2]*c-points[i+3]*s,y+points[i+2]*s+points[i+3]*c
    o.vx,o.vy,o.loose=vx,vy,loose
    bound(o)
   end
  else
   local o=result and result[1]
   if not o then o={p={}};result={o} end
   local p=o.p
   for i=1,#points,2 do
    p[i],p[i+1]=x+points[i]*c-points[i+1]*s,y+points[i]*s+points[i+1]*c
   end
   o.vx,o.vy,o.loose=vx,vy,loose
   bound(o)
  end
 else
  result=result or {}
 end
 old.x,old.y,old.angle,old.vx,old.vy,old.loose,old.shapes=x,y,angle,vx,vy,loose,result
 return result
end
-- Obstacles are gathered per body, not per fixture. A ship hull is a dozen
-- or more polygons; with hundreds of ships in an area every steering plan
-- used to walk thousands of fixtures through queryBoundingBox. Each step
-- the bodies are listed once (shared by every ship planning that step) with
-- a bounding circle; a plan only expands the fixtures of bodies its sweep
-- can actually reach.
local bodyReach=setmetatable({},{__mode='k'})
local reachTurn=0
-- (re-measured now and then: listing fixtures allocates, and a hull only
-- gains or loses parts rarely; losing one leaves the circle a little large)
local function radiusOf(body,stamp)
 local cached=bodyReach[body]
 if cached and stamp and stamp<cached.fresh and stamp>=cached.stamp then return cached.r end
 local fixtures=body:getFixtures()
 local r
 for _,f in ipairs(fixtures) do
  if not f:isSensor() then
   local shape=f:getShape();local kind=shape:getType()
   local fr=0
   if kind=='circle' then local cx,cy=shape:getPoint();fr=sqrt(cx*cx+cy*cy)+shape:getRadius()
   else
    local pts={shape:getPoints()}
    for i=1,#pts,2 do fr=max(fr,sqrt(pts[i]^2+pts[i+1]^2)) end
   end
   r=max(r or 0,fr+1)
  end
 end
 -- (each keeps its measure a different while, 60 to 120 steps: a map's
 -- bodies are all first seen on one step, and measuring them all again
 -- together a second later, every second, was a step several times as long)
 -- (and what doesn't fly, stations and structures with their hundreds of
 -- fixtures, keeps it a minute: those were most of the measuring)
 reachTurn=(reachTurn+37)%61
 local keep=60+reachTurn
 if body:getType()~='dynamic' then keep=keep*60 end
 bodyReach[body]={stamp=stamp or -math.huge,fresh=(stamp or -math.huge)+keep,r=r}
 return r
end
local index={}
local function bodies(game)
 local stamp=game.navStamp
 if stamp and index.world==game.world and index.stamp==stamp then return index.groups end
 local groups={}
 for _,body in ipairs(game.world:getBodies()) do
  if not body:isDestroyed() and body:isActive() then
   local r=radiusOf(body,stamp)
   if r then
    local x,y=body:getPosition();local vx,vy=body:getLinearVelocity()
    groups[#groups+1]={body=body,x=x,y=y,angle=body:getAngle(),vx=vx,vy=vy,loose=body:getType()=='dynamic' or nil,
     minx=x-r,miny=y-r,maxx=x+r,maxy=y+r,owner=body:getUserData()}
   end
  end
 end
 index.world,index.stamp,index.groups=game.world,stamp,groups
 return groups
end
local function expand(group)
 local prims=group.prims
 if prims then return prims end
 prims={}
 local fixtures=group.body:getFixtures()
 -- (outlines of fixtures the body has since lost: let them go)
 local store=bodyGeometry[group.body]
 if store and store.n>#fixtures then
  for fixture in pairs(store.fixtures) do
   if fixture:isDestroyed() then store.fixtures[fixture]=nil;store.n=store.n-1 end
  end
 end
 for _,fixture in ipairs(fixtures) do
  if not fixture:isSensor() then
   local o=fixture:getUserData() or group.owner
   if o and (o.dead or o.removed ) then group.anyGone=true end
   for _,primitive in ipairs(geometryFor(fixture,group.body,group)) do
    prims[#prims+1]=primitive;primitive.owner=o
   end
  end
 end
 group.prims=prims
 return prims
end
-- A primitive this plan should steer round.
local function counts(o,ignore,allowSurface)
 return o~=ignore and not (o and (o.dead or o.removed)) and not (allowSurface and o and o.kind=='planet')
end
-- Bodies near the ship that the plan should consider. Their fixtures are
-- expanded (prims) only when a sweep actually reaches the body's bounds.
local function obstacles(game,e,reach,ignore,allowSurface,staticOnly)
 local x,y=e.body:getPosition();local result={}
 local lx,ly,hx,hy=x-reach,y-reach,x+reach,y+reach
 for _,g in ipairs(bodies(game)) do
  if g.maxx>=lx and g.minx<=hx and g.maxy>=ly and g.miny<=hy and g.body~=e.body and (not staticOnly or not g.loose)
   and not g.body:isDestroyed() then result[#result+1]=g end
 end
 result.ignore,result.allowSurface=ignore,allowSurface
 -- Gas giants have no fixture, but transit traffic should stay above the clouds.
 local w=game.well
 if w and w.gas and not allowSurface then
  local r=w.radius+T.surfacePullRange
  local o={x=w.x,y=w.y,r=r,vx=0,vy=0,virtual=true,minx=w.x-r,maxx=w.x+r,miny=w.y-r,maxy=w.y+r}
  result[#result+1]={minx=o.minx,miny=o.miny,maxx=o.maxx,maxy=o.maxy,vx=0,vy=0,virtual=true,prims={o}}
 end
 return result
end
-- The fixtures of one body this plan counts as obstacles.
local function primsOf(g,list)
 local prims=g.prims or expand(g)
 local ignore,allowSurface=list.ignore,list.allowSurface
 if g.virtual or (ignore==nil and not allowSurface and not g.anyGone) then return prims end
 list.kept=list.kept or {}
 local keep=list.kept[g]
 if keep then return keep end
 keep={}
 for _,p in ipairs(prims) do if counts(p.owner,ignore,allowSurface) then keep[#keep+1]=p end end
 list.kept[g]=keep
 return keep
end
Nav.obstacleGroups=obstacles
-- The docking tower only takes control if the handoff can reach its
-- outer marker without sweeping through a hull or through local traffic.
function Nav.clearDockHandoff(game,e,gx,gy)
 local x,y=e.body:getPosition()
 local dx,dy=gx-x,gy-y
 local radius=max(e.halfLength or 0,e.hull.radius)
 local groups=obstacles(game,e,sqrt(dx*dx+dy*dy)+radius,nil,true)
 local minX,maxX=min(x,gx)-radius,max(x,gx)+radius
 local minY,maxY=min(y,gy)-radius,max(y,gy)+radius
 for _,group in ipairs(groups) do
  if group.maxx>=minX and group.minx<=maxX and group.maxy>=minY and group.miny<=maxY then
   for _,shape in ipairs(primsOf(group,groups)) do
    if shape.maxx>=minX and shape.minx<=maxX and shape.maxy>=minY and shape.miny<=maxY
     and Sweep.sweepCircle(x,y,radius,shape,dx,dy,1) then return false end
   end
  end
 end
 return true
end

-- Commit to a detour around scenery instead of repeatedly aiming into it.
-- Dynamic traffic still uses the predictive steering below.
function Nav.waypoint(game,e,gx,gy,options)
 options=options or {}
 local x,y=e.body:getPosition();local now=game.time or 0
 local old=e.detour
 local needsSight=options.sight~=nil
 local function distance(ax,ay,bx,by)return sqrt((ax-bx)^2+(ay-by)^2) end
 if old and old.sight==needsSight and old.ignore==options.ignore and old.surface==options.allowSurface
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
  for _,g in ipairs(geometry) do
   if g.maxx>=loX and g.minx<=hiX and g.maxy>=loY and g.miny<=hiY then
    for _,o in ipairs(primsOf(g,geometry)) do
     if o.maxx>=loX and o.minx<=hiX and o.maxy>=loY and o.miny<=hiY
      and Sweep.sweepCircle(ax,ay,radius,o,bx-ax,by-ay,1) then return false end
    end
   end
  end
  return true
 end
 local function save(path,ttl)
  e.detour={gx=requestedX,gy=requestedY,ignore=options.ignore,surface=options.allowSurface,sight=needsSight,
   path=path,index=1,expires=now+ttl}
  return path[1][1],path[1][2],#path>1
 end
 -- A near-side mining standoff can fall inside the parent asteroid.
 -- Find an accessible point on the same working ring before planning.
 local function usable(px,py)
  return clear(px,py,px,py) and (not options.sight or options.sight(px,py))
 end
 if not usable(gx,gy) and options.stand then
  local best
  for i=0,23 do
   local angle=i*pi/12
   local px,py=options.cx+cos(angle)*options.stand,options.cy+sin(angle)*options.stand
   if usable(px,py) then
    local cost=distance(x,y,px,py)
    if needsSight and not clear(x,y,px,py) then cost=cost+direct end
    if not best or cost<best then gx,gy,best=px,py,cost end
   end
  end
  if not best and needsSight then return nil end
 end
 if clear(x,y,gx,gy) then return save({{gx,gy}},.8) end
 if not clear(gx,gy,gx,gy) then return save({{gx,gy}},2) end
 -- The search itself (src/pathsearch.lua) works from just the obstacles
 -- that reach into the stretch it searches, as plain shapes...
 local Path=require('src.pathsearch')
 local step=Path.step(radius,padding,direct)
 local loX,hiX=min(x,gx)-padding-radius,max(x,gx)+padding+step+radius
 local loY,hiY=min(y,gy)-padding-radius,max(y,gy)+padding+step+radius
 local prims={}
 for _,g in ipairs(geometry) do
  if g.maxx>=loX and g.minx<=hiX and g.maxy>=loY and g.miny<=hiY then
   for _,o in ipairs(primsOf(g,geometry)) do
    if o.maxx>=loX and o.minx<=hiX and o.maxy>=loY and o.miny<=hiY then prims[#prims+1]=o end
   end
  end
 end
 -- ...so the background thread can do it (src/worker.lua): up to 1600
 -- points each swept against every obstacle was the longest single thing
 -- a step did. The ship heads straight for now (its steering still keeps
 -- it off things) and takes the path when it comes back, a few frames on.
 local Worker=require('src.worker')
 if Worker.active("path") then
  local ask={}
  e.pathAsk=ask
  local ignore,surface=options.ignore,options.allowSurface
  Worker.ask('path',{x,y,gx,gy,radius,padding,direct,Path.pack(prims)},function(found)
   if e.pathAsk~=ask or e.dead or e.removed then return end
   e.pathAsk=nil
   e.detour={gx=requestedX,gy=requestedY,ignore=ignore,surface=surface,sight=needsSight,
    path=found.path,index=1,expires=(game.time or 0)+found.ttl}
  end)
  return save({{gx,gy}},1.5)
 end
 local found=Path.search(x,y,gx,gy,radius,padding,direct,prims)
 return save(found.path,found.ttl)
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
 local overlapping
 for _,g in ipairs(geometry) do
  if g.loose and x+radius>=g.minx and x-radius<=g.maxx and y+radius>=g.miny and y-radius<=g.maxy then
   for _,o in ipairs(primsOf(g,geometry)) do
    if x+radius>=o.minx and x-radius<=o.maxx and y+radius>=o.miny and y-radius<=o.maxy
     and Sweep.sweepCircle(x,y,radius,o,0,0,1)==0 then overlapping=overlapping or {};overlapping[o]=true end
   end
  end
 end
 local spine=e.spine or {0,0}
 local offsets={spine[1],0,spine[2]}
 -- Reject an obstacle against the swept bounds of the entire spine before
 -- running the three exact circle sweeps. This only skips impossible hits.
 local minx,maxx=x+min(c*spine[1],0,c*spine[2])-radius,x+max(c*spine[1],0,c*spine[2])+radius
 local miny,maxy=y+min(s*spine[1],0,s*spine[2])-radius,y+max(s*spine[1],0,s*spine[2])+radius
 -- Drop bodies no heading can reach within the horizon, once, instead of
 -- re-testing them for every candidate heading.
 do
  local V=max(sqrt(vx*vx+vy*vy),sqrt(flowX*flowX+flowY*flowY)+want)
  local near={ignore=geometry.ignore,allowSurface=geometry.allowSurface}
  for _,g in ipairs(geometry) do
   local m=(V+sqrt(g.vx*g.vx+g.vy*g.vy))*horizon
   if maxx+m>=g.minx and minx-m<=g.maxx and maxy+m>=g.miny and miny-m<=g.maxy then near[#near+1]=g end
  end
  geometry=near
 end
 local function freeTime(dx,dy,ahead,physicalOnly)
  ahead=ahead or horizon
  local time=ahead
  for _,g in ipairs(geometry) do
   if not physicalOnly or not g.virtual then
    local rx,ry=dx-g.vx,dy-g.vy
    if maxx+max(0,rx*time)>=g.minx-1e-6 and minx+min(0,rx*time)<=g.maxx+1e-6
     and maxy+max(0,ry*time)>=g.miny-1e-6 and miny+min(0,ry*time)<=g.maxy+1e-6 then
     for _,o in ipairs(primsOf(g,geometry)) do
      if not (overlapping and overlapping[o])
       and maxx+max(0,rx*time)>=o.minx-1e-6 and minx+min(0,rx*time)<=o.maxx+1e-6
       and maxy+max(0,ry*time)>=o.miny-1e-6 and miny+min(0,ry*time)<=o.maxy+1e-6 then
       for _,offset in ipairs(offsets) do
        local hit=Sweep.sweepCircle(x+c*offset,y+s*offset,radius,o,rx,ry,time)
        if hit and hit<time then time=hit;if time==0 then return 0 end end
       end
      end
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
