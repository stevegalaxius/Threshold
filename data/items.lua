--[[
	Hold items: ammo, salvage and containers. Everything you carry takes hold volume
	(cubic metres) and adds mass (tonnes), so a hold full of shells makes
	the ship sluggish. Prices are what markets charge (not used yet in the
	flight toy, but they're the numbers the economy will be tuned with).

	Ammo: family (gun, artillery, missile, torpedo or drone) and size (S, M
	or L) decide
	which weapons can fire it: guns and artillery only take their own
	caliber, missile launchers take missiles of their size or smaller. The damage is in the ammo, not the weapon (the weapon
	only sets fire rate, accuracy, gimbal and recoil), so the shot table
	holds everything about the projectile:
	  damage     per hit                    splash     blast radius (pixels)
	  speed      pixels/second              knockback  push on what it hits
	  range      pixels (shots expire there)
	  accel, turnRate   missiles: acceleration and turn (rad/s); torpedoes: turnRate only (they launch at full speed)
	Explosive artillery shells and missiles burst on contact, at the end of their range, or
	when they pass close to an enemy: missiles within half their splash
	radius, shells within fuse pixels (default: the "Artillery proximity
	fuse" tuning share of their splash radius). Torpedoes
	are unguided and only burst on contact or at the end of their range.
	Scatter shells fire short-range pellets. Airburst gun rounds burst on
	contact or at their fixed range, without a proximity fuse.
	Drones aren't shots: their shot table names the hull that launches
	(hull). Drones fly lasers, so they need no ammo, and they don't
	expire: they dock back into the hold once there's nothing to fight,
	keeping whatever damage they took (the stack's wear).

	Grid shape: the hold is a grid of 1 m3 cells, and w x h is how many
	cells a stack of the item covers (it can be rotated), with up to stack
	items in it. A stack never holds more volume than its cells, so
	w * h >= volume * stack. Leave them out and src/inventory/shapes.lua
	works one out from the volume. 
]]

ammo { id = "rounds_s", name = "Solid Rounds S", shortName = "Solid S", default = true,  maker = "Halcyon Arms",       family = "gun",       size = "S", volume = 0.02, mass = 0.02, price = 6, w = 1, h = 1, stack = 50,
	shot = { damage = 12, speed = 4600, range = 8600, knockback = 250 } }
ammo { id = "rounds_m", name = "Solid Rounds M", shortName = "Solid M", default = true,  maker = "Brute Industries",   family = "gun",       size = "M", volume = 0.04, mass = 0.04, price = 18, w = 1, h = 1, stack = 25,
	shot = { damage = 36, speed = 4800, range = 9800, knockback = 400 } }

-- Flak gun rounds: a proximity fuse bursts them beside an enemy (fuse px,
-- default 0.6 x splash), so a stream of near misses still does damage. Less
-- per hit than solid rounds and a little slower and shorter-ranged, but far
-- more forgiving to aim.
ammo { id = "airburst_s", name = "Airburst Rounds S", shortName = "Airburst S", maker = "Halcyon Arms", family = "gun", size = "S", volume = 0.02, mass = 0.02, price = 6, w = 1, h = 1, stack = 50,
 shot = { damage = 8, splash = 80, fuse = 50, speed = 4000, range = 5000, knockback = 10, airburst = true } }
ammo { id = "airburst_m", name = "Airburst Rounds M", shortName = "Airburst M", maker = "Brute Industries", family = "gun", size = "M", volume = 0.04, mass = 0.04, price = 15, w = 1, h = 1, stack = 25,
 shot = { damage = 24, splash = 105, fuse = 65, speed = 4200, range = 5800, knockback = 18, airburst = true } }

ammo { id = "shell_s", name = "Explosive Shells S", shortName = "Explosive S", default = true,    maker = "Ferrous Collective", family = "artillery", size = "S", volume = 0.15, mass = 0.12, price = 45, w = 1, h = 1, stack = 6,
	shot = { damage = 45, splash = 60, speed = 6200, range = 9000, knockback = 6000 } }
ammo { id = "shell_m", name = "Explosive Shells M", shortName = "Explosive M", default = true,  maker = "Brute Industries",   family = "artillery", size = "M", volume = 0.30, mass = 0.25, price = 100, w = 1, h = 1, stack = 3,
	shot = { damage = 90, splash = 90, speed = 6500, range = 10400, knockback = 12000 } }
ammo { id = "shell_l", name = "Explosive Shells L", shortName = "Explosive L", default = true,  maker = "Ferrous Collective", family = "artillery", size = "L", volume = 0.60, mass = 0.50, price = 200, w = 2, h = 1, stack = 3,
	shot = { damage = 180, splash = 130, speed = 6800, range = 13000, knockback = 26000 } }

ammo { id = "shot_s", name = "Scatter Shells S", shortName = "Scatter S", maker = "Halcyon Arms",    family = "artillery", size = "S", volume = 0.06, mass = 0.05, price = 8, w = 1, h = 1, stack = 16,
	shot = { damage = 9, pellets = 6, pelletSpread = 7, speed = 5400, range = 3000, knockback = 120 } }
ammo { id = "shot_m", name = "Scatter Shells M", shortName = "Scatter M", maker = "Brute Industries",  family = "artillery", size = "M", volume = 0.12, mass = 0.10, price = 25, w = 1, h = 1, stack = 8,
	shot = { damage = 16, pellets = 7, pelletSpread = 6, speed = 5600, range = 3600, knockback = 220 } }
ammo { id = "shot_l", name = "Scatter Shells L", shortName = "Scatter L", maker = "Brute Industries", family = "artillery", size = "L", volume = 0.25, mass = 0.20, price = 65, w = 2, h = 1, stack = 6,
	shot = { damage = 28, pellets = 8, pelletSpread = 5, speed = 5800, range = 4200, knockback = 400 } }

ammo { id = "missile_s", name = "Missile S", maker = "Halcyon Arms",     family = "missile",   size = "S", volume = 0.08, mass = 0.06, price = 35, w = 2, h = 1, stack = 20,
	shot = { armTime = 1.0, damage = 14, splash = 35, speed = 6100, range = 12600, knockback = 5000, accel = 2200, turnRate = 5 } }
ammo { id = "missile_m", name = "Missile M",  maker = "Nova Syndicate",   family = "missile",   size = "M", volume = 0.15, mass = 0.12, price = 110, w = 3, h = 1, stack = 12,
	shot = { armTime = 1.8, damage = 45, splash = 55, speed = 5000, range = 13000, knockback = 10000, accel = 1800, turnRate = 4 } }
ammo { id = "missile_l", name = "Missile L", maker = "Ferrous Collective", family = "missile", size = "L", volume = 0.40, mass = 0.30, price = 300, w = 3, h = 1, stack = 6,
	shot = { armTime = 3.0, damage = 120, splash = 90, speed = 3900, range = 13400, knockback = 20000, accel = 1300, turnRate = 2.8 } }

ammo { id = "torp_s", name = "Torpedo S",      maker = "Brute Industries",   family = "torpedo", size = "S", volume = 1.2, mass = 1.0, price = 300, w = 2, h = 1, stack = 1,
	shot = { armTime = 5, recoil = 2, damage = 100, splash = 80, speed = 9500, turnRate = 0.5, range = 12400, knockback = 15000 } }
ammo { id = "torp_m", name = "Torpedo M",   maker = "Brute Industries",   family = "torpedo", size = "M", volume = 2.5, mass = 2.2, price = 750, w = 3, h = 1, stack = 1,
	shot = { armTime = 8, recoil = 2, damage = 250, splash = 130, speed = 8500, turnRate = 0.4, range = 12800, knockback = 35000 } }
ammo { id = "torp_l", name = "Torpedo L", maker = "Ferrous Collective", family = "torpedo", size = "L", volume = 5.0, mass = 4.5, price = 1650, w = 5, h = 1, stack = 1,
	shot = { armTime = 12, recoil = 2, damage = 550, splash = 210, speed = 7500, turnRate = 0.3, range = 13200, knockback = 80000 } }

ammo { id = "drone_s", name = "Drone S",    maker = "Nova Syndicate", family = "drone", size = "S", volume = 4, mass = 3, price = 2500, w = 2, h = 2, stack = 1,
	shot = { hull = "wasp_drone", speed = 300, range = 1500 } }
ammo { id = "drone_m", name = "Drone M",    maker = "Nova Syndicate", family = "drone", size = "M", volume = 8, mass = 7, price = 6000, w = 3, h = 3, stack = 1,
	shot = { hull = "hive_drone", speed = 250, range = 1800 } }
ammo { id = "drone_l", name = "Drone L",  maker = "Nova Syndicate", family = "drone", size = "L", volume = 16, mass = 14, price = 14000, w = 4, h = 4, stack = 1,
	shot = { hull = "warden_drone", speed = 200, range = 2000 } }

-- Cut from a wreck's hull with a drill: a fixed amount per hull (Game.wreckSteel).
-- A finished ship hull frame from a manufacturer's shipworks (data/industry.lua);
-- its dealer rolls frames out as new ships (src/dealers.lua).
salvage { id = "hull_frame", name = "Hull frame", volume = 16, mass = 20, price = 2400, w = 4, h = 4, stack = 1 }
-- A commodity: stations spend it on armor repairs at the dock, 100 armor a
-- plate (src/repair_materials.lua). Cut from wrecks, made from steel.
salvage { id = "steel_plate",  name = "Steel plates", volume = 0.25, mass = 0.5, price = 180, w = 1, h = 1, stack = 4 }

-- Usable items (src/item_use.lua). Each is only a combination of shared
-- effects; see the header there for the format.
salvage { id = "patch_kit", name = "Hull patch kit", description = "Quick-setting armor patches. Use it from the hold, or with Q.",
	volume = 0.25, mass = 0.3, price = 420, w = 1, h = 1, stack = 4,
	use = { label = "Patch hull", cast = 1, group = "repair", cooldown = 20,
		effects = { { "restore", "armor", 150 }, { "quest", item = "patch_kit" } } } }
-- Feedstock for armor repairer modules (not built yet): they'll consume it.
salvage { id = "nanite_paste", name = "Nanite paste", description = "Repair nanites. Armor repairers consume it.",
	volume = 0.1, mass = 0.05, price = 650, w = 1, h = 1, stack = 4 }

-- Standard cargo container. Empty, it's an 8 x 5 item, too big for a
-- Wisp's hold and only just fits an Anvil's. Out in space it's a box with
-- an 8 x 4 grid inside: tap E on it to open it, hold E to tow it (or stow
-- it, if it's empty and your hold has room). body is its size in pixels.
container { id = "cargo_container", name = "Cargo container", maker = "Ferrous Collective",
	volume = 40, mass = 4, price = 1200, w = 8, h = 5, grid = { 8, 4 }, hp = 90, body = { 46, 28 },
	lootTable = "lost_cargo" }

-- Countermeasure flares: a flare pod fires them on its own when a missile
-- closes in (src/weapons.lua).
salvage { id = "flare", name = "Flare charge", volume = 0.1, mass = 0.05, price = 20, w = 1, h = 1, stack = 10 }

-- What a mining drill gets out of the rock it breaks (src/game.lua ORE).
salvage { id = "iron_ore",  name = "Iron ore",  volume = 0.25, mass = 0.3, price = 60, w = 1, h = 1, stack = 4 }
salvage { id = "water_ice", name = "Water ice", volume = 0.25, mass = 0.22, price = 40, w = 1, h = 1, stack = 4 }
-- Rare ore: from a vein in a big rock, or a crystal frozen in big ice
-- (src/rock_chips.lua).
salvage { id = "gold_ore", name = "Gold ore", volume = 0.25, mass = 0.5, price = 220, w = 1, h = 1, stack = 4 }
salvage { id = "cryo_crystal", name = "Cryo crystal", volume = 0.25, mass = 0.2, price = 180, w = 1, h = 1, stack = 4 }

-- Industrial inputs and manufactured electronics.
salvage { id = "silicon", name = "Silicon", volume = 0.25, mass = 0.25, price = 60, w = 1, h = 1, stack = 4 }
salvage { id = "industrial_acids", name = "Industrial acids", volume = 0.25, mass = 0.25, price = 60, w = 1, h = 1, stack = 4 }
salvage { id = "electronics", name = "Electronics", volume = 0.1, mass = 0.05, price = 160, w = 1, h = 1, stack = 10 }
salvage { id = "heavy_metals", name = "Heavy metals", description = "Dense metal concentrate sorted out of belt regolith at the quarry depots. Coil works buy all they can get.", volume = 0.25, mass = 0.6, price = 80, w = 1, h = 1, stack = 4 }
salvage { id = "superconducting_coils", name = "Superconducting coils", description = "Heavy-metal windings on an electronic core. Every engine and reactor needs them.", volume = 0.25, mass = 0.3, price = 490, w = 1, h = 1, stack = 4 }
salvage { id = "thermal_ceramics", name = "Thermal ceramics", description = "Fired silicon tiles cured in acid. Engine nozzles and reactor shielding are lined with them.", volume = 0.25, mass = 0.2, price = 270, w = 1, h = 1, stack = 4 }

-- Trade commodities (src/commodities.lua): made at some stations, used up at others.
salvage { id = "water", name = "Water tank", volume = 0.25, mass = 0.25, price = 60, w = 1, h = 1, stack = 4 }
-- Delicate cargo (delicate = true) only rides in a climate-controlled
-- compartment: a hull's climate hold or a fitted Climate Pod.
salvage { id = "medical_supplies", name = "Medical supplies", delicate = true, volume = 0.25, mass = 0.1, price = 320, w = 1, h = 1, stack = 4,
	description = "Vaccines, blood and tissue cultures. Spoils outside a climate-controlled hold." }
-- Alkalines: brine salts pumped from the ocean moons (Europa, Enceladus).
salvage { id = "alkalines", name = "Alkalines", volume = 0.25, mass = 0.3, price = 70, w = 1, h = 1, stack = 4,
	description = "Lye and carbonate salts boiled out of ocean brine. Soap, glass, and less honest chemistry." }
-- Cartel goods (Milliways, src/reputation.lua Rep.CONTRABAND): made at the
-- Shoals and Antichthon, sold openly to Jove and Zhuhai, and into Estates
-- and Diwan space only through a fence.
salvage { id = "amphetamines", name = "Amphetamines", volume = 0.1, mass = 0.05, price = 420, w = 1, h = 1, stack = 10,
	description = "Shift stimulants. Twenty hours awake on a drill line, and the bill comes later." }
salvage { id = "fentanyl", name = "Fentanyl analogues", volume = 0.05, mass = 0.02, price = 900, w = 1, h = 1, stack = 20,
	description = "Synthetic opioids a hundred times stronger than morphine, pressed into tablets. A crate is worth a hauler's year." }
salvage { id = "cannabinoid_moss", name = "Cannabinoid moss", volume = 0.25, mass = 0.1, price = 180, w = 1, h = 1, stack = 4,
	description = "A moss engineered to make cannabinoids, grown under lamps at Antichthon and sold dried." }
-- Passengers ride in climate cells only, one to a cell (src/passengers.lua).
-- They are a contract's party, never market goods.
salvage { id = "passengers", name = "Passengers", delicate = true, passengers = true, volume = 1, mass = 0.1, price = 0, w = 1, h = 1, stack = 1,
	description = "A travelling party. Seated in a climate-controlled hold; the more comfortable the seats, the better the fare." }
-- A notable riding as a VIP (src/notables.lua): one seat, same rules.
-- Ejecting one in space is an airlock: they die, and the world changes.
salvage { id = "vip", name = "VIP passenger", delicate = true, passengers = true, volume = 1, mass = 0.1, price = 0, w = 1, h = 1, stack = 1,
	description = "Someone important, travelling under your care. Their staff booked the best seat you have." }
salvage { id = "vip_remains", name = "Remains in a pressure suit", volume = 1, mass = 0.1, price = 0, w = 1, h = 1, stack = 1,
	description = "What came out of the airlock. The suit's seal still carries their name." }
salvage { id = "food_crate", name = "Food crate", volume = 0.25, mass = 0.2, price = 40, w = 1, h = 1, stack = 4 }
salvage { id = "nitrates", name = "Nitrates", volume = 0.25, mass = 0.25, price = 60, w = 1, h = 1, stack = 4 }
salvage { id = "explosives", name = "Explosives", volume = 0.25, mass = 0.25, price = 175, w = 1, h = 1, stack = 4 }
salvage { id = "fertilizer", name = "Fertilizer", volume = 0.25, mass = 0.25, price = 95, w = 1, h = 1, stack = 4 }
salvage { id = "empty_canister", name = "Empty canister", volume = 0.25, mass = 0.08, price = 45, w = 1, h = 1, stack = 4 }
salvage { id = "hydrogen_canister", name = "Hydrogen canister", volume = 0.25, mass = 0.1, price = 75, w = 1, h = 1, stack = 4 }
-- Reactor fuel: ice from Ceres, cracked into deuterium and sealed in a
-- canister there (src/commodities.lua). Every ship's reactor burns it.
-- A folded satellite. Replacement-launch jobs hand you one to use at the
-- old satellite's spot (src/sat_quests.lua); one you buy (logistics
-- stations) puts up a satellite of your own wherever you use it in orbit
-- (src/satellites.lua, Sat.deploy).
salvage { id = "satellite_package", name = "Satellite package", description = "A folded relay satellite. Use it in orbit to put it up as your own: it earns while it has fuel. Use it at a launch job's site to replace a lost one.",
	volume = 1, mass = 1, price = 12000, w = 2, h = 2, stack = 1,
	use = { label = "Launch satellite", cast = 3, effects = { { "deploy_satellite" }, { "quest", item = "satellite_package" } } } }
salvage { id = "deuterium_canister", name = "Deuterium canister", volume = 0.25, mass = 0.15, price = 130, w = 1, h = 1, stack = 4 }
