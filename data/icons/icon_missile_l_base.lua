-- Made in the Shipyard (F2), Icons tab. Art for missile_l_base: its retail box, with the missile printed on the front.
icon {
	id = "icon_missile_l_base", item = "missile_l_base",
	boxes = {   -- 3/4 view blocks in cells: x across, y depth, z up
		{ name = "box", x = 0, y = 0, z = 0, w = 3, d = 0.6, h = 1.37 },
		{ name = "lid stripe", x = 0, y = -0.01, z = 1.096, w = 3, d = 0.01, h = 0.11, shade = 0.55, layer = "detail" },
	},
	boxView = { 49.859, 1.595, -0.471 },   -- art units per cell, centre x, y (Refit recomputes)
	parts = {
		{ name = "print fin", shape = { -46.313, 0.069, -29.294, 0.069, -34.967, -8.44, -44.422, -8.44 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print fin", shape = { -46.313, 12.36, -29.294, 12.36, -34.967, 20.87, -44.422, 20.87 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print canard", shape = { 2.852, 0.069, 10.416, 0.069, 7.58, -3.713, 3.798, -3.713 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print canard", shape = { 2.852, 12.36, 10.416, 12.36, 7.58, 16.142, 3.798, 16.142 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print nozzle", shape = { -51.986, 9.902, -47.258, 11.131, -47.258, 1.298, -51.986, 2.527 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print body", shape = { -47.258, 12.36, 19.871, 12.36, 19.871, 0.069, -47.258, 0.069 }, color = { 0.95, 0.95, 0.9 } },
		{ name = "print warhead", shape = { 19.871, 0.069, 25.744, 0.279, 31.216, 0.892, 35.916, 1.869, 39.522, 3.142, 41.789, 4.624, 42.562, 6.215, 41.789, 7.805, 39.522, 9.288, 35.916, 10.56, 31.216, 11.537, 25.744, 12.151, 19.871, 12.36 }, color = { 1, 0.38, 0.28 } },
		{ name = "print band", shape = { -14.166, 12.36, -11.33, 12.36, -11.33, 0.069, -14.166, 0.069 }, color = { 0.95, 0.8, 0.25 }, layer = "detail" },
		{ name = "print panel line", shape = { -27.403, 12.36, -26.458, 12.36, -26.458, 0.069, -27.403, 0.069 }, color = { 0.55, 0.56, 0.6 }, layer = "detail" },
		{ name = "print stage band", shape = { -23.621, 12.36, -20.785, 12.36, -20.785, 0.069, -23.621, 0.069 }, color = { 0.95, 0.8, 0.25 }, layer = "detail" },
		{ name = "print seeker", shape = { 41.9, 6.215, 41.54, 5.346, 40.671, 4.986, 39.802, 5.346, 39.442, 6.215, 39.802, 7.084, 40.671, 7.444, 41.54, 7.084 }, color = { 1, 0.38, 0.28 }, layer = "glow" },
	},
}
