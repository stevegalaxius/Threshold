-- Made in the Shipyard (F2), Icons tab. Art for Explosives.
icon {
	id = "icon_explosives", item = "explosives",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ color = { 0.7, 0.2, 0.15 }, d = 0.6, h = 0.7, material = "painted", name = "crate", primitive = "box", w = 1, x = 0, y = 0, z = 0, },
		{ color = { 0.8, 0.28, 0.2 }, d = 0.66, h = 0.1, material = "painted", name = "lid", primitive = "box", w = 1.06, x = -0.03, y = -0.03, z = 0.7, },
		{ color = { 0.36, 0.37, 0.4 }, d = 0.12, h = 0.04, material = "painted", name = "handle", primitive = "box", w = 0.4, x = 0.3, y = 0.24, z = 0.8, },
		{ color = { 0.95, 0.8, 0.2 }, d = 0.01, h = 0.12, material = "painted", name = "band", primitive = "box", w = 1, x = 0, y = -0.01, z = 0.3, },
	},
	boxView = { 11.8306, 0.5945, -0.319225 },   -- art units per cell, centre x, y (Refit recomputes)
}
