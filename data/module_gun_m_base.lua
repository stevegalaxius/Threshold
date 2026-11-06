-- Made in the Shipyard (F2), Weapons tab.
module {
	id = "gun_m_base", name = "RK-7 Autocannon",
	family = "weapon",
	maker = "Brute Industries",
	mass = 10,
	powerDraw = 2,
	price = 6500,
	size = "M",
	weapon = { fireRate = 4, gimbal = 10, chambers = { "gun" }, kind = "cannon", recoilPct = 50.5, spread = 1 },
	art = {
		muzzles = {
			{ 22, 0 },
		},
		parts = {
			{ name = "part 1", shape = { -2.5, -1.5, 22, -1.5, 22, 1.5, -2.5, 1.5 }, barrel = true },
			{ name = "part 2", shape = { -9.5, -2.5, 16, -2.5, 16, 2.5, -9.5, 2.5 }, paint = "primary" },
		},
	},
}
