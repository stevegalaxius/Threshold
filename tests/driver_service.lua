-- A ship on its way out through a mass driver that needs a repair visit
-- turns round where it is: its offline position never jumps, and no leg of
-- the visit starts at the driver itself (offline that is inside the gun, so
-- the ship would wake there).
return function(game)
 local A,L,G,T=require('src.alife'),require('src.locations'),require('src.travelgraph'),require('src.tuning')
 local Upkeep,Fields=require('src.upkeep'),require('src.fields')
 local copy=require('src.persistence').copy
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 game.autosaveOff=true;game:loadField('mars')
 local u=game.universe;local clock=u.clock
 local driver=Fields.mars.driverId
 local template
 for _,r in pairs(u.npcs) do if (r.populationGroup or r.role)=='trader' and r.home=='mars' then template=r;break end end
 assert(template,'no Mars trader')
 local home=L.station('mars','trade')
 local path=G.itinerary(home,L.station('earth','trade'),clock)
 assert(path,'no route Mars -> Earth')
 local at
 for i,id in ipairs(path) do if id==driver then at=i;break end end
 assert(at and at>1,'route does not leave through the driver')
 for _,p in ipairs({.3,.7,.95}) do
  local r=copy(template);r.id='npc/driver_service_'..p
  r.route=copy(path);r.index=at;r.state='travel';r.area='mars'
  r.service=nil;r.encounter=nil;r.worldRecovery=nil;r.waitingForHome=nil;r.driverState=nil
  r.offset=nil;r.pose=nil;r.queue=nil;r.nextServiceAt=nil;r.driverArrival=nil
  local duration=G.length(G.build('mars'),{from=path[at-1],to=driver},clock)/r.speed
  r.depart=clock-p*duration;r.arrive=r.depart+duration
  r.ship.armor=1 -- badly hurt: a repair is due
  u.npcs[r.id]=r
  local x,y=A.point(r,clock)
  check(Upkeep.plan(r,clock),'repair visit planned on the way out at p='..p)
  -- (where it is on its leg: a dock queue may line it up from there)
  local booked=r.queue;r.queue=nil
  local xx,yy=A.point(r,clock)
  r.queue=booked
  check((x-xx)^2+(y-yy)^2<50^2,('ship stays put when the visit is planned (moved %.0f px)'):format(math.sqrt((x-xx)^2+(y-yy)^2)))
  check(r.route[r.index]~=driver,'the leg under way no longer ends at the driver')
  for i=2,#r.route-1 do
   check(r.route[i]~=driver,'the visit never turns round at the driver ('..table.concat(r.route,' ')..')')
  end
  check(r.route[#r.route]==driver,'the visit ends back at the driver')
  local gx,gy=L.position(driver,clock);local hx,hy=A.point(r,clock)
  local clear=(T.driverBarrel+T.driverRadius)^2
  if (x-gx)^2+(y-gy)^2>clear then check((hx-gx)^2+(hy-gy)^2>clear,'not drawn on the driver at p='..p) end
  -- woken here (the player close by), it comes up clear of the gun
  game.player.body:setPosition(hx+3000,hy)
  local snapshot=copy(r)
  local e=A.wake(game,r)
  local ex,ey=e.body:getPosition()
  local drv=game:findDriver();local cx,cy=drv.body:getPosition()
  check((ex-cx)^2+(ey-cy)^2>clear,('woke inside the driver at p=%s (%.0f px from its middle)'):format(p,math.sqrt((ex-cx)^2+(ey-cy)^2)))
  game.alifeOnline[r.id]=nil;game:remove(e,true)
  r=snapshot;u.npcs[r.id]=r
  -- run it through: never on the driver until it comes back to leave by it
  for t=clock,clock+3600,5 do
   A.advance(r,t,u,game)
   if r.state=='transit' or r.area~='mars' then break end
   local from=r.route and r.route[(r.index-2)%#r.route+1]
   if r.state=='travel' and r.route[r.index]~=driver and from~=driver then
    local x,y=A.point(r,t);local gx,gy=L.position(driver,t)
    check((x-gx)^2+(y-gy)^2>clear,('on the driver at t=%.0f (p=%s), on its way to %s'):format(t-clock,p,r.route[r.index]))
   end
  end
  u.npcs[r.id]=nil
 end
 print(('DRIVER SERVICE TEST PASSED (%d checks)'):format(checks))
end
