-- World authoring: stable station identities and navigation topology.
-- Station designs/services live in data/stations/<id>.lua. Special construction stays
-- in its existing adapter; ordinary layout changes belong here.
local W={}
local T_SHOALS=math.pi*2/1800   -- rad/s: the Shoals' stations lap their centre every 30 min
W.stations = {

	-- Planetary industry (refining, acids, nitrates, ocean water) ships up to
	-- each system's logistics hub by rocket: it appears there, not at the
	-- station that used to make it. Every system has one (the Ring's is Providence
	-- itself; small moons go through their customs depot instead), so every cross-system trade goes hub to hub.
	-- surface=true marks a facility down on the planet or moon.
	mercury = {
		{ id = "station:mercury_1", facilities={roll_steel={capacity=480},shipworks={capacity=10}}, services = { "market", "shipyard", "hangar" }, spin = 0.05, phase = -0.8, primary = true, name = "Terminator Station", layout = "estates_palace" },
		{ id = "station:mercury_2", facilities={ceramic_works={capacity=8},silicon_refinery={capacity=24,surface=true}}, marketId = "market:mercury_2", services = { "market", "shipyard", "hangar" }, spin = -0.05, phase = 1.2943951023931953, name = "Haephestus Logistics", layout = "customs_1", hub = true  },
		{ id = "station:mercury_3", facilities={engines_works={capacity=1},brute_assembly={capacity=2}}, marketId = "market:mercury_3", services = { "market", "shipyard", "hangar", "repair" }, spin = 0.03, phase = 3.3887902047863905, name = "Brute Industries Shipyard", layout = "shipyard_1" },
		{ id = "station:mercury_4", facilities={bays_works={capacity=2},utility_works={capacity=2},drones={capacity=8}}, marketId = "market:mercury_4", services = { "market", "hangar", "repair" }, spin = 0.04, phase = 4.45, name = "Ashgrove Drone Foundry", layout = "estates_manor" },
		{ id = "station:mercury_5", marketId = "market:mercury_5", services = { "market", "hangar" }, spin = 0.04, name = "Daybreak Commons", layout = "estates_chandelier",
		  residential = { population = 3000, homes = 4, routes = {
			{ to = "station:mercury_1", kind = "work", weight = 3 },
			{ to = "station:mercury_2", kind = "work", weight = 2 },
			{ to = "station:mercury_3", kind = "work", weight = 2 },
			{ to = "station:mercury_4", kind = "work", weight = 3 } } } },
	},
	venus = {
		{ id = "station:venus_1", services = { "market", "hangar", "repair" }, spin = 0.05, phase = -0.8, primary = true, marketId = "market:venus_1", name = "Hub Station",
		  residential = { population = 3000, homes = 7, routes = {
			{ to = "station:venus_2", kind = "work", weight = 3 },
			{ to = "station:venus_3", kind = "work", weight = 1 },
			{ to = "station:venus_4", kind = "work", weight = 2 } } } },
		{ id = "station:venus_2", food = {use=64}, facilities={burn_hydrogen={capacity=-120},terraform_water={name="Terraforming water intake",capacity=-480},farm={capacity=640}}, marketId = "market:venus_2", services = { "market", "hangar" }, spin = -0.05, phase = 2.3415926535897933, name = "Cloudline Station", layout = "estates_palace"   },
		{ id = "station:venus_3", facilities={amw_assembly={capacity=2}}, marketId = "market:venus_3", services = { "market", "shipyard", "hangar", "repair" }, spin = 0.03, phase = 4.4, name = "Angelmaschinenwerft Atelier", layout = "shipyard_1" },
		{ id = "station:venus_4", orbit = 2, facilities={acid_works={capacity=72,surface=true}}, services = { "market", "hangar", "repair" }, spin = -0.04, phase = 1.0, marketId = "market:venus_4", name = "Venus Logistics", layout = "customs_1", hub = true },
	},
	earth = {
		{ id = "station:earth_1", food = {use=96}, facilities={silicon_refinery={capacity=24,surface=true},make_medical={capacity=8},surface_food={name="Surface food terminal",capacity=960,surface=true}}, services = { "market", "shipyard", "hangar" }, spin = 0.05, phase = -0.8, primary = true, marketId = "market:earth_1", name = "Jita Orbital Logistics", layout = "customs_1", hub = true },
		{ id = "station:earth_2", uses = { fence = true }, facilities={use_fentanyl={capacity=-6},use_moss={capacity=-6}}, food = {use=64}, services = { "market", "hangar" }, marketId = "market:earth_2", spin = -0.05, phase = 1.2943951023931953, name = "Elysium", layout = "estates_palace",
		  residential = { population = 5000, homes = 8, routes = {
			{ to = "station:earth_1", kind = "work", weight = 4 },
			{ to = "station:earth_3", kind = "work", weight = 3 },
			{ to = "station:earth_5", kind = "work", weight = 1 } } } },
		{ id = "station:earth_3", facilities={ferrous_assembly={capacity=2}}, marketId = "market:earth_3", services = { "market", "shipyard", "hangar", "repair" }, spin = 0.03, phase = 3.3887902047863905, name = "Ferrous Collective Shipyard", layout = "shipyard_1" },
		-- the Estates' military yards: builds its police and courier hulls (data/industry.lua serviceLineups)
		{ id = "station:earth_5", orbit = 2, uses = { military = true }, facilities={estates_assembly={capacity=2}}, marketId = "market:earth_5", services = { "market", "hangar", "repair" }, spin = 0.03, phase = 2.35, name = "Estates Naval Yards", layout = "shipyard_2" },
	},
	
	luna = {
		{ id = "station:luna_1", facilities={silicon_refinery={capacity=128,surface=true},electronics={capacity=48},coil_works={capacity=8}}, services = { "market", "shipyard", "hangar" }, spin = 0.05, phase = -0.8, primary = true, marketId = "market:luna_1", name = "Thule Prime", layout = "estates_palace"   },
		{ id = "station:luna_2", services = { "market", "shipyard", "hangar" }, marketId = "market:luna_2", spin = -0.05, phase = 2.3415926535897933, name = "The Apollo Heritage Foundation", layout = "estates_palace"   },
		-- residential (src/passengers.lua): housing only, no industry or ship sales
		{ id = "station:luna_3", marketId = "market:luna_3", services = { "market", "hangar" }, spin = 0.04, phase = 3.9, name = "Tranquility Commons", layout = "estates_quadrangle",
		  residential = { population = 3000, homes = 8, routes = {
			{ to = "station:luna_1", kind = "work", weight = 3 },
			{ to = "station:luna_2", kind = "work", weight = 1 },
			{ to = "station:earth_1", kind = "work", weight = 2 },
			{ to = "station:mars_5", kind = "visit", weight = 1 } } } },
		{ id = "station:luna_4", name = "Kepler Avionics Works", layout = "utility_exchange",
		  marketId = "market:luna_4", services = { "market", "hangar" }, phase = 1.55, spin = -0.03, facilities = {
			guidance_works = { type = "avionics_works", name = "Missile guidance works", capacity = 1, recipes = { "make_guidance_computer" } },
			uplink_works = { type = "avionics_works", name = "Drone uplink works", capacity = 1, recipes = { "make_drone_uplink" } },
		  } },
	},
	mars = {
		{ id = "station:mars_1", facilities={redfu_assembly={capacity=2}}, services = { "market", "shipyard", "hangar", "repair" }, spin = 0.05, phase = -0.8, primary = true, layout = "shipyard_1", marketId = "market:mars_1", name = "Red Furnace Shipyard" },
		{ id = "station:mars_2", facilities={intaki_assembly={capacity=2}}, services = { "market", "shipyard", "hangar", "repair" }, marketId = "market:mars_2", spin = -0.05, phase = 2.3415926535897933, layout = "shipyard_1",   name = "Zhongke Intelligent Manufacturing" },
		-- Zhuhai's logistics hub: Mars's production is on the Heaven-Ladder,
		-- the two orbital stations are shipyards, and freight meets here
		{ id = "station:mars_4", services = { "market", "hangar", "repair" }, spin = 0.04, phase = 4.45, marketId = "market:mars_4", name = "Zhuhai Logistics", layout = "customs_1", hub = true },
		-- residential: Zhuhai's workforce lives here, not on the shipyards
		{ id = "station:mars_5", facilities={use_amphetamines={capacity=-24},use_moss={capacity=-6}}, marketId = "market:mars_5", services = { "market", "hangar" }, spin = -0.03, phase = 1.0, name = "Hakka Tulou Habitat", layout = "zhuhai_tulou",
		  residential = { population = 4000, homes = 10, routes = {
			{ to = "station:mars_3", kind = "work", weight = 4 },
			{ to = "station:mars_1", kind = "work", weight = 3 },
			{ to = "station:mars_2", kind = "work", weight = 3 },
			{ to = "station:mars_4", kind = "work", weight = 1 },
			{ to = "station:ring_1", kind = "visit", weight = 1 },
			{ to = "station:luna_3", kind = "visit", weight = 1 } } } },
	},
	phobos = {
		{ id = "station:phobos_1", marketId = "market:mars_mine", services = { "market", "hangar", "repair" }, primary = true, name = "The Star-Breaking Mine", adapter = "surface_mine", layout = "zhuhai_strip_mine" },
	},
	deimos = {
		{ id = "station:deimos_1", marketId = "market:mars_mine", services = { "market", "hangar", "repair" }, primary = true, name = "The Moon-Swallowing Yard", adapter = "surface_mine", layout = "zhuhai_strip_mine" },
	},
	
	belt = {
		{ id = "station:belt_1", facilities={ice_wells={capacity=900,surface=true},drills_works={capacity=2},reactors_works={capacity=1},press_canisters={capacity=1200},crack_ice={capacity=1200,surface=true},water_melter={capacity=320},process_nitrates={capacity=80}}, services = { "market", "hangar", "repair" }, spin = 0.05, phase = -0.8, primary = true, marketId = "market:belt_1", name = "Ceres Dock" },
		{ id = "station:belt_2", facilities={mack_assembly={capacity=2}}, services = { "market", "shipyard", "hangar" }, spin = -0.05, phase = 2.3415926535897933, marketId = "market:belt_2", name = "MACK Industrial Works", layout = "shipyard_2" },
		{ id = "station:belt_3", services = { "market", "hangar", "repair" }, spin = 0.04, phase = 4.45, marketId = "market:belt_3", name = "Ceres Logistics", layout = "customs_1", hub = true },
	},
	jupiter = {
		{ id = "station:jupiter_1", facilities={skim_deuterium={capacity=4800},skim_hydrogen={capacity=20}}, services = { "market", "shipyard", "hangar" }, primary = true, marketId = "market:jupiter_1", name = "Olympus", adapter = "cloud" },
		{ id = "station:jupiter_2", uses = { military = true },
		  services = { "shipyard", "hangar" }, spin = 0.05, phase = -0.8, marketId = "market:jupiter_2", name = "Kyrakos", layout = "jovian_shipyard" },
		{ id = "station:jupiter_3", facilities={use_medical={capacity=-4}}, services = { "market", "hangar", "repair" }, spin = -0.04, phase = 2.3415926535897933, marketId = "market:jupiter_3", name = "Jovian Logistics", layout = "customs_1", hub = true },
				
	},

	io = {
		{ id = "station:io_1", facilities={ceramic_works={capacity=8},coil_works={capacity=8},acid_works={capacity=16,surface=true}}, services = { "market", "hangar", "repair" }, spin = 0.05, phase = -0.8, primary = true, marketId = "market:io_1", name = "Pele Works", layout = "jovian_works" },
		{ id = "station:io_2", facilities={lasers_works={capacity=2}}, services = { "market", "hangar", "repair" }, marketId = "market:io_2", spin = -0.05, phase = 2.3415926535897933, name = "Loki Laboratory", layout = "jovian_observatory" },
		{ id = "station:io_3", facilities = { iron_works = { name = "Io iron pits", capacity = 240, surface = true } }, services = { "market", "hangar", "repair" }, spin = 0.04, phase = 4.45, marketId = "market:io_3", name = "Io Customs", layout = "customs_1", customs = true },
	},
	europa = {
		{ id = "station:europa_1", facilities={water_wells={capacity=360,surface=true},alkali_works={capacity=24,surface=true}}, services = { "market", "hangar", "repair" }, spin = 0.05, phase = -0.8, primary = true, marketId = "market:europa_1", name = "Conamara Station", layout = "jovian_stack" },
		{ id = "station:europa_2", facilities={ice_wells={capacity=600,surface=true},water_melter={capacity=300}}, services = { "market", "hangar", "repair" }, marketId = "market:europa_2", spin = -0.05, phase = 2.3415926535897933, name = "Pwyll Station", layout = "jovian_works" },
		{ id = "station:europa_3", services = { "market", "hangar", "repair" }, spin = 0.04, phase = 4.45, marketId = "market:europa_3", name = "Europa Customs", layout = "customs_1", customs = true },
	},
	ganymede = {
		{ id = "station:ganymede_1", facilities={produce_nitrates={capacity=340,surface=true}}, services = { "market", "hangar", "repair" }, spin = 0.05, phase = -0.8, primary = true, marketId = "market:ganymede_1", name = "Galileo Regio", layout = "jovian_works" },
		{ id = "station:ganymede_2", facilities={make_medical={capacity=12}}, services = { "market", "hangar", "repair" }, marketId = "market:ganymede_2", spin = -0.05, phase = 2.3415926535897933, name = "Uruk Station", layout = "jovian_dingus" },
		{ id = "station:ganymede_3", services = { "market", "hangar", "repair" }, spin = 0.04, phase = 4.45, marketId = "market:ganymede_3", name = "Ganymede Customs", layout = "customs_1", customs = true },
		{ id = "station:ganymede_4", name = "Ganymede Canister Works", layout = "jovian_works", services = { "market", "hangar" },
		  phase = 1.55, spin = -0.03, facilities = { press_canisters = { capacity = 2000 } } },
		{ id = "station:ganymede_5", name = "Ganymede Outfitting Works", layout = "jovian_works",
		  marketId = "market:ganymede_5", services = { "market", "hangar" }, phase = 3.15, spin = 0.03, facilities = {
			cargo_pod_works = { type = "pods_works", name = "Cargo pod works", capacity = 1, recipes = { "make_hold_pod_s" } },
			climate_pod_works = { type = "pods_works", name = "Climate pod works", capacity = 1, recipes = { "make_climate_pod_s" } },
		  } },
	},
	callisto = {
		{ id = "station:callisto_1", food = {use=64}, facilities={farm={capacity=640},use_fentanyl={capacity=-18},use_amphetamines={capacity=-4},use_moss={capacity=-8}}, services = { "market", "hangar", "repair" }, spin = 0.05, phase = -0.8, primary = true, marketId = "market:callisto_1", name = "Valhalla Port", layout = "jovian_freeport" },
		{ id = "station:callisto_2", facilities={chemicals_fertilizer={type='chemicals',name='Fertilizer plant',recipes={'make_fertilizer'},capacity=160},chemicals_explosives={type='chemicals',name='Explosives plant',recipes={'make_explosives'},capacity=160}}, services = { "market", "hangar", "repair" }, marketId = "market:callisto_2", spin = -0.05, phase = 2.3415926535897933, name = "Asgard Station", layout = "jovian_works" },
		{ id = "station:callisto_3", services = { "market", "hangar", "repair" }, spin = 0.04, phase = 4.45, marketId = "market:callisto_3", name = "Callisto Customs", layout = "customs_1", customs = true },
	},
	saturn = {
		{ id = "station:saturn_1", facilities={farm={capacity=240}}, marketId = "market:saturn_1", services = { "market", "hangar", "repair" }, spin = 0.05, phase = -0.8, primary = true, name = "Zebulun's Bounty", layout = "diwan_court"   },
		{ id = "station:saturn_2", marketId = "market:saturn_2", services = { "market", "hangar", "repair" }, spin = -0.05, phase = 2.3415926535897933, name = "Shiloh", layout = "diwan_quarter",
		  residential = { population = 3000, homes = 6, routes = {
			{ to = "station:saturn_1", kind = "work", weight = 3 },
			{ to = "station:saturn_3", kind = "work", weight = 3 },
			{ to = "station:saturn_4", kind = "work", weight = 1 } } } },
		-- Atmospheric collectors deliver Saturn's hydrogen to the logistics hub.
		{ id = "station:saturn_3", facilities={skim_hydrogen={capacity=20,surface=true}}, services = { "market", "hangar", "repair" }, spin = 0.04, phase = 4.45, marketId = "market:saturn_3", name = "Saturn Logistics", layout = "customs_1", hub = true },
		-- the Diwan's military yards
		{ id = "station:saturn_4", orbit = 2, uses = { military = true }, facilities={diwan_assembly={capacity=2}}, marketId = "market:saturn_4", services = { "market", "hangar", "repair" }, spin = 0.03, phase = 0.9, name = "Diwan Military Yards", layout = "diwan_works" },
	},
	enceladus = {
		{ id = "station:enceladus_1", facilities={produce_nitrates={capacity=340,surface=true}}, services = { "market", "shipyard", "hangar", "repair" }, spin = 0.05, phase = -0.8, primary = true, marketId = "market:enceladus_1", name = "Sinai Deep" , layout = "diwan_hall"   },
		{ id = "station:enceladus_2", facilities={alkali_works={capacity=16,surface=true},ice_wells={capacity=600,surface=true},water_wells={capacity=320,surface=true},water_melter={capacity=260}}, services = { "market", "shipyard", "hangar", "repair" }, marketId = "market:enceladus_2", spin = -0.05, phase = 2.3415926535897933, name = "Rephidim", layout = "diwan_terminal"   },
	},
	titan = {
		{ id = "station:titan_1", food = {use=64}, facilities={use_medical={capacity=-4},produce_nitrates={capacity=340,surface=true},farm={capacity=960}}, services = { "market", "shipyard", "hangar", "repair" }, spin = 0.05, phase = -0.8, primary = true, marketId = "market:titan_1", name = "Ephraim's Bounty", layout = "diwan_court"   },
		{ id = "station:titan_2", facilities={reactors_works={capacity=1},chemicals_fertilizer={type='chemicals',name='Fertilizer plant',recipes={'make_fertilizer'},capacity=320},chemicals_explosives={type='chemicals',name='Explosives plant',recipes={'make_explosives'},capacity=320},pyrotechnics={capacity=24}}, services = { "market", "shipyard", "hangar" }, marketId = "market:titan_2", spin = -0.05, phase = 2.3415926535897933, name = "Abaddon", layout = "diwan_works"   },
		{ id = "station:titan_3", facilities={launchers_works={capacity=2},guided_missiles={type='guided_munitions',name='Missile line',recipes={'make_missile_s','make_missile_m','make_missile_l'},capacity=48},guided_torpedoes={type='guided_munitions',name='Torpedo line',recipes={'make_torp_s','make_torp_m','make_torp_l'},capacity=48}}, marketId = "market:titan_3", services = { "market", "hangar", "repair" }, spin = 0.04, phase = 4.45, name = "Gilgal Arsenal", layout = "diwan_works" },
	},
	titania = {
		{ id = "station:titania_1", facilities={ice_wells={capacity=600,surface=true},process_nitrates={capacity=80},chemicals_fertilizer={type='chemicals',name='Fertilizer plant',recipes={'make_fertilizer'},capacity=160},chemicals_explosives={type='chemicals',name='Explosives plant',recipes={'make_explosives'},capacity=160}}, services = { "market", "hangar", "repair" }, spin = 0.05, phase = -0.8, primary = true, marketId = "market:titania_1", name = "UAE-9" },
	},
	uranus = {
		{ id = "station:uranus_1", facilities={skim_deuterium={capacity=4800},skim_hydrogen={capacity=200}}, services = { "market", "shipyard", "hangar" }, primary = true, name = "UAE-4", marketId = "market:uranus_1", adapter = "cloud" },
		{ id = "station:uranus_2", facilities={engines_works={capacity=1}}, services = { "market", "shipyard", "hangar" }, spin = 0.05, phase = -0.8, primary = true, marketId = "market:uranus_2", name = "UAE-7", layout = "caliphate_chemworks" },
		{ id = "station:uranus_3", services = { "market", "hangar", "repair" }, spin = -0.04, phase = 2.3415926535897933, marketId = "market:uranus_3", name = "Uranian Logistics", layout = "customs_1", hub = true },
		},
	triton = {
		{ id = "station:triton_1", uses = { fence = true }, facilities={use_moss={capacity=-4}}, services = { "market", "hangar", "repair" }, marketId = "market:triton_1", spin = -0.05, phase = 2.3415926535897933, name = "Neptune's Bounty"   },
		{ id = "station:triton_3", services = { "market", "hangar", "repair" }, spin = 0.04, phase = -0.8, marketId = "market:triton_3", name = "Triton Logistics", layout = "customs_1", hub = true },
	
	},
	-- Milliways moved off Pluto onto its own dark grid (Fields.milliways,
	-- src/dark.lua). Same station id, so saves and reputation carry over.
	-- It is the dark network's logistics hub (src/economy.lua hubRoot): every
	-- dark grid trades with the white systems only through it.
	milliways = {
		{ id = "station:pluto_1", services = { "market", "shipyard", "hangar", "repair" }, spin = 0.05, primary = true, uses = { pirateBase = true }, layout = "jovian_kink", marketId = "market:pluto_1", name = "Milliways Freeport", hub = true },
	},
	ring = {
		{ id = "station:ring_1", services = { "market", "shipyard", "hangar", "repair" }, spin = 0.04, primary = true, name = "Providence", marketId = "market:ring_1", layout = "ring_horseshoe",
		  -- the big ring is a town as well as a market (src/passengers.lua)
		  residential = { population = 5000, homes = 12, routes = {
			{ to = "station:ring_2", kind = "work", weight = 3 },
			{ to = "station:mars_5", kind = "visit", weight = 1 } } } },
		-- An electronics fab off Providence: silicon and acids in, boards out.
		{ id = "station:ring_2", position = { x = 7000, y = -2500 }, facilities={coil_works={capacity=8},electronics={capacity=12}}, services = { "market", "hangar", "repair" }, spin = 0.03, marketId = "market:ring_2", name = "Lumen Fabrication", layout = "utility_exchange" },
	},
	-- Dark stations (src/dark.lua): pirate-run, off the public charts.
	-- The Shoals has no planet: its three stations slowly circle their common
	-- centre along the cleared channel through the rock (Fields.shoalsShape),
	-- 13,000 px out and 120 degrees apart (~22,500 px from each other), one
	-- lap every 30 minutes.
	shoals = {
		{ id = "station:shoals_1", position = { x = 0, y = -13000, rate = T_SHOALS }, facilities={roll_steel={capacity=240},press_canisters={capacity=800},water_melter={capacity=240}}, services = { "market", "hangar", "repair" }, spin = 0, primary = true, marketId = "market:shoals_1", name = "Slag Harbor", layout = "jovian_works" },
		{ id = "station:shoals_2", facilities={drug_lab={name='Cartel lab',capacity=20},ammo_solid={type='ammunition',name='Solid rounds line',recipes={'make_rounds_s','make_rounds_m'},capacity=12},ammo_airburst={type='ammunition',name='Airburst rounds line',recipes={'make_airburst_s','make_airburst_m'},capacity=12},ammo_shells={type='ammunition',name='Shell line',recipes={'make_shell_s','make_shell_m','make_shell_l'},capacity=12},ammo_shot={type='ammunition',name='Shot line',recipes={'make_shot_s','make_shot_m','make_shot_l'},capacity=12},ammo_patch={type='ammunition',name='Patch kit line',recipes={'make_patch_kit'},capacity=12},process_nitrates={capacity=120},chemicals_fertilizer={type='chemicals',name='Fertilizer plant',recipes={'make_fertilizer'},capacity=160},chemicals_explosives={type='chemicals',name='Explosives plant',recipes={'make_explosives'},capacity=160}}, services = { "market", "hangar", "repair" }, position = { x = 11258, y = 6500, rate = T_SHOALS }, spin = 0.04, marketId = "market:shoals_2", name = "Cinder Works", layout = "caliphate_chemworks" },
		{ id = "station:shoals_3", services = { "market", "shipyard", "hangar", "repair" }, position = { x = -11258, y = 6500, rate = T_SHOALS }, spin = -0.05, uses = { pirateBase = true }, marketId = "market:shoals_3", name = "Shoals Freeport", layout = "jovian_freeport" },
	},
	-- Antichthon: the pirates' hydroponics farm, on Earth's orbit behind the Sun.
	antichthon = {
		{ id = "station:antichthon_1", food = {use=32}, facilities={farm={capacity=240},moss_beds={name="Moss beds",capacity=12}}, services = { "market", "hangar", "repair" }, spin = 0.04, primary = true, marketId = "market:antichthon_1", name = "Antichthon Gardens", layout = "estates_manor" },
	},
	cordelia = {
		{ id = "station:cordelia_1", services = { "market", "shipyard", "hangar", "repair" }, spin = 0.05, primary = true, uses = { pirateBase = true }, marketId = "market:cordelia_1", name = "Cordelia Freeport", layout = "jovian_spur" },
	},
	ceres_quarry = {
		{ id = "station:ceres_quarry_1", facilities={metal_extraction={capacity=24},roll_steel={capacity=120},shipworks={capacity=3}}, services = { "market", "shipyard", "hangar", "repair" }, spin = 0, primary = true, marketId = "market:ceres_quarry_1", name = "Ceres Quarry Depot", layout = "jovian_works" },
	},
	quarry = {
		{ id = "station:quarry_1", facilities={metal_extraction={capacity=24},roll_steel={capacity=120},shipworks={capacity=3}}, services = { "market", "shipyard", "hangar", "repair" }, spin = 0, primary = true, marketId = "market:quarry_1", name = "Quarry Ore Depot", layout = "jovian_works" },
	},
	station = {
		-- Debug instance only (Fields.station): no lanes, no market, nothing
		-- eaten or drunk, no work, so the economy never counts it. Not Venus's
		-- Hub Station (station:venus_1).
		{ id = "station:station_1", services = { "shipyard", "hangar" }, spin = 0.04, phase = -0.8, primary = true, name = "Test Hub", wheel = { 1400, 160 },
		  food = { use = 0 }, water = { use = 0 }, uses = { trade = false, mining = false, patrol = false } },
	},

}
-- IDs are "<home area>_<n>" slugs, assigned once. They never change when a
-- station is renamed, retuned or moved; markets reuse their station's slug.
W.defaults={marketId='market:general',waterUse=16,foodUse=32,foodReserveHours=4,
 -- drugs every crewed market station takes, per food crate it eats an hour
 -- (src/crisis.lua: stims and fentanyl at their crisis peak, moss at its
 -- steady rate). An entry's own use_* facility overrides; drugs = false
 -- opts it out. The cartel's own areas don't buy their product.
 drugUse={use_amphetamines=.02,use_fentanyl=.02,use_moss=.01},
 drugFreeAreas={milliways=true,shoals=true,antichthon=true,cordelia=true,station=true}}
W.specials={heavenLadder={area='mars',id='station:mars_3',name='Heaven-Ladder',marketId='market:mars_3',food={use=96},facilities={ammo_solid={type='ammunition',name='Solid rounds line',recipes={'make_rounds_s','make_rounds_m'},capacity=24},ammo_airburst={type='ammunition',name='Airburst rounds line',recipes={'make_airburst_s','make_airburst_m'},capacity=24},ammo_shells={type='ammunition',name='Shell line',recipes={'make_shell_s','make_shell_m','make_shell_l'},capacity=24},ammo_shot={type='ammunition',name='Shot line',recipes={'make_shot_s','make_shot_m','make_shot_l'},capacity=24},ammo_patch={type='ammunition',name='Patch kit line',recipes={'make_patch_kit'},capacity=24},guns_works={capacity=2},press_canisters={capacity=10000},roll_steel={capacity=480},shipworks={capacity=10}},
 access={'station:mars_3','access:mars_3_2','access:mars_3_3','access:mars_3_4'}}}
-- Read-only compatibility aliases for saves from before independent station IDs.
W.aliases={
 ["station:earth_4"]="station:mercury_4",
 ["market:earth_4"]="market:mercury_4",
 ["phobos/strip_mine"]="station:phobos_1",
 ["deimos/strip_mine"]="station:deimos_1",
 ["mercury/terminator_station"]="station:mercury_1",
 ["mercury/dawnline_station"]="station:mercury_2",
 ["venus/hub_station"]="station:venus_1",
 ["venus/cloudline_station"]="station:venus_2",
 ["earth/orbital_one"]="station:earth_1",
 ["earth/orbital_two"]="station:earth_2",
 ["mars/station_alpha"]="station:mars_1",
 ["mars/station_beta"]="station:mars_2",
 ["belt/ceres_dock"]="station:belt_1",
 ["belt/piazzi_station"]="station:belt_2",
 ["jupiter/olympus"]="station:jupiter_1",
 ["saturn/cassini_gate"]="station:saturn_1",
 ["saturn/enceladus_station"]="station:saturn_2",
 ["uranus/herschel"]="station:uranus_1",
 ["luna/tranquility_dock"]="station:luna_1",
 ["luna/shackleton_station"]="station:luna_2",
 ["io/pele_works"]="station:io_1",
 ["io/loki_laboratory"]="station:io_2",
 ["europa/conamara_station"]="station:europa_1",
 ["europa/pwyll_station"]="station:europa_2",
 ["ganymede/galileo_regio"]="station:ganymede_1",
 ["ganymede/uruk_station"]="station:ganymede_2",
 ["callisto/valhalla_port"]="station:callisto_1",
 ["callisto/asgard_station"]="station:callisto_2",
 ["enceladus/tiger_stripe_laboratory"]="station:enceladus_1",
 ["enceladus/south_pole_port"]="station:enceladus_2",
 ["titan/kraken_station"]="station:titan_1",
 ["titan/huygens_station"]="station:titan_2",
 ["titania/gertrude_port"]="station:titania_1",
 ["titania/messina_research_station"]="station:titania_2",
 ["triton/cipango_station"]="station:triton_1",
 ["triton/voyager_station"]="station:triton_2",
 ["pluto/tombaugh_station"]="station:pluto_1",
 ["pluto/sputnik_port"]="station:pluto_2",
 ["ring/ring_station"]="station:ring_1",
 ["station/hub_station"]="station:station_1",
 ["mars/heaven_ladder"]="station:mars_3",
 ["mars/heaven_ladder_2"]="access:mars_3_2",
 ["mars/heaven_ladder_3"]="access:mars_3_3",
 ["mars/heaven_ladder_4"]="access:mars_3_4",
 -- Numbered ids from before location-based slugs.
 ["access:001"]="access:mars_3_2",
 ["access:002"]="access:mars_3_3",
 ["access:003"]="access:mars_3_4",
 ["market:001"]="market:venus_1",
 ["market:002"]="market:mars_1",
 ["market:003"]="market:mars_3",
 ["market:004"]="market:mars_2",
 ["market:005"]="market:earth_1",
 ["market:006"]="market:earth_2",
 ["market:007"]="market:luna_1",
 ["market:008"]="market:luna_2",
 ["market:009"]="market:europa_1",
 ["market:010"]="market:europa_2",
 ["market:011"]="market:ganymede_1",
 ["market:012"]="market:ganymede_2",
 ["market:013"]="market:titan_1",
 ["market:014"]="market:titan_2",
 ["market:015"]="market:triton_1",
 ["market:016"]="market:triton_2",
 ["market:017"]="market:io_1",
 ["market:018"]="market:io_2",
 ["market:019"]="market:callisto_1",
 ["market:020"]="market:callisto_2",
 ["market:021"]="market:enceladus_1",
 ["market:022"]="market:enceladus_2",
 ["market:023"]="market:pluto_1",
 ["market:024"]="market:pluto_2",
 ["market:025"]="market:titania_1",
 ["market:026"]="market:titania_2",
 ["station:001"]="station:phobos_1",
 ["station:002"]="station:deimos_1",
 ["station:003"]="station:mercury_1",
 ["station:004"]="station:mercury_2",
 ["station:005"]="station:venus_1",
 ["station:006"]="station:venus_2",
 ["station:007"]="station:earth_1",
 ["station:008"]="station:earth_2",
 ["station:009"]="station:mars_1",
 ["station:010"]="station:mars_2",
 ["station:011"]="station:belt_1",
 ["station:012"]="station:belt_2",
 ["station:013"]="station:jupiter_1",
 ["station:014"]="station:saturn_1",
 ["station:015"]="station:saturn_2",
 ["station:016"]="station:uranus_1",
 ["station:017"]="station:luna_1",
 ["station:018"]="station:luna_2",
 ["station:019"]="station:io_1",
 ["station:020"]="station:io_2",
 ["station:021"]="station:europa_1",
 ["station:022"]="station:europa_2",
 ["station:023"]="station:ganymede_1",
 ["station:024"]="station:ganymede_2",
 ["station:025"]="station:callisto_1",
 ["station:026"]="station:callisto_2",
 ["station:027"]="station:enceladus_1",
 ["station:028"]="station:enceladus_2",
 ["station:029"]="station:titan_1",
 ["station:030"]="station:titan_2",
 ["station:031"]="station:titania_1",
 ["station:032"]="station:titania_2",
 ["station:033"]="station:triton_1",
 ["station:034"]="station:triton_2",
 ["station:035"]="station:pluto_1",
 ["station:036"]="station:pluto_2",
 ["station:037"]="station:ring_1",
 ["station:038"]="station:station_1",
 ["station:039"]="station:mars_3",
}

-- Every rotating region declares its actual buoy placements here. Optional
-- radius overrides the track; phase/heading/spin use radians. prop selects an
-- F2 prop ID; scale changes its visual size. A region-wide buoyProp or
-- defaults.buoyProp can supply the prop for entries without one.
-- A numeric buoys count is also accepted for evenly spaced generated rings.
W.navigation={
 mercury={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 venus={drivers=2,buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 earth={drivers=2,buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 mars={drivers=4,buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 belt={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 jupiter={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+1*math.pi*2/3},
  {id='trade_buoy_c', phase=-.8+math.pi/2+2*math.pi*2/3},
 }, corridor='buoys', population={hauler=0}},
 saturn={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 uranus={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+1*math.pi*2/3},
  {id='trade_buoy_c', phase=-.8+math.pi/2+2*math.pi*2/3},
 }, corridor='buoys', population={hauler=0}},
 neptune={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 luna={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 phobos={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+1*math.pi*2/4},
  {id='trade_buoy_c', phase=-.8+math.pi/2+2*math.pi*2/4},
  {id='trade_buoy_d', phase=-.8+math.pi/2+3*math.pi*2/4},
 }, corridor='buoys'},
 deimos={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+1*math.pi*2/4},
  {id='trade_buoy_c', phase=-.8+math.pi/2+2*math.pi*2/4},
  {id='trade_buoy_d', phase=-.8+math.pi/2+3*math.pi*2/4},
 }, corridor='buoys'},
 io={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 callisto={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 enceladus={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 pluto={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 europa={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 ganymede={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 titan={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 titania={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
 triton={buoys={
  {id='trade_buoy_a', phase=-.8+math.pi/2},
  {id='trade_buoy_b', phase=-.8+math.pi/2+math.pi},
 }},
}

-- Placement operations change this definition; WorldAuthoring applies/reloads it.
function W.find(id)
 for area,entries in pairs(W.stations) do
  for index,entry in ipairs(entries) do if entry.id==id then return entry,area,index end end
 end
 for _,entry in pairs(W.specials) do if entry.id==id then return entry,entry.area end end
end
function W.addStation(area,definition)
 assert(require('src.fields')[area],'unknown region '..tostring(area))
 local entry=require('src.persistence').copy(definition)
 if not entry.id then
  repeat entry.id=('station:%08x%08x'):format(love.math.random(0,2147483646),love.math.random(0,2147483646)) until not W.find(entry.id)
 end
 assert(not W.find(entry.id),'station id already exists: '..entry.id)
 assert(type(entry.name)=='string','station needs a name')
 if entry.spin==nil then entry.spin=.04 end
 if not entry.position and not entry.motion and not entry.phase then
  local phases={}
  for _,existing in ipairs(W.stations[area] or {}) do
   phases[#phases+1]=(existing.phase or 0)%(math.pi*2)
  end
  table.sort(phases);local gap,phase=-1,0
  for i,value in ipairs(phases) do
   local nextValue=phases[i%#phases+1]+(i==#phases and math.pi*2 or 0)
   if nextValue-value>gap then gap,phase=nextValue-value,(nextValue+value)/2 end
  end
  entry.phase=phase
 end
 W.stations[area]=W.stations[area] or {}
 table.insert(W.stations[area],entry)
 return entry.id
end
function W.moveStation(id,area,position)
 local entry,oldArea,index=W.find(id);assert(entry,'unknown station '..tostring(id))
 assert(index,'special station placement belongs to its construction adapter')
 assert(require('src.fields')[area],'unknown region '..tostring(area))
 table.remove(W.stations[oldArea],index)
 W.stations[area]=W.stations[area] or {};table.insert(W.stations[area],entry)
 if position then entry.position=require('src.persistence').copy(position);entry.motion=nil;entry.phase=nil;entry.radius=nil end
 return id
end
function W.removeStation(id)
 local entry,area,index=W.find(id);assert(entry,'unknown station '..tostring(id))
 if index then table.remove(W.stations[area],index) else entry.enabled=false end
 return entry
end
function W.setStationEnabled(id,enabled)
 local entry=assert(W.find(id),'unknown station '..tostring(id));entry.enabled=not not enabled
end
function W.export()
 return 'return '..require('src.save').encode({stations=W.stations,navigation=W.navigation,specials=W.specials,defaults=W.defaults})
end
function W.signature()
 local h=0;local compiled={}
 local Fields=require('src.fields')
 for _,area in ipairs(Fields.list) do compiled[area]={locations=Fields[area].locations,links=Fields[area].travelLinks} end
 local text=W.export()..require('src.save').encode(compiled)
 for i=1,#text do h=(h*31+text:byte(i))%2147483647 end
 return h
end

-- Build corridor connections by bearing; surface/cloud destinations are spurs.
function W.connect(f)
 local byId={};for _,p in ipairs(f.locations) do byId[p.id]=p end
 local config=f.navigation or {}
 local corridor={}
 local orbiting=false
 for _,id in ipairs(f.stationIds) do if byId[id].motion.type=='orbit' then orbiting=true end end
 local buoyOnly=config.corridor=='buoys' or (not config.corridor and not orbiting)
 for _,id in ipairs(f.buoyIds) do corridor[#corridor+1]=id end
 if not buoyOnly then
  for _,id in ipairs(f.stationIds) do
   if byId[id].motion.type=='orbit' then corridor[#corridor+1]=id end
  end
 end
 table.sort(corridor,function(a,b)
  local aa,bb=byId[a].motion.phase or 0,byId[b].motion.phase or 0
  return aa==bb and a<b or aa<bb
 end)
 -- Start the local circuit at its explicitly designated primary port.
 local start=1
 for i,id in ipairs(corridor) do if byId[id].primary then start=i;break end end
 local ordered={};for i=1,#corridor do ordered[i]=corridor[(start+i-2)%#corridor+1] end
 corridor=ordered
 f.buoyCorridor=buoyOnly
 f.buoyCircuit={}
 for _,id in ipairs(corridor) do if byId[id].kind=='buoy' then f.buoyCircuit[#f.buoyCircuit+1]=id end end
-- Raid legs are worked out from where the buoys are now (security.lua).
 f.travelLinks={};local seen={}
 local function link(a,b)
  if not a or not b or a==b then return end
  assert(byId[a] and byId[b],'unknown world connection '..tostring(a)..' -> '..tostring(b))
  local key=a<b and a..'|'..b or b..'|'..a
  if not seen[key] then seen[key]=true;f.travelLinks[#f.travelLinks+1]={a,b} end
 end
-- Ordinary nodes need no authored links: NPCs fly straight between them,
 -- round the planet (travelgraph.lua, G.neighbours). Only gates, drivers,
 -- ladders and authored extras are linked here.
 local onCorridor={};for _,id in ipairs(corridor) do onCorridor[id]=true end
 local attachments=#corridor>0 and corridor or f.holdingId and {f.holdingId} or f.stationIds
 -- With three or more buoys, something off the ring joins only the two
 -- buoys either side of it; a link to a far buoy would cut across the planet.
 local function bearing(node)
  local m=byId[node].motion
  if m.type=='fixed' then return math.atan2(m.y or 0,m.x or 0) end
  return m.type=='cloud' and m.a or m.phase or 0
 end
 local function nearBuoys(id)
  if #f.buoyIds<3 then return f.buoyIds end
  local a=bearing(id);local list={}
  for _,b in ipairs(f.buoyIds) do
   local d=math.abs((bearing(b)-a+math.pi)%(2*math.pi)-math.pi);list[#list+1]={b,d}
  end
  table.sort(list,function(x,y) return x[2]==y[2] and x[1]<y[1] or x[2]<y[2] end)
  return {list[1][1],list[2][1]}
 end
 for _,id in ipairs(f.drillIds) do link(byId[id].motion.home,id) end
 for _,driver in ipairs(f.driverIds or {}) do
  for _,id in ipairs(buoyOnly and #f.buoyIds>0 and nearBuoys(driver) or {f.tradeHome or f.holdingId}) do link(driver,id) end
  -- and straight to the planet's logistics hub: trunk freight lands there,
  -- and routing it all past the primary port jammed traffic at that one station
  for _,id in ipairs(f.stationIds) do if byId[id].hub then link(driver,id) end end
 end
 local anchors={}
 for _,id in ipairs(f.ladderIds or {}) do anchors[#anchors+1]=id end
 do
  for k,id in ipairs(anchors) do
   -- each anchor is its own way in from the buoys; anchors are not linked
   -- to each other (that ring ran straight through the ladder's cables)
   for _,to in ipairs(f.buoyIds) do link(id,to) end
   -- and straight to the region's other stations and its mass driver, so
   -- traffic leaves an anchor outward instead of skirting the ladder
   for _,to in ipairs(f.stationIds) do if not byId[to].accessOf and to~=(f.ladderIds and f.ladderIds[1]) and to~=id then link(id,to) end end
   for _,driver in ipairs(f.driverIds or {}) do link(id,driver) end
  end
 end
 for _,p in ipairs(f.locations) do
  if p.kind=='moon_gate' then for _,id in ipairs(buoyOnly and #f.buoyIds>0 and nearBuoys(p.id) or attachments) do link(p.id,id) end end
 end
 for _,pair in ipairs(config.links or {}) do link(pair[1],pair[2]) end
 -- traders start docked at home and take work from the board
 local home=f.tradeHome or f.stationIds[1]
 f.traderRoute=home and {home,home} or {}
 f.navigationVersion=(f.navigationVersion or 0)+1
end
-- Every station drinks water like it eats food: defaults.waterUse tanks a
-- game hour, or the entry's own water = { use = n } (0 for none).
local function drinks(entry)
 local use=(entry.water or {}).use or W.defaults.waterUse
 if use>0 then entry.facilities=entry.facilities or {};entry.facilities.water=entry.facilities.water or {capacity=-use} end
end
-- Every crewed market station takes the cartel's drugs (defaults.drugUse).
local function takesDrugs(entry,area)
 if entry.drugs==false or W.defaults.drugFreeAreas[area or entry.area] then return end
 local market=false
 for _,s in ipairs(entry.services or {}) do if s=='market' then market=true end end
 if not market then return end
 local food=(entry.food or {}).use or W.defaults.foodUse
 entry.facilities=entry.facilities or {}
 for id,per in pairs(W.defaults.drugUse) do
  if not entry.facilities[id] and food*per>0 then entry.facilities[id]={capacity=-food*per} end
 end
end
function W.applyDefaults()
 for area,entries in pairs(W.stations) do for _,entry in ipairs(entries) do drinks(entry);takesDrugs(entry,area) end end
 for _,entry in pairs(W.specials) do if entry.id then drinks(entry);takesDrugs(entry) end end
end
W.applyDefaults()
return W
