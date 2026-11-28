return function()
 local Game,Tasks,Transport=require('src.game'),require('src.tasks'),require('src.transport')
 local Board,Stock,Copy=require('src.player_contracts'),require('src.stockpile'),require('src.persistence').copy
 local source,transfer,target='station:earth_3','station:earth_2','station:earth_1'
 local function post(u,item,n)
  return Tasks.post(u,Transport.quote({
   kind='transport',order=true,stocked=true,source=source,target=target,item=item,amount=n,
  },u.clock,u))
 end
 local game=Game.new({preview=true})
 game.autosaveOff=true
 local u=game.universe
 local function dock(station)
  assert(game:dockInstantly(game.player,assert(game:locationEntity(station))))
 end
 dock(source)
 Stock.add(u,source,'water',20)
 local personalWater=game.player.cargo.water or 0
 local original=post(u,'water',10)
 local totalFee=Transport.payment(original)
 assert(Board.accept(game,original.id))
 local held=assert(Board.active(game)).amount
 assert(held==10,'test freight did not fit')
 local credits=u.credits
 local shelf=Stock.count(u,transfer,'water')
 dock(transfer)
 assert(Board.chooseRecovery(game,'transfer'))
 assert(not Board.active(game) and (game.player.cargo.water or 0)==personalWater,'transfer did not unload or end original contract')
 assert(not Tasks.state(u).offers[original.id] and Stock.count(u,transfer,'water')==shelf,'transfer duplicated goods into market')
 local relay
 for _,o in pairs(Tasks.state(u).offers) do if o.relay then relay=o;break end end
 assert(relay and relay.source==transfer and relay.target==target and relay.amount==held,'transfer offer lost its original destination or quantity')
 assert(Transport.payment(relay)+u.credits-credits<=totalFee,'handoff increased the freight budget')
 assert(Transport.available(Copy(u),transfer,relay.item,relay.id)==held,'sealed freight disappeared after copying save records')
 assert(Board.accept(game,relay.id))
 assert(relay.loaded and Transport.available(u,transfer,relay.item,relay.id)==0)
 dock(target)
 assert(Board.advance(game) and not Board.active(game) and (game.player.cargo.water or 0)==personalWater,'replacement carrier could not settle freight')
 assert(u.credits-credits<=totalFee and not Tasks.state(u).offers[relay.id],'replacement delivery overpaid or remained open')

 -- Selecting a return elsewhere must keep the load aboard until docking.
 dock(source)
 local returning=post(u,'water',4)
 assert(Board.accept(game,returning.id))
 local originStock=Stock.count(u,source,'water')
 dock(transfer)
 assert(Board.chooseRecovery(game,'return') and Board.active(game).recoveryStop==source)
 assert((game.player.cargo.water or 0)==personalWater+4 and Stock.count(u,source,'water')==originStock,
  'choosing a return moved cargo before arrival')
 dock(source)
 game:playerDocked(game.player.dockState.station)
 assert(not Board.active(game) and Stock.count(u,source,'water')==originStock+4,
  'docking at origin did not automatically settle the return')

 -- Two lines share a hold. A partially filled companion must leave the
 -- uncollected balance on the board as soon as the pilot takes the job.
 local carrier={id='npc/test-partial',ship={hull='intaki_wisp',cargo={}}}
 local root=post(u,'water',16)
 local companion=post(u,'steel_plate',200)
 Stock.add(u,source,'steel_plate',200)
 local task=Copy(root)
 assert(Tasks.definitions.transport.prepare(u,carrier,task,target,u.clock))
 assert(companion.amount>0 and companion.amount<200 and companion.owner==carrier.id)
 local remaining=0
 for _,o in pairs(Tasks.state(u).offers) do
  if o.item=='steel_plate' and o.state=='available' and o.source==source and o.target==target then remaining=remaining+o.amount end
 end
 assert(companion.amount+remaining==200,'partial manifest lost some of the original order')
 local large=post(u,'food_crate',160)
 Stock.add(u,source,large.item,160)
 local smallPilot={id='npc/test-primary-partial',ship={hull='intaki_wisp',cargo={}}}
 assert(Tasks.definitions.transport.prepare(u,smallPilot,Copy(large),target,u.clock))
 local leftover=0
 for _,o in pairs(Tasks.state(u).offers) do
  if o.item==large.item and o.source==source and o.target==target and o.state=='available' then leftover=leftover+o.amount end
 end
 assert(large.amount>0 and leftover>0 and large.amount+leftover==160,'partial pickup lost the primary order remainder')
 -- An intermediate fence cannot legalize an embargoed buyer (a cartel
 -- station's goods to a power hostile to it). A fence remains a valid
 -- transfer point for a shipment a buyer may accept.
 local cartel='station:shoals_2'
 local goods={kind='transport',phase='delivery',order=true,stocked=true,layoutScope='economy',
  source=cartel,target=target,item='steel_plate',amount=5}
 assert(Transport.embargoed(goods) and not Transport.recoveryMode(u,goods,transfer,u.clock),
  'transferring through a fence bypassed the original embargo')
 assert(Transport.recoveryMode(u,goods,cartel,u.clock)=='return','embargo prevented return to the seller')
 -- the drugs are illegal but every station buys them: no embargo
 goods.item='amphetamines'
 assert(not Transport.embargoed(goods),'a station refused drugs (they trade everywhere)')
 goods.target='station:mars_5'
 assert(not Transport.embargoed(goods) and Transport.recoveryMode(u,goods,transfer,u.clock)=='transfer',
  'authorized shipment could not pass through a fence')
 game.world:destroy()
 print('ok  loaded freight: sealed transfer, single fee budget and immediate partial remainder')
end
