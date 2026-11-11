-- Shared used stock, real NPC arrival purchase, and readable production reasons.
return function(game)
 local D,S,P=require('src.dealers'),require('src.stockpile'),require('src.population')
 local data,L,I=require('src.data'),require('src.locations'),require('src.industry')
 local key='station:earth_1';local u=game.universe
 local state=D.state(u,key);state.lots={}
 local preset=data.enemies.runner_trader
 local lot=D.roll({hulls={preset.hull},trims={'stock'}},state,preset.hull)
 lot.loadout=require('src.persistence').copy(preset.loadout or data.hulls[preset.hull].loadout)
 lot.used=true;lot.condition=.8;lot.armor=require('src.stats').compute(data.hulls[lot.hull],lot.loadout).armor*.8
 lot.price=10000;lot.cargo={[require('src.reactor_fuel').item()]=2}
 state.lots={lot}
 -- No other Earth inventory can be chosen behind the test's back.
 for _,id in ipairs(L.stations('earth')) do if id~=key then D.state(u,id).lots={} end end
 local policy=require('src.npc_templates').purchase('trader')
 local candidate=D.purchaseCandidate(u,'earth',policy)
 assert(candidate and candidate.lot==lot,'eligible shared lot not offered to NPC')
 local poor=D.purchaseCandidate(u,'earth',{budget=1,requires={cargo=true}})
 assert(not poor,'acquisition ignored affordability')
 local count=require('src.population').total(u,'trader')
 local r,why=P.spawn(game,'earth','trader',false)
 assert(r,why)
 assert(r.ship.hull==lot.hull and r.shipAcquisition.lot==lot.id and r.shipAcquisition.price==lot.price,'arrival did not acquire the selected ship')
 assert(not D.find(u,key,lot.id),'NPC purchase remained available to the player')
 assert(P.total(u,'trader')==count+1,'purchase duplicated the NPC')
 local nextNpc=u.nextNpcId
 local missing,reason=P.spawn(game,'earth','trader',false)
 assert(not missing and reason:find('No suitable ship') and u.nextNpcId==nextNpc,'empty dealerships spawned a phantom hull')
 local copy=assert(require('src.save').decode(require('src.save').encode(r)))
 assert(copy.shipAcquisition.lot==lot.id,'acquisition provenance lost on save')
 local works='station:mars_2';local recipe=require('src.commodities').byId.make_missile_s
 S.stock(u,works,S.shopFor(works,'steel_plate')).steel_plate=1000
 S.stock(u,works,S.shopFor(works,'explosives')).explosives=1000
 S.stock(u,works,S.shopFor(works,'electronics')).electronics=0
 local label=I.status(u,works,'ammunition',recipe)
 assert(label:find('Waiting for Electronics'),'missing electronics reason was not shown: '..label)
 assert(game.stationServices({key='station:mercury_1',locationId='station:mercury_1'}).shipyard,'used exchange unavailable to the player')
 print('USED SHIPS: shared stock, affordability, NPC purchase, empty-stock deferral, provenance and production reasons passed')
end
