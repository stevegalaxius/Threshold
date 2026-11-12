-- Drill production and mineral objects have one plain record each. Bodies and
-- pickups are temporary representations, just like the A-Life ships that work them.
local Fields,L,T=require('src.fields'),require('src.locations'),require('src.tuning')
local data,Ship,Stats=require('src.data'),require('src.ship'),require('src.stats')
local Tasks,Hold=require('src.tasks'),require('src.inventory.hold')
local copy=require('src.persistence').copy
local Ore=require('src.ore')
local Population=require('src.population')
local Homes=require('src.npc_home')
local Jobs=require('src.jobs')
local Fuel=require('src.reactor_fuel')
local Actions=require('src.npc_actions')
local Operations=require('src.npc_operations')
local M={}
local sin,cos,sqrt,min,max,pi=math.sin,math.cos,math.sqrt,math.min,math.max,math.pi
function M.state(u) return Jobs.state(u) end
function M.active(r)return r and r.task and r.task.kind=='mine' or false end
function M.workPoint(site)
 return L.position(site.id,0)
end

Tasks.register('mine',{
 requires={capabilities={'cargo','drill'}},
 docks=function(r,id) return L.canonical(id)==L.canonical(r.task.source) end,
 eligible=function(u,r,o,node)
  if o.source~=node or not M.state(u).sites[o.target] then return false end
  if r.ship.hold then return Hold.room(Hold.deserialize(r.ship.hold),o.item,1)>0 end
  local used=0
  for id,n in pairs(r.ship.cargo or {}) do used=used+data.items[id].volume*n end
  return (data.hulls[r.ship.hull].hold or 0)-used>=data.items[o.item].volume
 end,
 score=function(u,r,o)return r.lastMine==o.target and -1 or 0 end,
 prepare=function(u,r,t)
  r.base=t.source
  t.retainedCargo=(r.ship.cargo or {})[t.item] or 0
  t.phase='mining';return true
 end,
 plan=function(t,node,clock) return require('src.travelgraph').itinerary(node,t.phase=='delivery' and t.source or t.target,clock) end,
 complete=function(u,r,t,node)
  if node~=t.source then return false end
  local cargo=r.ship.cargo or {};local n=math.max(0,(cargo[t.item] or 0)-(t.retainedCargo or 0))
  if n<=0 then
   if t.phase=='delivery' then Tasks.release(u,r,'no ore delivered',u.clock) end
   return false
  end
  Jobs.deliver(u,node,t.item,n);require('src.economy').stat(u,'made',t.item,n)
  cargo[t.item]=(cargo[t.item] or 0)-n
  if cargo[t.item]<=0 then cargo[t.item]=nil end
  if r.ship.hold then
   local h=Hold.deserialize(r.ship.hold,function(id)return data.items[id]~=nil end)
   Hold.sync(h,cargo);r.ship.hold=Hold.serialize(h)
  end
  r.lastMine=t.target
  return true
 end,
})
-- Deterministic per ejection, independent of visit order and unrelated RNG.
-- Small fragments are common; large field rocks are occasional.
function M.ejecta(site,sequence)
 local seed=sequence*7919
 for i=1,#site.id do seed=(seed*31+site.id:byte(i))%2147483647 end
 local rng=love.math.newRandomGenerator(seed)
 local size=rng:random()
 local throw=T.drillThrowMin+(T.drillThrowMax-T.drillThrowMin)*rng:random()
 return {radius=T.drillRockMin+(T.drillRockMax-T.drillRockMin)*size*size,
  speed=throw*T.miningChunkDamping,
  spread=(rng:random()*2-1)*T.drillSpread,
  spin=(rng:random()*2-1)*.12,angle=rng:random()*pi*2}
end
local function rigLength() return T.drillRockMax*3+40 end
function M.chunkDamping(area)
 return Fields[area].planetR and T.miningOrbitDamping or T.miningChunkDamping
end
function M.create(game,area,clock)
 local u,f=game.universe,Fields[area]
 Tasks.clean(u,clock)
 local available
 for _,offer in pairs(Tasks.state(u).offers) do
  if offer.kind=='mine' and offer.area==area and offer.state=='available' and (offer.readyAt or 0)<=clock and (not available or offer.id<available.id) then available=offer end
 end
 -- Debug arrivals may exceed the normal population, just like pirate arrivals.
 if not available then
  local id=f.drillIds[(u.nextNpcId%#f.drillIds)+1]
  local site=M.state(u).sites[id]
  available=Tasks.post(u,{kind='mine',source=site.home,target=id,area=area,item=site.item,cooldown=0})
 end
 local home=available.source
 local def=data.enemies.miner_packhorse;local hull=data.hulls[def.hull]
 u.nextNpcId=u.nextNpcId+1
 local r={id='npc/'..u.nextNpcId,archetype='miner_packhorse',home=area,area=area,
  base=home,node=home,route={home,home},index=1,
  state='idle',speed=require('src.npc').cruise('miner_packhorse'),spread=0,
  ship={hull=def.hull,loadout=copy(def.loadout),cargo={},armor=Stats.compute(hull,def.loadout).armor}}
 if game.arrivalShip then r.ship=copy(game.arrivalShip) end
 require('src.npc_templates').apply(r,'miner',area)
 require('src.personality').ensure(r)
 Homes.choose(u,r)
 u.npcs[r.id]=r
 require('src.npc').advance(r,clock,u,game)
 return r
end
function M.seed(game)
 local u=game.universe;local state=M.state(u)
 -- Drop sites whose source is gone (Ring Station's rocks moved to the
 -- Quarry), or their rigs keep drawing and ejecting with nothing to mine.
 for id in pairs(state.sites) do
  if not L.byId[id] then state.sites[id]=nil end
 end
 for offerId,offer in pairs(Tasks.state(u).offers) do
  if offer.kind=='mine' and not L.byId[offer.target] and not offer.owner then Tasks.state(u).offers[offerId]=nil end
 end
 for _,area in ipairs(Fields.list) do
  local specs=Fields.miningSources(area);local f=Fields[area]
  if #specs>0 then
   for index,s in ipairs(specs) do
    local id=area..'/drill/'..index
    if not state.sites[id] then
     local home=L.get(id).motion.home
     local angle=-pi/2
     if home then local hx,hy=L.position(home,0);angle=math.atan2(hy-s.y,hx-s.x) end
     -- A surface drill sits away from the station's roof and docking approach.
     if s.planet then angle=angle+pi end
     state.sites[id]={id=id,area=area,x=s.x,y=s.y,radius=s.radius,planet=s.planet,
      angle=angle,ore=s.ore or 'rock',item=Ore.items[s.ore or 'rock'],
      productionAt=u.clock,productionCarry=0,nextAt=u.clock+(T.drillIntervalMin+T.drillIntervalMax)/2,sequence=0,home=home}

    end
    local site=state.sites[id];site.home=L.get(id).motion.home
    -- what the drill brings up follows the source (Ceres turned to ice)
    site.ore=s.ore or 'rock';site.item=Ore.items[site.ore]
    if site.home and not f.instance then
     local count=0
     for offerId,offer in pairs(Tasks.state(u).offers) do
      if offer.kind=='mine' and offer.target==id then
       if offer.source==site.home then count=count+1;offer.item=site.item
       elseif not offer.owner then Tasks.state(u).offers[offerId]=nil end
      end
     end
     for _=count+1,(#specs==1 and T.minersPerArea or 1) do
      Tasks.post(u,{kind='mine',source=site.home,target=id,area=area,item=site.item,cooldown=0})
     end
    end
    -- Apply rig placement changes to existing saves without resetting resources.
    if s.planet and state.sites[id].home then
     local hx,hy=L.position(state.sites[id].home,0)
     state.sites[id].angle=math.atan2(hy-s.y,hx-s.x)+pi
    end
   end
   if not f.instance and L.station(area,'mining') and not state.seeded[area] then
    state.seeded[area]=true
    for _=1,T.minersPerArea do
     M.create(game,area,u.clock)
    end
   end
  end
 end
end
function M.position(resource,clock) return require('src.loose').position(resource,clock) end
-- Drilled rocks only; loose items use the shared model in src/loose.lua.
function M.rockPosition(resource,clock)
 local elapsed=max(0,clock-(resource.clock or clock));local f=Fields[resource.area]
 if f.planetR then
  local r=max(1,sqrt(resource.x^2+resource.y^2))
  local nx,ny=resource.x/r,resource.y/r
  local radial=resource.vx*nx+resource.vy*ny
  local tangent=-resource.vx*ny+resource.vy*nx
  if resource.relativeFlow then tangent=tangent+290*min(1,f.planetR/6000)*sqrt(f.planetR/max(r,f.planetR))*T.currentScale end
  local damping=resource.kind=='loot' and 1.5 or M.chunkDamping(resource.area)
  local function flow(at)
   return 290*min(1,f.planetR/6000)*sqrt(f.planetR/max(at,f.planetR))*T.currentScale
  end
  -- Radial drift settles into the surrounding belt; excess tangential launch
  -- speed relaxes toward the same orbital current as the physical rocks.
  local excess=tangent-flow(r)
  local function polar(t)
   local decay=math.exp(-damping*t)
   local radius=max(1,r+radial*(1-decay)/damping)
   local speed=flow(radius)+excess*math.exp(-(.1+damping)*t)*r/radius
   return radius,speed,radial*decay
  end
  -- Bounded quadrature follows the curved launch even after dematerializing.
  -- After settling, only the steady orbit remains, regardless of elapsed time.
  local duration=min(elapsed,240);local step=duration/32;local turn=0
  for i=0,32 do
   local radius,speed=polar(i*step)
   local weight=(i==0 or i==32) and 1 or (i%2==0 and 2 or 4)
   turn=turn+weight*speed/radius
  end
  turn=turn*step/3
  local radius,speed,outward=polar(elapsed)
  if elapsed>duration then turn=turn+(elapsed-duration)*speed/radius end
  local angle=math.atan2(resource.y,resource.x)+turn
  local c,s=cos(angle),sin(angle)
  return c*radius,s*radius,c*outward-s*speed,s*outward+c*speed
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
-- Fixed average production rate, independent of scene visibility or update
-- frequency. Only outstanding resources count against the site's buffer.
function M.advanceProduction(u,clock,onlySite)
 local state=M.state(u);local sites=state.sites
 if onlySite then
  local site=sites[onlySite];if not site or (site.productionAt or -1)>=clock then return end
  sites={[onlySite]=site}
 end
 local counts={}
 for _,resource in pairs(state.resources) do if resource.site then counts[resource.site]=(counts[resource.site] or 0)+1 end end
 for id,site in pairs(sites) do
  local period=(T.drillIntervalMin+T.drillIntervalMax)/2
  local crews=1+require('src.arbiter').extraMiners(site.area)/max(1,T.minersPerArea)
  period=period/crews
  local previous=site.productionAt or clock
  local dt=max(0,clock-previous);site.productionAt=clock
  local carry=site.productionCarry or 0
  local work=carry+dt/period
  local whole=math.floor(work+1e-9)
  local room=max(0,T.drillCap-(counts[id] or 0))
  if site.home and site.item and require('src.stockpile').count(u,site.home,site.item)>=T.drillStockCap then room=0 end
  local n=min(whole,room)
  for i=1,n do
   site.sequence=(site.sequence or 0)+1
   local spec=M.ejecta(site,site.sequence);local radius=spec.radius
   local key=id..'/chunk/'..site.sequence
   local nx,ny=cos(site.angle),sin(site.angle)
   local x,y=site.x+nx*site.radius,site.y+ny*site.radius
   local a=site.angle+spec.spread
   local item,yield=Ore.drop(site.ore or 'rock',radius)
   local birth=previous+(i-carry)*period
   state.resources[key]={id=key,site=id,area=site.area,kind='rock',debris=site.ore or 'rock',item=item,yield=yield,
    x=x+nx*(radius+rigLength()+20),y=y+ny*(radius+rigLength()+20),
    vx=cos(a)*spec.speed,vy=sin(a)*spec.speed,radius=radius,hp=radius*radius*T.asteroidToughness,
    angle=spec.angle,spin=spec.spin,clock=birth,readyAt=birth+T.miningSettleTime,relativeFlow=true}
   site.lastAt=birth
  end
  site.productionCarry=(whole>=room) and 0 or max(0,work-whole)
  site.nextAt=clock+(1-site.productionCarry)*period
 end
end
function M.produce(game,clock) M.advanceProduction(game.universe,clock) end
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
    require('src.loose').write(game,r,live.object)
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
 for _,p in ipairs(game.pickups) do if not p.looseId then keep[#keep+1]=p end end
 game.pickups=keep;game.miningLive={}
end
function M.breakRock(game,e,pickup)
 if not e.miningId then return end
 local state=M.state(game.universe);local r=state.resources[e.miningId]
 if r then M.advanceProduction(game.universe,game.universe.clock,r.site) end
 if r and r.kind=='rock' then
  Actions.targetResult(game.universe,r,pickup~=nil,'resource destroyed')
  if pickup and pickup.looseId then
   -- The ore has its own loot record already; it stays reserved for the site.
   local loot=state.resources[pickup.looseId]
   if loot then loot.site=r.site end
   state.resources[r.id]=nil;game.miningLive[r.id]=nil
  else
   -- Collisions and other weapons destroy the resource without a drill yield.
   state.resources[r.id]=nil;game.miningLive[r.id]=nil
  end
 end
end
function M.materialize(game)
 if game.lane or game.flight then return end
 -- game.focus: a map built ahead of the player (Game:stepScene, the lane's
 -- far end) streams in round where the player will come in
 local focus=game.focus
 if not focus and (not game.player or game.player.dead or game.player.removed or game.player.body:isDestroyed()) then M.unload(game);return end
 local state=M.state(game.universe)
 game.miningLive=game.miningLive or {}
 local px,py
 if focus then px,py=focus.x,focus.y else px,py=game.player.body:getPosition() end
 local function needed(x,y,range)
  if (x-px)^2+(y-py)^2<range^2 then return true end
  for id,e in pairs(game.alifeOnline or {}) do
   local worker=game.universe.npcs[id]
   if worker and worker.action and worker.action.target and worker.action.target.provider=='resource'
    and not e.dead and not e.removed and not e.dockState and not e.body:isDestroyed() then
    local ex,ey=e.body:getPosition()
    if (x-ex)^2+(y-ey)^2<range^2 then return true end
   end
  end
  return false
 end
 -- Stream in past the edge of the view, not just T.sleepNear: zoomed out
 -- (T.minZoom) the screen reaches well beyond it, and at speed the ship
 -- covers a lot of ground between scans.
 local near,far=T.sleepNear,T.sleepFar
 local cam=game.camera
 if cam and cam.zoom and cam.zoom>0 and love.graphics then
  local sw,sh=love.graphics.getDimensions()
  local vx,vy
  if focus then vx,vy=focus.vx or 0,focus.vy or 0 else vx,vy=game.player.body:getLinearVelocity() end
  local view=math.sqrt(sw*sw+sh*sh)/2/cam.zoom+math.sqrt(vx*vx+vy*vy)*T.miningScan*2+600
  if view>near then near,far=view,view+(T.sleepFar-T.sleepNear) end
 end
 for id,r in pairs(state.resources) do
  if r.area==game.fieldId and not game.miningLive[id] then
   local x,y,vx,vy=M.position(r,game.universe.clock)
   if needed(x,y,near) and (r.kind~='rock' or game:isClear(x,y,r.radius+10)) then
    if r.relativeFlow and not game.well then local fx,fy=game:flowAt(x,y);vx,vy=vx+fx,vy+fy end
    r.relativeFlow=nil
    if r.kind=='rock' then
     local e=game:spawnAsteroid(x,y,r.radius,r.debris or 'rock',r.verts)
     e.miningId,e.hp,e.drilled=r.id,r.hp,r.drilled;e.body:setAngle(r.angle);e.body:setAngularVelocity(r.spin)
     e.body:setLinearVelocity(vx,vy);e.body:setLinearDamping(M.chunkDamping(r.area))
     game.miningLive[id]={kind='rock',object=e}
    else
     local p=game:pickupView(x,y,r.item,r.count,vx,vy);p.looseId=id
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
   if not object.removed and not object.body:isDestroyed() then x,y=object.body:getPosition() else x,y=px+far+1,py end
  else x,y=object.x,object.y end
  if not r or not needed(x,y,far) then
   if live.kind=='rock' then if not object.removed then game:remove(object,true) end
   else
    -- Drop the view only; its record (if any) stays the authority.
    for i,p in ipairs(game.pickups) do if p==object then table.remove(game.pickups,i);break end end
   end
   game.miningLive[id]=nil
  end
 end
end
-- Jobs select a resource or a destination; shared actions execute both.
function M.returnHome(game,r)
 r.task.phase='delivery'
 return require('src.npc').travel(game,r,r.task.source,game.universe.clock)
end
Actions.registerTarget('resource',{
 resolve=function(ctx,t)
  local record=M.state(ctx.u).resources[t.id];if not record or record.area~=ctx.r.area then return end
  local live=ctx.game and ctx.game.miningLive and ctx.game.miningLive[t.id]
  if not live and ctx.game then
   for _,p in ipairs(ctx.game.pickups or {}) do if p.looseId==t.id and p.count>0 then live={kind='loot',object=p};break end end
  end
  if live and not ctx.e then return end -- live scene owns this resource
  local entity=live and live.object
  local x,y,vx,vy
  if entity and live.kind=='rock' then x,y=entity.body:getPosition();vx,vy=entity.body:getLinearVelocity()
  elseif entity then x,y,vx,vy=entity.x,entity.y,entity.vx,entity.vy
  else x,y,vx,vy=M.position(record,ctx.clock) end
  return {record=record,entity=entity,x=x,y=y,vx=vx,vy=vy,radius=entity and entity.radius or record.radius,
   done=t.expected and record.kind~=t.expected or entity and (entity.dead or entity.removed)}
 end,
 remove=function(ctx,t) local record=M.state(ctx.u).resources[t.id];if record and record.site then M.advanceProduction(ctx.u,ctx.clock,record.site) end;M.state(ctx.u).resources[t.id]=nil end,
})
-- Authored surface-drill ejecta is meant to be worked in the pull band.
-- Reject material inside the solid body, rather than treating all of it as
-- sinking salvage and leaving the site's entire production buffer untouched.
local function mineable(ctx,record,target)
 local site=M.state(ctx.u).sites[record.site]
 if site and site.planet then
  local dx,dy=target.x-site.x,target.y-site.y
  local clear=(site.radius or 0)+(target.radius or 0)
  return dx*dx+dy*dy>=clear*clear
 end
 return not Actions.sinking(ctx.r,target.x,target.y)
end
Actions.targets.resource.safe=function(ctx,target)return mineable(ctx,target.record,target)end
function M.nextAction(ctx)
 local r,t=ctx.r,ctx.r.task
 if t.phase=='delivery' or r.state~='idle' or r.node~=t.target then return end
 local cargo=ctx.e and ctx.e.cargo or r.ship.cargo
 local free=ctx.e and Ship.canFit(ctx.e,t.item,1) or Operations.room(r,t.item)
 if (cargo[t.item] or 0)-(t.retainedCargo or 0)>=T.minerLoad or free<=0 then
  M.returnHome(ctx.game,r);return
 end
 if r.action and r.action.kind=='work' then return r.action end
 if ctx.clock<(r.resourceScanAt or 0) then
  return {kind='hold',key='resource-wait/'..r.resourceScanAt,target={provider='location',id=t.target},untilTime=r.resourceScanAt}
 end
 r.resourceScanAt=ctx.clock+T.miningScan
 local x,y=Actions.actorPosition(ctx);local best,priority,distance
 for id,record in pairs(M.state(ctx.u).resources) do
  if record.site==t.target and ctx.clock>=(record.readyAt or 0) then
   local target=Actions.targets.resource.resolve(ctx,{id=id})
   if target and not target.done and Actions.available(ctx,target) and Actions.targets.resource.safe(ctx,target) then
    local d=(target.x-x)^2+(target.y-y)^2;local p=record.kind=='loot' and 1 or 0
    if not best or p>priority or p==priority and (d<distance or d==distance and id<best) then best,priority,distance=id,p,d end
   end
  end
 end
 if not best then return {kind='hold',key='resource-wait/'..r.resourceScanAt,target={provider='location',id=t.target},untilTime=r.resourceScanAt} end
 local kind=M.state(ctx.u).resources[best].kind
 return {kind='work',operation=kind=='loot' and 'collect' or 'drill',target={provider='resource',id=best,expected=kind}}
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
    -- World-sized structure: the chute clears the largest ejected rock.
    -- Detail and line widths stay in world pixels rather than being enlarged.
    -- A mass catapult: a dome over the bore, a drill derrick, and a launch
    -- rail of coils that light one by one as the next shot charges, then
    -- fire it along the rail. Ice rigs run cold blue, rock rigs amber.
    local length,hw=rigLength(),T.drillRockMax+18
    local ice=site.ore=='ice'
    local glow=ice and {.45,.85,1} or {1,.7,.3}
    local clock=game.universe.clock
    local last=site.lastAt or (site.nextAt-T.drillIntervalMax)
    local charge=max(0,min(1,(clock-last)/max(.01,site.nextAt-last)))
    local fired=max(0,1-(clock-last)/.35)
    lg.push('all');lg.translate(x,y);lg.rotate(math.atan2(ny,nx))
    lg.setLineWidth(max(px,1.5))
    -- footing and dome over the bore
    lg.setColor(.2,.23,.26)
    lg.polygon('fill',-40,-hw-60,10,-hw-44,10,hw+44,-40,hw+60)
    lg.setColor(.3,.34,.38);lg.arc('fill',0,0,hw+30,-pi/2,pi/2,24)
    lg.setColor(.55,.6,.64);lg.arc('line',0,0,hw+30,-pi/2,pi/2,24)
    -- derrick: a lattice tower off to one side of the rail
    local tx=hw*.2
    lg.setColor(.45,.5,.54)
    for _,side in ipairs({-1,1}) do
     local y0=side*(hw+18)
     lg.line(tx,y0,tx+70,y0+side*70);lg.line(tx+44,y0,tx+70,y0+side*70)
     for k=1,3 do local f=k/4;lg.line(tx+f*70,y0+side*f*70,tx+44+f*26,y0+side*f*70) end
     lg.setColor(1,.3,.25);lg.circle('fill',tx+70,y0+side*70,4,8);lg.setColor(.45,.5,.54)
    end
    -- the rail: two bars and a dark bore between them
    local r0,r1=hw+20,length
    lg.setColor(.1,.12,.14);lg.rectangle('fill',r0,-hw*.55,r1-r0,hw*1.1)
    lg.setColor(.58,.63,.66)
    lg.rectangle('fill',r0,-hw*.55-10,r1-r0,10);lg.rectangle('fill',r0,hw*.55,r1-r0,10)
    -- coils: each lights when the charge passes it, all flare when it fires
    local n=7
    for k=0,n-1 do
     local cx=r0+18+k*(r1-r0-36)/(n-1)
     local lit=charge*n>k and .35+.65*min(1,charge*n-k) or 0
     lit=max(lit,fired)
     lg.setColor(.26,.3,.33);lg.rectangle('fill',cx-9,-hw*.55-22,18,hw*1.1+44)
     if lit>0 then
      lg.setColor(glow[1],glow[2],glow[3],lit)
      lg.rectangle('fill',cx-5,-hw*.55-18,10,8);lg.rectangle('fill',cx-5,hw*.55+10,10,8)
      lg.setColor(glow[1],glow[2],glow[3],lit*.18);lg.rectangle('fill',cx-9,-hw*.55,18,hw*1.1)
     end
    end
    -- the round sitting in the breech, and the muzzle flash after a shot
    if charge>.15 and fired<=0 then
     lg.setColor(ice and {.6,.78,.88} or {.42,.38,.34});lg.circle('fill',r0+30,0,min(hw*.45,28),10)
    end
    if fired>0 then
     lg.setColor(glow[1],glow[2],glow[3],fired*.8)
     lg.polygon('fill',r1,-hw*.5,r1+90*fired+20,0,r1,hw*.5)
    end
    -- muzzle beacons
    lg.setColor(glow);lg.circle('fill',r1-6,-hw*.55-14,4,8);lg.circle('fill',r1-6,hw*.55+14,4,8)
    lg.pop()
   end
  end
 end
end
Population.register('miner',{
 -- a base crew, plus whatever the arbiter says unmet ore orders need
 target=function(f,area) return #f.drillIds>0 and L.station(area,'mining') and T.minersPerArea+require('src.arbiter').extraMiners(area) end,
 nodes=function(game,area) return Fields[area].drillIds end,
 create=function(game,area,node,clock) return M.create(game,area,clock) end,
})
local work=Tasks.definitions.mine
work.nextAction=M.nextAction
return M
