-- Made in the Shipyard (F2), Icons tab. Art for Solid Rounds M.
icon {
	id = "icon_rounds_m", item = "rounds_m",
	paint = "Olive Drab",   -- primary paint: a preset from src/paint.lua, or { r, g, b }
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ d = 0.55, h = 0.75, material = "painted", name = "can", primitive = "box", w = 1, x = 0, y = 0, z = 0, },
		{ d = 0.61, h = 0.1, light = 0.25, material = "painted", name = "lid", primitive = "box", w = 1.06, x = -0.03, y = -0.03, z = 0.75, },
		{ d = 0.12, h = 0.04, material = "painted", name = "handle", primitive = "box", shade = 0.6, w = 0.5, x = 0.25, y = 0.215, z = 0.85, },
		{ d = 0.2, h = 0.32, material = "painted", name = "latch", primitive = "box", shade = 0.6, w = 0.05, x = 1, y = 0.175, z = 0.5, },
		{ d = 0.02, h = 0.04, material = "painted", name = "rib", primitive = "box", shade = 0.6, w = 1, x = 0, y = -0.02, z = 0.6, },
		{ d = 0.02, h = 0.3, light = 0.45, material = "painted", name = "stencil", primitive = "box", w = 0.6, x = 0.15, y = -0.03, z = 0.12, },
		{ d = 0.02, h = 0.18, material = "painted", name = "size mark", primitive = "box", shade = 0.6, w = 0.2, x = 0.6, y = -0.03, z = 0.12, },
	},
	boxView = { 11.9794, 0.586625, -0.3251 },   -- art units per cell, centre x, y (Refit recomputes)
}
