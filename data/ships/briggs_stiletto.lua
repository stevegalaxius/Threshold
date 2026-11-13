-- Made in the Shipyard (F2). Base hull: briggs_stiletto
hull {
	id = "briggs_stiletto", name = "Stiletto",
	armor = 180,
	bonuses = {},
	class = "light",
	drag = 0.14,
	hold = 33,
	loadout = { "gun_s_base", "missile_s_base", "flit_engine", "ember_reactor", "hold_pod_s", "nav_computer" },
	maker = "Briggs MFG",
	mass = 73,
	mount = "fixed",
	paints = { "Primer", "Forest", "Signal", "Cobalt", "Hazard" },
	price = 11500,
	retroThrust = 340,
	sideThrust = 350,
	slots = {
		{ family = "hardpoint", size = "S", x = 32, y = 0 },
		{ family = "bay", size = "S", x = 22, y = 0 },
		{ family = "engine", size = "S", x = -27, y = 0 },
		{ family = "reactor", size = "S", x = -13, y = 0 },
		{ family = "utility", size = "any", x = 3, y = -3 },
		{ family = "utility", size = "any", x = 3, y = 3 },
	},
	turn = 450,
	turnResponse = 0.07,
	parts = {
		{ name = "part 2", shape = { -28, -4, -16, -4, -16, 4, -28, 4 }, lights = {
			{ kind = "strobe", rate = 1, x = -26, y = 0 },
		} },
		{ name = "part 4", shape = { 0, -8, 40, 0, 0, 8 }, paint = "primary" },
		{ name = "part 3", shape = { -16, -8, -16, 8, 0, 12, 0, -12 }, paint = "primary", cargo = true, core = true, lights = {
			{ kind = "nav", x = 0, y = -12 },
			{ kind = "nav", x = 0, y = 12 },
		} },
		{ name = "part 5", shape = { 6, -3, 31, 0, 6, 3 }, paint = "secondary", lights = {
			{ h = 1.5, kind = "window", w = 2, x = 8, y = -1 },
			{ h = 1.5, kind = "window", w = 2, x = 8, y = 1 },
		} },
	},
}
