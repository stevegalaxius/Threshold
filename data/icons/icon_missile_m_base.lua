-- Made in the Shipyard (F2), Icons tab. Art for missile_m_base: its retail box, with the missile printed on the front.
icon {
	id = "icon_missile_m_base", item = "missile_m_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3, d = 0.6, h = 1.072 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 0.857, w = 3, d = 0.01, h = 0.086, shade = 0.55, layer = "detail" },
	},
	boxView = { 39.824, 1.595, -0.389 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print fin", shape = { -53.942, 13.012, -46.774, 13.012, -27.658, 8.223, -27.658, 0.242, -46.774, -4.546, -53.942, -4.546 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print missile", shape = { -49.163, 8.223, 20.131, 8.223, 39.247, 4.233, 20.131, 0.242, -49.163, 0.242 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print band", shape = { -3.763, 8.223, 1.016, 8.223, 1.016, 0.242, -3.763, 0.242 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print warhead", shape = { 20.131, 8.223, 39.247, 4.233, 20.131, 0.242 }, color = { 1, 0.4, 0.3 } },
	},
}
