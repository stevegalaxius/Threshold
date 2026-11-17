-- Made in the Shipyard (F2), Icons tab. Art for Ember Reactor.
icon {
	id = "icon_ember_reactor", item = "ember_reactor",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 1.4, h = 0.22, material = "recess", name = "base", primitive = "cylinder", w = 1.4 },
		{ d = 0.46, h = 0.9, material = "emissive", name = "core", primitive = "cylinder", w = 0.46, x = 0.47, y = 0.47, z = 0.22, },
		{ d = 1.4, h = 0.12, material = "metal", name = "lower ring", primitive = "ring", w = 1.4, z = 0.22, },
		{ d = 1.4, h = 0.12, material = "metal", name = "upper ring", primitive = "ring", w = 1.4, z = 1.1, },
		{ d = 0.18, h = 0.8, material = "recess", name = "front support", primitive = "bevel", w = 0.18, x = 0.6, y = 0.02, z = 0.3, },
		{ d = 0.18, h = 0.8, material = "recess", name = "rear support", primitive = "bevel", w = 0.18, x = 0.6, y = 1.2, z = 0.3, },
	},
	boxView = { 32.1435, 0.9205, -0.556 },   -- art units per cell, centre x, y (Refit recomputes)
}
