-- Made in the Shipyard (F2), Icons tab. Art for gun_l_base: its retail box, with the gun printed on the front.
icon {
	id = "icon_gun_l_base", item = "gun_l_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3.6, d = 0.5, h = 1.05 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 0.84, w = 3.6, d = 0.01, h = 0.084, shade = 0.55, layer = "detail" },
	},
	boxView = { 42.315, 1.879, -0.368 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print receiver", shape = { -71.883, 10.175, -27.706, 10.175, -18.566, 8.22, -18.566, -3.51, -71.883, -3.51 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print upper barrel", shape = { -18.566, 1.866, 53.032, 1.866, 53.032, -1.066, -18.566, -1.066 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print lower barrel", shape = { -18.566, 7.242, 53.032, 7.242, 53.032, 4.31, -18.566, 4.31 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print muzzle", shape = { 53.032, 8.22, 62.172, 8.22, 62.172, -2.044, 53.032, -2.044 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print mount", shape = { -59.696, 10.175, -33.799, 10.175, -38.369, 14.085, -55.126, 14.085 }, color = { 0.95, 0.95, 0.9 } },
	},
}
