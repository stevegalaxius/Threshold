-- Made in the Shipyard (F2), Icons tab. Art for Missile M.
icon {
	id = "icon_missile_m", item = "missile_m",
	paint = "Cargo Blue",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 1, h = 0.8, material = "painted", name = "crate", primitive = "box", w = 3, x = 0, y = 0, z = 0, },
		{ d = 1.04, h = 0.84, material = "painted", name = "band left", primitive = "box", w = 0.2, x = 0.6, y = -0.02, z = -0.02, },
		{ d = 1.04, h = 0.84, material = "painted", name = "band right", primitive = "box", w = 0.2, x = 2.2, y = -0.02, z = -0.02, },
		{ d = 0.02, h = 0.3, material = "painted", name = "stencil", primitive = "box", shade = 0.6, w = 0.8, x = 1.1, y = -0.04, z = 0.25, },
	},
	boxView = { 14.178, 1.6575, -0.3775 },   -- art units per cell, centre x, y (Refit recomputes)
}
