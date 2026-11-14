-- The drill's drop table, shared by physical rock breaking and remote mining.
-- rare: what a vein in a big rock, or a crystal in big ice, gives
-- (src/rock_chips.lua).
local Ore={items={rock='iron_ore',ice='water_ice'},rare={rock='gold_ore',ice='cryo_crystal'}}
function Ore.isRare(item)
 for _,id in pairs(Ore.rare) do if id==item then return true end end
 return false
end
function Ore.drop(kind,radius)
 return Ore.items[kind],math.max(1,math.floor(radius/20))
end
return Ore
