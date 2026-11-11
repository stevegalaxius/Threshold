-- A new definition runs through real stock flow without a controller branch.
return function(game)
 local D,C,I,S=require('data.industry'),require('src.commodities'),require('src.industry'),require('src.stockpile')
 local L,W=require('src.locations'),require('src.world_layout')
 local key='station:mercury_1';local place=L.byId[key]
 local recipe={id='test_recovery',item='nitrates',time=2,cap=10,
  inputs={{item='iron_ore',n=2}},outputs={{item='nitrates',n=2,cap=10},{item='steel_plate',n=1,cap=4}}}
 D.recipes[#D.recipes+1]=recipe;C.byId[recipe.id]=recipe
 D.facilities.test_recovery={policy='fixed',recipes={recipe.id}}
 place.facilities.test_recovery={capacity=12}
 C.load()
 local u={clock=0,stations={},npcs={}}
 local function set(item,n) S.stock(u,key,S.shopFor(key,item))[item]=n end
 set('nitrates',0);set('steel_plate',0);set('iron_ore',20)
 set('hydrogen_canister',100)
 local o=require('src.tasks').post(u,{kind='transport',source=key,target='station:mars_1',item='iron_ore',amount=18,order=true})
 o.state='reserved';o.owner='test-owner'
 u.clock=300
 assert(S.count(u,key,'nitrates')==0,'fractional recipe time created a batch')
 local Save=require('src.save');u=assert(Save.decode(Save.encode(u)))
 u.clock=600
 assert(S.count(u,key,'nitrates')==2 and S.count(u,key,'steel_plate')==1,'multi-output recipe or saved progress failed')
 assert(S.count(u,key,'iron_ore')==18,'recipe stole reserved input')
 u.clock=3600
 assert(S.count(u,key,'nitrates')==2,'reserved inputs did not block production')
 u.tasks.offers={};set('iron_ore',100)
 u.clock=3601
 assert(S.count(u,key,'nitrates')==2,'blocked time banked into a burst')
 u.clock=7200
 assert(S.count(u,key,'steel_plate')==4 and S.count(u,key,'nitrates')==8,'secondary output cap was ignored')
 set('steel_plate',0);u.clock=7201
 assert(S.count(u,key,'nitrates')==8,'storage-blocked work was banked')
 -- Existing hydrogen consumption is a separate installation, not a share
 -- of the new facility's twelve processing units.
 S.count(u,key,'hydrogen_canister')
 assert(u.economyStats.used.hydrogen_canister>0,'independent consumer stopped')
 place.facilities.test_recovery=nil;D.facilities.test_recovery=nil;C.byId[recipe.id]=nil;table.remove(D.recipes)
 C.load()
 print('INDUSTRY: definition-only facility, processing time, multiple outputs, reservations, caps and saved progress passed')
end
