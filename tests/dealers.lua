-- Dealer lots: limited specific ships, timed restock, manufacturer frames.
return function(game)
 local D,S,data=require('src.dealers'),require('src.stockpile'),require('src.data')
 local u={clock=0,stations={},npcs={},credits=10^7}
 local L=require('src.locations')
 -- Earth also has the earth_4 drone foundry beside its shipyard
 for _,spec in ipairs({{'mercury','brute',3},{'earth','ferrous',4}}) do
  local area,maker=spec[1],spec[2];local id='station:'..area..'_3'
  assert(#L.stations(area)==spec[3],'dedicated shipyard did not leave '..spec[3]..' stations in '..area)
  assert(D.def(id).assembly==maker..'_assembly','dealer did not move to its shipyard')
  assert(not D.buildsShips('station:'..area..'_2'),'assembly remained at the old hub')
  assert(require('src.travelgraph').itinerary('station:mars_3',id,0),'new shipyard is unreachable for frame freight')
 end
 assert(#L.stations('mars')==4,'Mars should keep Red Furnace, Zhongke, Heaven-Ladder and Zhuhai Logistics')
 assert(L.get('station:belt_2').layout=='shipyard_2','MACK did not use the supplied shipyard')
 D.state(u,'station:belt_2').lots={}
 for _,hull in ipairs(require('data.industry').lineups.mack) do assert(D.room(u,'station:belt_2',hull)>0,'MACK shipyard cannot park '..hull) end
 local hub='station:venus_1'
 local lots=D.lots(u,hub)
 -- a dealer opens with its lots full (one-of-a-kind ships, each parked)
 assert(#lots==6,'dealer did not open fully stocked: '..#lots)
 for _,lot in ipairs(lots) do
  local h=data.hulls[lot.hull];assert(h and lot.price>0 and lot.paint and lot.loadout,'bad lot')
 end
 local first=lots[1].id
 assert(D.take(u,hub,first) and not D.find(u,hub,first),'sold ship stayed on the lot')
 u.clock=8*3600*20
 require('src.industry').update(u,u.clock,{hub})
 assert(#D.lots(u,hub)==6,'restock overfilled or stalled: '..#D.lots(u,hub))
 for _,lot in ipairs(D.lots(u,hub)) do
  local allowed=false;for _,hull in ipairs(D.def(hub).hulls) do if lot.hull==hull then allowed=true end end
  assert(not lot.used and allowed,'named dealer received generated used stock outside its lineup')
 end
 local used=D.lots(u,'station:earth_1')
 for _,lot in ipairs(used) do
  assert(lot.used and lot.condition>=.7 and lot.condition<=.95,'used lot lacks condition')
  assert(lot.price>0 and lot.armor>0,'invalid used ship')
 end
 -- Red Furnace assembles dealer inventory from delivered frames
 local works='station:mars_1'
 local s=D.state(u,works)
 local before=#s.lots
 local later={clock=0,stations={},npcs={}};D.state(later,works).lots={}
 later.clock=24*3600;D.update(later,works,later.clock)
 assert(#D.lots(later,works)==0,'ship factory received a timed delivery instead of manufacturing')
 S.stock(u,works,S.shopFor(works,D.FRAME))[D.FRAME]=0
 s.lots={};require('src.industry').update(u,u.clock,{works})
 assert(#s.lots==0,'manufacturer made ships without frames')
 S.stock(u,works,S.shopFor(works,D.FRAME))[D.FRAME]=2
 -- assembly also draws electronics and steel plate (data/industry.lua assemblyParts)
 S.stock(u,works,S.shopFor(works,'electronics')).electronics=1000
 S.stock(u,works,S.shopFor(works,'steel_plate')).steel_plate=1000
 assert(#D.lots(u,works)==0,'reading inventory built a ship')
 u.clock=u.clock+3600;require('src.industry').update(u,u.clock,{works})
 assert(#s.lots>=1,'manufacturer did not roll out a ship from frames')
 assert(s.production and s.production[s.lots[1].hull].count>0,'completed assembly did not feed NPC supply weights')
 local Save=require('src.save');u=assert(Save.decode(Save.encode(u)))
 assert(u.dealers[works],'lot not saved')
 for _,shop in ipairs(S.shops(works)) do assert(not S.lists(shop,D.FRAME),'hull frames got a storefront') end
 -- Mars specializes: Heaven-Ladder supplies frames through real freight.
 local C,E,Tasks=require('src.commodities'),require('src.economy'),require('src.tasks')
 local ladder='station:mars_3';local weaponWorks='station:mars_2'
 assert(C.byId.assemble_hull_frames.make[ladder]==10 and not C.byId.assemble_hull_frames.make[works] and not C.byId.assemble_hull_frames.make[weaponWorks],'frames assigned to the wrong Mars station')
 assert(C.byId.roll_steel.make[ladder]==480 and C.byId.press_canisters.make[ladder]==12000,'basic industry did not move intact')
 -- Zhongke (mars_2) is now the Intaki shipyard; Mars's ammunition is made on the Heaven-Ladder
 assert(C.byId.make_rounds_s.make[ladder]==24 and not C.byId.make_rounds_s.make[works] and not C.byId.make_rounds_s.make[weaponWorks],'ammunition did not consolidate on the Heaven-Ladder')
 local chain={clock=0,stations={},npcs={}}
 local dealer=D.state(chain,works);dealer.lots={}
 assert(S.count(chain,works,D.FRAME)==0 and S.count(chain,'station:earth_1',D.FRAME)==0,'frames seeded outside their producer')
 S.stock(chain,ladder,S.shopFor(ladder,D.FRAME))[D.FRAME]=60
 E.update(chain,0)
 local order
 for _,o in pairs(Tasks.state(chain).offers) do if o.item==D.FRAME and o.target==works then order=o;break end end
 assert(order and order.source==ladder,'Red Furnace did not order Heaven-Ladder frames')
 local needed=C.byId.assemble_redfu_crane.inputs[1].n
 S.add(chain,works,'electronics',1000);S.add(chain,works,'steel_plate',1000)
 S.add(chain,works,D.FRAME,needed);chain.clock=3600;E.update(chain,chain.clock)
 assert(#dealer.lots>0 and chain.economyStats.used[D.FRAME]>0,'delivered frames did not become dealer inventory')
 -- a factory dealer is full when its commercial parking is, not at its lot count
 for _,hull in ipairs(D.def(works).hulls) do while D.room(chain,works,hull)>0 do D.output(chain,works,hull,1) end end
 assert(E.target(chain,works,D.FRAME)==0,'full dealership keeps requesting frames')
 -- Assembly is scheduled, timed and saved; input reservations and lot
 -- capacity use the same executor limits as cargo-output manufacturing.
 local Industry=require('src.industry')
 local yard='station:mars_2' -- Zhongke, the Intaki atelier
 local function parts(w) S.add(w,yard,'electronics',1000);S.add(w,yard,'steel_plate',1000) end
 local timed={clock=0,stations={},npcs={}}
 local timedLot=D.state(timed,yard);timedLot.lots={};parts(timed)
 local facility=Industry.state(timed,yard,'intaki_assembly');facility.selected='assemble_intaki_archangel'
 Industry.update(timed,0,{yard});S.stock(timed,yard,S.shopFor(yard,D.FRAME))[D.FRAME]=4
 timed.clock=3600;Industry.update(timed,timed.clock,{yard})
 assert(#timedLot.lots==0 and S.count(timed,yard,D.FRAME)==4,'assembly ignored processing time')
 local oldUniverse=game.universe;game.universe=timed
 local assemblySave=assert(Save.decode(Save.encode(game:saveState())))
 game.universe=oldUniverse
 assert(assemblySave.facilities[yard..'|intaki_assembly'].recipes.assemble_intaki_archangel.carry==.5,'game save omitted assembly progress')
 local restored=assert(Save.decode(Save.encode(timed)))
 restored.clock=7200;Industry.update(restored,restored.clock,{yard})
 assert(#restored.dealers[yard].lots==1 and restored.dealers[yard].lots[1].hull=='intaki_archangel','saved assembly failed to produce its selected hull')
 assert(S.count(restored,yard,D.FRAME)==0 and restored.economyStats.used[D.FRAME]==4 and restored.economyStats.madeShips.intaki_archangel==1,'ship output bypassed stock or production accounting')
 Industry.update(restored,restored.clock,{yard})
 assert(#restored.dealers[yard].lots==1,'same-tick assembly duplicated output')
 local full=restored.dealers[yard]
 -- full means no commercial parking left (a factory dealer is not capped by its lot count)
 for _,hull in ipairs(D.def(yard).hulls) do while D.room(restored,yard,hull)>0 do D.output(restored,yard,hull,1) end end
 local parked=#full.lots
 S.add(restored,yard,D.FRAME,10);restored.clock=10800;Industry.update(restored,restored.clock,{yard})
 assert(#full.lots==parked and S.count(restored,yard,D.FRAME)==10,'full dealer consumed assembly input')
 D.take(restored,yard,full.lots[1].id);restored.clock=10801;Industry.update(restored,restored.clock,{yard})
 assert(#full.lots==parked-1,'full-lot time banked a replacement ship')
 local reserved={clock=0,stations={},npcs={}}
 local reservedLot=D.state(reserved,yard);reservedLot.lots={};parts(reserved)
 Industry.update(reserved,0,{yard});S.stock(reserved,yard,S.shopFor(yard,D.FRAME))[D.FRAME]=2
 local reservation=Tasks.post(reserved,{kind='transport',source=yard,target=ladder,item=D.FRAME,amount=2,order=true})
 reservation.state='reserved';reservation.owner='frame-hauler'
 reserved.clock=3600;Industry.update(reserved,reserved.clock,{yard})
 assert(#reservedLot.lots==0 and S.count(reserved,yard,D.FRAME)==2,'assembly consumed reserved frames')
 -- Dealer lots share physical parking, but remain outside player ownership.
 game:loadField('venus');game:captureALife(true)
 local st=assert(game:locationEntity(hub));game.universe.credits=10^8
 game:hangar(st)
 local displayed
 for _,lot in ipairs(D.lots(game.universe,st)) do if lot.bay or lot.mooring then displayed=lot;break end end
 assert(displayed,'dealer has no physically displayed ships')
 for _,owned in ipairs(game:hangar(st)) do assert(owned~=displayed,'dealer stock became player property') end
 local bay,mooring=displayed.bay,displayed.mooring
 if bay then assert(not game:hangarFree(st,{},displayed.hull,bay),'dealer bay did not block occupancy') end
 if mooring then assert(game:mooringTaken(st,mooring),'dealer berth did not block occupancy') end
 local state=assert(Save.decode(Save.encode(game:saveState())))
 local saved=state.dealers[hub].lots
 local found=false;for _,lot in ipairs(saved) do if lot.id==displayed.id then found=lot.bay~=nil or lot.mooring~=nil end end
 assert(found,'dealer parking was not saved')
 local displayedId=displayed.id
 game:loadState(state);st=assert(game:locationEntity(hub))
 displayed=assert(D.find(game.universe,st,displayedId),'saved dealer ship disappeared')
 assert(displayed.bay or displayed.mooring,'loaded dealer lost parking')
 bay,mooring=displayed.bay,displayed.mooring
 local rec,why=game:buyShip(st,displayed)
 assert(rec,why)
 assert(rec.bay==bay and rec.mooring==mooring,'purchase did not transfer its displayed space')
 assert(not D.find(game.universe,st,displayed.id),'purchased display remained on sale')
 local occurrences=0;for _,owner in ipairs(game:stationRoster(st)) do if owner==rec then occurrences=occurrences+1 end end
 assert(occurrences==1,'purchase duplicated the parked ship')
 -- Orders: the hall picks the hull the lot is shortest of and keeps it until built.
 do
  local Industry=require('src.industry');local q={clock=0,stations={},npcs={}};local yard='station:mars_2'
  local lot=D.state(q,yard);lot.lots={D.roll(D.def(yard),lot,'intaki_wisp'),D.roll(D.def(yard),lot,'intaki_praetor')}
  local room=D.room;D.room=function() return 1 end
  local def=Industry.definition('intaki_assembly',Industry.installations(yard).intaki_assembly)
  assert(Industry.job(q,yard,'intaki_assembly',def)=='assemble_intaki_archangel','heavy hull starved by lighter jobs')
  Industry.finished(q,yard,'assemble_intaki_archangel')
  lot.lots[#lot.lots+1]=D.roll(D.def(yard),lot,'intaki_archangel')
  assert(Industry.job(q,yard,'intaki_assembly',def)=='assemble_intaki_wisp','orders did not rotate after a ship rolled out')
  D.room=room
 end
 -- Consecutive real executor updates must build the middle lineup entry too.
 do
  local Industry=require('src.industry');local q={clock=0,stations={},npcs={}}
  local factory='station:mercury_3';local stock=D.state(q,factory);stock.lots={};stock.wholesaleAt=1e12
  local room,output=D.room,D.output;local completed={}
  D.room=function()return 1 end
  D.output=function(_,_,hull,n)
   completed[hull]=(completed[hull] or 0)+n
   for _=1,n do stock.lots[#stock.lots+1]={hull=hull} end
  end
  for clock=0,4*3600,60 do
   q.clock=clock
   S.stock(q,factory,S.shopFor(factory,D.FRAME))[D.FRAME]=100
   S.stock(q,factory,S.shopFor(factory,'electronics')).electronics=1000;S.stock(q,factory,S.shopFor(factory,'steel_plate')).steel_plate=1000
   S.stock(q,factory,S.shopFor(factory,'food_crate')).food_crate=1000
   Industry.update(q,clock,{factory})
  end
  D.room,D.output=room,output
  for _,hull in ipairs(require('data.industry').lineups.brute) do assert((completed[hull] or 0)>0,'assembly repeatedly skipped '..hull) end
  assert(q.economyStats.used[D.FRAME]<=8,'assembly credited the same elapsed work to multiple jobs')
 end
 print('DEALERS: limited lots, restock, trims, manufacturer frames and saving passed ('..before..' opening at the works)')
end
