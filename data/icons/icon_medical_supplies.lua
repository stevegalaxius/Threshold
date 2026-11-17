-- Made in the Shipyard (F2), Icons tab. Art for Medical supplies.
icon {
	id = "icon_medical_supplies", item = "medical_supplies",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ color = { 0.92, 0.93, 0.9 }, d = 0.6, h = 0.6, material = "painted", name = "case", primitive = "box", w = 1, x = 0, y = 0, z = 0, },
		{ color = { 0.8, 0.82, 0.85 }, d = 0.64, h = 0.08, material = "painted", name = "lid", primitive = "box", w = 1.04, x = -0.02, y = -0.02, z = 0.6, },
		{ color = { 0.85, 0.2, 0.2 }, d = 0.02, h = 0.12, material = "painted", name = "cross bar", primitive = "box", w = 0.4, x = 0.3, y = -0.03, z = 0.25, },
		{ color = { 0.85, 0.2, 0.2 }, d = 0.02, h = 0.4, material = "painted", name = "cross post", primitive = "box", w = 0.12, x = 0.44, y = -0.03, z = 0.11, },
		{ color = { 0.4, 0.8, 1 }, d = 0.02, h = 0.08, material = "emissive", name = "cold light", primitive = "box", w = 0.08, x = 0.82, y = -0.03, z = 0.45, },
	},
	boxView = { 12.0812, 0.5945, -0.28465 },   -- art units per cell, centre x, y (Refit recomputes)
}
