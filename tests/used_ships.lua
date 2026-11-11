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
 local supply=require('src.npc_ship_supply');local config=require('data.industry').npcShips
 local usedChance=config.usedChance;config.usedChance=1
 local count=require('src.population').total(u,'trader')
 local r,why=P.spawn(game,'earth','trader',false)
 assert(r,why)
 assert(r.ship.hull==lot.hull and r.shipAcquisition.lot==lot.id and r.shipAcquisition.price==lot.price,'arrival did not acquire the selected ship')
 assert(not D.find(u,key,lot.id),'NPC purchase remained available to the player')
 assert(P.total(u,'trader')==count+1,'purchase duplicated the NPC')
 local generated,reason=P.spawn(game,'earth','trader',false)
 assert(generated,reason)
 assert(generated.shipAcquisition.source=='generated','empty used market blocked generated arrival')
 state.lots={lot};config.usedChance=0
 local abstract,origin=supply.acquire(u,'earth',policy,function()return .5 end)
 assert(abstract and origin.source=='generated' and D.find(u,key,lot.id)==lot,'generated arrival consumed a physical lot')
 state.lots={}
 config.usedChance=usedChance
 local baseline=supply.weight(u,'mack_mustang')
 supply.produced(u,key,'mack_mustang',20)
 assert(supply.weight(u,'mack_mustang')==baseline+20,'completed production did not affect hull weight')
 local at=u.clock;u.clock=at+config.productionHalfLifeHours*3600
 assert(math.abs(supply.weight(u,'mack_mustang')-(baseline+10))<1e-6,'production influence did not decay')
 u.clock=at
 for _,role in ipairs({'trader','miner','salvager','patrol','pirate'}) do
  local policy=require('src.npc_templates').purchase(role)
  local ship,origin=supply.generated(u,policy,function()return .5 end)
  assert(ship,'no generated ship for '..role)
  if role=='trader' then assert(ship.hull=='mack_mustang','dominant production did not influence selection') end
  local capabilities=require('src.npc_access').capabilities({ship=ship})
  for name in pairs(policy.requires) do assert(capabilities[name],role..' lacks '..name) end
  assert(origin.price<=policy.budget,'generated ship exceeded budget')
  for i,id in ipairs(ship.loadout) do if id then assert(data.fits(data.hulls[ship.hull].slots[i],data.modules[id]),'generated fit incompatible') end end
 end
 local q={clock=0,stations={},npcs={}};local factory='station:mars_1'
 for id,place in pairs(L.byId) do if place.facilities and place.facilities.intaki_assembly then factory=id;break end end
 local factoryDef=D.def(factory);assert(factoryDef.assembly)
 local inventory=D.state(q,factory);inventory.lots={D.roll(factoryDef,inventory)}
 supply.wholesale(q,factory,inventory,factoryDef,0)
 q.clock=config.wholesaleHours*3600
 supply.wholesale(q,factory,inventory,factoryDef,q.clock)
 assert(#inventory.lots==0,'wholesale sale did not free factory space')
 local used=D.rollUsed(factoryDef,inventory);inventory.lots={used};q.clock=q.clock*2
 supply.wholesale(q,factory,inventory,factoryDef,q.clock)
 assert(inventory.lots[1]==used,'wholesale consumed player-facing used stock')
 local copy=assert(require('src.save').decode(require('src.save').encode(r)))
 assert(copy.shipAcquisition.lot==lot.id,'acquisition provenance lost on save')
 local saved=assert(require('src.save').decode(require('src.save').encode(game:saveState())))
 assert(saved.dealers[key].production.mack_mustang.count==20,'production influence was not saved')
 local works='station:mars_2';local recipe=require('src.commodities').byId.make_missile_s
 S.stock(u,works,S.shopFor(works,'steel_plate')).steel_plate=1000
 S.stock(u,works,S.shopFor(works,'explosives')).explosives=1000
 S.stock(u,works,S.shopFor(works,'electronics')).electronics=0
 local label=I.status(u,works,'ammunition',recipe)
 assert(label:find('Waiting for Electronics'),'missing electronics reason was not shown: '..label)
 assert(game.stationServices({key='station:mercury_1',locationId='station:mercury_1'}).shipyard,'used exchange unavailable to the player')
 print('USED SHIPS: shared stock, affordability, NPC purchase, generated fallback, production weights, wholesale, provenance and production reasons passed')
end
