-- Made in the Shipyard (F2), Icons tab. Art for Food crate.
icon {
	id = "icon_food_crate", item = "food_crate",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ color = { 0.65, 0.5, 0.32 }, d = 0.8, h = 0.6, material = "painted", name = "crate", primitive = "box", w = 1, x = 0, y = 0, z = 0, },
		{ color = { 0.45, 0.33, 0.2 }, d = 0.02, h = 0.04, material = "painted", name = "slat", primitive = "box", w = 1.02, x = -0.01, y = -0.02, z = 0.18, },
		{ color = { 0.45, 0.33, 0.2 }, d = 0.02, h = 0.04, material = "painted", name = "slat", primitive = "box", w = 1.02, x = -0.01, y = -0.02, z = 0.4, },
		{ color = { 0.9, 0.85, 0.6 }, d = 0.02, h = 0.14, material = "painted", name = "label", primitive = "box", w = 0.4, x = 0.3, y = -0.03, z = 0.22, },
		{ color = { 0.72, 0.56, 0.36 }, d = 0.8, h = 0.04, material = "painted", name = "lid", primitive = "box", w = 1, x = 0, y = 0, z = 0.6, },
	},
	boxView = { 11.8269, 0.61785, -0.302 },   -- art units per cell, centre x, y (Refit recomputes)
}
