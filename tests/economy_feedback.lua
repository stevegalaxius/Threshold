return function(game)
 local S,E,I=require('src.stockpile'),require('src.economy'),require('src.industry')
 local function world()return {clock=0,stations={},npcs={}} end
 local function set(u,key,item,n)S.stock(u,key,S.shopFor(key,item))[item]=n end
 local key='station:mars_3'
 local function scarce(first)
  local u=world();set(u,key,'iron_ore',10);set(u,key,'steel_plate',0);set(u,key,'empty_canister',0)
  u.clock=3600;S.count(u,key,first)
  return S.count(u,key,'steel_plate'),S.count(u,key,'empty_canister'),S.count(u,key,'iron_ore')
 end
 local a,b,c=scarce('steel_plate');local d,e,f=scarce('empty_canister')
 assert(a==d and b==e and c==f,'stock query order changed resource allocation')
 assert(a>0 and b>0 and a*2+math.ceil(b*.5-1e-9)==10,'scarce ore was lost or entirely monopolized')
 local u=world();local ceres='station:belt_1'
 set(u,ceres,'empty_canister',0);set(u,key,'empty_canister',1000)
 E.update(u,0)
 local imported=false
 for _,offer in pairs(require('src.tasks').state(u).offers) do
  if offer.item=='empty_canister' and offer.target==ceres then imported=true end
 end
 assert(imported,'producer could not import its own scarce input')
 local r={id='dry-customer',ship={hull='intaki_wisp',loadout=require('src.data').hulls.intaki_wisp.loadout,cargo={},fuelCharge=0,fuelInitialized=true}}
 set(u,ceres,'deuterium_canister',0)
 require('src.supplies').refill(r,ceres,u)
 assert((r.ship.cargo.deuterium_canister or 0)==0,'refill created emergency fuel')
 local worker={id='work-power',power=100,ship={hull='intaki_wisp',loadout=require('src.data').hulls.intaki_wisp.loadout,cargo={deuterium_canister=2},fuelInitialized=true,fuelCharge=0}}
 assert(require('src.npc_actions').power({r=worker},5,30)==30 and worker.power==70,'work did not spend capacitor')
 assert(worker.ship.cargo.deuterium_canister==2 and worker.ship.fuelCharge==0,'work ran a second reactor step')
 print('ECONOMY FEEDBACK: producer imports, fair weighted inputs, query independence and physical fuel passed')
end
