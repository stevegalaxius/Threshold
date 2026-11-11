--[[
	Sites (src/sites.lua): instanced places off the map that a mass driver
	can fire you to. Each one is a chain of pockets (small instanced maps)
	joined by acceleration gates: drivers with one fixed target.

	site {
	  id, name,
	  kind     = "raid" | "dungeon" | "meetup" | "station" | anything (a label)
	  color    = { r, g, b }      its diamond on the driver's orrery
	  home     = planet id or { ... } (picked at random when spawned)
	  lifetime = game-clock seconds before it closes (nil: never)
	  hidden   = true             off the orrery until discovered
	  fare     = cr to be fired there (else T.siteFare)
	  pockets  = {
	    { name, radius = map radius, spawn = { x, y } where you arrive,
	      pieces = {
	        { type = "rocks", count = n, minD = d }
	        { type = "giant", x, y, r }                 a huge rock
	        { type = "station", station = id, x, y, spin, name }   dockable
	        { type = "enemies", groups = { { enemy, n }, ... }, x, y, r,
	          tag = "boss" }                            spawned until cleared
	        { type = "containers", item = crate id | container = object id,
	          count = { min, max }, loot = table id, x, y, r }
	        { type = "spawnSet", id = set id, minD = d }
	        { type = "gate", to = pocket number | "exit", x, y, name,
	          unlock = nil | "clear" | { kill = tag } | { item = id } }
	      } },
	  },
	}

	Every pocket 1 also gets a way home: if none of its gates goes to
	"exit", a return gate is added beside the spawn point.
]]

-- The key the raid's vault gate wants: carried by the warden.
salvage { id = "vault_key", name = "Vault key", volume = 0.1, mass = 0.1, price = 400, w = 1, h = 1, stack = 1 }

loot_table {
	id = "site_cache", rolls = { 2, 3 },
	entries = {
		{ item = "salvage_kit", min = 1, max = 2, weight = 3 },
		{ item = "steel_plate", min = 2, max = 6, weight = 3 },
		{ item = "missile_m", min = 4, max = 10, weight = 2 },
		{ item = "shell_m", min = 3, max = 9, weight = 1 },
	},
}

loot_table {
	id = "warden_key", rolls = { 0, 0 },
	guaranteed = { { item = "vault_key", min = 1, max = 1 } },
}

loot_table {
	id = "vault_hoard", rolls = { 4, 6 },
	entries = {
		{ item = "salvage_kit", min = 2, max = 4, weight = 3 },
		{ item = "torp_s", min = 1, max = 2, weight = 1 },
		{ item = "missile_l", min = 2, max = 4, weight = 2 },
	},
}

-- A quiet spot to meet someone: one pocket, a few rocks, nothing else.
site {
	id = "quiet_meet", name = "Quiet rendezvous", kind = "meetup",
	color = { 0.45, 0.75, 1 }, home = { "earth", "mars", "venus" }, lifetime = 900,
	pockets = {
		{ name = "Rendezvous", radius = 15000, spawn = { 0, 4500 },
			pieces = { { type = "rocks", count = 225, minD = 2700 } } },
	},
}

-- A station that isn't on any chart: warp in, dock, warp out.
site {
	id = "dark_dock", name = "Unlisted dock", kind = "station", hidden = true,
	color = { 0.6, 0.9, 0.85 }, home = { "jupiter", "saturn", "belt" },
	pockets = {
		{ name = "Unlisted dock", radius = 21000, spawn = { 0, 9600 },
			pieces = {
				{ type = "station", station = "customs_1", x = 0, y = 0, spin = 0.02, name = "Unlisted dock" },
				{ type = "rocks", count = 270, minD = 6000 },
			} },
	},
}

-- Two pockets: a guarded field, then a gate that opens once it's quiet.
site {
	id = "smugglers_hollow", name = "Smugglers' hollow", kind = "dungeon",
	color = { 1, 0.6, 0.25 }, home = { "belt", "mars" }, lifetime = 1800,
	pockets = {
		{ name = "Hollow mouth", radius = 21000, spawn = { 0, 9000 },
			pieces = {
				{ type = "rocks", count = 540, minD = 2400 },
				{ type = "enemies", groups = { { "swarmer", 3 }, { "gunner", 2 } }, x = 0, y = -3600, r = 1800 },
				{ type = "gate", to = 2, x = 0, y = -11400, unlock = "clear" },
			} },
		{ name = "Hollow cache", radius = 18000, spawn = { 0, 7800 },
			pieces = {
				{ type = "giant", x = 0, y = -1800, r = 900 },
				{ type = "enemies", groups = { { "gunner", 2 }, { "interceptor", 1 } }, x = 0, y = -6600, r = 1200 },
				{ type = "containers", item = "cargo_container", count = { 2, 3 }, loot = "site_cache", x = 0, y = -7200, r = 700 },
				{ type = "gate", to = "exit", x = 6600, y = 6600 },
			} },
	},
}

-- Four pockets: a picket, a yard, the warden with the vault key, the vault.
site {
	id = "iron_vault", name = "Iron vault", kind = "raid",
	color = { 1, 0.3, 0.3 }, home = { "saturn", "jupiter", "uranus" }, lifetime = 3600, fare = 600,
	pockets = {
		{ name = "Picket", radius = 24000, spawn = { 0, 10500 },
			pieces = {
				{ type = "rocks", count = 360, minD = 3600 },
				{ type = "enemies", groups = { { "gunner", 3 }, { "interceptor", 2 } }, x = 0, y = -3000, r = 2000 },
				{ type = "gate", to = 2, x = 0, y = -13500, unlock = "clear" },
			} },
		{ name = "Breaker yard", radius = 24000, spawn = { 0, 10500 },
			pieces = {
				{ type = "rocks", count = 720, minD = 2700 },
				{ type = "enemies", groups = { { "brawler", 2 }, { "sniper", 1 }, { "swarmer", 4 } }, x = 0, y = -4500, r = 2500 },
				{ type = "containers", item = "cargo_container", count = { 1, 2 }, loot = "site_cache", x = 9000, y = 0, r = 800 },
				{ type = "gate", to = 3, x = 0, y = -14400, unlock = "clear" },
			} },
		{ name = "Warden's post", radius = 21000, spawn = { 0, 9000 },
			pieces = {
				{ type = "giant", x = 0, y = 0, r = 1200 },
				{ type = "enemies", groups = { { "brawler", 1 } }, x = 0, y = -7200, r = 300, tag = "warden" },
				{ type = "enemies", groups = { { "gunner", 2 } }, x = 0, y = -7800, r = 900 },
				{ type = "containers", container = "derelict_tug", count = 1, loot = "warden_key", x = 7200, y = -7200, r = 200 },
				{ type = "gate", to = 4, x = 0, y = -12600, unlock = { item = "vault_key" } },
			} },
		{ name = "The vault", radius = 15000, spawn = { 0, 7200 },
			pieces = {
				{ type = "containers", item = "cargo_container", count = { 3, 4 }, loot = "vault_hoard", x = 0, y = -2400, r = 900 },
				{ type = "gate", to = "exit", x = 0, y = -9000 },
			} },
	},
}
