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
	Artillery and missiles burst on contact, at the end of their range, or
	when they pass close to an enemy: missiles within half their splash
	radius, shells within fuse pixels (default: the "Artillery proximity
	fuse" tuning share of their splash radius). Torpedoes
	are unguided and only burst on contact or at the end of their range.
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

ammo { id = "rounds_s", name = "Bullet S",  maker = "Halcyon Arms",       family = "gun",       size = "S", volume = 0.02, mass = 0.02, price = 3, w = 1, h = 1, stack = 50,
	shot = { damage = 12, speed = 4600, range = 8600, knockback = 250 } }
ammo { id = "rounds_m", name = "Bullet M",  maker = "Brute Industries",   family = "gun",       size = "M", volume = 0.04, mass = 0.04, price = 6, w = 1, h = 1, stack = 25,
	shot = { damage = 36, speed = 4800, range = 9800, knockback = 400 } }

ammo { id = "shell_s", name = "Shell S",    maker = "Ferrous Collective", family = "artillery", size = "S", volume = 0.15, mass = 0.12, price = 25, w = 1, h = 1, stack = 6,
	shot = { damage = 45, splash = 60, speed = 4800, range = 9000, knockback = 6000 } }
ammo { id = "shell_m", name = "Shell M",  maker = "Brute Industries",   family = "artillery", size = "M", volume = 0.30, mass = 0.25, price = 50, w = 1, h = 1, stack = 3,
	shot = { damage = 90, splash = 90, speed = 4700, range = 10400, knockback = 12000 } }
ammo { id = "shell_l", name = "Shell L",  maker = "Ferrous Collective", family = "artillery", size = "L", volume = 0.60, mass = 0.50, price = 110, w = 2, h = 1, stack = 3,
	shot = { damage = 180, splash = 130, speed = 1900, range = 13000, knockback = 26000 } }

ammo { id = "shot_s", name = "Shot S", maker = "Halcyon Arms",    family = "shotgun", size = "S", volume = 0.06, mass = 0.05, price = 8, w = 1, h = 1, stack = 16,
	shot = { damage = 9, pellets = 6, pelletSpread = 7, speed = 4000, range = 3000, knockback = 120 } }
ammo { id = "shot_m", name = "Shot M", maker = "Brute Industries",  family = "shotgun", size = "M", volume = 0.12, mass = 0.10, price = 18, w = 1, h = 1, stack = 8,
	shot = { damage = 22, pellets = 7, pelletSpread = 6, speed = 4200, range = 3600, knockback = 220 } }
ammo { id = "shot_l", name = "Shot L", maker = "Brute Industries", family = "shotgun", size = "L", volume = 0.25, mass = 0.20, price = 40, w = 2, h = 1, stack = 6,
	shot = { damage = 45, pellets = 8, pelletSpread = 5, speed = 4400, range = 4200, knockback = 400 } }

ammo { id = "missile_s", name = "Missile S", maker = "Halcyon Arms",     family = "missile",   size = "S", volume = 0.08, mass = 0.06, price = 15, w = 2, h = 1, stack = 20,
	shot = { armTime = 1.0, damage = 14, splash = 35, speed = 6100, range = 12600, knockback = 5000, accel = 2200, turnRate = 5 } }
ammo { id = "missile_m", name = "Missile M",  maker = "Nova Syndicate",   family = "missile",   size = "M", volume = 0.15, mass = 0.12, price = 40, w = 3, h = 1, stack = 12,
	shot = { armTime = 1.8, damage = 45, splash = 55, speed = 5000, range = 13000, knockback = 10000, accel = 1800, turnRate = 4 } }
ammo { id = "missile_l", name = "Missile L", maker = "Ferrous Collective", family = "missile", size = "L", volume = 0.40, mass = 0.30, price = 120, w = 3, h = 1, stack = 6,
	shot = { armTime = 3.0, damage = 120, splash = 90, speed = 3900, range = 13400, knockback = 20000, accel = 1300, turnRate = 2.8 } }

-- An atomic warhead: vaporizes what it kills (no wreck, no cargo), and
-- takes an age to arm.
ammo { id = "atomic_l", name = "Atomic Missile L", maker = "Estates Military", family = "missile", size = "L", volume = 6, mass = 5, price = 60000, w = 6, h = 1, stack = 1,
	shot = { armTime = 30, damage = 25000, splash = 3000, speed = 3200, range = 14000, knockback = 400000, accel = 900, turnRate = 1.6, vaporize = true } }

ammo { id = "torp_s", name = "Torpedo S",      maker = "Brute Industries",   family = "torpedo", size = "S", volume = 1.2, mass = 1.0, price = 600, w = 2, h = 1, stack = 1,
	shot = { armTime = 5, recoil = 2, damage = 220, splash = 80, speed = 9500, turnRate = 0.5, range = 12400, knockback = 15000 } }
ammo { id = "torp_m", name = "Torpedo M",   maker = "Brute Industries",   family = "torpedo", size = "M", volume = 2.5, mass = 2.2, price = 1400, w = 3, h = 1, stack = 1,
	shot = { armTime = 8, recoil = 2, damage = 500, splash = 130, speed = 8500, turnRate = 0.4, range = 12800, knockback = 35000 } }
ammo { id = "torp_l", name = "Torpedo L", maker = "Ferrous Collective", family = "torpedo", size = "L", volume = 5.0, mass = 4.5, price = 3200, w = 5, h = 1, stack = 1,
	shot = { armTime = 12, recoil = 2, damage = 1100, splash = 210, speed = 7500, turnRate = 0.3, range = 13200, knockback = 80000 } }

ammo { id = "drone_s", name = "Drone S",    maker = "Nova Syndicate", family = "drone", size = "S", volume = 4, mass = 3, price = 2500, w = 2, h = 2, stack = 1,
	shot = { hull = "wasp_drone", speed = 300, range = 1500 } }
ammo { id = "drone_m", name = "Drone M",    maker = "Nova Syndicate", family = "drone", size = "M", volume = 8, mass = 7, price = 6000, w = 3, h = 3, stack = 1,
	shot = { hull = "hive_drone", speed = 250, range = 1800 } }
ammo { id = "drone_l", name = "Drone L",  maker = "Nova Syndicate", family = "drone", size = "L", volume = 16, mass = 14, price = 14000, w = 4, h = 4, stack = 1,
	shot = { hull = "warden_drone", speed = 200, range = 2000 } }

salvage { id = "scrap",       name = "Scrap metal",      volume = 0.5, mass = 0.4, price = 60, w = 1, h = 1, stack = 2 }
salvage { id = "salvage_kit", name = "Salvaged circuitry", volume = 1.0, mass = 0.3, price = 260, w = 1, h = 1, stack = 1 }
-- Cut from a wreck's hull with a drill: a fixed amount per hull (Game.wreckAlloy).
salvage { id = "hull_alloy",  name = "Salvaged hull alloy", volume = 0.25, mass = 0.5, price = 180, w = 1, h = 1, stack = 4 }

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
salvage { id = "iron_ore",  name = "Iron ore",  volume = 0.25, mass = 0.3, price = 25, w = 1, h = 1, stack = 4 }
salvage { id = "water_ice", name = "Water ice", volume = 0.25, mass = 0.22, price = 15, w = 1, h = 1, stack = 4 }

-- Trade commodities (src/commodities.lua): made at some stations, used up at others.
salvage { id = "food_crate", name = "Food crate", volume = 0.25, mass = 0.2, price = 30, w = 1, h = 1, stack = 4 }
salvage { id = "empty_canister", name = "Empty canister", volume = 0.25, mass = 0.08, price = 15, w = 1, h = 1, stack = 4 }
salvage { id = "hydrogen_canister", name = "Hydrogen canister", volume = 0.25, mass = 0.1, price = 40, w = 1, h = 1, stack = 4 }
-- Reactor fuel: ice from Ceres, cracked into deuterium and sealed in a
-- canister there (src/commodities.lua). Every ship's reactor burns it.
salvage { id = "deuterium_canister", name = "Deuterium canister", volume = 0.25, mass = 0.15, price = 60, w = 1, h = 1, stack = 4 }
salvage { id = "martian_ore", name = "Martian ore", volume = 1, mass = 1, price = 30, w = 1, h = 1, stack = 1 }
