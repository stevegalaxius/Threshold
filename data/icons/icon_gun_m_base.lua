-- Made in the Shipyard (F2), Icons tab. Art for gun_m_base: its retail box, with the gun printed on the front.
icon {
	id = "icon_gun_m_base", item = "gun_m_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3.4, d = 0.4, h = 0.75 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 0.6, w = 3.4, d = 0.01, h = 0.06, shade = 0.55, layer = "detail" },
	},
	boxView = { 36.018, 1.763, -0.269 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print receiver", shape = { -56.152, 6.132, -19.414, 6.132, -19.414, -1.594, -56.152, -1.594 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print drum", shape = { -50.029, 6.132, -31.66, 6.132, -31.66, 8.806, -50.029, 8.806 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print jacket", shape = { -19.414, 5.241, 5.079, 5.241, 5.079, -0.405, -19.414, -0.405 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print barrel", shape = { 5.079, 3.755, 43.042, 3.755, 43.042, 1.081, 5.079, 1.081 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print muzzle", shape = { 43.042, 4.795, 50.389, 4.795, 50.389, 0.041, 43.042, 0.041 }, color = { 0.95, 0.95, 0.9 } },
	},
}
