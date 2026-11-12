-- Recipes and facility types. Capacities are batches per game hour.
local D={recipes={
 -- Raw nitrates: Ceres processes ice, chemical-rich moons supply directly.
 {id='process_nitrates',item='nitrates',opening=0,cap=960,input={item='water_ice',n=1}},
 {id='produce_nitrates',item='nitrates',opening=0,cap=960},
 -- Each unit uses one unit of a plant's shared chemical processing time.
 {id='make_fertilizer',item='fertilizer',group='chemicals',cap=480,input={item='nitrates',n=1}},
 {id='make_explosives',item='explosives',group='chemicals',cap=720,input={item='nitrates',n=2}},
 -- rolled steel shares the same item as plates recovered from wrecks
 {id='roll_steel',item='steel_plate',cap=1200,input={item='iron_ore',n=2}},
 -- One ore presses two empty canisters; fractional credits keep stock whole.
 {id='press_canisters',market=false,item='empty_canister',cap=6000,input={item='iron_ore',n=.5}},
 -- filling them with hydrogen skimmed from a gas giant
 {id='skim_hydrogen',market=false,item='hydrogen_canister',cap=60,input={item='empty_canister',n=1}},
 -- cracking ice into deuterium, one canister of it per ice
 {id='crack_ice',market=false,item='deuterium_canister',cap=4000,
  inputs={{item='water_ice',n=1},{item='empty_canister',n=1}}},
 -- skimming deuterium straight from a gas giant's air: just canisters
 {id='skim_deuterium',market=false,item='deuterium_canister',cap=4000,input={item='empty_canister',n=1}},
 -- welding hull frames for a manufacturer's dealer lot (src/dealers.lua)
 {id='assemble_hull_frames',item='hull_frame',group='shipworks',market=false,storefront=false,opening=0,cap=36,input={item='steel_plate',n=6}},
 -- Refined local resources: abstract station extraction, no extra ore chain.
 {id='refine_silicon',group='resources',item='silicon',opening=0,cap=192},
 {id='produce_acids',group='resources',item='industrial_acids',opening=0,cap=128},
 {id='make_electronics',group='electronics',item='electronics',opening=0,batch=8,cap=256,
  inputs={{item='silicon',n=2},{item='industrial_acids',n=1}}},
 -- using hydrogen up (the inner planets' industry)
 {id='burn_hydrogen',market=false,item='hydrogen_canister',cap=60},
}}
-- Plain rounds come from the munitions factory; guided rounds (anything
-- with electronics) from their own works; drones from a drone works.
local function recipe(item,batch,steel,explosives,electronics,time,group)
 local c={reserve={service='supplies',stacks=2,excludeProducers=true},id='make_'..item,item=item,batch=batch,cap=batch*8,group=group or (electronics and 'guided_munitions' or 'ammunition'),time=time,
  inputs={{item='steel_plate',n=steel}}}
 if explosives>0 then c.inputs[#c.inputs+1]={item='explosives',n=explosives} end
 if electronics then c.inputs[#c.inputs+1]={item='electronics',n=electronics} end
 D.recipes[#D.recipes+1]=c
end
recipe('rounds_s',200,1,1);recipe('rounds_m',100,1,1)
recipe('airburst_s',200,1,3);recipe('airburst_m',100,1,3)
recipe('shell_s',24,1,2);recipe('shell_m',12,2,3);recipe('shell_l',12,4,6)
recipe('shot_s',64,1,1);recipe('shot_m',32,2,1);recipe('shot_l',24,4,2)
-- Guided ammunition: electronics, steel casing and explosive warheads.
recipe('missile_s',40,1,1,1,1);recipe('missile_m',20,2,2,1,1);recipe('missile_l',12,4,4,2,2)
recipe('torp_s',4,4,8,2,2);recipe('torp_m',2,6,12,3,3);recipe('torp_l',1,8,16,4,4)
-- Drones: mostly electronics in a steel frame, no warhead.
recipe('drone_s',4,2,0,2,2,'drones');recipe('drone_m',2,3,0,3,3,'drones');recipe('drone_l',1,4,0,4,4,'drones')
-- Finished ships are typed outputs delivered to dealer inventory, not cargo.
-- Factory lineups: each maker's assembly hall builds its own three hulls.
-- Hull frames per ship (also its assembly time), roughly one per 25k of
-- list price.
D.lineups={
 mack={'mack_mustang','mack_burro','mack_longhorn'},
 ferrous={'ferrous_runner','ferrous_mule','ferrous_bison'},
 brute={'brute_runt','brute_anvil','brute_nautilus'},
 intaki={'intaki_wisp','intaki_praetor','intaki_archangel'},
}
D.assemblyFrames={mack_mustang=2,mack_burro=2,mack_longhorn=3,ferrous_runner=1,ferrous_mule=2,ferrous_bison=3,
 brute_runt=2,brute_anvil=2,brute_nautilus=3,intaki_wisp=1,intaki_praetor=3,intaki_archangel=4}
for _,hulls in pairs(D.lineups) do for _,hull in ipairs(hulls) do
 local n=D.assemblyFrames[hull]
 D.recipes[#D.recipes+1]={id='assemble_'..hull,group='ship_assembly',market=false,storefront=false,stockless=true,time=n,
  inputs={{item='hull_frame',n=n}},outputs={{kind='ship',hull=hull,n=1}}}
end end
D.recipes[#D.recipes+1]={id='grow_food',consumption='food',market=false,item='food_crate',cap=4000,inputs={{item='fertilizer',n=1/20}},foodIndependent=true}
D.facilities={
 silicon_refinery={policy='fixed',recipes={'refine_silicon'}},
 acid_works={policy='fixed',recipes={'produce_acids'}},
 electronics={policy='profit',recipes={'make_electronics'}},
 chemicals={policy='profit',openingInputs={nitrates=.5},recipes={'make_fertilizer','make_explosives'}},
 ammunition={policy='profit',recipes={}},
 -- Electronics come a long way to Saturn, so keep a longer input buffer.
 guided_munitions={policy='profit',inputHours=3,recipes={}},
 drones={policy='profit',recipes={}},
 farm={policy='fixed',recipes={'grow_food'}},
 shipworks={policy='fixed',openingOutputs={hull_frame=2},openingInputs={steel_plate=.5},recipes={'assemble_hull_frames'}},
}
for maker,hulls in pairs(D.lineups) do
 local r={};for i,h in ipairs(hulls) do r[i]='assemble_'..h end
 D.facilities[maker..'_assembly']={policy='orders',recipes=r}
end
for _,c in ipairs(D.recipes) do
 if c.group=='ammunition' or c.group=='guided_munitions' or c.group=='drones' then local f=D.facilities[c.group].recipes;f[#f+1]=c.id end
 if not c.group and c.id~='grow_food' then D.facilities[c.id]={policy='adaptive',recipes={c.id}} end
 if c.market==nil then c.market=true end
end
D.inputHours=.5 -- reorder at thirty minutes, refill toward one hour
D.shops={chemicals={id='chemicals',name='Chemicals',description='Nitrates, agricultural fertilizer and industrial explosives.',sells={{'nitrates',1},{'fertilizer',1},{'explosives',1}}}}
D.usedShips={intervalHours=8,markup=.85,minCondition=.7,maxCondition=.95,presets={'runner_trader','packhorse_trader','freighter','longhorn_hauler','miner_packhorse','salvager_packhorse','patrol_wisp','pirate_wisp'}}
D.npcShips={usedChance=.2,productionHalfLifeHours=12,baselineWeight=1,wholesaleHours=2}
D.dealerParking={guestHangarFraction=.25,guestBerths=2}
-- Fuel-chain throughput supports the original 2,500-energy canister. The
-- half-hour input buffer starts logistics; ongoing stock still needs freight.
D.facilities.press_canisters.openingInputs={iron_ore=.5}
D.facilities.skim_deuterium.openingInputs={empty_canister=.5}
D.facilities.crack_ice.openingInputs={water_ice=.5,empty_canister=.5}
D.reserves={deuterium_canister={service='supplies',minimum=120,openingMultiplier=2},steel_plate={service='repair',minimum=8,openingMultiplier=2}}
D.consumption={food={recipe='grow_food',facility='farm',item='food_crate',reserveHours=4,transition=3600,minOutput=.5}}
return D
