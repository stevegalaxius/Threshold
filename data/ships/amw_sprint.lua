-- Made in the Shipyard (F2). Base hull: amw_sprint
hull {
	id = "amw_sprint", name = "Sprint Sport",
	armor = 90,
	bonuses = {},
	class = "Sport",
	drag = 0.17,
	hold = 25,
	loadout = { "drone_s_base", "flit_engine", "ember_reactor", "flare_pod", "nav_computer" },
	maker = "Vantage Orbital",
	mass = 60,
	mount = "fixed",
	paints = { "Champagne" },
	price = 26000,
	ramSpeed = 150,
	retroThrust = 520,
	sideThrust = 720,
	slots = {
		{ family = "bay", mount = "fixed", size = "S", x = 16, y = 0 },
		{ family = "engine", size = "S", x = -44, y = 0 },
		{ family = "reactor", size = "S", x = -20, y = 4 },
		{ family = "utility", size = "any", x = -12, y = -4 },
		{ family = "utility", size = "any", x = -4, y = -4 },
	},
	spoolTime = 0.08,
	turn = 200,
	turnResponse = 0.15,
	turnSpeed = 250,
	parts = {
		{ name = "nose", shape = { 10, -6, 40, -2, 59, 0, 40, 2, 10, 6 }, paint = "primary", lights = {
			{ kind = "nav", x = 60, y = 0 },
		} },
		{ name = "spine", shape = { -30, -8, -10, -10, 10, -6, 10, 6, -10, 10, -30, 8 }, paint = "primary" },
		{ name = "fin", shape = { -10, -10, -30, -8, -27, -19, -18, -18 }, paint = "secondary", mirror = true, lights = {
			{ kind = "nav", size = 3, x = -27, y = -19 },
		} },
		{ name = "tail", shape = { -30, -8, -44, -4, -44, 4, -30, 8 }, paint = "secondary", lights = {
			{ kind = "strobe", rate = 1, x = -42, y = 0 },
		} },
		{ name = "part 5", shape = { 10, 0, 0, -4, -17, -5, -29, 0, -17, 5, 0, 4 }, lights = {
			{ h = 1.5, kind = "window", w = 1.5, x = 7, y = 0 },
			{ h = 1.5, kind = "window", w = 1.5, x = 0, y = -2 },
			{ h = 1.5, kind = "window", w = 1.5, x = 0, y = 2 },
		} },
	},
}
