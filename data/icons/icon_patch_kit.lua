-- Made in the Shipyard (F2), Icons tab. Art for Hull patch kit.
icon {
	id = "icon_patch_kit", item = "patch_kit",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ color = { 0.9, 0.55, 0.2 }, d = 0.5, h = 0.6, material = "painted", name = "case", primitive = "box", w = 1, x = 0, y = 0, z = 0, },
		{ color = { 0.95, 0.68, 0.35 }, d = 0.56, h = 0.1, material = "painted", name = "lid", primitive = "box", w = 1.06, x = -0.03, y = -0.03, z = 0.6, },
		{ color = { 0.45, 0.47, 0.52 }, d = 0.12, h = 0.06, material = "painted", name = "handle", primitive = "box", w = 0.4, x = 0.3, y = 0.18, z = 0.7, },
		{ color = { 0.45, 0.47, 0.52 }, d = 0.02, h = 0.14, material = "painted", name = "latch left", primitive = "box", w = 0.1, x = 0.12, y = -0.04, z = 0.48, },
		{ color = { 0.45, 0.47, 0.52 }, d = 0.02, h = 0.14, material = "painted", name = "latch right", primitive = "box", w = 0.1, x = 0.78, y = -0.04, z = 0.48, },
		{ color = { 0.95, 0.95, 0.92 }, d = 0.02, h = 0.1, material = "painted", name = "cross bar", primitive = "box", w = 0.36, x = 0.32, y = -0.03, z = 0.24, },
		{ color = { 0.95, 0.95, 0.92 }, d = 0.02, h = 0.34, material = "painted", name = "cross post", primitive = "box", w = 0.1, x = 0.45, y = -0.03, z = 0.12, },
	},
	boxView = { 12.132, 0.57875, -0.275975 },   -- art units per cell, centre x, y (Refit recomputes)
}
