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
 {id='skim_hydrogen',market=false,item='hydrogen_canister',cap=600,input={item='empty_canister',n=1}},
 -- cracking ice into deuterium, one canister of it per ice
 {id='crack_ice',market=false,globalPrice=true,item='deuterium_canister',cap=4000,
  inputs={{item='water_ice',n=1},{item='empty_canister',n=1}}},
 -- skimming deuterium straight from a gas giant's air: just canisters
 {id='skim_deuterium',market=false,item='deuterium_canister',cap=4000,input={item='empty_canister',n=1}},
 -- welding hull frames for a manufacturer's dealer lot (src/dealers.lua)
 {id='assemble_hull_frames',item='hull_frame',group='shipworks',market=false,storefront=false,opening=0,cap=36,input={item='steel_plate',n=6}},
 -- Refined local resources: abstract station extraction, no extra ore chain.
 -- Water: every station drinks it (world_layout defaults.waterUse); Ceres
 -- melts ice for it, and the ice moons pump it straight from their oceans.
 {id='use_water',market=false,service='water',item='water',cap=200},   -- (a station service: src/station_services.lua runs it)
 {id='melt_water',item='water',opening=0,cap=1200,input={item='water_ice',n=1}},
 {id='pump_water',group='resources',item='water',opening=0,cap=1200},
 {id='refine_silicon',group='resources',item='silicon',opening=0,cap=192},
 {id='produce_acids',group='resources',item='industrial_acids',opening=0,cap=128},
 -- Medical supplies: made at Earth from electronics and water, used up
 -- by the far stations; delicate, so only climate holds carry them.
 {id='make_medical',item='medical_supplies',opening=0,batch=4,cap=128,inputs={{item='electronics',n=1},{item='water',n=1}}},
 {id='use_medical',market=false,item='medical_supplies',cap=96},
 {id='make_electronics',group='electronics',item='electronics',opening=0,batch=8,cap=256,
  inputs={{item='silicon',n=2},{item='industrial_acids',n=1}}},
 -- Ice moons cut ice from their crusts. Terraforming takes tanked water.
 {id='cut_ice',group='resources',item='water_ice',opening=0,cap=1600},
 {id='terraform_water',market=false,item='water',cap=400},
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
-- Flare charges: a steel casing and a pyrotechnic charge, made at the
-- Diwan chemical works on Titan (Abaddon).
recipe('flare',60,1,1,nil,nil,'pyrotechnics')
recipe('shot_s',64,1,1);recipe('shot_m',32,2,1);recipe('shot_l',24,4,2)
-- Guided ammunition: electronics, steel casing and explosive warheads.
recipe('missile_s',40,1,1,1,1);recipe('missile_m',20,2,2,1,1);recipe('missile_l',12,4,4,2,2)
recipe('torp_s',4,1,2,1,2);recipe('torp_m',2,2,3,1,3);recipe('torp_l',1,2,3,2,4)
-- Drones: mostly electronics in a steel frame, no warhead.
recipe('drone_s',4,2,0,2,2,'drones');recipe('drone_m',2,3,0,3,3,'drones');recipe('drone_l',1,4,0,4,4,'drones')
-- Hull patch kits: steel and an acid-cured sealant, made at the munitions
-- works alongside ammunition and stocked at every station the same way.
D.recipes[#D.recipes+1]={reserve={service='supplies',stacks=2,excludeProducers=true},id='make_patch_kit',item='patch_kit',batch=8,cap=64,group='ammunition',
 inputs={{item='steel_plate',n=1},{item='industrial_acids',n=1}}}
-- Finished ships are typed outputs delivered to dealer inventory, not cargo.
-- Factory lineups: each maker's assembly hall builds its own three hulls.
-- Hull frames per ship (also its assembly time), roughly one per 25k of
-- list price.
D.lineups={
 mack={'mack_mustang','mack_burro','mack_longhorn'},
 ferrous={'ferrous_pony','ferrous_mule','ferrous_bison','ferrous_bison_carrier'},
 brute={'brute_anvil','brute_nautilus'},
 amw={'amw_sprint','amw_sprint_fat','amw_wayfarer','amw_wayfarer_fat'},
 redfu={'redfu_crane','redfu_pelican','redfu_gila'},
 intaki={'intaki_wisp','intaki_praetor','intaki_archangel'},
}
D.assemblyFrames={mack_mustang=2,mack_burro=2,mack_longhorn=3,ferrous_pony=1,ferrous_mule=2,ferrous_bison=3,ferrous_bison_carrier=3,
 brute_anvil=2,brute_nautilus=3,intaki_wisp=1,intaki_praetor=3,intaki_archangel=4,
 amw_sprint=1,amw_sprint_fat=1,amw_wayfarer=2,amw_wayfarer_fat=2,redfu_crane=1,redfu_pelican=2,redfu_gila=3}
-- Parts per ship beyond its frames: two electronics per 5k of list price,
-- one steel plate per 50 mass (generated from data/ships).
D.assemblyParts={mack_mustang={electronics=13,steel=7},
 mack_burro={electronics=20,steel=12},
 mack_longhorn={electronics=29,steel=16},
 ferrous_pony={electronics=9,steel=3},
 ferrous_mule={electronics=20,steel=9},
 ferrous_bison={electronics=28,steel=18},
 ferrous_bison_carrier={electronics=30,steel=16},
 brute_anvil={electronics=16,steel=5},
 brute_nautilus={electronics=29,steel=16},
 amw_sprint={electronics=11,steel=2},
 amw_sprint_fat={electronics=11,steel=2},
 amw_wayfarer={electronics=17,steel=4},
 amw_wayfarer_fat={electronics=17,steel=5},
 redfu_crane={electronics=8,steel=4},
 redfu_pelican={electronics=16,steel=9},
 redfu_gila={electronics=25,steel=17},
 intaki_wisp={electronics=12,steel=2},
 intaki_praetor={electronics=22,steel=7},
 intaki_archangel={electronics=38,steel=16}}
-- Military yards: each faction's own service hulls, built for its police
-- and couriers (src/npc_ship_supply.lua takes them off the yard's lot).
-- Kept apart from D.lineups so they never reach a public dealer or an
-- ordinary buyer.
D.serviceLineups={
 estates={'estates_whisper','estates_rapier','estates_bastion'},
 diwan={'diwan_cherubim','diwan_seraph'},
}
D.assemblyFrames.estates_whisper,D.assemblyFrames.estates_rapier,D.assemblyFrames.estates_bastion=1,2,4
D.assemblyFrames.diwan_cherubim,D.assemblyFrames.diwan_seraph=2,4
D.assemblyParts.estates_whisper={electronics=12,steel=1}
D.assemblyParts.estates_rapier={electronics=16,steel=6}
D.assemblyParts.estates_bastion={electronics=38,steel=15}
D.assemblyParts.diwan_cherubim={electronics=25,steel=6}
D.assemblyParts.diwan_seraph={electronics=36,steel=9}
for _,set in ipairs({D.lineups,D.serviceLineups}) do for _,hulls in pairs(set) do for _,hull in ipairs(hulls) do
 local n=D.assemblyFrames[hull];local parts=D.assemblyParts[hull]
 D.recipes[#D.recipes+1]={id='assemble_'..hull,group='ship_assembly',market=false,storefront=false,stockless=true,time=n,
  inputs={{item='hull_frame',n=n},{item='electronics',n=parts.electronics},{item='steel_plate',n=parts.steel}},outputs={{kind='ship',hull=hull,n=1}}}
end end end
D.recipes[#D.recipes+1]={id='grow_food',consumption='food',market=false,item='food_crate',cap=4000,inputs={{item='fertilizer',n=1/20}},foodIndependent=true}
D.recipes[#D.recipes+1]={id='receive_surface_food',consumption='food',market=false,item='food_crate',cap=8000,foodIndependent=true}
D.facilities={
 water={policy='fixed',recipes={'use_water'}},
 terraform_water={policy='fixed',recipes={'terraform_water'}},
 water_melter={policy='fixed',recipes={'melt_water'}},
 water_wells={policy='fixed',recipes={'pump_water'}},
 -- adaptive, so ice follows demand instead of piling up at the wells
 ice_wells={policy='adaptive',recipes={'cut_ice'}},
 silicon_refinery={policy='fixed',recipes={'refine_silicon'}},
 acid_works={policy='fixed',recipes={'produce_acids'}},
 electronics={policy='profit',recipes={'make_electronics'}},
 chemicals={policy='profit',openingInputs={nitrates=.5},recipes={'make_fertilizer','make_explosives'}},
 ammunition={policy='profit',recipes={}},
 pyrotechnics={policy='profit',recipes={}},
 -- Electronics come a long way to Saturn, so keep a longer input buffer.
 guided_munitions={policy='profit',inputHours=3,recipes={}},
 drones={policy='profit',recipes={}},
 farm={policy='fixed',recipes={'grow_food'}},
 surface_food={policy='fixed',recipes={'receive_surface_food'}},
 shipworks={policy='fixed',openingOutputs={hull_frame=2},openingInputs={steel_plate=.5},recipes={'assemble_hull_frames'}},
}
-- Ship modules ----------------------------------------------------------
-- Each kind of module comes from one faction's works (D.moduleLines);
-- engines and reactors from two works each. A module is market cargo like
-- ammunition: the works stocks it, freight carries it to every station whose
-- market lists it, and those listings are the shelves' targets
-- (reserve service 'listed', src/reserves.lua).
-- Belt depots extract heavy metals like Mercury refines silicon; coils and
-- ceramics are the intermediates engines and reactors are built from.
D.recipes[#D.recipes+1]={id='extract_heavy_metals',group='resources',item='heavy_metals',opening=0,cap=192}
D.recipes[#D.recipes+1]={id='make_superconducting_coils',group='coils',item='superconducting_coils',opening=0,cap=64,
 inputs={{item='heavy_metals',n=2},{item='electronics',n=1}}}
D.recipes[#D.recipes+1]={id='make_thermal_ceramics',group='ceramics',item='thermal_ceramics',opening=0,cap=64,
 inputs={{item='silicon',n=2},{item='industrial_acids',n=1}}}
-- Inputs per module, from its mass and list price the way ship parts are:
-- one steel plate per 4 t, one electronics per 2,500 CR, and an hour of
-- works time per 10,000 CR (half an hour at least).
--   { module, mass, price [, coils, ceramics, deuterium] }
D.moduleLines={
 launchers={maker='Gilgal Arsenal',modules={{'missile_s_base',3,4000},{'missile_m_base',8,11000},{'missile_l_base',18,26000}}},
 guns={maker='Zhongke Ordnance',modules={{'gun_s_base',4,2200},{'gun_m_base',10,6500},{'gun_l_base',24,15000},
  {'artillery_s_base',6,3400},{'artillery_m_base',16,9000},{'artillery_l_base',34,24000}}},
 bays={maker='Ashgrove Foundry',modules={{'drone_s_base',6,7000},{'drone_m_base',14,18000},{'drone_l_base',30,40000}}},
 lasers={maker='Loki Optics',modules={{'beam_s_base',6,6000},{'beam_m_base',14,16000},{'beam_l_base',32,42000},
  {'pulse_s_base',5,5200},{'pulse_m_base',12,14000},{'pulse_l_base',30,38000}}},
 drills={maker='Ceres Concern',modules={{'drill_s_base',6,3500},{'drill_m_base',14,9000},{'drill_l_base',34,24000}}},
 engines={modules={{'flit_engine',6,3000,1,1},{'mule_engine',16,9000,2,2},{'cinder_drive',40,26000,4,4}}},
 reactors={modules={{'ember_reactor',5,2500,1,1,1},{'kiln_reactor',14,8000,2,2,1},{'forge_reactor',32,21000,4,4,1}}},
}
-- fixed order, so recipe lists come out the same every run
D.moduleLineOrder={'launchers','guns','bays','lasers','drills','engines','reactors'}
for _,line in ipairs(D.moduleLineOrder) do
 local def,ids=D.moduleLines[line],{}
 for i,m in ipairs(def.modules) do
  local id,mass,price,coils,ceramics,fuel=m[1],m[2],m[3],m[4],m[5],m[6]
  local inputs={{item='steel_plate',n=math.max(1,math.floor(mass/4+.5))}}
  local electronics=math.max(coils and 0 or 1,math.floor(price/2500+.5)-(coils or 0)*2)
  if electronics>0 then inputs[#inputs+1]={item='electronics',n=electronics} end
  if coils then inputs[#inputs+1]={item='superconducting_coils',n=coils} end
  if ceramics then inputs[#inputs+1]={item='thermal_ceramics',n=ceramics} end
  if fuel then inputs[#inputs+1]={item='deuterium_canister',n=fuel} end
  D.recipes[#D.recipes+1]={id='make_'..id,group=line,item=id,cap=4,time=math.max(.5,price/10000),
   reserve={service='listed',excludeProducers=true},inputs=inputs}
  ids[i]='make_'..id
 end
 D.facilities[line..'_works']={policy='profit',recipes=ids}
end
D.facilities.metal_extraction={policy='fixed',recipes={'extract_heavy_metals'}}
D.facilities.coil_works={policy='profit',recipes={'make_superconducting_coils'}}
D.facilities.ceramic_works={policy='profit',recipes={'make_thermal_ceramics'}}
for _,set in ipairs({D.lineups,D.serviceLineups}) do for maker,hulls in pairs(set) do
 local r={};for i,h in ipairs(hulls) do r[i]='assemble_'..h end
 D.facilities[maker..'_assembly']={policy='orders',recipes=r}
end end
for _,c in ipairs(D.recipes) do
 if c.group=='ammunition' or c.group=='guided_munitions' or c.group=='drones' or c.group=='pyrotechnics' then local f=D.facilities[c.group].recipes;f[#f+1]=c.id end
 if not c.group and c.consumption~='food' then D.facilities[c.id]={policy='adaptive',recipes={c.id}} end
 if c.market==nil then c.market=true end
end
D.inputHours=.5 -- reorder at thirty minutes, refill toward one hour
D.shops={chemicals={id='chemicals',name='Chemicals',description='Nitrates, agricultural fertilizer and industrial explosives.',sells={{'nitrates',1},{'fertilizer',1},{'explosives',1}}}}
D.usedShips={lots=2,intervalHours=16,markup=.85,minCondition=.7,maxCondition=.95,presets={'ferrous_pony','ferrous_mule','ferrous_bison','mack_longhorn','miner','police','raider'},
 -- Decommissioned police hulls: rarely, a used lot is one of these.
 rarePresets={'estates_whisper','diwan_cherubim'},rareChance=.04}
D.npcShips={usedChance=.2,productionHalfLifeHours=12,baselineWeight=1}
D.dealerParking={guestHangarFraction=.25,guestBerths=2}
-- Fuel-chain throughput supports the original 2,500-energy canister. The
-- half-hour input buffer starts logistics; ongoing stock still needs freight.
D.facilities.press_canisters.openingInputs={iron_ore=.5}
D.facilities.skim_deuterium.openingInputs={empty_canister=.5}
D.facilities.crack_ice.openingInputs={water_ice=.5,empty_canister=.5}
D.reserves={deuterium_canister={service='supplies',minimum=120,openingMultiplier=2},steel_plate={service='repair',minimum=8,openingMultiplier=2}}
D.consumption={food={recipe='grow_food',facility='farm',item='food_crate',reserveHours=4,transition=3600,minOutput=.25}}
return D
