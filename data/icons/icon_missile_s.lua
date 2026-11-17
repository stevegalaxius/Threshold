-- Made in the Shipyard (F2), Icons tab. Art for Missile S.
icon {
	id = "icon_missile_s", item = "missile_s",
	paint = "Cargo Blue",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 1, h = 0.7, material = "painted", name = "crate", primitive = "box", w = 2, x = 0, y = 0, z = 0, },
		{ d = 1.04, h = 0.74, material = "painted", name = "band", primitive = "box", shade = 0.6, w = 0.2, x = 0.9, y = -0.02, z = -0.02, },
		{ d = 0.02, h = 0.266, light = 0.45, material = "painted", name = "stencil", primitive = "box", w = 0.6, x = 0.2, y = -0.04, z = 0.21, },
	},
	boxView = { 13.3909, 1.1575, -0.35 },   -- art units per cell, centre x, y (Refit recomputes)
}
