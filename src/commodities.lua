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
}}
function C.rate(c,area) return (c.make[area] or 0)-(c.use[area] or 0) end
-- Regions that take this item: its users, and makers that need it as input.
function C.takers(c)
 local set={}
 for area in pairs(c.use) do set[area]=true end
 for _,o in ipairs(C.list) do
  if o.input and o.input.item==c.item then for area in pairs(o.make) do set[area]=true end end
 end
 return set
end
return C
