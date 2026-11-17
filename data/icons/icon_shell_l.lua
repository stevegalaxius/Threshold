-- Made in the Shipyard (F2), Icons tab. Art for Explosive Shells L.
icon {
	id = "icon_shell_l", item = "shell_l",
	paint = "Khaki",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 1, h = 0.7, material = "painted", name = "crate", primitive = "box", w = 2, x = 0, y = 0, z = 0, },
		{ d = 0.04, h = 0.01, material = "painted", name = "lid seam", primitive = "box", shade = 0.6, w = 1.9, x = 0.05, y = 0.33, z = 0.7, },
		{ d = 0.04, h = 0.01, material = "painted", name = "lid seam", primitive = "box", shade = 0.6, w = 1.9, x = 0.05, y = 0.66, z = 0.7, },
		{ d = 0.4, h = 0.12, light = 0.45, material = "painted", name = "rope end left", primitive = "box", w = 0.06, x = -0.06, y = 0.3, z = 0.25, },
		{ d = 0.4, h = 0.12, light = 0.45, material = "painted", name = "rope end right", primitive = "box", w = 0.06, x = 2, y = 0.3, z = 0.25, },
		{ d = 0.04, h = 0.1, material = "painted", name = "skid", primitive = "box", shade = 0.6, w = 1.8, x = 0.1, y = -0.02, z = -0.02, },
		{ d = 0.02, h = 0.1, light = 0.45, material = "painted", name = "stripe", primitive = "box", w = 1.7, x = 0.15, y = -0.03, z = 0.25, },
		{ d = 0.02, h = 0.1, material = "painted", name = "stencil", primitive = "box", shade = 0.6, w = 0.7, x = 0.15, y = -0.03, z = 0.4, },
	},
	boxView = { 13.3909, 1.1575, -0.34135 },   -- art units per cell, centre x, y (Refit recomputes)
}
