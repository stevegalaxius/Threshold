-- Shared by live stations and remote A-Life. Missing lists retain the original
-- services; an explicitly empty list offers no optional services.
local S={}
function S.get(def)
 local set={}
 for _,id in ipairs(def and def.services or {'market','shipyard','hangar'}) do set[id]=true end
 return set
end
return S
