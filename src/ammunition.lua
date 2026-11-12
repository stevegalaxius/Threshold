-- Factory time is measured in batches; ingredients are whole cargo units.
local A={products={},recipes={},byItem={}}
for _,c in ipairs(require('data.industry').recipes) do
 if c.group=='ammunition' or c.group=='guided_munitions' or c.group=='drones' then A.products[#A.products+1]=c.item;A.recipes[#A.recipes+1]=c;A.byItem[c.item]=c end
end
function A.shop()
 local sells={};for _,id in ipairs(A.products) do sells[#sells+1]={id,1} end
 return {id='ammunition',name='Manufactured ammunition',description='Solid and airburst rounds, explosive and scatter shells, missiles, torpedoes and drones.',sells=sells}
end
function A.reserve(key,item) return require('src.reserves').minimum(key,item) end
return A
