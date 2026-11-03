-- Made in the Shipyard (F2). Base hull: halcyon_wisp
hull {
	id = "intaki_wisp", name = "Wisp",
	armor = 120,
	bonuses = {},
	cargo = { missile_s = 4, rounds_s = 400 },
	class = "light",
	drag = 0.14,
	hold = 24,
	loadout = { "px2_autogun", "px2_autogun", "sparrow_rack", "flit_engine", "ember_reactor", "hold_pod_s", "nav_computer" },
	maker = "Halcyon Arms",
	mass = 58,
	mount = "fixed",
	price = 14000,
	ramSpeed = 100,
	retroThrust = 340,
	sideThrust = 410,
	slots = {
		{ family = "primary", size = "S", x = 12, y = -9 },
		{ family = "primary", size = "S", x = 12, y = 9 },
		{ family = "auxiliary", size = "S", x = 24, y = 0 },
		{ family = "engine", size = "S", x = -26, y = 0 },
		{ family = "reactor", size = "S" },
		{ family = "utility", size = "any" },
		{ family = "computer", size = "any" },
	},
	turn = 500,
	parts = {
		{ name = "part 2", shape = { -28, -4, -16, -4, -16, 4, -28, 4 }, lights = {
			{ kind = "strobe", rate = 1, x = -20, y = 0 },
		} },
		{ name = "part 3", shape = { -20, -4, -28, -16, -12, -20, 8, -12, 40, -4 }, mirror = true, lights = {
			{ kind = "nav", size = 2, x = -12, y = -20 },
		} },
	},
}
