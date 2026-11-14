-- Regional availability: love . --availabilitytest
return function(game)
 local A,S,L=require('src.availability'),require('src.stockpile'),require('src.locations')
 assert(A.status(1,4)=='short' and A.status(4,4)=='ok' and A.status(12,4)=='glut' and A.status(0,0)=='none' and A.status(68,0)=='glut','status bands')
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
 -- module availability and regional fits
 local data=require('src.data')
 local mods=A.modules(u,area)
 for mid,r in pairs(mods) do assert(data.modules[mid] and r.count>=0,'bad module row '..mid) end
 local hull={slots={{family='hardpoint',size='S'}}}
 local base=data.modules.gun_s_base;local alt
 for mid,c in pairs(data.modules) do
  if mid~='gun_s_base' and A.role(c)==A.role(base) and data.fits(hull.slots[1],c) then alt=mid;break end
 end
 if alt then
  local fake={gun_s_base={count=0,stations={}},[alt]={count=5,stations={}}}
  assert(A.regionalFit(u,area,hull,{'gun_s_base'},fake)[1]==alt,'regional fit kept a module the region lacks')
 end
 assert(A.regionalFit(u,area,hull,{'gun_s_base'},{gun_s_base={count=3,stations={}}})[1]=='gun_s_base','regional fit swapped a stocked module')
 assert(A.role(data.modules.gun_s_base)~=A.role(data.modules.beam_s_base),'a laser counts as a gun')
 assert(A.regionalFit(u,area,hull,{false},{})[1]==false,'regional fit filled an empty slot')
 -- every view draws without error (stub UI)
 local lines=0
 local Stub={BeginComboBox=function() return false end,EndComboBox=function() end,
  TextSelectable=function() return false end,Text=function() lines=lines+1 end}
 for _,mode in ipairs({'good','region','short','hulls','modules'}) do A.view.mode=mode;A.panel(game,Stub) end
 assert(lines>4,'panel drew nothing')
 print('AVAILABILITY TEST PASSED')
end
