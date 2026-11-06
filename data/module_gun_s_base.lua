-- Made in the Shipyard (F2), Weapons tab.
module {
	id = "gun_s_base", name = "Gun S",
	family = "weapon",
	maker = "Halcyon Arms",
	mass = 4,
	powerDraw = 1,
	price = 2200,
	size = "S",
	weapon = { fireRate = 5, gimbal = 10, chambers = { "gun" }, kind = "cannon", recoilPct = 16, spread = 0.8 },
	art = {
		muzzles = {
			{ 12, 0 },
		},
		parts = {
			{ name = "part 2", shape = { 3, -1, 12, -1, 12, 1, 3, 1 }, barrel = true },
			{ name = "part 1", shape = { -5.5, -1.5, 8, -1.5, 8, 1.5, -5.5, 1.5 } },
		},
	},
}
