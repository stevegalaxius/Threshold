-- Made in the Shipyard (F2), Icons tab. Art for gun_s_base: its retail box, with the gun printed on the front.
icon {
	id = "icon_gun_s_base", item = "gun_s_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3, d = 0.6, h = 1.932 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 1.545, w = 3, d = 0.01, h = 0.155, shade = 0.55, layer = "detail" },
	},
	boxView = { 24.773, 1.595, -0.626 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print receiver", shape = { -33.555, 9.71, -9.773, 9.71, -9.773, 11.815, -2.341, 11.815, -2.341, -3.975, -33.555, -3.975 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print barrel", shape = { -2.341, 6.026, 22.927, 6.026, 22.927, 1.288, -2.341, 1.288 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print muzzle", shape = { 22.927, 7.605, 27.386, 7.605, 27.386, -0.291, 22.927, -0.291 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print grip", shape = { -26.123, 9.71, -20.177, 9.71, -23.15, 13.921, -29.839, 13.921 }, color = { 0.95, 0.95, 0.9 } },
	},
}
