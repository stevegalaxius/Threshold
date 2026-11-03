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
 local st=game:locationEntity('earth/orbital_one')
 game.universe.populationSpawns={}
 game:dockInstantly(game.player,st,{interior=true})
 local r=game:stationRecord(st)
 check(#Cargo.tabs==3,'station services missing')
 local labels={};for _,tab in ipairs(Cargo.tabs) do labels[tab.label]=true end
 check(labels.Storage and labels.Market and labels.Hangar and not labels.Outfitting,'service tabs do not describe existing station mechanics')
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
 check(#tabs==3 and tabs[1].x>=0 and tabs[3].x+tabs[3].w<=sw,'service tabs moved outside the resized window')
 screenshot('storage')
 Cargo.setTab(game,'hangar');local shipLayout=Hangar.layout(game)
 local listed=false
 for _,s in ipairs(shipLayout.ships) do if s.owner==game.player and s.exterior then listed=true end end
 check(listed and #shipLayout.berths==#slots,'hangar does not show active and stored exterior ships')
 screenshot('hangar')
 Cargo.setTab(game,'market');local layout=Cargo.layout(game)
 check(#layout.sides==3 and layout.equip.hidden,'market is not a three-panel inventory workspace')
 checkWorkspace(layout.sides)
 for _,g in ipairs(layout.grids) do
  check(g.x>=g.side.x and g.x+g.g.w*layout.cs<=g.side.x+g.side.pw and g.y+g.g.h*layout.cs<=g.side.y+g.side.ph,'inventory grid overflows its station panel')
 end
 local offer=layout.sides[2]
 check(offer.complete.x>=offer.x and offer.complete.x+offer.complete.w<=offer.x+offer.pw and offer.clear.y+offer.clear.h<=offer.y+offer.ph,'trade controls leave center panel')
 local trade=layout.sides[2].hold
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
 screenshot('market')
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
 local worldCanvas=love.graphics.newCanvas(love.graphics.getDimensions())
 love.graphics.push('all');love.graphics.setCanvas(worldCanvas)
 require('src.render').world(game)
 love.graphics.setCanvas();love.graphics.pop();worldCanvas:release()
 game:undock()
 local after=game:credits();check(after==before,'undocking changed credits')
 Cargo.open=true;Cargo.loot=nil;Cargo.inner=nil
 local space=Cargo.layout(game)
 check(#space.sides==1 and space.sides[1].hold==game.player.hold and not space.equip.hidden,'station prototype changed the in-space inventory structure')
 screenshot('space')
 Cargo.open=false
 print(('STATION SERVICES TEST PASSED (%d checks)'):format(checks))
end
