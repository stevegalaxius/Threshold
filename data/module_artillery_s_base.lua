-- Made in the Shipyard (F2), Weapons tab.
module {
	id = "artillery_s_base", name = "Artillery S",
	family = "weapon",
	maker = "Ferrous Collective",
	mass = 6,
	powerDraw = 1,
	price = 3400,
	size = "S",
	weapon = { fireRate = 1.2, gimbal = 6, chambers = { "artillery", "gun" }, kind = "cannon", recoilPct = 100, spread = 1 },
	art = {
		muzzles = {
			{ 19, 0 },
		},
		parts = {
			{ name = "part 2", shape = { 4, -0.5, 19, -0.5, 19, 0.5, 4, 0.5 } },
			{ name = "part 1", shape = { -8, -1.5, 6, -1.5, 6, 1.5, -8, 1.5 } },
		},
	},
}
