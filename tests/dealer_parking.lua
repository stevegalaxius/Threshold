-- Guest reserves and real occupancy constrain both scheduled ship outputs
-- and dealer replenishment, including stations without live physics bodies.
return function(game)
 local P,D,I,S,C=require('src.dealer_parking'),require('src.dealers'),require('src.industry'),require('src.stockpile'),require('src.commodities')
 local data,L,Game=require('src.data'),require('src.locations'),require('src.game')
 local key='station:mars_1';local place=L.get(key);local original=data.stations[place.layout]
 local market=S.definition(key);local oldDealer=market.dealer
 local oldRecipes=require('data.industry').facilities.intaki_assembly.recipes
 local w,h=Game.hangarFootprint('intaki_wisp',false)
 local def={hangar={w=w*2,h=h*2},docks={{hw=1000}},parts={},berths={}}
 for i=1,4 do def.berths[i]={x=i*2000,y=0,heading=0,maxLength=1000,maxWidth=1000} end
 data.stations[place.layout]=def
 market.dealer={hulls={'intaki_wisp'},lots=20,assembly='intaki_assembly'}
 local recipe={id='test_parked_ship',stockless=true,storefront=false,market=false,inputs={{item='hull_frame',n=1}},outputs={{kind='ship',hull='intaki_wisp',n=1}},make={[key]=2},use={}}
 C.list[#C.list+1]=recipe;C.byId[recipe.id]=recipe
 require('data.industry').facilities.intaki_assembly.recipes={recipe.id}
 local u={clock=0,stations={},npcs={},dealers={[key]={lots={},serial=0}}}
 local remote=P.plan(u,key,'intaki_wisp',20)
 assert(#remote==4,'unexpected commercial bay/berth capacity')
 local world=love.physics.newWorld();local body=love.physics.newBody(world)
 local station={key=key,def=def,docks=def.docks,dock=def.docks[1],body=body}
 local live=setmetatable({universe=u,fieldId=place.area,entities={},alifeOnline={}},{__index=Game})
 P.bind(u,live,station)
 local loaded=P.plan(u,key,'intaki_wisp',20)
 assert(require('src.save').encode(remote)==require('src.save').encode(loaded),'remote and loaded allocations disagree')
 D.output(u,key,'intaki_wisp',4)
 local rows,reserved=P.reserve(station)
 local inside,outside=0,0
 for _,lot in ipairs(D.lots(u,key)) do
  if lot.bay then
   local _,height=Game.hangarFootprint(lot.hull,lot.bay.rot)
   assert(lot.bay.y+height<=def.hangar.h-rows,'dealer occupied guest hangar strip');inside=inside+1
  else assert(not reserved[lot.mooring],'dealer occupied a guest berth');outside=outside+1 end
 end
 assert(inside==2 and outside==2 and D.room(u,key,'intaki_wisp')==0,'physical parking did not limit output')
 local visitor={hull='intaki_wisp'}
 assert(live:hangarFit(station,visitor.hull,visitor) and live:mooringFit(station,visitor.hull,visitor),'dealer stock blocked all guest space')
 assert(D.frameTarget(u,key)==0,'physically full station still requested construction frames')
 I.update(u,0,{key});S.stock(u,key,S.shopFor(key,D.FRAME))[D.FRAME]=10
 u.clock=3600;I.update(u,u.clock,{key})
 assert(#D.lots(u,key)==4 and S.count(u,key,D.FRAME)==10,'blocked output consumed frames or created hidden stock')
 local sold=D.lots(u,key)[1];D.take(u,key,sold.id)
 u.clock=3601;I.update(u,u.clock,{key})
 assert(#D.lots(u,key)==3,'blocked time banked an instant replacement')
 u.clock=5401;I.update(u,u.clock,{key})
 assert(#D.lots(u,key)==4 and S.count(u,key,D.FRAME)==9,'freed parking did not allow manufacturing to resume')
 local saved=assert(require('src.save').decode(require('src.save').encode(u)))
 assert(D.room(saved,key,'intaki_wisp')==0,'save/load lost commercial occupancy')
 -- A buyer can use the guest berth released by a trade-in even though
 -- the incoming lot is marked as dealer stock. Fill every other space.
 local stock=u.dealers[key];stock.lots={}
 local owned=S.record(u,key).hangar;for i=#owned,1,-1 do owned[i]=nil end
 while true do
  local rec={hull='intaki_wisp'};local bay=live:hangarFit(station,rec.hull,rec)
  if not bay then break end
  rec.bay=bay;owned[#owned+1]=rec
 end
 local tradeIn
 for i=1,4 do
  local rec={hull='intaki_wisp',mooring=i}
  owned[#owned+1]=rec;if i==1 then tradeIn=rec end
 end
 local lot=D.roll(market.dealer,stock,'intaki_wisp');stock.lots={lot}
 u.credits=1000000;live.world=world;live.idCounter=0
 assert(not live:shipParkingFit(station,lot.hull,lot),'fixture unexpectedly has commercial parking')
 assert(live:shipBuyProblem(station,lot,nil),'purchase should require the trade-in space')
 assert(not live:shipBuyProblem(station,lot,tradeIn),'preview rejected the freed guest berth')
 local bought,why=live:buyShip(station,lot,{tradeIn=tradeIn})
 assert(bought,why)
 assert(bought.mooring==1 and not bought.dealerStock,'purchase failed to transfer into the guest berth')
 assert(not D.find(u,key,lot.id),'purchase retained the sale lot')
 body:destroy();world:destroy()
 require('data.industry').facilities.intaki_assembly.recipes=oldRecipes
 table.remove(C.list);C.byId[recipe.id]=nil
 market.dealer=oldDealer;data.stations[place.layout]=original
 -- Heaven-Ladder shares trade identity, but each anchor owns its parking.
 game:loadField('mars');game:captureALife(true)
 local ladder=require('src.fields').mars.ladderIds;local anchors,ships={},{}
 D.state(game.universe,ladder[1]).lots={}
 for i=1,4 do
  anchors[i]=assert(game:findStation(ladder[1],i))
  ships[i]=assert(game:addToHangar(anchors[i],'intaki_wisp'))
  assert(game:hangar(anchors[i])[1]==ships[i] and #game:hangar(anchors[i])==1,'anchor duplicated another hangar roster')
  assert(game:stationStorage(anchors[i])==game:stationStorage(anchors[1]),'anchor split the shared economy storage')
 end
 local a,b=anchors[1],anchors[2]
 ships[1].loadout[1]=false
 ships[1].bay=nil;ships[1].mooring=1
 assert(game:mooringTaken(a,1) and not game:mooringTaken(b,1),'berth occupancy leaked between anchors')
 ships[2].bay=nil;ships[2].mooring=1
 assert(game:mooringTaken(a,1) and game:mooringTaken(b,1),'anchors cannot independently use the same berth number')
 local Room=require('src.dock_room');local crowded={npcs={}}
 local capacity=Room.capacity(ladder[1],'intaki_wisp')
 assert(capacity<math.huge,'missing anchor docking capacity')
 for i=1,capacity do crowded.npcs[i]={state='docked',node=ladder[1],ship={hull='intaki_wisp'}} end
 local visitor={ship={hull='intaki_wisp'}}
 assert(not Room.room(crowded,visitor,ladder[1]) and Room.room(crowded,visitor,ladder[2]),'offline anchor occupancy was combined')
 local Queue,NPC=require('src.queue'),require('src.npc');local docksAt=NPC.docksAt
 NPC.docksAt=function()return true end
 local first,_,firstCapacity=Queue.chokepoint({route={ladder[1]}},1)
 local second,_,secondCapacity=Queue.chokepoint({route={ladder[2]}},1)
 NPC.docksAt=docksAt
 assert(first==ladder[1] and second==ladder[2] and first~=second,'anchor queues share a booking key')
 assert(firstCapacity==#a.docks and secondCapacity==#b.docks,'anchor queue combined every entrance')
 assert(game:dockInstantly(game.player,anchors[3]),'player could not dock at third anchor')
 assert(game.player.bayStation==ladder[3],'player parking identity lost its anchor')
 local Save=require('src.save');local state=assert(Save.decode(Save.encode(game:saveState())))
 game:loadState(state)
 assert(game.player.dockState.station.accessIndex==3,'save/load docked player at wrong anchor')
 a,b=game:findStation(ladder[1],1),game:findStation(ladder[1],2)
 local firstShips,secondShips=game:hangar(a),game:hangar(b)
 assert(#firstShips==1 and #secondShips==1 and firstShips[1]~=secondShips[1],'save/load merged anchor rosters')
 assert(firstShips[1].loadout[1]==false and secondShips[1].loadout[1]~=false,'save/load moved ships between anchors')
 assert(firstShips[1].mooring==1 and secondShips[1].mooring==1,'save/load lost independent berths')
 print('DEALER PARKING: shared remote/live geometry, guest reserves, full-space blocking, resumption, independent anchor hangars/queues and saving passed')
end
