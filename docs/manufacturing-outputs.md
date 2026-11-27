# Manufacturing outputs

Generated from the current item, recipe and station definitions with `love . --industrycatalogue`. Capture stdout to regenerate this file.

Capacities below are rated processing units per game hour. Recipes in one installation share that capacity. Output/hour = allocated capacity × batch output ÷ processing time; food shortages and missing inputs/storage can reduce it. Adaptive facilities retain their existing 0.25–4 rate multiplier.

## Recipe outputs

| Recipe | Inputs per batch | Outputs per batch | Processing time | Storage limit |
|---|---|---|---:|---|
| `assemble_brute_anvil` | 2 Hull frame | 1 Anvil → dealer inventory | 2 | Available dealer parking and lot limit |
| `assemble_brute_nautilus` | 3 Hull frame | 1 Nautilus → dealer inventory | 3 | Available dealer parking and lot limit |
| `assemble_brute_runt` | 2 Hull frame | 1 Runt → dealer inventory | 2 | Available dealer parking and lot limit |
| `assemble_ferrous_bison` | 3 Hull frame | 1 Bison → dealer inventory | 3 | Available dealer parking and lot limit |
| `assemble_ferrous_mule` | 2 Hull frame | 1 Mule → dealer inventory | 2 | Available dealer parking and lot limit |
| `assemble_ferrous_runner` | 1 Hull frame | 1 Runner → dealer inventory | 1 | Available dealer parking and lot limit |
| `assemble_hull_frames` | 6 Steel plates | 1 Hull frame | 1 | 36 Hull frame |
| `assemble_intaki_archangel` | 4 Hull frame | 1 Archangel → dealer inventory | 4 | Available dealer parking and lot limit |
| `assemble_intaki_praetor` | 3 Hull frame | 1 Praetor → dealer inventory | 3 | Available dealer parking and lot limit |
| `assemble_intaki_wisp` | 1 Hull frame | 1 Wisp → dealer inventory | 1 | Available dealer parking and lot limit |
| `assemble_mack_burro` | 2 Hull frame | 1 Burro → dealer inventory | 2 | Available dealer parking and lot limit |
| `assemble_mack_longhorn` | 3 Hull frame | 1 Longhorn → dealer inventory | 3 | Available dealer parking and lot limit |
| `assemble_mack_mustang` | 2 Hull frame | 1 Mustang → dealer inventory | 2 | Available dealer parking and lot limit |
| `crack_ice` | 1 Water ice, 1 Empty canister | 1 Deuterium canister | 1 | 4000 Deuterium canister |
| `grow_food` | 0.05 Fertilizer | 1 Food crate | 1 | 4000 Food crate |
| `make_airburst_m` | 1 Steel plates, 3 Explosives | 100 Airburst Rounds M | 1 | 800 Airburst Rounds M |
| `make_airburst_s` | 1 Steel plates, 3 Explosives | 200 Airburst Rounds S | 1 | 1600 Airburst Rounds S |
| `make_electronics` | 2 Silicon, 1 Industrial acids | 8 Electronics | 1 | 256 Electronics |
| `make_explosives` | 2 Nitrates | 1 Explosives | 1 | 720 Explosives |
| `make_fertilizer` | 1 Nitrates | 1 Fertilizer | 1 | 480 Fertilizer |
| `make_missile_l` | 4 Steel plates, 4 Explosives, 2 Electronics | 12 Missile L | 2 | 96 Missile L |
| `make_missile_m` | 2 Steel plates, 2 Explosives, 1 Electronics | 20 Missile M | 1 | 160 Missile M |
| `make_missile_s` | 1 Steel plates, 1 Explosives, 1 Electronics | 40 Missile S | 1 | 320 Missile S |
| `make_rounds_m` | 1 Steel plates, 1 Explosives | 100 Solid Rounds M | 1 | 800 Solid Rounds M |
| `make_rounds_s` | 1 Steel plates, 1 Explosives | 200 Solid Rounds S | 1 | 1600 Solid Rounds S |
| `make_shell_l` | 4 Steel plates, 6 Explosives | 12 Explosive Shells L | 1 | 96 Explosive Shells L |
| `make_shell_m` | 2 Steel plates, 3 Explosives | 12 Explosive Shells M | 1 | 96 Explosive Shells M |
| `make_shell_s` | 1 Steel plates, 2 Explosives | 24 Explosive Shells S | 1 | 192 Explosive Shells S |
| `make_shot_l` | 4 Steel plates, 2 Explosives | 24 Scatter Shells L | 1 | 192 Scatter Shells L |
| `make_shot_m` | 2 Steel plates, 1 Explosives | 32 Scatter Shells M | 1 | 256 Scatter Shells M |
| `make_shot_s` | 1 Steel plates, 1 Explosives | 64 Scatter Shells S | 1 | 512 Scatter Shells S |
| `make_torp_l` | 8 Steel plates, 16 Explosives, 4 Electronics | 1 Torpedo L | 4 | 8 Torpedo L |
| `make_torp_m` | 6 Steel plates, 12 Explosives, 3 Electronics | 2 Torpedo M | 3 | 16 Torpedo M |
| `make_torp_s` | 4 Steel plates, 8 Explosives, 2 Electronics | 4 Torpedo S | 2 | 32 Torpedo S |
| `press_canisters` | 0.5 Iron ore | 1 Empty canister | 1 | 6000 Empty canister |
| `process_nitrates` | 1 Water ice | 1 Nitrates | 1 | 960 Nitrates |
| `produce_acids` | Local extraction | 1 Industrial acids | 1 | 128 Industrial acids |
| `produce_nitrates` | Local extraction | 1 Nitrates | 1 | 960 Nitrates |
| `refine_silicon` | Local extraction | 1 Silicon | 1 | 192 Silicon |
| `roll_steel` | 2 Iron ore | 1 Steel plates | 1 | 1200 Steel plates |
| `skim_deuterium` | 1 Empty canister | 1 Deuterium canister | 1 | 4000 Deuterium canister |
| `skim_hydrogen` | 1 Empty canister | 1 Hydrogen canister | 1 | 60 Hydrogen canister |

## Installed capacities

| Location | Installation | Policy | Capacity/hour | Recipes |
|---|---|---|---:|---|
| Ceres Dock (`station:belt_1`) | `crack_ice` | adaptive | 1200 | crack_ice |
| Ceres Dock (`station:belt_1`) | `press_canisters` | adaptive | 1200 | press_canisters |
| Ceres Dock (`station:belt_1`) | `process_nitrates` | adaptive | 80 | process_nitrates |
| MACK Industrial Works (`station:belt_2`) | `mack_assembly` | orders | 2 | assemble_mack_mustang, assemble_mack_burro, assemble_mack_longhorn |
| Asgard Station (`station:callisto_2`) | `chemicals` | profit | 160 | make_fertilizer, make_explosives |
| Jita Orbital Logistics (`station:earth_1`) | `electronics` | profit | 4 | make_electronics |
| Elysium (`station:earth_2`) | `farm` | fixed | 960 | grow_food |
| Ferrous Collective Shipyard (`station:earth_3`) | `ferrous_assembly` | orders | 2 | assemble_ferrous_runner, assemble_ferrous_mule, assemble_ferrous_bison |
| Sinai Deep (`station:enceladus_1`) | `produce_nitrates` | adaptive | 120 | produce_nitrates |
| Galileo Regio (`station:ganymede_1`) | `produce_nitrates` | adaptive | 240 | produce_nitrates |
| Pele Works (`station:io_1`) | `acid_works` | fixed | 8 | produce_acids |
| Olympus (`station:jupiter_1`) | `skim_deuterium` | adaptive | 2400 | skim_deuterium |
| Olympus (`station:jupiter_1`) | `skim_hydrogen` | adaptive | 10 | skim_hydrogen |
| Kyrakos (`station:jupiter_2`) | `skim_deuterium` | adaptive | 2400 | skim_deuterium |
| Kyrakos (`station:jupiter_2`) | `skim_hydrogen` | adaptive | 10 | skim_hydrogen |
| Thule Prime (`station:luna_1`) | `electronics` | profit | 4 | make_electronics |
| The Apollo Heritage Foundation (`station:luna_2`) | `silicon_refinery` | fixed | 12 | refine_silicon |
| Red Furnace Shipyard (`station:mars_1`) | `intaki_assembly` | orders | 2 | assemble_intaki_wisp, assemble_intaki_praetor, assemble_intaki_archangel |
|  Zhongke Intelligent Manufacturing (`station:mars_2`) | `ammunition` | profit | 24 | make_rounds_s, make_rounds_m, make_airburst_s, make_airburst_m, make_shell_s, make_shell_m, make_shell_l, make_shot_s, make_shot_m, make_shot_l, make_missile_s, make_missile_m, make_missile_l, make_torp_s, make_torp_m, make_torp_l |
| Heaven-Ladder (`station:mars_3`) | `press_canisters` | adaptive | 12000 | press_canisters |
| Heaven-Ladder (`station:mars_3`) | `roll_steel` | adaptive | 480 | roll_steel |
| Heaven-Ladder (`station:mars_3`) | `shipworks` | fixed | 10 | assemble_hull_frames |
| Terminator Station (`station:mercury_1`) | `roll_steel` | adaptive | 480 | roll_steel |
| Terminator Station (`station:mercury_1`) | `shipworks` | fixed | 10 | assemble_hull_frames |
| Ceres Quarry Depot (`station:ceres_quarry_1`) | `roll_steel` | adaptive | 120 | roll_steel |
| Ceres Quarry Depot (`station:ceres_quarry_1`) | `shipworks` | fixed | 3 | assemble_hull_frames |
| Quarry Ore Depot (`station:quarry_1`) | `roll_steel` | adaptive | 120 | roll_steel |
| Quarry Ore Depot (`station:quarry_1`) | `shipworks` | fixed | 3 | assemble_hull_frames |
| Lumen Fabrication (`station:ring_2`) | `electronics` | profit | 12 | make_electronics |
| Valhalla Port (`station:callisto_1`) | `farm` | fixed | 640 | grow_food |
| UAE-9 (`station:titania_1`) | `process_nitrates` | adaptive | 80 | process_nitrates |
| UAE-9 (`station:titania_1`) | `chemicals` | profit | 160 | make_fertilizer, make_explosives |
| Uruk Station (`station:ganymede_2`) | `make_medical` | adaptive | 8 | make_medical |
| Gilgal Arsenal (`station:titan_3`) | `launchers_works` | profit | 2 | missile launchers S/M/L |
| The Star-Breaking Mine (`station:phobos_1`) | `guns_works` | profit | 2 | guns and artillery S/M/L |
| Ashgrove Drone Foundry (`station:earth_4`) | `bays_works` | profit | 2 | drone bays S/M/L |
| Loki Laboratory (`station:io_2`) | `lasers_works` | profit | 2 | beam and pulse lasers S/M/L |
| Ceres Dock (`station:belt_1`) | `drills_works` | profit | 2 | drills S/M/L |
| UAE-7 (`station:uranus_2`), Brute Industries Shipyard (`station:mercury_3`) | `engines_works` | profit | 1 each | engines S/M/L |
| Ceres Dock (`station:belt_1`), Abaddon (`station:titan_2`) | `reactors_works` | profit | 1 each | reactors S/M/L |
| Lumen Fabrication (`station:ring_2`), Pele Works (`station:io_1`) | `coil_works` | profit | 8 each | make_superconducting_coils |
| Pele Works (`station:io_1`), Haephestus Logistics (`station:mercury_2`) | `ceramic_works` | profit | 8 each | make_thermal_ceramics |
| Ceres Quarry Depot (`station:ceres_quarry_1`), Quarry Ore Depot (`station:quarry_1`) | `metal_extraction` | fixed | 24 each | extract_heavy_metals |
| Terminator Station (`station:mercury_1`) | `burn_hydrogen` | adaptive | -12 | burn_hydrogen |
| Terminator Station (`station:mercury_1`) | `silicon_refinery` | fixed | 12 | refine_silicon |
| Haephestus Logistics (`station:mercury_2`) | `burn_hydrogen` | adaptive | -12 | burn_hydrogen |
| Brute Industries Shipyard (`station:mercury_3`) | `brute_assembly` | orders | 2 | assemble_brute_runt, assemble_brute_anvil, assemble_brute_nautilus |
| Zebulun's Bounty (`station:saturn_1`) | `skim_hydrogen` | adaptive | 10 | skim_hydrogen |
| Shiloh (`station:saturn_2`) | `skim_hydrogen` | adaptive | 10 | skim_hydrogen |
| Ephraim's Bounty (`station:titan_1`) | `farm` | fixed | 960 | grow_food |
| Ephraim's Bounty (`station:titan_1`) | `produce_nitrates` | adaptive | 120 | produce_nitrates |
| Abaddon (`station:titan_2`) | `chemicals` | profit | 160 | make_fertilizer, make_explosives |
| UAE-4 (`station:uranus_1`) | `skim_deuterium` | adaptive | 2400 | skim_deuterium |
| UAE-4 (`station:uranus_1`) | `skim_hydrogen` | adaptive | 6 | skim_hydrogen |
| UAE-7 (`station:uranus_2`) | `skim_deuterium` | adaptive | 2400 | skim_deuterium |
| UAE-7 (`station:uranus_2`) | `skim_hydrogen` | adaptive | 6 | skim_hydrogen |
| Hub Station (`station:venus_1`) | `acid_works` | fixed | 8 | produce_acids |
| Hub Station (`station:venus_1`) | `burn_hydrogen` | adaptive | -16 | burn_hydrogen |
| Cloudline Station (`station:venus_2`) | `burn_hydrogen` | adaptive | -16 | burn_hydrogen |
| Cloudline Station (`station:venus_2`) | `farm` | fixed | 640 | grow_food |

Negative capacity entries are consumption, not manufacturing output. Food is also consumed separately at every inhabited station; repairs, rearming and fuel sales are event-driven consumers.

Finished ships include the dealership-selected trim, paint and fitted modules. Modules are not yet separately consumed by ship assembly. Opening dealer inventory is seeded world stock; subsequent manufactured ships require recipe inputs and processing time. Output requires a real free bay or berth within the sales-lot limit. Dealers cannot occupy the bottom quarter of the hangar or the two largest exterior berths, which remain available to guests. Blocked output consumes no frames and banks no replacement work.


## Ship modules

Every module except utility pods is manufactured (`data/industry.lua` `D.moduleLines`). Each faction makes one weapon line: the Diwan launchers, Zhuhai guns and artillery, the Estates drone bays, Jove lasers, Ceres drills. Engines and reactors are built at two works each from superconducting coils (heavy metals and electronics) and thermal ceramics (silicon and acids), each made at two stations; reactors also take one deuterium canister. Heavy metals are extracted at the two belt quarry depots.

Inputs follow each module's mass and price: one steel plate per 4 t, one electronics per 2,500 CR (engines and reactors take coils in place of part of it), and one processing unit per 10,000 CR, half a unit at least. A works stores four of each module.

A station whose market data lists a module keeps that many on its shelf as a reserve target (`reserve.service = 'listed'`, `src/reserves.lua`), filled by freight from the works instead of the timed restock. Faction pilots lean towards their faction's weapon line when refitting and their faction's makers' hulls when arriving (`src/faction_gear.lua`). Ships still roll out of the yards with modules fitted; assembly doesn't consume modules.
