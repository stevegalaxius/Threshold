-- Live admission follows occupied runways and arrival order, not ETA bookings.
return function(game)
 local A=require('src.alife');local Q=require('src.queue');local AI=require('src.ai')
 local L=require('src.locations');local copy=require('src.persistence').copy
 game:loadField('earth');game:captureALife(true)
 local template
 for _,r in pairs(game.universe.npcs) do
  if r.home=='earth' and r.populationGroup=='patrol' then template=copy(r);break end
 end
 assert(template,'missing dock queue fixture')
 local target=L.station('earth','trade');local st=assert(game:locationEntity(target))
 local x,y=AI.stopPoint(st)
 local function ship(id)
  local r=copy(template);r.id=id;r.state='travel';r.area='earth'
  r.route={require('src.fields').earth.buoyIds[1],target};r.index=2
  r.task=nil;r.action=nil;r.service={station=target,need='fuel'}
  r.depart=game.universe.clock;r.arrive=r.depart+60
  r.pose={x=x,y=y,a=0,vx=0,vy=0,w=0,clock=game.universe.clock}
  game.universe.npcs[id]=r;Q.leg(r);r.queue.ready=r.arrive+600
  return r,A.wake(game,r)
 end
 -- Clear unrelated traffic so this is one controlled station approach.
 for _,e in pairs(game.alifeOnline) do game:remove(e,true) end
 game.alifeOnline={};game.universe.npcs={}
 local r,first=ship('dock/first')
 assert(not Q.holding(game,first,st),'free runway waited for a future booking')
 assert(not Q.waiting(r,game.universe.clock,game),'debug state reports an artificial wait')
 local dock=AI.approachDock(first,st)
 game.player.dockState={station=st,dock=dock,phase='tractor'}
 assert(Q.holding(game,first,st),'occupied player beam did not hold arrivals')
 game.player.dockState=nil
 game.universe.clock=game.universe.clock+1
 local _,second=ship('dock/second')
 second.approach={stop=st,dock=dock}
 assert(not Q.holding(game,first,st) and Q.holding(game,second,st),'actual arrival order was not preserved')
 game:beginDocking(first,st,1,dock)
 assert(Q.holding(game,second,st),'NPC beam did not hold the next ship')
 local otherDock
 for _,candidate in ipairs(st.docks) do if candidate~=dock then otherDock=candidate;break end end
 assert(otherDock,'fixture needs two runways')
 second.approach={stop=st,dock=otherDock}
 local sx,sy=AI.stopPoint(st,second);second.body:setPosition(sx,sy)
 assert(not Q.holding(game,second,st),'occupied runway blocked a separate free runway')
 second.approach={stop=st,dock=dock};second.body:setPosition(x,y)
 first.dockState.done=true;first.dockState.phase='done'
 assert(not Q.holding(game,second,st),'completed docking did not release the runway')
 first.dockState=nil;first.dockExit={station=st,dock=dock}
 assert(Q.holding(game,second,st),'outbound ship did not hold arrivals')
 print('DOCK QUEUE: free approaches, arrival order and occupied runways passed')
end
