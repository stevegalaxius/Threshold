-- Reconcile a changed catalogue at a world load/edit, never per-frame pathfinding.
-- Recovery uses the existing itinerary, flight controller and docking lifecycle.
local L,F,G=require('src.locations'),require('src.fields'),require('src.travelgraph')
local W,H,Tasks=require('src.world_layout'),require('src.npc_home'),require('src.tasks')
local copy=require('src.persistence').copy
local R={}
local function endpoint(u,id)
 local p=u.worldLocations and u.worldLocations[id] or L.byId[id]
 return p and (p.kind=='driver' or p.kind=='moon_gate') or false
end
local function oldPosition(u,id,clock)
 local old=u.worldLocations and u.worldLocations[id]
 if old then return L.motionPosition(old.motion,clock) end
 if L.byId[id] then return L.position(id,clock) end
end
local function pose(u,r,clock)
 if r.pose then return r.pose.x,r.pose.y end
 local route=r.route or {};local id=route[r.index or 1]
 local x,y=oldPosition(u,id,clock)
 if r.state=='travel' and #route>0 and r.depart and r.arrive then
  local ax,ay=oldPosition(u,route[((r.index or 1)-2)%#route+1],clock)
  if ax and x then
   local p=math.max(0,math.min(1,(clock-r.depart)/math.max(.1,r.arrive-r.depart)))
   local bx,by=G.interpolate(ax,ay,x,y,p,endpoint(u,route[((r.index or 1)-2)%#route+1]),endpoint(u,id))
   bx,by=G.withSpread(bx,by,p,r.spread)
   if r.offset then
    local fade=(1-p)/math.max(.001,1-(r.offset.progress or 0))
    bx,by=bx+r.offset.x*fade,by+r.offset.y*fade
   end
   return bx,by
  end
 end
 return x,y
end
local function samePlace(u,id)
 local old=u.worldLocations and u.worldLocations[id];local new=L.byId[id]
 if not new then return false end
 if old and (old.area~=new.area or require('src.save').encode(old.motion)~=require('src.save').encode(new.motion)) then return false end
 return true
end
local function validRoute(r)
 if not r.route or #r.route==0 then return false end
 for i,id in ipairs(r.route) do
  if not L.byId[id] then return false end
  if i>1 then
   local from=r.route[i-1];local a,b=L.get(from),L.get(id)
   if a.area~=b.area then if not G.transit(from,id,0) then return false end
   elseif from~=id then
    local linked=false
    for _,edge in ipairs(G.neighbours(G.build(a.area),from,0)) do
     if edge.to==id then linked=true;break end
    end
    if not linked then return false end
   end
  end
 end
 return true
end
local function taskValid(t)
 if not t then return true end
 if not L.byId[t.target] then return false end
 if t.kind=='transport' then return L.get(t.target).kind=='station' end
 if not L.byId[t.source] then return false end
 if t.kind=='mine' then return L.get(t.target).motion.home==t.source end
 return true
end
function R.begin(u,r,clock,start)
 local home=H.get(r);local region=r.area or r.home
 if not F[region] then region=home and L.get(home).area or F.start end
 local x,y=pose(u,r,clock)
 local node=L.nearest(region,x or 0,y or 0,clock)
 if not node then return false end
 local keep=r.task and r.task.kind=='transport' and taskValid(r.task)
 if not keep then Tasks.release(u,r,'world layout changed',clock) end
 r.encounter,r.targetId,r.offlineLoot,r.job=nil,nil,nil,nil
 r.tripRoute,r.onRoundTrip,r.tripDestination,r.tradeHome=nil,nil,nil,nil
 if keep then r.taskWorker=true end
 r.driverState,r.cityExit,r.docking,r.repairReturn=nil,nil,nil,nil
 if not home then
  r.waitingForHome=true;r.worldRecovery=nil;r.taskStatus='waiting for a home station'
  r.state='idle';r.area=region;r.node=node;r.route={node,node};r.index=1;r.untilTime=clock+10
  r.pose,r.offset=nil,nil
  return false
 end
 local target=keep and r.task.target or home
 local path=G.itinerary(node,target,clock)
 if not path then
  r.waitingForHome=true;r.worldRecovery=nil;r.taskStatus='waiting for a route to a home station'
  r.state='idle';r.area=region;r.node=node;r.route={node,node};r.index=1;r.untilTime=clock+10
  r.pose,r.offset=nil,nil
  return false
 end
 r.waitingForHome=nil;r.taskStatus=keep and 'rerouting delivery' or 'returning to home station'
 r.worldRecovery={target=target,delivery=not not keep}
 if not r.roamingHome then r.home=L.get(home).area end
 if r.task and r.task.kind=='mine' then r.base=home;r.mineSite=nil end
 if r.piracy~=nil then
  r.taskWorker=true
  r.piracy=r.piracy or {phase='escape',origin=L.rally(r.home,node,clock) or node}
  r.piracy.base=home;r.piracy.phase='escape'
  if not L.byId[r.piracy.origin] then r.piracy.origin=L.rally(r.home,node,clock) or node end
 end
 if r.state=='transit' and r.transit and r.route and L.byId[r.route[r.index]] then
  local destination=r.route[r.index];local tail=G.itinerary(destination,target,clock)
  if tail then
   local source=r.route[(r.index-2)%#r.route+1]
   r.route={source};for _,id in ipairs(tail) do r.route[#r.route+1]=id end;r.index=2;require('src.queue').leg(r)
   return true
  end
 end
 local previousPose=r.pose
 r.route=path;r.index=1
 if #path==1 then path[2]=path[1] end
 start(r,clock,2)
 if x then
  local bx,by=L.position(path[1],clock)
  r.offset={x=x-bx,y=y-by,progress=0}
  r.pose={x=x,y=y,a=previousPose and previousPose.a or 0,vx=previousPose and previousPose.vx or 0,vy=previousPose and previousPose.vy or 0,w=0,clock=clock}
  r.arrive=math.max(r.arrive,clock+math.sqrt((x-bx)^2+(y-by)^2)/r.speed)
 end
 return true
end
function R.resume(u,r,clock)
 local duty=r.worldRecovery;if not duty then return end
 r.worldRecovery=nil;r.taskStatus=nil;r.node=duty.target;r.state='docked';r.untilTime=clock or u.clock

end
function R.prepare(game,start)
 local u,clock=game.universe,game.universe.clock
 local signature=W.signature()
 if u.worldLayoutSignature==signature then return end
 if u.home then
  local place=L.byId[u.home.key]
  local id=place and place.id or L.station(u.home.field,'trade')
  u.home=id and {key=id,field=L.get(id).area,name=L.get(id).name} or nil
 end
 local board=Tasks.state(u)
 for _,r in pairs(u.npcs) do
  if r.state~='dead' and r.state~='escaped' then
   local oldHome=r.homeStation or r.base or r.tradeHome
   local home=H.get(r)
   local invalid=not validRoute(r) or not taskValid(r.task) or r.waitingForHome
   for _,id in ipairs(r.route or {}) do if not samePlace(u,id) then invalid=true end end
   if oldHome and oldHome~=home then invalid=true end
   if home and not r.roamingHome and L.get(home).area~=r.home then invalid=true end
   if invalid then R.begin(u,r,clock,start) end
  end
 end
 for id,o in pairs(board.offers) do
  if not L.byId[o.source] or not L.byId[o.target] then
   if not o.owner then board.offers[id]=nil end
  end
 end
 -- Wreck loot remains at its last position when the route that described it
 -- disappears; deleting a station must not delete its surrounding salvage.
 for _,wreck in pairs(u.alifeWrecks or {}) do
  if not wreck.worldPosition and (not samePlace(u,wreck.from) or not samePlace(u,wreck.to)) then
   local x,y=oldPosition(u,wreck.from,clock)
   local xx,yy=oldPosition(u,wreck.to,clock)
   if x then
    local px,py=G.interpolate(x,y,xx or x,yy or y,wreck.progress or 0,endpoint(u,wreck.from),endpoint(u,wreck.to))
    wreck.worldPosition={x=px,y=py}
   end
  end
 end
 u.worldLocations={}
 for id,place in pairs(L.byId) do
  if place.kind~='mining_site' then u.worldLocations[id]={area=place.area,kind=place.kind,motion=copy(place.motion)} end
 end
 u.worldLayoutSignature=signature
end
return R
