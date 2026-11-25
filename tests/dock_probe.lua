-- Docking probe: love . --dockprobe [minutes]
-- Runs the starting map and reports how NPCs dock and launch: docks
-- completed, station contacts by NPC ships above the ram grace (and at what
-- speed, in which phase), and NPC deaths against stations.
return function(game)
 local T=require('src.tuning')
 local events=require('src.events')
 local minutes=3
 for _,a in ipairs(arg or {}) do if tonumber(a) then minutes=tonumber(a) end end
 game.autosaveOff=true
 game:loadField(require('src.fields').start)
 local docks,undocks,glides,hits,deaths,maxHit=0,0,0,{},0,0
 events.on('dock',function(e) if not e.isPlayer then docks=docks+1 end end)
 local undockAt={}
 events.on('undock',function(e) if not e.isPlayer then undocks=undocks+1;undockAt[e]=game.time end end)
 local seen={}
 local begin=game.beginContact
 game.beginContact=function(self,fa,fb,contact)
  local a,b=fa:getUserData(),fb:getUserData()
  if a and b and a.body and b.body and not fa:isSensor() and not fb:isSensor() then
   local ship,st=a,b
   if b.kind=='ship' then ship,st=b,a end
   if ship.kind=='ship' and not ship.isPlayer and st.kind=='station' then
    local x,y=contact:getPositions()
    if x then
     local nx,ny=contact:getNormal()
     local avx,avy=a.body:getLinearVelocityFromWorldPoint(x,y)
     local bvx,bvy=b.body:getLinearVelocityFromWorldPoint(x,y)
     local v=(avx-bvx)*nx+(avy-bvy)*ny
     if v>T.ramGrace then
      local phase=ship.dockState and ship.dockState.phase or ship.launchGlide and 'launch' or ship.dockExit and 'exit' or ship.bayExit and 'bayExit' or 'flight'
      local stop=ship.route and ship.route[ship.routeIndex or 1]
      local held=stop and require('src.queue').holding(self,ship,stop)
      local sx,sy=st.body:getPosition();local px,py=ship.body:getPosition()
      local r=require('src.alife') and game.universe.npcs[ship.alifeId]
      hits[#hits+1]=('%s %s %s %.0f px/s (%s) stop=%s held=%s cd=%.1f r=%.0f hull=%.0f task=%s state=%s'):format(tostring(ship.alifeId),ship.hull and ship.hull.id,tostring(st.locationId),v,phase,
       tostring(stop and (stop.locationId or stop.kind)),tostring(held),ship.dockCooldown or 0,math.sqrt((px-sx)^2+(py-sy)^2),require('src.ai').hullRadius(st),
       tostring(r and r.task and r.task.kind),tostring(r and r.state))
       ..(' sinceUndock=%s bayExit=%s'):format(undockAt[ship] and ('%.1f'):format(game.time-undockAt[ship]) or '-',tostring(ship.bayExit~=nil))..(' act=%s ship=%.0f stpt=%.0f w=%.3f'):format(tostring(r and r.action and (r.action.kind..'/'..tostring(r.action.operation))),
        math.sqrt(ship.body:getLinearVelocity()^2+select(2,ship.body:getLinearVelocity())^2),
        math.sqrt(st.body:getLinearVelocityFromWorldPoint(x,y)^2+select(2,st.body:getLinearVelocityFromWorldPoint(x,y))^2),st.body:getAngularVelocity())
      if v>maxHit then maxHit=v end
     end
    end
   end
  end
  return begin(self,fa,fb,contact)
 end
 events.on('kill',function(victim) if victim and victim.kind=='ship' and not victim.isPlayer and victim.stationImpact then deaths=deaths+1 end end)
 local stuck={}
 for i=1,math.floor(minutes*60*60) do
  game:step(1/60)
  if i%60==0 then
   for _,e in ipairs(game.entities) do
    if e.dockState and e.dockState.phase=='glide' and not seen[e] then seen[e]=true;glides=glides+1 end
    if e.dockState and e.dockState.phase=='glide' and e.dockState.t>60 then stuck[e]=true end
   end
  end
 end
 local nstuck=0 for _ in pairs(stuck) do nstuck=nstuck+1 end
 print(('dock probe: %d min, %d glides begun, %d NPC docks, %d launches, %d station hits > %d px/s (max %.0f), %d station deaths, %d glides over 60s')
  :format(minutes,glides,docks,undocks,#hits,T.ramGrace,maxHit,deaths,nstuck))
 for i=1,math.min(#hits,40) do print('  '..hits[i]) end
end
