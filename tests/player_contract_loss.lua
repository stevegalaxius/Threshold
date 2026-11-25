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
 assert(not Board.active(game) and not Tasks.state(u).offers[offer.id],'loaded wreck left a contract or pickup on the board')
 assert(Stock.count(u,source,item)==before and u.credits==credits,'wreck restored stock or paid the order')
 assert(Hold.count(game.playerHusk.hold,item)>=4,'freight was stripped from the wreck')
 assert(game.wreckContractNotice and Board.lossNotice(game),'player received no failure notice')
 local notice=Board.lossNotice(game)
 game:loadState(game:saveState())
 assert(game.state=='dead' and game.wreckContractNotice==notice,'lost contract notice did not survive save/load')
 game:respawn()
 assert(not Board.active(game) and Board.lossNotice(game)==notice,'failed contract returned after respawn')
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
 print('ok  player contract loss: loaded wreck, uncollected release and legacy loss report')
end
