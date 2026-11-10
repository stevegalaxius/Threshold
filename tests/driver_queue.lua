return function(game)
 local A=require('src.alife');local Q=require('src.queue');local AI=require('src.ai');local copy=require('src.persistence').copy
 game:loadField('mars');game:captureALife(true)
 local template
 for _,r in pairs(game.universe.npcs)do if r.home=='mars' and r.archetype then template=copy(r);break end end
 assert(template)
 for _,e in pairs(game.alifeOnline)do game:remove(e,true)end
 game.alifeOnline={};game.universe.npcs={}
 local F=require('src.fields');local g=game:locationEntity(F.mars.driverId)
 local x,y=game:driverBreech(g);local clock=game.universe.clock
 local ships={}
 for i=1,3 do
  local r=copy(template);r.id='driver/'..i;r.area='mars';r.home='mars';r.taskWorker=true
  r.state='travel';r.route={F.mars.buoyIds[1],F.mars.driverId,F.earth.driverId};r.index=2
  r.task=nil;r.action=nil;r.service=nil;r.transit=nil;r.savedOnline=nil
  r.depart=clock-100;r.arrive=clock-20
  r.pose={x=x-math.cos(g.angle)*(100+(i-1)*600),y=y-math.sin(g.angle)*(100+(i-1)*600),a=g.angle,vx=0,vy=0,w=0,clock=clock}
  game.universe.npcs[r.id]=r;Q.leg(r);r.queue.ready=clock-10
  ships[i]=A.wake(game,r)
 end
 assert(not Q.holding(game,ships[1],ships[1].route[2]),'first ship should approach free driver')
 assert(Q.holding(game,ships[2],ships[2].route[2]),'expired bookings let the second ship enter with the first')
 assert(Q.holding(game,ships[3],ships[3].route[2]),'third ship did not queue')
 AI.trade(game,ships[1],1/120)
 assert(ships[1].driverTractor,'first ship did not capture')
 assert(Q.holding(game,ships[2],ships[2].route[2]),'occupied driver did not hold next ship')
 AI.trade(game,ships[2],1/120);AI.trade(game,ships[3],1/120)
 local a,b=ships[2].navAim,ships[3].navAim
 assert(a and b and math.abs(math.sqrt((a.sx-b.sx)^2+(a.sy-b.sy)^2)-require('src.tuning').queueGap)<.01,'waiting ships did not steer to separate queue positions')
 game:remove(ships[1],true);g.driverShip=nil
 assert(not Q.holding(game,ships[2],ships[2].route[2]) and Q.holding(game,ships[3],ships[3].route[2]),'releasing the driver did not admit exactly the next ship')
 g.driverShip=game.player
 assert(Q.holding(game,ships[2],ships[2].route[2]),'player occupancy did not hold the line')
 g.driverShip=nil
 -- Repeated queries share one line calculation until the next simulation tick.
 local stopPoint=AI.stopPoint;local samples=0
 AI.stopPoint=function(...)samples=samples+1;return stopPoint(...)end
 game.universe.clock=game.universe.clock+1/120
 Q.holding(game,ships[2],ships[2].route[2]);local firstSamples=samples
 Q.holding(game,ships[3],ships[3].route[2]);Q.holding(game,ships[2],ships[2].route[2])
 AI.stopPoint=stopPoint
 assert(firstSamples>0 and samples==firstSamples,'same-tick queue queries recalculated the line')
 print('DRIVER QUEUE: expired bookings, spaced holding points and ordered admission passed')
end
