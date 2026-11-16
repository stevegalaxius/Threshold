-- Made in the Shipyard (F2), Icons tab. Art for gun_m_base: its retail box, with the gun printed on the front.
icon {
	id = "icon_gun_m_base", item = "gun_m_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3, d = 0.6, h = 1.072 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 0.857, w = 3, d = 0.01, h = 0.086, shade = 0.55, layer = "detail" },
	},
	boxView = { 39.824, 1.595, -0.389 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print receiver", shape = { -56.332, 9.866, -20.49, 9.866, -20.49, -2.34, -56.332, -2.34 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print drum", shape = { -50.358, 9.866, -32.437, 9.866, -32.437, 14.092, -50.358, 14.092 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print jacket", shape = { -20.49, 8.458, 3.405, 8.458, 3.405, -0.462, -20.49, -0.462 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print barrel", shape = { 3.405, 6.111, 40.442, 6.111, 40.442, 1.886, 3.405, 1.886 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print muzzle", shape = { 40.442, 7.754, 47.61, 7.754, 47.61, 0.242, 40.442, 0.242 }, color = { 0.95, 0.95, 0.9 } },
	},
}
