-- Made in the Shipyard (F2). Base hull: amw_sprint_fat
hull {
	id = "amw_sprint_fat", name = "Sprint Sperrig",
	armor = 130,
	bonuses = {},
	class = "Shuttle",
	drag = 0.12,
	hold = 45,
	loadout = { "drone_s_base", false, "ember_reactor", false, false },
	maker = "Angelmaschinenwerft",
	mass = 75,
	mount = "fixed",
	paints = { "Champagne" },
	price = 26000,
	ramSpeed = 150,
	retroThrust = 520,
	sideThrust = 380,
	slots = {
		{ family = "bay", size = "S", x = 20, y = 0 },
		{ family = "engine", size = "S", x = -44, y = 0 },
		{ family = "reactor", size = "S", x = -24, y = 0 },
		{ family = "utility", size = "any", x = 36, y = 0 },
		{ family = "utility", size = "any", x = 36, y = 0 },
	},
	spoolTime = 0.08,
	turn = 200,
	turnResponse = 0.15,
	turnSpeed = 250,
	parts = {
		{ name = "nose", shape = { 10, -10, 40, -8, 59, 0, 40, 8, 10, 10 }, paint = "primary", lights = {
			{ kind = "nav", x = 60, y = 0 },
		} },
		{ name = "spine", shape = { -30, -8, -10, -10, 10, -10, 10, 10, -10, 10, -30, 8 }, paint = "primary" },
		{ name = "fin", shape = { 10, -10, -30, -8, -27, -19, -8, -18 }, paint = "secondary", mirror = true, lights = {
			{ kind = "nav", size = 3, x = -27, y = -19 },
		} },
		{ name = "tail", shape = { -30, -8, -44, -4, -44, 4, -30, 8 }, paint = "secondary", lights = {
			{ kind = "strobe", rate = 1, x = -42, y = 0 },
		} },
		{ name = "part 5", shape = { 47, 0, 34, -4, 17, -5, 14, -1, 14, 1, 17, 5, 34, 4 }, lights = {
			{ h = 1.5, kind = "window", w = 1.5, x = 41, y = 0 },
			{ h = 1.5, kind = "window", w = 1.5, x = 34, y = -2 },
			{ h = 1.5, kind = "window", w = 1.5, x = 34, y = 2 },
		} },
	},
}
