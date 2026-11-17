-- Made in the Shipyard (F2), Icons tab. Art for Torpedo L.
icon {
	id = "icon_torp_l", item = "torp_l",
	paint = "Tanker",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 1, h = 0.75, material = "painted", name = "crate", primitive = "box", w = 4.5, x = 0.25, y = 0, z = 0, },
		{ d = 1.04, h = 0.79, material = "painted", name = "band left", primitive = "box", shade = 0.6, w = 0.15, x = 1.6, y = -0.02, z = -0.02, },
		{ d = 1.04, h = 0.79, material = "painted", name = "band right", primitive = "box", shade = 0.6, w = 0.15, x = 3.25, y = -0.02, z = -0.02, },
		{ d = 0.06, h = 0.01, light = 0.45, material = "painted", name = "lid seam", primitive = "box", w = 4.4, x = 0.3, y = 0.47, z = 0.75, },
		{ d = 1.08, h = 0.83, material = "painted", name = "end cap left", primitive = "box", shade = 0.6, w = 0.3, x = 0, y = -0.04, z = -0.04, },
		{ d = 1.08, h = 0.83, material = "painted", name = "end cap right", primitive = "box", shade = 0.6, w = 0.3, x = 4.7, y = -0.04, z = -0.04, },
		{ d = 0.02, h = 0.25, light = 0.45, material = "painted", name = "stencil", primitive = "box", w = 0.95, x = 2.05, y = -0.04, z = 0.25, },
		{ d = 0.02, h = 0.1, light = 0.45, material = "painted", name = "arrow", primitive = "box", w = 0.6, x = 3.6, y = -0.04, z = 0.32, },
	},
	boxView = { 14.7935, 2.6575, -0.36375 },   -- art units per cell, centre x, y (Refit recomputes)
}
