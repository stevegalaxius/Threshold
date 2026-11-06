-- Made in the Shipyard (F2), Weapons tab.
module {
	id = "artillery_l_base", name = "Artillery L",
	family = "weapon",
	maker = "Ferrous Collective",
	mass = 34,
	powerDraw = 3,
	price = 24000,
	size = "L",
	weapon = { fireRate = 0.5, gimbal = 5, chambers = { "artillery", "gun" }, kind = "cannon", recoilPct = 100, spread = 0.5 },
	art = {
		muzzles = {
			{ 52, 0 },
		},
		parts = {
			{ name = "part 2", shape = { 0, -1.5, 52, -1.5, 52, 1.5, 0, 1.5 }, barrel = true },
			{ name = "part 1", shape = { -28, -4, 12, -4, 12, 4, -28, 4 } },
		},
	},
}
