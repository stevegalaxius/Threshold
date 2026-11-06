-- Made in the Shipyard (F2), Weapons tab.
module {
	id = "missile_l_base", name = "Missile Rack L",
	family = "bay",
	maker = "Ferrous Collective",
	mass = 18,
	price = 26000,
	size = "L",
	weapon = { fireRate = 1.5, kind = "missile", recoil = 1600 },
	art = {
		parts = {
			{ name = "part 1", shape = { -9, -9, -9, 9, 10, 9, 16, 4, 16, -4, 10, -9 }, paint = "primary" },
			{ name = "part 2", shape = { 5, -4, 16, -4, 16, 4, 5, 4 }, barrel = true },
		},
	},
}
