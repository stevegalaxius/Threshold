-- Made in the Shipyard (F2), Weapons tab.
module {
	id = "artillery_m_base", name = "Artillery M",
	family = "weapon",
	maker = "Brute Industries",
	mass = 16,
	powerDraw = 2,
	price = 9000,
	size = "M",
	weapon = { fireRate = 0.8, gimbal = 6, chambers = { "artillery" }, kind = "cannon", recoilPct = 100, spread = 1 },
	art = {
		muzzles = {
			{ 28, 0 },
		},
		parts = {
			{ name = "part 2", shape = { 0, -1, 28, -1, 28, 1, 0, 1 } },
			{ name = "part 1", shape = { -16, -2, 8, -2, 8, 2, -16, 2 } },
		},
	},
}
