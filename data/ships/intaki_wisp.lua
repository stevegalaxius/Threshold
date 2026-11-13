-- Made in the Shipyard (F2). Base hull: intaki_wisp
hull {
	id = "intaki_wisp", name = "Wisp",
	armor = 120,
	bonuses = {},
	class = "light",
	drag = 0.14,
	hold = 24,
	loadout = { "beam_s_base", "gun_s_base", "flit_engine", "ember_reactor", "hold_pod_s", "nav_computer" },
	maker = "Intaki",
	mass = 58,
	mount = "fixed",
	paints = { "Khaki", "Sage", "Old Gold", "Champagne" },
	price = 14000,
	retroThrust = 340,
	sideThrust = 410,
	slots = {
		{ family = "hardpoint", size = "S", x = 24, y = 4 },
		{ family = "hardpoint", size = "S", trigger = "secondary" },
		{ family = "engine", size = "S", x = -26, y = 0 },
		{ family = "reactor", size = "S" },
		{ family = "utility", size = "any" },
		{ family = "utility", size = "any" },
	},
	turn = 500,
	parts = {
		{ name = "part 2", shape = { -28, -4, -16, -8, -16, 8, -28, 4 }, lights = {
			{ kind = "strobe", rate = 1, x = -20, y = 0 },
		} },
		{ name = "part 3", shape = { -16, -4, -24, -16, -8, -20, 12, -12, 44, -4 }, paint = "primary", mirror = true, lights = {
			{ kind = "nav", size = 2, x = -8, y = -20 },
		} },
		{ name = "part 4", shape = { -16, -4, 24, -4, 24, 4, -16, 4 }, paint = "secondary" },
	},
}
