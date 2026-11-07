-- Drill production and mineral objects have one plain record each. Bodies and
-- pickups are temporary representations, just like the A-Life ships that work them.
local Fields,L,T=require('src.fields'),require('src.locations'),require('src.tuning')
local data,Ship,Stats=require('src.data'),require('src.ship'),require('src.stats')
local Tasks,Hold=require('src.tasks'),require('src.inventory.hold')
local copy=require('src.persistence').copy
local Ore=require('src.ore')
local Population=require('src.population')
local Repairs=require('src.npc_repair')
local Supplies=require('src.supplies')
local Homes=require('src.npc_home')
local Jobs=require('src.jobs')
local Fuel=require('src.reactor_fuel')
local M={}
local sin,cos,sqrt,min,max,pi=math.sin,math.cos,math.sqrt,math.min,math.max,math.pi
function M.state(u) return Jobs.state(u) end
function M.isMiner(r)return r and r.role=='miner' end
-- Miners fly straight between their base and a rock field and drill there;
-- that world model is theirs. Upkeep, fuel and speed are the shared loop's.
require('src.npc').job('miner',{
 match=M.isMiner,
 docks=function(r,id) return id==r.base end,
 next=function() return nil end,
 advance=function(game,r,clock) return M.advance(game,r,clock) end,
})
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
  local cargo=r.ship.cargo or {};local n=cargo[t.item] or 0
  if n<=0 then return false end
  Jobs.deliver(u,node,t.item,n)
  cargo[t.item]=nil
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
 return {radius=T.drillRockMin+(T.drillRockMax-T.drillRockMin)*size*size,
  speed=T.drillSpeedMin+(T.drillSpeedMax-T.drillSpeedMin)*rng:random(),
  spread=(rng:random()*2-1)*T.drillSpread,
  spin=(rng:random()*2-1)*.12,angle=rng:random()*pi*2,
  delay=T.drillIntervalMin+(T.drillIntervalMax-T.drillIntervalMin)*rng:random()}
end
local function rigLength() return T.drillRockMax*2+20 end
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
 local r={id='npc/'..u.nextNpcId,role='miner',archetype='miner_packhorse',home=area,area=area,
  base=home,node=home,route={home,home},index=1,
  state='idle',speed=require('src.npc').cruise('miner_packhorse'),spread=0,
  ship={hull=def.hull,loadout=copy(def.loadout),cargo={},armor=Stats.compute(hull,def.loadout).armor}}
 Homes.assign(r,home)
 u.npcs[r.id]=r
 M.advance(game,r,clock)
 return r
end
function M.seed(game)
 local u=game.universe;local state=M.state(u)
 -- Upgrade existing workers without replacing their identity, task or cargo.
 for _,r in pairs(u.npcs) do
  if M.isMiner(r) and r.ship.hull=='intaki_wisp' then
   local def=data.enemies.miner_packhorse
   local old=Stats.compute(data.hulls[r.ship.hull],r.ship.loadout)
   local fitted=Stats.compute(data.hulls[def.hull],def.loadout)
   r.ship.armor=fitted.armor*min(1,(r.ship.armor or old.armor)/old.armor)
   r.ship.hull,r.ship.loadout=def.hull,copy(def.loadout)
   r.archetype,r.speed=def.id,require('src.npc').cruise(def.id)
  end
 end
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
      angle=angle,item=Ore.items.rock,
      nextAt=u.clock+M.ejecta({id=id},1).delay,sequence=0,home=home}

    end
    local site=state.sites[id];site.home=L.get(id).motion.home
    if site.home and not f.instance then
     local count=0
     for offerId,offer in pairs(Tasks.state(u).offers) do
      if offer.kind=='mine' and offer.target==id then
       if offer.source==site.home then count=count+1
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
function M.produce(game,clock)
 local state=M.state(game.universe)
 local counts={}
 for _,resource in pairs(state.resources) do if resource.site then counts[resource.site]=(counts[resource.site] or 0)+1 end end
 for id,site in pairs(state.sites) do
  if clock>=site.nextAt then
   -- One irregular ejection, never a catch-up volley after travel or loading.
   local spec=M.ejecta(site,site.sequence+1)
   site.nextAt=clock+spec.delay
   local count=(counts[id] or 0)<T.drillCap and 1 or 0
   local x,y,nx,ny=site.x+cos(site.angle)*site.radius,site.y+sin(site.angle)*site.radius,cos(site.angle),sin(site.angle)
   if site.area==game.fieldId then x,y,nx,ny=pointAtBody(site,game) end
   if count>0 then
    site.sequence=site.sequence+1
    local key=id..'/chunk/'..site.sequence
    local radius=spec.radius
    local item,yield=Ore.drop('rock',radius)
    local a=site.angle+spec.spread
    local dx,dy=cos(a),sin(a)
    if Fields[site.area].planetR then
     -- Join the planet's clockwise flow. Variation changes orbital speed and
     -- gentle outward drift, never the direction of a random radial spray.
     local outward=T.miningOutwardRatio*(1+spec.spread*.25)
     dx,dy=-ny+nx*outward,nx+ny*outward
    end
    state.resources[key]={id=key,site=id,area=site.area,kind='rock',item=item,yield=yield,
     x=x+nx*(radius+rigLength()+20),y=y+ny*(radius+rigLength()+20),
     vx=dx*spec.speed,vy=dy*spec.speed,radius=radius,hp=radius*radius*T.asteroidToughness,
     angle=spec.angle,spin=spec.spin,clock=clock,readyAt=clock+T.miningSettleTime,relativeFlow=true}
   end
   if count>0 and site.area==game.fieldId and game.player and not game.player.dead
    and not game.player.removed and not game.player.body:isDestroyed() then
    local px,py=game.player.body:getPosition()
    if (px-x)^2+(py-y)^2<T.sleepNear^2 then
     local ex,ey=x+nx*rigLength(),y+ny*rigLength()
     game:spark(ex,ey,8,{1,.7,.25})
     game:addEffect({kind='explosion',x=ex,y=ey,r=spec.radius*.8,t=0,life=.3,dust=true})
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
 if r and r.kind=='rock' then
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
 -- Stream in past the edge of the view, not just T.sleepNear: zoomed out
 -- (T.minZoom) the screen reaches well beyond it, and at speed the ship
 -- covers a lot of ground between scans.
 local near,far=T.sleepNear,T.sleepFar
 local cam=game.camera
 if cam and cam.zoom and cam.zoom>0 and love.graphics then
  local sw,sh=love.graphics.getDimensions()
  local vx,vy=game.player.body:getLinearVelocity()
  local view=math.sqrt(sw*sw+sh*sh)/2/cam.zoom+math.sqrt(vx*vx+vy*vy)*T.miningScan*2+600
  if view>near then near,far=view,view+(T.sleepFar-T.sleepNear) end
 end
 for id,r in pairs(state.resources) do
  if r.area==game.fieldId and not game.miningLive[id] then
   local x,y,vx,vy=M.position(r,game.universe.clock)
   if needed(x,y,near) then
    if r.relativeFlow and not game.well then local fx,fy=game:flowAt(x,y);vx,vy=vx+fx,vy+fy end
    r.relativeFlow=nil
    if r.kind=='rock' then
     local e=game:spawnAsteroid(x,y,r.radius,'rock',r.verts)
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
 if r.state=='docked' then Repairs.advance(r,clock,r.base) end
 if r.state=='docked' and clock>=(r.untilTime or 0) then
  if r.repairReturn and r.task and (r.ship.cargo[r.task.item] or 0)==0 then
   r.task.phase='mining';r.state='idle'
  else Tasks.arrive(u,r,r.base,clock);r.state='idle';r.task=nil end
  r.repairReturn=nil
  Supplies.refill(r,r.base)
 end
 if not r.task then r.task=Tasks.choose(u,r,r.base,clock);r.nextMiningAt=clock+T.miningOfflineEvery end
 if not r.task then
  r.state='docked';r.node=r.base;r.route={r.base,r.base};r.index=1;r.untilTime=clock+10;return
 end
 r.mineSite=copy(M.state(u).sites[r.task.target])
 if r.task.phase=='mining' and ((Repairs.needs(r) and Repairs.supports(r.base)) or (Supplies.needs(r) and Supplies.supports(r.base))) then r.repairReturn=true;M.returnHome(game,r,M.point(u,r,clock)) end
 if r.task.phase=='mining' then r.route={r.base,r.task.target};r.index=2;r.node=r.task.target end
 if r.task.phase=='delivery' then
  if r.state~='docked' and clock>=r.arrive then r.state='docked';Repairs.begin(r,r.base,r.arrive,T.alifeStay) end
  return
 end
 -- Restore a saved physical worker before allowing any abstract mining tick.
 if r.savedOnline and r.pose and math.abs(clock-r.pose.clock)<.001 then return end
 if clock<(r.nextMiningAt or 0) then return end
 r.nextMiningAt=clock+T.miningOfflineEvery
 local state=M.state(u);local loot,rock
 for id,resource in pairs(state.resources) do
  if resource.site==r.task.target and game.universe.clock>=(resource.readyAt or 0) and not (game.miningLive and game.miningLive[id]) then
   if resource.kind=='loot' then loot=resource;break else rock=resource end
  end
 end
 local elapsed=math.min(T.miningOfflineEvery,math.max(0,clock-(r.fuelClock or clock-T.miningOfflineEvery)))
 r.fuelClock=clock
 local requested=0
 if rock and not loot then
  for _,id in ipairs(r.ship.loadout) do
   local w=id and data.modules[id] and data.modules[id].weapon
   if w and w.kind=='drill' then requested=requested+(w.powerPerSecond or 0)*elapsed end
  end
 end
 local energy=Fuel.withRecord(r,function(e,s)
  local _,delivered=Fuel.step(e,s,elapsed,false,requested)
  return delivered
 end)
 if loot then
  local n=min(loot.count,room(r,loot.item))
  r.ship.cargo[loot.item]=(r.ship.cargo[loot.item] or 0)+n;loot.count=loot.count-n
  if loot.count<=0 then state.resources[loot.id]=nil end
 elseif rock then
  for _,id in ipairs(r.ship.loadout) do
   local m=id and data.modules[id];local w=m and m.weapon
   if w and w.kind=='drill' then
    local seconds=min(elapsed,energy/max(.001,w.powerPerSecond or 0))
    energy=energy-seconds*(w.powerPerSecond or 0)
    rock.hp=rock.hp-seconds*w.damage*(w.rockDamage or 1)
    if seconds>0 then rock.drilled=true end
   end
  end
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
  r.docking.mooring=copy(e.dockState.mooring)
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
 if r.repairReturn and r.task and (e.cargo[r.task.item] or 0)==0 then r.task.phase='mining' end
 r.repairReturn=nil
 Tasks.arrive(game.universe,r,L.canonical(station.locationId),game.universe.clock)
 Supplies.refill(r,L.canonical(station.locationId))
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
 local Nav=require('src.local_navigation')
 local gx,gy=x-dx/d*stand,y-dy/d*stand
 local wx,wy=Nav.waypoint(game,e,gx,gy,{ignore=ignore,cx=x,cy=y,stand=stand})
 local rx,ry=wx-bx,wy-by;local leg=max(.001,sqrt(rx*rx+ry*ry))
 local want=min(require('src.npc').liveCruise(e),leg*.8,sqrt(2*Nav.brakeAccel(e)*leg))
 local ux,uy,scale=Nav.steer(game,e,rx/leg,ry/leg,want,vx,vy,
  {ignore=ignore,brake=Nav.brakeAccel(e),distance=leg})
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
 if r.task.phase=='mining' and ((Repairs.needs(r,e.armor,e.stats.armor) and Repairs.supports(r.base)) or (Supplies.needs(r,e) and Supplies.supports(r.base))) then
  e.miningTarget,e.miningPickup,e.miningResource,e.tractorTarget=nil,nil,nil,nil;e.intent.tractor=false
  r.repairReturn=true;M.returnHome(game,r,e.body:getPosition());M.bind(game,e,r);AI.trade(game,e,dt);return true
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
   local resource=p.looseId and M.state(game.universe).resources[p.looseId]
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
    if resource and resource.site==r.task.target and game.universe.clock>=(resource.readyAt or 0) and not o.dead and not o.removed
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
    if resource.site==r.task.target and game.universe.clock>=(resource.readyAt or 0) and not (game.miningLive and game.miningLive[id]) then
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
    -- World-sized structure: the chute clears the largest ejected rock.
    -- Detail and line widths stay in world pixels rather than being enlarged.
    local length,hw=rigLength(),T.drillRockMax+18
    lg.push('all');lg.translate(x,y);lg.rotate(math.atan2(ny,nx))
    lg.setLineWidth(max(px,1.5))
    lg.setColor(.22,.25,.28)
    lg.polygon('fill',-28,-hw-26,16,-hw-26,32,-hw+10,32,hw-10,16,hw+26,-28,hw+26)
    lg.setColor(.34,.39,.43)
    lg.polygon('fill',8,-hw,76,-hw,98,-hw+22,98,hw-22,76,hw,8,hw)
    lg.setColor(.57,.62,.64)
    lg.polygon('line',8,-hw,76,-hw,98,-hw+22,98,hw-22,76,hw,8,hw)
    -- Open conveyor/ejector bed, with structural rails and braces.
    lg.setColor(.12,.15,.18);lg.rectangle('fill',48,-hw+12,length-48,hw*2-24)
    for j=0,5 do
     local bx=60+j*(length-76)/5
     lg.setColor(.39,.44,.47);lg.rectangle('fill',bx,-hw+17,7,hw*2-34)
    end
    lg.setColor(.62,.66,.68)
    lg.rectangle('fill',46,-hw,length-46,10);lg.rectangle('fill',46,hw-10,length-46,10)
    lg.setColor(.32,.37,.4)
    lg.polygon('fill',40,-hw-8,length-18,-hw-8,length,-hw,40,-hw)
    lg.polygon('fill',40,hw, length,hw,length-18,hw+8,40,hw+8)
    -- Separate drives and warning markings retain ship-scale detail.
    for _,side in ipairs({-1,1}) do
     lg.setColor(.46,.5,.52);lg.rectangle('fill',18,side*(hw-27)-12,40,24)
     lg.setColor(.92,.64,.22)
     for j=0,3 do lg.rectangle('fill',24+j*8,side*(hw+5)-3,4,6) end
    end
    lg.setColor(.13,.17,.19);lg.rectangle('fill',16,-30,26,60)
    lg.setColor(.6,.65,.68)
    for j=0,4 do lg.line(20,-23+j*11,38,-23+j*11) end
    lg.setColor(.4,1,.55);lg.circle('fill',29,-43,3,8)
    lg.setColor(1,.65,.2);lg.circle('fill',length-8,-hw-4,3,8);lg.circle('fill',length-8,hw+4,3,8)
    lg.pop()
   end
  end
 end
end
Population.register('miner',{
 target=function(f,area) return #f.drillIds>0 and L.station(area,'mining') and T.minersPerArea end,
 nodes=function(game,area) return Fields[area].drillIds end,
 create=function(game,area,node,clock) return M.create(game,area,clock) end,
})
return M
