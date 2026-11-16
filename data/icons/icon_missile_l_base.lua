-- Made in the Shipyard (F2), Icons tab. Art for missile_l_base: its retail box, with the missile printed on the front.
icon {
	id = "icon_missile_l_base", item = "missile_l_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3.6, d = 0.5, h = 1.05 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 0.84, w = 3.6, d = 0.01, h = 0.084, shade = 0.55, layer = "detail" },
	},
	boxView = { 42.315, 1.879, -0.368 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print fin", shape = { -67.313, 12.961, -58.173, 12.961, -33.799, 7.975, -33.799, -0.333, -58.173, -5.318, -67.313, -5.318 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print missile", shape = { -61.22, 7.975, 27.135, 7.975, 51.508, 3.821, 27.135, -0.333, -61.22, -0.333 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print band", shape = { -3.332, 7.975, 2.761, 7.975, 2.761, -0.333, -3.332, -0.333 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print warhead", shape = { 27.135, 7.975, 51.508, 3.821, 27.135, -0.333 }, color = { 1, 0.4, 0.3 } },
	},
}
