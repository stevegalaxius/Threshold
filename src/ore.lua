-- The drill's drop table, shared by physical rock breaking and remote mining.
local Ore={items={rock='iron_ore',ice='water_ice',junk='scrap'}}
function Ore.drop(kind,radius)
 return Ore.items[kind],math.max(1,math.floor(radius/20))
end
return Ore
