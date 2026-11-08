-- Shared by live stations and remote A-Life. Missing lists retain the original
-- services; an explicitly empty list offers no optional services.
local S={}
-- A station's own services (its world_layout entry) win over its design's.
function S.get(def,place)
 local set={}
 for _,id in ipairs(place and place.services or def and def.services or {'market','shipyard','hangar'}) do set[id]=true end
 return set
end
return S
