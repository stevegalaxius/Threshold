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
	  accel, turnRate   missiles only: acceleration and turn (rad/s)
	Artillery and missiles burst on contact, at the end of their range, or
	when they pass close to an enemy: missiles within half their splash
	radius, shells within fuse pixels (default: the "Artillery proximity
	fuse" tuning share of their splash radius). Torpedoes
	are unguided and only burst on contact or at the end of their range.
	Drones aren't shots: their shot table names the hull that launches
	(hull), its gun ammo (cargo) and how many seconds it fights (life).

	Grid shape: the hold is a grid of 1 m3 cells, and w x h is how many
	cells a stack of the item covers (it can be rotated), with up to stack
	items in it. A stack never holds more volume than its cells, so
	w * h >= volume * stack. Leave them out and src/inventory/shapes.lua
	works one out from the volume. Ammo crates are 2 x 2.
]]

ammo { id = "rounds_s",  name = "Light rounds",  maker = "Halcyon Arms",       family = "gun",       size = "S", volume = 0.02, mass = 0.02, price = 3, w = 1, h = 1, stack = 50,
	shot = { damage = 10.8, speed = 2600, range = 4000, knockback = 250 } }
ammo { id = "rounds_m",  name = "Heavy rounds",  maker = "Brute Industries",   family = "gun",       size = "M", volume = 0.04, mass = 0.04, price = 6, w = 1, h = 1, stack = 25,
	shot = { damage = 36, speed = 2800, range = 4500, knockback = 400 } }

ammo { id = "shell_s",   name = "Pip shells",    maker = "Ferrous Collective", family = "artillery", size = "S", volume = 0.15, mass = 0.12, price = 25, w = 1, h = 1, stack = 6,
	shot = { damage = 45, splash = 60, speed = 1800, range = 5000, knockback = 6000 } }
ammo { id = "shell_m",   name = "Field shells",  maker = "Brute Industries",   family = "artillery", size = "M", volume = 0.30, mass = 0.25, price = 50, w = 1, h = 1, stack = 3,
	shot = { damage = 90, splash = 90, speed = 1700, range = 6000, knockback = 12000 } }
ammo { id = "shell_l",   name = "Siege shells",  maker = "Ferrous Collective", family = "artillery", size = "L", volume = 0.60, mass = 0.50, price = 110, w = 2, h = 1, stack = 3,
	shot = { damage = 180, splash = 130, speed = 1900, range = 7500, knockback = 26000 } }

ammo { id = "missile_s", name = "Sparrow missile", maker = "Halcyon Arms",     family = "missile",   size = "S", volume = 0.80, mass = 0.60, price = 400, w = 2, h = 1, stack = 2,
	shot = { damage = 70, splash = 45, speed = 1100, range = 6500, knockback = 5000, accel = 2200, turnRate = 5 } }
ammo { id = "missile_m", name = "Hornet missile",  maker = "Nova Syndicate",   family = "missile",   size = "M", volume = 1.50, mass = 1.20, price = 900, w = 3, h = 1, stack = 2,
	shot = { damage = 140, splash = 70, speed = 1000, range = 7500, knockback = 10000, accel = 1800, turnRate = 4 } }
ammo { id = "missile_l", name = "Longbow missile", maker = "Ferrous Collective", family = "missile", size = "L", volume = 3.00, mass = 2.50, price = 2000, w = 3, h = 1, stack = 1,
	shot = { damage = 260, splash = 110, speed = 900, range = 8500, knockback = 20000, accel = 1300, turnRate = 2.8 } }

ammo { id = "torp_s", name = "Maul torpedo",      maker = "Brute Industries",   family = "torpedo", size = "S", volume = 1.2, mass = 1.0, price = 600, w = 2, h = 1, stack = 1,
	shot = { damage = 220, splash = 80, speed = 750, range = 6000, knockback = 15000 } }
ammo { id = "torp_m", name = "Breaker torpedo",   maker = "Brute Industries",   family = "torpedo", size = "M", volume = 2.5, mass = 2.2, price = 1400, w = 3, h = 1, stack = 1,
	shot = { damage = 500, splash = 130, speed = 650, range = 7000, knockback = 35000 } }
ammo { id = "torp_l", name = "Leviathan torpedo", maker = "Ferrous Collective", family = "torpedo", size = "L", volume = 5.0, mass = 4.5, price = 3200, w = 5, h = 1, stack = 1,
	shot = { damage = 1100, splash = 210, speed = 550, range = 8000, knockback = 80000 } }

ammo { id = "drone_s", name = "Wasp drone",    maker = "Nova Syndicate", family = "drone", size = "S", volume = 4, mass = 3, price = 2500, w = 2, h = 2, stack = 1,
	shot = { hull = "wasp_drone", cargo = { rounds_s = 150 }, life = 25, speed = 300, range = 3800 } }
ammo { id = "drone_m", name = "Hive drone",    maker = "Nova Syndicate", family = "drone", size = "M", volume = 8, mass = 7, price = 6000, w = 3, h = 3, stack = 1,
	shot = { hull = "hive_drone", cargo = { rounds_m = 200 }, life = 30, speed = 250, range = 4500 } }
ammo { id = "drone_l", name = "Warden drone",  maker = "Nova Syndicate", family = "drone", size = "L", volume = 16, mass = 14, price = 14000, w = 4, h = 4, stack = 1,
	shot = { hull = "warden_drone", cargo = { rounds_m = 300 }, life = 40, speed = 200, range = 5000 } }

salvage { id = "scrap",       name = "Scrap metal",      volume = 0.5, mass = 0.4, price = 60, w = 1, h = 1, stack = 2 }
salvage { id = "salvage_kit", name = "Salvaged circuitry", volume = 1.0, mass = 0.3, price = 260, w = 1, h = 1, stack = 1 }

-- Standard cargo container. Empty, it's an 8 x 5 item, too big for a
-- Wisp's hold and only just fits an Anvil's. Out in space it's a box with
-- an 8 x 4 grid inside: tap E on it to open it, hold E to tow it (or stow
-- it, if it's empty and your hold has room). body is its size in pixels.
container { id = "cargo_container", name = "Cargo container", maker = "Ferrous Collective",
	volume = 40, mass = 4, price = 1200, w = 8, h = 5, grid = { 8, 4 }, hp = 90, body = { 46, 28 },
	fill = {
		{ "rounds_s_crate", 20, 120, 0.6 }, { "rounds_m_crate", 20, 80, 0.5 },
		{ "shell_s_crate", 4, 18, 0.35 }, { "missile_s_crate", 2, 8, 0.3 },
		{ "scrap", 2, 12, 0.7 }, { "salvage_kit", 1, 4, 0.4 },
	} }
