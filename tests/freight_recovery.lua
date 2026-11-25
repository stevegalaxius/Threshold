return function()
 local Game,Ship,AI=require('src.game'),require('src.ship'),require('src.ai')
 local NPC,ALife,Tasks=require('src.npc'),require('src.alife'),require('src.tasks')
 local Locations,T=require('src.locations'),require('src.tuning')
 local game=Game.new({preview=true})
 local source,target='station:earth_3','station:earth_1'
 local u=game.universe
 game.fieldId='earth'
 game.alifeOnline={}
 local function run(phase)
  local destination=phase=='pickup' and source or target
  local station=game:locationEntity(destination) or Locations.spawnStation(game,destination)
  station.docks={station.dock}
  local x,y=station.body:getPosition()
  local e=Ship.new(game,{hull='intaki_wisp',x=x+2000,y=y,team=3})
  local offer=Tasks.post(u,{kind='transport',source=source,target=target,item='steel_plate',amount=3,order=true,stocked=true})
  local r={id='npc/freight-test',ship=Ship.record(e),state='travel',area='earth',node=target,
   speed=600,depart=u.clock,arrive=u.clock+80,index=2,route=phase=='pickup' and {target,source} or {source,target}}
  r.task={id=offer.id,kind='transport',source=source,target=target,phase=phase,item=offer.item,amount=offer.amount}
  if phase=='delivery' then offer.loaded=true;e.cargo[offer.item]=offer.amount end
  offer.owner,offer.state=r.id,'reserved'
  e.alifeId,e.alifeRecord=r.id,r
  u.npcs[r.id]=r;game.alifeOnline[r.id]=e
  ALife.bindRoute(game,e,r)
  local function tick(seconds)
   for _=1,seconds do
    u.clock=u.clock+T.npcDecisionInterval
    NPC.recoverFreight(NPC.context(game,r,u.clock,e,1/60,AI))
   end
  end
  -- A real queue result pauses the timer even while the body is still.
  local blocker=Ship.new(game,{hull='intaki_wisp',x=x,y=y,team=3})
  blocker.dockExit={station=station,dock=AI.approachDock(e,station)}
  game.entities[#game.entities+1]=blocker
  assert(require('src.queue').holding(game,e,e.route[e.routeIndex]),'test ship failed to join live queue')
  tick(T.freightStallTime+2)
  assert(r.task and not r.task.freightRecovery.retried,'queue time counted as stalled flight')
  game:remove(blocker)
  local half=math.floor(T.freightStallTime/2)
  tick(half)
  local sx,sy=AI.stopPoint(e.route[e.routeIndex],e)
  local px,py=e.body:getPosition()
  local distance=math.sqrt((sx-px)^2+(sy-py)^2)
  local step=2*T.freightProgressDistance/distance
  e.body:setPosition(px+(sx-px)*step,py+(sy-py)*step)
  tick(half+2)
  assert(r.task and not r.task.freightRecovery.retried,'forward progress failed to reset the stall timer')
  tick(T.freightStallTime+2)
  assert(r.task and r.task.freightRecovery.retried and offer.owner==r.id,'stalled route did not retry')
  tick(2*T.freightStallTime+2)
  if phase=='pickup' then
   assert(offer.state=='available' and not offer.owner,'stalled pickup did not release reserved stock')
  else
   assert(r.task and offer.owner==r.id and offer.loaded and e.cargo[offer.item]==offer.amount,
    'stalled delivery released the order or changed the cargo')
  end
  game:remove(e,true)
  u.npcs[r.id]=nil
 end
 run('pickup')
 run('delivery')
 game.world:destroy()
 print('ok  freight recovery: queue waits, live retry, pickup release and loaded custody')
end
