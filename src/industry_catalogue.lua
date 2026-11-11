-- A documentation view of the live definitions; no duplicate recipe table.
local M={}
function M.markdown()
 local C,I,L,data=require('src.commodities'),require('src.industry'),require('src.locations'),require('src.data')
 local lines={'# Manufacturing outputs','','Generated from the current item, recipe and station definitions with `love . --industrycatalogue`. Capture stdout to regenerate this file.','',
 'Capacities below are rated processing units per game hour. Recipes in one installation share that capacity. Output/hour = allocated capacity × batch output ÷ processing time; food shortages and missing inputs/storage can reduce it. Adaptive facilities retain their existing 0.25–4 rate multiplier.','',
 '## Recipe outputs','','| Recipe | Inputs per batch | Outputs per batch | Processing time | Storage limit |','|---|---|---|---:|---|'}
 local recipes={};for _,c in ipairs(C.list) do recipes[#recipes+1]=c end;table.sort(recipes,function(a,b)return a.id<b.id end)
 for _,c in ipairs(recipes) do
  if next(c.make) then
   local inputs,outputs,caps={},{},{}
   for _,input in ipairs(C.inputs(c)) do inputs[#inputs+1]=input.n..' '..data.items[input.item].name end
   for _,o in ipairs(C.outputs(c)) do
    if o.kind=='ship' then outputs[#outputs+1]=o.n..' '..data.hulls[o.hull].name..' → dealer inventory';caps[#caps+1]='Dealer lot limit'
    else outputs[#outputs+1]=o.n..' '..data.items[o.item].name;caps[#caps+1]=(o.cap or c.cap)..' '..data.items[o.item].name end
   end
   lines[#lines+1]=('| `%s` | %s | %s | %s | %s |'):format(c.id,#inputs>0 and table.concat(inputs,', ') or 'Local extraction',table.concat(outputs,', '),c.time or 1,table.concat(caps,', '))
  end
 end
 lines[#lines+1]='';lines[#lines+1]='## Installed capacities';lines[#lines+1]=''
 lines[#lines+1]='| Location | Installation | Policy | Capacity/hour | Recipes |';lines[#lines+1]='|---|---|---|---:|---|'
 local keys={};for key,p in pairs(L.byId) do if p.facilities then keys[#keys+1]=key end end;table.sort(keys)
 for _,key in ipairs(keys) do
  local ids={};for id in pairs(I.installations(key)) do ids[#ids+1]=id end;table.sort(ids)
  for _,id in ipairs(ids) do
   local installation=I.installations(key)[id];local def=I.definition(id,installation)
   lines[#lines+1]=('| %s (`%s`) | `%s` | %s | %s | %s |'):format(L.get(key).name,key,id,def.policy,installation.capacity,table.concat(def.recipes,', '))
  end
 end
 lines[#lines+1]='';lines[#lines+1]='Negative capacity entries are consumption, not manufacturing output. Food is also consumed separately at every inhabited station; repairs, rearming and fuel sales are event-driven consumers.'
 lines[#lines+1]='';lines[#lines+1]='Finished ships include the dealership-selected trim, paint and fitted modules. Modules are not yet separately consumed by ship assembly. Opening dealer inventory is seeded world stock; subsequent manufactured ships require recipe inputs and processing time. Sales-lot capacity governs output; physical parking allocation remains separate, and ships may await a berth.'
 return table.concat(lines,'\n')..'\n'
end
return M
