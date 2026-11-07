--[[
	Trade commodities: what regions make and use, in units per game hour.
	A region's trade stations each make (make) or use up (use) the item, in
	the shop that holds it for NPCs (src/stockpile.lua). Making stops at cap
	and, with an input, uses input.n of that item (from the same station's
	stock) per unit made; using stops at empty.

	Transport (src/transport.lua) posts hauls from each maker to each user,
	and to each region whose making needs it as input. A hauler only takes
	one when the source has the cargo and the target is under cap.
]]
local C={list={
 -- Mars presses empty canisters from the ore its moons send down.
 {item='empty_canister',amount=10,cap=60,make={mars=24},use={},input={item='iron_ore',n=1}},
 -- The gas giants fill them for the inner planets.
 {item='hydrogen_canister',amount=10,cap=60,
  make={jupiter=20,saturn=20,uranus=12,neptune=12},input={item='empty_canister',n=1},
  use={venus=16,mercury=12}},
 -- Ceres cracks its ice into deuterium, one canister of it per two ice.
 -- (Not hauled out yet: nothing lists a user.)
 {item='deuterium_canister',amount=10,cap=60,make={belt=12},use={},
  inputs={{item='water_ice',n=2},{item='empty_canister',n=1}}},
 -- Jupiter and Uranus skim deuterium from their atmospheres: no ice, just
 -- canisters to fill. (A second entry for the same item: each region makes
 -- it by one recipe only, so their carries never mix.)
 {item='deuterium_canister',amount=10,cap=60,make={jupiter=12,uranus=8},use={},
  input={item='empty_canister',n=1}},
}}
-- A commodity's inputs, whether it lists one (input) or several (inputs).
function C.inputs(c) return c.inputs or (c.input and {c.input}) or {} end
function C.rate(c,area) return (c.make[area] or 0)-(c.use[area] or 0) end
-- Regions that take this item: its users, and makers that need it as input.
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
