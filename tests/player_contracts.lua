-- One bounded player journey through the real shared freight board and UI.
return function()
 local game=require('src.game').new({field='mars'});game.autosaveOff=true
 local Board,Tasks=require('src.player_contracts'),require('src.tasks')
 local Stock,Hold,Ship=require('src.stockpile'),require('src.inventory.hold'),require('src.ship')
 local Save,Transport=require('src.save'),require('src.transport')
 local source,target='station:mars_1','station:mars_2'
 local function dock(id)
  local st=assert(game:findStation(id));game.state='docked'
  game.player.dockState={station=st,done=true,phase='done',dock=st.dock,side=1}
 end
 local function resetHold()
  local p=game.player;p.cargo={};p.hold=Hold.new(Ship.holdLayout(p));Ship.updateMass(p)
 end
 local function set(n) Stock.stock(game.universe,source,Stock.shopFor(source,'nitrates')).nitrates=n end
 local function post(n)
  return Tasks.post(game.universe,{kind='transport',source=source,target=target,item='nitrates',amount=n,
   order=true,stocked=true,routeAU=0,placed=game.universe.clock,npcClaimAt=game.universe.clock+30})
 end
 resetHold();dock(target);set(1000)
 local u=game.universe;local n=Ship.canFit(game.player,'nitrates',1000);assert(n>0)
 local o=post(n+3);local initial=Stock.count(u,source,'nitrates')
 local q=assert(Board.quote(game,o));local payment=q.payment
 assert(q.amount==n and payment==math.floor(n*2.5+200*n/(n+3)+1e-7),'partial player quote lost volume or handling share')
 local found=false;for _,job in ipairs(Board.list(game)) do if job.id==o.id then found=true end end
 assert(found,'public listing window hid work from the player')
 assert(Board.accept(game,o.id),'remote acceptance failed')
 assert(Board.active(game).phase=='pickup' and not game.player.cargo.nitrates,'remote acceptance loaded cargo')
 local remainder
 for _,offer in pairs(Tasks.state(u).offers) do if offer.id~=o.id and offer.item=='nitrates' and offer.source==source and offer.amount==3 then remainder=offer end end
 assert(remainder and remainder.state=='available','partial acceptance lost the rest of the order')
 Tasks.clean(u,u.clock+60)
 assert(o.owner=='player' and o.state=='reserved','NPC cleanup released the player reservation')
 assert(Transport.reserved(u,source,'nitrates')>=n,'player cargo not protected from consumers')
 local rival={id='contract-rival',ship={hull=game.player.hull.id,cargo={}},workWeights={transport=1,mine=0,salvage=0,patrol=0,raid=0}}
 local selected=Tasks.choose(u,rival,source,u.clock)
 assert(not selected or selected.id~=o.id,'NPC claimed an accepted player contract')
 require('src.economy').update(u,u.clock)
 assert(o.owner=='player' and o.state=='reserved','economy trimmed accepted player freight')
 assert(not Board.accept(game,remainder.id),'player accepted two simultaneous contracts')
 assert(not Board.advance(game),'wrong station loaded cargo')
 dock(source);assert(Board.advance(game));assert(Board.active(game).phase=='delivery')
 assert(game.player.cargo.nitrates==n and Stock.count(u,source,'nitrates')==initial-n,'pickup duplicated or lost cargo')
 -- Real save/load must retain ownership, cargo, quote and delivery phase.
 local snapshot=assert(Save.decode(Save.encode(game:saveState())))
 assert(snapshot.tasks.player.ship==nil,'saved duplicate player cargo ledger')
 game:loadState(snapshot);u=game.universe;dock(source)
 Tasks.clean(u,u.clock+60)
 assert(Board.active(game).phase=='delivery' and Tasks.state(u).offers[o.id].owner=='player','reload lost contract')
 assert(game.player.cargo.nitrates==n,'reload lost freight cargo')
 -- Cargo can be moved/sold/lost; settlement requires replacing it.
 Hold.take(game.player.hold,'nitrates',1);game.player.cargo=Hold.totals(game.player.hold);Ship.updateMass(game.player)
 dock(target);local credits=game:credits();local stock=Stock.count(u,target,'nitrates')
 assert(not Board.advance(game) and game:credits()==credits and Board.active(game),'missing cargo paid or discarded contract')
 Ship.addCargo(game.player,'nitrates',1)
 assert(not Board.cancel(game),'loaded cargo cancelled away from source')
 -- Exercise the station's actual tab and button dispatch, including rendering.
 local Cargo,View=require('src.ui.cargo'),require('src.ui.contracts')
 assert(Cargo.setTab(game,'contracts'),'station did not offer Contracts')
 local canvas=love.graphics.newCanvas(love.graphics.getDimensions());love.graphics.setCanvas(canvas);love.graphics.clear();Cargo.draw(game);love.graphics.setCanvas()
 if os.getenv('CONTRACT_SCREENSHOT') then
  local f=assert(io.open(os.getenv('CONTRACT_SCREENSHOT'),'wb'));f:write(canvas:newImageData():encode('png'):getString());f:close()
 end
 local r=View.layout(game).advance
 Cargo.mousepressed(game,r.x+5,r.y+5,1)
 assert(not Board.active(game) and game:credits()==credits+payment,'delivery button did not settle exact quote')
 assert(Stock.count(u,target,'nitrates')==stock+n and not game.player.cargo.nitrates,'delivery did not transfer actual cargo')
 assert(not Board.advance(game) and game:credits()==credits+payment,'delivery paid twice')
 assert(not Tasks.state(u).offers[o.id],'completed order remained claimable')
 -- Before-pickup cancellation releases the same offer; after pickup returns stock.
 resetHold();dock(target);set(1000);o=post(2)
 assert(Board.accept(game,o.id));assert(Board.cancel(game))
 assert(o.state=='available' and not o.owner,'unloaded cancellation did not release reservation')
 o.readyAt=0;dock(source);local before=Stock.count(u,source,'nitrates')
 assert(Board.accept(game,o.id));assert(Board.cancel(game))
 assert(Stock.count(u,source,'nitrates')==before and not game.player.cargo.nitrates,'returned cancellation lost or duplicated cargo')
 o.readyAt=0;o.owner='other';o.state='reserved'
 assert(not Board.accept(game,o.id),'stale UI stole an NPC reservation')
 local private=post(2);private.requires={authorization='police'};private.issuer='zhuhai';private.jurisdiction='mars'
 assert(not Board.accept(game,private.id),'player bypassed job authorization')
 game.state='playing';game.player.dockState=nil
 assert(not Board.accept(game,remainder.id),'player accepted work in flight')
 Cargo.open=true;Cargo.spaceTab='contracts';Cargo.draw(game);Cargo.open=false
 print('PLAYER CONTRACTS: global orders, partial loads, ownership, real pickup/delivery, exact payment, save/reload, returns and station UI passed')
end
