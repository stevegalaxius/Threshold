-- Made in the Shipyard (F2), Icons tab. Art for Explosive Shells M.
icon {
	id = "icon_shell_m", item = "shell_m",
	paint = "Khaki",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 1, h = 0.7, material = "painted", name = "crate", primitive = "box", w = 1, x = 0, y = 0, z = 0, },
		{ d = 0.04, h = 0.01, material = "painted", name = "lid seam", primitive = "box", shade = 0.6, w = 0.9, x = 0.05, y = 0.33, z = 0.7, },
		{ d = 0.04, h = 0.01, material = "painted", name = "lid seam", primitive = "box", shade = 0.6, w = 0.9, x = 0.05, y = 0.66, z = 0.7, },
		{ d = 0.4, h = 0.12, light = 0.45, material = "painted", name = "rope end left", primitive = "box", w = 0.06, x = -0.06, y = 0.3, z = 0.25, },
		{ d = 0.4, h = 0.12, light = 0.45, material = "painted", name = "rope end right", primitive = "box", w = 0.06, x = 1, y = 0.3, z = 0.25, },
		{ d = 0.04, h = 0.1, material = "painted", name = "skid", primitive = "box", shade = 0.6, w = 0.8, x = 0.1, y = -0.02, z = -0.02, },
		{ d = 0.02, h = 0.1, light = 0.45, material = "painted", name = "stripe", primitive = "box", w = 0.7, x = 0.15, y = -0.03, z = 0.25, },
		{ d = 0.02, h = 0.1, material = "painted", name = "stencil", primitive = "box", shade = 0.6, w = 0.35, x = 0.15, y = -0.03, z = 0.4, },
	},
	boxView = { 11.4068, 0.6575, -0.34135 },   -- art units per cell, centre x, y (Refit recomputes)
}
