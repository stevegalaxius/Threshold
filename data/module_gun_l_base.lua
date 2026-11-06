-- Made in the Shipyard (F2), Weapons tab.
module {
	id = "gun_l_base", name = "Gun L",
	family = "weapon",
	maker = "Brute Industries",
	mass = 24,
	powerDraw = 4,
	price = 15000,
	size = "L",
	weapon = {
		barrelGap = 10,
		barrels = 2,
		caliber = "M",
		fireRate = 8,
		gimbal = 10,
		chambers = { "gun", "shotgun" }, kind = "cannon",
		recoilPct = 17.5,
		spread = 1,
	},
	art = {
		muzzles = {
			{ 22.5, -4.5 },
			{ 22.5, 4.5 },
		},
		parts = {
			{ name = "part 2", shape = { 0.5, -6, 22.5, -6, 22.5, -3, 0.5, -3 }, mirror = true },
			{ name = "part 1", shape = { -11, -7, 16, -7, 16, -2, -11, -2 }, mirror = true },
		},
	},
}
