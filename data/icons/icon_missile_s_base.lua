-- Made in the Shipyard (F2), Icons tab. Art for missile_s_base: its retail box, with the missile printed on the front.
icon {
	id = "icon_missile_s_base", item = "missile_s_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3, d = 0.6, h = 1.932 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 1.545, w = 3, d = 0.01, h = 0.155, shade = 0.55, layer = "detail" },
	},
	boxView = { 24.773, 1.595, -0.626 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print fin", shape = { -33.555, 12.71, -29.095, 12.71, -17.205, 7.341, -17.205, -1.607, -29.095, -6.976, -33.555, -6.976 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print missile", shape = { -30.582, 7.341, 12.523, 7.341, 24.413, 2.867, 12.523, -1.607, -30.582, -1.607 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print band", shape = { -2.341, 7.341, 0.632, 7.341, 0.632, -1.607, -2.341, -1.607 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print warhead", shape = { 12.523, 7.341, 24.413, 2.867, 12.523, -1.607 }, color = { 1, 0.4, 0.3 } },
	},
}
