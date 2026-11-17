-- Made in the Shipyard (F2), Icons tab. Art for Silicon.
icon {
	id = "icon_silicon", item = "silicon",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ color = { 0.5, 0.55, 0.65 }, d = 0.6, h = 0.35, material = "painted", name = "boule", primitive = "box", w = 0.45, x = 0, y = 0.05, z = 0, },
		{ color = { 0.45, 0.5, 0.6 }, d = 0.6, h = 0.35, material = "painted", name = "boule", primitive = "box", w = 0.45, x = 0.5, y = 0.05, z = 0, },
		{ color = { 0.55, 0.6, 0.7 }, d = 0.55, h = 0.35, material = "painted", name = "boule", primitive = "box", w = 0.45, x = 0.25, y = 0.1, z = 0.35, },
		{ color = { 0.6, 0.7, 0.9 }, d = 0.02, h = 0.06, material = "emissive", name = "sheen", primitive = "box", w = 0.3, x = 0.3, y = 0.08, z = 0.5, },
	},
	boxView = { 13.1694, 0.58525, -0.30275 },   -- art units per cell, centre x, y (Refit recomputes)
}
