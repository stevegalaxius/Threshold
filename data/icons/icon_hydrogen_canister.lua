-- Made in the Shipyard (F2), Icons tab. Art for Hydrogen canister.
icon {
	id = "icon_hydrogen_canister", item = "hydrogen_canister",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ color = { 0.5, 0.5, 0.5 }, d = 0.5, h = 0.4, material = "painted", name = "base cap", primitive = "box", w = 1, x = 0, y = 0, z = 0, },
		{ color = { 1, 0.5, 0.2 }, d = 0.44, h = 0.8, material = "crystal", name = "core", primitive = "box", w = 0.86, x = 0.07, y = 0.03, z = 0.4, },
		{ color = { 0.5, 0.5, 0.5 }, d = 0.5, h = 0.36, material = "painted", name = "top cap", primitive = "box", w = 1, x = 0, y = 0, z = 1.2, },
		{ color = { 0.85, 0.85, 0.88 }, d = 0.16, h = 0.12, material = "painted", name = "valve", primitive = "box", w = 0.4, x = 0.3, y = 0.17, z = 1.56, },
		{ color = { 0.62, 0.62, 0.64 }, d = 0.01, h = 0.07, material = "painted", name = "base rim", primitive = "box", w = 1, x = 0, y = -0.01, z = 0.33, },
		{ color = { 0.62, 0.62, 0.64 }, d = 0.01, h = 0.07, material = "painted", name = "top rim", primitive = "box", w = 1, x = 0, y = -0.01, z = 1.2, },
		{ color = { 0.85, 0.85, 0.85 }, d = 0.01, h = 0.14, material = "painted", name = "label", primitive = "box", w = 0.4, x = 0.12, y = -0.01, z = 0.1, },
	},
	boxView = { 12.9238, 0.577175, -0.513975 },   -- art units per cell, centre x, y (Refit recomputes)
}
