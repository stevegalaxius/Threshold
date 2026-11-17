-- Made in the Shipyard (F2), Icons tab. Art for Deuterium canister.
icon {
	id = "icon_deuterium_canister", item = "deuterium_canister",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 0.7, h = 1.1, material = "metal", name = "tank", primitive = "cylinder", w = 0.7 },
		{ d = 0.76, h = 0.1, material = "recess", name = "lower rim", primitive = "ring", w = 0.76, x = -0.03, y = -0.03, z = 0.06, },
		{ d = 0.7, h = 0.18, material = "metal", name = "neck", primitive = "taper", w = 0.7, z = 1.1 },
		{ color = { 0.9, 0.5, 0.12 }, d = 0.3, h = 0.12, material = "painted", name = "valve", primitive = "bevel", w = 0.3, x = 0.2, y = 0.2, z = 1.28, },
		{ d = 0.06, h = 0.65, material = "emissive", name = "window", primitive = "bevel", w = 0.15, x = 0.26, y = -0.04, z = 0.22, },
	},
	boxView = { 16.1725, 0.46025, -0.46375 },   -- art units per cell, centre x, y (Refit recomputes)
}
