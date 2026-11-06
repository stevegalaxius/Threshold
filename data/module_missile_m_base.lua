-- Made in the Shipyard (F2), Weapons tab.
module {
	id = "missile_m_base", name = "Missile Rack M",
	family = "bay",
	maker = "Nova Syndicate",
	mass = 8,
	price = 11000,
	size = "M",
	weapon = { capacity = 6, fireRate = 2.5, kind = "missile", recoil = 800 },
	art = {
		parts = {
			{ name = "part 1", shape = { -6, 6, -6, -6, 8, -6, 12, -3, 12, 3, 8, 6 }, paint = "primary" },
			{ name = "part 2", shape = { 5, -2, 12, -2, 12, 2, 5, 2 }, barrel = true },
		},
	},
}
