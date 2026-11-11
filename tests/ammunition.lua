-- Bounded manufacture -> freight -> finite NPC rearming scenario.
return function(game)
 local A,S,C=require('src.ammunition'),require('src.stockpile'),require('src.markets')
 local E,Tasks,Supplies=require('src.economy'),require('src.tasks'),require('src.supplies')
 local plant='station:mars_1';local destination='station:earth_1'
 local function set(u,key,item,n) S.stock(u,key,S.shopFor(key,item))[item]=n>0 and n or nil end
 local function world(item)
  local u={clock=0,stations={},npcs={},industry={[plant]={press_canisters=0,roll_steel=0}}}
  local mix=require('src.industry').state(u,plant,'ammunition').mix
  for _,id in ipairs(A.products) do S.count(u,plant,id);mix['make_'..id]=item and (id==item and 1 or 0) or 1/#A.products end
  set(u,plant,'steel_plate',1000);set(u,plant,'explosives',1000)
  return u
 end
 for _,recipe in ipairs(A.recipes) do
  local u=world(recipe.item)
  u.clock=300
  assert(S.count(u,plant,recipe.item)==recipe.batch,'recipe did not produce a complete ammunition batch: '..recipe.item)
  assert(S.count(u,plant,'steel_plate')==1000-recipe.inputs[1].n and S.count(u,plant,'explosives')==1000-recipe.inputs[2].n,'ammunition did not use both material inputs')
  set(u,plant,'explosives',0);u.clock=600
  assert(S.count(u,plant,recipe.item)==recipe.batch,'ammunition appeared without explosives')
 end
 assert(A.byItem.airburst_s.inputs[2].n>A.byItem.rounds_s.inputs[2].n and A.byItem.shell_s.inputs[2].n>A.byItem.shot_s.inputs[2].n,'special ammunition did not require more explosives')
 local u=world();u.clock=3600
 local batches=0
 for _,recipe in ipairs(A.recipes) do batches=batches+S.count(u,plant,recipe.item)/recipe.batch end
 assert(batches<=12,'ammunition recipes each received the full shared capacity')
 -- A full store cannot bank unused factory time for instantaneous production.
 local capped=world('rounds_s');set(capped,plant,'rounds_s',A.byItem.rounds_s.cap)
 capped.clock=3600;S.count(capped,plant,'rounds_s')
 S.take(capped,plant,'rounds_s',200);capped.clock=3601
 assert(S.count(capped,plant,'rounds_s')==A.byItem.rounds_s.cap-200,'capped factory banked an hour of production')
 local r={id='ammo-customer',ship={hull='intaki_wisp',loadout=require('src.data').hulls.intaki_wisp.loadout,cargo={deuterium_canister=20},fuelCharge=2500,fuelInitialized=true},ammoReserve={rounds_s=10}}
 set(u,destination,'rounds_s',7)
 Supplies.refill(r,destination,u)
 assert(r.ship.cargo.rounds_s==7 and S.count(u,destination,'rounds_s')==0,'NPC rearming ignored finite station stock')
 Supplies.refill(r,destination,u)
 assert(r.ship.cargo.rounds_s==7 and u.economyStats.used.rounds_s==7,'empty station created ammunition or double-counted usage')
 r.ammoReserve=nil;r.ship.loads={}
 for index,id in pairs(r.ship.loadout) do
  local m=id and require('src.data').modules[id]
  if m and m.weapon and m.weapon.kind=='cannon' then r.ship.loads[index]='airburst_s' end
 end
 set(u,destination,'airburst_s',3)
 Supplies.refill(r,destination,u)
 assert(r.ship.cargo.airburst_s==3,'NPC did not rearm its selected alternative ammunition')
 E.update(u,u.clock)
 local shipment
 for _,o in pairs(Tasks.state(u).offers) do if o.item=='rounds_s' and o.source==plant and o.target==destination then shipment=o;break end end
 assert(shipment and shipment.commodityBuyPrice and shipment.commoditySellPrice,'empty ammunition store did not generate quoted freight')
 local before=S.count(u,destination,'rounds_s')
 local t=require('src.persistence').copy(shipment);t.amount=10;t.phase='delivery'
 local carrier={id='ammo-hauler',ship={cargo={rounds_s=10}}}
 assert(Tasks.definitions.transport.complete(u,carrier,t,destination,u.clock),'ammunition freight did not deliver')
 assert(S.count(u,destination,'rounds_s')==before+10,'ammunition delivery did not replenish real rearming stock')
 -- Opening a shop never replaces missing manufactured ammunition.
 local old=game.universe;game.universe=u
 local st={key=destination,locationId=destination};local shop=S.shopFor(st,'rounds_s')
 set(u,destination,'rounds_s',0)
 local market=game:stationMarket(st,shop);market.next.rounds_s=u.clock-10000
 game:shopTick(st,shop,S.shops(st)[shop])
 assert(S.count(u,destination,'rounds_s')==0,'legacy market timer conjured manufactured ammunition')
 assert(S.stock(u,st,#S.shops(st))==nil,'debug supplies stopped being a separate unlimited shop')
 game.universe=old
 print('AMMUNITION: all recipes, shared batches, input limits, finite rearming, freight and shop stock passed')
end
