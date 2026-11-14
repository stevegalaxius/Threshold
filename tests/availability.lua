-- Regional availability: love . --availabilitytest
return function(game)
 local A,S,L=require('src.availability'),require('src.stockpile'),require('src.locations')
 assert(A.status(1,4)=='short' and A.status(4,4)=='ok' and A.status(12,4)=='glut' and A.status(0,0)=='none','status bands')
 local u=game.universe
 local items=A.items()
 assert(#items>0,'no goods listed')
 local rows=A.table(u)
 local area='earth';local id=L.stations(area,'trade')[1]
 assert(id,'earth has no trade station')
 local item='steel_plate'
 local before=rows[item][area].count
 S.stock(u,id,S.shopFor(id,item))[item]=S.count(u,id,item)+7
 local after=A.region(u,area,item)
 assert(after.count==before+7,'region total does not follow station stock')
 for _,st in ipairs(after.stations) do assert(st.target>=0,'negative target') end
 local hulls=A.hulls(u)
 assert(type(hulls[area])=='table','no hull roll-up')
 -- every view draws without error (stub UI)
 local lines=0
 local Stub={BeginComboBox=function() return false end,EndComboBox=function() end,
  TextSelectable=function() return false end,Text=function() lines=lines+1 end}
 for _,mode in ipairs({'good','region','short','hulls'}) do A.view.mode=mode;A.panel(game,Stub) end
 assert(lines>4,'panel drew nothing')
 print('AVAILABILITY TEST PASSED')
end
