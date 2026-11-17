-- Made in the Shipyard (F2), Icons tab. Art for Missile L.
icon {
	id = "icon_missile_l", item = "missile_l",
	paint = "Cargo Blue",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 1, h = 0.9, material = "painted", name = "crate", primitive = "box", w = 3, x = 0, y = 0, z = 0, },
		{ d = 1.04, h = 0.94, material = "painted", name = "band", primitive = "box", shade = 0.6, w = 0.2, x = 0.9, y = -0.02, z = -0.02, },
		{ d = 1.04, h = 0.94, material = "painted", name = "band", primitive = "box", shade = 0.6, w = 0.2, x = 1.9, y = -0.02, z = -0.02, },
		{ d = 1.08, h = 0.98, material = "painted", name = "end cap left", primitive = "box", shade = 0.6, w = 0.2, x = -0.04, y = -0.04, z = -0.04, },
		{ d = 1.08, h = 0.98, material = "painted", name = "end cap right", primitive = "box", shade = 0.6, w = 0.2, x = 2.84, y = -0.04, z = -0.04, },
		{ d = 0.02, h = 0.342, light = 0.45, material = "painted", name = "stencil", primitive = "box", w = 0.8, x = 1.1, y = -0.04, z = 0.27, },
	},
	boxView = { 13.7419, 1.6575, -0.405 },   -- art units per cell, centre x, y (Refit recomputes)
}
