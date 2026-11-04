-- End-to-end first prototype: use the existing inventory controls and ship records.
return function(game)
 local Cargo,Hangar=require('src.ui.cargo'),require('src.ui.hangar')
 local Hold,Grid=require('src.inventory.hold'),require('src.inventory.grid')
 local Ship,Save,data=require('src.ship'),require('src.save'),require('src.data')
 local checks=0
 local function check(ok,msg)assert(ok,msg);checks=checks+1 end
 local function screenshot(name)
  local canvas=love.graphics.newCanvas(love.graphics.getDimensions())
  love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear(.02,.035,.06)
  Cargo.draw(game);love.graphics.setCanvas();love.graphics.pop()
  canvas:newImageData():encode('png','station-prototype-'..name..'.png');canvas:release()
 end
 game.autosaveOff=true;game:loadField('earth');game:captureALife(true)
 local st=game:locationEntity('station:007')
 game.universe.populationSpawns={}
 game:dockInstantly(game.player,st,{interior=true})
 local r=game:stationRecord(st)
 check(#Cargo.tabs==5,'station services missing')
 local labels={};for _,tab in ipairs(Cargo.tabs) do labels[tab.label]=true end
 check(labels.Storage and labels.Market and labels.Shipyard and labels.Hangar and labels.Repair and not labels.Outfitting,'service tabs do not describe existing station mechanics')
 local w,h=game.hangarSize(st)
 check(w==12 and h==10,'default interior is not a small finite grid')
 check(game:hangarFit(st,'halcyon_wisp')~=nil,'small ship does not fit inside')
 check(not game:hangarFit(st,'ferrous_freighter'),'hauler still fits the default small interior')
 local marker=st.def.berths and st.def.berths[1] and st.def.berths[1].size
 local slots=game:stationMoorings(st)
 check(#slots==#st.def.berths,'station added unplaced overflow moorings')
 check(game:mooringFit(st,'ferrous_freighter')~=nil,'real station berths reject the hauler')
 if marker then check(st.def.berths[1].size==marker,'exterior allocation resized an editor marker') end
 if st.def.berths and st.def.berths[1] then
  local berth=st.def.berths[1];local bx,by=berth.x,berth.y
  local shape=st.body:getFixtures()[1]:getShape()
  if shape:getType()=='polygon' then
   local points={shape:getPoints()};local x,y=0,0
   for i=1,#points,2 do x=x+points[i];y=y+points[i+1] end
   berth.x,berth.y=x/(#points/2),y/(#points/2)
   check(not game:mooringFits(st,1,'ferrous_freighter'),'berth admitted a ship intersecting station geometry')
   berth.x,berth.y=bx,by
  end
 end

 game.universe.credits=1000000
 local big=assert(game:buyShip(st,'ferrous_freighter'))
 check(big.mooring and not big.bay,'large purchased ship did not reserve exterior storage')
 local index;for i,rec in ipairs(game:hangar(st)) do if rec==big then index=i end end
 local exterior=big.mooring
 check(game:flyFromHangar(index),'could not select an exterior ship')
 check(game.player.parkingMooring==exterior and not game.player.bay,'ship switching consumed an interior bay for a large ship')
 -- Exercise the physical tractor handoff with a real hauler at the real station.
 local hauler,d=game.player,st.dock
 hauler.dockState=nil;hauler.parkingMooring=nil;hauler.bayStation=nil;hauler.body:setActive(true)
 local ax,ay=game.dockWorld(st,1,d.x2+hauler.halfLength+40,0,d)
 hauler.body:setPosition(ax,ay);hauler.body:setLinearVelocity(0,0)
 game:beginDocking(hauler,st,1,d);game:updateDockedShip(hauler,1/120)
 check(hauler.dockState and hauler.dockState.berth and not hauler.dockState.mooring,'hauler used overflow instead of a placed berth')
 exterior=hauler.dockState.berth;game:updateDockedShip(hauler,10)
 local pad=st.def.berths[exterior];local px,py=st.body:getLocalPoint(hauler.body:getPosition())
 check(math.abs(px-pad.x)<.01 and math.abs(py-pad.y)<.01,'hauler did not arrive at its real berth')
 local small=game:hangar(st)[index]
 check(small.hull=='halcyon_wisp' and small.bay,'previous small ship was not retained in its interior grid position')
 check(not game:mooringFit(st,'ferrous_freighter',nil) or game:mooringFit(st,'ferrous_freighter',nil)~=exterior,'active exterior ship did not reserve its slot')
 -- Capacity is per station; a larger authored interior can accept larger hulls.
 st.def.hangar={w=40,h=24}
 check(game:hangarFit(st,'ferrous_freighter')~=nil,'hangar has a hard-coded hull-class limit')
 st.def.hangar=nil
 -- Cargo stays a real small-cell inventory; equipment stays beside storage.
 Cargo.setTab(game,'cargo');local storageLayout=Cargo.layout(game)
 check(not storageLayout.equip.hidden,'storage lost the existing equipment panel')
 local function checkWorkspace(panels)
  for i,panel in ipairs(panels) do
   check(panel.y==112 and panel.ph==panels[1].ph,'station panel tops and bottoms differ')
   if i>1 then check(panel.x>panels[i-1].x+panels[i-1].pw,'station panels overlap') end
  end
 end
 checkWorkspace({storageLayout.equip,storageLayout.sides[1],storageLayout.sides[2]})
 -- Extra window space must not stretch cells or panels beyond their contents.
 local sw,sh=love.graphics.getDimensions()
 love.window.setMode(1600,1100);local large=Cargo.layout(game)
 love.window.setMode(1900,1300);local larger=Cargo.layout(game)
 check(large.cs==larger.cs and large.cs==30,'inventory cells scale up with the window')
 for i,side in ipairs(large.sides) do
  check(side.pw==larger.sides[i].pw and side.ph==larger.sides[i].ph,'inventory panel size follows window size')
 end
 love.window.setMode(sw,sh)
 local tabs=Cargo.tabRects(game)
 check(#tabs==5 and tabs[1].x>=0 and tabs[5].x+tabs[5].w<=sw,'service tabs moved outside the resized window')
 screenshot('storage')
 Cargo.setTab(game,'hangar');local shipLayout=Hangar.layout(game)
 local listed=false
 for _,s in ipairs(shipLayout.ships) do if s.owner==game.player and s.exterior then listed=true end end
 check(listed and #shipLayout.berths==#slots,'hangar does not show active and stored exterior ships')
 screenshot('hangar')
 -- Use the same drag gesture for interior and exterior owned ships.
 local shipCell
 for _,entry in ipairs(shipLayout.ships) do if entry.owner==small then shipCell=entry;break end end
 check(shipCell~=nil,'stored small ship is absent from hangar grid')
 local destination=game:mooringFit(st,small.hull,small)
 check(destination and shipLayout.berths[destination].visible,'no visible free berth for drag test')
 local row=shipLayout.berths[destination]
 Hangar.lastClick=nil
 Hangar.mousepressed(game,shipCell.x+shipLayout.cs*.5,shipCell.y+shipLayout.cs*.5,1)
 Hangar.mousereleased(game,row.x+16,row.y+16)
 check(small.mooring==destination and not small.bay,'hangar drag failed to reserve selected berth')
 local outside=Hangar.layout(game);local stored
 for _,entry in ipairs(outside.ships) do if entry.owner==small then stored=entry end end
 Hangar.lastClick=nil;Hangar.mousepressed(game,stored.x+16,stored.y+16,1)
 local occupied=outside.berths[game.player.parkingMooring]
 Hangar.mousereleased(game,occupied.x+16,occupied.y+16)
 check(small.mooring==destination,'drop on occupied berth changed ship parking')
 Hangar.lastClick=nil;Hangar.mousepressed(game,stored.x+16,stored.y+16,1)
 Hangar.mousereleased(game,outside.gx+outside.cs*.5,outside.gy+outside.cs*.5)
 check(small.bay and small.bay.x==0 and not small.mooring,'berth drag back to hangar retained exterior allocation')
 local active=game.player;local originalBerth=active.parkingMooring
 local function dragActiveTo(index)
  local view=Hangar.layout(game);local ship
  for _,entry in ipairs(view.ships) do if entry.owner==active then ship=entry end end
  check(ship~=nil,'active ship is not visible for berth drag')
  local row=view.berths[index];Hangar.lastClick=nil
  Hangar.mousepressed(game,ship.x+16,ship.y+16,1)
  Hangar.mousereleased(game,row.x+16,row.y+16)
  check(active.parkingMooring==index and active.dockState.berth==index,'active ship drag did not update physical berth')
 end
 dragActiveTo(destination);dragActiveTo(originalBerth)


 Cargo.setTab(game,'market');local layout=Cargo.layout(game)
 check(#layout.sides==3 and layout.equip.hidden,'market is not a three-panel inventory workspace')
 for _,filter in ipairs(layout.sides[3].filters) do check(filter.id~='ships','Market still contains a Shipyard filter') end
 checkWorkspace(layout.sides)
 for _,g in ipairs(layout.grids) do
  check(g.x>=g.side.x and g.x+g.g.w*layout.cs<=g.side.x+g.side.pw and g.y+g.g.h*layout.cs<=g.side.y+g.side.ph,'inventory grid overflows its station panel')
 end
 local offer=layout.sides[2]
 check(offer.complete.x>=offer.x and offer.complete.x+offer.complete.w<=offer.x+offer.pw and offer.clear.y+offer.clear.h<=offer.y+offer.ph,'trade controls leave center panel')
 local trade=layout.sides[2].hold
 -- Orbital One has two shops, each with its own shelf.
 local shopButtons=layout.sides[3].shops;local menu=layout.sides[3].shopMenu
 check(#shopButtons==2 and game:currentShop(st)==1,'market did not list the station shops')
 local firstShelf=game:stationMarket(st).hold
 Cargo.mousepressed(game,menu.x+4,menu.y+4,1)
 check(Cargo.shopOpen,'shop dropdown did not open')
 screenshot('shop-menu')
 Cargo.mousepressed(game,shopButtons[2].x+4,shopButtons[2].y+4,1)
 check(not Cargo.shopOpen,'shop dropdown stayed open')
 check(game:currentShop(st)==2 and game:stationMarket(st).hold~=firstShelf,'switching shops kept the same shelf')
 local beam=false;for _,g in ipairs(game:stationMarket(st).hold.grids) do for _,s in ipairs(g.stacks) do if s.id=='glint_laser' then beam=true end end end
 check(beam,'second shop is not stocked from its own list')
 screenshot('shops')
 Cargo.mousepressed(game,menu.x+4,menu.y+4,1);Cargo.mousepressed(game,shopButtons[1].x+4,shopButtons[1].y+4,1)
 layout=Cargo.layout(game)

 check(#trade.grids==2 and trade.grids[1].tradeOwner=='player' and trade.grids[2].tradeOwner=='station','give and receive inventories are not separated')
 -- Exercise actual right-click transfers through the existing inventory UI.
 local ship=game.player
 ship.hold=Hold.new({{key='hull',name='Cargo',w=12,h=10}})
 Hold.add(ship.hold,'scrap',8);ship.cargo=Hold.totals(ship.hold);Ship.updateMass(ship)
 layout=Cargo.layout(game)
 local playerGrid=layout.grids[1];local stack=playerGrid.g.stacks[1];local offered=stack.n
 local x=playerGrid.x+(stack.x+.5)*layout.cs;local y=playerGrid.y+(stack.y+.5)*layout.cs
 Cargo.mousepressed(game,x,y,2)
 check(Hold.count(trade,'scrap')==offered and Hold.count(ship.hold,'scrap')==8-offered,'right-click offer bypassed or broke spatial transfer')
 local shelf=game:stationMarket(st).hold
 local grid=shelf.grids[1];local stock=grid.stacks[1];assert(stock)
 local id,n=stock.id,stock.n;local prior=Hold.count(shelf,id)
 for _,g in ipairs(layout.grids) do
  if g.side.market then
   Cargo.mousepressed(game,g.x+(stock.x+.5)*layout.cs,g.y+(stock.y+.5)*layout.cs,2);break
  end
 end
 check(Hold.count({grids={trade.grids[2]}},id)==n,'station item was not placed in the receive grid')
 check(Hold.count({grids={trade.grids[1]}},id)==(id=='scrap' and offered or 0),'station stock entered the player-offer grid')
 love.mouse.setPosition(x,y)
 screenshot('market')
 love.mouse.setPosition(0,0)
 Cargo.setTab(game,'cargo')
 check(Hold.count(trade,'scrap')==0 and Hold.count(shelf,id)==prior,'leaving the market did not cancel and return goods')
 check(Hold.count(ship.hold,'scrap')==8,'cancelled sale lost player inventory')
 -- Settlement stays atomic across both offer grids, including insufficient funds.
 Cargo.setTab(game,'market');layout=Cargo.layout(game);trade=layout.sides[2].hold
 check(Hold.placeStack({grids={trade.grids[2]}},{id='salvage_kit',n=1,owner='station'}),'could not stage purchase')
 local credits=game:credits();game.universe.credits=0
 local failed=game:completeTrade(st,trade)
 check(not failed and Hold.count(trade,'salvage_kit')==1,'failed trade consumed the pending offer')
 game.universe.credits=credits
 local before=Hold.count(ship.hold,'salvage_kit')+Hold.count(game:stationStorage(st),'salvage_kit')
 local ok=game:completeTrade(st,trade)
 check(ok and Hold.count(trade,'salvage_kit')==0,'purchase did not settle the receive grid')
 check(Hold.count(ship.hold,'salvage_kit')+Hold.count(game:stationStorage(st),'salvage_kit')==before+1,'purchase did not reach inventory')
 Cargo.setTab(game,'cargo')
 local Export=require('src.editor.export')
 local config=Export.stationDef({id='prototype_parking',name='Parking',parts={},hangar={w=40,h=24},
  berths={{x=0,y=0,size=80,maxLength=1200,maxWidth=400}}})
 check(config.hangar.w==40 and config.berths[1].maxLength==1200 and config.berths[1].maxWidth==400,'station export lost spatial capacity configuration')

 -- Services come from the station definition: drop repair, lose the tab.
 local oldServices=st.def.services
 check(oldServices and game.stationServices(st).repair,'station data does not define its services')
 st.def.services={'hangar'}
 check(#Cargo.tabRects(game)==2 and not Cargo.setTab(game,'market'),'tabs ignore station services')
 st.def.services=oldServices
 -- Repair: fix the flying ship by clicking its row.
 local Repair=require('src.ui.repair')
 check(Cargo.setTab(game,'repair'),'repair tab missing')
 game.player.armor=game.player.stats.armor-50
 local RL=Repair.layout(game);local before=game:credits()
 Cargo.mousepressed(game,RL.rows[1].button.x+4,RL.rows[1].button.y+4,1)
 check(game.player.armor==game.player.stats.armor and game:credits()==before-50*game.repairRate(st),'repair did not charge and fix armor')
 game.player.armor=game.player.stats.armor-50;game.universe.credits=game.repairRate(st)*20
 screenshot('repair')
 Cargo.mousepressed(game,RL.rows[1].button.x+4,RL.rows[1].button.y+4,1)
 check(game.player.armor==game.player.stats.armor-30 and game:credits()==0,'partial repair wrong')
 game.player.armor=game.player.stats.armor;game.universe.credits=before
 Cargo.setTab(game,'cargo')

 -- The Shipyard tab: a catalogue of this station's hulls, bought by click.
 local Shipyard=require('src.ui.shipyard')
 local control
 for _,tab in ipairs(Cargo.tabRects(game)) do if tab.id=='shipyard' then control=tab end end
 check(control and control.label=='Shipyard','Shipyard service tab missing')
 Cargo.mousepressed(game,control.x+2,control.y+2,1)
 check(Cargo.tab=='shipyard','Shipyard tab did not open')
 local Y=Shipyard.layout(game)
 check(#Y.stock==#game.shipyard(st),'shipyard UI does not match actual station stock')
 screenshot('actual-shipyard')
 local marketDef=game.marketDefinition(st);local oldShips=marketDef.ships
 marketDef.ships={'halcyon_wisp','ferrous_runner'}
 Y=Shipyard.layout(game)
 check(#Y.rows==2,'catalogue rows missing')
 -- pick the second hull and a non-default paint with the mouse
 Cargo.mousepressed(game,Y.rows[2].x+10,Y.rows[2].y+10,1)
 check(Shipyard.sel=='ferrous_runner','clicking a catalogue row did not select it')
 Y=Shipyard.layout(game)
 local sw=Y.swatches[#Y.swatches]
 Cargo.mousepressed(game,sw.x+2,sw.y+2,1)
 check(Shipyard.paint==sw.name,'clicking a swatch did not pick that paint')
 screenshot('ship-catalogue-detail')
 game.universe.credits=0
 local beforeShips=#game:hangar(st)
 Cargo.mousepressed(game,Y.buy.x+4,Y.buy.y+4,1)
 check(#game:hangar(st)==beforeShips and game:credits()==0,'buy without credits changed the roster')
 game.universe.credits=1000000
 Cargo.mousepressed(game,Y.buy.x+4,Y.buy.y+4,1)
 local bought=game:hangar(st)[#game:hangar(st)]
 check(#game:hangar(st)==beforeShips+1 and bought.hull=='ferrous_runner','buy did not park a new ship')
 check(bought.color and bought.color.name==sw.name,'bought ship ignored the chosen paint')
 check(game:credits()==1000000-data.hulls.ferrous_runner.price,'buy charged the wrong price')
 -- trade it back in toward a Wisp: needs two clicks, sells the old record
 Cargo.mousepressed(game,Y.rows[1].x+10,Y.rows[1].y+10,1)
 Y=Shipyard.layout(game)
 local credit=game.shipSellPrice(bought)
 while Shipyard.tradeIn~=bought do Cargo.mousepressed(game,Y.tiNext.x+4,Y.tiNext.y+4,1) end
 local credits=game:credits()
 Cargo.mousepressed(game,Y.buy.x+4,Y.buy.y+4,1)
 check(game:credits()==credits,'trade-in bought on the first click')
 screenshot('ship-trade')
 Cargo.mousepressed(game,Y.buy.x+4,Y.buy.y+4,1)
 local still=false;for _,rec in ipairs(game:hangar(st)) do if rec==bought then still=true end end
 check(not still,'traded-in ship still owned')
 check(game:credits()==credits+credit-data.hulls.halcyon_wisp.price,'trade-in settled the wrong amount')
 check(game:hangar(st)[#game:hangar(st)].hull=='halcyon_wisp','trade-in did not deliver the new ship')
 -- selling from the hangar card also takes two clicks
 Cargo.setTab(game,'hangar')
 local wisp=game:hangar(st)[#game:hangar(st)];Hangar.sel=wisp
 local HL=Hangar.layout(game);credits=game:credits()
 Cargo.mousepressed(game,HL.sell.x+4,HL.sell.y+4,1)
 check(game:credits()==credits,'sell happened on the first click')
 screenshot('hangar-sell')
 Cargo.mousepressed(game,HL.sell.x+4,HL.sell.y+4,1)
 check(game:credits()==credits+game.shipSellPrice(wisp),'hangar sell paid the wrong amount')
 Cargo.setTab(game,'market')
 check(not Cargo.layout(game).sides[3].shipEntries,'Market shows ships')
 Cargo.setTab(game,'cargo');Cargo.marketLeft='hold';Cargo.filter='all';marketDef.ships=oldShips

 -- Save the roster, grid layout, finite mooring locations and active parking.
 local saved=assert(Save.decode(Save.encode(game:saveState())))
 check(saved.player.at.parkingMooring==exterior,'save lost active exterior allocation')
 check(saved.stations[st.key].moorings[exterior]~=nil,'save lost exterior layout')
 game:loadState(saved);st=game.player.dockState.station
 check(game.player.parkingMooring==exterior,'load lost active exterior ship location')
 check(game:hangar(st)[index].bay~=nil,'load lost stored interior ship position')
 local legacy=assert(Save.decode(Save.encode(game:saveState())))
 legacy.player.at.parkingMooring=#st.def.berths+1
 legacy.player.at.berth=nil
 legacy.player.at.mooring={x=100000,y=100000,heading=0,slot=legacy.player.at.parkingMooring}
 game:loadState(legacy);st=game.player.dockState.station
 check(game.player.dockState.berth and not game.player.dockState.mooring,'old overflow save did not move to a real berth')
 local pad=st.def.berths[game.player.dockState.berth]
 local lx,ly=st.body:getLocalPoint(game.player.body:getPosition())
 check(math.abs(lx-pad.x)<.01 and math.abs(ly-pad.y)<.01,'restored ship is away from its authored berth')
 local credits=game:credits()
 for i=#game:hangar(st),1,-1 do game:sellShip(st,i) end
 local filled=0
 while filled<#game:stationMoorings(st)+2 do
  local rec=game:addToHangar(st,'ferrous_freighter');if not rec then break end
  check(rec.mooring~=nil,'oversized ship was packed into the interior');filled=filled+1
 end
 check(filled>0 and filled<#game:stationMoorings(st)+2,'exterior storage is unbounded')
 check(game:shipBuyProblem(st,'ferrous_freighter')~=nil,'full exterior storage permits another purchase')
 local before=game:credits();check(not game:buyShip(st,'ferrous_freighter') and game:credits()==before,'failed purchase consumed credits')
 -- A full station rejects an offer atomically; selling a berthed ship
 -- in that offer can make exactly the required room.
 local mk=game.marketDefinition(st);local catalogue=mk.ships;mk.ships={'ferrous_freighter'}
 local exchange=Hold.new({{key='give',w=20,h=10},{key='receive',w=20,h=10}})
 local buy={id='ship:ferrous_freighter',n=1,owner='station'}
 assert(Hold.placeStack({grids={exchange.grids[2]}},buy))
 local roster=game:hangar(st);local count=#roster;local balance=game:credits()
 local ok,why=game:completeTrade(st,exchange)
 check(not ok and why=='NO SUITABLE FREE PARKING' and #roster==count and game:credits()==balance,'full berth offer was not atomic')
 local sell=roster[1];assert(sell)
 assert(Hold.placeStack({grids={exchange.grids[1]}},{id='ship:'..sell.hull,n=1,owner='player',shipRecord=sell}))
 local ok,why=game:completeTrade(st,exchange);check(ok,why)
 check(#game:hangar(st)==count,'ship exchange did not reuse released parking')
 mk.ships={'ferrous_freighter','ferrous_mule','ferrous_runner'}
 Cargo.setTab(game,'shipyard')
 screenshot('ship-catalogue')
 Cargo.setTab(game,'cargo');Cargo.marketLeft='hold';Cargo.filter='all';mk.ships=catalogue
 -- Filling later berths must not make newly added ships unreachable.
 local roster=game:hangar(st);local last=roster[#roster]
 Hangar.focus(game,last)
 local view=Hangar.layout(game);local visible=false
 for _,ship in ipairs(view.ships) do if ship.owner==last then visible=true end end
 check(visible,'focus failed to reveal newly added stored ship')
 local worldCanvas=love.graphics.newCanvas(love.graphics.getDimensions())
 love.graphics.push('all');love.graphics.setCanvas(worldCanvas)
 require('src.render').world(game)
 love.graphics.setCanvas();love.graphics.pop();worldCanvas:release()
 -- An open container stays on screen throughout pickup and drop.
 Cargo.setTab(game,'cargo')
 local storage=game:stationStorage(st)
 local contents=Hold.new({{key='box',name='Box contents',w=8,h=5}})
 Hold.add(contents,'scrap',3)
 local box={id='cargo_container',n=1,inner=contents}
 check(Hold.placeStack(storage,box),'could not place test container')
 Cargo.inner=contents;Cargo.lastClick=nil
 local beforeDrag=Cargo.layout(game);local source
 for _,g in ipairs(beforeDrag.grids) do if g.side.hold==storage then source=g;break end end
 local dx,dy=source.x+(box.x+.5)*beforeDrag.cs,source.y+(box.y+.5)*beforeDrag.cs
 Cargo.mousepressed(game,dx,dy,1)
 check(Cargo.hand and Cargo.hand.inner==contents,'container pickup lost its contents')
 local during=Cargo.layout(game)
 check(#during.sides==#beforeDrag.sides and during.cs==beforeDrag.cs,'container pickup changed panel count or cell size')
 for i,g in ipairs(beforeDrag.grids) do
  check(during.grids[i].x==g.x and during.grids[i].y==g.y,'container pickup moved a grid under the cursor')
 end
 Cargo.mousereleased(game,dx,dy,1)
 check(not Cargo.hand and Cargo.inner==contents and Hold.count(contents,'scrap')==3,'container drop lost open state or cargo')
 local restored=Grid.at(source.g,box.x,box.y)
 check(restored and restored.inner==contents,'container did not return to the drop cell')
 Cargo.inner=nil
 before=game:credits()
 game:undock()
 local after=game:credits();check(after==before,'undocking changed credits')
 Cargo.open=true;Cargo.loot=nil;Cargo.inner=nil
 local space=Cargo.layout(game)
 check(#space.sides==1 and space.sides[1].hold==game.player.hold and not space.equip.hidden,'station prototype changed the in-space inventory structure')
 screenshot('space')
 Cargo.open=false
 print(('STATION SERVICES TEST PASSED (%d checks)'):format(checks))
end
