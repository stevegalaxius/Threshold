-- Made by hand: a starting point for the Shipyard (F2), Weapons tab.
module {
	id = "shotgun_l_base", name = "Doorkicker",
	family = "weapon",
	maker = "Brute Industries",
	mass = 26,
	powerDraw = 4,
	price = 18000,
	size = "L",
	weapon = { fireRate = 0.8, gimbal = 6, chambers = { "shotgun" }, kind = "cannon", recoilPct = 60, spread = 0.5 },
	art = {
		muzzles = {
			{ 26, 0 },
		},
		parts = {
			{ name = "barrel", shape = { 0, -3.5, 28, -3.5, 28, 3.5, 0, 3.5 }, barrel = true },
			{ name = "body", shape = { -14, -5.6, 4, -5.6, 4, 5.6, -14, 5.6 }, paint = "primary" },
		},
	},
}
