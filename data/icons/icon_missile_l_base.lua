-- Made in the Shipyard (F2), Icons tab. Art for Missile Rack L.
icon {
	id = "icon_missile_l_base", item = "missile_l_base",
	paint = "Cargo Blue",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 0.6, h = 3.501, material = "painted", name = "box", primitive = "box", w = 3, x = 0, y = 0, z = 0, },
		{ d = 0.01, h = 0.28, material = "painted", name = "lid stripe", primitive = "box", shade = 0.55, w = 3, x = 0, y = -0.01, z = 2.801, },
	},
	boxView = { 29.7605, 1.59292, -1.05727 },   -- art units per cell, centre x, y (Refit recomputes)
}
