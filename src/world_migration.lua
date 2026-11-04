-- Translate legacy identity references in a snapshot without changing its data.
-- Active systems use immutable IDs; old names are confined to the alias table.
local aliases=require('src.world_layout').aliases
local M={}
function M.ids(value)
 if type(value)=='string' then return aliases[value] or value end
 if type(value)~='table' then return value end
 local result={}
 for key,item in pairs(value) do result[M.ids(key)]=M.ids(item) end
 return result
end
return M
