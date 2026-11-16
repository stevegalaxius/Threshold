-- Made in the Shipyard (F2), Icons tab. Art for missile_s_base: its retail box, with the missile printed on the front.
icon {
	id = "icon_missile_s_base", item = "missile_s_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 2.2, d = 0.35, h = 0.7 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 0.56, w = 2.2, d = 0.01, h = 0.056, shade = 0.55, layer = "detail" },
	},
	boxView = { 34.195, 1.155, -0.248 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print fin", shape = { -33.482, 7.072, -28.968, 7.072, -16.931, 4.386, -16.931, -0.09, -28.968, -2.775, -33.482, -2.775 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print missile", shape = { -30.472, 4.386, 13.161, 4.386, 25.198, 2.148, 13.161, -0.09, -30.472, -0.09 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print band", shape = { -1.885, 4.386, 1.124, 4.386, 1.124, -0.09, -1.885, -0.09 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print warhead", shape = { 13.161, 4.386, 25.198, 2.148, 13.161, -0.09 }, color = { 1, 0.4, 0.3 } },
	},
}
