-- Made by hand: a starting point for the Shipyard (F2), Weapons tab.
module {
	id = "shotgun_s_base", name = "Scattergun",
	family = "weapon",
	maker = "Halcyon Arms",
	mass = 4,
	powerDraw = 1,
	price = 3000,
	size = "S",
	weapon = { fireRate = 1.2, gimbal = 8, chambers = { "shotgun" }, kind = "cannon", recoilPct = 60, spread = 0.5 },
	art = {
		muzzles = {
			{ 10, 0 },
		},
		parts = {
			{ name = "barrel", shape = { 0, -1.5, 12, -1.5, 12, 1.5, 0, 1.5 }, barrel = true },
			{ name = "body", shape = { -6, -2.4, 4, -2.4, 4, 2.4, -6, 2.4 }, paint = "primary" },
		},
	},
}
