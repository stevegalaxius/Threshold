return function()
 local Game,Board,Tasks=require('src.game'),require('src.player_contracts'),require('src.tasks')
 local Ship,Stock,Hold=require('src.ship'),require('src.stockpile'),require('src.inventory.hold')
 local source,target='station:earth_3','station:earth_1'
 local item='water'
 local function setup(station)
  local game=Game.new({preview=true})
  game.autosaveOff=true
  local st=assert(game:locationEntity(station))
  assert(game:dockInstantly(game.player,st))
  game.state='docked'
  local u=game.universe
  Stock.add(u,source,item,4)
  local offer=Tasks.post(u,{kind='transport',source=source,target=target,item=item,amount=4,stocked=true,order=true})
  assert(Board.accept(game,offer.id))
  return game,offer
 end
 local function wreck(game)
  game.player.dead=true
  game:reap()
  assert(game.state=='dead' and game.playerHusk,'test must use the normal wreck path')
 end

 local game,offer=setup(source)
 local u=game.universe
 assert(Board.active(game).phase=='delivery' and offer.loaded)
 local before,credits=Stock.count(u,source,item),u.credits
 wreck(game)
 assert(Board.active(game) and offer.owner=='player' and offer.loaded,'wreck closed or relisted recoverable freight')
 assert(Stock.count(u,source,item)==before and u.credits==credits,'wreck restored stock or paid the order')
 assert(Hold.count(game.playerHusk.hold,item)>=4,'freight was stripped from the wreck')
 assert(game.wreckContractNotice and not Board.lossNotice(game),'wreck failed the contract or gave no recovery notice')
 local notice=game.wreckContractNotice
 local save=game:saveState()
 local wreckId=assert(game.playerHusk.persistenceId)
 game:loadState(save)
 assert(game.state=='dead' and game.wreckContractNotice==notice,'recovery notice did not survive save/load')
 game:respawn()
 assert(Board.active(game).id==offer.id and Board.cargoMissing(game),'contract did not survive respawn')
 local husk
 for _,entity in ipairs(game.entities) do
  if entity.kind=='husk' and entity.persistenceId==wreckId and Hold.count(entity.hold,item)>=4 then
   husk=entity
   break
  end
 end
 assert(husk,'wreck cargo did not survive save/load')
 assert(Hold.add(game.player.hold,item,4)==4 and Hold.take(husk.hold,item,4)==4)
 game.player.cargo=Hold.totals(game.player.hold)
 Ship.updateMass(game.player)
 assert(game:dockInstantly(game.player,assert(game:locationEntity(target))))
 game.state='docked'
 u=game.universe
 credits=u.credits
 assert(Board.advance(game) and u.credits>credits,'salvaged freight could not be delivered for payment')
 assert(not Board.active(game) and not Tasks.state(u).offers[offer.id],'delivery left a stranded contract')
 game.world:destroy()

 game,offer=setup(target)
 u=game.universe
 assert(Board.active(game).phase=='pickup')
 before=Stock.count(u,source,item)
 wreck(game)
 assert(not Board.active(game) and offer.state=='available' and not offer.owner and not offer.loaded,
  'uncollected order was lost rather than released')
 assert(Stock.count(u,source,item)==before,'release changed physical source stock')
 game.world:destroy()

 game,offer=setup(source)
 u=game.universe
 assert(Hold.take(game.player.hold,item,4)==4)
 game.player.cargo=Hold.totals(game.player.hold)
 Ship.updateMass(game.player)
 assert(Board.cargoMissing(game) and Board.reportLoss(game),'missing cargo could not be reported')
 assert(not Board.active(game) and not Tasks.state(u).offers[offer.id] and not Board.reportLoss(game),
  'reported loss left a live shipment or could be settled twice')
 game.world:destroy()
 print('ok  player contract loss: wreck salvage and delivery, uncollected release and loss reporting')
end
