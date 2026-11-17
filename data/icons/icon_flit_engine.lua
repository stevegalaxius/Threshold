-- Made in the Shipyard (F2), Icons tab. Art for Flit Engine.
icon {
	id = "icon_flit_engine", item = "flit_engine",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 0.8, h = 1.3, material = "metal", name = "housing", primitive = "cylinder", ry = 90, w = 0.8, },
		{ d = 0.94, h = 0.18, material = "recess", name = "nozzle", primitive = "ring", ry = 90, w = 0.94, x = 1.3, y = -0.07, z = 0.07, },
		{ d = 0.5, h = 0.02, material = "emissive", name = "exhaust", primitive = "cylinder", ry = 90, w = 0.5, x = 1.4, y = 0.15, z = -0.15, },
		{ d = 0.48, h = 0.2, material = "recess", name = "mount", primitive = "bevel", w = 0.65, x = 0.25, y = 0.16, z = -0.95, },
	},
	boxView = { 35.9169, 0.877025, 0.134456 },   -- art units per cell, centre x, y (Refit recomputes)
}
