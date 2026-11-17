-- Made in the Shipyard (F2), Icons tab. Art for Gun L.
icon {
	id = "icon_gun_l_base", item = "gun_l_base",
	paint = "Gunmetal",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 0.6, h = 1.37, material = "painted", name = "box", primitive = "box", w = 3, x = 0, y = 0, z = 0, },
		{ d = 0.01, h = 0.11, material = "painted", name = "lid stripe", primitive = "box", shade = 0.55, w = 3, x = 0, y = -0.01, z = 1.096, },
	},
	boxView = { 49.8097, 1.59292, -0.47125 },   -- art units per cell, centre x, y (Refit recomputes)
}
