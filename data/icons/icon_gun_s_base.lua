-- Made in the Shipyard (F2), Icons tab. Art for gun_s_base: its retail box, with the gun printed on the front.
icon {
	id = "icon_gun_s_base", item = "gun_s_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 2.2, d = 0.35, h = 0.7 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 0.56, w = 2.2, d = 0.01, h = 0.056, shade = 0.55, layer = "detail" },
	},
	boxView = { 34.195, 1.155, -0.248 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print receiver", shape = { -33.482, 5.571, -9.408, 5.571, -9.408, 6.625, -1.885, 6.625, -1.885, -1.275, -33.482, -1.275 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print barrel", shape = { -1.885, 3.728, 23.693, 3.728, 23.693, 1.358, -1.885, 1.358 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print muzzle", shape = { 23.693, 4.518, 28.207, 4.518, 28.207, 0.568, 23.693, 0.568 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print grip", shape = { -25.959, 5.571, -19.94, 5.571, -22.949, 7.678, -29.72, 7.678 }, color = { 0.95, 0.95, 0.9 } },
	},
}
