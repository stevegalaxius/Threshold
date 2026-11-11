-- Bounded raw resources -> electronics -> guided ammunition integration.
return function(game)
 local S,C,E,I=require('src.stockpile'),require('src.commodities'),require('src.economy'),require('src.industry')
 local Tasks,Transport=require('src.tasks'),require('src.transport')
 local function set(u,key,item,n) S.stock(u,key,S.shopFor(key,item))[item]=n end
 local function world() return {clock=0,stations={},npcs={}} end
 local sources={{'station:mercury_1','silicon',12},{'station:luna_2','silicon',12},{'station:venus_1','industrial_acids',8},{'station:io_1','industrial_acids',8}}
 for _,source in ipairs(sources) do
  local u=world();assert(S.count(u,source[1],source[2])==0)
  u.clock=3600
  assert(S.count(u,source[1],source[2])==source[3],'wrong raw resource source or rate')
 end
 for _,key in ipairs({'station:earth_1','station:luna_1'}) do
  local u=world();set(u,key,'silicon',2);set(u,key,'industrial_acids',1);S.count(u,key,'electronics')
  u.clock=900
  assert(S.count(u,key,'electronics')==8 and S.count(u,key,'silicon')==0 and S.count(u,key,'industrial_acids')==0,'electronics ignored inputs or batch rate')
  u.clock=1800
  assert(S.count(u,key,'electronics')==8,'electronics appeared without input supply')
 end
 local u=world();local source='station:earth_1';local works='station:mars_2'
 set(u,source,'electronics',100);set(u,works,'electronics',0)
 E.update(u,0)
 local order
 for _,o in pairs(Tasks.state(u).offers) do if o.item=='electronics' and o.source==source and o.target==works then order=o;break end end
 assert(order and order.commodityBuyPrice and order.commoditySellPrice,'missing quoted electronics freight to Zhongke')
 local carrier={id='electronics-hauler',ship={cargo={electronics=order.amount}},credits=0}
 order.phase='delivery';Tasks.definitions.transport.complete(u,carrier,order,works,0)
 assert(S.count(u,works,'electronics')==order.amount,'electronics delivery failed')
 -- Guided recipes are blocked by electronics, not just casing/warheads.
 local guided={'missile_s','missile_m','missile_l','torp_s','torp_m','torp_l'}
 for _,item in ipairs(guided) do
  local w=world();local mix=I.state(w,works,'ammunition').mix
  for id in pairs(mix) do mix[id]=id=='make_'..item and 1 or 0 end
  set(w,works,'steel_plate',1000);set(w,works,'explosives',1000);set(w,works,'electronics',0);S.count(w,works,item)
  w.clock=3600
  assert(S.count(w,works,item)==0,'guided ammunition did not require electronics')
 end
 -- These types now use the same finite rearming path and usage accounting.
 local customer='station:earth_2'
 local data=require('src.data');local hull,slot
 for _,candidate in pairs(data.hulls) do
  for i,spec in ipairs(candidate.slots) do if spec.family=='bay' and spec.size=='S' then hull,slot=candidate,i;break end end
  if hull then break end
 end
 assert(hull,'missing missile customer fixture')
 local loadout=require('src.persistence').copy(hull.loadout);loadout[slot]='missile_s_base'
 local r={id='guided-customer',ship={hull=hull.id,loadout=loadout,loads={},cargo={},fuelCharge=2500,fuelInitialized=true},ammoReserve={missile_s=5,torp_s=2}}
 for _,entry in ipairs({{'missile_s',2},{'torp_s',1}}) do
  r.ship.loads[slot]=entry[1];set(u,customer,entry[1],entry[2])
  require('src.supplies').refill(r,customer,u)
  assert(r.ship.cargo[entry[1]]==entry[2],'guided rearming ignored stock')
  require('src.supplies').refill(r,customer,u)
  assert(r.ship.cargo[entry[1]]==entry[2],'empty station generated guided ammunition')
 end
 print('ELECTRONICS: resource geography, recipe inputs, freight, guided requirements and finite rearming passed')
end
