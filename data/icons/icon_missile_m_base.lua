-- Made in the Shipyard (F2), Icons tab. Art for missile_m_base: its retail box, with the missile printed on the front.
icon {
	id = "icon_missile_m_base", item = "missile_m_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3, d = 0.6, h = 1.072 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 0.857, w = 3, d = 0.01, h = 0.086, shade = 0.55, layer = "detail" },
	},
	boxView = { 39.824, 1.595, -0.389 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print fin", shape = { -31.543, 1.23, -20.178, 1.23, -23.967, -4.452, -30.28, -4.452 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print fin", shape = { -31.543, 8.175, -20.178, 8.175, -23.967, 13.857, -30.28, 13.857 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print canard", shape = { 1.287, 1.23, 6.338, 1.23, 4.444, -1.295, 1.919, -1.295 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print canard", shape = { 1.287, 8.175, 6.338, 8.175, 4.444, 10.7, 1.919, 10.7 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print nozzle", shape = { -35.331, 6.786, -32.174, 7.48, -32.174, 1.924, -35.331, 2.619 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print body", shape = { -32.174, 8.175, 12.652, 8.175, 12.652, 1.23, -32.174, 1.23 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print warhead", shape = { 12.652, 1.23, 16.573, 1.348, 20.228, 1.695, 23.366, 2.247, 25.774, 2.966, 27.288, 3.804, 27.804, 4.702, 27.288, 5.601, 25.774, 6.439, 23.366, 7.158, 20.228, 7.71, 16.573, 8.056, 12.652, 8.175 }, color = { 1, 0.38, 0.28 } },
		{ name = "print band", shape = { -10.077, 8.175, -8.183, 8.175, -8.183, 1.23, -10.077, 1.23 }, color = { 0.95, 0.8, 0.25 }, layer = "detail" },
		{ name = "print panel line", shape = { -18.916, 8.175, -18.284, 8.175, -18.284, 1.23, -18.916, 1.23 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print seeker", shape = { 27.362, 4.702, 27.122, 4.122, 26.541, 3.882, 25.961, 4.122, 25.721, 4.702, 25.961, 5.283, 26.541, 5.523, 27.122, 5.283 }, color = { 1, 0.38, 0.28 }, layer = "glow" },
	},
}
