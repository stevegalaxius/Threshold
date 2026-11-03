-- Drill production and mineral objects have one plain record each. Bodies and
-- pickups are temporary representations, just like the A-Life ships that work them.
local Fields,L,T=require('src.fields'),require('src.locations'),require('src.tuning')
local data,Ship,Stats=require('src.data'),require('src.ship'),require('src.stats')
local Tasks,Hold=require('src.tasks'),require('src.inventory.hold')
local copy=require('src.persistence').copy
local Ore=require('src.ore')
local M={}
local sin,cos,sqrt,min,max,pi=math.sin,math.cos,math.sqrt,math.min,math.max,math.pi
function M.state(u)
 u.mining=u.mining or {sites={},resources={},stock={},seeded={}}
 return u.mining
end
function M.isMiner(r)return r and r.role=='miner' end
function M.workPoint(site)
 return L.position(site.id,0)
end

Tasks.register('mine',{
 roles={miner=true},
 eligible=function(u,r,o,node)return o.source==node and o.area==r.home end,
 score=function(u,r,o)return r.lastMine==o.target and -1 or 0 end,
 prepare=function(u,r,t)t.phase='mining';return true end,
 plan=function(t)return {t.source,t.target} end,
 complete=function(u,r,t,node)
  if node~=t.source then return false end
  local state=M.state(u);local cargo=r.ship.cargo or {};local n=cargo[t.item] or 0
  if n<=0 then return false end
  state.stock[node]=state.stock[node] or {}
  state.stock[node][t.item]=(state.stock[node][t.item] or 0)+n
  cargo[t.item]=nil
  if r.ship.hold then
   local h=Hold.deserialize(r.ship.hold,function(id)return data.items[id]~=nil end)
   Hold.sync(h,cargo);r.ship.hold=Hold.serialize(h)
  end
  r.lastMine=t.target
  return true
 end,
})
function M.seed(game)
 local u=game.universe;local state=M.state(u)
 for _,area in ipairs(Fields.list) do
  local specs=Fields.miningSources(area);local f=Fields[area]
  if #specs>0 then
   for index,s in ipairs(specs) do
    local id=area..'/drill/'..index
    if not state.sites[id] then
     local home=f.stationIds and f.stationIds[1]
     local angle=-pi/2
     if home then local hx,hy=L.position(home,0);angle=math.atan2(hy-s.y,hx-s.x) end
     -- A surface drill sits away from the station's roof and docking approach.
     if s.planet then angle=angle+.9 end
     state.sites[id]={id=id,area=area,x=s.x,y=s.y,radius=s.radius,planet=s.planet,
      angle=angle,item=Ore.items.rock,
      nextAt=u.clock+T.drillInterval,sequence=0,home=home}
     if home and not f.instance then
      for _=1,(#specs==1 and T.minersPerArea or 1) do
       Tasks.post(u,{kind='mine',source=home,target=id,area=area,item=state.sites[id].item,cooldown=0})
      end
     end
    end
   end
   if not f.instance and f.stationIds[1] and not state.seeded[area] then
    state.seeded[area]=true
    for _=1,T.minersPerArea do
     local def=data.enemies.miner_wisp;local hull=data.hulls[def.hull]
     u.nextNpcId=u.nextNpcId+1
     local r={id='npc/'..u.nextNpcId,role='miner',archetype='miner_wisp',home=area,area=area,
      base=f.stationIds[1],node=f.stationIds[1],route={f.stationIds[1],f.stationIds[1]},index=1,
      state='idle',speed=def.ai.cruise,spread=0,
      ship={hull=def.hull,loadout=copy(def.loadout),cargo={},color=copy(def.color),armor=Stats.compute(hull,def.loadout).armor}}
     u.npcs[r.id]=r
     M.advance(game,r,u.clock)
    end
   end
  end
 end
end
function M.position(resource,clock)
 local elapsed=max(0,clock-(resource.clock or clock));local f=Fields[resource.area]
 if f.planetR then
  local r=sqrt(resource.x^2+resource.y^2)
  local rate=resource.orbitRate or 290*sqrt(f.planetR/max(r,f.planetR))*T.currentScale/max(r,1)
  local a=rate*elapsed
  return resource.x*cos(a)-resource.y*sin(a),resource.x*sin(a)+resource.y*cos(a),
   resource.vx*cos(a)-resource.vy*sin(a),resource.vx*sin(a)+resource.vy*cos(a)
 end
 local damping=resource.kind=='loot' and 1.5 or T.miningChunkDamping
 local travel=(1-math.exp(-damping*elapsed))/damping
 return resource.x+resource.vx*travel,resource.y+resource.vy*travel,
  resource.vx*math.exp(-damping*elapsed),resource.vy*math.exp(-damping*elapsed)
end
local function pointAtBody(site,game)
 local parent
 for _,e in ipairs(game.entities) do
  if site.planet and e.kind=='planet' and e.landable or not site.planet and e.giant then
   local x,y=e.body:getPosition()
   if (x-site.x)^2+(y-site.y)^2<1 then parent=e;break end
  end
 end
 local radius=site.radius
 local outline=parent and (parent.outline or parent.rock and parent.rock.outline)
 local nx,ny=cos(site.angle),sin(site.angle)
 if outline then
  for i=1,#outline,2 do
   local j=i+2;if j>#outline then j=1 end
   local ax,ay=outline[i],outline[i+1];local dx,dy=outline[j]-ax,outline[j+1]-ay
   local cross=nx*dy-ny*dx
   if math.abs(cross)>.00001 then
    local r=(ax*dy-ay*dx)/cross;local along=(ax*ny-ay*nx)/cross
    if r>0 and along>=0 and along<=1 then radius=r;break end
   end
  end
 end
 return site.x+nx*radius,site.y+ny*radius,nx,ny
end
function M.produce(game,clock)
 local state=M.state(game.universe)
 local counts={}
 for _,resource in pairs(state.resources) do counts[resource.site]=(counts[resource.site] or 0)+1 end
 for id,site in pairs(state.sites) do
  if clock>=site.nextAt then
   -- One overdue batch, never a catch-up storm after loading an old save.
   site.nextAt=clock+T.drillInterval
   local count=min(T.drillBatch,T.drillCap-(counts[id] or 0))
   local x,y,nx,ny=site.x+cos(site.angle)*site.radius,site.y+sin(site.angle)*site.radius,cos(site.angle),sin(site.angle)
   if site.area==game.fieldId then x,y,nx,ny=pointAtBody(site,game) end
   for i=1,count do
    site.sequence=site.sequence+1
    local key=id..'/chunk/'..site.sequence
    local radius=28+(site.sequence%4)*5
    local item,yield=Ore.drop('rock',radius)
    local spread=(i-(count+1)/2)*60
    state.resources[key]={id=key,site=id,area=site.area,kind='rock',item=item,yield=yield,
     x=x+nx*(radius+40)-ny*spread,y=y+ny*(radius+40)+nx*spread,
     vx=nx*T.drillEjectSpeed,vy=ny*T.drillEjectSpeed,radius=radius,hp=radius*radius*T.asteroidToughness,
     angle=site.sequence*2.399963,spin=.2,clock=clock,relativeFlow=true}
   end
   if count>0 and site.area==game.fieldId and game.player and not game.player.dead
    and not game.player.removed and not game.player.body:isDestroyed() then
    local px,py=game.player.body:getPosition()
    if (px-x)^2+(py-y)^2<T.sleepNear^2 then
     game:spark(x,y,14,{1,.7,.25})
     game:addEffect({kind='explosion',x=x,y=y,r=90,t=0,life=.4,dust=true})
    end
   end
  end
 end
end
function M.captureResources(game)
 if game.preview then return end
 local resources=M.state(game.universe).resources
 for id,live in pairs(game.miningLive or {}) do
  local r=resources[id]
  if r and live.kind==r.kind then
   if live.kind=='rock' then
    local e=live.object
    if not e.removed and not e.dead and not e.body:isDestroyed() then
     r.x,r.y=e.body:getPosition();r.vx,r.vy=e.body:getLinearVelocity()
     if game.well then r.orbitRate=(r.x*r.vy-r.y*r.vx)/max(1,r.x*r.x+r.y*r.y) end
     r.angle,r.spin,r.hp=e.body:getAngle(),e.body:getAngularVelocity(),e.hp
     r.drilled=e.drilled
     r.verts=copy(e.verts);r.clock=game.universe.clock
    end
   else
    local p=live.object
    if p.count<=0 then resources[id]=nil
    else r.x,r.y,r.vx,r.vy,r.count,r.clock=p.x,p.y,p.vx,p.vy,p.count,game.universe.clock end
   end
  end
 end
end
function M.unload(game)
 M.captureResources(game)
 for _,live in pairs(game.miningLive or {}) do
  if live.kind=='rock' and not live.object.removed then game:remove(live.object,true) end
 end
 local keep={}
 for _,p in ipairs(game.pickups) do if not p.miningId then keep[#keep+1]=p end end
 game.pickups=keep;game.miningLive={}
end
function M.breakRock(game,e,pickup)
 if not e.miningId then return end
 local state=M.state(game.universe);local r=state.resources[e.miningId]
 if r and r.kind=='rock' then
  if pickup then
   r.x,r.y,r.vx,r.vy,r.clock=pickup.x,pickup.y,pickup.vx,pickup.vy,game.universe.clock
   r.kind,r.item,r.count='loot',pickup.item,pickup.count
   pickup.miningId=r.id
   game.miningLive[r.id]={kind='loot',object=pickup}
  else
   -- Collisions and other weapons destroy the resource without a drill yield.
   state.resources[r.id]=nil;game.miningLive[r.id]=nil
  end
 end
end
function M.materialize(game)
 if game.lane or game.flight then return end
 if not game.player or game.player.dead or game.player.removed or game.player.body:isDestroyed() then M.unload(game);return end
 local state=M.state(game.universe)
 game.miningLive=game.miningLive or {}
 local px,py=game.player.body:getPosition()
 local function needed(x,y,range)
  if (x-px)^2+(y-py)^2<range^2 then return true end
  for id,e in pairs(game.alifeOnline or {}) do
   local worker=game.universe.npcs[id]
   if M.isMiner(worker) and worker.task and worker.task.phase=='mining'
    and not e.dead and not e.removed and not e.dockState and not e.body:isDestroyed() then
    local ex,ey=e.body:getPosition()
    if (x-ex)^2+(y-ey)^2<range^2 then return true end
   end
  end
  return false
 end
 for id,r in pairs(state.resources) do
  if r.area==game.fieldId and not game.miningLive[id] then
   local x,y,vx,vy=M.position(r,game.universe.clock)
   if needed(x,y,T.sleepNear) then
    if r.relativeFlow then local fx,fy=game:flowAt(x,y);vx,vy=vx+fx,vy+fy end
    r.relativeFlow=nil
    if r.kind=='rock' then
     local e=game:spawnAsteroid(x,y,r.radius,'rock',r.verts)
     e.miningId,e.hp,e.drilled=r.id,r.hp,r.drilled;e.body:setAngle(r.angle);e.body:setAngularVelocity(r.spin)
     e.body:setLinearVelocity(vx,vy);e.body:setLinearDamping(T.miningChunkDamping)
     game.miningLive[id]={kind='rock',object=e}
    else
     game:spawnPickup(x,y,r.item,r.count)
     local p=game.pickups[#game.pickups];p.miningId=id;p.vx,p.vy=vx,vy
     game.miningLive[id]={kind='loot',object=p}
    end
   end
  end
 end
 -- Keep the physical population local, without discarding its resource records.
 M.captureResources(game)
 for id,live in pairs(game.miningLive) do
  local r=state.resources[id];local object=live.object
  local x,y
  if live.kind=='rock' then
   if not object.removed and not object.body:isDestroyed() then x,y=object.body:getPosition() else x,y=px+T.sleepFar+1,py end
  else x,y=object.x,object.y end
  if not r or not needed(x,y,T.sleepFar) then
   if live.kind=='rock' then if not object.removed then game:remove(object,true) end else object.count=0 end
   game.miningLive[id]=nil
  end
 end
end
function M.point(gameOrUniverse,r,clock)
 local u=gameOrUniverse and (gameOrUniverse.universe or gameOrUniverse)
 local site=r.mineSite or (u and r.task and M.state(u).sites[r.task.target])
 if r.state=='docked' or not site then return L.position(r.base,clock) end
 local x,y=M.workPoint(site)
 if r.task.phase=='delivery' then
  local hx,hy=L.position(r.base,clock)
  local p=r.encounter and r.encounter.progress or min(1,max(0,(clock-r.depart)/max(.1,r.arrive-r.depart)))
  local origin=r.mineDeparture or {x=x,y=y}
  return origin.x+(hx-origin.x)*p,origin.y+(hy-origin.y)*p
 end
 local phase=(tonumber(r.id:match('%d+$')) or 0)*2.3999632297
 return x+cos(phase)*180,y+sin(phase)*180
end
local function room(r,item)
 local used=0
 for id,n in pairs(r.ship.cargo) do used=used+data.items[id].volume*n end
 return max(0,math.floor((Stats.compute(data.hulls[r.ship.hull],r.ship.loadout).hold-used)/data.items[item].volume))
end
function M.returnHome(game,r,x,y)
 r.task.phase='delivery';r.state='travel';r.depart=game.universe.clock
 r.route={r.task.target,r.base};r.index=2;r.node=nil
 r.mineDeparture={x=x,y=y}
 local hx,hy=L.position(r.base,r.depart)
 r.arrive=r.depart+max(1,sqrt((hx-x)^2+(hy-y)^2)/r.speed)
end
function M.advance(game,r,clock)
 local u=game.universe
 if r.state=='dead' or r.state=='escaped' or r.encounter then return end
 if r.state=='docked' and clock>=(r.untilTime or 0) then
  Tasks.arrive(u,r,r.base,clock);r.state='idle';r.task=nil
 end
 if not r.task then r.task=Tasks.choose(u,r,r.base,clock);r.nextMiningAt=clock+T.miningOfflineEvery end
 if not r.task then return end
 r.mineSite=copy(M.state(u).sites[r.task.target])
 if r.task.phase=='mining' then r.route={r.base,r.task.target};r.index=2;r.node=r.task.target end
 if r.task.phase=='delivery' then
  if r.state~='docked' and clock>=r.arrive then r.state='docked';r.untilTime=r.arrive+T.alifeStay end
  return
 end
 if clock<(r.nextMiningAt or 0) then return end
 r.nextMiningAt=clock+T.miningOfflineEvery
 local state=M.state(u);local loot,rock
 for id,resource in pairs(state.resources) do
  if resource.site==r.task.target and not (game.miningLive and game.miningLive[id]) then
   if resource.kind=='loot' then loot=resource;break else rock=resource end
  end
 end
 if loot then
  local n=min(loot.count,room(r,loot.item))
  r.ship.cargo[loot.item]=(r.ship.cargo[loot.item] or 0)+n;loot.count=loot.count-n
  if loot.count<=0 then state.resources[loot.id]=nil end
 elseif rock then
  local stats=Stats.compute(data.hulls[r.ship.hull],r.ship.loadout)
  local energy=max(0,(r.power or stats.powerCap)+stats.powerNet*T.miningOfflineEvery)
  for _,id in ipairs(r.ship.loadout) do
   local m=id and data.modules[id];local w=m and m.weapon
   if w and w.kind=='drill' then
    local seconds=min(T.miningOfflineEvery,energy/max(.001,w.powerPerSecond or 0))
    energy=energy-seconds*(w.powerPerSecond or 0)
    rock.hp=rock.hp-seconds*w.damage*(w.rockDamage or 1)
    if seconds>0 then rock.drilled=true end
   end
  end
  r.power=min(stats.powerCap,max(0,energy))
  if rock.hp<=0 then rock.kind,rock.count='loot',rock.yield end
 end
 if (r.ship.cargo[r.task.item] or 0)>=T.minerLoad or room(r,r.task.item)<=0 then
  M.returnHome(game,r,M.point(u,r,clock))
 end
end
function M.capture(game,e,r,remote)
 r.pose=nil;r.docking=nil
 if not remote then
  local x,y=e.body:getPosition();local vx,vy=e.body:getLinearVelocity()
  r.pose={x=x,y=y,a=e.body:getAngle(),vx=vx,vy=vy,w=e.body:getAngularVelocity(),clock=game.universe.clock}
 end
 if e.dockState then
  r.docking={}
  for k,v in pairs(e.dockState) do if type(v)~='table' and type(v)~='userdata' then r.docking[k]=v end end
  r.state='docked';r.untilTime=game.universe.clock+max(0,(e.dockState.stay or T.alifeStay)-e.dockState.t)
 elseif r.task and r.task.phase=='delivery' and not r.encounter then
  local x,y=e.body:getPosition();local hx,hy=L.position(r.base,game.universe.clock)
  r.mineDeparture={x=x,y=y};r.depart=game.universe.clock
  r.arrive=r.depart+max(1,sqrt((hx-x)^2+(hy-y)^2)/r.speed)
 end
end
function M.bind(game,e,r)
 e.routeIndex=2
 local work={kind='waypoint',hold=true,inspection=true,locationId=r.task and r.task.target,removed=false,
  body={getPosition=function()
   local resource=e.miningResource and M.state(game.universe).resources[e.miningResource]
   if resource and r.task and r.task.phase=='mining' then return M.position(resource,game.universe.clock) end
   local site=r.task and M.state(game.universe).sites[r.task.target]
   if site then
    if r.task.phase=='delivery' then return M.workPoint(site) end
    return M.point(game,r,game.universe.clock)
   end
   return L.position(r.base,game.universe.clock)
  end,getLinearVelocityFromWorldPoint=function()
   local resource=e.miningResource and M.state(game.universe).resources[e.miningResource]
   if resource and r.task and r.task.phase=='mining' then
    local _,_,vx,vy=M.position(resource,game.universe.clock);return vx,vy
   end
   return 0,0
  end}}
 local home=game:locationEntity(r.base)
 if r.task and r.task.phase=='delivery' then e.route={work,home}
 else e.route={home,work} end
end
function M.depart(game,e,station)
 local r=game.universe.npcs[e.alifeId]
 r.ship.cargo=copy(e.cargo)
 Tasks.arrive(game.universe,r,L.canonical(station.locationId),game.universe.clock)
 e.cargo=copy(r.ship.cargo);Ship.updateMass(e)
 Tasks.choose(game.universe,r,r.base,game.universe.clock)
 r.mineSite=r.task and copy(M.state(game.universe).sites[r.task.target])
 r.state='idle';r.nextMiningAt=game.universe.clock+T.miningOfflineEvery
 if r.task then r.route={r.base,r.task.target};r.index=2;r.node=r.task.target end
 M.bind(game,e,r)
 return r.task~=nil
end
local function follow(game,e,AI,x,y,vx,vy,stand,ignore)
 local bx,by=e.body:getPosition();local dx,dy=x-bx,y-by;local d=max(.001,sqrt(dx*dx+dy*dy))
 local want=min(e.def.ai.cruise,max(-120,(d-stand)*.8))
 local sign=want<0 and -1 or 1
 local Nav=require('src.local_navigation')
 local ux,uy,scale=Nav.steer(game,e,dx/d*sign,dy/d*sign,math.abs(want),vx,vy,
  {ignore=ignore,brake=Nav.brakeAccel(e),distance=max(1,math.abs(d-stand))})
 AI.driveVelocity(e,vx+ux*math.abs(want)*scale,vy+uy*math.abs(want)*scale,ux,uy,e.def.ai.throttle)
 return d
end
function M.think(game,e,dt,AI)
 local r=game.universe.npcs[e.alifeId]
 if not M.isMiner(r) then return false end
 if not r.task then
  Tasks.choose(game.universe,r,r.base,game.universe.clock)
  r.mineSite=r.task and copy(M.state(game.universe).sites[r.task.target]);M.bind(game,e,r)
 end
 if not r.task then return true end
 r.mineSite=r.mineSite or copy(M.state(game.universe).sites[r.task.target])
 if e.aggressor and not e.aggressor.dead and not e.aggressor.removed then
  e.miningTarget,e.miningPickup,e.miningResource,e.tractorTarget=nil,nil,nil,nil;e.intent.tractor=false;return false
 end
 if r.task.phase=='delivery' then
  e.miningTarget,e.miningPickup,e.miningResource,e.tractorTarget=nil,nil,nil,nil;e.intent.tractor=false;AI.trade(game,e,dt);return true
 end
 if (e.cargo[r.task.item] or 0)>=T.minerLoad or Ship.canFit(e,r.task.item,1)<=0 then
  e.miningTarget,e.miningPickup,e.miningResource,e.tractorTarget=nil,nil,nil,nil;e.intent.tractor=false
  M.returnHome(game,r,e.body:getPosition());M.bind(game,e,r);AI.trade(game,e,dt);return true
 end
 local x,y=e.body:getPosition()
 if game.time>=(e.miningScan or 0) then
  e.miningScan=game.time+T.miningScan
  e.miningTarget=nil;e.miningPickup=nil;e.miningResource=nil;e.tractorTarget=nil
  local best=math.huge
  for _,p in ipairs(game.pickups) do
   local resource=p.miningId and M.state(game.universe).resources[p.miningId]
   local owner=p.collector
   if resource and resource.site==r.task.target and p.count>0 and (not owner or owner==e or owner.dead or owner.removed or owner.miningPickup~=p) then
    local d=(p.x-x)^2+(p.y-y)^2
    if d<best then e.miningPickup=p;best=d end
   end
  end
  if e.miningPickup then e.miningPickup.collector=e
  else
   for _,o in ipairs(game.entities) do
    local resource=o.miningId and M.state(game.universe).resources[o.miningId]
    local owner=o.miningOwner
    if resource and resource.site==r.task.target and not o.dead and not o.removed
     and (not owner or owner==e or owner.dead or owner.removed or owner.miningTarget~=o) then
     local ox,oy=o.body:getPosition();local d=(ox-x)^2+(oy-y)^2
     if d<best then e.miningTarget=o;best=d end
    end
   end
   if e.miningTarget then e.miningTarget.miningOwner=e end
  end
  -- A capped site can have all its resources outside the local physics band.
  -- Pursue their saved positions instead of waiting forever at an empty node.
  if not e.miningPickup and not e.miningTarget then
   local preferred
   for id,resource in pairs(M.state(game.universe).resources) do
    if resource.site==r.task.target and not (game.miningLive and game.miningLive[id]) then
     local claimed=false
     for _,other in pairs(game.alifeOnline or {}) do
      if other~=e and not other.dead and not other.removed and other.miningResource==id then claimed=true;break end
     end
     if not claimed then
      local rx,ry=M.position(resource,game.universe.clock);local d=(rx-x)^2+(ry-y)^2
      local priority=resource.kind=='loot' and 1 or 0
      if not preferred or priority>preferred or priority==preferred and d<best then
       e.miningResource=id;preferred=priority;best=d
      end
     end
    end
   end
  end
 end
 local pickup=e.miningPickup
 if pickup and pickup.count>0 then
  follow(game,e,AI,pickup.x,pickup.y,pickup.vx,pickup.vy,Ship.tractorRange(e)*.55)
  e.intent.aimX,e.intent.aimY=pickup.x,pickup.y
  -- Navigation owns the goal until collected; the beam only owns it in range.
  local inRange=Ship.distanceTo(e,pickup.x,pickup.y)<=Ship.tractorRange(e)
  e.tractorTarget=inRange and pickup or nil;e.intent.tractor=inRange
 elseif e.miningTarget and not e.miningTarget.dead and not e.miningTarget.removed then
  e.tractorTarget=nil;e.intent.tractor=false
  local rock=e.miningTarget;local rx,ry=rock.body:getPosition();local vx,vy=rock.body:getLinearVelocity()
  local d=follow(game,e,AI,rx,ry,vx,vy,e.noseX+rock.radius+25,rock)
  e.intent.aimX,e.intent.aimY=rx,ry;e.intent.targetDist=nil
  local a=e.body:getAngle();local diff=(math.atan2(ry-y,rx-x)-a+pi)%(2*pi)-pi
  local hit=game:raycast(x+cos(a)*e.halfLength,y+sin(a)*e.halfLength,rx,ry,e.team)
  e.intent.firePrimary=d<e.halfLength*3+rock.radius and math.abs(diff)<.18 and hit and hit.entity==rock or false
 else
  e.tractorTarget=nil;e.intent.tractor=false;AI.trade(game,e,dt)
 end
 return true
end
function M.update(game)
 if game.preview or game.universe.clock<(game.miningNext or 0) then return end
 game.miningNext=game.universe.clock+T.miningScan
 M.captureResources(game);M.produce(game,game.universe.clock);M.materialize(game)
end
function M.draw(game,px)
 local state=game.universe.mining
 if not state then return end
 local lg=love.graphics
 for _,site in pairs(state.sites) do
  if site.area==game.fieldId then
   local x,y,nx,ny=pointAtBody(site,game)
   local cx,cy=game.camera.x,game.camera.y
   if math.abs(x-cx)<love.graphics.getWidth()/game.camera.zoom and math.abs(y-cy)<love.graphics.getHeight()/game.camera.zoom then
    lg.push('all');lg.translate(x,y);lg.rotate(math.atan2(ny,nx))
    lg.setColor(.3,.34,.38);lg.polygon('fill',-12,-26,12,-26,22,0,12,26,-12,26)
    lg.setColor(1,.66,.2);lg.setLineWidth(max(px,2));lg.rectangle('line',-10,-24,24,48)
    lg.setColor(.65,.7,.76);lg.rectangle('fill',-18,-7,46,14)
    lg.setColor(1,.8,.35);lg.circle('fill',28,0,6+2*sin(game.time*14),12)
    lg.setColor(.4,1,.55);lg.circle('fill',6,-16,3*px,8)
    lg.pop()
   end
  end
 end
end
return M
