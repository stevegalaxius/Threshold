-- Made in the Shipyard (F2), Icons tab. Art for missile_m_base: its retail box, with the missile printed on the front.
icon {
	id = "icon_missile_m_base", item = "missile_m_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3.4, d = 0.4, h = 0.75 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 0.6, w = 3.4, d = 0.01, h = 0.06, shade = 0.55, layer = "detail" },
	},
	boxView = { 36.018, 1.763, -0.269 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print fin", shape = { -53.703, 8.123, -46.355, 8.123, -26.761, 5.092, -26.761, 0.041, -46.355, -2.99, -53.703, -2.99 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print missile", shape = { -48.805, 5.092, 22.223, 5.092, 41.817, 2.566, 22.223, 0.041, -48.805, 0.041 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print band", shape = { -2.269, 5.092, 2.629, 5.092, 2.629, 0.041, -2.269, 0.041 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print warhead", shape = { 22.223, 5.092, 41.817, 2.566, 22.223, 0.041 }, color = { 1, 0.4, 0.3 } },
	},
}
