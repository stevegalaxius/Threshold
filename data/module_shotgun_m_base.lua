-- Made by hand: a starting point for the Shipyard (F2), Weapons tab.
module {
	id = "shotgun_m_base", name = "Breacher",
	family = "weapon",
	maker = "Brute Industries",
	mass = 11,
	powerDraw = 2,
	price = 8000,
	size = "M",
	weapon = { fireRate = 1.0, gimbal = 7, chambers = { "shotgun" }, kind = "cannon", recoilPct = 60, spread = 0.5 },
	art = {
		muzzles = {
			{ 18, 0 },
		},
		parts = {
			{ name = "barrel", shape = { 0, -2.5, 20, -2.5, 20, 2.5, 0, 2.5 }, barrel = true },
			{ name = "body", shape = { -10, -4, 4, -4, 4, 4, -10, 4 }, paint = "primary" },
		},
	},
}
