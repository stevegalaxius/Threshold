-- Made in the Shipyard (F2). Base hull: briggs_runt
hull {
	id = "brute_runt", name = "Runt",
	armor = 170,
	bonuses = {},
	class = "small",
	drag = 0.3,
	hold = 50,
	loadout = { "missile_s_base", "missile_s_base", "flit_engine", "ember_reactor", "tug_beam", "nav_computer" },
	maker = "Brute Industries",
	mass = 95,
	mount = "gimbal",
	paints = { "Moss" },
	price = 38000,
	ramSpeed = 170,
	retroThrust = 390,
	sideThrust = 609,
	slots = {
		{ family = "bay", mount = "fixed", size = "S", x = 8, y = -8 },
		{ family = "bay", mount = "fixed", size = "S", x = 8, y = 8 },
		{ family = "engine", size = "S", x = -36, y = 0 },
		{ family = "reactor", size = "S" },
		{ family = "utility", size = "any" },
		{ family = "computer", size = "any" },
	},
	spoolTime = 0.2,
	turn = 3500,
	turnSpeed = 200,
	parts = {
		{ name = "part 5", shape = { 8, -8, 8, 8, 44, 4, 44, -4 }, paint = "secondary", lights = {
			{ color = { 1, 0.95, 0.85 }, h = 1.5, kind = "window", w = 2, x = 12, y = -4 },
			{ color = { 1, 0.95, 0.85 }, h = 1.5, kind = "window", w = 2, x = 12, y = 4 },
			{ kind = "strobe", rate = 1, x = 40, y = 0 },
		} },
		{ name = "part 2", shape = { 8, -12, 8, 12, -8, 8, -8, -8 }, paint = "primary", lights = {
			{ kind = "nav", x = 8, y = -12 },
			{ kind = "nav", x = 8, y = 12 },
		} },
		{ name = "part 3", shape = { -8, -8, -32, -8, -32, 8, -8, 8 }, paint = "primary" },
		{ name = "part 4", shape = { -36, -4, -12, -4, -12, 4, -36, 4 }, lights = {
			{ kind = "strobe", rate = 1, x = -32, y = 0 },
		} },
	},
}
