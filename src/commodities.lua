--[[
	Trade commodities: what stations make and use, in units per game hour.
	Each station runs its own recipes (make) or uses an item up (use), in
	the shop that holds it for NPCs (src/stockpile.lua). Making stops at cap
	and, with an input, uses input.n of that item (from the same station's
	stock) per unit made; using stops at empty.

	Stations order what they run short of (src/economy.lua), and haulers
	fill the orders from whichever maker has stock to spare.
]]
-- Recipes: what a station can make and from what. Which stations run one,
-- and how fast, is the station's own (its industry in src/world_layout.lua:
-- recipe id = units an hour, a negative rate uses the item up).
local C={list={
 -- processing mineral-bearing ice into agricultural nutrients
 {id='make_fertilizer',item='fertilizer',cap=240,input={item='water_ice',n=1}},
 -- Saturn's moon stations supply fertilizer directly, without imported inputs
 {id='produce_fertilizer',item='fertilizer',cap=240},
 -- pressing empty canisters out of ore
 {id='press_canisters',item='empty_canister',amount=10,cap=1500,input={item='iron_ore',n=1}},
 -- filling them with hydrogen skimmed from a gas giant
 {id='skim_hydrogen',item='hydrogen_canister',amount=10,cap=60,input={item='empty_canister',n=1}},
 -- cracking ice into deuterium, one canister of it per ice
 {id='crack_ice',item='deuterium_canister',amount=10,cap=1000,
  inputs={{item='water_ice',n=1},{item='empty_canister',n=1}}},
 -- skimming deuterium straight from a gas giant's air: just canisters
 {id='skim_deuterium',item='deuterium_canister',amount=10,cap=1000,input={item='empty_canister',n=1}},
 -- using hydrogen up (the inner planets' industry)
 {id='burn_hydrogen',item='hydrogen_canister',amount=10,cap=60},
}}
C.byId={}
for _,c in ipairs(C.list) do C.byId[c.id]=c end
-- Fill each recipe's per-station rates (make / use) from the world layout.
function C.load()
 local W=require('src.world_layout')
 for _,c in ipairs(C.list) do c.make,c.use={},{} end
 for _,entries in pairs(W.stations) do
  for _,entry in ipairs(entries) do
   for id,rate in pairs(entry.industry or {}) do
    local c=assert(C.byId[id],'unknown recipe '..tostring(id)..' at '..entry.id)
    if rate>0 then c.make[entry.id]=rate else c.use[entry.id]=-rate end
   end
  end
 end
end
C.load()
-- A commodity's inputs, whether it lists one (input) or several (inputs).
function C.inputs(c) return c.inputs or (c.input and {c.input}) or {} end
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
