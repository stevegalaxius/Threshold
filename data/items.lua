--[[
	Hold items: ammo and salvage. Everything you carry takes hold volume
	(cubic metres) and adds mass (tonnes), so a hold full of shells makes
	the ship sluggish. Prices are what markets charge (not used yet in the
	flight toy, but they're the numbers the economy will be tuned with).

	Ammo: family (gun, artillery or missile) and size (S, M or L) decide
	which weapons can fire it.
]]

ammo { id = "rounds_s",  name = "Light rounds",  maker = "Halcyon Arms",       family = "gun",       size = "S", volume = 0.02, mass = 0.02, price = 3 }
ammo { id = "rounds_m",  name = "Heavy rounds",  maker = "Brute Industries",   family = "gun",       size = "M", volume = 0.04, mass = 0.04, price = 6 }
ammo { id = "shell_s",   name = "Pip shells",    maker = "Ferrous Collective", family = "artillery", size = "S", volume = 0.15, mass = 0.12, price = 25 }
ammo { id = "shell_m",   name = "Field shells",  maker = "Brute Industries",   family = "artillery", size = "M", volume = 0.30, mass = 0.25, price = 50 }
ammo { id = "shell_l",   name = "Siege shells",  maker = "Ferrous Collective", family = "artillery", size = "L", volume = 0.60, mass = 0.50, price = 110 }
ammo { id = "missile_s", name = "Sparrow missile", maker = "Halcyon Arms",     family = "missile",   size = "S", volume = 0.80, mass = 0.60, price = 400 }
ammo { id = "missile_m", name = "Hornet missile",  maker = "Nova Syndicate",   family = "missile",   size = "M", volume = 1.50, mass = 1.20, price = 900 }

salvage { id = "scrap",       name = "Scrap metal",      volume = 0.5, mass = 0.4, price = 60 }
salvage { id = "salvage_kit", name = "Salvaged circuitry", volume = 1.0, mass = 0.3, price = 260 }
