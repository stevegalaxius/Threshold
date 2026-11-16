-- Made in the Shipyard (F2), Icons tab. Art for missile_s_base: its retail box, with the missile printed on the front.
icon {
	id = "icon_missile_s_base", item = "missile_s_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3, d = 0.6, h = 1.932 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 1.545, w = 3, d = 0.01, h = 0.155, shade = 0.55, layer = "detail" },
	},
	boxView = { 24.773, 1.595, -0.626 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print fin", shape = { -31.117, 0.451, -19.345, 0.451, -23.269, -5.435, -29.809, -5.435 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print fin", shape = { -31.117, 6.337, -19.345, 6.337, -23.269, 12.223, -29.809, 12.223 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print nozzle", shape = { -35.041, 5.16, -31.771, 5.748, -31.771, 1.039, -35.041, 1.628 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print body", shape = { -31.771, 6.337, 14.663, 6.337, 14.663, 0.451, -31.771, 0.451 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print warhead", shape = { 14.663, 0.451, 18.725, 0.551, 22.511, 0.845, 25.762, 1.313, 28.256, 1.922, 29.824, 2.632, 30.359, 3.394, 29.824, 4.155, 28.256, 4.865, 25.762, 5.475, 22.511, 5.942, 18.725, 6.236, 14.663, 6.337 }, color = { 1, 0.38, 0.28 } },
		{ name = "print band", shape = { -8.881, 6.337, -6.919, 6.337, -6.919, 0.451, -8.881, 0.451 }, color = { 0.95, 0.8, 0.25 }, layer = "detail" },
		{ name = "print panel line", shape = { -18.037, 6.337, -17.383, 6.337, -17.383, 0.451, -18.037, 0.451 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print seeker", shape = { 29.901, 3.394, 29.652, 2.793, 29.051, 2.544, 28.45, 2.793, 28.201, 3.394, 28.45, 3.995, 29.051, 4.244, 29.652, 3.995 }, color = { 1, 0.38, 0.28 }, layer = "glow" },
	},
}
