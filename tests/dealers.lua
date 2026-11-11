-- Dealer lots: limited specific ships, timed restock, manufacturer frames.
return function(game)
 local D,S,data=require('src.dealers'),require('src.stockpile'),require('src.data')
 local u={clock=0,stations={},npcs={},credits=10^7}
 local hub='station:venus_1'
 local lots=D.lots(u,hub)
 assert(#lots==math.ceil(6*0.6),'dealer did not open part-stocked: '..#lots)
 for _,lot in ipairs(lots) do
  local h=data.hulls[lot.hull];assert(h and lot.price>0 and lot.paint and lot.loadout,'bad lot')
 end
 local first=lots[1].id
 assert(D.take(u,hub,first) and not D.find(u,hub,first),'sold ship stayed on the lot')
 u.clock=8*3600*20
 require('src.industry').update(u,u.clock,{hub})
 assert(#D.lots(u,hub)==6,'restock overfilled or stalled: '..#D.lots(u,hub))
 local used=D.lots(u,'station:ring_1')
 for _,lot in ipairs(used) do
  assert(lot.used and lot.condition>=.7 and lot.condition<=.95,'used lot lacks condition')
  assert(lot.price>0 and lot.armor>0,'invalid used ship')
 end
 -- Red Furnace assembles dealer inventory from delivered frames
 local works='station:mars_1'
 local s=D.state(u,works)
 local before=#s.lots
 S.stock(u,works,S.shopFor(works,D.FRAME))[D.FRAME]=0
 s.lots={};require('src.industry').update(u,u.clock,{works})
 assert(#s.lots==0,'manufacturer made ships without frames')
 S.stock(u,works,S.shopFor(works,D.FRAME))[D.FRAME]=2
 assert(#D.lots(u,works)==0,'reading inventory built a ship')
 u.clock=u.clock+3600;require('src.industry').update(u,u.clock,{works})
 assert(#s.lots>=1,'manufacturer did not roll out a ship from frames')
 local Save=require('src.save');u=assert(Save.decode(Save.encode(u)))
 assert(u.dealers[works],'lot not saved')
 for _,shop in ipairs(S.shops(works)) do assert(not S.lists(shop,D.FRAME),'hull frames got a storefront') end
 -- Mars specializes: Heaven-Ladder supplies frames through real freight.
 local C,E,Tasks=require('src.commodities'),require('src.economy'),require('src.tasks')
 local ladder='station:mars_3';local weaponWorks='station:mars_2'
 assert(C.byId.assemble_hull_frames.make[ladder]==2 and not C.byId.assemble_hull_frames.make[works] and not C.byId.assemble_hull_frames.make[weaponWorks],'frames assigned to the wrong Mars station')
 assert(C.byId.roll_steel.make[ladder]==120 and C.byId.press_canisters.make[ladder]==2400,'basic industry did not move intact')
 assert(C.byId.make_rounds_s.make[weaponWorks]==24 and not C.byId.make_rounds_s.make[works],'ammunition did not consolidate at Zhongke')
 local chain={clock=0,stations={},npcs={}}
 local dealer=D.state(chain,works);dealer.lots={}
 assert(S.count(chain,works,D.FRAME)==0 and S.count(chain,'station:earth_1',D.FRAME)==0,'frames seeded outside their producer')
 S.stock(chain,ladder,S.shopFor(ladder,D.FRAME))[D.FRAME]=12
 E.update(chain,0)
 local order
 for _,o in pairs(Tasks.state(chain).offers) do if o.item==D.FRAME and o.target==works then order=o;break end end
 assert(order and order.source==ladder,'Red Furnace did not order Heaven-Ladder frames')
 local needed=C.byId.assemble_brute_anvil.inputs[1].n
 S.add(chain,works,D.FRAME,needed);chain.clock=3600;E.update(chain,chain.clock)
 assert(#dealer.lots>0 and chain.economyStats.used[D.FRAME]>0,'delivered frames did not become dealer inventory')
 while #dealer.lots<D.def(works).lots do dealer.lots[#dealer.lots+1]=D.roll(D.def(works),dealer) end
 assert(E.target(chain,works,D.FRAME)==0,'full dealership keeps requesting frames')
 -- Assembly is scheduled, timed and saved; input reservations and lot
 -- capacity use the same executor limits as cargo-output manufacturing.
 local Industry=require('src.industry')
 local timed={clock=0,stations={},npcs={}}
 local timedLot=D.state(timed,works);timedLot.lots={}
 local facility=Industry.state(timed,works,'ship_assembly');facility.selected='assemble_brute_nautilus'
 Industry.update(timed,0,{works});S.stock(timed,works,S.shopFor(works,D.FRAME))[D.FRAME]=4
 timed.clock=3600;Industry.update(timed,timed.clock,{works})
 assert(#timedLot.lots==0 and S.count(timed,works,D.FRAME)==4,'assembly ignored processing time')
 local oldUniverse=game.universe;game.universe=timed
 local assemblySave=assert(Save.decode(Save.encode(game:saveState())))
 game.universe=oldUniverse
 assert(assemblySave.facilities[works..'|ship_assembly'].recipes.assemble_brute_nautilus.carry==.5,'game save omitted assembly progress')
 local restored=assert(Save.decode(Save.encode(timed)))
 restored.clock=7200;Industry.update(restored,restored.clock,{works})
 assert(#restored.dealers[works].lots==1 and restored.dealers[works].lots[1].hull=='brute_nautilus','saved assembly failed to produce its selected hull')
 assert(S.count(restored,works,D.FRAME)==0 and restored.economyStats.used[D.FRAME]==4 and restored.economyStats.madeShips.brute_nautilus==1,'ship output bypassed stock or production accounting')
 Industry.update(restored,restored.clock,{works})
 assert(#restored.dealers[works].lots==1,'same-tick assembly duplicated output')
 local full=restored.dealers[works]
 while #full.lots<D.def(works).lots do full.lots[#full.lots+1]=D.roll(D.def(works),full) end
 S.add(restored,works,D.FRAME,10);restored.clock=10800;Industry.update(restored,restored.clock,{works})
 assert(#full.lots==D.def(works).lots and S.count(restored,works,D.FRAME)==10,'full dealer consumed assembly input')
 D.take(restored,works,full.lots[1].id);restored.clock=10801;Industry.update(restored,restored.clock,{works})
 assert(#full.lots==D.def(works).lots-1,'full-lot time banked a replacement ship')
 local reserved={clock=0,stations={},npcs={}}
 local reservedLot=D.state(reserved,works);reservedLot.lots={}
 Industry.update(reserved,0,{works});S.stock(reserved,works,S.shopFor(works,D.FRAME))[D.FRAME]=2
 local reservation=Tasks.post(reserved,{kind='transport',source=works,target=ladder,item=D.FRAME,amount=2,order=true})
 reservation.state='reserved';reservation.owner='frame-hauler'
 reserved.clock=3600;Industry.update(reserved,reserved.clock,{works})
 assert(#reservedLot.lots==0 and S.count(reserved,works,D.FRAME)==2,'assembly consumed reserved frames')
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
 print('DEALERS: limited lots, restock, trims, manufacturer frames and saving passed ('..before..' opening at the works)')
end
