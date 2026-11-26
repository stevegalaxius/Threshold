return function()
 local Access=require('src.npc_access')
 local Rep=require('src.reputation')
 local NPC=require('src.npc')
 local Tasks=require('src.tasks')
 local Game=require('src.game')
 local Ship=require('src.ship')
 local Security=require('src.security')
 local Queue=require('src.queue')
 local Upkeep=require('src.upkeep')
 local game=Game.new({preview=true})
 local u=game.universe
 local earth,mars,cordelia='station:earth_2','station:mars_5','station:cordelia_1'
 local station=assert(game:locationEntity(earth))
 local crew={id='npc/faction-test',affiliation=Rep.CARTEL,homeStation=cordelia,state='travel',
  route={earth,earth},index=2,arrive=1,speed=600,area='earth'}
 local ship=Ship.new(game,{hull='intaki_wisp'})
 ship.alifeRecord=crew
 crew.ship=Ship.record(ship)
 local inspector={alifeRecord={task={kind='patrol',jurisdiction='earth'}}}

 assert(Access.eligible({job='hauler'},{kind='transport',source='station:shoals_2',target=mars},nil,u),
  'civilian freight to open cartel ports was blocked')
 assert(not Access.canStop(crew,earth,u) and Access.canDock(crew,earth,u,'fence'),
  'routine dock access and a deliberate fence run have the same permission')
 assert(not Access.canDock(crew,'station:saturn_4',u),'hostile military yard admitted a cartel crew')
 assert(Access.canDock({piracy={}},earth,u),'unaffiliated pirates were classed as cartel')

 Rep.setStance(u,'estates',Rep.CARTEL,'neutral')
 assert(game:beginDocking(ship,station,1,station.dock),'neutral relationship blocked the tractor')
 assert(Rep.stance(Rep.CARTEL,'estates',{})=='hostile','relationship leaked into a different save')
 Rep.setStance(u,Rep.CARTEL,'estates',nil)
 game:updateDockedShip(ship,1/120)
 assert(not ship.dockState and not game:beginDocking(ship,station,1,station.dock),
  'hostile relationship admitted the crew to a live dock')
 assert(Security.hostile(game,inspector,ship),'patrol did not use the same relationship')
 crew.queue={kind='dock',key=earth,ready=5}
 u.queues={[earth]={{id=crew.id,start=5,finish=9}}}
 assert(Queue.due(crew,u)==crew.arrive and not crew.queue and #u.queues[earth]==0,
  'a closed port kept the ship in its offline queue')
 NPC.arrive(crew,earth,1,u,game)
 assert(crew.state=='idle','offline arrival docked at a closed port')

 local offer=Tasks.post(u,{kind='transport',source=mars,target=earth,item='steel_plate',amount=1})
 offer.state,offer.owner='reserved',crew.id
 crew.task={kind='transport',phase='pickup',id=offer.id,source=mars,target=earth}
 assert(not Tasks.arrive(u,crew,mars,1,game) and not crew.task and offer.state=='available',
  'a reserved pickup loaded goods for a newly closed destination')

 -- A closed destination can end a load after ordinary recovery runs
 -- out of options. The existing release settles its unused fee.
 local Accounts=require('src.accounts')
 local seller,node='station:shoals_2','station:shoals_1'
 local prepaid=Tasks.post(u,{kind='transport',source=seller,target=earth,item='steel_plate',
  amount=1,order=true,stocked=true})
 prepaid.state,prepaid.owner,prepaid.loaded='reserved',crew.id,true
 local balance,sellerBalance=Accounts.balance(u,earth),Accounts.balance(u,seller)
 assert(Accounts.reserve(u,earth,15))
 crew.ship.cargo={steel_plate=1}
 crew.node,crew.area=node,'shoals'
 crew.task={kind='transport',phase='delivery',id=prepaid.id,source=seller,target=earth,
  item=prepaid.item,amount=1,order=true,stocked=true,buyerFunded=true,prepaidGoods=100,prepaidFee=15}
 NPC.controller.next({u=u,r=crew,node=node,clock=2,wasDocked=true,game=game})
 assert(not crew.task and crew.lastTask.status=='delivery blocked' and not Tasks.state(u).offers[prepaid.id],
  'blocked freight job stayed active or relisted its loaded stock')
 assert(Accounts.balance(u,earth)==balance and Accounts.balance(u,seller)==sellerBalance
  and crew.ship.cargo.steel_plate==1,'blocked freight did not use existing settlement')

 local yard='station:mercury_3'
 local damaged={id='npc/repair-test',affiliation=Rep.CARTEL,state='idle',area='mercury',
  route={yard,yard},node=yard,index=1,speed=600,ship=require('src.persistence').copy(crew.ship)}
 damaged.ship.armor=1
 assert(not Upkeep.plan(damaged,1,nil,u),'crew planned to service at a closed port')
 Rep.setStance(u,'estates',Rep.CARTEL,'neutral')
 damaged.nextServiceAt=nil
 assert(Upkeep.plan(damaged,1,nil,u) and damaged.service.station==yard,
  'same port was unavailable after relations improved')

 local source='station:jupiter_1'
 local courier={id='npc/route-test',affiliation='jove',ship=crew.ship,workWeights={travel_test=1}}
 local function choose(clock)
  local board={clock=clock,reputation=u.reputation}
  local safe=Tasks.post(board,{kind='travel_test',source=source,target=mars})
  local risky=Tasks.post(board,{kind='travel_test',source=source,target=cordelia})
  courier.task=nil
  local chosen=assert(Tasks.choose(board,courier,source,clock))
  return chosen.id,safe.id,risky.id
 end
 Tasks.register('travel_test',{eligible=function() return true end,score=function(_,_,o) return o.target==cordelia and 100 or 1 end})
 local chosen,_,risky=choose(1)
 assert(chosen==risky,'route risk changed choices while the corridor was neutral')
 Rep.setStance(u,'bowman','jove','hostile')
 assert(Access.canDock(courier,cordelia,u) and Access.travelRisk(courier,source,cordelia,u)==1,
  'route through a hostile moon gateway lost its transit risk or became undockable')
 local preferred,safe=choose(2)
 assert(preferred==safe,'safer itinerary did not outrank a higher scoring job')
 Tasks.definitions.travel_test=nil
 game.world:destroy()
 print('ok  faction travel: open trade, hostile stops, live and offline access, queue release and route risk')
end
