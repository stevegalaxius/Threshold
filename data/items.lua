--[[
	Hold items: ammo and salvage. Everything you carry takes hold volume
	(cubic metres) and adds mass (tonnes), so a hold full of shells makes
	the ship sluggish. Prices are what markets charge (not used yet in the
	flight toy, but they're the numbers the economy will be tuned with).

	Ammo: family (gun, artillery or missile) and size (S, M or L) decide
	which weapons can fire it: a weapon fires its own family in its own
	size or smaller. The damage is in the ammo, not the weapon (the weapon
	only sets fire rate, accuracy, gimbal and recoil), so the shot table
	holds everything about the projectile:
	  damage     per hit                    splash     blast radius (pixels)
	  speed      pixels/second              knockback  push on what it hits
	  range      pixels (shots expire there)
	  accel, turnRate   missiles only: acceleration and turn (rad/s)
	Artillery and missiles burst on contact, at the end of their range, or
	when they pass within half their splash radius of an enemy.
]]

ammo { id = "rounds_s",  name = "Light rounds",  maker = "Halcyon Arms",       family = "gun",       size = "S", volume = 0.02, mass = 0.02, price = 3,
	shot = { damage = 10.8, speed = 2600, range = 1000, knockback = 250 } }
ammo { id = "rounds_m",  name = "Heavy rounds",  maker = "Brute Industries",   family = "gun",       size = "M", volume = 0.04, mass = 0.04, price = 6,
	shot = { damage = 20, speed = 2800, range = 1150, knockback = 400 } }

ammo { id = "shell_s",   name = "Pip shells",    maker = "Ferrous Collective", family = "artillery", size = "S", volume = 0.15, mass = 0.12, price = 25,
	shot = { damage = 45, splash = 60, speed = 1800, range = 2000, knockback = 6000 } }
ammo { id = "shell_m",   name = "Field shells",  maker = "Brute Industries",   family = "artillery", size = "M", volume = 0.30, mass = 0.25, price = 50,
	shot = { damage = 90, splash = 90, speed = 1700, range = 2400, knockback = 12000 } }
ammo { id = "shell_l",   name = "Siege shells",  maker = "Ferrous Collective", family = "artillery", size = "L", volume = 0.60, mass = 0.50, price = 110,
	shot = { damage = 180, splash = 130, speed = 1900, range = 3000, knockback = 26000 } }

ammo { id = "missile_s", name = "Sparrow missile", maker = "Halcyon Arms",     family = "missile",   size = "S", volume = 0.80, mass = 0.60, price = 400,
	shot = { damage = 70, splash = 45, speed = 1100, range = 2600, knockback = 5000, accel = 2200, turnRate = 5 } }
ammo { id = "missile_m", name = "Hornet missile",  maker = "Nova Syndicate",   family = "missile",   size = "M", volume = 1.50, mass = 1.20, price = 900,
	shot = { damage = 140, splash = 70, speed = 1000, range = 3000, knockback = 10000, accel = 1800, turnRate = 4 } }
ammo { id = "missile_l", name = "Longbow missile", maker = "Ferrous Collective", family = "missile", size = "L", volume = 3.00, mass = 2.50, price = 2000,
	shot = { damage = 260, splash = 110, speed = 900, range = 3400, knockback = 20000, accel = 1300, turnRate = 2.8 } }

salvage { id = "scrap",       name = "Scrap metal",      volume = 0.5, mass = 0.4, price = 60 }
salvage { id = "salvage_kit", name = "Salvaged circuitry", volume = 1.0, mass = 0.3, price = 260 }
