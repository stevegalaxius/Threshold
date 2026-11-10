-- Factory time is measured in batches; ingredients are whole cargo units.
local A={products={},recipes={},byItem={}}
local function recipe(item,batch,steel,explosives)
 local c={id='make_'..item,item=item,batch=batch,cap=batch*8,factory='ammunition',
  inputs={{item='steel_plate',n=steel},{item='explosives',n=explosives}}}
 A.products[#A.products+1]=item;A.recipes[#A.recipes+1]=c;A.byItem[item]=c
end
recipe('rounds_s',200,1,1);recipe('rounds_m',100,1,1)
recipe('airburst_s',200,1,3);recipe('airburst_m',100,1,3)
recipe('shell_s',24,1,2);recipe('shell_m',12,2,3);recipe('shell_l',12,4,6)
recipe('shot_s',64,1,1);recipe('shot_m',32,2,1);recipe('shot_l',24,4,2)
function A.shop()
 local sells={};for _,id in ipairs(A.products) do sells[#sells+1]={id,1} end
 return {id='ammunition',name='Ballistic ammunition',description='Manufactured solid and airburst rounds; explosive and scatter shells.',sells=sells}
end
function A.reserve(key,item)
 if not A.byItem[item] then return 0 end
 local L=require('src.locations');local p=L.byId[key]
 if not p or p.ammunitionCapacity or not require('src.supplies').supports(key) then return 0 end
 return require('src.data').items[item].stack*2
end
return A
