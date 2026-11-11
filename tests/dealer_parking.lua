-- Guest reserves and real occupancy constrain both scheduled ship outputs
-- and dealer replenishment, including stations without live physics bodies.
return function(game)
 local P,D,I,S,C=require('src.dealer_parking'),require('src.dealers'),require('src.industry'),require('src.stockpile'),require('src.commodities')
 local data,L,Game=require('src.data'),require('src.locations'),require('src.game')
 local key='station:mars_1';local place=L.get(key);local original=data.stations[place.layout]
 local market=S.definition(key);local oldDealer=market.dealer
 local oldRecipes=require('data.industry').facilities.ship_assembly.recipes
 local w,h=Game.hangarFootprint('intaki_wisp',false)
 local def={hangar={w=w*2,h=h*2},docks={{hw=1000}},parts={},berths={}}
 for i=1,4 do def.berths[i]={x=i*2000,y=0,heading=0,maxLength=1000,maxWidth=1000} end
 data.stations[place.layout]=def
 market.dealer={hulls={'intaki_wisp'},lots=20,assembly='ship_assembly'}
 local recipe={id='test_parked_ship',stockless=true,storefront=false,market=false,inputs={{item='hull_frame',n=1}},outputs={{kind='ship',hull='intaki_wisp',n=1}},make={[key]=2},use={}}
 C.list[#C.list+1]=recipe;C.byId[recipe.id]=recipe
 require('data.industry').facilities.ship_assembly.recipes={recipe.id}
 local u={clock=0,stations={},npcs={},dealers={[key]={lots={},serial=0}}}
 local remote=P.plan(u,key,'intaki_wisp',20)
 assert(#remote==4,'unexpected commercial bay/berth capacity')
 local world=love.physics.newWorld();local body=love.physics.newBody(world)
 local station={key=key,def=def,docks=def.docks,dock=def.docks[1],body=body}
 local live=setmetatable({universe=u,fieldId=place.area,entities={},alifeOnline={}},{__index=Game})
 P.bind(u,live,station)
 local loaded=P.plan(u,key,'intaki_wisp',20)
 assert(require('src.save').encode(remote)==require('src.save').encode(loaded),'remote and loaded allocations disagree')
 D.output(u,key,'intaki_wisp',4)
 local rows,reserved=P.reserve(station)
 local inside,outside=0,0
 for _,lot in ipairs(D.lots(u,key)) do
  if lot.bay then
   local _,height=Game.hangarFootprint(lot.hull,lot.bay.rot)
   assert(lot.bay.y+height<=def.hangar.h-rows,'dealer occupied guest hangar strip');inside=inside+1
  else assert(not reserved[lot.mooring],'dealer occupied a guest berth');outside=outside+1 end
 end
 assert(inside==2 and outside==2 and D.room(u,key,'intaki_wisp')==0,'physical parking did not limit output')
 local visitor={hull='intaki_wisp'}
 assert(live:hangarFit(station,visitor.hull,visitor) and live:mooringFit(station,visitor.hull,visitor),'dealer stock blocked all guest space')
 assert(D.frameTarget(u,key)==0,'physically full station still requested construction frames')
 I.update(u,0,{key});S.stock(u,key,S.shopFor(key,D.FRAME))[D.FRAME]=10
 u.clock=3600;I.update(u,u.clock,{key})
 assert(#D.lots(u,key)==4 and S.count(u,key,D.FRAME)==10,'blocked output consumed frames or created hidden stock')
 local sold=D.lots(u,key)[1];D.take(u,key,sold.id)
 u.clock=3601;I.update(u,u.clock,{key})
 assert(#D.lots(u,key)==3,'blocked time banked an instant replacement')
 u.clock=5401;I.update(u,u.clock,{key})
 assert(#D.lots(u,key)==4 and S.count(u,key,D.FRAME)==9,'freed parking did not allow manufacturing to resume')
 local saved=assert(require('src.save').decode(require('src.save').encode(u)))
 assert(D.room(saved,key,'intaki_wisp')==0,'save/load lost commercial occupancy')
 body:destroy();world:destroy()
 require('data.industry').facilities.ship_assembly.recipes=oldRecipes
 table.remove(C.list);C.byId[recipe.id]=nil
 market.dealer=oldDealer;data.stations[place.layout]=original
 print('DEALER PARKING: shared remote/live geometry, guest reserves, full-space blocking, resumption and saving passed')
end
