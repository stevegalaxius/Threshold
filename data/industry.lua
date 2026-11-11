-- Recipes and facility types. Capacities are batches per game hour.
local D={recipes={
 -- Raw nitrates: Ceres processes ice, chemical-rich moons supply directly.
 {id='process_nitrates',item='nitrates',opening=0,cap=480,input={item='water_ice',n=1}},
 {id='produce_nitrates',item='nitrates',opening=0,cap=480},
 -- Each unit uses one unit of a plant's shared chemical processing time.
 {id='make_fertilizer',item='fertilizer',group='chemicals',cap=240,input={item='nitrates',n=1}},
 {id='make_explosives',item='explosives',group='chemicals',cap=240,input={item='nitrates',n=2}},
 -- rolled steel shares the same item as plates recovered from wrecks
 {id='roll_steel',item='steel_plate',cap=240,input={item='iron_ore',n=2}},
 -- pressing empty canisters out of ore
 {id='press_canisters',market=false,item='empty_canister',cap=1500,input={item='iron_ore',n=1}},
 -- filling them with hydrogen skimmed from a gas giant
 {id='skim_hydrogen',market=false,item='hydrogen_canister',cap=60,input={item='empty_canister',n=1}},
 -- cracking ice into deuterium, one canister of it per ice
 {id='crack_ice',market=false,item='deuterium_canister',cap=1000,
  inputs={{item='water_ice',n=1},{item='empty_canister',n=1}}},
 -- skimming deuterium straight from a gas giant's air: just canisters
 {id='skim_deuterium',market=false,item='deuterium_canister',cap=1000,input={item='empty_canister',n=1}},
 -- welding hull frames for a manufacturer's dealer lot (src/dealers.lua)
 {id='assemble_hull_frames',item='hull_frame',group='shipworks',market=false,storefront=false,opening=0,cap=12,input={item='steel_plate',n=6}},
 -- using hydrogen up (the inner planets' industry)
 {id='burn_hydrogen',market=false,item='hydrogen_canister',cap=60},
}}
local function recipe(item,batch,steel,explosives)
 local c={reserve={service='supplies',stacks=2,excludeProducers=true},id='make_'..item,item=item,batch=batch,cap=batch*8,group='ammunition',
  inputs={{item='steel_plate',n=steel},{item='explosives',n=explosives}}}
 D.recipes[#D.recipes+1]=c
end
recipe('rounds_s',200,1,1);recipe('rounds_m',100,1,1)
recipe('airburst_s',200,1,3);recipe('airburst_m',100,1,3)
recipe('shell_s',24,1,2);recipe('shell_m',12,2,3);recipe('shell_l',12,4,6)
recipe('shot_s',64,1,1);recipe('shot_m',32,2,1);recipe('shot_l',24,4,2)
D.recipes[#D.recipes+1]={id='grow_food',consumption='food',market=false,item='food_crate',cap=4000,inputs={{item='fertilizer',n=1/20}},foodIndependent=true}
D.facilities={
 chemicals={policy='profit',openingInputs={nitrates=1},recipes={'make_fertilizer','make_explosives'}},
 ammunition={policy='profit',recipes={}},
 farm={policy='fixed',recipes={'grow_food'}},
 shipworks={policy='fixed',openingOutputs={hull_frame=2},openingInputs={steel_plate=8},recipes={'assemble_hull_frames'}},
}
for _,c in ipairs(D.recipes) do
 if c.group=='ammunition' then D.facilities.ammunition.recipes[#D.facilities.ammunition.recipes+1]=c.id end
 if not c.group and c.id~='grow_food' then D.facilities[c.id]={policy='adaptive',recipes={c.id}} end
 if c.market==nil then c.market=true end
end
D.shops={chemicals={id='chemicals',name='Chemicals',description='Nitrates, agricultural fertilizer and industrial explosives.',sells={{'nitrates',1},{'fertilizer',1},{'explosives',1}}}}
D.reserves={steel_plate={service='repair',minimum=8,openingMultiplier=2}}
D.consumption={food={recipe='grow_food',facility='farm',item='food_crate',reserveHours=4,transition=3600,minOutput=.5}}
return D
