-- Compiled views of data-defined facilities for freight and reserve queries.
local C={list=require('data.industry').recipes,byId={}}
for _,c in ipairs(C.list) do
 assert(not C.byId[c.id],'duplicate recipe '..c.id)
 assert((c.time or 1)>0,'invalid recipe processing time')
 c.item=c.item or c.outputs and c.outputs[1].item
 assert(c.item,'recipe requires a primary output')
 C.byId[c.id]=c
end
-- Fill each recipe's per-station rates (make / use) from the world layout.
function C.load()
 if package.loaded['src.stockpile'] then package.loaded['src.stockpile'].shopCache={} end
 local W=require('src.world_layout')
 for _,c in ipairs(C.list) do c.make,c.use={},{} end
 for _,entries in pairs(W.stations) do
  for _,entry in ipairs(entries) do
   for id,installation in pairs(entry.facilities or {}) do
    local def=assert(require('data.industry').facilities[installation.type or id],'unknown facility '..id)
    for _,recipe in ipairs(def.recipes) do
     local c=assert(C.byId[recipe],'unknown recipe '..recipe)
     c.factory=def.policy=='profit' or c.factory
     c.adaptive=def.policy=='adaptive'
     assert(not c.make[entry.id] and not c.use[entry.id],'recipe installed twice at '..entry.id)
     local rate=installation.capacity
     if rate>0 then c.make[entry.id]=rate else c.use[entry.id]=-rate end
    end
   end
  end
 end
end
C.load()
-- A commodity's inputs, whether it lists one (input) or several (inputs).
function C.inputs(c) return c.inputs or (c.input and {c.input}) or {} end
function C.outputs(c) return c.outputs or {{item=c.item,n=c.batch or 1,cap=c.cap}} end
function C.rate(c,key) return (c.make[key] or 0)-(c.use[key] or 0) end
-- Stations that take this item: its users, and makers that need it as input.
function C.takers(c)
 local set={}
 for area in pairs(c.use) do set[area]=true end
 for _,o in ipairs(C.list) do
  for _,input in ipairs(C.inputs(o)) do
   if input.item==c.item then for area in pairs(o.make) do set[area]=true end end
  end
 end
 return set
end
return C
