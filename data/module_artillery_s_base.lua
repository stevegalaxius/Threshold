-- Made in the Shipyard (F2), Weapons tab.
module {
	id = "artillery_s_base", name = "Pip Mortar",
	family = "weapon",
	maker = "Ferrous Collective",
	mass = 6,
	powerDraw = 1,
	price = 3400,
	size = "S",
	weapon = { fireRate = 1.2, gimbal = 6, cycle = 4, kind = "cannon", recoilPct = 100, spread = 1 },
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
